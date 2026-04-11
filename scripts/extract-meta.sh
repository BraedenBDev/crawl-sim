#!/usr/bin/env bash
set -eu
# Note: no pipefail because grep -oiE legitimately returns 1 on no-match

# extract-meta.sh — Extract title, meta, OG, headings, images from HTML
# Usage: extract-meta.sh [file] | extract-meta.sh < html
# Output: JSON to stdout

# Read HTML from file arg or stdin
if [ $# -ge 1 ] && [ -f "$1" ]; then
  HTML=$(cat "$1")
else
  HTML=$(cat)
fi

# Flatten whitespace for regex matching
HTML_FLAT=$(printf '%s' "$HTML" | tr '\n' ' ' | tr -s ' ')

# Helper: extract attribute value from an attribute-value pattern
# $1 = the attribute pattern to match (e.g. 'content', 'href')
# $2 = the tag regex
grep_tag() {
  printf '%s' "$HTML_FLAT" | grep -oiE "$1" | head -1 || true
}

extract_content() {
  local tag
  tag=$(grep_tag "$1")
  [ -z "$tag" ] && return 0
  printf '%s' "$tag" | sed -E 's/.*content=["'\''"]([^"'\''"]*)["'\''"].*/\1/i'
}

extract_href() {
  local tag
  tag=$(grep_tag "$1")
  [ -z "$tag" ] && return 0
  printf '%s' "$tag" | sed -E 's/.*href=["'\''"]([^"'\''"]*)["'\''"].*/\1/i'
}

count_pattern() {
  printf '%s' "$HTML_FLAT" | grep -ociE "$1" || true
}

# Title
TITLE_TAG=$(printf '%s' "$HTML_FLAT" | grep -oiE '<title[^>]*>[^<]*</title>' | head -1 || true)
TITLE=""
if [ -n "$TITLE_TAG" ]; then
  TITLE=$(printf '%s' "$TITLE_TAG" | sed -E 's/<title[^>]*>([^<]*)<\/title>/\1/i')
fi

# Meta description
DESCRIPTION=$(extract_content '<meta[^>]*name=["'\''"]description["'\''"][^>]*>')

# Canonical
CANONICAL=$(extract_href '<link[^>]*rel=["'\''"]canonical["'\''"][^>]*>')

# OG tags
OG_TITLE=$(extract_content '<meta[^>]*property=["'\''"]og:title["'\''"][^>]*>')
OG_DESCRIPTION=$(extract_content '<meta[^>]*property=["'\''"]og:description["'\''"][^>]*>')
OG_IMAGE=$(extract_content '<meta[^>]*property=["'\''"]og:image["'\''"][^>]*>')
OG_TYPE=$(extract_content '<meta[^>]*property=["'\''"]og:type["'\''"][^>]*>')

# Twitter card
TWITTER_CARD=$(extract_content '<meta[^>]*name=["'\''"]twitter:card["'\''"][^>]*>')

# Heading counts
H1_COUNT=$(count_pattern '<h1[^>]*>')
H2_COUNT=$(count_pattern '<h2[^>]*>')
H3_COUNT=$(count_pattern '<h3[^>]*>')

# First H1 text
H1_TAG=$(printf '%s' "$HTML_FLAT" | grep -oiE '<h1[^>]*>[^<]*</h1>' | head -1 || true)
H1_TEXT=""
if [ -n "$H1_TAG" ]; then
  H1_TEXT=$(printf '%s' "$H1_TAG" | sed -E 's/<h1[^>]*>([^<]*)<\/h1>/\1/i')
fi

# Image counts
IMG_TOTAL=$(count_pattern '<img[^>]*>')
IMG_WITH_ALT=$(count_pattern '<img[^>]*alt=["'\''"][^"'\''"]*["'\''"][^>]*>')

# Lang attribute on <html>
LANG_TAG=$(printf '%s' "$HTML_FLAT" | grep -oiE '<html[^>]*lang=["'\''"][^"'\''"]*["'\''"]' | head -1 || true)
LANG_VAL=""
if [ -n "$LANG_TAG" ]; then
  LANG_VAL=$(printf '%s' "$LANG_TAG" | sed -E 's/.*lang=["'\''"]([^"'\''"]*)["'\''"].*/\1/i')
fi

# Viewport meta
VIEWPORT=$(extract_content '<meta[^>]*name=["'\''"]viewport["'\''"][^>]*>')

# Build output JSON
jq -n \
  --arg title "$TITLE" \
  --arg description "$DESCRIPTION" \
  --arg canonical "$CANONICAL" \
  --arg ogTitle "$OG_TITLE" \
  --arg ogDescription "$OG_DESCRIPTION" \
  --arg ogImage "$OG_IMAGE" \
  --arg ogType "$OG_TYPE" \
  --arg twitterCard "$TWITTER_CARD" \
  --arg h1Text "$H1_TEXT" \
  --arg lang "$LANG_VAL" \
  --arg viewport "$VIEWPORT" \
  --argjson h1Count "$H1_COUNT" \
  --argjson h2Count "$H2_COUNT" \
  --argjson h3Count "$H3_COUNT" \
  --argjson imgTotal "$IMG_TOTAL" \
  --argjson imgWithAlt "$IMG_WITH_ALT" \
  '{
    title: (if $title == "" then null else $title end),
    description: (if $description == "" then null else $description end),
    canonical: (if $canonical == "" then null else $canonical end),
    lang: (if $lang == "" then null else $lang end),
    viewport: (if $viewport == "" then null else $viewport end),
    og: {
      title: (if $ogTitle == "" then null else $ogTitle end),
      description: (if $ogDescription == "" then null else $ogDescription end),
      image: (if $ogImage == "" then null else $ogImage end),
      type: (if $ogType == "" then null else $ogType end)
    },
    twitter: {
      card: (if $twitterCard == "" then null else $twitterCard end)
    },
    headings: {
      h1: { count: $h1Count, firstText: (if $h1Text == "" then null else $h1Text end) },
      h2: { count: $h2Count },
      h3: { count: $h3Count }
    },
    images: {
      total: $imgTotal,
      withAlt: $imgWithAlt,
      missingAlt: ($imgTotal - $imgWithAlt)
    }
  }'
