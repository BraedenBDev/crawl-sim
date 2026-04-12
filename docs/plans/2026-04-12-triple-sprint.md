# crawl-sim v1.2.0 — Triple Sprint Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the parallel-fetch correctness bug (#11), ship accuracy sprint 2 items C3+C4+H2+H3 (#12), and package crawl-sim as a Claude Code plugin for `/plugin install` distribution.

**Architecture:** Three independent workstreams that can run as separate branches or one combined feature branch. Sprint A (H1 bug) touches `fetch-as-bot.sh` + `compute-score.sh`. Sprint B (accuracy) touches `compute-score.sh` + `fetch-as-bot.sh` + `diff-render.sh`. Sprint C (plugin) is structural — adds `.claude-plugin/` directory and restructures into plugin layout. Sprint A should merge first since B's C4 depends on multi-bot fetch reliability.

**Tech Stack:** Bash (curl, jq), Node.js (bin/install.js), Claude Code plugin manifest (JSON)

---

## Sprint A: Fix `fetch-as-bot.sh` Parallel Failure (Issue #11)

**Why:** Under parallel invocation, fetch output files intermittently come back 0 bytes. Downstream scripts score phantom data. Reproduced twice. This is a correctness bug that blocks parallelizing fetches (#1) and makes every multi-bot audit unreliable.

**Root cause:** `set -euo pipefail` + `2>/dev/null` on the curl call + `|| echo '{...}'` fallback. Transient errors exit silently — no stderr, no diagnostic, no signal to caller.

### Task A1: Make curl errors produce a failure JSON instead of empty output

**Files:**
- Modify: `scripts/fetch-as-bot.sh:26-32` (the curl call and error path)
- Test: `test/run-scoring-tests.sh` (new assertions)
- Create: `test/fixtures/fetch-failed/fetch-googlebot.json`

- [ ] **Step 1: Create the fetch-failed fixture**

This fixture simulates what `fetch-as-bot.sh` should produce when curl fails. Create a minimal fixture directory with a `fetchFailed` JSON:

```bash
mkdir -p test/fixtures/fetch-failed
```

Write `test/fixtures/fetch-failed/fetch-googlebot.json`:
```json
{
  "url": "https://example.invalid/",
  "bot": {
    "id": "googlebot",
    "name": "Googlebot",
    "userAgent": "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
    "rendersJavaScript": true
  },
  "fetchFailed": true,
  "error": "curl: (6) Could not resolve host: example.invalid",
  "status": 0,
  "timing": { "total": 0, "ttfb": 0 },
  "size": 0,
  "wordCount": 0,
  "headers": {},
  "bodyBase64": ""
}
```

Also copy `meta-googlebot.json`, `jsonld-googlebot.json`, `links-googlebot.json`, `robots-googlebot.json`, `llmstxt.json`, `sitemap.json` from `root-minimal` into `fetch-failed` — these files represent a scenario where downstream extractors ran on empty data. Create minimal stubs:

Write `test/fixtures/fetch-failed/meta-googlebot.json`:
```json
{"title":"","description":"","canonical":"","og":{"title":"","description":""},"headings":{"h1":{"count":0},"h2":{"count":0}},"images":{"total":0,"withAlt":0}}
```

Write `test/fixtures/fetch-failed/jsonld-googlebot.json`:
```json
{"blockCount":0,"validCount":0,"invalidCount":0,"types":[]}
```

Write `test/fixtures/fetch-failed/links-googlebot.json`:
```json
{"counts":{"total":0,"internal":0,"external":0}}
```

Write `test/fixtures/fetch-failed/robots-googlebot.json`:
```json
{"allowed":true}
```

Write `test/fixtures/fetch-failed/llmstxt.json`:
```json
{"url":"https://example.invalid/","llmsTxt":{"exists":false},"llmsFullTxt":{"exists":false}}
```

Write `test/fixtures/fetch-failed/sitemap.json`:
```json
{"url":"https://example.invalid/sitemap.xml","exists":false,"containsTarget":false}
```

- [ ] **Step 2: Add regression tests for fetchFailed handling**

Append to `test/run-scoring-tests.sh` before the summary section:

```bash
# ----- fetchFailed handling (Issue #11) -----

case_begin "H1: compute-score.sh handles fetchFailed: true gracefully"
if OUT=$(run_score fetch-failed 2>/dev/null); then
  BOT_SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.score')
  BOT_GRADE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.grade')
  FETCH_FAILED=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.fetchFailed // false')
  assert_eq "$FETCH_FAILED" "true" "bot-level fetchFailed flag propagated"
  assert_eq "$BOT_SCORE" "0" "fetchFailed bot scores 0"
  assert_eq "$BOT_GRADE" "F" "fetchFailed bot grades F"
else
  fail "compute-score.sh exited non-zero on fetch-failed fixture"
fi
```

- [ ] **Step 3: Run tests — verify they fail**

Run: `npm test`
Expected: New tests fail because `compute-score.sh` doesn't handle `fetchFailed` yet and because `fetch-failed` fixture doesn't exist yet.

- [ ] **Step 4: Fix `fetch-as-bot.sh` — replace silent curl error handling**

In `scripts/fetch-as-bot.sh`, replace the curl call block (lines 26-32):

Old:
```bash
TIMING=$(curl -sS -L \
  -H "User-Agent: $UA" \
  -D "$HEADERS_FILE" \
  -o "$BODY_FILE" \
  -w '{"total":%{time_total},"ttfb":%{time_starttransfer},"connect":%{time_connect},"statusCode":%{http_code},"sizeDownload":%{size_download}}' \
  --max-time 30 \
  "$URL" 2>/dev/null || echo '{"total":0,"ttfb":0,"connect":0,"statusCode":0,"sizeDownload":0}')
```

New:
```bash
CURL_STDERR_FILE=$(mktemp "$TMPDIR/crawlsim-stderr.XXXXXX")
trap 'rm -f "$HEADERS_FILE" "$BODY_FILE" "$CURL_STDERR_FILE"' EXIT

printf '[%s] fetching %s\n' "$BOT_ID" "$URL" >&2

set +e
TIMING=$(curl -sS -L \
  -H "User-Agent: $UA" \
  -D "$HEADERS_FILE" \
  -o "$BODY_FILE" \
  -w '{"total":%{time_total},"ttfb":%{time_starttransfer},"connect":%{time_connect},"statusCode":%{http_code},"sizeDownload":%{size_download}}' \
  --max-time 30 \
  "$URL" 2>"$CURL_STDERR_FILE")
CURL_EXIT=$?
set -e

CURL_ERR=""
if [ -s "$CURL_STDERR_FILE" ]; then
  CURL_ERR=$(cat "$CURL_STDERR_FILE")
fi

if [ "$CURL_EXIT" -ne 0 ]; then
  printf '[%s] FAILED: curl exit %d — %s\n' "$BOT_ID" "$CURL_EXIT" "$CURL_ERR" >&2
  jq -n \
    --arg url "$URL" \
    --arg botId "$BOT_ID" \
    --arg botName "$BOT_NAME" \
    --arg ua "$UA" \
    --arg rendersJs "$RENDERS_JS" \
    --arg error "$CURL_ERR" \
    --argjson exitCode "$CURL_EXIT" \
    '{
      url: $url,
      bot: {
        id: $botId,
        name: $botName,
        userAgent: $ua,
        rendersJavaScript: (if $rendersJs == "true" then true elif $rendersJs == "false" then false else $rendersJs end)
      },
      fetchFailed: true,
      error: $error,
      curlExitCode: $exitCode,
      status: 0,
      timing: { total: 0, ttfb: 0 },
      size: 0,
      wordCount: 0,
      headers: {},
      bodyBase64: ""
    }'
  exit 0
fi
```

Also update the existing trap line (line 24) to include the new temp file:
```bash
# Remove old trap line, the new one above covers it
```

And add a success progress line after the existing processing, before the final `jq -n` output (around line 60):
```bash
printf '[%s] ok: status=%s size=%s words=%s time=%ss\n' "$BOT_ID" "$STATUS" "$SIZE" "$WORD_COUNT" "$TOTAL_TIME" >&2
```

- [ ] **Step 5: Make `compute-score.sh` handle `fetchFailed` bots**

In `scripts/compute-score.sh`, add a check at the top of the per-bot loop (after line 272, inside `for bot_id in $BOTS`):

```bash
  # Check for fetch failure — skip scoring, emit F grade
  FETCH_FAILED=$(jget_bool "$FETCH" '.fetchFailed')
  if [ "$FETCH_FAILED" = "true" ]; then
    FETCH_ERROR=$(jget "$FETCH" '.error' "unknown error")
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
    continue
  fi
```

- [ ] **Step 6: Run tests — verify they pass**

Run: `npm test`
Expected: All tests pass, including the new `fetchFailed` assertions.

- [ ] **Step 7: Live test — verify parallel fetch no longer produces 0-byte files**

```bash
SKILL_DIR="$HOME/.claude/skills/crawl-sim"
RUN_DIR=$(mktemp -d -t crawl-sim-parallel-test.XXXXXX)
URL="https://www.almostimpossible.agency/"
for bot in googlebot gptbot claudebot perplexitybot; do
  "$SKILL_DIR/scripts/fetch-as-bot.sh" "$URL" "$SKILL_DIR/profiles/${bot}.json" > "$RUN_DIR/fetch-${bot}.json" &
done
wait
wc -c "$RUN_DIR"/fetch-*.json
```

Expected: All four files should be >0 bytes. Stderr should show `[botId] fetching ...` and `[botId] ok: ...` lines for each bot.

Run this 5 times to check for intermittent failures.

- [ ] **Step 8: Commit**

```bash
git add scripts/fetch-as-bot.sh scripts/compute-score.sh test/run-scoring-tests.sh test/fixtures/fetch-failed/
git commit -m "fix: handle curl failures gracefully in fetch-as-bot.sh (closes #11)

- Replace 2>/dev/null with explicit stderr capture
- Emit [botId] progress lines to stderr for parallel visibility
- Output fetchFailed JSON instead of 0-byte file on curl error
- compute-score.sh treats fetchFailed bots as grade F
- New test fixture + regression assertions

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Sprint B: Accuracy Sprint 2 — C3, C4, H2, H3 (Issue #12)

**Why:** Sprint 1 shipped page-type rubrics and self-explaining scores. Sprint 2 adds field-level validation (C3), cross-bot parity scoring (C4), diff-render warning surfacing (H2), and redirect chain capture (H3). Together these close the gap between "data is correct" and "narrative is trustworthy."

### Task B1: C3 — Reward correctness over presence (schema field validation)

**Files:**
- Modify: `scripts/compute-score.sh` (structured data scoring block)
- Create: `scripts/schema-fields.sh` (required-field definitions per schema type)
- Modify: `test/run-scoring-tests.sh` (new assertions)
- Create: `test/fixtures/root-invalid-fields/` (fixture with present-but-broken schemas)

- [ ] **Step 1: Create `scripts/schema-fields.sh` — required fields per schema.org type**

```bash
#!/usr/bin/env bash
# schema-fields.sh — Required field definitions per schema.org type.
# Usage: source this file, then call required_fields_for <SchemaType>

required_fields_for() {
  case "$1" in
    Organization)       echo "name url" ;;
    WebSite)            echo "name url" ;;
    Article)            echo "headline author datePublished" ;;
    NewsArticle)        echo "headline author datePublished" ;;
    FAQPage)            echo "mainEntity" ;;
    BreadcrumbList)     echo "itemListElement" ;;
    CollectionPage)     echo "name" ;;
    ItemList)           echo "itemListElement" ;;
    AboutPage)          echo "name" ;;
    ContactPage)        echo "name" ;;
    Product)            echo "name" ;;
    LocalBusiness)      echo "name address" ;;
    ProfessionalService) echo "name" ;;
    Person)             echo "name" ;;
    ImageObject)        echo "contentUrl" ;;
    PostalAddress)      echo "streetAddress" ;;
    *)                  echo "" ;;
  esac
}
```

- [ ] **Step 2: Create the `root-invalid-fields` fixture**

This fixture has Organization + WebSite schemas that are present but missing required fields (no `name`, no `url`).

```bash
mkdir -p test/fixtures/root-invalid-fields
```

Write `test/fixtures/root-invalid-fields/fetch-googlebot.json`:
```json
{
  "url": "https://example.com/",
  "bot": { "id": "googlebot", "name": "Googlebot", "userAgent": "Googlebot/2.1", "rendersJavaScript": true },
  "status": 200, "timing": { "total": 0.5, "ttfb": 0.2 }, "size": 50000, "wordCount": 500, "headers": {}, "bodyBase64": ""
}
```

Write `test/fixtures/root-invalid-fields/jsonld-googlebot.json`:
```json
{
  "blockCount": 2,
  "validCount": 2,
  "invalidCount": 0,
  "types": ["Organization", "WebSite"],
  "blocks": [
    { "type": "Organization", "fields": ["@context", "@type"] },
    { "type": "WebSite", "fields": ["@context", "@type"] }
  ]
}
```

Note: The `blocks[].fields` array is a new contract — `extract-jsonld.sh` will need to emit field names per block (Task B1 Step 5).

Copy remaining fixture files from `root-minimal` (meta, links, robots, llmstxt, sitemap).

```bash
for f in meta-googlebot.json links-googlebot.json robots-googlebot.json llmstxt.json sitemap.json; do
  cp test/fixtures/root-minimal/$f test/fixtures/root-invalid-fields/$f
done
```

- [ ] **Step 3: Add tests for field-level validation**

Append to `test/run-scoring-tests.sh`:

```bash
# ----- C3: field-level validation -----

case_begin "C3: schemas present but missing required fields get validity penalty"
if OUT=$(run_score root-invalid-fields 2>/dev/null); then
  SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.score')
  VIOLATIONS=$(printf '%s' "$OUT" | jq '[.bots.googlebot.categories.structuredData.violations[] | select(.kind=="missing_required_field")] | length')
  assert_lt "$SCORE" "100" "missing required fields reduce score below 100"
  assert_ge "$VIOLATIONS" "1" "at least one missing_required_field violation"
else
  fail "compute-score.sh exited non-zero on root-invalid-fields"
fi
```

- [ ] **Step 4: Run tests — verify they fail**

Run: `npm test`
Expected: New C3 tests fail.

- [ ] **Step 5: Modify `scripts/extract-jsonld.sh` to emit field names per block**

Add a `blocks` array to the output that lists the top-level field names of each JSON-LD block. This gives `compute-score.sh` the data it needs for field validation without parsing the full block again.

In `extract-jsonld.sh`, update the final jq output to include:
```json
"blocks": [{ "type": "Organization", "fields": ["@context", "@type", "name", "url", "logo"] }]
```

The implementation: after extracting each JSON-LD block, capture its top-level keys.

- [ ] **Step 6: Add field validation to `compute-score.sh`**

After the existing structured data scoring block (around line 380), source the new schema-fields helper and validate:

```bash
# Source field definitions
. "$SCRIPT_DIR/schema-fields.sh"

# Field-level validation (C3): check required fields per schema type
FIELD_VIOLATIONS=""
FIELD_PENALTY=0
if [ -f "$JSONLD" ]; then
  BLOCK_COUNT=$(jq '.blocks | length' "$JSONLD" 2>/dev/null || echo "0")
  i=0
  while [ "$i" -lt "$BLOCK_COUNT" ]; do
    BLOCK_TYPE=$(jq -r ".blocks[$i].type" "$JSONLD" 2>/dev/null || echo "")
    BLOCK_FIELDS=$(jq -r ".blocks[$i].fields[]?" "$JSONLD" 2>/dev/null | tr '\n' ' ')
    REQUIRED=$(required_fields_for "$BLOCK_TYPE")
    for field in $REQUIRED; do
      if ! printf '%s' " $BLOCK_FIELDS " | grep -q " $field "; then
        FIELD_VIOLATIONS="$FIELD_VIOLATIONS {\"kind\":\"missing_required_field\",\"schema\":\"$BLOCK_TYPE\",\"field\":\"$field\",\"impact\":-5}"
        FIELD_PENALTY=$((FIELD_PENALTY + 5))
      fi
    done
    i=$((i + 1))
  done
fi
[ $FIELD_PENALTY -gt 30 ] && FIELD_PENALTY=30

STRUCTURED=$((STRUCTURED - FIELD_PENALTY))
[ $STRUCTURED -lt 0 ] && STRUCTURED=0
```

Merge field violations into the existing `violations` array in the STRUCTURED_OBJ jq call.

- [ ] **Step 7: Run tests — verify they pass**

Run: `npm test`
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add scripts/schema-fields.sh scripts/compute-score.sh scripts/extract-jsonld.sh test/
git commit -m "feat: C3 — validate required fields per schema type, penalize broken schemas

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task B2: C4 — Cross-bot parity signal as a scoring category

**Files:**
- Modify: `scripts/compute-score.sh` (add parity calculation after per-bot loop)
- Modify: `test/run-scoring-tests.sh` (new assertions)
- Create: `test/fixtures/parity-mismatch/` (fixture with divergent bot word counts)

- [ ] **Step 1: Create the parity-mismatch fixture**

A fixture with two bots: `googlebot` sees 1000 words (rendersJS=true), `gptbot` sees 100 words (rendersJS=false). This simulates a CSR site.

```bash
mkdir -p test/fixtures/parity-mismatch
```

Write `test/fixtures/parity-mismatch/fetch-googlebot.json`:
```json
{
  "url": "https://example.com/",
  "bot": { "id": "googlebot", "name": "Googlebot", "userAgent": "Googlebot/2.1", "rendersJavaScript": true },
  "status": 200, "timing": { "total": 1.2, "ttfb": 0.3 }, "size": 100000, "wordCount": 1000, "headers": {}, "bodyBase64": ""
}
```

Write `test/fixtures/parity-mismatch/fetch-gptbot.json`:
```json
{
  "url": "https://example.com/",
  "bot": { "id": "gptbot", "name": "GPTBot", "userAgent": "GPTBot/1.2", "rendersJavaScript": false },
  "status": 200, "timing": { "total": 1.0, "ttfb": 0.2 }, "size": 10000, "wordCount": 100, "headers": {}, "bodyBase64": ""
}
```

Create stub versions of meta, jsonld, links, robots for both bots, plus llmstxt and sitemap (copy from root-minimal but create gptbot variants too).

- [ ] **Step 2: Add parity tests**

```bash
case_begin "C4: cross-bot parity — high divergence produces low parity score"
if OUT=$(run_score parity-mismatch 2>/dev/null); then
  PARITY_SCORE=$(printf '%s' "$OUT" | jq -r '.parity.score')
  PARITY_MAX_DELTA=$(printf '%s' "$OUT" | jq -r '.parity.maxDeltaPct')
  assert_lt "$PARITY_SCORE" "50" "parity score below 50 when 10x word count difference"
  assert_ge "$PARITY_MAX_DELTA" "80" "maxDeltaPct reflects 90% content difference"
else
  fail "compute-score.sh exited non-zero on parity-mismatch"
fi

case_begin "C4: cross-bot parity — identical content produces parity 100"
if OUT=$(run_score root-minimal 2>/dev/null); then
  PARITY_SCORE=$(printf '%s' "$OUT" | jq -r '.parity.score')
  assert_eq "$PARITY_SCORE" "100" "single-bot fixture has perfect parity"
else
  fail "compute-score.sh exited non-zero on root-minimal for parity"
fi
```

- [ ] **Step 3: Run tests — verify they fail**

Run: `npm test`

- [ ] **Step 4: Add parity computation to `compute-score.sh`**

After the per-bot loop ends (after line 548), add parity calculation:

```bash
# --- Cross-bot content parity (C4) ---
MIN_WORDS=999999999
MAX_WORDS=0
for bot_id in $BOTS; do
  FETCH="$RESULTS_DIR/fetch-$bot_id.json"
  FETCH_FAILED=$(jget_bool "$FETCH" '.fetchFailed')
  [ "$FETCH_FAILED" = "true" ] && continue
  WC=$(jget_num "$FETCH" '.wordCount')
  [ "$WC" -lt "$MIN_WORDS" ] && MIN_WORDS=$WC
  [ "$WC" -gt "$MAX_WORDS" ] && MAX_WORDS=$WC
done

if [ "$MAX_WORDS" -gt 0 ] && [ "$MIN_WORDS" -lt 999999999 ]; then
  PARITY_SCORE=$(awk -v min="$MIN_WORDS" -v max="$MAX_WORDS" \
    'BEGIN { if (max == 0) print 100; else printf "%d", (min / max) * 100 + 0.5 }')
  MAX_DELTA_PCT=$(awk -v min="$MIN_WORDS" -v max="$MAX_WORDS" \
    'BEGIN { if (max == 0) print 0; else printf "%d", ((max - min) / max) * 100 + 0.5 }')
else
  PARITY_SCORE=100
  MAX_DELTA_PCT=0
fi

[ "$PARITY_SCORE" -gt 100 ] && PARITY_SCORE=100
PARITY_GRADE=$(grade_for "$PARITY_SCORE")

if [ "$PARITY_SCORE" -ge 95 ]; then
  PARITY_INTERP="Content is consistent across all bots."
elif [ "$PARITY_SCORE" -ge 50 ]; then
  PARITY_INTERP="Moderate content divergence between bots — likely partial CSR hydration."
else
  PARITY_INTERP="Severe content divergence — site likely relies on client-side rendering. AI bots see significantly less content than Googlebot."
fi
```

Add a `parity` object to the final jq output:

```bash
  --argjson parityScore "$PARITY_SCORE" \
  --arg parityGrade "$PARITY_GRADE" \
  --argjson parityMinWords "$MIN_WORDS" \
  --argjson parityMaxWords "$MAX_WORDS" \
  --argjson parityMaxDelta "$MAX_DELTA_PCT" \
  --arg parityInterp "$PARITY_INTERP" \
```

Add to the output JSON:
```json
  "parity": {
    "score": $parityScore,
    "grade": $parityGrade,
    "minWords": $parityMinWords,
    "maxWords": $parityMaxWords,
    "maxDeltaPct": $parityMaxDelta,
    "interpretation": $parityInterp
  }
```

- [ ] **Step 5: Run tests — verify they pass**

Run: `npm test`

- [ ] **Step 6: Commit**

```bash
git add scripts/compute-score.sh test/
git commit -m "feat: C4 — cross-bot parity scoring category

Computes content parity across bots based on word count divergence.
Perfect parity (95%+) = 100/A, severe CSR mismatch = F.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task B3: H2 — `diff-render.sh` skip-warning surfacing

**Files:**
- Modify: `scripts/compute-score.sh` (add `warnings` array to output)
- Modify: `test/run-scoring-tests.sh`

- [ ] **Step 1: Add test for diff-render skip warning**

```bash
case_begin "H2: missing diff-render.json emits a warning"
if OUT=$(run_score root-minimal 2>/dev/null); then
  WARN_COUNT=$(printf '%s' "$OUT" | jq '[.warnings[]? | select(.code=="diff_render_unavailable")] | length')
  assert_eq "$WARN_COUNT" "1" "warning emitted when diff-render.json is absent"
else
  fail "compute-score.sh exited non-zero on root-minimal"
fi
```

- [ ] **Step 2: Run test — verify it fails**

Run: `npm test`

- [ ] **Step 3: Add `warnings` array to `compute-score.sh` output**

Before the final jq output, build a warnings array:

```bash
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
```

Add `--argjson warnings "$WARNINGS"` to the final jq call and include `warnings: $warnings` in the output object.

- [ ] **Step 4: Run tests — verify they pass**

Run: `npm test`

- [ ] **Step 5: Commit**

```bash
git add scripts/compute-score.sh test/run-scoring-tests.sh
git commit -m "feat: H2 — surface diff-render skip as a warning in score output

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task B4: H3 — Redirect chain capture in fetch output

**Files:**
- Modify: `scripts/fetch-as-bot.sh` (capture redirect chain from headers dump)
- Modify: `test/run-scoring-tests.sh`

- [ ] **Step 1: Add test for redirect chain fields**

The `root-minimal` fixture should have `redirectCount: 0` and `redirectChain: []` in its fetch JSON. First, update the fixture:

```bash
case_begin "H3: fetch output includes redirect fields"
# Use root-minimal which has a direct fetch (no redirect)
if OUT=$(run_score root-minimal 2>/dev/null); then
  # These fields come from the fetch file, not compute-score.sh
  # We test them via reading the fixture directly
  REDIRECT_COUNT=$(jq -r '.redirectCount // "missing"' test/fixtures/root-minimal/fetch-googlebot.json)
  assert_eq "$REDIRECT_COUNT" "0" "redirectCount present in fetch output"
else
  fail "compute-score.sh exited non-zero"
fi
```

- [ ] **Step 2: Run test — verify it fails**

- [ ] **Step 3: Add redirect chain capture to `fetch-as-bot.sh`**

After curl completes successfully, parse the headers dump for redirect hops. The `-D` dump file contains multiple HTTP response blocks when redirects occur — each block starts with `HTTP/`.

Add to the curl `-w` format string:
```
,"redirectCount":%{num_redirects},"finalUrl":"%{url_effective}"
```

After the headers parsing, build the redirect chain from the dump file:

```bash
# Parse redirect chain from headers dump
# Each HTTP/ line starts a new response block
REDIRECT_COUNT=$(echo "$TIMING" | jq -r '.redirectCount')
FINAL_URL=$(echo "$TIMING" | jq -r '.finalUrl')

REDIRECT_CHAIN="[]"
if [ "$REDIRECT_COUNT" -gt 0 ]; then
  # Extract status + location from each response block
  REDIRECT_CHAIN=$(awk '
    /^HTTP\// { status=$2; url="" }
    /^[Ll]ocation:/ { gsub(/\r/, ""); url=$2 }
    /^$/ && status { if (url) printf "%s %s\n", status, url; status="" }
  ' "$HEADERS_FILE" | jq -Rs '
    split("\n") | map(select(length > 0)) |
    to_entries | map({
      hop: .key,
      status: (.value | split(" ")[0] | tonumber),
      location: (.value | split(" ")[1:] | join(" "))
    })
  ')
fi
```

Add to the final jq output:
```bash
  --argjson redirectCount "$REDIRECT_COUNT" \
  --arg finalUrl "$FINAL_URL" \
  --argjson redirectChain "$REDIRECT_CHAIN" \
```

And include in the JSON:
```json
  "redirectCount": $redirectCount,
  "finalUrl": $finalUrl,
  "redirectChain": $redirectChain,
```

- [ ] **Step 4: Update fixture files to include new fields**

Add `"redirectCount": 0, "finalUrl": "https://example.com/", "redirectChain": []` to all existing `fetch-*.json` fixture files so existing tests don't break.

- [ ] **Step 5: Run tests — verify they pass**

Run: `npm test`

- [ ] **Step 6: Commit**

```bash
git add scripts/fetch-as-bot.sh test/
git commit -m "feat: H3 — capture redirect chain in fetch-as-bot.sh output

Adds redirectCount, finalUrl, and redirectChain[] to fetch JSON.
Parsed from curl's header dump file.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Sprint C: Plugin Packaging for Claude Code Distribution

**Why:** crawl-sim currently installs via `npm install -g @braedenbuilds/crawl-sim && crawl-sim install`. The Claude Code plugin system lets users install with `/plugin install crawl-sim@github` or through a marketplace. Plugin distribution is the native path — npm remains available but isn't the primary UX for Claude Code users.

**Distribution model from research:**

| Method | Command | What it needs in repo |
|--------|---------|----------------------|
| Direct GitHub | `/plugin install BraedenBDev/crawl-sim@github` | `.claude-plugin/plugin.json` + `skills/crawl-sim/SKILL.md` |
| Own marketplace | `/plugin marketplace add BraedenBDev/crawl-sim` then `/plugin install crawl-sim@crawl-sim` | Above + `.claude-plugin/marketplace.json` |
| Third-party marketplace | `/plugin install crawl-sim@some-marketplace` | Submit to marketplace repo |
| npm | `/plugin install @braedenbuilds/crawl-sim@npm` | `plugin.json` in npm package |

**Decision: direct GitHub install + own marketplace.** Keeps distribution under Braeden's control. Third-party marketplaces can reference the GitHub repo later.

### Task C1: Add plugin manifest and restructure for plugin layout

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `skills/crawl-sim/SKILL.md` (moved from root, root becomes symlink)
- Restructure: `scripts/` and `profiles/` move under `skills/crawl-sim/`
- Modify: `bin/install.js` (update source paths)
- Modify: `package.json` (update `files` array)

- [ ] **Step 1: Create the plugin manifest**

Write `.claude-plugin/plugin.json`:
```json
{
  "name": "crawl-sim",
  "version": "1.2.0",
  "description": "Multi-bot web crawler simulator — audit how Googlebot, GPTBot, ClaudeBot, and PerplexityBot see your site",
  "author": {
    "name": "BraedenBDev",
    "url": "https://github.com/BraedenBDev"
  },
  "homepage": "https://github.com/BraedenBDev/crawl-sim#readme",
  "repository": "https://github.com/BraedenBDev/crawl-sim",
  "license": "MIT",
  "keywords": ["seo", "crawler", "ai-visibility", "claude-code-skill", "googlebot", "gptbot"]
}
```

- [ ] **Step 2: Create the marketplace manifest**

Write `.claude-plugin/marketplace.json`:
```json
{
  "name": "crawl-sim",
  "owner": {
    "name": "BraedenBDev",
    "email": "braeden@braedenbuilds.com"
  },
  "plugins": [
    {
      "name": "crawl-sim",
      "source": "./",
      "description": "Multi-bot web crawler simulator — audit how Googlebot, GPTBot, ClaudeBot, and PerplexityBot see your site",
      "version": "1.2.0"
    }
  ]
}
```

- [ ] **Step 3: Create the `skills/crawl-sim/` directory structure**

The plugin auto-discovery expects `skills/<name>/SKILL.md`. The SKILL.md references `$SKILL_DIR/scripts/` and `$SKILL_DIR/profiles/`. For the plugin layout, scripts and profiles need to live alongside the SKILL.md so that `$SKILL_DIR` resolves correctly.

```bash
mkdir -p skills/crawl-sim
```

Move the core files:
```bash
git mv SKILL.md skills/crawl-sim/SKILL.md
git mv scripts skills/crawl-sim/scripts
git mv profiles skills/crawl-sim/profiles
```

Create root-level symlinks so existing npm installs and the test harness still work:
```bash
ln -s skills/crawl-sim/SKILL.md SKILL.md
ln -s skills/crawl-sim/scripts scripts
ln -s skills/crawl-sim/profiles profiles
```

- [ ] **Step 4: Update `bin/install.js` source paths**

In `bin/install.js`, update `SKILL_FILES` and `SKILL_DIRS` to look under the new location:

```javascript
const SKILL_ROOT = path.resolve(__dirname, '..', 'skills', 'crawl-sim');
const SKILL_FILES = [path.join(SKILL_ROOT, 'SKILL.md')];
const SKILL_DIRS = [
  { src: path.join(SKILL_ROOT, 'profiles'), name: 'profiles' },
  { src: path.join(SKILL_ROOT, 'scripts'), name: 'scripts' }
];
```

Update the `install()` function to use the new structure. The SKILL.md copies to `target/SKILL.md`, scripts to `target/scripts/`, profiles to `target/profiles/`.

- [ ] **Step 5: Update `package.json` files array**

```json
"files": [
  "bin/",
  "skills/",
  ".claude-plugin/",
  "SKILL.md",
  "profiles",
  "scripts",
  "README.md",
  "LICENSE"
]
```

Note: symlinks are included so npm consumers still see the expected structure.

- [ ] **Step 6: Update SKILL.md skill-directory resolution**

The SKILL.md already has guidance at line 43: "Use `$CLAUDE_PLUGIN_ROOT` if set, otherwise find the directory containing this `SKILL.md`." Update the Stage 1 bash block to prefer `$CLAUDE_PLUGIN_ROOT`:

```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  SKILL_DIR="$CLAUDE_PLUGIN_ROOT/skills/crawl-sim"
elif [ -d "$HOME/.claude/skills/crawl-sim" ]; then
  SKILL_DIR="$HOME/.claude/skills/crawl-sim"
elif [ -d ".claude/skills/crawl-sim" ]; then
  SKILL_DIR=".claude/skills/crawl-sim"
else
  echo "ERROR: cannot find crawl-sim skill directory" >&2
  exit 1
fi
```

- [ ] **Step 7: Update test harness paths**

In `test/run-scoring-tests.sh`, the `COMPUTE_SCORE` and `_lib.sh` references need to follow the new structure:

```bash
COMPUTE_SCORE="$REPO_ROOT/skills/crawl-sim/scripts/compute-score.sh"
```

And the `_lib.sh` source:
```bash
. "$REPO_ROOT/skills/crawl-sim/scripts/_lib.sh"
```

However, if symlinks are in place, the existing paths (`$REPO_ROOT/scripts/compute-score.sh`) will still work. Prefer using the canonical path through the symlink for now — update to the direct path if symlinks are ever removed.

- [ ] **Step 8: Verify everything works**

```bash
# Tests still pass through symlinks
npm test

# Plugin validates (if claude CLI available)
# /plugin validate .

# npm pack shows correct files
npm pack --dry-run 2>&1 | head -30
```

- [ ] **Step 9: Update README with plugin install instructions**

Add a "Plugin Install" section to `README.md` above or alongside the existing npm install section:

```markdown
## Install

### Claude Code Plugin (recommended)

```
/plugin install BraedenBDev/crawl-sim@github
```

Or add as a marketplace:
```
/plugin marketplace add BraedenBDev/crawl-sim
/plugin install crawl-sim@crawl-sim
```

### npm (alternative)

```bash
npm install -g @braedenbuilds/crawl-sim
crawl-sim install
```
```

- [ ] **Step 10: Commit**

```bash
git add .claude-plugin/ skills/ SKILL.md scripts profiles bin/install.js package.json README.md test/
git commit -m "feat: package crawl-sim as a Claude Code plugin

- Add .claude-plugin/plugin.json manifest
- Add .claude-plugin/marketplace.json for marketplace distribution
- Move SKILL.md + scripts + profiles into skills/crawl-sim/
- Root-level symlinks preserve npm + test compat
- SKILL.md prefers \$CLAUDE_PLUGIN_ROOT when available
- README documents /plugin install path

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Version bump and release

After all three sprints merge:

- [ ] **Bump `package.json` to 1.2.0**
- [ ] **Bump `.claude-plugin/plugin.json` to 1.2.0**
- [ ] **Bump `.claude-plugin/marketplace.json` to 1.2.0**
- [ ] **Update CHANGELOG / release notes:**
  - Fix: `fetch-as-bot.sh` no longer silently fails under parallel invocation (#11)
  - Feat: C3 — schema field validation penalizes present-but-broken schemas
  - Feat: C4 — cross-bot parity score as a new output section
  - Feat: H2 — diff-render skip produces a visible warning
  - Feat: H3 — redirect chain captured in fetch output
  - Feat: Plugin distribution — install via `/plugin install BraedenBDev/crawl-sim@github`
- [ ] **Tag `v1.2.0`, push, let CI publish to npm**
- [ ] **Test plugin install from a clean machine:**
  ```
  /plugin install BraedenBDev/crawl-sim@github
  /crawl-sim https://www.almostimpossible.agency/
  ```

---

## Dependency order

```
Sprint A (#11 fix) ──→ can merge independently
Sprint B (C3,C4,H2,H3) ──→ depends on A for reliable multi-bot fixtures
Sprint C (plugin) ──→ can run in parallel with A+B, merge last
```

Recommended: A first, then B, then C. Or A+C in parallel, then B.
