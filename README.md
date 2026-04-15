# crawl-sim

**Your site ranks #1 on Google but doesn't exist in ChatGPT search results. Here's why.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![npm version](https://img.shields.io/npm/v/@braedenbuilds/crawl-sim.svg)](https://www.npmjs.com/package/@braedenbuilds/crawl-sim)
[![Built for Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-D97757.svg)](https://claude.com/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)

Google renders your JavaScript. GPTBot, ClaudeBot, and PerplexityBot don't. They read server HTML and move on. If your content lives behind client-side hydration, AI search engines cite your competitors instead of you. Cloudflare blocks AI training crawlers by default on 20% of the web. ChatGPT-User and Perplexity-User ignore robots.txt for user-initiated fetches. Your blocking rules may not be doing what you think.

`crawl-sim` started when a production site turned out to be invisible to every AI search engine despite ranking well on Google. The cause wasn't a bug in the code. Cloudflare was blocking AI training crawlers by default. Googlebot got full HTML. GPTBot and ClaudeBot got challenge pages. No error in server logs, no opt-in, no indication anything was wrong. SEO tools said green because they only check the Google view. The gap was invisible until we fetched as each bot and compared.

This is for developers checking their own sites, agencies who need to show clients the gap with numbers, and SEO teams adding GEO to their toolkit.

Ships as a [Claude Code plugin](https://docs.claude.com/en/docs/claude-code/plugins) and a Codex-compatible local plugin. Scoring, extraction, and validation run in bash, not in your context window. A full audit uses ~2,500 output tokens vs ~10,000+ if the agent wrote the pipeline from scratch each time.

---

## Quick start

Claude Code:

```text
/plugin marketplace add BraedenBDev/crawl-sim
/plugin install crawl-sim@crawl-sim
/crawl-sim https://yoursite.com
```

Codex:

```bash
npm install -g @braedenbuilds/crawl-sim
crawl-sim install --codex
```

Then restart Codex, open Plugins, install `crawl-sim` from your local marketplace, and ask Codex to use `@crawl-sim` on a URL.

Or standalone:

```bash
git clone https://github.com/BraedenBDev/crawl-sim.git ~/plugins/crawl-sim
cd ~/plugins/crawl-sim
./scripts/fetch-as-bot.sh https://yoursite.com profiles/gptbot.json | jq '{status, wordCount, timing}'
```

Requires `curl` + `jq`. The installer will offer to set up Playwright for you, or install it manually with `npx playwright install chromium`. Without it, crawl-sim still runs but all bots score the same on content visibility because there's no JS render comparison. With Playwright, Googlebot gets scored on the full rendered page while AI bots get scored on server HTML only, which is where the interesting findings come from.

---

## Usage

Claude Code:

```text
/crawl-sim https://yoursite.com                                    # full audit
/crawl-sim https://yoursite.com --bot gptbot                       # single bot
/crawl-sim https://yoursite.com --pdf                              # audit + PDF
/crawl-sim https://yoursite.com --compare https://competitor.com   # side-by-side
/crawl-sim https://yoursite.com --json                             # JSON only (CI)
```

Codex:

```text
@crawl-sim Audit https://yoursite.com
@crawl-sim Compare https://yoursite.com and https://competitor.com
```

Output: score card, narrative with prioritized fixes, and `crawl-sim-report.json`.

Every script is standalone:

```bash
./scripts/fetch-as-bot.sh    https://yoursite.com profiles/gptbot.json
./scripts/check-robots.sh    https://yoursite.com GPTBot
./scripts/compute-score.sh   /tmp/audit-data/
./scripts/build-report.sh    /tmp/audit-data/
```

---

## Features

- **9 bot profiles** with verified UA strings, robots.txt enforceability classification, and Cloudflare tier mapping
- **Scored 0-100** across five categories (accessibility, content, structured data, technical, AI readiness) with page-type-aware schema rubrics
- **Cross-bot parity** measures whether all bots see the same content and surfaces CSR gaps as the headline finding
- **PDF reports + competitive comparisons** via `--pdf` and `--compare <url2>` for client-facing output
- **Regression coverage** for scoring, field validation, parity, report generation, and critical-fail criteria
- **Shell-native** with `curl` + `jq` only, no runtime dependencies

---

## Scoring

| Category | Weight | What it checks |
|----------|:------:|----------------|
| Accessibility | 25% | robots.txt, HTTP status, TTFB. Robots block = auto-F. |
| Content Visibility | 30% | Word count, headings, links, image alt text |
| Structured Data | 20% | JSON-LD types, required fields, page-type rubric |
| Technical Signals | 15% | title, description, canonical, OG, sitemap |
| AI Readiness | 10% | llms.txt / llms-full.txt presence and structure |

Composite weighs Googlebot 40%, GPTBot/ClaudeBot/PerplexityBot 20% each. Cross-bot parity scored separately. A 10x word-count gap between Googlebot and AI bots is the finding that matters most.

---

## Supported bots

| Profile | Vendor | Purpose | JS | robots.txt | Enforceability |
|---------|--------|---------|:--:|:----------:|:--------------:|
| `googlebot` | Google | Search | yes | yes | enforced |
| `gptbot` | OpenAI | Training | no | yes | enforced |
| `oai-searchbot` | OpenAI | Search | ? | yes | enforced |
| `chatgpt-user` | OpenAI | User fetch | ? | partial | **advisory_only** |
| `claudebot` | Anthropic | Training | no | yes | enforced |
| `claude-user` | Anthropic | User fetch | ? | yes | enforced |
| `claude-searchbot` | Anthropic | Search | ? | yes | enforced |
| `perplexitybot` | Perplexity | Search | no | yes | **stealth_risk** |
| `perplexity-user` | Perplexity | User fetch | ? | no | **advisory_only** |

**advisory_only** = vendor says user-initiated fetches may ignore robots.txt. **stealth_risk** = claims compliance, but Cloudflare has documented bypass via undeclared crawlers. Since July 2025, Cloudflare blocks training-tier bots by default on ~20% of the web.

Add a custom bot: drop a JSON file in `profiles/`. Auto-discovered.

Sources: [`research/bot-profiles-verified.md`](./research/bot-profiles-verified.md)

---

## Architecture

```
crawl-sim/
├── .claude-plugin/            plugin manifest
├── .codex-plugin/             Codex plugin manifest
├── skills/crawl-sim/
│   ├── SKILL.md               orchestrator
│   ├── profiles/              9 bot profiles
│   └── scripts/               15 scripts (fetch, extract, check, score, report, pdf)
├── test/                      regression assertions + synthetic fixtures
├── docs/output-schemas.md     JSON contracts
└── bin/install.js             npm installer
```

---

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Core rules: `curl` + `jq` only, JSON to stdout, cite sources for bot profile claims.

---

## Acknowledgments

Bot documentation from [OpenAI](https://developers.openai.com/api/docs/bots), [Anthropic](https://privacy.claude.com), [Perplexity](https://docs.perplexity.ai/docs/resources/perplexity-crawlers), and [Google Search Central](https://developers.google.com/search/docs). Cloudflare bot classification from [Cloudflare Radar](https://radar.cloudflare.com/bots) and [Cloudflare Docs](https://developers.cloudflare.com/bots/concepts/bot/). Built with [Claude Code](https://claude.com/claude-code).

---

## License

[MIT](./LICENSE) © 2026 BraedenBDev
