# crawl-sim

**See your site through the eyes of Googlebot, GPTBot, ClaudeBot, and PerplexityBot.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![npm version](https://img.shields.io/npm/v/@braedenbuilds/crawl-sim.svg)](https://www.npmjs.com/package/@braedenbuilds/crawl-sim)
[![Built for Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-D97757.svg)](https://claude.com/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)

`crawl-sim` is the first open-source, **agent-native multi-bot web crawler simulator**. It audits a URL from the perspective of each major crawler — Google's search bot, OpenAI's GPTBot, Anthropic's ClaudeBot, Perplexity's crawler, and more — then produces a quantified score card, prioritized findings, and structured JSON output.

It ships as a [Claude Code skill](https://docs.claude.com/en/docs/claude-code/skills) backed by standalone shell scripts, so the intelligence lives in the agent and the plumbing stays debuggable.

---

## Why this exists

The crawler-simulation market has a gap. Most tools pick one lane:

| Category | Examples | What they miss |
|----------|----------|----------------|
| **Rendering tools** | Screaming Frog, TametheBot | Googlebot only — no AI crawlers |
| **Monitoring SaaS** | Otterly, ZipTie, Peec | Track citations but don't simulate crawls |
| **Frameworks** | Crawlee, Playwright | Raw building blocks with no bot intelligence |

No existing tool combines **multi-bot simulation + LLM-powered interpretation + quantified scoring** in an agent-native format. `crawl-sim` does.

The concept was validated manually: a curl-as-GPTBot + Claude analysis caught a real SSR bug (`ssr: false` on a dynamic import) that was silently hiding article cards from AI crawlers on a production site.

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

### In Claude Code (recommended)

```bash
npm install -g @braedenbuilds/crawl-sim
crawl-sim install              # → ~/.claude/skills/crawl-sim/
crawl-sim install --project    # → .claude/skills/crawl-sim/
```

Then in Claude Code:

```
/crawl-sim https://yoursite.com
```

Claude runs the full pipeline, interprets the results, and returns a score card plus prioritized findings.

> **Why `npm install -g` instead of `npx`?** Recent versions of npx have a known issue linking bins for scoped single-bin packages in ephemeral installs. A persistent global install avoids the problem entirely. The git clone path below is the zero-npm fallback.

### As a standalone CLI

```bash
git clone https://github.com/BraedenBDev/crawl-sim.git
cd crawl-sim
./scripts/fetch-as-bot.sh https://yoursite.com profiles/gptbot.json | jq .
```

You can also clone directly into the Claude Code skills directory:

```bash
git clone https://github.com/BraedenBDev/crawl-sim.git ~/.claude/skills/crawl-sim
```

### Prerequisites

- **`curl`** — pre-installed on macOS/Linux
- **`jq`** — `brew install jq` (macOS) or `apt install jq` (Linux)
- **`playwright`** (optional) — for Googlebot JS-render comparison: `npx playwright install chromium`

---

## Features

- **Multi-bot simulation.** Nine verified bot profiles covering Google, OpenAI, Anthropic, and Perplexity — including the bot-vs-user-agent distinction (e.g., `ChatGPT-User` officially ignores robots.txt; `claude-user` respects it).
- **Quantified scoring.** Each bot is graded 0–100 across five categories with letter grades A through F, plus a weighted composite score.
- **Agent-native interpretation.** The Claude Code skill reads raw data, identifies root causes (framework signals, hydration boundaries, soft-404s), and recommends specific fixes.
- **Three-layer output.** Terminal score card, prose narrative, and structured JSON — so humans and CI both get what they need.
- **Confidence transparency.** Every claim is tagged `official`, `observed`, or `inferred`. The skill notes when recommendations depend on observed-but-undocumented behavior.
- **Shell-native core.** All checks use only `curl` + `jq`. No Node, no Python, no Docker. Each script is independently invokable.
- **Extensible.** Drop a new profile JSON into `profiles/` and it's auto-discovered.

---

## Usage

### Claude Code skill

```
/crawl-sim https://yoursite.com                            # full audit
/crawl-sim https://yoursite.com --bot gptbot               # single bot
/crawl-sim https://yoursite.com --category structured-data # category deep-dive
/crawl-sim https://yoursite.com --json                     # JSON only (for CI)
```

Output is a three-layer report:

1. **Score card** — ASCII overview with per-bot and per-category scores.
2. **Narrative audit** — prose findings ranked by point impact, with fix recommendations.
3. **JSON report** — saved to `crawl-sim-report.json` for diffing and automation.

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
./scripts/compute-score.sh   --page-type root /tmp/audit-data/   # override URL heuristic
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
| **Accessibility** | 25 | robots.txt allows, HTTP 200, response time |
| **Content Visibility** | 30 | server HTML word count, heading structure, internal links, image alt text |
| **Structured Data** | 20 | JSON-LD presence, validity, page-type-aware `@type` rubric (root / detail / archive / faq / about / contact / generic) |
| **Technical Signals** | 15 | title / description / canonical / OG meta, sitemap inclusion |
| **AI Readiness** | 10 | `llms.txt` structure, content citability |

**Overall composite** weighs bots by reach:

- Googlebot **40%** — still the primary search driver
- GPTBot, ClaudeBot, PerplexityBot — **20% each** — the AI visibility tier

**Grade thresholds**

| Score | Grade | Meaning |
|-------|:-----:|---------|
| 93–100 | A | Fully visible, well-structured, citable |
| 90–92 | A- | Near-perfect with minor gaps |
| 80–89 | B / B+ / B- | Visible but missing optimization opportunities |
| 70–79 | C+ / C / C- | Partially visible, significant gaps |
| 60–69 | D+ / D / D- | Major issues — limited discoverability |
| 0–59 | F | Invisible or broken for this bot |

**The key differentiator:** bots with `rendersJavaScript: false` (GPTBot, ClaudeBot, PerplexityBot) are scored against **server HTML only**. Googlebot can be scored against the rendered DOM via the optional `diff-render.sh`. This surfaces CSR hydration issues that hide content from AI crawlers — exactly the kind of bug SEO tools don't catch because they're built around Googlebot's headless-Chrome behavior.

---

## Supported bots

| Profile | Vendor | Purpose | JS Render | Respects robots.txt |
|---------|--------|---------|:---------:|:-------------------:|
| `googlebot` | Google | Search indexing | **yes** (official) | yes |
| `gptbot` | OpenAI | Model training | no (observed) | yes |
| `oai-searchbot` | OpenAI | ChatGPT search | unknown (inferred) | yes |
| `chatgpt-user` | OpenAI | User fetches | unknown | partial (*) |
| `claudebot` | Anthropic | Model training | no (observed) | yes |
| `claude-user` | Anthropic | User fetches | unknown | yes |
| `claude-searchbot` | Anthropic | Search quality | unknown | yes |
| `perplexitybot` | Perplexity | Search indexing | no (observed) | yes |
| `perplexity-user` | Perplexity | User fetches | unknown | no (*) |

\* Officially documented as ignoring robots.txt for user-initiated fetches.

Every profile is backed by official vendor documentation where possible. See [`research/bot-profiles-verified.md`](./research/bot-profiles-verified.md) for sources and confidence levels. When a claim is `observed` or `inferred` rather than `official`, the skill output notes this transparently.

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
  "rendersJavaScript": false,
  "respectsRobotsTxt": true,
  "lastVerified": "2026-04-11"
}
```

---

## Architecture

```
crawl-sim/
├── SKILL.md               # Claude Code orchestrator skill
├── bin/install.js         # npm installer
├── profiles/              # 9 verified bot profiles (JSON)
├── scripts/
│   ├── fetch-as-bot.sh    # curl with bot UA → JSON (status/headers/body/timing)
│   ├── extract-meta.sh    # title, description, OG, headings, images
│   ├── extract-jsonld.sh  # JSON-LD @type detection
│   ├── extract-links.sh   # internal/external link classification
│   ├── check-robots.sh    # robots.txt parsing per UA token
│   ├── check-llmstxt.sh   # llms.txt presence and structure
│   ├── check-sitemap.sh   # sitemap.xml URL inclusion
│   ├── diff-render.sh     # optional Playwright server-vs-rendered comparison
│   └── compute-score.sh   # aggregates all checks → per-bot + per-category scores
├── research/              # Verified bot data sources
└── docs/specs/            # Design docs
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

- **Keep the core dependency-free** — `curl` + `jq` only. `diff-render.sh` is the single Playwright exception.
- **Every script outputs valid JSON to stdout** and is testable against a live URL.
- **Cite sources** when adding or updating bot profiles — every behavioral claim needs a vendor doc link or a reproducible observation.

---

## Acknowledgments

- **Bot documentation** from [OpenAI](https://developers.openai.com/api/docs/bots), [Anthropic](https://privacy.claude.com), [Perplexity](https://docs.perplexity.ai/docs/resources/perplexity-crawlers), and [Google Search Central](https://developers.google.com/search/docs).
- **Prior art** in the space: [Dark Visitors](https://darkvisitors.com), [CrawlerCheck](https://crawlercheck.com), [Cloudflare Radar](https://radar.cloudflare.com).
- Built with [Claude Code](https://claude.com/claude-code).

---

## License

[MIT](./LICENSE) © 2026 BraedenBDev

Free for personal and commercial use. If `crawl-sim` helps your project, a GitHub star or a mention is always appreciated.
