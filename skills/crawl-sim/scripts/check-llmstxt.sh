#!/usr/bin/env bash
set -eu

# check-llmstxt.sh — Check for llms.txt and llms-full.txt presence + structure
# Usage: check-llmstxt.sh <url>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

URL="${1:?Usage: check-llmstxt.sh <url>}"
printf '[check-llmstxt] %s\n' "$URL" >&2
CANONICAL_URL=$(canonical_url "$URL")
ORIGIN=$(origin_from_url "$CANONICAL_URL")

TMPDIR="${TMPDIR:-/tmp}"
LLMS_FILE=$(mktemp "$TMPDIR/crawlsim-llms.XXXXXX")
LLMS_FULL_FILE=$(mktemp "$TMPDIR/crawlsim-llms-full.XXXXXX")
trap 'rm -f "$LLMS_FILE" "$LLMS_FULL_FILE"' EXIT

analyze_file() {
  local file="$1"
  local status_code="$2"

  local exists=false
  local line_count=0
  local has_title=false
  local title=""
  local has_description=false
  local url_count=0

  # Treat non-200 or HTML responses as "not present"
  if [ "$status_code" = "200" ] && [ -s "$file" ]; then
    # Heuristic: if file starts with <!doctype or <html, site serves HTML fallback — not a real llms.txt
    local first_bytes
    first_bytes=$(head -c 100 "$file" | tr '[:upper:]' '[:lower:]')
    case "$first_bytes" in
      *"<!doctype"*|*"<html"*) ;;
      *)
        exists=true
        line_count=$(wc -l < "$file" | tr -d ' ')
        # Title: first line starting with "# "
        if head -1 "$file" | grep -qE '^#[[:space:]]+'; then
          has_title=true
          title=$(head -1 "$file" | sed -E 's/^#[[:space:]]+//' | tr -d '\r')
        fi
        # Description: block quote or paragraph after title
        if grep -qE '^>[[:space:]]+' "$file" || sed -n '2,5p' "$file" | grep -qE '^[A-Za-z]'; then
          has_description=true
        fi
        # Count URLs (markdown links)
        url_count=$(grep -oE '\[[^]]*\]\(https?://[^)]+\)' "$file" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
        ;;
    esac
  fi

  # Output values via globals (bash function limitation workaround)
  EXISTS="$exists"
  LINE_COUNT="$line_count"
  HAS_TITLE="$has_title"
  TITLE="$title"
  HAS_DESCRIPTION="$has_description"
  URL_COUNT="$url_count"
}

LLMS_STATUS=$(fetch_to_file "${ORIGIN}/llms.txt" "$LLMS_FILE")
analyze_file "$LLMS_FILE" "$LLMS_STATUS"
LLMS_EXISTS=$EXISTS
LLMS_LINES=$LINE_COUNT
LLMS_HAS_TITLE=$HAS_TITLE
LLMS_TITLE=$TITLE
LLMS_HAS_DESC=$HAS_DESCRIPTION
LLMS_URLS=$URL_COUNT

LLMS_FULL_STATUS=$(fetch_to_file "${ORIGIN}/llms-full.txt" "$LLMS_FULL_FILE")
analyze_file "$LLMS_FULL_FILE" "$LLMS_FULL_STATUS"
LLMS_FULL_EXISTS=$EXISTS
LLMS_FULL_LINES=$LINE_COUNT
LLMS_FULL_HAS_TITLE=$HAS_TITLE
LLMS_FULL_HAS_DESC=$HAS_DESCRIPTION
LLMS_FULL_URLS=$URL_COUNT

TOP_EXISTS=false
[ "$LLMS_EXISTS" = "true" ] || [ "$LLMS_FULL_EXISTS" = "true" ] && TOP_EXISTS=true

jq -n \
  --arg url "$URL" \
  --argjson topExists "$TOP_EXISTS" \
  --arg llmsUrl "${ORIGIN}/llms.txt" \
  --arg llmsFullUrl "${ORIGIN}/llms-full.txt" \
  --argjson llmsExists "$LLMS_EXISTS" \
  --argjson llmsLines "$LLMS_LINES" \
  --argjson llmsHasTitle "$LLMS_HAS_TITLE" \
  --arg llmsTitle "$LLMS_TITLE" \
  --argjson llmsHasDesc "$LLMS_HAS_DESC" \
  --argjson llmsUrls "$LLMS_URLS" \
  --argjson llmsFullExists "$LLMS_FULL_EXISTS" \
  --argjson llmsFullLines "$LLMS_FULL_LINES" \
  --argjson llmsFullHasTitle "$LLMS_FULL_HAS_TITLE" \
  --argjson llmsFullHasDesc "$LLMS_FULL_HAS_DESC" \
  --argjson llmsFullUrls "$LLMS_FULL_URLS" \
  '{
    url: $url,
    exists: $topExists,
    llmsTxt: {
      url: $llmsUrl,
      exists: $llmsExists,
      lineCount: $llmsLines,
      hasTitle: $llmsHasTitle,
      title: (if $llmsTitle == "" then null else $llmsTitle end),
      hasDescription: $llmsHasDesc,
      urlCount: $llmsUrls
    },
    llmsFullTxt: {
      url: $llmsFullUrl,
      exists: $llmsFullExists,
      lineCount: $llmsFullLines,
      hasTitle: $llmsFullHasTitle,
      hasDescription: $llmsFullHasDesc,
      urlCount: $llmsFullUrls
    }
  }'
