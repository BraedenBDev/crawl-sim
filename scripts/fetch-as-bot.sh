#!/usr/bin/env bash
set -euo pipefail

# fetch-as-bot.sh — Fetch a URL as a specific bot User-Agent
# Usage: fetch-as-bot.sh <url> <profile.json>
# Output: JSON to stdout

URL="${1:?Usage: fetch-as-bot.sh <url> <profile.json>}"
PROFILE="${2:?Usage: fetch-as-bot.sh <url> <profile.json>}"

# Read profile fields
BOT_ID=$(jq -r '.id' "$PROFILE")
BOT_NAME=$(jq -r '.name' "$PROFILE")
UA=$(jq -r '.userAgent' "$PROFILE")

# Temp files for headers and body
TMPDIR="${TMPDIR:-/tmp}"
HEADERS_FILE=$(mktemp "$TMPDIR/crawlsim-headers.XXXXXX")
BODY_FILE=$(mktemp "$TMPDIR/crawlsim-body.XXXXXX")
trap 'rm -f "$HEADERS_FILE" "$BODY_FILE"' EXIT

# Curl with timing, headers, and body capture
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

# Parse response headers into JSON object
HEADERS_JSON=$(awk '
BEGIN { printf "{" }
/^[A-Za-z]/ {
  gsub(/\r/, "")
  split($0, parts, ": ")
  key = parts[1]
  val = ""
  for (i=2; i<=length(parts); i++) {
    if (i > 2) val = val ": "
    val = val parts[i]
  }
  gsub(/"/, "\\\"", val)
  if (n++ > 0) printf ","
  printf "\"%s\":\"%s\"", key, val
}
END { printf "}" }
' "$HEADERS_FILE")

# Count words in body (strip HTML tags)
WORD_COUNT=0
if [ -s "$BODY_FILE" ]; then
  WORD_COUNT=$(sed 's/<[^>]*>//g' "$BODY_FILE" | tr -s '[:space:]' '\n' | grep -c '[a-zA-Z0-9]' || true)
fi

# Base64 encode body for safe JSON embedding
BODY_B64=""
if [ -s "$BODY_FILE" ]; then
  BODY_B64=$(base64 < "$BODY_FILE")
fi

# Build output JSON
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
