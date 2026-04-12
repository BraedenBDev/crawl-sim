# crawl-sim

**See your site through the eyes of Googlebot, GPTBot, ClaudeBot, and PerplexityBot.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![npm version](https://img.shields.io/npm/v/@braedenbuilds/crawl-sim.svg)](https://www.npmjs.com/package/@braedenbuilds/crawl-sim)
[![Built for Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-D97757.svg)](https://claude.com/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)

`crawl-sim` is the first open-source, **agent-native multi-bot web crawler simulator**. It audits a URL from the perspective of each major crawler — Google's search bot, OpenAI's GPTBot, Anthropic's ClaudeBot, Perplexity's crawler, and more — then produces a quantified score card, prioritized findings, and structured JSON output.

It ships as a [Claude Code plugin](https://docs.claude.com/en/docs/claude-code/plugins) backed by standalone shell scripts, so the intelligence lives in the agent and the plumbing stays debuggable.

---

## Why this exists

The crawler-simulation market has a gap. Most tools pick one lane:

| Category | Examples | What they miss |
|----------|----------|----------------|
| **Rendering tools** | Screaming Frog, TametheBot | Googlebot only — no AI crawlers |
| **Monitoring SaaS** | Otterly, ZipTie, Peec | Track citations but don't simulate crawls |
| **Frameworks** | Crawlee, Playwright | Raw building blocks with no bot intelligence |

No existing tool combines **multi-bot simulation + LLM-powered interpretation + quantified scoring** in an agent-native format. `crawl-sim` does.

---

## Why a plugin instead of prompting Claude directly?

Claude Code has Bash, curl, and jq. It *could* write all of this from scratch every time you ask. But that's the wrong comparison. Here's what actually happens:

| | Without crawl-sim | With crawl-sim |
|---|---|---|
| **User prompt** | ~500 tokens explaining what you want | `/crawl-sim https://site.com` — 20 tokens |
| **Bot UA strings** | Claude guesses or hallucinates them | 9 verified profiles with researched data |
| **Scoring logic** | Claude invents it mid-conversation (~3,000 tokens) | `compute-score.sh` runs in bash — 0 tokens |
| **Edge case handling** | Claude debugs live (~2,000 tokens) | 70 regression tests already caught those bugs |
| **robots.txt analysis** | Generic "blocked/not blocked" | Enforceability context — is the block actually enforceable? |
| **Total output tokens** | ~10,000+ per audit | ~2,500 per audit |

The scripts do the heavy lifting in bash, not in your context window. Scoring, extraction, field validation, parity computation — all zero tokens. Claude only spends tokens on interpretation.

**What this means in practice:**
- **Consistent.** Same rubric every run, not dependent on how Claude feels today. Page-type-aware schema scoring, cross-bot parity, critical-fail criteria — all tested.
- **Accurate.** Bot profiles include Cloudflare tier classification, robots.txt enforceability, and documented bypass behavior. You'd have to research this yourself otherwise.
- **Fast.** One command replaces 30 minutes of ad-hoc scripting and guesswork.
- **Debuggable.** Every script is standalone, outputs JSON, and can be run independently. When something looks wrong, you inspect the intermediate files — not a wall of LLM output.

---

## Table of contents

- [Quick start](#quick-start)
- [Features](#features)
- [Usage](#usage)
- [Scoring system](#scoring-system)
- [Supported bots](#supported-bots)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [License](#license)

---

## Quick start

### As a Claude Code plugin (recommended)

```
/plugin marketplace add BraedenBDev/crawl-sim
/plugin install crawl-sim@crawl-sim
```

Then invoke:

```
/crawl-sim https://yoursite.com
```

Claude runs the full pipeline, interprets the results, and returns a score card plus prioritized findings.

> **Verified:** Plugin installs from GitHub via the marketplace route, discovers the skill at `skills/crawl-sim/SKILL.md`, and all 15 scripts + 9 profiles are executable from the plugin cache path.

### Via npm (alternative)

```bash
npm install -g @braedenbuilds/crawl-sim
crawl-sim install              # → ~/.claude/skills/crawl-sim/
crawl-sim install --project    # → .claude/skills/crawl-sim/
```

### As a standalone CLI

```bash
git clone https://github.com/BraedenBDev/crawl-sim.git
cd crawl-sim
./scripts/fetch-as-bot.sh https://yoursite.com profiles/gptbot.json | jq .
```

### Prerequisites

- **`curl`** — pre-installed on macOS/Linux
- **`jq`** — `brew install jq` (macOS) or `apt install jq` (Linux)
- **`playwright`** (optional) — for Googlebot JS-render comparison: `npx playwright install chromium`
- **Chrome or Playwright** (optional) — for PDF report generation

---

## Features

- **Multi-bot simulation.** Nine verified bot profiles covering Google, OpenAI, Anthropic, and Perplexity — including the bot-vs-user-agent distinction (e.g., `ChatGPT-User` officially ignores robots.txt; `claude-user` respects it).
- **Quantified scoring.** Each bot is graded 0–100 across five categories with letter grades A through F, plus a weighted composite score.
- **Page-type-aware rubric.** The structured-data category derives the page type from the URL (`root` / `detail` / `archive` / `faq` / `about` / `contact` / `generic`) and applies a per-type schema rubric. A homepage shipping `Organization` + `WebSite` scores 100 without being penalized for missing `BreadcrumbList` or `FAQPage`. Override the detection with `--page-type <type>` when the URL heuristic picks wrong.
- **Self-explaining scores.** Every `structuredData` block ships `pageType`, `expected`, `present`, `missing`, `violations` (with `confidence` levels), `calculation`, and `notes` — so the narrative reads the scorer's reasoning directly instead of guessing.
- **Schema field validation.** Checks that present schemas include required fields per schema.org type (e.g., Organization must have `name` + `url`). Missing required fields produce `missing_required_field` violations.
- **Cross-bot parity scoring.** Measures word-count divergence across bots. Perfect parity = 100/A. Severe CSR mismatch (Googlebot sees 10x more than GPTBot) = F with interpretation.
- **robots.txt enforceability.** Each bot profile carries `robotsTxtEnforceability` (`enforced`, `advisory_only`, `stealth_risk`) based on documented compliance. When robots.txt blocks a bot that ignores it, the narrative flags the block as unenforceable.
- **Cloudflare-aware.** Bot profiles include `cloudflareCategory` (`ai_crawler`, `ai_search`, `ai_assistant`) matching Cloudflare's three-tier classification. Since July 2025, Cloudflare blocks AI training crawlers by default on ~20% of the web.
- **PDF reports.** Generate styled HTML audit reports and convert to PDF via Chrome or Playwright. Pass `--pdf` for a one-command PDF to Desktop.
- **Comparative audits.** `--compare <url2>` runs two full audits and produces a side-by-side VS report with category deltas, per-bot comparison, and winner determination. Combine with `--pdf` for a comparison PDF.
- **Consolidated report.** `build-report.sh` merges score data with raw per-bot extraction data into a single `crawl-sim-report.json`. The narrative reads one file instead of 8+.
- **Agent-native interpretation.** The Claude Code skill reads raw data, identifies root causes (framework signals, hydration boundaries, soft-404s), and recommends specific fixes.
- **Three-layer output.** Terminal score card, prose narrative, and structured JSON — so humans and CI both get what they need.
- **Shell-native core.** All checks use only `curl` + `jq`. No Node, no Python, no Docker. Each script is independently invokable.
- **Regression-tested.** `npm test` runs a 70-assertion scoring suite against synthetic fixtures, covering URL→page-type detection, per-type rubrics, field validation, parity scoring, critical-fail criteria, and golden non-structured output.
- **Extensible.** Drop a new profile JSON into `profiles/` and it's auto-discovered.

---

## Usage

### Claude Code skill

```
/crawl-sim https://yoursite.com                                    # full audit
/crawl-sim https://yoursite.com --bot gptbot                       # single bot
/crawl-sim https://yoursite.com --category structured-data         # category deep-dive
/crawl-sim https://yoursite.com --json                             # JSON only (for CI)
/crawl-sim https://yoursite.com --pdf                              # audit + PDF report
/crawl-sim https://yoursite.com --compare https://competitor.com   # side-by-side comparison
/crawl-sim https://yoursite.com --compare https://competitor.com --pdf  # comparison PDF
```

The skill auto-detects page type from the URL. Pass `--page-type root|detail|archive|faq|about|contact|generic` when the URL heuristic picks the wrong type (e.g., a homepage at `/en/` that parses as `generic`).

Output is a three-layer report:

1. **Score card** — ASCII overview with per-bot and per-category scores. When content parity is high (all bots see the same content), bot rows collapse to a single line.
2. **Narrative audit** — prose findings ranked by point impact, with fix recommendations. Includes robots.txt enforceability context for each bot.
3. **JSON report** — saved to `crawl-sim-report.json` with score data + raw per-bot extraction data for diffing and automation.

### Direct script invocation

Every script is standalone and outputs JSON to stdout:

```bash
./scripts/fetch-as-bot.sh    https://yoursite.com profiles/gptbot.json
./scripts/extract-meta.sh    < response.html
./scripts/extract-jsonld.sh  < response.html
./scripts/extract-links.sh   https://yoursite.com < response.html
./scripts/check-robots.sh    https://yoursite.com GPTBot
./scripts/check-llmstxt.sh   https://yoursite.com
./scripts/check-sitemap.sh   https://yoursite.com
./scripts/compute-score.sh   /tmp/audit-data/
./scripts/build-report.sh    /tmp/audit-data/               # consolidated report
./scripts/generate-report-html.sh crawl-sim-report.json      # HTML report
./scripts/html-to-pdf.sh     report.html output.pdf          # PDF conversion
```

### CI/CD

```yaml
- name: crawl-sim audit
  run: |
    ./scripts/fetch-as-bot.sh "$DEPLOY_URL" profiles/gptbot.json > /tmp/gptbot.json
    ./scripts/compute-score.sh /tmp/ > /tmp/score.json
    jq -e '.overall.score >= 70' /tmp/score.json
```

---

## Scoring system

Each bot is scored 0–100 across five weighted categories:

| Category | Weight | Measures |
|----------|:------:|----------|
| **Accessibility** | 25 | robots.txt allows, HTTP 200, response time. Robots blocking = auto-F (critical-fail). |
| **Content Visibility** | 30 | server HTML word count, heading structure, internal links, image alt text |
| **Structured Data** | 20 | JSON-LD presence, validity, per-type `@type` rubric, required field validation |
| **Technical Signals** | 15 | title / description / canonical / OG meta, sitemap inclusion |
| **AI Readiness** | 10 | `llms.txt` and/or `llms-full.txt` structure, content citability |

**Overall composite** weighs bots by reach:

- Googlebot **40%** — still the primary search driver
- GPTBot, ClaudeBot, PerplexityBot — **20% each** — the AI visibility tier

**Cross-bot parity** is scored separately (not part of the composite). It measures whether all bots see the same content. A severe CSR mismatch (Googlebot renders JS and sees 10x more content than AI bots) surfaces as the headline finding.

**Grade thresholds**

| Score | Grade | Meaning |
|-------|:-----:|---------|
| 93–100 | A | Fully visible, well-structured, citable |
| 90–92 | A- | Near-perfect with minor gaps |
| 80–89 | B / B+ / B- | Visible but missing optimization opportunities |
| 70–79 | C+ / C / C- | Partially visible, significant gaps |
| 60–69 | D+ / D / D- | Major issues — limited discoverability |
| 0–59 | F | Invisible or broken for this bot |

---

## Supported bots

| Profile | Vendor | Purpose | JS Render | robots.txt | Enforceability | Cloudflare tier |
|---------|--------|---------|:---------:|:----------:|:--------------:|:---------------:|
| `googlebot` | Google | Search | **yes** | yes | enforced | search_engine |
| `gptbot` | OpenAI | Training | no | yes | enforced | ai_crawler |
| `oai-searchbot` | OpenAI | Search | unknown | yes | enforced | ai_search |
| `chatgpt-user` | OpenAI | User fetch | unknown | partial | **advisory_only** | ai_assistant |
| `claudebot` | Anthropic | Training | no | yes | enforced | ai_crawler |
| `claude-user` | Anthropic | User fetch | unknown | yes | enforced | ai_assistant |
| `claude-searchbot` | Anthropic | Search | unknown | yes | enforced | ai_search |
| `perplexitybot` | Perplexity | Search | no | yes | **stealth_risk** | ai_search |
| `perplexity-user` | Perplexity | User fetch | unknown | no | **advisory_only** | ai_assistant |

**Enforceability key:**
- **enforced** — the bot respects robots.txt directives
- **advisory_only** — the bot's vendor has stated user-initiated fetches may ignore robots.txt. Blocking via robots.txt alone has no effect; network-level enforcement (e.g., Cloudflare WAF) is needed.
- **stealth_risk** — the bot claims compliance, but Cloudflare has documented instances of undeclared crawlers with generic user-agent strings bypassing blocks.

**Cloudflare context:** Since July 2025, Cloudflare blocks all `ai_crawler` tier bots by default on new domains (~20% of the web). `ai_search` and `ai_assistant` bots are in Cloudflare's verified bots directory and are not blocked by the default toggle.

Every profile is backed by official vendor documentation where possible. See [`research/bot-profiles-verified.md`](./research/bot-profiles-verified.md) for sources and confidence levels.

### Adding a custom bot

Drop a JSON file in `profiles/`. The skill auto-discovers all `*.json` files.

```json
{
  "id": "mybot",
  "name": "MyBot",
  "vendor": "Example Corp",
  "userAgent": "Mozilla/5.0 ... MyBot/1.0",
  "robotsTxtToken": "MyBot",
  "purpose": "search",
  "cloudflareCategory": "ai_search",
  "robotsTxtEnforceability": "enforced",
  "rendersJavaScript": false,
  "respectsRobotsTxt": true,
  "lastVerified": "2026-04-12"
}
```

---

## Architecture

```
crawl-sim/
├── .claude-plugin/           # Plugin manifest + marketplace config
│   ├── plugin.json
│   └── marketplace.json
├── skills/crawl-sim/         # Plugin-structured skill directory
│   ├── SKILL.md              # Claude Code orchestrator skill
│   ├── profiles/             # 9 verified bot profiles (JSON)
│   ├── scripts/
│   │   ├── _lib.sh               # shared helpers (URL parsing, page-type detection)
│   │   ├── fetch-as-bot.sh       # curl with bot UA → JSON (status/headers/body/timing/redirects)
│   │   ├── extract-meta.sh       # title, description, OG, headings, images
│   │   ├── extract-jsonld.sh     # JSON-LD types + per-block field names
│   │   ├── extract-links.sh      # internal/external link classification (flat schema)
│   │   ├── check-robots.sh       # robots.txt parsing per UA token
│   │   ├── check-llmstxt.sh      # llms.txt + llms-full.txt presence and structure
│   │   ├── check-sitemap.sh      # sitemap.xml URL inclusion + sample URLs
│   │   ├── diff-render.sh        # optional Playwright server-vs-rendered comparison
│   │   ├── compute-score.sh      # aggregates all checks → per-bot + per-category scores
│   │   ├── schema-fields.sh      # required field definitions per schema.org type
│   │   ├── build-report.sh       # consolidate score + raw data into single report
│   │   ├── generate-report-html.sh   # styled HTML audit report
│   │   ├── generate-compare-html.sh  # side-by-side comparison report
│   │   └── html-to-pdf.sh        # Chrome → Playwright PDF renderer
│   └── templates/             # HTML templates for report generation
├── bin/install.js             # npm installer (copies to ~/.claude/skills/)
├── test/
│   ├── run-scoring-tests.sh   # 70-assertion bash harness (run with `npm test`)
│   └── fixtures/              # synthetic RUN_DIR fixtures for regression tests
├── research/                  # Verified bot data sources
└── docs/
    ├── output-schemas.md      # JSON contract for every script's stdout
    ├── issues/                # Accuracy handoff documentation
    └── plans/                 # Sprint implementation plans
```

The shell scripts are the plumbing. The Claude Code skill is the intelligence — it reads the raw JSON, understands framework context (Next.js, Nuxt, SPAs), identifies root causes, and writes actionable recommendations.

---

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md) for details on:

- Reporting bugs and requesting features
- Adding or updating bot profiles when vendor docs change
- Writing new check scripts (must be `curl` + `jq` only, must output JSON)
- Running the integration test suite
- Coding standards and commit conventions

Quick principles:

- **Keep the core dependency-free** — `curl` + `jq` only. `diff-render.sh` and `html-to-pdf.sh` are the optional-dependency exceptions.
- **Every script outputs valid JSON to stdout** and is testable against a live URL.
- **Cite sources** when adding or updating bot profiles — every behavioral claim needs a vendor doc link or a reproducible observation.

---

## Acknowledgments

- **Bot documentation** from [OpenAI](https://developers.openai.com/api/docs/bots), [Anthropic](https://privacy.claude.com), [Perplexity](https://docs.perplexity.ai/docs/resources/perplexity-crawlers), and [Google Search Central](https://developers.google.com/search/docs).
- **Cloudflare bot classification** from [Cloudflare Radar](https://radar.cloudflare.com/bots) and [Cloudflare Docs](https://developers.cloudflare.com/bots/concepts/bot/).
- **Prior art** in the space: [Dark Visitors](https://darkvisitors.com), [CrawlerCheck](https://crawlercheck.com).
- Built with [Claude Code](https://claude.com/claude-code).

---

## License

[MIT](./LICENSE) © 2026 BraedenBDev

Free for personal and commercial use. If `crawl-sim` helps your project, a GitHub star or a mention is always appreciated.
