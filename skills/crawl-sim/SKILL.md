---
name: crawl-sim
description: Audit a URL through the eyes of Googlebot, GPTBot, ClaudeBot, and PerplexityBot. Fetches the page as each bot, runs structural checks, compares server HTML vs JS-rendered DOM to differentiate rendering-capable bots from non-rendering ones, then scores and returns a score card + narrative audit + JSON report. Trigger when the user asks to audit a site for AI/search visibility, test how bots see a page, check if content is visible to GPTBot/ClaudeBot/Perplexity, analyze llms.txt / robots.txt / structured data, or says "/crawl-sim".
allowed-tools: Bash, Read, Write
---

# crawl-sim — Multi-Bot Visibility Audit

You are running a per-URL audit that simulates how different web crawlers see a site. You orchestrate shell scripts, interpret the raw data, and produce a three-layer output: (1) a terminal score card, (2) a prose narrative with prioritized findings, (3) a structured JSON report.

## Experience principle

**This tool should feel alive.** Before each stage of the pipeline, emit a one-sentence status line to the user in plain text (not inside a code block). The user should know what's happening without expanding tool-call details. Example cadence:

> Fetching the page as 4 bots in parallel...
>
> Extracting meta, JSON-LD, and links from each response...
>
> Checking robots.txt per bot, plus llms.txt and sitemap...
>
> Comparing server HTML vs Playwright-rendered DOM (this is what differentiates bots)...
>
> Computing scores and finalizing...

Keep status lines short, active, and specific to this URL. Never use the same sentence twice in one run.

## Usage

```
/crawl-sim <url>                            # full audit (default)
/crawl-sim <url> --bot gptbot               # single bot
/crawl-sim <url> --category structured-data # category deep dive
/crawl-sim <url> --json                     # JSON output only (for CI)
```

## Prerequisites — check once at the start

```bash
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required"; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq)"; exit 1; }
```

Locate the skill directory. Check in this order:
1. `$CLAUDE_PLUGIN_ROOT/skills/crawl-sim` (plugin install)
2. `~/.claude/skills/crawl-sim/` (global npm install)
3. `.claude/skills/crawl-sim/` (project-level install)

## Orchestration — five narrated stages

Split the work into **five Bash invocations**, each with a clear `description` field, and emit a plain-text status line *before* each one. Do not run the whole pipeline in one giant bash block — that makes the tool feel silent.

### Stage 1 — Fetch

Tell the user: "Fetching as Googlebot, GPTBot, ClaudeBot, and PerplexityBot in parallel..."

```bash
# Resolve skill directory
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT/skills/crawl-sim" ]; then
  SKILL_DIR="$CLAUDE_PLUGIN_ROOT/skills/crawl-sim"
elif [ -d "$HOME/.claude/skills/crawl-sim" ]; then
  SKILL_DIR="$HOME/.claude/skills/crawl-sim"
elif [ -d ".claude/skills/crawl-sim" ]; then
  SKILL_DIR=".claude/skills/crawl-sim"
else
  echo "ERROR: cannot find crawl-sim skill directory" >&2; exit 1
fi
RUN_DIR=$(mktemp -d -t crawl-sim.XXXXXX)
URL="<user-provided-url>"
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

Each fetch emits a `[fetch-as-bot] BotName <- URL` line to stderr that surfaces in the Bash call's output.

If `--bot <id>` was passed, use only that bot. Also optionally include the secondary profiles (`oai-searchbot`, `chatgpt-user`, `claude-user`, `claude-searchbot`, `perplexity-user`) when the user passes `--all`.

### Stage 2 — Extract HTML structure

Tell the user: "Extracting meta, JSON-LD, and links from each bot's view..."

```bash
for bot in googlebot gptbot claudebot perplexitybot; do
  jq -r '.bodyBase64' "$RUN_DIR/fetch-${bot}.json" | base64 -d > "$RUN_DIR/body-${bot}.html"
  "$SKILL_DIR/scripts/extract-meta.sh"   "$RUN_DIR/body-${bot}.html" > "$RUN_DIR/meta-${bot}.json"
  "$SKILL_DIR/scripts/extract-jsonld.sh" "$RUN_DIR/body-${bot}.html" > "$RUN_DIR/jsonld-${bot}.json"
  "$SKILL_DIR/scripts/extract-links.sh" "$URL" "$RUN_DIR/body-${bot}.html" > "$RUN_DIR/links-${bot}.json"
done
```

### Stage 3 — Crawler policy checks

Tell the user: "Checking robots.txt for each bot's UA token, plus llms.txt and sitemap.xml..."

```bash
for bot in googlebot gptbot claudebot perplexitybot; do
  token=$(jq -r '.robotsTxtToken' "$SKILL_DIR/profiles/${bot}.json")
  "$SKILL_DIR/scripts/check-robots.sh" "$URL" "$token" > "$RUN_DIR/robots-${bot}.json"
done
"$SKILL_DIR/scripts/check-llmstxt.sh" "$URL" > "$RUN_DIR/llmstxt.json"
"$SKILL_DIR/scripts/check-sitemap.sh" "$URL" > "$RUN_DIR/sitemap.json"
```

### Stage 4 — Render comparison (this is the differentiator)

Tell the user something like: "Comparing server HTML vs Playwright-rendered DOM — this is how Googlebot and the AI bots get scored differently..."

```bash
if [ -x "$SKILL_DIR/scripts/diff-render.sh" ]; then
  "$SKILL_DIR/scripts/diff-render.sh" "$URL" > "$RUN_DIR/diff-render.json" \
    || echo '{"skipped":true,"reason":"diff-render failed"}' > "$RUN_DIR/diff-render.json"
fi
```

Never redirect `diff-render.sh` stderr into the output file — the narration line would corrupt the JSON.

**Why this stage matters:** the score depends on it. `compute-score.sh` uses the rendered word count for bots with `rendersJavaScript: true` (Googlebot) and applies a hydration penalty to bots with `rendersJavaScript: false` (GPTBot, ClaudeBot, PerplexityBot) proportional to how much content is invisible to them. On a site with significant client-side hydration, this is where the bot scores actually diverge. Without this stage, all non-blocked bots would score identically.

If Playwright isn't installed, `diff-render.sh` writes `{"skipped": true, "reason": "..."}` and the scoring falls back to server-HTML-only for all bots — the narrative must acknowledge this: "Per-bot differentiation was limited because JS render comparison was unavailable."

### Stage 5 — Score and aggregate

Tell the user: "Computing per-bot scores and finalizing the report..."

```bash
"$SKILL_DIR/scripts/compute-score.sh" "$RUN_DIR" > "$RUN_DIR/score.json"
"$SKILL_DIR/scripts/build-report.sh" "$RUN_DIR" > ./crawl-sim-report.json
```

**Page-type awareness.** `compute-score.sh` derives a page type from the target URL (`root` / `detail` / `archive` / `faq` / `about` / `contact` / `generic`) and picks a schema rubric accordingly. Root pages are expected to ship `Organization` + `WebSite` — penalizing them for missing `BreadcrumbList` or `FAQPage` would be wrong, so the scorer doesn't. If the URL heuristic picks the wrong type (e.g., a homepage at `/en/` that URL-parses as generic), pass `--page-type <type>`:

```bash
"$SKILL_DIR/scripts/compute-score.sh" --page-type root "$RUN_DIR" > "$RUN_DIR/score.json"
```

Valid values: `root`, `detail`, `archive`, `faq`, `about`, `contact`, `generic`. The detected (or overridden) page type is exposed on `score.pageType`, and `score.pageTypeOverridden` flips `true` when `--page-type` was used.

## Output Layer 1 — Score Card (ASCII)

Print a boxed score card to the terminal:

```
╔══════════════════════════════════════════════╗
║         crawl-sim — Bot Visibility Audit     ║
║         <URL>                                ║
╠══════════════════════════════════════════════╣
║  Overall: <score>/100 (<grade>)              ║
╠══════════════════════════════════════════════╣
║  Googlebot      <s>  <g>  <bar>              ║
║  GPTBot         <s>  <g>  <bar>              ║
║  ClaudeBot      <s>  <g>  <bar>              ║
║  PerplexityBot  <s>  <g>  <bar>              ║
╠══════════════════════════════════════════════╣
║  By Category:                                ║
║  Accessibility      <s>  <g>                 ║
║  Content Visibility <s>  <g>                 ║
║  Structured Data    <s>  <g>                 ║
║  Technical Signals  <s>  <g>                 ║
║  AI Readiness       <s>  <g>                 ║
╚══════════════════════════════════════════════╝
```

Progress bars are 20 chars wide using `█` and `░` (each char = 5%).

**Parity-aware display.** When `parity.score >= 95` AND all per-bot composite scores are within 5 points of each other, collapse the four bot rows into one:

```
║  All 4 bots     98  A   ███████████████████░  (parity: content identical)  ║
```

Only show individual bot rows when scores diverge — that's when per-bot detail adds information. Always show the parity line in the category breakdown:

```
║  Content Parity   100  A   (all bots see the same content)                 ║
```

## Output Layer 2 — Narrative Audit

Lead with a **Bot differentiation summary** — state up front whether the bots scored the same or differently, and why. If they scored the same, explicitly say so:

> *"All four bots scored 94/A because the server HTML is complete (2,166 words), robots.txt allows every UA token, and there was no meaningful JS hydration gap (delta 11%, below the 20% penalty threshold). On a clean site like this, crawl-sim's multi-bot angle isn't the headline finding — the category gaps are."*

If they scored differently (the interesting case):

> *"Googlebot scored 92/A because it renders JS and sees the full 3,400-word page. GPTBot, ClaudeBot, and PerplexityBot scored 78/C+ because they only see the 2,100-word server HTML — 1,300 words (38%) of content is invisible to AI crawlers, including the testimonials section and half the product cards."*

Then produce **prioritized findings** ranked by total point impact across bots:

```markdown
### 1. <Title> (−<total> pts across <bot count> bots)

**Affected:** <bot list>
**Category:** <category>
**Observed:** <what the data shows — cite counts, tag names, paths>
**Likely cause:** <if inferable from HTML/framework signals>
**Fix:** <actionable, file-path-specific if possible>
**Impact if fixed:** +<N> points on affected bot scores
```

### Interpretation rules

- **Cross-bot deltas are the headline.** Compare `visibility.effectiveWords` across bots — if Googlebot has significantly more than the AI bots, that's finding #1. The raw delta is in `visibility.missedWordsVsRendered`.
- **Trust the structuredData rubric.** Every `bots.<bot>.categories.structuredData` block now carries `pageType`, `expected`, `optional`, `forbidden`, `present`, `missing`, `extras`, `violations`, `calculation`, and `notes`. Read `missing` and `violations` directly — never guess what the scorer was penalizing for. If `notes` says the page scores 100 with no action needed, that IS the finding; don't invent fixes. If the rubric looks wrong for this specific page (e.g., a homepage detected as `generic` because the URL ends in `/en/`), rerun with `--page-type <correct-type>` instead of arguing with the score. Never recommend adding a schema that already appears in `present` or `extras`.
- **Confidence transparency.** If a claim depends on a bot profile's `rendersJavaScript: false` at `observed` confidence (not `official`), note it: *"Based on observed behavior, not official documentation."*
- **Framework detection.** Scan the HTML body for signals: `<meta name="next-head-count">` or `_next/static` → Next.js (Pages Router or App Router respectively), `<div id="__nuxt">` → Nuxt, `<div id="app">` with thin content → SPA (Vue/React CSR), `<!--$-->` placeholder tags → React 18 Suspense. Use these to tailor fix recommendations.
- **No speculation beyond the data.** If server HTML has 0 `<a>` tags inside a component, say "component not present in server HTML" — not "JavaScript hydration failed" unless the diff-render data proves it.
- **Known extractor limitations.** The bash meta extractor sometimes reports `h1Text: null` even when `h1.count: 1` — that happens when the H1 contains nested tags (`<br>`, `<span>`, `<svg>`). The count is still correct. Don't flag this as a site bug — it's tracked in GitHub issue #4.
- **Per-bot quirks to surface:**
  - Googlebot: renders JS. If `diff-render.sh` was skipped, note that comparison was unavailable and recommend installing Playwright.
  - GPTBot / ClaudeBot / PerplexityBot: `rendersJavaScript: false` at observed confidence — flag any server-vs-rendered delta as invisible-to-AI content.
  - `chatgpt-user` / `perplexity-user`: officially ignore robots.txt for user-initiated fetches. Blocking these via robots.txt has no effect.
  - PerplexityBot: third-party reports of stealth/undeclared crawling. Mention if relevant, don't assert.

After findings, write a **Summary** paragraph: what's working well, biggest wins, confidence caveats. Keep it short — two to three sentences.

## Output Layer 3 — JSON Report

`./crawl-sim-report.json` is written in Stage 5. The schema is stable for diffing across runs. Tell the user the report path at the end and also print the `RUN_DIR` so they can inspect intermediate JSON.

## Error Handling

- If any script fails, include the failure in the narrative — don't silently skip.
- If the target URL returns non-200, report immediately and still run robots.txt / sitemap / llms.txt checks (they don't require the page to load).
- If `jq` or `curl` is missing, exit with install instructions.
- If `diff-render.sh` skips, the narrative must note that per-bot differentiation is reduced.

## Cleanup

`$RUN_DIR` is small and informative — leave it in place and print the path. The user may want to inspect the raw JSON for any of the 23+ intermediate files.
