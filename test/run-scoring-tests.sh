#!/usr/bin/env bash
set -eu

# Scoring regression tests for crawl-sim.
# Each test runs compute-score.sh against a synthetic fixture dir and
# asserts fields on the emitted score JSON.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPUTE_SCORE="$REPO_ROOT/scripts/compute-score.sh"
BUILD_REPORT="$REPO_ROOT/scripts/build-report.sh"
GENERATE_REPORT_HTML="$REPO_ROOT/scripts/generate-report-html.sh"
GENERATE_COMPARE_HTML="$REPO_ROOT/scripts/generate-compare-html.sh"
CHECK_ROBOTS="$REPO_ROOT/scripts/check-robots.sh"
CHECK_SITEMAP="$REPO_ROOT/scripts/check-sitemap.sh"
CHECK_LLMSTXT="$REPO_ROOT/scripts/check-llmstxt.sh"
DIFF_RENDER="$REPO_ROOT/scripts/diff-render.sh"
EXTRACT_JSONLD="$REPO_ROOT/scripts/extract-jsonld.sh"
INSTALLER="$REPO_ROOT/bin/install.js"

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
TMP_FIXTURE=$(mktemp -d)
PORT=$(python3 - <<'EOF'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
EOF
)
cat > "$TMP_FIXTURE/index.html" <<'EOF'
<html><body>redirect shape fixture</body></html>
EOF
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$TMP_FIXTURE" >/dev/null 2>&1 &
SERVER_PID=$!
sleep 1
REDIRECT_TEST_OUT=$("$REPO_ROOT/scripts/fetch-as-bot.sh" "http://127.0.0.1:${PORT}/index.html" "$REPO_ROOT/profiles/googlebot.json" 2>/dev/null || echo '{}')
kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" 2>/dev/null || true
rm -rf "$TMP_FIXTURE"
REDIRECT_COUNT=$(printf '%s' "$REDIRECT_TEST_OUT" | jq -r '.redirectCount // "missing"')
FINAL_URL=$(printf '%s' "$REDIRECT_TEST_OUT" | jq -r '.finalUrl // "missing"')
REDIRECT_CHAIN=$(printf '%s' "$REDIRECT_TEST_OUT" | jq -r '.redirectChain // "missing"')
assert_eq "$REDIRECT_COUNT" "0" "redirectCount present for direct fetch"
if [ "$FINAL_URL" = "http://127.0.0.1:${PORT}/index.html" ]; then
  pass "finalUrl field present"
else
  fail "finalUrl field missing from fetch output"
fi
if [ "$REDIRECT_CHAIN" != "missing" ]; then
  pass "redirectChain field present"
else
  fail "redirectChain field missing from fetch output"
fi

case_begin "Fetch: file-backed body output replaces bodyBase64"
TMP_FIXTURE=$(mktemp -d)
FETCH_OUT_DIR=$(mktemp -d)
PORT=$(python3 - <<'EOF'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
EOF
)
cat > "$TMP_FIXTURE/index.html" <<'EOF'
<html><head><title>Fixture</title></head><body><h1>Hello bots</h1><p>This body lives on disk.</p></body></html>
EOF
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$TMP_FIXTURE" >/dev/null 2>&1 &
SERVER_PID=$!
sleep 1
if OUT=$("$REPO_ROOT/scripts/fetch-as-bot.sh" --out-dir "$FETCH_OUT_DIR" "http://127.0.0.1:${PORT}/index.html" "$REPO_ROOT/profiles/googlebot.json" 2>/dev/null); then
  BODY_FILE=$(printf '%s' "$OUT" | jq -r '.bodyFile // "missing"')
  BODY_BYTES=$(printf '%s' "$OUT" | jq -r '.bodyBytes // "missing"')
  HAS_BODY_BASE64=$(printf '%s' "$OUT" | jq 'has("bodyBase64")')
  if [ "$BODY_FILE" != "missing" ] && [ -f "$FETCH_OUT_DIR/$BODY_FILE" ]; then
    pass "bodyFile points to an on-disk HTML file"
    ACTUAL_BYTES=$(wc -c < "$FETCH_OUT_DIR/$BODY_FILE" | tr -d '[:space:]')
    assert_eq "$BODY_BYTES" "$ACTUAL_BYTES" "bodyBytes matches the saved HTML size"
  else
    fail "bodyFile missing or did not resolve under --out-dir"
  fi
  assert_ge "$BODY_BYTES" "1" "bodyBytes reports a non-empty fetch body"
  assert_eq "$HAS_BODY_BASE64" "false" "bodyBase64 field removed from fetch output"
else
  fail "fetch-as-bot.sh exited non-zero for file-backed body test"
fi
kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" 2>/dev/null || true
rm -rf "$TMP_FIXTURE" "$FETCH_OUT_DIR"

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
if REPORT=$("$BUILD_REPORT" "$SCRIPT_DIR/fixtures/root-minimal" 2>/dev/null); then
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

case_begin "Security: generated HTML report escapes attacker-controlled markup"
TMP_FIXTURE=$(mktemp -d)
cp "$SCRIPT_DIR/fixtures/root-minimal/"*.json "$TMP_FIXTURE/"
"$COMPUTE_SCORE" "$TMP_FIXTURE" > "$TMP_FIXTURE/score.json" 2>/dev/null
if "$BUILD_REPORT" "$TMP_FIXTURE" > "$TMP_FIXTURE/report.json" 2>/dev/null; then
  jq '.bots.googlebot.categories.structuredData.notes = "<script>alert(1)</script>"' \
    "$TMP_FIXTURE/report.json" > "$TMP_FIXTURE/malicious.json"
  if HTML=$("$GENERATE_REPORT_HTML" "$TMP_FIXTURE/malicious.json" 2>/dev/null); then
    assert_contains "$HTML" "&lt;script&gt;alert(1)&lt;/script&gt;" "report HTML escapes script payload"
    assert_not_contains "$HTML" "<script>alert(1)</script>" "report HTML omits raw injected script"
  else
    fail "generate-report-html.sh exited non-zero on malicious report fixture"
  fi
else
  fail "build-report.sh exited non-zero while preparing malicious report fixture"
fi
rm -rf "$TMP_FIXTURE"

case_begin "Report: generate-compare-html.sh succeeds on two valid reports"
TMP_FIXTURE=$(mktemp -d)
cp "$SCRIPT_DIR/fixtures/root-minimal/"*.json "$TMP_FIXTURE/"
"$COMPUTE_SCORE" "$TMP_FIXTURE" > "$TMP_FIXTURE/score.json" 2>/dev/null
if "$BUILD_REPORT" "$TMP_FIXTURE" > "$TMP_FIXTURE/a.json" 2>/dev/null; then
  cp "$TMP_FIXTURE/a.json" "$TMP_FIXTURE/b.json"
  if HTML=$("$GENERATE_COMPARE_HTML" "$TMP_FIXTURE/a.json" "$TMP_FIXTURE/b.json" 2>/dev/null); then
    assert_contains "$HTML" "Comparative Audit" "compare HTML includes page heading"
    assert_contains "$HTML" "googlebot" "compare HTML includes per-bot table rows"
  else
    fail "generate-compare-html.sh exited non-zero on two valid reports"
  fi
else
  fail "build-report.sh exited non-zero while preparing compare reports"
fi
rm -rf "$TMP_FIXTURE"

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

case_begin "Robots: check-robots.sh respects Disallow: / for matching paths"
TMP_FIXTURE=$(mktemp -d)
PORT=$(python3 - <<'EOF'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
EOF
)
cat > "$TMP_FIXTURE/robots.txt" <<'EOF'
User-agent: GPTBot
Disallow: /
EOF
cat > "$TMP_FIXTURE/index.html" <<'EOF'
hello
EOF
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$TMP_FIXTURE" >/dev/null 2>&1 &
SERVER_PID=$!
sleep 1
if OUT=$("$CHECK_ROBOTS" "http://127.0.0.1:${PORT}/index.html" "GPTBot" 2>/dev/null); then
  ALLOWED=$(printf '%s' "$OUT" | jq -r '.allowed')
  assert_eq "$ALLOWED" "false" "Disallow: / blocks a matching GPTBot fetch"
else
  fail "check-robots.sh exited non-zero against local robots fixture"
fi
kill "$SERVER_PID" >/dev/null 2>&1 || true
wait "$SERVER_PID" 2>/dev/null || true
rm -rf "$TMP_FIXTURE"

case_begin "AC-1: check-sitemap.sh follows redirects to canonical host"
TMP_FIXTURE=$(mktemp -d)
# Pick two free ports
PORT_A=$(python3 - <<'EOF'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
EOF
)
PORT_B=$(python3 - <<'EOF'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
EOF
)
# Port A redirects every request to Port B (simulates bare->www canonicalization)
cat > "$TMP_FIXTURE/redirect_server.py" <<PY
import http.server, socketserver, sys
PORT_A = int(sys.argv[1]); PORT_B = int(sys.argv[2])
class H(http.server.BaseHTTPRequestHandler):
  def do_GET(self): self._r()
  def do_HEAD(self): self._r()
  def _r(self):
    self.send_response(301)
    self.send_header('Location', f'http://127.0.0.1:{PORT_B}' + self.path)
    self.end_headers()
  def log_message(self, *a): pass
with socketserver.TCPServer(('127.0.0.1', PORT_A), H) as s: s.serve_forever()
PY
# Port B serves the actual sitemap
mkdir -p "$TMP_FIXTURE/b"
cat > "$TMP_FIXTURE/b/index.html" <<EOF
hello
EOF
cat > "$TMP_FIXTURE/b/sitemap.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>http://127.0.0.1:${PORT_B}/</loc></url>
</urlset>
EOF
python3 "$TMP_FIXTURE/redirect_server.py" "$PORT_A" "$PORT_B" >/dev/null 2>&1 &
REDIR_PID=$!
( cd "$TMP_FIXTURE/b" && python3 -m http.server "$PORT_B" --bind 127.0.0.1 ) >/dev/null 2>&1 &
SITEMAP_PID=$!
sleep 1
if OUT=$("$CHECK_SITEMAP" "http://127.0.0.1:${PORT_A}/" 2>/dev/null); then
  EXISTS=$(printf '%s' "$OUT" | jq -r '.exists')
  URL_COUNT=$(printf '%s' "$OUT" | jq -r '.urlCount')
  CONTAINS=$(printf '%s' "$OUT" | jq -r '.containsTarget')
  assert_eq "$EXISTS" "true" "sitemap discovered via canonical redirect"
  assert_ge "$URL_COUNT" "1" "urlCount > 0 after following canonical redirect"
  assert_eq "$CONTAINS" "true" "containsTarget true when canonical URL appears in sitemap"
else
  fail "check-sitemap.sh exited non-zero against redirecting host"
fi
kill "$REDIR_PID" "$SITEMAP_PID" >/dev/null 2>&1 || true
wait "$REDIR_PID" 2>/dev/null || true
wait "$SITEMAP_PID" 2>/dev/null || true
rm -rf "$TMP_FIXTURE"

case_begin "AC-2: check-robots.sh follows redirects to canonical host"
TMP_FIXTURE=$(mktemp -d)
PORT_A=$(python3 - <<'EOF'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
EOF
)
PORT_B=$(python3 - <<'EOF'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
EOF
)
cat > "$TMP_FIXTURE/redirect_server.py" <<PY
import http.server, socketserver, sys
PORT_A = int(sys.argv[1]); PORT_B = int(sys.argv[2])
class H(http.server.BaseHTTPRequestHandler):
  def do_GET(self): self._r()
  def do_HEAD(self): self._r()
  def _r(self):
    self.send_response(301)
    self.send_header('Location', f'http://127.0.0.1:{PORT_B}' + self.path)
    self.end_headers()
  def log_message(self, *a): pass
with socketserver.TCPServer(('127.0.0.1', PORT_A), H) as s: s.serve_forever()
PY
mkdir -p "$TMP_FIXTURE/b"
cat > "$TMP_FIXTURE/b/robots.txt" <<'EOF'
User-agent: GPTBot
Disallow: /
EOF
cat > "$TMP_FIXTURE/b/index.html" <<'EOF'
hello
EOF
python3 "$TMP_FIXTURE/redirect_server.py" "$PORT_A" "$PORT_B" >/dev/null 2>&1 &
REDIR_PID=$!
( cd "$TMP_FIXTURE/b" && python3 -m http.server "$PORT_B" --bind 127.0.0.1 ) >/dev/null 2>&1 &
ROBOTS_PID=$!
sleep 1
if OUT=$("$CHECK_ROBOTS" "http://127.0.0.1:${PORT_A}/index.html" "GPTBot" 2>/dev/null); then
  ALLOWED=$(printf '%s' "$OUT" | jq -r '.allowed')
  REPORTED_URL=$(printf '%s' "$OUT" | jq -r '.robotsUrl')
  assert_eq "$ALLOWED" "false" "robots.txt discovered via canonical redirect still blocks GPTBot"
  assert_contains "$REPORTED_URL" "127.0.0.1:${PORT_B}" "robotsUrl reports canonical origin, not raw input"
else
  fail "check-robots.sh exited non-zero against redirecting host"
fi
kill "$REDIR_PID" "$ROBOTS_PID" >/dev/null 2>&1 || true
wait "$REDIR_PID" 2>/dev/null || true
wait "$ROBOTS_PID" 2>/dev/null || true
rm -rf "$TMP_FIXTURE"

case_begin "AC-2: check-llmstxt.sh follows redirects to canonical host"
TMP_FIXTURE=$(mktemp -d)
PORT_A=$(python3 - <<'EOF'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
EOF
)
PORT_B=$(python3 - <<'EOF'
import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()
EOF
)
cat > "$TMP_FIXTURE/redirect_server.py" <<PY
import http.server, socketserver, sys
PORT_A = int(sys.argv[1]); PORT_B = int(sys.argv[2])
class H(http.server.BaseHTTPRequestHandler):
  def do_GET(self): self._r()
  def do_HEAD(self): self._r()
  def _r(self):
    self.send_response(301)
    self.send_header('Location', f'http://127.0.0.1:{PORT_B}' + self.path)
    self.end_headers()
  def log_message(self, *a): pass
with socketserver.TCPServer(('127.0.0.1', PORT_A), H) as s: s.serve_forever()
PY
mkdir -p "$TMP_FIXTURE/b"
cat > "$TMP_FIXTURE/b/llms.txt" <<'EOF'
# Example Site

> A short description of the site.

- [Home](http://127.0.0.1/)
EOF
cat > "$TMP_FIXTURE/b/index.html" <<'EOF'
hello
EOF
python3 "$TMP_FIXTURE/redirect_server.py" "$PORT_A" "$PORT_B" >/dev/null 2>&1 &
REDIR_PID=$!
( cd "$TMP_FIXTURE/b" && python3 -m http.server "$PORT_B" --bind 127.0.0.1 ) >/dev/null 2>&1 &
LLMS_PID=$!
sleep 1
if OUT=$("$CHECK_LLMSTXT" "http://127.0.0.1:${PORT_A}/" 2>/dev/null); then
  LLMS_EXISTS=$(printf '%s' "$OUT" | jq -r '.llmsTxt.exists')
  LLMS_URL=$(printf '%s' "$OUT" | jq -r '.llmsTxt.url')
  assert_eq "$LLMS_EXISTS" "true" "llms.txt discovered via canonical redirect"
  assert_contains "$LLMS_URL" "127.0.0.1:${PORT_B}" "llmsTxt.url reports canonical origin, not raw input"
else
  fail "check-llmstxt.sh exited non-zero against redirecting host"
fi
kill "$REDIR_PID" "$LLMS_PID" >/dev/null 2>&1 || true
wait "$REDIR_PID" 2>/dev/null || true
wait "$LLMS_PID" 2>/dev/null || true
rm -rf "$TMP_FIXTURE"

case_begin "Structured data: invalid @graph members trigger required-field violations"
TMP_FIXTURE=$(mktemp -d)
cp "$SCRIPT_DIR/fixtures/root-minimal/fetch-googlebot.json" "$TMP_FIXTURE/"
cp "$SCRIPT_DIR/fixtures/root-minimal/meta-googlebot.json" "$TMP_FIXTURE/"
cp "$SCRIPT_DIR/fixtures/root-minimal/links-googlebot.json" "$TMP_FIXTURE/"
cp "$SCRIPT_DIR/fixtures/root-minimal/robots-googlebot.json" "$TMP_FIXTURE/"
cp "$SCRIPT_DIR/fixtures/root-minimal/llmstxt.json" "$TMP_FIXTURE/"
cp "$SCRIPT_DIR/fixtures/root-minimal/sitemap.json" "$TMP_FIXTURE/"
cat > "$TMP_FIXTURE/graph.html" <<'EOF'
<html><head><script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"Organization","name":"Acme"},{"@type":"WebSite","name":"Acme"}]}</script></head><body><h1>Home</h1></body></html>
EOF
if "$EXTRACT_JSONLD" "$TMP_FIXTURE/graph.html" > "$TMP_FIXTURE/jsonld-googlebot.json" 2>/dev/null; then
  if OUT=$("$COMPUTE_SCORE" "$TMP_FIXTURE" 2>/dev/null); then
    FIELD_VIOLATIONS=$(printf '%s' "$OUT" | jq '[.bots.googlebot.categories.structuredData.violations[] | select(.kind=="missing_required_field")] | length')
    SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.score')
    assert_ge "$FIELD_VIOLATIONS" "2" "missing required-field violations emitted for @graph members"
    assert_lt "$SCORE" "100" "invalid @graph members reduce structured-data score"
  else
    fail "compute-score.sh exited non-zero on @graph fixture"
  fi
else
  fail "extract-jsonld.sh exited non-zero on @graph fixture"
fi
rm -rf "$TMP_FIXTURE"

case_begin "Install: Claude skill layout still works"
TMP_HOME=$(mktemp -d)
if printf 'n\n' | HOME="$TMP_HOME" node "$INSTALLER" install >/dev/null 2>&1; then
  CLAUDE_INSTALL="$TMP_HOME/.claude/skills/crawl-sim"
  if [ -f "$CLAUDE_INSTALL/SKILL.md" ] && [ -x "$CLAUDE_INSTALL/scripts/fetch-as-bot.sh" ] && [ -f "$CLAUDE_INSTALL/profiles/googlebot.json" ]; then
    pass "Claude install writes the expected skill files"
  else
    fail "Claude install missing SKILL.md, scripts, or profiles"
  fi
else
  fail "bin/install.js failed for Claude install"
fi
rm -rf "$TMP_HOME"

case_begin "Install: Codex plugin layout still works"
TMP_HOME=$(mktemp -d)
if printf 'n\n' | HOME="$TMP_HOME" node "$INSTALLER" install --codex >/dev/null 2>&1; then
  CODEX_PLUGIN="$TMP_HOME/plugins/crawl-sim"
  MARKETPLACE="$TMP_HOME/.agents/plugins/marketplace.json"
  HAS_ENTRY=$(jq -r '[.plugins[]? | select(.name=="crawl-sim")] | length' "$MARKETPLACE" 2>/dev/null || echo "0")
  if [ -f "$CODEX_PLUGIN/.codex-plugin/plugin.json" ] && [ -f "$CODEX_PLUGIN/skills/crawl-sim/SKILL.md" ]; then
    pass "Codex install writes the plugin and skill tree"
  else
    fail "Codex install missing plugin manifest or skill tree"
  fi
  assert_eq "$HAS_ENTRY" "1" "Codex install registers one local marketplace entry"
else
  fail "bin/install.js failed for Codex install"
fi
rm -rf "$TMP_HOME"

# ----- Summary -----

printf '\n================================================\n'
printf '  passed: %d   failed: %d\n' "$PASSED" "$FAILED"
printf '================================================\n'

[ "$FAILED" -eq 0 ]
