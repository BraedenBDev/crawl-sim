# crawl-sim

> Agent-native multi-bot web crawler simulator. See your site through the eyes of **Googlebot**, **GPTBot**, **ClaudeBot**, and **PerplexityBot** — with scored reports, prioritized findings, and structured JSON output.

**Why:** Rendering tools (Screaming Frog) focus on Googlebot only. Monitoring SaaS (Otterly, Peec) track citations but don't simulate crawls. Frameworks (Crawlee, Playwright) are raw building blocks with no bot intelligence. `crawl-sim` is the first open-source tool that combines multi-bot simulation + LLM-powered interpretation + quantified scoring — all as a Claude Code skill.

## Install

### In Claude Code (recommended)

```bash
npx crawl-sim install              # → ~/.claude/skills/crawl-sim/
npx crawl-sim install --project    # → .claude/skills/crawl-sim/
```

Then invoke with `/crawl-sim <url>` in Claude Code.

### As a standalone CLI

```bash
git clone https://github.com/BraedenBDev/crawl-sim.git
cd crawl-sim
./scripts/fetch-as-bot.sh https://yoursite.com profiles/gptbot.json
```

## Prerequisites

- `curl` — pre-installed on macOS/Linux
- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)
- `playwright` (optional) — for `diff-render.sh` Googlebot JS comparison: `npx playwright install chromium`

## Usage

### In Claude Code

```
/crawl-sim https://yoursite.com                          # full audit
/crawl-sim https://yoursite.com --bot gptbot             # single bot
/crawl-sim https://yoursite.com --category structured-data
/crawl-sim https://yoursite.com --json                   # JSON only (CI)
```

The skill orchestrates all scripts, then Claude interprets the results and produces:

1. **Score card** — ASCII overview with per-bot + per-category scores and grades
2. **Narrative audit** — prose findings prioritized by point impact, with actionable fixes
3. **JSON report** — structured data saved to `crawl-sim-report.json`

### Direct script invocation

Each script is standalone and outputs JSON to stdout:

```bash
./scripts/fetch-as-bot.sh https://yoursite.com profiles/gptbot.json
./scripts/extract-meta.sh    < response.html
./scripts/extract-jsonld.sh  < response.html
./scripts/extract-links.sh   https://yoursite.com < response.html
./scripts/check-robots.sh    https://yoursite.com GPTBot
./scripts/check-llmstxt.sh   https://yoursite.com
./scripts/check-sitemap.sh   https://yoursite.com
./scripts/compute-score.sh   /tmp/audit-data/
```

Chain them together for CI:

```yaml
- name: crawl-sim audit
  run: |
    ./scripts/fetch-as-bot.sh "$DEPLOY_URL" profiles/gptbot.json > /tmp/gptbot.json
    ./scripts/compute-score.sh /tmp/ > /tmp/score.json
    jq -e '.overall.score >= 70' /tmp/score.json
```

## Scoring

Each bot is scored 0–100 across five categories:

| Category | Weight | Measures |
|----------|--------|----------|
| Accessibility | 25 | robots.txt allows, HTTP 200, response time |
| Content Visibility | 30 | server HTML word count, headings, internal links, image alt text |
| Structured Data | 20 | JSON-LD presence, validity, page-appropriate `@type` |
| Technical Signals | 15 | title/description/canonical/og meta, sitemap inclusion |
| AI Readiness | 10 | llms.txt structure, content citability |

**Overall composite** is a weighted average across bots:

- Googlebot 40% — still the primary search driver
- GPTBot, ClaudeBot, PerplexityBot — 20% each — the AI visibility tier

**Grades:** `93+ = A`, `90–92 = A-`, `87–89 = B+`, …, `<60 = F`.

The key differentiator: bots with `rendersJavaScript: false` (GPTBot, ClaudeBot, PerplexityBot) are scored against **server HTML only**. Googlebot can be scored against the rendered DOM via the optional `diff-render.sh`. This surfaces CSR hydration issues that hide content from AI crawlers.

## Bot Profiles

| Profile | Vendor | Purpose | JS Render |
|---------|--------|---------|-----------|
| `googlebot` | Google | Search indexing | **yes** (official) |
| `gptbot` | OpenAI | Model training | no (observed) |
| `oai-searchbot` | OpenAI | ChatGPT search | unknown (inferred) |
| `chatgpt-user` | OpenAI | User fetches | unknown |
| `claudebot` | Anthropic | Model training | no (observed) |
| `claude-user` | Anthropic | User fetches | unknown |
| `claude-searchbot` | Anthropic | Search quality | unknown |
| `perplexitybot` | Perplexity | Search indexing | no (observed) |
| `perplexity-user` | Perplexity | User fetches | unknown |

Every profile is backed by official vendor docs where possible — see `research/bot-profiles-verified.md`. When a claim is "observed" or "inferred" rather than "official", the skill output notes this.

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

## Contributing

- Update bot profiles when vendor docs change — include a link in `research/bot-profiles-verified.md`.
- Keep scripts dependency-free (curl + jq only). `diff-render.sh` is the single exception.
- All scripts must output valid JSON to stdout and be testable against a live URL.

## License

MIT — see [LICENSE](./LICENSE).
