#!/usr/bin/env bash
set -eu

# Scoring regression tests for crawl-sim.
# Each test runs compute-score.sh against a synthetic fixture dir and
# asserts fields on the emitted score JSON.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPUTE_SCORE="$REPO_ROOT/scripts/compute-score.sh"

if [ ! -x "$COMPUTE_SCORE" ]; then
  echo "compute-score.sh is not executable or missing: $COMPUTE_SCORE" >&2
  exit 2
fi

PASSED=0
FAILED=0
CURRENT_CASE=""

case_begin() {
  CURRENT_CASE="$1"
  printf '\n▶ %s\n' "$CURRENT_CASE"
}

pass() {
  printf '  ✓ %s\n' "$1"
  PASSED=$((PASSED + 1))
}

fail() {
  printf '  ✗ %s\n' "$1" >&2
  FAILED=$((FAILED + 1))
}

assert_eq() {
  local actual="$1" expected="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$msg (= $expected)"
  else
    fail "$msg — expected '$expected', got '$actual'"
  fi
}

assert_lt() {
  local actual="$1" limit="$2" msg="$3"
  if [ "$actual" -lt "$limit" ]; then
    pass "$msg ($actual < $limit)"
  else
    fail "$msg — expected < $limit, got '$actual'"
  fi
}

assert_ge() {
  local actual="$1" floor="$2" msg="$3"
  if [ "$actual" -ge "$floor" ]; then
    pass "$msg ($actual ≥ $floor)"
  else
    fail "$msg — expected ≥ $floor, got '$actual'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if printf '%s' "$haystack" | grep -q -- "$needle"; then
    pass "$msg"
  else
    fail "$msg — expected to contain '$needle' in: $haystack"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if printf '%s' "$haystack" | grep -q -- "$needle"; then
    fail "$msg — unexpected '$needle' in: $haystack"
  else
    pass "$msg"
  fi
}

# Run compute-score.sh against a fixture dir and print its stdout.
# Usage: run_score <fixture-name> [extra compute-score args...]
run_score() {
  local name="$1"
  shift
  local fx="$SCRIPT_DIR/fixtures/$name"
  if [ ! -d "$fx" ]; then
    echo "fixture missing: $fx" >&2
    return 2
  fi
  "$COMPUTE_SCORE" "$@" "$fx"
}

# ----- Unit tests: page_type_for_url (AC1 table) -----

# shellcheck source=../scripts/_lib.sh
. "$REPO_ROOT/scripts/_lib.sh"

case_begin "AC1 unit: page_type_for_url classifies URL patterns"
assert_eq "$(page_type_for_url 'https://example.com/')"                  "root"    "apex root"
assert_eq "$(page_type_for_url 'https://example.com')"                   "root"    "apex no trailing slash"
assert_eq "$(page_type_for_url 'https://www.example.com/?utm=abc')"      "root"    "apex with query"
assert_eq "$(page_type_for_url 'https://example.com/work')"              "archive" "/work terminal"
assert_eq "$(page_type_for_url 'https://example.com/work/')"             "archive" "/work/ trailing slash"
assert_eq "$(page_type_for_url 'https://example.com/journal')"           "archive" "/journal terminal"
assert_eq "$(page_type_for_url 'https://example.com/work/cool-project')" "detail"  "/work/:slug"
assert_eq "$(page_type_for_url 'https://example.com/blog/post-name')"    "detail"  "/blog/:slug"
assert_eq "$(page_type_for_url 'https://example.com/articles/my-story')" "detail"  "/articles/:slug"
assert_eq "$(page_type_for_url 'https://example.com/faq')"               "faq"     "/faq"
assert_eq "$(page_type_for_url 'https://example.com/help/faq')"          "faq"     "nested faq"
assert_eq "$(page_type_for_url 'https://example.com/about')"             "about"   "/about"
assert_eq "$(page_type_for_url 'https://example.com/about-us')"          "about"   "/about-us"
assert_eq "$(page_type_for_url 'https://example.com/team')"              "about"   "/team"
assert_eq "$(page_type_for_url 'https://example.com/contact')"           "contact" "/contact"
assert_eq "$(page_type_for_url 'https://example.com/get-in-touch')"      "generic" "generic fallback"
assert_eq "$(page_type_for_url 'https://example.com/services/seo')"      "generic" "unknown section"

# ----- Integration tests: compute-score.sh -----

case_begin "AC1+AC4: root URL auto-detects root, Org+WebSite scores 100"
if OUT=$(run_score root-minimal 2>/dev/null); then
  SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.score')
  PAGE_TYPE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.pageType // "missing"')
  TOP_PAGE_TYPE=$(printf '%s' "$OUT" | jq -r '.pageType // "missing"')
  OVERRIDDEN=$(printf '%s' "$OUT" | jq -r '.pageTypeOverridden')
  MISSING_LEN=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.missing | length')
  VIOLATIONS_LEN=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.violations | length')
  assert_eq "$PAGE_TYPE" "root" "per-bot structuredData.pageType auto-detected from https://example.com/"
  assert_eq "$TOP_PAGE_TYPE" "root" "top-level pageType"
  assert_eq "$OVERRIDDEN" "false" "pageTypeOverridden=false when no flag passed"
  assert_eq "$SCORE" "100" "structuredData score for root with canonical root set"
  assert_eq "$MISSING_LEN" "0" "no missing expected schemas"
  assert_eq "$VIOLATIONS_LEN" "0" "no violations"
else
  fail "compute-score.sh exited non-zero on root-minimal"
fi

case_begin "AC2 validation: invalid --page-type is rejected"
if run_score root-minimal --page-type pizza >/dev/null 2>&1; then
  fail "compute-score.sh accepted invalid --page-type value"
else
  pass "compute-score.sh rejected --page-type pizza with non-zero exit"
fi

case_begin "AC9: non-structured categories unchanged vs baseline golden"
GOLDEN="$SCRIPT_DIR/fixtures/root-minimal/golden-non-structured.json"
if OUT=$(run_score root-minimal 2>/dev/null); then
  ACTUAL=$(printf '%s' "$OUT" | jq '{
    accessibility:     .bots.googlebot.categories.accessibility,
    contentVisibility: .bots.googlebot.categories.contentVisibility,
    technicalSignals:  .bots.googlebot.categories.technicalSignals,
    aiReadiness:       .bots.googlebot.categories.aiReadiness,
    visibility:        .bots.googlebot.visibility
  }')
  EXPECTED=$(jq '.' "$GOLDEN")
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    pass "non-structured categories byte-match golden baseline"
  else
    fail "non-structured categories drifted from golden baseline"
    printf 'expected:\n%s\nactual:\n%s\n' "$EXPECTED" "$ACTUAL" >&2
  fi
else
  fail "compute-score.sh exited non-zero on root-minimal"
fi

case_begin "AC6: root with forbidden schemas (Article + FAQPage) is penalized"
if OUT=$(run_score root-overreaching 2>/dev/null); then
  SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.score')
  PRESENT_FORBIDDEN=$(printf '%s' "$OUT" | jq -c '[.bots.googlebot.categories.structuredData.violations[] | select(.kind=="forbidden_schema") | .schema]')
  VIOL_COUNT=$(printf '%s' "$OUT" | jq -r '[.bots.googlebot.categories.structuredData.violations[] | select(.kind=="forbidden_schema")] | length')
  NOTES=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.notes')
  assert_lt "$SCORE" "100" "forbidden schemas drop structuredData below perfect"
  assert_eq "$VIOL_COUNT" "2" "two forbidden-schema violations (Article + FAQPage)"
  assert_contains "$PRESENT_FORBIDDEN" "Article" "violations mention Article"
  assert_contains "$PRESENT_FORBIDDEN" "FAQPage" "violations mention FAQPage"
  assert_contains "$NOTES" "Forbidden schemas present" "notes explain the forbidden schemas"
else
  fail "compute-score.sh exited non-zero on root-overreaching"
fi

case_begin "AC2+AC5: --page-type detail on same content scores low and flags missing schemas"
if OUT=$(run_score root-minimal --page-type detail 2>/dev/null); then
  SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.score')
  PAGE_TYPE=$(printf '%s' "$OUT" | jq -r '.pageType')
  OVERRIDDEN=$(printf '%s' "$OUT" | jq -r '.pageTypeOverridden')
  MISSING=$(printf '%s' "$OUT" | jq -c '.bots.googlebot.categories.structuredData.missing')
  EXTRAS=$(printf '%s' "$OUT" | jq -c '.bots.googlebot.categories.structuredData.extras')
  assert_eq "$PAGE_TYPE" "detail" "top-level pageType honors --page-type override"
  assert_eq "$OVERRIDDEN" "true" "pageTypeOverridden=true when flag passed"
  assert_lt "$SCORE" "70" "structuredData score for wrong page-type classification"
  assert_contains "$MISSING" "Article" "missing[] contains Article for detail page"
  assert_contains "$MISSING" "BreadcrumbList" "missing[] contains BreadcrumbList for detail page"
  assert_contains "$EXTRAS" "Organization" "extras[] contains Organization (not in detail rubric)"
  assert_contains "$EXTRAS" "WebSite" "extras[] contains WebSite (not in detail rubric)"
else
  fail "compute-score.sh exited non-zero with --page-type detail"
fi

# ----- Sprint A: fetchFailed handling (Issue #11) -----

case_begin "AC-A3: compute-score.sh handles fetchFailed: true — grades F with score 0"
if OUT=$(run_score fetch-failed 2>/dev/null); then
  FETCH_FAILED=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.fetchFailed // false')
  BOT_SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.score')
  BOT_GRADE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.grade')
  ACC_SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.accessibility.score')
  CONTENT_SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.contentVisibility.score')
  STRUCTURED_SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.score')
  assert_eq "$FETCH_FAILED" "true" "bot-level fetchFailed flag propagated"
  assert_eq "$BOT_SCORE" "0" "fetchFailed bot composite score = 0"
  assert_eq "$BOT_GRADE" "F" "fetchFailed bot grade = F"
  assert_eq "$ACC_SCORE" "0" "fetchFailed accessibility = 0"
  assert_eq "$CONTENT_SCORE" "0" "fetchFailed contentVisibility = 0"
  assert_eq "$STRUCTURED_SCORE" "0" "fetchFailed structuredData = 0"
else
  fail "compute-score.sh exited non-zero on fetch-failed fixture"
fi

# ----- Sprint B: H3 redirect chain (AC-B6) -----

case_begin "AC-B6: fetch-as-bot.sh output includes redirect fields"
# Test against an actual fetch to verify the shape includes new fields.
# We invoke fetch-as-bot.sh against httpbin which reliably returns 200.
REDIRECT_TEST_OUT=$("$REPO_ROOT/scripts/fetch-as-bot.sh" "https://httpbin.org/get" "$REPO_ROOT/profiles/googlebot.json" 2>/dev/null || echo '{}')
REDIRECT_COUNT=$(printf '%s' "$REDIRECT_TEST_OUT" | jq -r '.redirectCount // "missing"')
FINAL_URL=$(printf '%s' "$REDIRECT_TEST_OUT" | jq -r '.finalUrl // "missing"')
REDIRECT_CHAIN=$(printf '%s' "$REDIRECT_TEST_OUT" | jq -r '.redirectChain // "missing"')
assert_eq "$REDIRECT_COUNT" "0" "redirectCount present for direct fetch"
if [ "$FINAL_URL" != "missing" ]; then
  pass "finalUrl field present"
else
  fail "finalUrl field missing from fetch output"
fi
if [ "$REDIRECT_CHAIN" != "missing" ]; then
  pass "redirectChain field present"
else
  fail "redirectChain field missing from fetch output"
fi

# ----- Sprint B: C3 field validation (AC-B1, AC-B2) -----

case_begin "AC-B2: schemas present but missing required fields get validity penalty"
if OUT=$(run_score root-invalid-fields 2>/dev/null); then
  SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.score')
  VIOLATIONS=$(printf '%s' "$OUT" | jq '[.bots.googlebot.categories.structuredData.violations[] | select(.kind=="missing_required_field")] | length')
  assert_lt "$SCORE" "100" "missing required fields reduce score below 100"
  assert_ge "$VIOLATIONS" "1" "at least one missing_required_field violation"
else
  fail "compute-score.sh exited non-zero on root-invalid-fields"
fi

case_begin "AC-B1+B2: root-minimal with valid schemas has no field violations"
if OUT=$(run_score root-minimal 2>/dev/null); then
  FIELD_VIOLATIONS=$(printf '%s' "$OUT" | jq '[.bots.googlebot.categories.structuredData.violations[] | select(.kind=="missing_required_field")] | length')
  assert_eq "$FIELD_VIOLATIONS" "0" "no missing_required_field violations for valid schemas"
else
  fail "compute-score.sh exited non-zero on root-minimal"
fi

# ----- Sprint B: C4 cross-bot parity (AC-B3, AC-B4) -----

case_begin "AC-B4: cross-bot parity — high divergence (10x word count) scores low"
if OUT=$(run_score parity-mismatch 2>/dev/null); then
  PARITY_SCORE=$(printf '%s' "$OUT" | jq -r '.parity.score')
  PARITY_GRADE=$(printf '%s' "$OUT" | jq -r '.parity.grade')
  PARITY_MAX_DELTA=$(printf '%s' "$OUT" | jq -r '.parity.maxDeltaPct')
  PARITY_INTERP=$(printf '%s' "$OUT" | jq -r '.parity.interpretation')
  assert_lt "$PARITY_SCORE" "50" "parity score below 50 when 10x word count gap"
  assert_eq "$PARITY_GRADE" "F" "parity grade F for severe divergence"
  assert_ge "$PARITY_MAX_DELTA" "80" "maxDeltaPct reflects 90% content difference"
  assert_contains "$PARITY_INTERP" "client-side rendering" "interpretation mentions CSR"
else
  fail "compute-score.sh exited non-zero on parity-mismatch"
fi

case_begin "AC-B3: cross-bot parity — single bot has perfect parity"
if OUT=$(run_score root-minimal 2>/dev/null); then
  PARITY_SCORE=$(printf '%s' "$OUT" | jq -r '.parity.score')
  PARITY_GRADE=$(printf '%s' "$OUT" | jq -r '.parity.grade')
  assert_eq "$PARITY_SCORE" "100" "single-bot fixture has perfect parity"
  assert_eq "$PARITY_GRADE" "A" "parity grade A for perfect parity"
else
  fail "compute-score.sh exited non-zero on root-minimal for parity"
fi

# ----- Sprint B: H2 diff-render warning (AC-B5) -----

case_begin "AC-B5: missing diff-render.json emits a warning"
if OUT=$(run_score root-minimal 2>/dev/null); then
  WARNINGS_EXIST=$(printf '%s' "$OUT" | jq 'has("warnings")')
  WARN_COUNT=$(printf '%s' "$OUT" | jq '[.warnings[]? | select(.code=="diff_render_unavailable")] | length')
  assert_eq "$WARNINGS_EXIST" "true" "warnings array exists in output"
  assert_eq "$WARN_COUNT" "1" "diff_render_unavailable warning emitted when diff-render.json absent"
else
  fail "compute-score.sh exited non-zero on root-minimal"
fi

# ----- M1: check-llmstxt.sh top-level exists (AC-4) -----

case_begin "AC-4/M1: llmstxt fixture has top-level exists field"
LLMS_TOP_EXISTS=$(jq -r '.exists // "missing"' "$SCRIPT_DIR/fixtures/root-minimal/llmstxt.json")
assert_eq "$LLMS_TOP_EXISTS" "true" "top-level exists present and true when llmsTxt.exists is true"
LLMS_HAS_EXISTS=$(jq 'has("exists")' "$SCRIPT_DIR/fixtures/fetch-failed/llmstxt.json")
LLMS_TOP_EXISTS_ABSENT=$(jq -r '.exists | tostring' "$SCRIPT_DIR/fixtures/fetch-failed/llmstxt.json")
assert_eq "$LLMS_HAS_EXISTS" "true" "fetch-failed fixture has exists key"
assert_eq "$LLMS_TOP_EXISTS_ABSENT" "false" "top-level exists false when neither variant exists"

# ----- AI readiness: llms-full.txt credited same as llms.txt -----

case_begin "AI readiness: llms-full.txt only still scores AI points"
if OUT=$(run_score llms-full-only 2>/dev/null); then
  AI_SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.aiReadiness.score')
  assert_ge "$AI_SCORE" "60" "llms-full.txt earns AI readiness points (got $AI_SCORE)"
else
  fail "compute-score.sh exited non-zero on llms-full-only"
fi

# ----- M3: extract-links.sh flat schema (AC-6) -----

case_begin "AC-6/M3: links fixture uses flat schema with top-level total"
LINKS_TOTAL=$(jq -r '.total // "missing"' "$SCRIPT_DIR/fixtures/parity-mismatch/links-googlebot.json")
assert_eq "$LINKS_TOTAL" "10" "top-level total field present in flat schema"

# ----- M5: consolidated report (AC-8) -----

case_begin "AC-8/M5: build-report.sh merges score + raw data"
"$COMPUTE_SCORE" "$SCRIPT_DIR/fixtures/root-minimal" > "$SCRIPT_DIR/fixtures/root-minimal/score.json" 2>/dev/null
if REPORT=$("$REPO_ROOT/skills/crawl-sim/scripts/build-report.sh" "$SCRIPT_DIR/fixtures/root-minimal" 2>/dev/null); then
  HAS_RAW=$(printf '%s' "$REPORT" | jq 'has("raw")')
  HAS_PERBOT=$(printf '%s' "$REPORT" | jq '.raw | has("perBot")')
  HAS_INDEPENDENT=$(printf '%s' "$REPORT" | jq '.raw | has("independent")')
  SCORE=$(printf '%s' "$REPORT" | jq -r '.overall.score')
  assert_eq "$HAS_RAW" "true" "report has raw section"
  assert_eq "$HAS_PERBOT" "true" "report has raw.perBot section"
  assert_eq "$HAS_INDEPENDENT" "true" "report has raw.independent section"
  assert_ge "$SCORE" "0" "report preserves overall score"
else
  fail "build-report.sh exited non-zero"
fi
rm -f "$SCRIPT_DIR/fixtures/root-minimal/score.json"

# ----- R4: critical-fail robots blocking (AC-10) -----

case_begin "AC-10/R4: bot blocked by robots.txt gets auto-F on accessibility"
if OUT=$(run_score critical-fail-robots 2>/dev/null); then
  ACC_SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.accessibility.score')
  ACC_GRADE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.accessibility.grade')
  BOT_SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.score')
  assert_eq "$ACC_SCORE" "0" "robots-blocked bot gets 0 on accessibility"
  assert_eq "$ACC_GRADE" "F" "robots-blocked bot gets F grade"
  assert_lt "$BOT_SCORE" "80" "composite drops below 80 with accessibility zeroed"
else
  fail "compute-score.sh exited non-zero on critical-fail-robots"
fi

# ----- R2: confidence levels (AC-11) -----

case_begin "AC-11/R2: violations include confidence field"
if OUT=$(run_score root-overreaching 2>/dev/null); then
  FIRST_CONFIDENCE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.violations[0].confidence')
  assert_eq "$FIRST_CONFIDENCE" "high" "violations carry confidence level"
else
  fail "compute-score.sh exited non-zero on root-overreaching"
fi

# ----- Summary -----

printf '\n================================================\n'
printf '  passed: %d   failed: %d\n' "$PASSED" "$FAILED"
printf '================================================\n'

[ "$FAILED" -eq 0 ]
