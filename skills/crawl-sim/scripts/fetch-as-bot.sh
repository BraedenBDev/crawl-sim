#!/usr/bin/env bash
set -euo pipefail

# fetch-as-bot.sh — Fetch a URL as a specific bot User-Agent
# Usage: fetch-as-bot.sh <url> <profile.json>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

URL="${1:?Usage: fetch-as-bot.sh <url> <profile.json>}"
PROFILE="${2:?Usage: fetch-as-bot.sh <url> <profile.json>}"

BOT_ID=$(jq -r '.id' "$PROFILE")
BOT_NAME=$(jq -r '.name' "$PROFILE")
UA=$(jq -r '.userAgent' "$PROFILE")
RENDERS_JS=$(jq -r '.rendersJavaScript' "$PROFILE")
PURPOSE=$(jq -r '.purpose // "unknown"' "$PROFILE")
ROBOTS_ENFORCE=$(jq -r '.robotsTxtEnforceability // "unknown"' "$PROFILE")

TMPDIR="${TMPDIR:-/tmp}"
HEADERS_FILE=$(mktemp "$TMPDIR/crawlsim-headers.XXXXXX")
BODY_FILE=$(mktemp "$TMPDIR/crawlsim-body.XXXXXX")
CURL_STDERR_FILE=$(mktemp "$TMPDIR/crawlsim-stderr.XXXXXX")
trap 'rm -f "$HEADERS_FILE" "$BODY_FILE" "$CURL_STDERR_FILE"' EXIT

printf '[%s] fetching %s\n' "$BOT_ID" "$URL" >&2

set +e
TIMING=$(curl -sS -L \
  -H "User-Agent: $UA" \
  -D "$HEADERS_FILE" \
  -o "$BODY_FILE" \
  -w '%{time_total}\t%{time_starttransfer}\t%{time_connect}\t%{http_code}\t%{size_download}\t%{num_redirects}\t%{url_effective}' \
  --max-time 30 \
  "$URL" 2>"$CURL_STDERR_FILE")
CURL_EXIT=$?
set -e

CURL_ERR=""
if [ -s "$CURL_STDERR_FILE" ]; then
  CURL_ERR=$(cat "$CURL_STDERR_FILE")
fi

if [ "$CURL_EXIT" -ne 0 ]; then
  printf '[%s] FAILED: curl exit %d — %s\n' "$BOT_ID" "$CURL_EXIT" "$CURL_ERR" >&2
  jq -n \
    --arg url "$URL" \
    --arg botId "$BOT_ID" \
    --arg botName "$BOT_NAME" \
    --arg ua "$UA" \
    --arg rendersJs "$RENDERS_JS" \
    --arg purpose "$PURPOSE" \
    --arg robotsEnforce "$ROBOTS_ENFORCE" \
    --arg error "$CURL_ERR" \
    --argjson exitCode "$CURL_EXIT" \
    '{
      url: $url,
      bot: {
        id: $botId,
        name: $botName,
        userAgent: $ua,
        rendersJavaScript: (if $rendersJs == "true" then true elif $rendersJs == "false" then false else $rendersJs end),
        purpose: $purpose,
        robotsTxtEnforceability: $robotsEnforce
      },
      fetchFailed: true,
      error: $error,
      curlExitCode: $exitCode,
      status: 0,
      timing: { total: 0, ttfb: 0 },
      size: 0,
      wordCount: 0,
      headers: {},
      bodyBase64: ""
    }'
  exit 0
fi

# TIMING is tab-separated: total ttfb connect statusCode sizeDownload redirectCount finalUrl
IFS=$'\t' read -r TOTAL_TIME TTFB _CONNECT STATUS SIZE REDIRECT_COUNT FINAL_URL <<< "$TIMING"

# Parse response headers into a JSON object using jq for safe escaping.
# curl -L writes multiple blocks on redirect; jq keeps the last definition
# of each header since `add` overwrites left-to-right.
HEADERS_JSON=$(tr -d '\r' < "$HEADERS_FILE" \
  | grep -E '^[A-Za-z][A-Za-z0-9-]*:[[:space:]]' \
  | jq -Rs '
      split("\n")
      | map(select(length > 0))
      | map(capture("^(?<k>[^:]+):[[:space:]]*(?<v>.*)$"))
      | map({(.k): .v})
      | add // {}
    ')

# Parse redirect chain from headers dump.
# curl -D writes multiple HTTP response blocks on redirect — each starts with HTTP/.
REDIRECT_CHAIN="[]"
if [ "$REDIRECT_COUNT" -gt 0 ]; then
  REDIRECT_CHAIN=$(tr -d '\r' < "$HEADERS_FILE" | awk '
    /^HTTP\// { status=$2; url="" }
    /^[Ll]ocation:/ { url=$2 }
    /^$/ && status && url { printf "%s %s\n", status, url; status=""; url="" }
  ' | jq -Rs '
    split("\n") | map(select(length > 0)) |
    to_entries | map({
      hop: .key,
      status: (.value | split(" ")[0] | tonumber),
      location: (.value | split(" ")[1:] | join(" "))
    })
  ')
fi

WORD_COUNT=$(count_words "$BODY_FILE")
[ -z "$WORD_COUNT" ] && WORD_COUNT=0

BODY_B64=""
if [ -s "$BODY_FILE" ]; then
  BODY_B64=$(base64 < "$BODY_FILE")
fi

printf '[%s] ok: status=%s size=%s words=%s time=%ss\n' "$BOT_ID" "$STATUS" "$SIZE" "$WORD_COUNT" "$TOTAL_TIME" >&2

jq -n \
  --arg url "$URL" \
  --arg botId "$BOT_ID" \
  --arg botName "$BOT_NAME" \
  --arg ua "$UA" \
  --arg rendersJs "$RENDERS_JS" \
  --arg purpose "$PURPOSE" \
  --arg robotsEnforce "$ROBOTS_ENFORCE" \
  --argjson status "$STATUS" \
  --argjson totalTime "$TOTAL_TIME" \
  --argjson ttfb "$TTFB" \
  --argjson size "$SIZE" \
  --argjson wordCount "$WORD_COUNT" \
  --argjson headers "$HEADERS_JSON" \
  --argjson redirectCount "$REDIRECT_COUNT" \
  --arg finalUrl "$FINAL_URL" \
  --argjson redirectChain "$REDIRECT_CHAIN" \
  --arg bodyBase64 "$BODY_B64" \
  '{
    url: $url,
    bot: {
      id: $botId,
      name: $botName,
      userAgent: $ua,
      rendersJavaScript: (if $rendersJs == "true" then true elif $rendersJs == "false" then false else $rendersJs end),
      purpose: $purpose,
      robotsTxtEnforceability: $robotsEnforce
    },
    status: $status,
    timing: { total: $totalTime, ttfb: $ttfb },
    size: $size,
    wordCount: $wordCount,
    redirectCount: $redirectCount,
    finalUrl: $finalUrl,
    redirectChain: $redirectChain,
    headers: $headers,
    bodyBase64: $bodyBase64
  }'
