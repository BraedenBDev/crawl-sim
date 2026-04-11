#!/usr/bin/env bash
set -eu

# check-robots.sh — Fetch robots.txt and parse rules for a given UA token
# Usage: check-robots.sh <url> <ua-token>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

URL="${1:?Usage: check-robots.sh <url> <ua-token>}"
UA_TOKEN="${2:?Usage: check-robots.sh <url> <ua-token>}"

ORIGIN=$(origin_from_url "$URL")
URL_PATH=$(path_from_url "$URL")
ROBOTS_URL="${ORIGIN}/robots.txt"

TMPDIR="${TMPDIR:-/tmp}"
ROBOTS_FILE=$(mktemp "$TMPDIR/crawlsim-robots.XXXXXX")
RAW_FILE=$(mktemp "$TMPDIR/crawlsim-robots-raw.XXXXXX")
DISALLOWED_PATHS_FILE=$(mktemp "$TMPDIR/crawlsim-disallowed.XXXXXX")
ALLOW_PATHS_FILE=$(mktemp "$TMPDIR/crawlsim-allow.XXXXXX")
SITEMAPS_FILE=$(mktemp "$TMPDIR/crawlsim-sitemaps.XXXXXX")
trap 'rm -f "$ROBOTS_FILE" "$RAW_FILE" "$DISALLOWED_PATHS_FILE" "$ALLOW_PATHS_FILE" "$SITEMAPS_FILE"' EXIT

HTTP_STATUS=$(fetch_to_file "$ROBOTS_URL" "$ROBOTS_FILE")

EXISTS=false
if [ "$HTTP_STATUS" = "200" ] && [ -s "$ROBOTS_FILE" ]; then
  EXISTS=true
fi

ALLOWED=true
CRAWL_DELAY="null"

if [ "$EXISTS" = "true" ]; then
  # Extract sitemap directives
  grep -iE '^[[:space:]]*sitemap[[:space:]]*:' "$ROBOTS_FILE" 2>/dev/null \
    | sed -E 's/^[[:space:]]*[sS][iI][tT][eE][mM][aA][pP][[:space:]]*:[[:space:]]*//' \
    | tr -d '\r' \
    | sed -E 's/[[:space:]]+$//' \
    > "$SITEMAPS_FILE" || true

  # Parse User-agent blocks using portable awk
  # State machine: track current UA group(s), emit rules tagged EXACT_ or WILD_
  awk -v ua="$UA_TOKEN" '
    function lower(s) { return tolower(s) }
    function trim(s) {
      sub(/^[ \t\r]+/, "", s)
      sub(/[ \t\r]+$/, "", s)
      return s
    }
    function parse_directive(line,    colon, key, val) {
      colon = index(line, ":")
      if (colon == 0) return ""
      key = lower(trim(substr(line, 1, colon - 1)))
      val = trim(substr(line, colon + 1))
      return key "\t" val
    }
    function emit(kind, value,    i, u) {
      for (i = 1; i <= n_uas; i++) {
        u = uas[i]
        if (lower(u) == lower(ua)) {
          print "EXACT_" kind "\t" value
        }
        if (u == "*") {
          print "WILD_" kind "\t" value
        }
      }
    }
    BEGIN { n_uas = 0; prev_was_rule = 0 }
    {
      line = $0
      # Strip comments
      hash = index(line, "#")
      if (hash > 0) line = substr(line, 1, hash - 1)
      line = trim(line)
      if (line == "") next

      parsed = parse_directive(line)
      if (parsed == "") next

      tab = index(parsed, "\t")
      key = substr(parsed, 1, tab - 1)
      val = substr(parsed, tab + 1)

      if (key == "user-agent") {
        if (prev_was_rule) {
          n_uas = 0
          prev_was_rule = 0
        }
        n_uas++
        uas[n_uas] = val
        next
      }
      if (key == "disallow") { prev_was_rule = 1; emit("DISALLOW", val); next }
      if (key == "allow")    { prev_was_rule = 1; emit("ALLOW", val); next }
      if (key == "crawl-delay") { prev_was_rule = 1; emit("DELAY", val); next }
    }
  ' "$ROBOTS_FILE" > "$RAW_FILE"

  # Prefer exact UA rules if present, else wildcard
  PREFIX="WILD_"
  if grep -q '^EXACT_' "$RAW_FILE"; then
    PREFIX="EXACT_"
  fi

  grep "^${PREFIX}DISALLOW" "$RAW_FILE" 2>/dev/null \
    | cut -f2- \
    | grep -v '^$' \
    > "$DISALLOWED_PATHS_FILE" || true

  grep "^${PREFIX}ALLOW" "$RAW_FILE" 2>/dev/null \
    | cut -f2- \
    > "$ALLOW_PATHS_FILE" || true

  DELAY_LINE=$(grep "^${PREFIX}DELAY" "$RAW_FILE" 2>/dev/null | head -1 | cut -f2- || true)
  if [ -n "$DELAY_LINE" ]; then
    if printf '%s' "$DELAY_LINE" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
      CRAWL_DELAY="$DELAY_LINE"
    fi
  fi

  # Longest-match path check (allow overrides disallow at equal or longer length)
  BEST_MATCH_LEN=-1
  BEST_MATCH_KIND="allow"

  match_pattern() {
    # Convert robots.txt glob (* and $) to a regex prefix check
    local pat="$1"
    local path="$2"
    # Escape regex special chars except * and $
    local esc
    esc=$(printf '%s' "$pat" | sed 's/[].[\^$()+?{|]/\\&/g' | sed 's/\*/.*/g')
    printf '%s' "$path" | grep -qE "^${esc}"
  }

  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    if match_pattern "$pat" "$URL_PATH"; then
      PAT_LEN=${#pat}
      if [ "$PAT_LEN" -gt "$BEST_MATCH_LEN" ]; then
        BEST_MATCH_LEN=$PAT_LEN
        BEST_MATCH_KIND="disallow"
      fi
    fi
  done < "$DISALLOWED_PATHS_FILE"

  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    if match_pattern "$pat" "$URL_PATH"; then
      PAT_LEN=${#pat}
      if [ "$PAT_LEN" -ge "$BEST_MATCH_LEN" ]; then
        BEST_MATCH_LEN=$PAT_LEN
        BEST_MATCH_KIND="allow"
      fi
    fi
  done < "$ALLOW_PATHS_FILE"

  if [ "$BEST_MATCH_KIND" = "disallow" ]; then
    ALLOWED=false
  fi
fi

# Build JSON arrays
DISALLOWED_JSON="[]"
if [ -s "$DISALLOWED_PATHS_FILE" ]; then
  DISALLOWED_JSON=$(head -100 "$DISALLOWED_PATHS_FILE" | jq -R . | jq -s .)
fi

SITEMAPS_JSON="[]"
if [ -s "$SITEMAPS_FILE" ]; then
  SITEMAPS_JSON=$(jq -R . < "$SITEMAPS_FILE" | jq -s .)
fi

jq -n \
  --arg url "$URL" \
  --arg uaToken "$UA_TOKEN" \
  --arg robotsUrl "$ROBOTS_URL" \
  --argjson exists "$EXISTS" \
  --argjson allowed "$ALLOWED" \
  --argjson crawlDelay "$CRAWL_DELAY" \
  --argjson disallowedPaths "$DISALLOWED_JSON" \
  --argjson sitemaps "$SITEMAPS_JSON" \
  '{
    url: $url,
    uaToken: $uaToken,
    robotsUrl: $robotsUrl,
    exists: $exists,
    allowed: $allowed,
    crawlDelay: $crawlDelay,
    disallowedPaths: $disallowedPaths,
    sitemaps: $sitemaps
  }'
