---
name: crawl-sim
description: Audit a URL through the eyes of Googlebot, GPTBot, ClaudeBot, and PerplexityBot. Fetches the page as each bot, runs structural checks, computes per-bot + per-category scores, and returns a score card + narrative audit + JSON report. Trigger when the user asks to audit a site for AI/search visibility, test how bots see a page, check if content is visible to GPTBot/ClaudeBot/Perplexity, analyze llms.txt / robots.txt / structured data, or says "/crawl-sim".
allowed-tools: Bash, Read, Write
---

# crawl-sim — Multi-Bot Visibility Audit

You are running a per-URL audit that simulates how different web crawlers see a site. You orchestrate shell scripts, interpret the raw data, and produce a three-layer output: (1) a terminal score card, (2) a prose narrative with prioritized findings, (3) a structured JSON report.

## Usage

The user invokes this skill with a URL and optional flags:

```
/crawl-sim <url>                          # full audit (default)
/crawl-sim <url> --bot gptbot             # single bot
/crawl-sim <url> --category structured-data  # category deep dive
/crawl-sim <url> --json                   # JSON output only (for CI)
```

## Prerequisites — always check first

Run these checks before starting:

```bash
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required"; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq)"; exit 1; }
```

If the skill dir is not the working directory, locate it: it is typically `~/.claude/skills/crawl-sim/` or `.claude/skills/crawl-sim/`. Use `$CLAUDE_PLUGIN_ROOT` if available, otherwise find the directory containing this `SKILL.md`.

## Orchestration Flow

Execute these steps in order. Do NOT skip steps. Do NOT parallelize — each step depends on data produced by the previous step.

### Step 1: Set up working directory

Create a per-run temp directory to hold all intermediate JSON:

```bash
RUN_DIR=$(mktemp -d -t crawl-sim.XXXXXX)
echo "Results: $RUN_DIR"
```

### Step 2: Discover bot profiles

```bash
SKILL_DIR="<path to this skill dir>"
PROFILES=$(ls "$SKILL_DIR/profiles/"*.json)
```

If the user passed `--bot <id>`, filter to just that profile. Otherwise use the four primary bots: `googlebot`, `gptbot`, `claudebot`, `perplexitybot`. Bot-specific variants (`oai-searchbot`, `chatgpt-user`, `claude-user`, `claude-searchbot`, `perplexity-user`) are secondary — include them only on `--all` or explicit request.

### Step 3: Fetch as each bot

For each selected profile, run `fetch-as-bot.sh`:

```bash
for profile in $SELECTED_PROFILES; do
  bot_id=$(jq -r '.id' "$profile")
  "$SKILL_DIR/scripts/fetch-as-bot.sh" "$URL" "$profile" > "$RUN_DIR/fetch-${bot_id}.json"
done
```

### Step 4: Extract structure from each fetched response

For each fetch output, decode the base64 body and run the extractors:

```bash
for profile in $SELECTED_PROFILES; do
  bot_id=$(jq -r '.id' "$profile")
  jq -r '.bodyBase64' "$RUN_DIR/fetch-${bot_id}.json" | base64 -d > "$RUN_DIR/body-${bot_id}.html"
  "$SKILL_DIR/scripts/extract-meta.sh"    "$RUN_DIR/body-${bot_id}.html" > "$RUN_DIR/meta-${bot_id}.json"
  "$SKILL_DIR/scripts/extract-jsonld.sh"  "$RUN_DIR/body-${bot_id}.html" > "$RUN_DIR/jsonld-${bot_id}.json"
  "$SKILL_DIR/scripts/extract-links.sh" "$URL" "$RUN_DIR/body-${bot_id}.html" > "$RUN_DIR/links-${bot_id}.json"
done
```

### Step 5: Check robots.txt per bot

Each bot has its own `robotsTxtToken`:

```bash
for profile in $SELECTED_PROFILES; do
  bot_id=$(jq -r '.id' "$profile")
  token=$(jq -r '.robotsTxtToken' "$profile")
  "$SKILL_DIR/scripts/check-robots.sh" "$URL" "$token" > "$RUN_DIR/robots-${bot_id}.json"
done
```

### Step 6: Bot-independent checks

```bash
"$SKILL_DIR/scripts/check-llmstxt.sh" "$URL" > "$RUN_DIR/llmstxt.json"
"$SKILL_DIR/scripts/check-sitemap.sh" "$URL" > "$RUN_DIR/sitemap.json"
```

### Step 7: Optional — diff-render (Googlebot JS rendering)

If any selected profile has `rendersJavaScript: true` AND `diff-render.sh` is available AND playwright is installed, run it:

```bash
if [ -x "$SKILL_DIR/scripts/diff-render.sh" ]; then
  "$SKILL_DIR/scripts/diff-render.sh" "$URL" > "$RUN_DIR/diff-render.json" 2>/dev/null || true
fi
```

If the script output has `"skipped": true`, note this in the narrative — JS rendering comparison was unavailable.

### Step 8: Compute scores

```bash
"$SKILL_DIR/scripts/compute-score.sh" "$RUN_DIR" > "$RUN_DIR/score.json"
```

### Step 9: Interpret and produce the three output layers

Read `$RUN_DIR/score.json` and all intermediate files, then produce:

## Output Layer 1: Score Card (ASCII)

Print a boxed score card to the terminal. Use this exact format:

```
╔══════════════════════════════════════════════╗
║         crawl-sim — Bot Visibility Audit     ║
║         <URL>                                ║
╠══════════════════════════════════════════════╣
║  Overall: <score>/100 (<grade>)              ║
╠══════════════════════════════════════════════╣
║  Googlebot      <s>  <g>  <progress bar>     ║
║  GPTBot         <s>  <g>  <progress bar>     ║
║  ClaudeBot      <s>  <g>  <progress bar>     ║
║  PerplexityBot  <s>  <g>  <progress bar>     ║
╠══════════════════════════════════════════════╣
║  By Category:                                ║
║  Accessibility      <s>  <g>                 ║
║  Content Visibility <s>  <g>                 ║
║  Structured Data    <s>  <g>                 ║
║  Technical Signals  <s>  <g>                 ║
║  AI Readiness       <s>  <g>                 ║
╚══════════════════════════════════════════════╝
```

Progress bars use `█` for filled and `░` for empty, 20 chars wide (each char = 5%).

## Output Layer 2: Narrative Audit

After the score card, write prioritized prose findings. Rank findings by point impact — biggest score gains first. Each finding must have:

- A title
- Which bots are affected
- The observed problem (specific — cite counts, file paths, tag names)
- The recommended fix (actionable, specific)
- Estimated point impact

**Confidence transparency:** When a claim depends on a `confidence.level` of "observed" or "inferred" in the bot profile, note this: "Based on observed behavior, not official documentation."

**Do not speculate beyond the data.** If the server HTML has 0 `<a>` tags inside a component, say "component not present in server HTML" — not "JavaScript hydration failed" unless you have evidence. If you suspect a framework issue (Next.js `ssr: false`, React Suspense boundary, etc.), say "likely cause:" rather than asserting.

**Framework context:** Look at the HTML for signals:
- `<meta name="next-head-count">` → Next.js
- `<div id="__nuxt">` → Nuxt
- `<div id="app">` with minimal server content → SPA (Vue/React CSR)
- `<!--$-->` placeholder tags → React 18 Suspense

Use these to tailor fix recommendations.

### Prioritization

Score findings by point impact. A finding that affects 3 bots × 15 points each = 45 total impact, even if no single bot loses 45.

### Template

```markdown
## Priority Findings

### 1. <Title> (−<total> pts across <bot count> bots)

**Affected:** <bot list>
**Category:** <category>
**Observed:** <what the data shows — be specific>
**Likely cause:** <if inferable from HTML/framework signals>
**Fix:** <actionable, file-path-specific if possible>
**Impact if fixed:** +<N> points on affected bot scores

### 2. ...
```

After findings, write a short **Summary** paragraph: what's working well, what the biggest wins would be, and any caveats about confidence.

## Output Layer 3: JSON report

Save the full report to `<cwd>/crawl-sim-report.json`:

```bash
# Merge score.json with findings and raw check outputs
cp "$RUN_DIR/score.json" ./crawl-sim-report.json
# Optionally enrich with findings array
```

Tell the user the report path at the end.

## Interpretation Guidelines

**When reading raw check outputs:**

- `fetch-*.json` → HTTP status, word count, size, headers. A 200 with low word count (<100) vs the same page rendered (Googlebot) = likely SPA hydration issue for non-rendering bots.
- `meta-*.json` → Title, description, canonical, OG, headings, images. Missing title = critical. Missing canonical on a multi-domain site = duplicate content risk.
- `jsonld-*.json` → Structured data presence. No schema.org = invisible to knowledge-graph features.
- `links-*.json` → Internal link counts. If a page has <3 internal links in the server HTML but is supposed to be a hub page, that's a "hidden navigation" finding.
- `robots-*.json` → Per-bot allowance. A `false` allowed value is the most critical finding possible — the bot literally can't crawl the page.
- `llmstxt.json` → AI-readiness signal. Missing = −20 pts AI Readiness across all bots.
- `sitemap.json` → Sitemap presence and URL inclusion. URL not in sitemap = discovery risk.

**Cross-bot comparison is the key differentiator.** If Googlebot sees 1800 words and GPTBot sees 120, that's the headline finding. Compute: `diff = googlebot.wordCount - gptbot.wordCount`, report as a percentage.

**Per-bot quirks to flag:**

- Googlebot: renders JS. If `diff-render.sh` skipped, note that JS rendering comparison was unavailable and recommend running with Playwright installed.
- GPTBot / ClaudeBot / PerplexityBot: observed to NOT render JS. If the user's framework relies on CSR for content, flag it.
- ChatGPT-User / Perplexity-User: officially ignore robots.txt (or "may not apply"). Note this in narrative — blocking these via robots.txt has no effect.
- PerplexityBot: there are third-party reports of stealth/undeclared crawling. Don't assert this as fact, but if the user asks about Perplexity blocking, mention it's contested.

## Error Handling

If any script fails or returns an error, include the failure in the narrative — don't silently skip. If the target URL returns a non-200 status, report it immediately and still run checks where possible (robots.txt, sitemap, llms.txt don't require the page to load).

If `jq` or `curl` is missing, exit with the install instructions from the Prerequisites section.

## Cleanup

After producing output, the temp dir `$RUN_DIR` can be left in place (it's small). Print the path so the user can inspect raw JSON if they want.
