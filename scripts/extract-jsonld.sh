#!/usr/bin/env bash
set -eu

# extract-jsonld.sh — Extract JSON-LD structured data from HTML
# Usage: extract-jsonld.sh [file] | extract-jsonld.sh < html
# Output: JSON to stdout with count, types, and flags

# Read HTML from file or stdin
if [ $# -ge 1 ] && [ -f "$1" ]; then
  HTML=$(cat "$1")
else
  HTML=$(cat)
fi

# Extract JSON-LD blocks into a temp file (one block per line, flattened)
# Match <script type="application/ld+json">...</script> across lines
TMPDIR="${TMPDIR:-/tmp}"
BLOCKS_FILE=$(mktemp "$TMPDIR/crawlsim-jsonld.XXXXXX")
trap 'rm -f "$BLOCKS_FILE"' EXIT

# Use awk to extract script blocks across lines
printf '%s' "$HTML" | awk '
BEGIN { in_block = 0; block = "" }
{
  line = $0
  while (length(line) > 0) {
    if (in_block == 0) {
      # Look for opening script tag (case-insensitive)
      idx = match(tolower(line), /<script[^>]*type=["'\''"]application\/ld\+json["'\''"][^>]*>/)
      if (idx == 0) break
      # Skip past the opening tag
      end_of_open = idx + RLENGTH - 1
      line = substr(line, end_of_open + 1)
      in_block = 1
      block = ""
    } else {
      # Look for closing tag
      idx = match(tolower(line), /<\/script>/)
      if (idx == 0) {
        block = block line " "
        break
      }
      block = block substr(line, 1, idx - 1)
      print block
      line = substr(line, idx + RLENGTH)
      in_block = 0
    }
  }
}
' > "$BLOCKS_FILE"

# Count blocks
BLOCK_COUNT=$(wc -l < "$BLOCKS_FILE" | tr -d ' ')
# Handle empty file (wc returns 0 for empty)
if [ ! -s "$BLOCKS_FILE" ]; then
  BLOCK_COUNT=0
fi

# Parse each block and collect @type values
TYPES_FILE=$(mktemp "$TMPDIR/crawlsim-types.XXXXXX")
VALID_FILE=$(mktemp "$TMPDIR/crawlsim-valid.XXXXXX")
trap 'rm -f "$BLOCKS_FILE" "$TYPES_FILE" "$VALID_FILE"' EXIT

VALID_COUNT=0
INVALID_COUNT=0

if [ "$BLOCK_COUNT" -gt 0 ]; then
  while IFS= read -r block; do
    [ -z "$block" ] && continue
    # Try to parse as JSON
    if printf '%s' "$block" | jq -e . >/dev/null 2>&1; then
      VALID_COUNT=$((VALID_COUNT + 1))
      # Extract @type values (may be single string, array, or nested under @graph)
      printf '%s' "$block" | jq -r '
        def collect_types:
          if type == "object" then
            (if has("@type") then (.["@type"] | if type == "array" then .[] else . end) else empty end),
            (if has("@graph") then (.["@graph"][] | collect_types) else empty end)
          elif type == "array" then .[] | collect_types
          else empty end;
        collect_types
      ' 2>/dev/null >> "$TYPES_FILE" || true
    else
      INVALID_COUNT=$((INVALID_COUNT + 1))
    fi
  done < "$BLOCKS_FILE"
fi

# Deduplicate and sort types
TYPES_JSON="[]"
if [ -s "$TYPES_FILE" ]; then
  TYPES_JSON=$(sort -u "$TYPES_FILE" | jq -R . | jq -s .)
fi

# Boolean flags for common types
has_type() {
  printf '%s' "$TYPES_JSON" | jq -e --arg t "$1" 'any(. == $t)' >/dev/null 2>&1 && echo true || echo false
}

HAS_ORG=$(has_type "Organization")
HAS_BREADCRUMB=$(has_type "BreadcrumbList")
HAS_WEBSITE=$(has_type "WebSite")
HAS_ARTICLE=$(has_type "Article")
HAS_FAQ=$(has_type "FAQPage")
HAS_PRODUCT=$(has_type "Product")
HAS_PROFESSIONAL_SERVICE=$(has_type "ProfessionalService")

jq -n \
  --argjson count "$BLOCK_COUNT" \
  --argjson valid "$VALID_COUNT" \
  --argjson invalid "$INVALID_COUNT" \
  --argjson types "$TYPES_JSON" \
  --argjson hasOrg "$HAS_ORG" \
  --argjson hasBreadcrumb "$HAS_BREADCRUMB" \
  --argjson hasWebsite "$HAS_WEBSITE" \
  --argjson hasArticle "$HAS_ARTICLE" \
  --argjson hasFaq "$HAS_FAQ" \
  --argjson hasProduct "$HAS_PRODUCT" \
  --argjson hasProfService "$HAS_PROFESSIONAL_SERVICE" \
  '{
    blockCount: $count,
    validCount: $valid,
    invalidCount: $invalid,
    types: $types,
    flags: {
      hasOrganization: $hasOrg,
      hasBreadcrumbList: $hasBreadcrumb,
      hasWebSite: $hasWebsite,
      hasArticle: $hasArticle,
      hasFAQPage: $hasFaq,
      hasProduct: $hasProduct,
      hasProfessionalService: $hasProfService
    }
  }'
