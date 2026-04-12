# Quick Wins + Sprint 3 + Sprint 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship all remaining accuracy items from the handoff doc — CI fix, parallel fetches, jq batching, 5 polish items (M1–M5), and 3 roadmap items (R2–R4) — taking crawl-sim from v1.2.0 to v1.3.0.

**Architecture:** 11 independent tasks grouped into 3 waves. Wave 1 (quick wins) has zero cross-dependencies. Wave 2 (M1–M5) touches individual scripts with no shared state. Wave 3 (R2–R4) modifies `compute-score.sh` scoring logic and SKILL.md narrative guidance. Each task is self-contained and can be committed independently.

**Tech Stack:** Bash (curl, jq, awk), GitHub Actions YAML, Node.js (bin/install.js)

---

## File Map

| File | Tasks | Change |
|------|-------|--------|
| `.github/workflows/publish.yml` | 1 | Bump actions to v5 |
| `skills/crawl-sim/SKILL.md` | 2 | Parallelize Stage 1 fetch loop |
| `skills/crawl-sim/scripts/compute-score.sh` | 3, 10, 11 | Batch jq reads; critical-fail logic; R2 confidence |
| `skills/crawl-sim/scripts/check-llmstxt.sh` | 4 | Add top-level `exists` field |
| `skills/crawl-sim/scripts/check-sitemap.sh` | 5 | Add `sampleUrls` array |
| `skills/crawl-sim/scripts/extract-links.sh` | 6 | Flatten output schema |
| `skills/crawl-sim/SKILL.md` | 8, 9 | Narrative guidance for M5 consolidated report, R3 parity collapse |
| `skills/crawl-sim/scripts/build-report.sh` | 8 | New — consolidate all JSON into one report |
| `test/run-scoring-tests.sh` | 3, 4, 5, 6, 8, 10, 11 | New assertions for each feature |
| `test/fixtures/*` | 3, 6, 10, 11 | Updated/new fixture files |
| `docs/output-schemas.md` | 7 | New — document every script's JSON contract |

---

## Wave 1 — Quick Wins

### Task 1: Bump GitHub Actions to v5 (CI chore)

**Files:**
- Modify: `.github/workflows/publish.yml:30,34`

- [ ] **Step 1: Update checkout and setup-node to v5**

In `.github/workflows/publish.yml`, replace:

```yaml
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
```

With:

```yaml
      - name: Checkout
        uses: actions/checkout@v5

      - name: Setup Node
        uses: actions/setup-node@v5
```

- [ ] **Step 2: Verify the workflow YAML is valid**

```bash
cat .github/workflows/publish.yml | head -40
```

Confirm `@v5` on both lines.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/publish.yml
git commit -m "ci: bump checkout and setup-node to v5 (Node 20 deprecation)"
```

---

### Task 2: Parallelize bot fetches in SKILL.md (#1)

**Files:**
- Modify: `skills/crawl-sim/SKILL.md:69-71` (Stage 1 fetch loop)

- [ ] **Step 1: Replace the serial fetch loop with parallel background jobs**

In `skills/crawl-sim/SKILL.md`, replace the Stage 1 bash block's fetch loop:

```bash
for bot in googlebot gptbot claudebot perplexitybot; do
  "$SKILL_DIR/scripts/fetch-as-bot.sh" "$URL" "$SKILL_DIR/profiles/${bot}.json" > "$RUN_DIR/fetch-${bot}.json"
done
```

With:

```bash
for bot in googlebot gptbot claudebot perplexitybot; do
  "$SKILL_DIR/scripts/fetch-as-bot.sh" "$URL" "$SKILL_DIR/profiles/${bot}.json" > "$RUN_DIR/fetch-${bot}.json" &
done
wait

# Verify no empty fetch files (guard against silent parallel failures)
for bot in googlebot gptbot claudebot perplexitybot; do
  if [ ! -s "$RUN_DIR/fetch-${bot}.json" ]; then
    echo "WARNING: fetch-${bot}.json is empty — retrying serially" >&2
    "$SKILL_DIR/scripts/fetch-as-bot.sh" "$URL" "$SKILL_DIR/profiles/${bot}.json" > "$RUN_DIR/fetch-${bot}.json"
  fi
done
```

- [ ] **Step 2: Update the prose above the code block**

Change the "Tell the user" line from:
> "Fetching as Googlebot, GPTBot, ClaudeBot, and PerplexityBot..."

To:
> "Fetching as Googlebot, GPTBot, ClaudeBot, and PerplexityBot in parallel..."

- [ ] **Step 3: Commit**

```bash
git add skills/crawl-sim/SKILL.md
git commit -m "feat: parallelize bot fetches in SKILL.md Stage 1 (closes #1)

Background all 4 fetches with & + wait. Retry serially if any
file is empty (belt-and-suspenders on top of the H1 fix)."
```

---

### Task 3: Batch jq reads in compute-score.sh (#3)

**Files:**
- Modify: `skills/crawl-sim/scripts/compute-score.sh:270-380` (per-bot field extraction)
- Test: `test/run-scoring-tests.sh`

The per-bot loop currently calls `jget`/`jget_num`/`jget_bool` ~34 times, each spawning a `jq` subprocess. The fix: extract all fields from each JSON file in a single `jq` call using `@tsv`, then `read` the values into shell variables.

- [ ] **Step 1: Run existing tests to establish baseline**

```bash
npm test
```

Expected: 57 passing, 0 failing.

- [ ] **Step 2: Batch the per-bot field extraction from fetch, meta, jsonld, links, and robots files**

Replace the individual `jget`/`jget_num`/`jget_bool` calls inside the per-bot loop (after the `fetchFailed` guard, lines 315-320) with batched reads:

```bash
  # Batch-read fields from fetch file (1 jq call instead of 4)
  read -r STATUS TOTAL_TIME SERVER_WORD_COUNT RENDERS_JS <<< \
    "$(jq -r '[
      (.status // 0),
      (.timing.total // 0),
      (.wordCount // 0),
      (.bot.rendersJavaScript | if . == null then "unknown" else tostring end)
    ] | @tsv' "$FETCH" 2>/dev/null || echo "0	0	0	unknown")"

  # Batch-read fields from robots file (1 jq call instead of 1 — unchanged count but consistent style)
  ROBOTS_ALLOWED=$(jq -r '.allowed // false | tostring' "$ROBOTS" 2>/dev/null || echo "false")
```

Replace the meta field reads (lines 356-367):

```bash
  # Batch-read fields from meta file (1 jq call instead of 6)
  read -r H1_COUNT H2_COUNT IMG_TOTAL IMG_WITH_ALT <<< \
    "$(jq -r '[
      (.headings.h1.count // 0),
      (.headings.h2.count // 0),
      (.images.total // 0),
      (.images.withAlt // 0)
    ] | @tsv' "$META" 2>/dev/null || echo "0	0	0	0")"
```

Replace the links read (line 361):

```bash
  INTERNAL_LINKS=$(jq -r '.counts.internal // 0' "$LINKS" 2>/dev/null || echo "0")
```

Replace the technical signals reads (around lines 505-520):

```bash
  # Batch-read fields from meta for technical signals (1 jq call instead of 5)
  read -r TITLE DESCRIPTION CANONICAL OG_TITLE OG_DESC <<< \
    "$(jq -r '[
      (.title // "" | gsub("\t"; " ")),
      (.description // "" | gsub("\t"; " ")),
      (.canonical // "" | gsub("\t"; " ")),
      (.og.title // "" | gsub("\t"; " ")),
      (.og.description // "" | gsub("\t"; " "))
    ] | @tsv' "$META" 2>/dev/null || printf '\t\t\t\t')"
```

Replace the AI readiness reads (around lines 530-537):

```bash
  # Batch-read llmstxt fields (1 jq call instead of 4)
  read -r LLMS_EXISTS LLMS_HAS_TITLE LLMS_HAS_DESC LLMS_URLS <<< \
    "$(jq -r '[
      (.llmsTxt.exists // false | tostring),
      (.llmsTxt.hasTitle // false | tostring),
      (.llmsTxt.hasDescription // false | tostring),
      (.llmsTxt.urlCount // 0)
    ] | @tsv' "$LLMSTXT_FILE" 2>/dev/null || echo "false	false	false	0")"
```

- [ ] **Step 3: Run tests — verify no regressions**

```bash
npm test
```

Expected: 57 passing, 0 failing. The golden file test (AC9) is the critical check — it verifies non-structured category scores are byte-identical.

- [ ] **Step 4: Commit**

```bash
git add skills/crawl-sim/scripts/compute-score.sh
git commit -m "perf: batch jq reads in compute-score.sh — ~34 jq calls → ~10 (#3)

Replace individual jget/jget_num/jget_bool calls with batched
jq @tsv reads. Each file is now parsed once instead of 4-6 times."
```

---

## Wave 2 — Sprint 3 Polish (M1–M5)

### Task 4: M1 — `check-llmstxt.sh` top-level `exists` field

**Files:**
- Modify: `skills/crawl-sim/scripts/check-llmstxt.sh:97-116` (final jq output)
- Test: `test/run-scoring-tests.sh`

- [ ] **Step 1: Add test for top-level `exists` field**

Append to `test/run-scoring-tests.sh` before the summary section:

```bash
# ----- M1: check-llmstxt.sh top-level exists -----

case_begin "M1: llmstxt fixture has top-level exists field"
LLMS_EXISTS=$(jq -r '.exists // "missing"' test/fixtures/root-minimal/llmstxt.json)
assert_eq "$LLMS_EXISTS" "false" "top-level exists field present and false when llms.txt absent"
```

- [ ] **Step 2: Run test — verify it fails**

```bash
npm test
```

Expected: M1 test fails with `expected 'false', got 'missing'`.

- [ ] **Step 3: Add top-level `exists` to `check-llmstxt.sh` output**

In `skills/crawl-sim/scripts/check-llmstxt.sh`, in the final `jq -n` call (line 97), add a computed `exists` field. Add a new `--argjson` arg and modify the output object:

After line 96 (`--argjson llmsFullUrls "$LLMS_FULL_URLS"`), add:

```bash
  --argjson topExists "$([ "$LLMS_EXISTS" = "true" ] || [ "$LLMS_FULL_EXISTS" = "true" ] && echo true || echo false)" \
```

And in the output JSON object, add as the first field after `url`:

```json
    exists: $topExists,
```

- [ ] **Step 4: Update the test fixture**

Add `"exists": false` to `test/fixtures/root-minimal/llmstxt.json` and `test/fixtures/fetch-failed/llmstxt.json` and `test/fixtures/parity-mismatch/llmstxt.json` and `test/fixtures/root-invalid-fields/llmstxt.json`.

- [ ] **Step 5: Run tests — verify they pass**

```bash
npm test
```

- [ ] **Step 6: Commit**

```bash
git add skills/crawl-sim/scripts/check-llmstxt.sh test/
git commit -m "feat: M1 — add top-level exists field to check-llmstxt.sh output"
```

---

### Task 5: M2 — `check-sitemap.sh` sample URLs

**Files:**
- Modify: `skills/crawl-sim/scripts/check-sitemap.sh:44-79` (after URL count, before final output)

- [ ] **Step 1: Add `sampleUrls` extraction after the URL_COUNT line**

After line 44 (`URL_COUNT=$(grep ...)`), add:

```bash
      # Extract first 10 <loc> URLs as sample
      SAMPLE_URLS=$(grep -oE '<loc>[^<]+</loc>' "$SITEMAP_FILE" \
        | sed -E 's/<\/?loc>//g' \
        | head -10 \
        | jq -R . | jq -s .)
```

Initialize `SAMPLE_URLS="[]"` before the `if` block (around line 28), and add it to the output:

```bash
  --argjson sampleUrls "$SAMPLE_URLS" \
```

And in the output JSON:

```json
    sampleUrls: $sampleUrls,
```

- [ ] **Step 2: Run tests — verify no regressions**

```bash
npm test
```

- [ ] **Step 3: Commit**

```bash
git add skills/crawl-sim/scripts/check-sitemap.sh
git commit -m "feat: M2 — add sampleUrls array to check-sitemap.sh output (first 10 URLs)"
```

---

### Task 6: M3 — `extract-links.sh` flat schema

**Files:**
- Modify: `skills/crawl-sim/scripts/extract-links.sh:90-103` (final jq output)
- Modify: `skills/crawl-sim/scripts/compute-score.sh:361` (reads `.counts.internal`)
- Modify: `test/fixtures/*/links-*.json` (update fixture format)
- Test: `test/run-scoring-tests.sh`

- [ ] **Step 1: Add test for flat schema**

```bash
# ----- M3: extract-links.sh flat schema -----

case_begin "M3: links fixture uses flat schema"
TOTAL=$(jq -r '.total // "missing"' test/fixtures/parity-mismatch/links-googlebot.json)
assert_eq "$TOTAL" "10" "top-level total field present in flat schema"
```

- [ ] **Step 2: Run test — verify it fails**

- [ ] **Step 3: Flatten `extract-links.sh` output**

Replace the final `jq -n` call (lines 90-103):

```bash
jq -n \
  --argjson internalCount "$INTERNAL_COUNT" \
  --argjson externalCount "$EXTERNAL_COUNT" \
  --argjson internalSample "$INTERNAL_SAMPLE" \
  --argjson externalSample "$EXTERNAL_SAMPLE" \
  '{
    total: ($internalCount + $externalCount),
    internal: $internalCount,
    external: $externalCount,
    internalUrls: $internalSample,
    externalUrls: $externalSample
  }'
```

- [ ] **Step 4: Update `compute-score.sh` to read from flat schema**

Change line 361 from:

```bash
  INTERNAL_LINKS=$(jget_num "$LINKS" '.counts.internal')
```

To:

```bash
  INTERNAL_LINKS=$(jq -r '.internal // .counts.internal // 0' "$LINKS" 2>/dev/null || echo "0")
```

This reads the new flat field first, falling back to the old nested path for backward compat with any cached fixture data.

- [ ] **Step 5: Update all `links-*.json` fixtures**

Update every `test/fixtures/*/links-*.json` from:

```json
{"counts":{"total":0,"internal":0,"external":0}}
```

To:

```json
{"total":0,"internal":0,"external":0}
```

And for parity-mismatch:

```json
{"total":10,"internal":8,"external":2}
```

And for root-minimal and root-overreaching (which have the same content):

```json
{"total":10,"internal":8,"external":2}
```

Check each fixture's current values and preserve them — only change the shape.

- [ ] **Step 6: Run tests — verify they pass**

```bash
npm test
```

- [ ] **Step 7: Commit**

```bash
git add skills/crawl-sim/scripts/extract-links.sh skills/crawl-sim/scripts/compute-score.sh test/
git commit -m "feat: M3 — flatten extract-links.sh output schema

Old: {counts: {total, internal, external}, internal: [...], external: [...]}
New: {total, internal, external, internalUrls: [...], externalUrls: [...]}
compute-score.sh reads flat field with nested fallback."
```

---

### Task 7: M4 — `docs/output-schemas.md`

**Files:**
- Create: `docs/output-schemas.md`

- [ ] **Step 1: Document every script's JSON output contract**

Create `docs/output-schemas.md` with the exact JSON shape of each script's stdout. Use the actual current output from each script as the source of truth. Include field names, types, and brief descriptions.

Scripts to document:
- `fetch-as-bot.sh` (success path + fetchFailed path)
- `extract-meta.sh`
- `extract-jsonld.sh` (including new `blocks[]`)
- `extract-links.sh` (new flat schema)
- `check-robots.sh`
- `check-llmstxt.sh` (including new top-level `exists`)
- `check-sitemap.sh` (including new `sampleUrls`)
- `diff-render.sh` (success + skipped paths)
- `compute-score.sh` (full score.json schema with `parity`, `warnings`, per-bot `structuredData` explained fields)

For each script, show the complete JSON shape with `// type — description` comments. Example:

```markdown
## fetch-as-bot.sh

### Success output

\`\`\`jsonc
{
  "url": "string — the fetched URL",
  "bot": {
    "id": "string — bot profile ID (e.g., 'googlebot')",
    "name": "string — display name",
    "userAgent": "string — full UA string",
    "rendersJavaScript": "boolean"
  },
  "status": "number — HTTP status code",
  "timing": {
    "total": "number — seconds",
    "ttfb": "number — seconds"
  },
  "size": "number — bytes downloaded",
  "wordCount": "number — visible words in HTML",
  "redirectCount": "number — redirect hops",
  "finalUrl": "string — URL after redirects",
  "redirectChain": "array — [{hop, status, location}]",
  "headers": "object — response headers",
  "bodyBase64": "string — base64-encoded HTML body"
}
\`\`\`

### Failure output (fetchFailed)

\`\`\`jsonc
{
  "url": "string",
  "bot": { ... },
  "fetchFailed": true,
  "error": "string — curl error message",
  "curlExitCode": "number",
  ...remaining fields zeroed...
}
\`\`\`
```

- [ ] **Step 2: Commit**

```bash
git add docs/output-schemas.md
git commit -m "docs: M4 — document JSON output schemas for all scripts"
```

---

### Task 8: M5 — Consolidated `crawl-sim-report.json`

**Files:**
- Create: `skills/crawl-sim/scripts/build-report.sh`
- Modify: `skills/crawl-sim/SKILL.md` (Stage 5 — add build-report call)
- Test: `test/run-scoring-tests.sh`

- [ ] **Step 1: Create `build-report.sh`**

```bash
#!/usr/bin/env bash
set -eu

# build-report.sh — Consolidate all crawl-sim outputs into a single JSON report
# Usage: build-report.sh <results-dir>
# Output: JSON to stdout

RESULTS_DIR="${1:?Usage: build-report.sh <results-dir>}"

if [ ! -f "$RESULTS_DIR/score.json" ]; then
  echo "Error: score.json not found in $RESULTS_DIR" >&2
  exit 1
fi

# Read the score as the base
SCORE=$(cat "$RESULTS_DIR/score.json")

# Collect per-bot raw data
PER_BOT="{}"
for f in "$RESULTS_DIR"/fetch-*.json; do
  [ -f "$f" ] || continue
  bot_id=$(basename "$f" .json | sed 's/^fetch-//')

  BOT_RAW=$(jq -n \
    --argjson fetch "$(jq '{status, timing, size, wordCount, redirectCount, finalUrl, redirectChain, fetchFailed, error}' "$f" 2>/dev/null || echo '{}')" \
    --argjson meta "$(jq '.' "$RESULTS_DIR/meta-$bot_id.json" 2>/dev/null || echo '{}')" \
    --argjson jsonld "$(jq '{blockCount, types, blocks}' "$RESULTS_DIR/jsonld-$bot_id.json" 2>/dev/null || echo '{}')" \
    --argjson links "$(jq '.' "$RESULTS_DIR/links-$bot_id.json" 2>/dev/null || echo '{}')" \
    --argjson robots "$(jq '.' "$RESULTS_DIR/robots-$bot_id.json" 2>/dev/null || echo '{}')" \
    '{fetch: $fetch, meta: $meta, jsonld: $jsonld, links: $links, robots: $robots}')

  PER_BOT=$(printf '%s' "$PER_BOT" | jq --argjson raw "$BOT_RAW" --arg id "$bot_id" '.[$id] = $raw')
done

# Collect independent (non-per-bot) data
INDEPENDENT=$(jq -n \
  --argjson sitemap "$(jq '.' "$RESULTS_DIR/sitemap.json" 2>/dev/null || echo '{}')" \
  --argjson llmstxt "$(jq '.' "$RESULTS_DIR/llmstxt.json" 2>/dev/null || echo '{}')" \
  --argjson diffRender "$(jq '.' "$RESULTS_DIR/diff-render.json" 2>/dev/null || echo '{"skipped":true,"reason":"not_found"}')" \
  '{sitemap: $sitemap, llmstxt: $llmstxt, diffRender: $diffRender}')

# Merge score + raw data
printf '%s' "$SCORE" | jq \
  --argjson perBot "$PER_BOT" \
  --argjson independent "$INDEPENDENT" \
  '. + {raw: {perBot: $perBot, independent: $independent}}'
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x skills/crawl-sim/scripts/build-report.sh
```

- [ ] **Step 3: Add test**

```bash
# ----- M5: consolidated report -----

case_begin "M5: build-report.sh merges score + raw data into one file"
REPORT=$("$REPO_ROOT/skills/crawl-sim/scripts/build-report.sh" "$SCRIPT_DIR/fixtures/root-minimal" 2>/dev/null)
HAS_RAW=$(printf '%s' "$REPORT" | jq 'has("raw")')
HAS_PERBOT=$(printf '%s' "$REPORT" | jq 'has("raw") and (.raw | has("perBot"))')
HAS_INDEPENDENT=$(printf '%s' "$REPORT" | jq 'has("raw") and (.raw | has("independent"))')
SCORE=$(printf '%s' "$REPORT" | jq -r '.overall.score')
assert_eq "$HAS_RAW" "true" "report has raw section"
assert_eq "$HAS_PERBOT" "true" "report has raw.perBot section"
assert_eq "$HAS_INDEPENDENT" "true" "report has raw.independent section"
assert_ge "$SCORE" "0" "report preserves score from compute-score"
```

This test requires a `score.json` in the `root-minimal` fixture. Generate it:

```bash
"$REPO_ROOT/skills/crawl-sim/scripts/compute-score.sh" "$SCRIPT_DIR/fixtures/root-minimal" > "$SCRIPT_DIR/fixtures/root-minimal/score.json" 2>/dev/null
```

Actually, generate it inline in the test:

```bash
case_begin "M5: build-report.sh merges score + raw data into one file"
# Generate score.json for the fixture (build-report needs it)
"$COMPUTE_SCORE" "$SCRIPT_DIR/fixtures/root-minimal" > "$SCRIPT_DIR/fixtures/root-minimal/score.json" 2>/dev/null
REPORT=$("$REPO_ROOT/skills/crawl-sim/scripts/build-report.sh" "$SCRIPT_DIR/fixtures/root-minimal" 2>/dev/null)
rm -f "$SCRIPT_DIR/fixtures/root-minimal/score.json"
HAS_RAW=$(printf '%s' "$REPORT" | jq 'has("raw")')
HAS_PERBOT=$(printf '%s' "$REPORT" | jq '.raw | has("perBot")')
HAS_INDEPENDENT=$(printf '%s' "$REPORT" | jq '.raw | has("independent")')
SCORE=$(printf '%s' "$REPORT" | jq -r '.overall.score')
assert_eq "$HAS_RAW" "true" "report has raw section"
assert_eq "$HAS_PERBOT" "true" "report has raw.perBot section"
assert_eq "$HAS_INDEPENDENT" "true" "report has raw.independent section"
assert_ge "$SCORE" "0" "report preserves overall score"
```

- [ ] **Step 4: Run tests — verify M5 test fails (build-report.sh doesn't exist yet)**

- [ ] **Step 5: Create the script as shown in Step 1**

- [ ] **Step 6: Update SKILL.md Stage 5 to call build-report.sh**

In `skills/crawl-sim/SKILL.md`, update the Stage 5 bash block. After `compute-score.sh`:

```bash
"$SKILL_DIR/scripts/compute-score.sh" "$RUN_DIR" > "$RUN_DIR/score.json"
"$SKILL_DIR/scripts/build-report.sh" "$RUN_DIR" > ./crawl-sim-report.json
```

Remove the old `cp "$RUN_DIR/score.json" ./crawl-sim-report.json` line.

- [ ] **Step 7: Run tests — verify they pass**

- [ ] **Step 8: Commit**

```bash
git add skills/crawl-sim/scripts/build-report.sh skills/crawl-sim/SKILL.md test/run-scoring-tests.sh
git commit -m "feat: M5 — consolidated crawl-sim-report.json via build-report.sh

Single file contains score + raw per-bot data + independent checks.
Narrative layer reads one file instead of 8+."
```

---

## Wave 3 — Sprint 4 Roadmap (R2–R4)

### Task 9: R3 — Adaptive per-bot display when parity collapses

**Files:**
- Modify: `skills/crawl-sim/SKILL.md` (Score Card section)

This is a narrative-layer change only — the data (`parity.score`) already exists from C4.

- [ ] **Step 1: Update the Score Card template in SKILL.md**

In the "Output Layer 1 — Score Card (ASCII)" section, add guidance after the score card template:

```markdown
**Parity-aware display.** When `parity.score >= 95` AND all per-bot composite scores are within 5 points of each other, collapse the four bot rows into one:

\`\`\`
║  All 4 bots     98  A   ███████████████████░  (parity: content identical)  ║
\`\`\`

Only show individual bot rows when scores diverge — that's when per-bot detail adds information. Always show the `parity` line in the category breakdown:

\`\`\`
║  Content Parity   100  A   (all bots see the same content)                 ║
\`\`\`
```

- [ ] **Step 2: Commit**

```bash
git add skills/crawl-sim/SKILL.md
git commit -m "feat: R3 — adaptive per-bot display guidance when parity collapses"
```

---

### Task 10: R4 — Critical-fail criteria for auto-F grades

**Files:**
- Modify: `skills/crawl-sim/scripts/compute-score.sh` (inside per-bot loop, after category scoring)
- Test: `test/run-scoring-tests.sh`
- Create: `test/fixtures/critical-fail-robots/` (bot blocked by robots.txt)

- [ ] **Step 1: Create the critical-fail-robots fixture**

A fixture where robots blocks the bot:

```bash
mkdir -p test/fixtures/critical-fail-robots
```

Write `test/fixtures/critical-fail-robots/fetch-googlebot.json`:
```json
{
  "url": "https://example.com/",
  "bot": { "id": "googlebot", "name": "Googlebot", "userAgent": "Googlebot/2.1", "rendersJavaScript": true },
  "status": 200, "timing": { "total": 0.5, "ttfb": 0.2 }, "size": 50000, "wordCount": 500,
  "redirectCount": 0, "finalUrl": "https://example.com/", "redirectChain": [],
  "headers": {}, "bodyBase64": ""
}
```

Write `test/fixtures/critical-fail-robots/robots-googlebot.json`:
```json
{"allowed": false}
```

Copy remaining fixtures from `root-minimal`: `meta-googlebot.json`, `jsonld-googlebot.json`, `links-googlebot.json`, `llmstxt.json`, `sitemap.json`.

- [ ] **Step 2: Add tests**

```bash
# ----- R4: critical-fail criteria -----

case_begin "R4: bot blocked by robots.txt gets auto-F on accessibility"
if OUT=$(run_score critical-fail-robots 2>/dev/null); then
  ACC_SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.accessibility.score')
  ACC_GRADE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.accessibility.grade')
  BOT_SCORE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.score')
  assert_eq "$ACC_SCORE" "0" "robots-blocked bot gets 0 on accessibility"
  assert_eq "$ACC_GRADE" "F" "robots-blocked bot gets F grade on accessibility"
  assert_lt "$BOT_SCORE" "60" "robots-blocked bot composite score drops below 60"
else
  fail "compute-score.sh exited non-zero on critical-fail-robots"
fi
```

- [ ] **Step 3: Run tests — verify they fail**

The current scorer gives 40 points for status 200 + 20 for TTFB even when robots blocks. The test expects 0.

- [ ] **Step 4: Add critical-fail logic to compute-score.sh**

After the accessibility scoring (around line 347), add:

```bash
  # Critical-fail: robots blocking overrides accessibility to 0/F
  if [ "$ROBOTS_ALLOWED" != "true" ]; then
    ACC=0
  fi
```

- [ ] **Step 5: Run tests — verify they pass**

```bash
npm test
```

- [ ] **Step 6: Commit**

```bash
git add skills/crawl-sim/scripts/compute-score.sh test/
git commit -m "feat: R4 — critical-fail criteria: robots blocking = auto-F on accessibility

A bot blocked by robots.txt now scores 0/F on accessibility regardless
of HTTP status or TTFB. This prevents misleading A grades on bots
that can't actually access the page."
```

---

### Task 11: R2 — Confidence levels on structuredData findings

**Files:**
- Modify: `skills/crawl-sim/scripts/compute-score.sh` (structuredData violations block)
- Modify: `skills/crawl-sim/SKILL.md` (interpretation rules)
- Test: `test/run-scoring-tests.sh`

- [ ] **Step 1: Add `confidence` field to existing violation objects**

In `compute-score.sh`, update the violations construction in the STRUCTURED_OBJ jq call. Each violation type gets a confidence level:

```jq
      violations: (
        ($forbiddenPresent | to_arr | map({kind: "forbidden_schema", schema: ., impact: -10, confidence: "high"}))
        + (if $validPenalty > 0
             then [{kind: "invalid_jsonld", count: $invalidCount, impact: (0 - $validPenalty), confidence: "high"}]
             else []
           end)
        + $fieldViolations
      ),
```

Also update the `FIELD_VIOLATIONS_JSON` construction to include confidence:

```bash
          FIELD_VIOLATIONS_JSON=$(printf '%s' "$FIELD_VIOLATIONS_JSON" | jq \
            --arg schema "$BLOCK_TYPE" --arg field "$field" \
            '. + [{kind: "missing_required_field", schema: $schema, field: $field, impact: -5, confidence: "high"}]')
```

- [ ] **Step 2: Add test for confidence field**

```bash
# ----- R2: confidence levels -----

case_begin "R2: violations include confidence field"
if OUT=$(run_score root-overreaching 2>/dev/null); then
  FIRST_CONFIDENCE=$(printf '%s' "$OUT" | jq -r '.bots.googlebot.categories.structuredData.violations[0].confidence')
  assert_eq "$FIRST_CONFIDENCE" "high" "violations carry confidence level"
else
  fail "compute-score.sh exited non-zero on root-overreaching"
fi
```

- [ ] **Step 3: Run tests — verify they fail**

- [ ] **Step 4: Implement the confidence changes as shown in Step 1**

- [ ] **Step 5: Update SKILL.md interpretation rules**

Add to the interpretation rules section:

```markdown
- **Confidence on violations.** Every violation now carries a `confidence` field (`high`, `medium`, or `low`). `high` = directly observed in the data (schema missing, field absent). `medium` = inferred from documented behavior. `low` = heuristic. The narrative must cite confidence for any finding that isn't `high`.
```

- [ ] **Step 6: Run tests — verify they pass**

- [ ] **Step 7: Commit**

```bash
git add skills/crawl-sim/scripts/compute-score.sh skills/crawl-sim/SKILL.md test/run-scoring-tests.sh
git commit -m "feat: R2 — confidence levels on structuredData violations

Every violation now carries confidence: high/medium/low.
Current violations are all 'high' (directly observed in data).
SKILL.md interpretation rules updated to require citation for
non-high confidence findings."
```

---

## Final: Version bump + close issues

- [ ] **Step 1: Bump version to 1.3.0**

Update `package.json`, `.claude-plugin/plugin.json`, and `.claude-plugin/marketplace.json` to `1.3.0`.

- [ ] **Step 2: Commit + tag**

```bash
git add package.json .claude-plugin/
git commit -m "chore: bump to v1.3.0"
git tag v1.3.0
git push && git push --tags
```

- [ ] **Step 3: Close issues**

```bash
gh issue close 1 --comment "Fixed in v1.3.0 — Stage 1 fetches now run in parallel with & + wait."
gh issue close 3 --comment "Fixed in v1.3.0 — jq calls batched from ~34 to ~10 per bot."
gh issue comment 12 --body "M1–M5 and R2–R4 shipped in v1.3.0. All items from this umbrella are now complete."
gh issue close 12
```

---

## Dependency graph

```
Task 1 (CI) ─────────────────────────────────── can run first, no deps
Task 2 (parallel fetch) ────────────────────── no deps
Task 3 (batch jq) ──────────────────────────── no deps
Task 4 (M1 llmstxt exists) ─────────────────── no deps
Task 5 (M2 sitemap sample) ─────────────────── no deps
Task 6 (M3 links flat) ─────────────────────── no deps (compute-score uses fallback)
Task 7 (M4 output schemas) ─────────────────── after Tasks 4-6 (documents final shapes)
Task 8 (M5 consolidated report) ─────────────  after Task 6 (reads new links shape)
Task 9 (R3 parity display) ─────────────────── no deps (SKILL.md only)
Task 10 (R4 critical-fail) ─────────────────── no deps
Task 11 (R2 confidence) ────────────────────── no deps
```

All tasks except 7 and 8 are fully independent. Maximum parallelism: dispatch 1-6 + 9-11 as parallel subagents, then 7+8 sequentially.
