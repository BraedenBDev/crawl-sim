#!/usr/bin/env bash
set -eu

# extract-links.sh — Extract and classify internal/external links from HTML
# Usage: extract-links.sh <base-url> [file] | extract-links.sh <base-url> < html

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

BASE_URL="${1:?Usage: extract-links.sh <base-url> [file]}"
shift || true

if [ $# -ge 1 ] && [ -f "$1" ]; then
  HTML=$(cat "$1")
else
  HTML=$(cat)
fi

BASE_HOST=$(host_from_url "$BASE_URL")
BASE_ORIGIN=$(origin_from_url "$BASE_URL")
BASE_DIR=$(dir_from_url "$BASE_URL")

HTML_FLAT=$(printf '%s' "$HTML" | tr '\n' ' ')

TMPDIR="${TMPDIR:-/tmp}"
HREFS_FILE=$(mktemp "$TMPDIR/crawlsim-hrefs.XXXXXX")
INTERNAL_FILE=$(mktemp "$TMPDIR/crawlsim-internal.XXXXXX")
EXTERNAL_FILE=$(mktemp "$TMPDIR/crawlsim-external.XXXXXX")
trap 'rm -f "$HREFS_FILE" "$INTERNAL_FILE" "$EXTERNAL_FILE"' EXIT

# Extract hrefs from <a> tags — handle double and single quoting separately.
{
  printf '%s' "$HTML_FLAT" \
    | grep -oiE '<a[[:space:]][^>]*href="[^"]*"' \
    | sed -E 's/.*href="([^"]*)".*/\1/' || true
  printf '%s' "$HTML_FLAT" \
    | grep -oiE "<a[[:space:]][^>]*href='[^']*'" \
    | sed -E "s/.*href='([^']*)'.*/\\1/" || true
} > "$HREFS_FILE"

while IFS= read -r href; do
  [ -z "$href" ] && continue
  case "$href" in
    mailto:*|tel:*|javascript:*|"#"*) continue ;;
  esac

  if printf '%s' "$href" | grep -qE '^https?://'; then
    HREF_HOST=$(host_from_url "$href")
    if [ "$HREF_HOST" = "$BASE_HOST" ]; then
      echo "$href" >> "$INTERNAL_FILE"
    else
      echo "$href" >> "$EXTERNAL_FILE"
    fi
  elif printf '%s' "$href" | grep -qE '^//'; then
    # Protocol-relative — inherit base scheme
    scheme=$(printf '%s' "$BASE_URL" | sed -E 's#^(https?):.*#\1#')
    abs="${scheme}:${href}"
    HREF_HOST=$(host_from_url "$abs")
    if [ "$HREF_HOST" = "$BASE_HOST" ]; then
      echo "$abs" >> "$INTERNAL_FILE"
    else
      echo "$abs" >> "$EXTERNAL_FILE"
    fi
  elif printf '%s' "$href" | grep -qE '^/'; then
    # Root-relative — attach to origin
    echo "${BASE_ORIGIN}${href}" >> "$INTERNAL_FILE"
  else
    # Document-relative — attach to base directory
    echo "${BASE_DIR}${href}" >> "$INTERNAL_FILE"
  fi
done < "$HREFS_FILE"

INTERNAL_COUNT=0
EXTERNAL_COUNT=0
[ -s "$INTERNAL_FILE" ] && INTERNAL_COUNT=$(wc -l < "$INTERNAL_FILE" | tr -d ' ')
[ -s "$EXTERNAL_FILE" ] && EXTERNAL_COUNT=$(wc -l < "$EXTERNAL_FILE" | tr -d ' ')

INTERNAL_SAMPLE="[]"
EXTERNAL_SAMPLE="[]"
if [ -s "$INTERNAL_FILE" ]; then
  INTERNAL_SAMPLE=$(head -50 "$INTERNAL_FILE" | jq -R . | jq -s .)
fi
if [ -s "$EXTERNAL_FILE" ]; then
  EXTERNAL_SAMPLE=$(head -50 "$EXTERNAL_FILE" | jq -R . | jq -s .)
fi

jq -n \
  --argjson internalCount "$INTERNAL_COUNT" \
  --argjson externalCount "$EXTERNAL_COUNT" \
  --argjson internalSample "$INTERNAL_SAMPLE" \
  --argjson externalSample "$EXTERNAL_SAMPLE" \
  '{
    counts: {
      internal: $internalCount,
      external: $externalCount,
      total: ($internalCount + $externalCount)
    },
    internal: $internalSample,
    external: $externalSample
  }'
