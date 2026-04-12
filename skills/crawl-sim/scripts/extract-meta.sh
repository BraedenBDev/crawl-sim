#!/usr/bin/env bash
set -eu

# extract-meta.sh — Extract title, meta, OG, headings, images from HTML
# Usage: extract-meta.sh [file] | extract-meta.sh < html

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

if [ $# -ge 1 ] && [ -f "$1" ]; then
  HTML=$(cat "$1")
  printf '[extract-meta] %s\n' "$1" >&2
else
  HTML=$(cat)
  printf '[extract-meta] (stdin)\n' >&2
fi

HTML_FLAT=$(printf '%s' "$HTML" | tr '\n' ' ' | tr -s ' ')

# Match a tag by regex, then pull a named attribute value that respects the
# actual opening quote char. Works for both "…" and '…' quoting.
# $1 = grep regex to find the tag
# $2 = attribute name (e.g. "content", "href")
get_attr() {
  local tag_regex="$1"
  local attr="$2"
  local tag
  tag=$(printf '%s' "$HTML_FLAT" | grep -oiE "$tag_regex" | head -1 || true)
  [ -z "$tag" ] && return 0
  # Try double-quoted first, then single-quoted
  local val
  val=$(printf '%s' "$tag" | sed -n -E "s/.*${attr}=\"([^\"]*)\".*/\\1/p" | head -1)
  if [ -z "$val" ]; then
    val=$(printf '%s' "$tag" | sed -n -E "s/.*${attr}='([^']*)'.*/\\1/p" | head -1)
  fi
  printf '%s' "$val"
}

count_pattern() {
  local n
  n=$(printf '%s' "$HTML_FLAT" | grep -oiE "$1" | wc -l | tr -d ' ' || true)
  printf '%s' "${n:-0}"
}

TITLE_TAG=$(printf '%s' "$HTML_FLAT" | grep -oiE '<title[^>]*>[^<]*</title>' | head -1 || true)
TITLE=""
if [ -n "$TITLE_TAG" ]; then
  TITLE=$(printf '%s' "$TITLE_TAG" | sed -E 's/<title[^>]*>(.*)<\/title>/\1/I')
fi

DESCRIPTION=$(get_attr '<meta[^>]*name=["'\''"]description["'\''"][^>]*>' 'content')
OG_TITLE=$(get_attr '<meta[^>]*property=["'\''"]og:title["'\''"][^>]*>' 'content')
OG_DESCRIPTION=$(get_attr '<meta[^>]*property=["'\''"]og:description["'\''"][^>]*>' 'content')
OG_IMAGE=$(get_attr '<meta[^>]*property=["'\''"]og:image["'\''"][^>]*>' 'content')
OG_TYPE=$(get_attr '<meta[^>]*property=["'\''"]og:type["'\''"][^>]*>' 'content')
TWITTER_CARD=$(get_attr '<meta[^>]*name=["'\''"]twitter:card["'\''"][^>]*>' 'content')
VIEWPORT=$(get_attr '<meta[^>]*name=["'\''"]viewport["'\''"][^>]*>' 'content')
CANONICAL=$(get_attr '<link[^>]*rel=["'\''"]canonical["'\''"][^>]*>' 'href')
LANG_VAL=$(get_attr '<html[^>]*>' 'lang')

H1_COUNT=$(count_pattern '<h1[^>]*>')
H2_COUNT=$(count_pattern '<h2[^>]*>')
H3_COUNT=$(count_pattern '<h3[^>]*>')

H1_TAG=$(printf '%s' "$HTML_FLAT" | grep -oiE '<h1[^>]*>[^<]*</h1>' | head -1 || true)
H1_TEXT=""
if [ -n "$H1_TAG" ]; then
  H1_TEXT=$(printf '%s' "$H1_TAG" | sed -E 's/<h1[^>]*>(.*)<\/h1>/\1/I')
fi

IMG_TOTAL=$(count_pattern '<img[^>]*>')
IMG_WITH_ALT=$(count_pattern '<img[^>]*alt=("[^"]*"|'\''[^'\'']*'\'')[^>]*>')

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
