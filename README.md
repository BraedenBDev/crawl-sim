# crawl-sim

**Your site ranks #1 on Google but doesn't exist in ChatGPT search results. Here's why.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![npm version](https://img.shields.io/npm/v/@braedenbuilds/crawl-sim.svg)](https://www.npmjs.com/package/@braedenbuilds/crawl-sim)
[![Built for Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-D97757.svg)](https://claude.com/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)

Google renders your JavaScript. GPTBot, ClaudeBot, and PerplexityBot don't — they read server HTML and move on. If your content lives behind client-side hydration, AI search engines cite your competitors instead of you. Cloudflare blocks AI training crawlers by default on 20% of the web. ChatGPT-User and Perplexity-User ignore robots.txt for user-initiated fetches. Your blocking rules may not be doing what you think.

`crawl-sim` was built from a real bug: `ssr: false` on a dynamic import was hiding article cards from every AI crawler on a production site. Screaming Frog didn't catch it — it only simulates Googlebot. The fix took two minutes once we could see the problem. Finding the problem took weeks.

This is for developers checking their own sites, agencies who need to show clients the gap with numbers, and SEO teams adding GEO to their toolkit.

Ships as a [Claude Code plugin](https://docs.claude.com/en/docs/claude-code/plugins). Scripts run in bash (`curl` + `jq`), not in your context window — scoring and extraction cost zero tokens.

---

## Quick start

```
/plugin marketplace add BraedenBDev/crawl-sim
/plugin install crawl-sim@crawl-sim
/crawl-sim https://yoursite.com
```

Or via npm:

```bash
npm install -g @braedenbuilds/crawl-sim && crawl-sim install
```

Or standalone:

```bash
git clone https://github.com/BraedenBDev/crawl-sim.git
./crawl-sim/scripts/fetch-as-bot.sh https://yoursite.com profiles/gptbot.json | jq .
```

Requires `curl` + `jq`. Optional: `playwright` (JS render comparison), Chrome (PDF reports).

---

## Usage

```
/crawl-sim https://yoursite.com                                    # full audit
/crawl-sim https://yoursite.com --bot gptbot                       # single bot
/crawl-sim https://yoursite.com --pdf                              # audit + PDF
/crawl-sim https://yoursite.com --compare https://competitor.com   # side-by-side
/crawl-sim https://yoursite.com --json                             # JSON only (CI)
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
- **Scored 0–100** across five categories (accessibility, content, structured data, technical, AI readiness) with page-type-aware schema rubrics
- **Cross-bot parity** — measures whether all bots see the same content; surfaces CSR gaps as the headline finding
- **PDF reports + competitive comparisons** — `--pdf` and `--compare <url2>` for client-facing output
- **70 regression tests** covering scoring, field validation, parity, critical-fail criteria
- **Shell-native** — `curl` + `jq` only, no runtime dependencies

---

## Scoring

| Category | Weight | What it checks |
|----------|:------:|----------------|
| Accessibility | 25% | robots.txt, HTTP status, TTFB. Robots block = auto-F. |
| Content Visibility | 30% | Word count, headings, links, image alt text |
| Structured Data | 20% | JSON-LD types, required fields, page-type rubric |
| Technical Signals | 15% | title, description, canonical, OG, sitemap |
| AI Readiness | 10% | llms.txt / llms-full.txt presence and structure |

Composite weighs Googlebot 40%, GPTBot/ClaudeBot/PerplexityBot 20% each. Cross-bot parity scored separately — a 10x word-count gap between Googlebot and AI bots is the finding that matters most.

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
├── .claude-plugin/            # plugin manifest
├── skills/crawl-sim/
│   ├── SKILL.md               # orchestrator
│   ├── profiles/              # 9 bot profiles
│   └── scripts/               # 15 scripts (fetch, extract, check, score, report, pdf)
├── test/                      # 70 assertions + synthetic fixtures
├── docs/output-schemas.md     # JSON contracts
└── bin/install.js             # npm installer
```

---

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Core rules: `curl` + `jq` only, JSON to stdout, cite sources for bot profile claims.

---

## License

[MIT](./LICENSE) © 2026 BraedenBDev
