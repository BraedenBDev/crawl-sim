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
  if [ "$actual" -lt "$limit" ] 2>/dev/null; then
    pass "$msg ($actual < $limit)"
  else
    fail "$msg — expected < $limit, got '$actual'"
  fi
}

assert_ge() {
  local actual="$1" floor="$2" msg="$3"
  if [ "$actual" -ge "$floor" ] 2>/dev/null; then
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

# ----- Test cases -----

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

# ----- Summary -----

printf '\n================================================\n'
printf '  passed: %d   failed: %d\n' "$PASSED" "$FAILED"
printf '================================================\n'

[ "$FAILED" -eq 0 ]
