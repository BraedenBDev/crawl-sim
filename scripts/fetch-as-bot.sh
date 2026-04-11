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

TMPDIR="${TMPDIR:-/tmp}"
HEADERS_FILE=$(mktemp "$TMPDIR/crawlsim-headers.XXXXXX")
BODY_FILE=$(mktemp "$TMPDIR/crawlsim-body.XXXXXX")
trap 'rm -f "$HEADERS_FILE" "$BODY_FILE"' EXIT

TIMING=$(curl -sS -L \
  -H "User-Agent: $UA" \
  -D "$HEADERS_FILE" \
  -o "$BODY_FILE" \
  -w '{"total":%{time_total},"ttfb":%{time_starttransfer},"connect":%{time_connect},"statusCode":%{http_code},"sizeDownload":%{size_download}}' \
  --max-time 30 \
  "$URL" 2>/dev/null || echo '{"total":0,"ttfb":0,"connect":0,"statusCode":0,"sizeDownload":0}')

STATUS=$(echo "$TIMING" | jq -r '.statusCode')
TOTAL_TIME=$(echo "$TIMING" | jq -r '.total')
TTFB=$(echo "$TIMING" | jq -r '.ttfb')
SIZE=$(echo "$TIMING" | jq -r '.sizeDownload')

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

WORD_COUNT=$(count_words "$BODY_FILE")
[ -z "$WORD_COUNT" ] && WORD_COUNT=0

BODY_B64=""
if [ -s "$BODY_FILE" ]; then
  BODY_B64=$(base64 < "$BODY_FILE")
fi

jq -n \
  --arg url "$URL" \
  --arg botId "$BOT_ID" \
  --arg botName "$BOT_NAME" \
  --arg ua "$UA" \
  --argjson status "$STATUS" \
  --argjson totalTime "$TOTAL_TIME" \
  --argjson ttfb "$TTFB" \
  --argjson size "$SIZE" \
  --argjson wordCount "$WORD_COUNT" \
  --argjson headers "$HEADERS_JSON" \
  --arg bodyBase64 "$BODY_B64" \
  '{
    url: $url,
    bot: { id: $botId, name: $botName, userAgent: $ua },
    status: $status,
    timing: { total: $totalTime, ttfb: $ttfb },
    size: $size,
    wordCount: $wordCount,
    headers: $headers,
    bodyBase64: $bodyBase64
  }'
