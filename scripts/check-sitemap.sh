#!/usr/bin/env bash
set -eu

# check-sitemap.sh — Fetch sitemap.xml, check URL inclusion and structure
# Usage: check-sitemap.sh <url>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

URL="${1:?Usage: check-sitemap.sh <url>}"
printf '[check-sitemap] %s\n' "$URL" >&2
ORIGIN=$(origin_from_url "$URL")
SITEMAP_URL="${ORIGIN}/sitemap.xml"

TMPDIR="${TMPDIR:-/tmp}"
SITEMAP_FILE=$(mktemp "$TMPDIR/crawlsim-sitemap.XXXXXX")
trap 'rm -f "$SITEMAP_FILE"' EXIT

HTTP_STATUS=$(fetch_to_file "$SITEMAP_URL" "$SITEMAP_FILE")

EXISTS=false
URL_COUNT=0
CONTAINS_TARGET=false
HAS_LASTMOD=false
IS_INDEX=false
CHILD_SITEMAP_COUNT=0

if [ "$HTTP_STATUS" = "200" ] && [ -s "$SITEMAP_FILE" ]; then
  # Check if content looks like XML (not HTML fallback)
  FIRST_BYTES=$(head -c 200 "$SITEMAP_FILE" | tr '[:upper:]' '[:lower:]')
  case "$FIRST_BYTES" in
    *"<!doctype html"*|*"<html"*) ;;
    *)
      EXISTS=true

      # Is this a sitemap index?
      if grep -qi '<sitemapindex' "$SITEMAP_FILE"; then
        IS_INDEX=true
        CHILD_SITEMAP_COUNT=$(grep -oE '<sitemap>' "$SITEMAP_FILE" | wc -l | tr -d ' ')
      fi

      # Count <loc> tags (URLs, or child sitemaps in an index)
      URL_COUNT=$(grep -oE '<loc>' "$SITEMAP_FILE" | wc -l | tr -d ' ')

      # Check if target URL appears anywhere in the sitemap
      # Match both with and without trailing slash
      URL_NO_TRAILING=$(printf '%s' "$URL" | sed -E 's#/$##')
      if grep -qF "$URL_NO_TRAILING<" "$SITEMAP_FILE" || grep -qF "${URL_NO_TRAILING}/<" "$SITEMAP_FILE"; then
        CONTAINS_TARGET=true
      fi

      # Has lastmod dates?
      if grep -qi '<lastmod>' "$SITEMAP_FILE"; then
        HAS_LASTMOD=true
      fi
      ;;
  esac
fi

jq -n \
  --arg url "$URL" \
  --arg sitemapUrl "$SITEMAP_URL" \
  --argjson exists "$EXISTS" \
  --argjson isIndex "$IS_INDEX" \
  --argjson urlCount "$URL_COUNT" \
  --argjson childSitemapCount "$CHILD_SITEMAP_COUNT" \
  --argjson containsTarget "$CONTAINS_TARGET" \
  --argjson hasLastmod "$HAS_LASTMOD" \
  '{
    url: $url,
    sitemapUrl: $sitemapUrl,
    exists: $exists,
    isIndex: $isIndex,
    urlCount: $urlCount,
    childSitemapCount: $childSitemapCount,
    containsTarget: $containsTarget,
    hasLastmod: $hasLastmod
  }'
