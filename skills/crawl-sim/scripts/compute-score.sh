#!/usr/bin/env bash
set -eu

# compute-score.sh — Aggregate check outputs into per-bot + per-category scores
# Usage: compute-score.sh [--page-type <type>] <results-dir>
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
#
# The --page-type flag overrides URL-based page-type detection. Valid values:
# root, detail, archive, faq, about, contact, generic.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"
# shellcheck source=schema-fields.sh
. "$SCRIPT_DIR/schema-fields.sh"

PAGE_TYPE_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --page-type)
      [ $# -ge 2 ] || { echo "--page-type requires a value" >&2; exit 2; }
      PAGE_TYPE_OVERRIDE="$2"
      shift 2
      ;;
    --page-type=*)
      PAGE_TYPE_OVERRIDE="${1#--page-type=}"
      shift
      ;;
    -h|--help)
      echo "Usage: compute-score.sh [--page-type <type>] <results-dir>"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

RESULTS_DIR="${1:?Usage: compute-score.sh [--page-type <type>] <results-dir>}"

if [ -n "$PAGE_TYPE_OVERRIDE" ]; then
  case "$PAGE_TYPE_OVERRIDE" in
    root|detail|archive|faq|about|contact|generic) ;;
    *)
      echo "Error: invalid --page-type '$PAGE_TYPE_OVERRIDE' (valid: root, detail, archive, faq, about, contact, generic)" >&2
      exit 2
      ;;
  esac
fi

printf '[compute-score] aggregating %s\n' "$RESULTS_DIR" >&2

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
overall_weight() {
  case "$1" in
    googlebot) echo 40 ;;
    gptbot) echo 20 ;;
    claudebot) echo 20 ;;
    perplexitybot) echo 20 ;;
    *) echo 0 ;;
  esac
}

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

# Rubric: expected schema types per page type.
rubric_expected() {
  case "$1" in
    root)    echo "Organization WebSite" ;;
    detail)  echo "Article BreadcrumbList" ;;
    archive) echo "CollectionPage ItemList BreadcrumbList" ;;
    faq)     echo "FAQPage BreadcrumbList" ;;
    about)   echo "AboutPage BreadcrumbList Organization" ;;
    contact) echo "ContactPage BreadcrumbList" ;;
    *)       echo "WebPage BreadcrumbList" ;;
  esac
}

rubric_optional() {
  case "$1" in
    root)    echo "ProfessionalService LocalBusiness" ;;
    detail)  echo "NewsArticle ImageObject Person" ;;
    archive) echo "" ;;
    faq)     echo "WebPage" ;;
    about)   echo "Person" ;;
    contact) echo "PostalAddress" ;;
    *)       echo "" ;;
  esac
}

rubric_forbidden() {
  case "$1" in
    root)    echo "BreadcrumbList Article FAQPage" ;;
    detail)  echo "CollectionPage ItemList" ;;
    archive) echo "Article Product" ;;
    faq)     echo "Article CollectionPage" ;;
    about)   echo "Article Product" ;;
    contact) echo "Article Product" ;;
    *)       echo "" ;;
  esac
}

list_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

list_count() {
  # shellcheck disable=SC2086
  set -- $1
  echo "$#"
}

list_intersect() {
  local a="$1" b="$2"
  local out="" item
  # shellcheck disable=SC2086
  for item in $a; do
    # shellcheck disable=SC2086
    if list_contains "$item" $b; then
      out="$out $item"
    fi
  done
  printf '%s' "${out# }"
}

list_diff() {
  local a="$1" b="$2"
  local out="" item
  # shellcheck disable=SC2086
  for item in $a; do
    # shellcheck disable=SC2086
    if ! list_contains "$item" $b; then
      out="$out $item"
    fi
  done
  printf '%s' "${out# }"
}

jget() {
  local file="$1"
  local query="$2"
  local default="${3:-null}"
  if [ -f "$file" ]; then
    jq -r --arg d "$default" "$query // \$d" "$file" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

jget_num() {
  local v
  v=$(jget "$1" "$2" "0")
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

BOTS=""
FIRST_FETCH=""
for f in "$RESULTS_DIR"/fetch-*.json; do
  [ -f "$f" ] || continue
  [ -z "$FIRST_FETCH" ] && FIRST_FETCH="$f"
  bot_id=$(basename "$f" .json | sed 's/^fetch-//')
  BOTS="$BOTS $bot_id"
done

if [ -z "$BOTS" ]; then
  echo "Error: no fetch-*.json files found in $RESULTS_DIR" >&2
  exit 1
fi

LLMSTXT_FILE="$RESULTS_DIR/llmstxt.json"
SITEMAP_FILE="$RESULTS_DIR/sitemap.json"
DIFF_RENDER_FILE="$RESULTS_DIR/diff-render.json"

DIFF_AVAILABLE=false
DIFF_RENDERED_WORDS=0
DIFF_DELTA_PCT=0
if [ -f "$DIFF_RENDER_FILE" ]; then
  DIFF_SKIPPED=$(jq -r '.skipped | if . == null then "true" else tostring end' "$DIFF_RENDER_FILE" 2>/dev/null || echo "true")
  if [ "$DIFF_SKIPPED" = "false" ]; then
    DIFF_AVAILABLE=true
    DIFF_RENDERED_WORDS=$(jq -r '.renderedWordCount // 0' "$DIFF_RENDER_FILE")
    DIFF_DELTA_PCT=$(jq -r '.deltaPct // 0' "$DIFF_RENDER_FILE")
  fi
fi

# Resolve page type once from the first fetch file's URL, unless overridden.
TARGET_URL=$(jget "$FIRST_FETCH" '.url' "")
if [ -n "$PAGE_TYPE_OVERRIDE" ]; then
  PAGE_TYPE="$PAGE_TYPE_OVERRIDE"
else
  PAGE_TYPE=$(page_type_for_url "$TARGET_URL")
fi
printf '[compute-score] page type: %s (url: %s)\n' "$PAGE_TYPE" "$TARGET_URL" >&2

RUBRIC_EXPECTED="$(rubric_expected "$PAGE_TYPE")"
RUBRIC_OPTIONAL="$(rubric_optional "$PAGE_TYPE")"
RUBRIC_FORBIDDEN="$(rubric_forbidden "$PAGE_TYPE")"
EXPECTED_COUNT=$(list_count "$RUBRIC_EXPECTED")

BOTS_JSON="{}"

CAT_ACCESSIBILITY_SUM=0
CAT_CONTENT_SUM=0
CAT_STRUCTURED_SUM=0
CAT_TECHNICAL_SUM=0
CAT_AI_SUM=0
CAT_N=0

OVERALL_WEIGHTED_SUM=0
OVERALL_WEIGHT_TOTAL=0

for bot_id in $BOTS; do
  FETCH="$RESULTS_DIR/fetch-$bot_id.json"
  META="$RESULTS_DIR/meta-$bot_id.json"
  JSONLD="$RESULTS_DIR/jsonld-$bot_id.json"
  LINKS="$RESULTS_DIR/links-$bot_id.json"
  ROBOTS="$RESULTS_DIR/robots-$bot_id.json"

  BOT_NAME=$(jget "$FETCH" '.bot.name' "$bot_id")

  # Check for fetch failure — skip scoring, emit F grade (AC-A3)
  FETCH_FAILED=$(jget_bool "$FETCH" '.fetchFailed')
  if [ "$FETCH_FAILED" = "true" ]; then
    FETCH_ERROR=$(jget "$FETCH" '.error' "unknown error")
    RENDERS_JS=$(jq -r '.bot.rendersJavaScript | if . == null then "unknown" else tostring end' "$FETCH" 2>/dev/null || echo "unknown")
    BOT_OBJ=$(jq -n \
      --arg id "$bot_id" \
      --arg name "$BOT_NAME" \
      --arg rendersJs "$RENDERS_JS" \
      --arg error "$FETCH_ERROR" \
      '{
        id: $id,
        name: $name,
        rendersJavaScript: (if $rendersJs == "true" then true elif $rendersJs == "false" then false else $rendersJs end),
        fetchFailed: true,
        error: $error,
        score: 0,
        grade: "F",
        visibility: { serverWords: 0, effectiveWords: 0, missedWordsVsRendered: 0, hydrationPenaltyPts: 0 },
        categories: {
          accessibility:     { score: 0, grade: "F" },
          contentVisibility: { score: 0, grade: "F" },
          structuredData:    { score: 0, grade: "F", pageType: "unknown", expected: [], optional: [], forbidden: [], present: [], missing: [], extras: [], violations: [{ kind: "fetch_failed", impact: -100 }], calculation: "fetch failed — no data to score", notes: ("Fetch failed: " + $error) },
          technicalSignals:  { score: 0, grade: "F" },
          aiReadiness:       { score: 0, grade: "F" }
        }
      }')
    BOTS_JSON=$(printf '%s' "$BOTS_JSON" | jq --argjson bot "$BOT_OBJ" --arg id "$bot_id" '.[$id] = $bot')
    printf '[compute-score] %s: fetch failed, scoring as F\n' "$bot_id" >&2
    CAT_N=$((CAT_N + 1))
    continue
  fi

  STATUS=$(jget_num "$FETCH" '.status')
  TOTAL_TIME=$(jget_num "$FETCH" '.timing.total')
  SERVER_WORD_COUNT=$(jget_num "$FETCH" '.wordCount')
  RENDERS_JS=$(jq -r '.bot.rendersJavaScript | if . == null then "unknown" else tostring end' "$FETCH" 2>/dev/null || echo "unknown")

  ROBOTS_ALLOWED=$(jget_bool "$ROBOTS" '.allowed')

  EFFECTIVE_WORD_COUNT=$SERVER_WORD_COUNT
  HYDRATION_PENALTY=0
  MISSED_WORDS=0
  if [ "$DIFF_AVAILABLE" = "true" ]; then
    if [ "$RENDERS_JS" = "true" ]; then
      EFFECTIVE_WORD_COUNT=$DIFF_RENDERED_WORDS
    elif [ "$RENDERS_JS" = "false" ]; then
      ABS_DELTA=$(awk -v d="$DIFF_DELTA_PCT" 'BEGIN { printf "%d", (d < 0 ? -d : d) + 0.5 }')
      if [ "$ABS_DELTA" -gt 5 ]; then
        HYDRATION_PENALTY=$(awk -v d="$ABS_DELTA" 'BEGIN {
          p = (d - 5)
          if (p > 15) p = 15
          printf "%d", p
        }')
      fi
      MISSED_WORDS=$((DIFF_RENDERED_WORDS - SERVER_WORD_COUNT))
      [ "$MISSED_WORDS" -lt 0 ] && MISSED_WORDS=0
    fi
  fi

  # --- Category 1: Accessibility (0-100) ---
  ACC=0
  [ "$ROBOTS_ALLOWED" = "true" ] && ACC=$((ACC + 40))
  [ "$STATUS" = "200" ] && ACC=$((ACC + 40))
  TIME_SCORE=$(awk -v t="$TOTAL_TIME" 'BEGIN { if (t < 2) print 20; else if (t < 5) print 10; else print 0 }')
  ACC=$((ACC + TIME_SCORE))

  # --- Category 2: Content Visibility (0-100) ---
  CONTENT=0
  if [ "$EFFECTIVE_WORD_COUNT" -ge 300 ]; then CONTENT=$((CONTENT + 30))
  elif [ "$EFFECTIVE_WORD_COUNT" -ge 150 ]; then CONTENT=$((CONTENT + 20))
  elif [ "$EFFECTIVE_WORD_COUNT" -ge 50 ]; then CONTENT=$((CONTENT + 10))
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

  CONTENT=$((CONTENT - HYDRATION_PENALTY))
  [ $CONTENT -lt 0 ] && CONTENT=0

  # --- Category 3: Structured Data (0-100) ---
  JSONLD_COUNT=$(jget_num "$JSONLD" '.blockCount')
  JSONLD_VALID=$(jget_num "$JSONLD" '.validCount')
  JSONLD_INVALID=$(jget_num "$JSONLD" '.invalidCount')

  if [ -f "$JSONLD" ]; then
    PRESENT_TYPES=$(jq -r '.types[]? // empty' "$JSONLD" 2>/dev/null | awk 'NF && !seen[$0]++' | tr '\n' ' ')
    PRESENT_TYPES=${PRESENT_TYPES% }
  else
    PRESENT_TYPES=""
  fi

  PRESENT_EXPECTED=$(list_intersect "$RUBRIC_EXPECTED" "$PRESENT_TYPES")
  PRESENT_OPTIONAL=$(list_intersect "$RUBRIC_OPTIONAL" "$PRESENT_TYPES")
  PRESENT_FORBIDDEN=$(list_intersect "$RUBRIC_FORBIDDEN" "$PRESENT_TYPES")
  MISSING_EXPECTED=$(list_diff "$RUBRIC_EXPECTED" "$PRESENT_TYPES")
  RUBRIC_KNOWN="$RUBRIC_EXPECTED $RUBRIC_OPTIONAL $RUBRIC_FORBIDDEN"
  EXTRAS=$(list_diff "$PRESENT_TYPES" "$RUBRIC_KNOWN")

  PRESENT_EXPECTED_COUNT=$(list_count "$PRESENT_EXPECTED")
  PRESENT_OPTIONAL_COUNT=$(list_count "$PRESENT_OPTIONAL")
  PRESENT_FORBIDDEN_COUNT=$(list_count "$PRESENT_FORBIDDEN")

  BASE=$(awk -v h="$PRESENT_EXPECTED_COUNT" -v t="$EXPECTED_COUNT" \
    'BEGIN { if (t == 0) print 0; else printf "%d", (h / t) * 100 + 0.5 }')

  BONUS=$((PRESENT_OPTIONAL_COUNT * 10))
  [ $BONUS -gt 20 ] && BONUS=20

  FORBID_PENALTY=$((PRESENT_FORBIDDEN_COUNT * 10))

  VALID_PENALTY=0
  if [ "$JSONLD_COUNT" -gt 0 ] && [ "$JSONLD_INVALID" -gt 0 ]; then
    VALID_PENALTY=$((JSONLD_INVALID * 5))
    [ $VALID_PENALTY -gt 20 ] && VALID_PENALTY=20
  fi

  # Field-level validation (C3): check required fields per schema type
  FIELD_PENALTY=0
  FIELD_VIOLATIONS_JSON="[]"
  if [ -f "$JSONLD" ] && jq -e '.blocks' "$JSONLD" >/dev/null 2>&1; then
    BLOCK_COUNT_FOR_FIELDS=$(jq '.blocks | length' "$JSONLD" 2>/dev/null || echo "0")
    i=0
    while [ "$i" -lt "$BLOCK_COUNT_FOR_FIELDS" ]; do
      BLOCK_TYPE=$(jq -r ".blocks[$i].type" "$JSONLD" 2>/dev/null || echo "")
      BLOCK_FIELDS=$(jq -r ".blocks[$i].fields[]?" "$JSONLD" 2>/dev/null | tr '\n' ' ')
      REQUIRED=$(required_fields_for "$BLOCK_TYPE")
      for field in $REQUIRED; do
        if ! printf ' %s ' "$BLOCK_FIELDS" | grep -q " $field "; then
          FIELD_VIOLATIONS_JSON=$(printf '%s' "$FIELD_VIOLATIONS_JSON" | jq \
            --arg schema "$BLOCK_TYPE" --arg field "$field" \
            '. + [{kind: "missing_required_field", schema: $schema, field: $field, impact: -5}]')
          FIELD_PENALTY=$((FIELD_PENALTY + 5))
        fi
      done
      i=$((i + 1))
    done
  fi
  [ $FIELD_PENALTY -gt 30 ] && FIELD_PENALTY=30

  STRUCTURED=$((BASE + BONUS - FORBID_PENALTY - VALID_PENALTY - FIELD_PENALTY))
  [ $STRUCTURED -gt 100 ] && STRUCTURED=100
  [ $STRUCTURED -lt 0 ] && STRUCTURED=0

  CALCULATION=$(printf 'base: %d/%d expected present = %d; +%d optional bonus; -%d forbidden penalty; -%d validity penalty; -%d field penalty; clamp [0,100] = %d' \
    "$PRESENT_EXPECTED_COUNT" "$EXPECTED_COUNT" "$BASE" \
    "$BONUS" "$FORBID_PENALTY" "$VALID_PENALTY" "$FIELD_PENALTY" "$STRUCTURED")

  if [ "$STRUCTURED" -ge 100 ] && [ -z "$PRESENT_FORBIDDEN" ] && [ "$VALID_PENALTY" -eq 0 ] && [ "$FIELD_PENALTY" -eq 0 ]; then
    NOTES="All expected schemas for pageType=$PAGE_TYPE are present. No structured-data action needed."
  elif [ -n "$MISSING_EXPECTED" ] && [ -z "$PRESENT_FORBIDDEN" ]; then
    NOTES="Missing expected schemas for pageType=$PAGE_TYPE: $MISSING_EXPECTED. Add these to raise the score."
  elif [ -n "$PRESENT_FORBIDDEN" ] && [ -z "$MISSING_EXPECTED" ]; then
    NOTES="Forbidden schemas present for pageType=$PAGE_TYPE: $PRESENT_FORBIDDEN. Remove these (or re-classify the page type with --page-type)."
  elif [ -n "$PRESENT_FORBIDDEN" ] && [ -n "$MISSING_EXPECTED" ]; then
    NOTES="Mixed: missing $MISSING_EXPECTED and forbidden present $PRESENT_FORBIDDEN for pageType=$PAGE_TYPE."
  elif [ "$FIELD_PENALTY" -gt 0 ]; then
    NOTES="Schemas for pageType=$PAGE_TYPE are present but missing required fields. See violations for details."
  elif [ "$VALID_PENALTY" -gt 0 ]; then
    NOTES="Score reduced by $VALID_PENALTY pts due to invalid JSON-LD blocks."
  else
    NOTES="Structured data scored for pageType=$PAGE_TYPE."
  fi

  STRUCTURED_GRADE=$(grade_for "$STRUCTURED")
  STRUCTURED_OBJ=$(jq -n \
    --argjson score "$STRUCTURED" \
    --arg grade "$STRUCTURED_GRADE" \
    --arg pageType "$PAGE_TYPE" \
    --arg expectedList "$RUBRIC_EXPECTED" \
    --arg optionalList "$RUBRIC_OPTIONAL" \
    --arg forbiddenList "$RUBRIC_FORBIDDEN" \
    --arg presentList "$PRESENT_TYPES" \
    --arg missingList "$MISSING_EXPECTED" \
    --arg extrasList "$EXTRAS" \
    --arg forbiddenPresent "$PRESENT_FORBIDDEN" \
    --argjson invalidCount "$JSONLD_INVALID" \
    --argjson validPenalty "$VALID_PENALTY" \
    --argjson fieldViolations "$FIELD_VIOLATIONS_JSON" \
    --arg calculation "$CALCULATION" \
    --arg notes "$NOTES" \
    '
    def to_arr: split(" ") | map(select(length > 0));
    {
      score: $score,
      grade: $grade,
      pageType: $pageType,
      expected:   ($expectedList   | to_arr),
      optional:   ($optionalList   | to_arr),
      forbidden:  ($forbiddenList  | to_arr),
      present:    ($presentList    | to_arr),
      missing:    ($missingList    | to_arr),
      extras:     ($extrasList     | to_arr),
      violations: (
        ($forbiddenPresent | to_arr | map({kind: "forbidden_schema", schema: ., impact: -10}))
        + (if $validPenalty > 0
             then [{kind: "invalid_jsonld", count: $invalidCount, impact: (0 - $validPenalty)}]
             else []
           end)
        + $fieldViolations
      ),
      calculation: $calculation,
      notes: $notes
    }
    ')

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
  [ "$EFFECTIVE_WORD_COUNT" -ge 200 ] && AI=$((AI + 20))
  if [ "$H1_COUNT" -ge 1 ] && [ -n "$DESCRIPTION" ] && [ "$DESCRIPTION" != "null" ]; then
    AI=$((AI + 20))
  fi

  [ $ACC -gt 100 ] && ACC=100
  [ $CONTENT -gt 100 ] && CONTENT=100
  [ $TECHNICAL -gt 100 ] && TECHNICAL=100
  [ $AI -gt 100 ] && AI=100

  BOT_SCORE=$(awk -v a=$ACC -v c=$CONTENT -v s=$STRUCTURED -v t=$TECHNICAL -v ai=$AI \
    -v wa=$W_ACCESSIBILITY -v wc=$W_CONTENT -v ws=$W_STRUCTURED -v wt=$W_TECHNICAL -v wai=$W_AI \
    'BEGIN { printf "%d", (a*wa + c*wc + s*ws + t*wt + ai*wai) / (wa+wc+ws+wt+wai) + 0.5 }')

  BOT_GRADE=$(grade_for "$BOT_SCORE")
  ACC_GRADE=$(grade_for "$ACC")
  CONTENT_GRADE=$(grade_for "$CONTENT")
  TECHNICAL_GRADE=$(grade_for "$TECHNICAL")
  AI_GRADE=$(grade_for "$AI")

  BOT_OBJ=$(jq -n \
    --arg id "$bot_id" \
    --arg name "$BOT_NAME" \
    --arg rendersJs "$RENDERS_JS" \
    --argjson score "$BOT_SCORE" \
    --arg grade "$BOT_GRADE" \
    --argjson acc "$ACC" \
    --arg accGrade "$ACC_GRADE" \
    --argjson content "$CONTENT" \
    --arg contentGrade "$CONTENT_GRADE" \
    --argjson structured "$STRUCTURED_OBJ" \
    --argjson technical "$TECHNICAL" \
    --arg technicalGrade "$TECHNICAL_GRADE" \
    --argjson ai "$AI" \
    --arg aiGrade "$AI_GRADE" \
    --argjson serverWords "$SERVER_WORD_COUNT" \
    --argjson effectiveWords "$EFFECTIVE_WORD_COUNT" \
    --argjson missedWords "$MISSED_WORDS" \
    --argjson hydrationPenalty "$HYDRATION_PENALTY" \
    '{
      id: $id,
      name: $name,
      rendersJavaScript: (if $rendersJs == "true" then true elif $rendersJs == "false" then false else $rendersJs end),
      score: $score,
      grade: $grade,
      visibility: {
        serverWords: $serverWords,
        effectiveWords: $effectiveWords,
        missedWordsVsRendered: $missedWords,
        hydrationPenaltyPts: $hydrationPenalty
      },
      categories: {
        accessibility:     { score: $acc,       grade: $accGrade },
        contentVisibility: { score: $content,   grade: $contentGrade },
        structuredData:    $structured,
        technicalSignals:  { score: $technical, grade: $technicalGrade },
        aiReadiness:       { score: $ai,        grade: $aiGrade }
      }
    }')

  BOTS_JSON=$(printf '%s' "$BOTS_JSON" | jq --argjson bot "$BOT_OBJ" --arg id "$bot_id" '.[$id] = $bot')

  CAT_ACCESSIBILITY_SUM=$((CAT_ACCESSIBILITY_SUM + ACC))
  CAT_CONTENT_SUM=$((CAT_CONTENT_SUM + CONTENT))
  CAT_STRUCTURED_SUM=$((CAT_STRUCTURED_SUM + STRUCTURED))
  CAT_TECHNICAL_SUM=$((CAT_TECHNICAL_SUM + TECHNICAL))
  CAT_AI_SUM=$((CAT_AI_SUM + AI))
  CAT_N=$((CAT_N + 1))

  W=$(overall_weight "$bot_id")
  if [ "$W" -gt 0 ]; then
    OVERALL_WEIGHTED_SUM=$((OVERALL_WEIGHTED_SUM + BOT_SCORE * W))
    OVERALL_WEIGHT_TOTAL=$((OVERALL_WEIGHT_TOTAL + W))
  fi
done

CAT_ACC_AVG=$((CAT_ACCESSIBILITY_SUM / CAT_N))
CAT_CONTENT_AVG=$((CAT_CONTENT_SUM / CAT_N))
CAT_STRUCTURED_AVG=$((CAT_STRUCTURED_SUM / CAT_N))
CAT_TECHNICAL_AVG=$((CAT_TECHNICAL_SUM / CAT_N))
CAT_AI_AVG=$((CAT_AI_SUM / CAT_N))

if [ "$OVERALL_WEIGHT_TOTAL" -gt 0 ]; then
  OVERALL_SCORE=$((OVERALL_WEIGHTED_SUM / OVERALL_WEIGHT_TOTAL))
else
  OVERALL_SCORE=$(((CAT_ACC_AVG + CAT_CONTENT_AVG + CAT_STRUCTURED_AVG + CAT_TECHNICAL_AVG + CAT_AI_AVG) / 5))
fi

OVERALL_GRADE=$(grade_for "$OVERALL_SCORE")
CAT_ACC_GRADE=$(grade_for "$CAT_ACC_AVG")
CAT_CONTENT_GRADE=$(grade_for "$CAT_CONTENT_AVG")
CAT_STRUCTURED_GRADE=$(grade_for "$CAT_STRUCTURED_AVG")
CAT_TECHNICAL_GRADE=$(grade_for "$CAT_TECHNICAL_AVG")
CAT_AI_GRADE=$(grade_for "$CAT_AI_AVG")

# --- Cross-bot content parity (C4) ---
PARITY_MIN_WORDS=999999999
PARITY_MAX_WORDS=0
PARITY_BOT_COUNT=0
for bot_id in $BOTS; do
  FETCH="$RESULTS_DIR/fetch-$bot_id.json"
  P_FETCH_FAILED=$(jget_bool "$FETCH" '.fetchFailed')
  [ "$P_FETCH_FAILED" = "true" ] && continue
  WC=$(jget_num "$FETCH" '.wordCount')
  [ "$WC" -lt "$PARITY_MIN_WORDS" ] && PARITY_MIN_WORDS=$WC
  [ "$WC" -gt "$PARITY_MAX_WORDS" ] && PARITY_MAX_WORDS=$WC
  PARITY_BOT_COUNT=$((PARITY_BOT_COUNT + 1))
done

if [ "$PARITY_BOT_COUNT" -le 1 ]; then
  PARITY_SCORE=100
  PARITY_MAX_DELTA=0
elif [ "$PARITY_MAX_WORDS" -gt 0 ]; then
  PARITY_SCORE=$(awk -v min="$PARITY_MIN_WORDS" -v max="$PARITY_MAX_WORDS" \
    'BEGIN { printf "%d", (min / max) * 100 + 0.5 }')
  PARITY_MAX_DELTA=$(awk -v min="$PARITY_MIN_WORDS" -v max="$PARITY_MAX_WORDS" \
    'BEGIN { printf "%d", ((max - min) / max) * 100 + 0.5 }')
else
  PARITY_SCORE=100
  PARITY_MAX_DELTA=0
fi

[ "$PARITY_SCORE" -gt 100 ] && PARITY_SCORE=100
PARITY_GRADE=$(grade_for "$PARITY_SCORE")

if [ "$PARITY_SCORE" -ge 95 ]; then
  PARITY_INTERP="Content is consistent across all bots."
elif [ "$PARITY_SCORE" -ge 50 ]; then
  PARITY_INTERP="Moderate content divergence between bots — likely partial client-side rendering hydration."
else
  PARITY_INTERP="Severe content divergence — site likely relies on client-side rendering. AI bots see significantly less content than Googlebot."
fi

# --- Warnings (H2) ---
WARNINGS="[]"
if [ "$DIFF_AVAILABLE" != "true" ]; then
  DIFF_REASON="not_found"
  if [ -f "$DIFF_RENDER_FILE" ]; then
    DIFF_REASON=$(jq -r '.reason // "skipped"' "$DIFF_RENDER_FILE" 2>/dev/null || echo "skipped")
  fi
  WARNINGS=$(printf '%s' "$WARNINGS" | jq --arg reason "$DIFF_REASON" \
    '. + [{
      code: "diff_render_unavailable",
      severity: "high",
      message: "JS rendering comparison was skipped. If this site uses CSR, non-JS bot scores may be inaccurate.",
      reason: $reason
    }]')
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
  --arg url "$TARGET_URL" \
  --arg timestamp "$TIMESTAMP" \
  --arg version "0.2.0" \
  --arg pageType "$PAGE_TYPE" \
  --arg pageTypeOverride "$PAGE_TYPE_OVERRIDE" \
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
  --argjson warnings "$WARNINGS" \
  --argjson parityScore "$PARITY_SCORE" \
  --arg parityGrade "$PARITY_GRADE" \
  --argjson parityMinWords "$PARITY_MIN_WORDS" \
  --argjson parityMaxWords "$PARITY_MAX_WORDS" \
  --argjson parityMaxDelta "$PARITY_MAX_DELTA" \
  --arg parityInterp "$PARITY_INTERP" \
  '{
    url: $url,
    timestamp: $timestamp,
    version: $version,
    pageType: $pageType,
    pageTypeOverridden: ($pageTypeOverride | length > 0),
    overall: { score: $overallScore, grade: $overallGrade },
    parity: {
      score: $parityScore,
      grade: $parityGrade,
      minWords: (if $parityMinWords >= 999999999 then 0 else $parityMinWords end),
      maxWords: $parityMaxWords,
      maxDeltaPct: $parityMaxDelta,
      interpretation: $parityInterp
    },
    warnings: $warnings,
    bots: $bots,
    categories: {
      accessibility:     { score: $catAcc,        grade: $catAccGrade },
      contentVisibility: { score: $catContent,    grade: $catContentGrade },
      structuredData:    { score: $catStructured, grade: $catStructuredGrade },
      technicalSignals:  { score: $catTechnical,  grade: $catTechnicalGrade },
      aiReadiness:       { score: $catAi,         grade: $catAiGrade }
    }
  }'
