# crawl-sim — Design Spec

**Date:** 2026-04-11
**Status:** Draft
**Author:** BraedenBDev + Claude

## What

The first open-source, agent-native multi-bot web crawler simulator. A Claude Code skill backed by standalone shell scripts that shows how Googlebot, GPTBot, ClaudeBot, PerplexityBot, and other crawlers see and interpret a website — with quantified scoring, narrative interpretation, and structured JSON output.

## Why

The crawler simulation market is fragmented:
- **Rendering tools** (Screaming Frog, TametheBots) focus on Googlebot only
- **Monitoring SaaS** (Otterly, ZipTie, Peec) track citations but don't simulate crawls
- **Frameworks** (Crawlee, Playwright) are raw building blocks with no bot intelligence

No tool combines multi-bot simulation + LLM-powered interpretation + quantified scoring in an agent-native format. The concept was validated manually on almostimpossible.agency — curl-as-bot + LLM analysis caught a real SSR bug (`ssr: false` on JournalSpotlight hiding article links from AI crawlers).

## Audience

Everyone — developers, SEO professionals, agencies — but launching with Claude Code skill users first. CLI developers and non-agent users can invoke the shell scripts directly.

## Distribution

### Primary: npm installer
```bash
npx crawl-sim install              # → ~/.claude/skills/crawl-sim/
npx crawl-sim install --project    # → .claude/skills/crawl-sim/
```

The npm package contains `bin/install.js` which:
1. Detects target directory (global `~/.claude/skills/` vs project `.claude/skills/`)
2. Copies `SKILL.md`, `profiles/`, `scripts/` to target
3. Makes scripts executable (`chmod +x`)
4. Checks prerequisites (`curl`, `jq`, optionally `playwright`)
5. Prints success + usage instructions

### Fallback: git clone
```bash
git clone https://github.com/BraedenBDev/crawl-sim.git ~/.claude/skills/crawl-sim
```

---

## Architecture

### Directory Structure

```
crawl-sim/
├── package.json                # npm package metadata + bin entry
├── bin/
│   └── install.js              # npm installer script
├── SKILL.md                    # Orchestrator skill — Claude Code entry point
├── README.md                   # Install + usage + contributing
├── LICENSE                     # MIT
├── profiles/
│   ├── googlebot.json
│   ├── gptbot.json
│   ├── oai-searchbot.json
│   ├── chatgpt-user.json
│   ├── claudebot.json
│   ├── claude-user.json
│   ├── claude-searchbot.json
│   ├── perplexitybot.json
│   └── perplexity-user.json
├── scripts/
│   ├── fetch-as-bot.sh         # curl with bot UA, captures status/headers/body/timing
│   ├── extract-meta.sh         # title, description, canonical, og tags from HTML
│   ├── extract-jsonld.sh       # all JSON-LD blocks from HTML
│   ├── extract-links.sh        # internal/external link count and list
│   ├── check-robots.sh         # robots.txt parsing for a given UA token
│   ├── check-llmstxt.sh        # llms.txt presence, structure, content
│   ├── check-sitemap.sh        # sitemap fetch + URL inclusion check
│   ├── diff-render.sh          # Playwright: server HTML vs JS-rendered DOM (optional)
│   └── compute-score.sh        # raw check outputs → per-bot + per-category scores
├── research/
│   ├── bot-profiles-verified.md
│   └── market-landscape.md
└── docs/
    └── specs/
        └── 2026-04-11-crawl-sim-design.md
```

### Script Design

Each script is standalone:
- Takes URL/file as input, outputs JSON to stdout
- No dependencies between scripts
- Core scripts require only `curl`, `jq` (pre-installed or trivially installable)
- `diff-render.sh` requires Playwright — optional, gracefully skips if unavailable

### Skill Orchestration

SKILL.md instructs the agent to:
1. Load all profiles from `profiles/`
2. Run `fetch-as-bot.sh` for each bot UA against the target URL
3. Run `extract-meta.sh`, `extract-jsonld.sh`, `extract-links.sh` on each response
4. Run `check-robots.sh` for each bot UA token
5. Run `check-llmstxt.sh` and `check-sitemap.sh` once (bot-independent)
6. If any profile has `rendersJavaScript: true` → run `diff-render.sh`
7. Run `compute-score.sh` with all collected data
8. Interpret results: produce score card, narrative audit, and JSON report

The agent adds the intelligence layer — understanding framework context (e.g., "this is Next.js with SSR"), identifying root causes (e.g., "`ssr: false` on a dynamic import"), and recommending specific fixes with file paths.

---

## Bot Profiles

### Schema

```json
{
  "id": "gptbot",
  "name": "GPTBot",
  "vendor": "OpenAI",
  "userAgent": "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; GPTBot/1.3; +https://openai.com/gptbot",
  "robotsTxtToken": "GPTBot",
  "purpose": "training",
  "rendersJavaScript": "unknown",
  "respectsRobotsTxt": true,
  "crawlDelaySupported": "unknown",
  "ipRangesUrl": "https://openai.com/gptbot.json",
  "docs": "https://developers.openai.com/api/docs/bots",
  "confidence": {
    "rendersJavaScript": {
      "value": false,
      "level": "observed",
      "source": "Multiple third-party tests with JS-only pages show empty content"
    },
    "respectsRobotsTxt": {
      "value": true,
      "level": "official",
      "source": "https://developers.openai.com/api/docs/bots"
    }
  },
  "lastVerified": "2026-04-11",
  "relatedBots": ["oai-searchbot", "chatgpt-user"]
}
```

### Confidence Levels

- **official** — documented by the vendor on their own website
- **observed** — consistent third-party testing confirms behavior
- **inferred** — logical deduction from UA string, vendor patterns, or related bot behavior

When a claim is "observed" or "inferred", the skill output must note this: "Based on observed behavior, not official documentation."

### Day-One Profiles (9)

| Profile | Vendor | Purpose | JS Rendering (confidence) |
|---------|--------|---------|--------------------------|
| googlebot | Google | Search indexing | true (official) |
| gptbot | OpenAI | Foundation model training | false (observed) |
| oai-searchbot | OpenAI | ChatGPT search results | unknown (inferred — UA mimics Chrome 131) |
| chatgpt-user | OpenAI | User-initiated fetches | unknown |
| claudebot | Anthropic | Model training | false (observed) |
| claude-user | Anthropic | User-initiated fetches | unknown |
| claude-searchbot | Anthropic | Search quality | unknown |
| perplexitybot | Perplexity | Search indexing | false (observed) |
| perplexity-user | Perplexity | User-initiated fetches | unknown |

### Extensibility

Users add custom bots by dropping a JSON file in `profiles/`. The skill discovers all `*.json` files in the directory at runtime.

---

## Scoring System

### Categories (5)

| Category | What It Measures | Weight |
|----------|-----------------|--------|
| Accessibility | robots.txt allows, HTTP 200, no WAF block, response time | 25 |
| Content Visibility | Server HTML word count, heading structure, internal links, images with alt text | 30 |
| Structured Data | JSON-LD present, valid, page-type-appropriate (Organization, BreadcrumbList, Article, etc.) | 20 |
| Technical Signals | Meta tags complete (title, description, canonical, og), sitemap inclusion, status codes | 15 |
| AI Readiness | llms.txt present and well-structured, content citability, semantic clarity | 10 |

### Per-Bot Score (0-100)

Each bot is scored across all 5 categories. For bots with `rendersJavaScript: true` (Googlebot), Content Visibility also evaluates the rendered DOM. For bots with `rendersJavaScript: false`, only server HTML is evaluated — this is the key differentiator.

### Per-Category Score (0-100)

Same 5 categories averaged across all bots. Answers "what should I fix first?"

### Overall Composite

Weighted average of per-bot scores:
- Googlebot: 40%
- GPTBot: 20%
- ClaudeBot: 20%
- PerplexityBot: 20%

Weights are configurable via SKILL.md arguments.

### Grade Thresholds

| Score | Grade | Meaning |
|-------|-------|---------|
| 90-100 | A | Fully visible, well-structured, citable |
| 70-89 | B | Visible but missing optimization opportunities |
| 50-69 | C | Partially visible, significant gaps |
| 0-49 | F | Invisible or broken for this bot |

Plus/minus modifiers: 93+ = A, 90-92 = A-, 87-89 = B+, etc.

---

## Output

### Layer 1: Score Card (terminal)

```
╔══════════════════════════════════════════════╗
║         crawl-sim — Bot Visibility Audit     ║
║         https://example.com                  ║
╠══════════════════════════════════════════════╣
║  Overall: 88/100 (A-)                        ║
╠══════════════════════════════════════════════╣
║  Googlebot      95  A   ██████████████████░░ ║
║  GPTBot         82  B+  ████████████████░░░░ ║
║  ClaudeBot      82  B+  ████████████████░░░░ ║
║  PerplexityBot  79  B   ███████████████░░░░░ ║
╠══════════════════════════════════════════════╣
║  By Category:                                ║
║  Accessibility      96  A                    ║
║  Content Visibility 81  B+                   ║
║  Structured Data    92  A                    ║
║  Technical Signals  90  A                    ║
║  AI Readiness       65  C                    ║
╚══════════════════════════════════════════════╝
```

### Layer 2: Narrative Audit (agent-interpreted)

The LLM reads raw data and writes prioritized prose findings:

```markdown
## Priority Findings

1. **JournalSpotlight invisible to AI crawlers** (-18 pts Content Visibility for AI bots)
   `ssr: false` on dynamic import means 3 article cards don't exist in server HTML.
   
   **Fix:** Remove `ssr: false`, pass initial data from server component.
   **Impact:** +12-15 points on AI bot scores.

2. **No llms.txt** (-20 pts AI Readiness across all bots)
   ...
```

Findings are ordered by point impact — biggest score gains first.

### Layer 3: Structured JSON (programmatic)

Saved to `crawl-sim-report.json`:

```json
{
  "url": "https://example.com",
  "timestamp": "2026-04-11T22:41:00Z",
  "version": "1.0.0",
  "overall": { "score": 88, "grade": "A-" },
  "bots": {
    "googlebot": {
      "score": 95,
      "grade": "A",
      "categories": {
        "accessibility": { "score": 100, "checks": [] },
        "contentVisibility": { "score": 92, "checks": [] }
      }
    }
  },
  "categories": {
    "accessibility": { "score": 96, "grade": "A" },
    "contentVisibility": { "score": 81, "grade": "B+" }
  },
  "findings": [
    {
      "severity": "high",
      "category": "contentVisibility",
      "affectedBots": ["gptbot", "claudebot", "perplexitybot"],
      "title": "Dynamic import with ssr:false hides content from AI crawlers",
      "pointImpact": 15
    }
  ]
}
```

The JSON schema is stable for diffing reports over time.

---

## Usage

### In Claude Code

```
/crawl-sim https://yoursite.com                          # full audit
/crawl-sim https://yoursite.com --bot gptbot             # single bot
/crawl-sim https://yoursite.com --category structured-data  # category deep dive
/crawl-sim https://yoursite.com --json                   # JSON only (CI)
/crawl-sim https://yoursite.com --compare last           # diff against previous (v1 stretch)
```

### Direct script invocation (any shell)

```bash
./scripts/fetch-as-bot.sh https://yoursite.com profiles/gptbot.json
./scripts/extract-jsonld.sh < response.html
./scripts/check-robots.sh https://yoursite.com GPTBot
./scripts/compute-score.sh /tmp/audit-data/
```

### CI/CD (future)

```yaml
- name: Crawl Sim Audit
  run: |
    ./scripts/fetch-as-bot.sh $DEPLOY_URL profiles/gptbot.json > /tmp/gptbot.json
    ./scripts/compute-score.sh /tmp/ --threshold 70
```

---

## Prerequisites

- `curl` — pre-installed on macOS/Linux
- `jq` — `brew install jq` or `apt install jq`
- Optional: `npx playwright install chromium` — for Googlebot JS render comparison

---

## Non-Goals (v1)

- Full site crawling (v1 is single-page audit)
- Historical tracking dashboard (JSON output enables this externally)
- Automated fixing (the agent recommends, the human applies)
- Bot fingerprint simulation (TLS/JA4/HTTP2 — future)
- Claude Code plugin marketplace submission (GitHub distribution first)

---

## Future (post-v1)

- Multi-page crawl mode (audit N pages, aggregate scores)
- `--watch` mode (re-audit on file change during dev)
- CI GitHub Action (`uses: BraedenBDev/crawl-sim@v1`)
- Historical score tracking + trend charts
- Known Agents / Dark Visitors API integration for real bot traffic correlation
- Additional bot profiles (Bingbot, AppleBot, Meta, Bytespider)
- TLS/HTTP2 fingerprint simulation for advanced bot detection testing
