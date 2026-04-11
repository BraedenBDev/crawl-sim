# Bot Profiles — Verified Sources

Research compiled 2026-04-11. Each claim is sourced to official documentation or credible third-party analysis.

## OpenAI (3 bots)

**Source:** https://developers.openai.com/api/docs/bots

### GPTBot
- **UA String:** `Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; GPTBot/1.3; +https://openai.com/gptbot`
- **Purpose:** Training data for generative AI foundation models
- **Respects robots.txt:** Yes
- **Crawl-delay:** Not documented
- **JS Rendering:** NOT officially documented. Observational evidence says No.
- **IP Ranges:** https://openai.com/gptbot.json
- **Notes:** "Disallowing GPTBot indicates a site's content should not be used in training generative AI foundation models."

### OAI-SearchBot
- **UA String:** `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36; compatible; OAI-SearchBot/1.3; +https://openai.com/searchbot`
- **Purpose:** Surface websites in ChatGPT search results
- **Respects robots.txt:** Yes
- **Crawl-delay:** Not documented
- **JS Rendering:** NOT documented. UA mimics Chrome 131 — may indicate rendering capability, but unconfirmed.
- **IP Ranges:** https://openai.com/searchbot.json
- **Notes:** "Sites that are opted out of OAI-SearchBot will not be shown in ChatGPT search answers, though can still appear as navigational links."

### ChatGPT-User
- **UA String:** `Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; ChatGPT-User/1.0; +https://openai.com/bot`
- **Purpose:** User-initiated fetches in ChatGPT and Custom GPTs
- **Respects robots.txt:** **"Because these actions are initiated by a user, robots.txt rules may not apply."** (official)
- **Crawl-delay:** Not documented
- **JS Rendering:** Not documented
- **IP Ranges:** https://openai.com/chatgpt-user.json
- **Notes:** Not used for automatic crawling. Not used to determine search appearance.

---

## Anthropic (3 bots)

**Source:** https://privacy.claude.com/en/articles/8896518-does-anthropic-crawl-data-from-the-web-and-how-can-site-owners-block-the-crawler
**Analysis:** https://ppc.land/anthropic-clarifies-what-its-three-web-crawlers-do-and-how-to-block-them/

### ClaudeBot
- **UA String:** `ClaudeBot` (short token for robots.txt matching)
- **Purpose:** Training data — "collects web content that could potentially contribute to AI model training"
- **Respects robots.txt:** Yes
- **Crawl-delay:** **Yes** (non-standard, explicitly supported)
- **JS Rendering:** NOT documented. Observational evidence says No.
- **IP Ranges:** Not published. Anthropic explicitly states "blocking IP addresses will not reliably work."
- **Notes:** Blocking signals content should be excluded from AI training datasets.

### Claude-User
- **UA String:** `Claude-User`
- **Purpose:** User-initiated fetches — "When individuals ask questions to Claude, it may access websites"
- **Respects robots.txt:** Yes, but "blocking may reduce your site's visibility for user-directed web search"
- **Crawl-delay:** Not documented
- **JS Rendering:** Not documented
- **IP Ranges:** Not published
- **Notes:** Blocking prevents Claude from retrieving content in response to user queries.

### Claude-SearchBot
- **UA String:** `Claude-SearchBot`
- **Purpose:** Search result quality — "navigates the web to improve search result quality"
- **Respects robots.txt:** Yes, but "may reduce visibility and accuracy in user search results"
- **Crawl-delay:** Not documented
- **JS Rendering:** Not documented
- **IP Ranges:** Not published
- **Notes:** Focused on search indexing, not training.

---

## Perplexity (2 bots)

**Source:** https://docs.perplexity.ai/docs/resources/perplexity-crawlers

### PerplexityBot
- **UA String:** `Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; PerplexityBot/1.0; +https://perplexity.ai/perplexitybot)`
- **Purpose:** Search indexing — "designed to surface and link websites in search results on Perplexity. NOT used to crawl content for AI foundation models."
- **Respects robots.txt:** Yes
- **Crawl-delay:** Not documented
- **JS Rendering:** NOT documented
- **IP Ranges:** https://www.perplexity.com/perplexitybot.json
- **Notes:** Changes may take up to 24 hours to reflect.

### Perplexity-User
- **UA String:** `Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Perplexity-User/1.0; +https://perplexity.ai/perplexity-user)`
- **Purpose:** User-initiated fetches — "supports user actions within Perplexity"
- **Respects robots.txt:** **"Since a user requested the fetch, this fetcher generally ignores robots.txt rules."** (official)
- **Crawl-delay:** Not documented
- **JS Rendering:** Not documented
- **IP Ranges:** https://www.perplexity.com/perplexity-user.json
- **Notes:** Not used for web crawling or AI training.

### Third-Party Observations (Unverified)
- Cloudflare and DataDome report stealth/undeclared crawlers from Perplexity rotating IPs and evading robots.txt/WAF
- Independent reports are mixed on JS rendering capability — some say partial, most say none

---

## Googlebot

**Source:** https://developers.google.com/search/docs/crawling-indexing/javascript/fix-search-javascript

### Googlebot (Mobile)
- **UA String:** `Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/W.X.Y.Z Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)`
- **Purpose:** Web indexing for Google Search (mobile-first)
- **Respects robots.txt:** Yes (RFC 9309 compliant)
- **Crawl-delay:** Not officially supported (uses its own adaptive rate)
- **JS Rendering:** **YES — full headless Chrome via Web Rendering Service (WRS)**
- **IP Ranges:** Published + reverse DNS verification (`crawl-*.googlebot.com` or `geo-crawl-*.geo.googlebot.com`)
- **Notes:**
  - Two-phase: initial fetch (HTML) → queued render (headless Chrome)
  - WRS uses evergreen Chromium (latest stable)
  - Stateless: fresh browser session per render, no user interactions
  - ~5-second default timeout for initial page load (can extend for complex pages)
  - Does NOT execute user interactions (clicks, scrolling, typing)
  - May not fetch resources that don't contribute to essential page content
  - Client-side analytics may not accurately represent Googlebot activity

### Googlebot (Desktop)
- **UA String:** `Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)` or full Chrome-style UA with desktop OS

---

## Evidence Gaps — What We DON'T Know

These are the things NO vendor officially documents:

| Question | Status | Best Available Evidence |
|----------|--------|----------------------|
| Does GPTBot execute JavaScript? | **Unconfirmed** | Blog tests (JS-only pages invisible), inference from UA (no Chrome version) |
| Does ClaudeBot execute JavaScript? | **Unconfirmed** | Same observational evidence pattern |
| Does PerplexityBot execute JavaScript? | **Unconfirmed** | Mixed reports — most say no, some say partial |
| Does OAI-SearchBot render JS? | **Unconfirmed** | UA includes Chrome/131 — could indicate headless Chrome, or could be cosmetic |
| Exact Chrome version for Googlebot WRS? | Documented as "evergreen" | Google updates to latest stable; exact version not pinned |
| Do AI crawlers handle cookies/sessions? | **Unconfirmed** | Conservative assumption: stateless, no cookies |
| HTTP/2 vs HTTP/1.1 for AI crawlers? | **Unconfirmed** | No vendor documents this |
| TLS fingerprint (JA4) for AI crawlers? | **Unconfirmed** | Would require server-side capture of real bot traffic |

---

## Data Sources for Ongoing Maintenance

| Source | What it provides | URL |
|--------|-----------------|-----|
| OpenAI Bots Docs | Official UA strings, IP ranges, robots.txt behavior | https://developers.openai.com/api/docs/bots |
| Anthropic Privacy Docs | Official bot purposes, robots.txt + crawl-delay | https://privacy.claude.com |
| Perplexity Crawlers Docs | Official UA strings, IP ranges, purposes | https://docs.perplexity.ai/docs/resources/perplexity-crawlers |
| Google Search Central | Googlebot rendering behavior, WRS docs | https://developers.google.com/search/docs |
| Known Agents (darkvisitors.com) | Comprehensive bot directory, analytics, verification | https://darkvisitors.com |
| CrawlerCheck | Per-bot UA strings, blocking rules, safety ratings | https://crawlercheck.com |
| Cloudflare Radar | 500+ verified bots, crawl-to-referral ratios | https://radar.cloudflare.com |
| krowdev bot detection article | 7-layer detection hierarchy (TCP→TLS→HTTP/2→headers→behavior) | https://krowdev.com/article/bot-detection-2026/ |

---

## Implications for crawl-sim

### Profile schema must include:
- `source`: URL of official documentation
- `confidence`: "official" | "observed" | "inferred"
- `lastVerified`: ISO date of last verification
- `rendersJavaScript`: true | false | "unknown"
- `respectsRobotsTxt`: true | false | "partial" (with notes)
- `ipRangesUrl`: URL to published IP list (or null)
- `crawlDelaySupported`: true | false | "unknown"

### Simulation approach:
- For `rendersJavaScript: true` (Googlebot) → use Playwright/headless Chrome
- For `rendersJavaScript: false` or `"unknown"` (AI bots) → use raw curl (server HTML only)
- For `"unknown"` → flag in output: "This bot's rendering capability is unconfirmed. Showing server HTML view (conservative)."
