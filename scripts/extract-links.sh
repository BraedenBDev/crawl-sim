#!/usr/bin/env bash
set -eu

# extract-links.sh — Extract and classify internal/external links from HTML
# Usage: extract-links.sh <base-url> [file] | extract-links.sh <base-url> < html
# Output: JSON to stdout with counts and sample lists

BASE_URL="${1:?Usage: extract-links.sh <base-url> [file]}"
shift || true

# Read HTML from file or stdin
if [ $# -ge 1 ] && [ -f "$1" ]; then
  HTML=$(cat "$1")
else
  HTML=$(cat)
fi

# Extract base host from URL (e.g. https://example.com/path -> example.com)
BASE_HOST=$(printf '%s' "$BASE_URL" | sed -E 's#^https?://##' | sed -E 's#/.*$##' | sed -E 's#^www\.##')
BASE_ORIGIN=$(printf '%s' "$BASE_URL" | sed -E 's#(^https?://[^/]+).*#\1#')

# Flatten HTML
HTML_FLAT=$(printf '%s' "$HTML" | tr '\n' ' ')

# Extract all href values from <a> tags
TMPDIR="${TMPDIR:-/tmp}"
HREFS_FILE=$(mktemp "$TMPDIR/crawlsim-hrefs.XXXXXX")
INTERNAL_FILE=$(mktemp "$TMPDIR/crawlsim-internal.XXXXXX")
EXTERNAL_FILE=$(mktemp "$TMPDIR/crawlsim-external.XXXXXX")
trap 'rm -f "$HREFS_FILE" "$INTERNAL_FILE" "$EXTERNAL_FILE"' EXIT

printf '%s' "$HTML_FLAT" \
  | grep -oiE '<a[[:space:]][^>]*href=["'\''"][^"'\''"]*["'\''"]' \
  | sed -E 's/.*href=["'\''"]([^"'\''"]*)["'\''"].*/\1/i' \
  > "$HREFS_FILE" || true

# Classify links
while IFS= read -r href; do
  [ -z "$href" ] && continue
  # Skip non-http (mailto, tel, javascript, anchors)
  case "$href" in
    mailto:*|tel:*|javascript:*|"#"*) continue ;;
  esac

  if printf '%s' "$href" | grep -qE '^https?://'; then
    # Absolute URL — check host
    HREF_HOST=$(printf '%s' "$href" | sed -E 's#^https?://##' | sed -E 's#/.*$##' | sed -E 's#^www\.##')
    if [ "$HREF_HOST" = "$BASE_HOST" ]; then
      echo "$href" >> "$INTERNAL_FILE"
    else
      echo "$href" >> "$EXTERNAL_FILE"
    fi
  else
    # Relative or root-relative — internal
    if printf '%s' "$href" | grep -qE '^/'; then
      echo "${BASE_ORIGIN}${href}" >> "$INTERNAL_FILE"
    else
      echo "${BASE_ORIGIN}/${href}" >> "$INTERNAL_FILE"
    fi
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
