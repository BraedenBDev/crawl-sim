#!/usr/bin/env bash
set -eu

# compute-score.sh — Aggregate check outputs into per-bot + per-category scores
# Usage: compute-score.sh <results-dir>
# Output: JSON to stdout
#
# Expected filenames in <results-dir>:
#   fetch-<bot_id>.json      — fetch-as-bot.sh output
#   meta-<bot_id>.json       — extract-meta.sh output
#   jsonld-<bot_id>.json     — extract-jsonld.sh output
#   links-<bot_id>.json      — extract-links.sh output
#   robots-<bot_id>.json     — check-robots.sh output
#   llmstxt.json             — check-llmstxt.sh output (bot-independent)
#   sitemap.json             — check-sitemap.sh output (bot-independent)
#   diff-render.json         — diff-render.sh output (optional, Googlebot only)

RESULTS_DIR="${1:?Usage: compute-score.sh <results-dir>}"

if [ ! -d "$RESULTS_DIR" ]; then
  echo "Error: results dir not found: $RESULTS_DIR" >&2
  exit 1
fi

# Category weights (as percentages of per-bot composite)
W_ACCESSIBILITY=25
W_CONTENT=30
W_STRUCTURED=20
W_TECHNICAL=15
W_AI=10

# Overall composite weights (per bot)
# Default: Googlebot 40, GPTBot 20, ClaudeBot 20, PerplexityBot 20
overall_weight() {
  case "$1" in
    googlebot) echo 40 ;;
    gptbot) echo 20 ;;
    claudebot) echo 20 ;;
    perplexitybot) echo 20 ;;
    *) echo 0 ;;
  esac
}

# Grade from score (0-100)
grade_for() {
  local s=$1
  if   [ "$s" -ge 93 ]; then echo "A"
  elif [ "$s" -ge 90 ]; then echo "A-"
  elif [ "$s" -ge 87 ]; then echo "B+"
  elif [ "$s" -ge 83 ]; then echo "B"
  elif [ "$s" -ge 80 ]; then echo "B-"
  elif [ "$s" -ge 77 ]; then echo "C+"
  elif [ "$s" -ge 73 ]; then echo "C"
  elif [ "$s" -ge 70 ]; then echo "C-"
  elif [ "$s" -ge 67 ]; then echo "D+"
  elif [ "$s" -ge 63 ]; then echo "D"
  elif [ "$s" -ge 60 ]; then echo "D-"
  else echo "F"
  fi
}

# Read a jq value from a file with a default fallback
jget() {
  local file="$1"
  local query="$2"
  local default="${3:-null}"
  if [ -f "$file" ]; then
    jq -r "$query // \"$default\"" "$file" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

jget_num() {
  local v
  v=$(jget "$1" "$2" "0")
  # Replace "null" or non-numeric with 0
  if ! printf '%s' "$v" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
    echo "0"
  else
    echo "$v"
  fi
}

jget_bool() {
  local v
  v=$(jget "$1" "$2" "false")
  if [ "$v" = "true" ]; then echo "true"; else echo "false"; fi
}

# Discover bots from fetch-*.json files
BOTS=""
for f in "$RESULTS_DIR"/fetch-*.json; do
  [ -f "$f" ] || continue
  bot_id=$(basename "$f" .json | sed 's/^fetch-//')
  BOTS="$BOTS $bot_id"
done

if [ -z "$BOTS" ]; then
  echo "Error: no fetch-*.json files found in $RESULTS_DIR" >&2
  exit 1
fi

# Bot-independent check files
LLMSTXT_FILE="$RESULTS_DIR/llmstxt.json"
SITEMAP_FILE="$RESULTS_DIR/sitemap.json"

# Track per-bot JSON output
BOTS_JSON="{}"

# Accumulators for per-category averages (across bots)
CAT_ACCESSIBILITY_SUM=0
CAT_CONTENT_SUM=0
CAT_STRUCTURED_SUM=0
CAT_TECHNICAL_SUM=0
CAT_AI_SUM=0
CAT_N=0

# Accumulators for overall weighted composite
OVERALL_WEIGHTED_SUM=0
OVERALL_WEIGHT_TOTAL=0

for bot_id in $BOTS; do
  FETCH="$RESULTS_DIR/fetch-$bot_id.json"
  META="$RESULTS_DIR/meta-$bot_id.json"
  JSONLD="$RESULTS_DIR/jsonld-$bot_id.json"
  LINKS="$RESULTS_DIR/links-$bot_id.json"
  ROBOTS="$RESULTS_DIR/robots-$bot_id.json"

  BOT_NAME=$(jget "$FETCH" '.bot.name' "$bot_id")
  STATUS=$(jget_num "$FETCH" '.status')
  TOTAL_TIME=$(jget_num "$FETCH" '.timing.total')
  WORD_COUNT=$(jget_num "$FETCH" '.wordCount')

  ROBOTS_ALLOWED=$(jget_bool "$ROBOTS" '.allowed')

  # --- Category 1: Accessibility (0-100) ---
  ACC=0
  # robots.txt allows: 40
  [ "$ROBOTS_ALLOWED" = "true" ] && ACC=$((ACC + 40))
  # HTTP 200: 40
  [ "$STATUS" = "200" ] && ACC=$((ACC + 40))
  # Response time: <2s = 20, <5s = 10, else 0
  TIME_SCORE=$(awk -v t="$TOTAL_TIME" 'BEGIN { if (t < 2) print 20; else if (t < 5) print 10; else print 0 }')
  ACC=$((ACC + TIME_SCORE))

  # --- Category 2: Content Visibility (0-100) ---
  CONTENT=0
  # Word count
  if [ "$WORD_COUNT" -ge 300 ]; then CONTENT=$((CONTENT + 30))
  elif [ "$WORD_COUNT" -ge 150 ]; then CONTENT=$((CONTENT + 20))
  elif [ "$WORD_COUNT" -ge 50 ]; then CONTENT=$((CONTENT + 10))
  fi

  H1_COUNT=$(jget_num "$META" '.headings.h1.count')
  H2_COUNT=$(jget_num "$META" '.headings.h2.count')
  [ "$H1_COUNT" -ge 1 ] && CONTENT=$((CONTENT + 20))
  [ "$H2_COUNT" -ge 1 ] && CONTENT=$((CONTENT + 15))

  INTERNAL_LINKS=$(jget_num "$LINKS" '.counts.internal')
  if [ "$INTERNAL_LINKS" -ge 5 ]; then CONTENT=$((CONTENT + 20))
  elif [ "$INTERNAL_LINKS" -ge 1 ]; then CONTENT=$((CONTENT + 10))
  fi

  IMG_TOTAL=$(jget_num "$META" '.images.total')
  IMG_WITH_ALT=$(jget_num "$META" '.images.withAlt')
  if [ "$IMG_TOTAL" -eq 0 ]; then
    CONTENT=$((CONTENT + 15))
  else
    ALT_SCORE=$(awk -v a="$IMG_WITH_ALT" -v t="$IMG_TOTAL" 'BEGIN { printf "%d", (a / t) * 15 }')
    CONTENT=$((CONTENT + ALT_SCORE))
  fi

  # --- Category 3: Structured Data (0-100) ---
  STRUCTURED=0
  JSONLD_COUNT=$(jget_num "$JSONLD" '.blockCount')
  JSONLD_VALID=$(jget_num "$JSONLD" '.validCount')
  JSONLD_INVALID=$(jget_num "$JSONLD" '.invalidCount')
  HAS_ORG=$(jget_bool "$JSONLD" '.flags.hasOrganization')
  HAS_WEBSITE=$(jget_bool "$JSONLD" '.flags.hasWebSite')
  HAS_BREADCRUMB=$(jget_bool "$JSONLD" '.flags.hasBreadcrumbList')
  HAS_ARTICLE=$(jget_bool "$JSONLD" '.flags.hasArticle')
  HAS_PRODUCT=$(jget_bool "$JSONLD" '.flags.hasProduct')
  HAS_FAQ=$(jget_bool "$JSONLD" '.flags.hasFAQPage')

  [ "$JSONLD_COUNT" -ge 1 ] && STRUCTURED=$((STRUCTURED + 30))
  if [ "$JSONLD_COUNT" -ge 1 ] && [ "$JSONLD_INVALID" -eq 0 ]; then
    STRUCTURED=$((STRUCTURED + 20))
  fi
  if [ "$HAS_ORG" = "true" ] || [ "$HAS_WEBSITE" = "true" ]; then
    STRUCTURED=$((STRUCTURED + 20))
  fi
  [ "$HAS_BREADCRUMB" = "true" ] && STRUCTURED=$((STRUCTURED + 15))
  if [ "$HAS_ARTICLE" = "true" ] || [ "$HAS_PRODUCT" = "true" ] || [ "$HAS_FAQ" = "true" ]; then
    STRUCTURED=$((STRUCTURED + 15))
  fi

  # --- Category 4: Technical Signals (0-100) ---
  TECHNICAL=0
  TITLE=$(jget "$META" '.title' "")
  DESCRIPTION=$(jget "$META" '.description' "")
  CANONICAL=$(jget "$META" '.canonical' "")
  OG_TITLE=$(jget "$META" '.og.title' "")
  OG_DESC=$(jget "$META" '.og.description' "")

  [ -n "$TITLE" ] && [ "$TITLE" != "null" ] && TECHNICAL=$((TECHNICAL + 25))
  [ -n "$DESCRIPTION" ] && [ "$DESCRIPTION" != "null" ] && TECHNICAL=$((TECHNICAL + 25))
  [ -n "$CANONICAL" ] && [ "$CANONICAL" != "null" ] && TECHNICAL=$((TECHNICAL + 20))
  if [ -n "$OG_TITLE" ] && [ "$OG_TITLE" != "null" ]; then TECHNICAL=$((TECHNICAL + 8)); fi
  if [ -n "$OG_DESC" ] && [ "$OG_DESC" != "null" ]; then TECHNICAL=$((TECHNICAL + 7)); fi

  SITEMAP_EXISTS=$(jget_bool "$SITEMAP_FILE" '.exists')
  SITEMAP_CONTAINS=$(jget_bool "$SITEMAP_FILE" '.containsTarget')
  if [ "$SITEMAP_EXISTS" = "true" ] && [ "$SITEMAP_CONTAINS" = "true" ]; then
    TECHNICAL=$((TECHNICAL + 15))
  elif [ "$SITEMAP_EXISTS" = "true" ]; then
    TECHNICAL=$((TECHNICAL + 10))
  fi

  # --- Category 5: AI Readiness (0-100) ---
  AI=0
  LLMS_EXISTS=$(jget_bool "$LLMSTXT_FILE" '.llmsTxt.exists')
  LLMS_HAS_TITLE=$(jget_bool "$LLMSTXT_FILE" '.llmsTxt.hasTitle')
  LLMS_HAS_DESC=$(jget_bool "$LLMSTXT_FILE" '.llmsTxt.hasDescription')
  LLMS_URLS=$(jget_num "$LLMSTXT_FILE" '.llmsTxt.urlCount')

  if [ "$LLMS_EXISTS" = "true" ]; then
    AI=$((AI + 40))
    [ "$LLMS_HAS_TITLE" = "true" ] && AI=$((AI + 7))
    [ "$LLMS_HAS_DESC" = "true" ] && AI=$((AI + 7))
    [ "$LLMS_URLS" -ge 1 ] && AI=$((AI + 6))
  fi
  # Content citable (>= 200 words)
  [ "$WORD_COUNT" -ge 200 ] && AI=$((AI + 20))
  # Semantic clarity: has H1 + description
  if [ "$H1_COUNT" -ge 1 ] && [ -n "$DESCRIPTION" ] && [ "$DESCRIPTION" != "null" ]; then
    AI=$((AI + 20))
  fi

  # Cap categories at 100
  [ $ACC -gt 100 ] && ACC=100
  [ $CONTENT -gt 100 ] && CONTENT=100
  [ $STRUCTURED -gt 100 ] && STRUCTURED=100
  [ $TECHNICAL -gt 100 ] && TECHNICAL=100
  [ $AI -gt 100 ] && AI=100

  # Per-bot composite score (weighted average of 5 categories)
  BOT_SCORE=$(awk -v a=$ACC -v c=$CONTENT -v s=$STRUCTURED -v t=$TECHNICAL -v ai=$AI \
    -v wa=$W_ACCESSIBILITY -v wc=$W_CONTENT -v ws=$W_STRUCTURED -v wt=$W_TECHNICAL -v wai=$W_AI \
    'BEGIN { printf "%d", (a*wa + c*wc + s*ws + t*wt + ai*wai) / (wa+wc+ws+wt+wai) + 0.5 }')

  BOT_GRADE=$(grade_for "$BOT_SCORE")
  ACC_GRADE=$(grade_for "$ACC")
  CONTENT_GRADE=$(grade_for "$CONTENT")
  STRUCTURED_GRADE=$(grade_for "$STRUCTURED")
  TECHNICAL_GRADE=$(grade_for "$TECHNICAL")
  AI_GRADE=$(grade_for "$AI")

  # Build bot object
  BOT_OBJ=$(jq -n \
    --arg id "$bot_id" \
    --arg name "$BOT_NAME" \
    --argjson score "$BOT_SCORE" \
    --arg grade "$BOT_GRADE" \
    --argjson acc "$ACC" \
    --arg accGrade "$ACC_GRADE" \
    --argjson content "$CONTENT" \
    --arg contentGrade "$CONTENT_GRADE" \
    --argjson structured "$STRUCTURED" \
    --arg structuredGrade "$STRUCTURED_GRADE" \
    --argjson technical "$TECHNICAL" \
    --arg technicalGrade "$TECHNICAL_GRADE" \
    --argjson ai "$AI" \
    --arg aiGrade "$AI_GRADE" \
    '{
      id: $id,
      name: $name,
      score: $score,
      grade: $grade,
      categories: {
        accessibility:     { score: $acc,        grade: $accGrade },
        contentVisibility: { score: $content,    grade: $contentGrade },
        structuredData:    { score: $structured, grade: $structuredGrade },
        technicalSignals:  { score: $technical,  grade: $technicalGrade },
        aiReadiness:       { score: $ai,         grade: $aiGrade }
      }
    }')

  BOTS_JSON=$(printf '%s' "$BOTS_JSON" | jq --argjson bot "$BOT_OBJ" --arg id "$bot_id" '.[$id] = $bot')

  # Accumulate category averages
  CAT_ACCESSIBILITY_SUM=$((CAT_ACCESSIBILITY_SUM + ACC))
  CAT_CONTENT_SUM=$((CAT_CONTENT_SUM + CONTENT))
  CAT_STRUCTURED_SUM=$((CAT_STRUCTURED_SUM + STRUCTURED))
  CAT_TECHNICAL_SUM=$((CAT_TECHNICAL_SUM + TECHNICAL))
  CAT_AI_SUM=$((CAT_AI_SUM + AI))
  CAT_N=$((CAT_N + 1))

  # Accumulate weighted overall
  W=$(overall_weight "$bot_id")
  if [ "$W" -gt 0 ]; then
    OVERALL_WEIGHTED_SUM=$((OVERALL_WEIGHTED_SUM + BOT_SCORE * W))
    OVERALL_WEIGHT_TOTAL=$((OVERALL_WEIGHT_TOTAL + W))
  fi
done

# Per-category averages (across all bots)
CAT_ACC_AVG=$((CAT_ACCESSIBILITY_SUM / CAT_N))
CAT_CONTENT_AVG=$((CAT_CONTENT_SUM / CAT_N))
CAT_STRUCTURED_AVG=$((CAT_STRUCTURED_SUM / CAT_N))
CAT_TECHNICAL_AVG=$((CAT_TECHNICAL_SUM / CAT_N))
CAT_AI_AVG=$((CAT_AI_SUM / CAT_N))

# Overall composite
if [ "$OVERALL_WEIGHT_TOTAL" -gt 0 ]; then
  OVERALL_SCORE=$((OVERALL_WEIGHTED_SUM / OVERALL_WEIGHT_TOTAL))
else
  # Fall back to simple average if none of the 4 standard bots are present
  OVERALL_SCORE=$(((CAT_ACC_AVG + CAT_CONTENT_AVG + CAT_STRUCTURED_AVG + CAT_TECHNICAL_AVG + CAT_AI_AVG) / 5))
fi

OVERALL_GRADE=$(grade_for "$OVERALL_SCORE")
CAT_ACC_GRADE=$(grade_for "$CAT_ACC_AVG")
CAT_CONTENT_GRADE=$(grade_for "$CAT_CONTENT_AVG")
CAT_STRUCTURED_GRADE=$(grade_for "$CAT_STRUCTURED_AVG")
CAT_TECHNICAL_GRADE=$(grade_for "$CAT_TECHNICAL_AVG")
CAT_AI_GRADE=$(grade_for "$CAT_AI_AVG")

# Get the URL from the first fetch file
FIRST_FETCH=$(ls "$RESULTS_DIR"/fetch-*.json | head -1)
TARGET_URL=$(jget "$FIRST_FETCH" '.url' "")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
  --arg url "$TARGET_URL" \
  --arg timestamp "$TIMESTAMP" \
  --arg version "0.1.0" \
  --argjson overallScore "$OVERALL_SCORE" \
  --arg overallGrade "$OVERALL_GRADE" \
  --argjson bots "$BOTS_JSON" \
  --argjson catAcc "$CAT_ACC_AVG" \
  --arg catAccGrade "$CAT_ACC_GRADE" \
  --argjson catContent "$CAT_CONTENT_AVG" \
  --arg catContentGrade "$CAT_CONTENT_GRADE" \
  --argjson catStructured "$CAT_STRUCTURED_AVG" \
  --arg catStructuredGrade "$CAT_STRUCTURED_GRADE" \
  --argjson catTechnical "$CAT_TECHNICAL_AVG" \
  --arg catTechnicalGrade "$CAT_TECHNICAL_GRADE" \
  --argjson catAi "$CAT_AI_AVG" \
  --arg catAiGrade "$CAT_AI_GRADE" \
  '{
    url: $url,
    timestamp: $timestamp,
    version: $version,
    overall: { score: $overallScore, grade: $overallGrade },
    bots: $bots,
    categories: {
      accessibility:     { score: $catAcc,        grade: $catAccGrade },
      contentVisibility: { score: $catContent,    grade: $catContentGrade },
      structuredData:    { score: $catStructured, grade: $catStructuredGrade },
      technicalSignals:  { score: $catTechnical,  grade: $catTechnicalGrade },
      aiReadiness:       { score: $catAi,         grade: $catAiGrade }
    }
  }'
