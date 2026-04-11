# Market Landscape — Crawler Simulation & AI Visibility Tools

Research compiled 2026-04-11.

## The Gap

No single tool exists that:
1. Simulates multiple bot perspectives (Googlebot + AI crawlers)
2. Compares what each bot sees side-by-side
3. Provides LLM-powered interpretation and fix recommendations
4. Is agent-native (designed for CLI agents like Claude Code)
5. Is open source

## Existing Tools by Category

### Free / Open Source (Simulation & Rendering)

| Tool | What It Does | URL | Limitation |
|------|-------------|-----|-----------|
| TametheBots Fetch & Render | Googlebot fetch/render simulator (Puppeteer + google/robotstxt parser). Shows initial HTML vs rendered DOM, screenshots, Lighthouse. | https://tamethebots.com/tools/fetch-render | Googlebot only. Web UI, no CLI/API. |
| Crawlee + Playwright | Full browser automation framework. Custom UA, HAR recording, screenshots, proxy rotation. CI/CD integrable. | https://crawlee.dev | No pre-built bot profiles. Raw framework. |
| Lightpanda | Lightweight headless browser. CDP compatible, V8 JS execution, robots.txt option, proxy, custom headers. AGPL-3.0. | https://github.com/nickoala/lightpanda | Early stage. Fidelity unverified. |
| Crawl4AI | Python LLM-friendly crawler with JS execution, CSS extraction. Trending. Apache-2.0. | https://github.com/unclecode/crawl4ai | No bot profiles. Content extraction focused. |
| CloakBrowser | Browser wrapper with fingerprint controls: timezone, WebRTC, proxy, persistent contexts. | GitHub (research) | Anti-detection focused, ethical considerations. |
| TLS-Chameleon | Python TLS/fingerprint toolkit. 45 browser profiles. Rate limiting, proxy pool. | GitHub (research) | HTTP client only, no rendering. |
| isbot | JS library to detect bot user-agents from maintained list. | https://github.com/nickoala/isbot | Detection only, not simulation. |
| GPT Crawler | Build knowledge bases for custom GPTs. npm-based. | GitHub | Corpus building, not audit. |

### Free Checkers (Access/Policy Only)

| Tool | What It Checks | URL |
|------|---------------|-----|
| PixelMojo AI Crawl Checker | 14 bot UAs, robots.txt, JSON-LD, llms.txt, content accessibility | https://www.pixelmojo.io/tools/ai-crawl-checker |
| BeeWeb LLM Visibility Checker | Visibility to ChatGPT, Claude, Perplexity, Gemini | https://tools.beewebsystems.com/llm-visibility-checker |
| Search Engine Land AI Checker | Brand visibility in AI-generated responses | https://searchengineland.com/tools/ai-visibility-checker |
| Cite.sh | AI citation directory + robots.txt/llms.txt optimization guide | https://www.cite.sh/blog/ai-crawler-guide/ |

### SaaS / Mid-Market ($25-250/mo) — Monitoring & Citations

| Platform | Focus | Price | URL |
|----------|-------|-------|-----|
| Otterly.AI | Track brand mentions in ChatGPT/Perplexity/Gemini responses | From $25/mo | https://otterly.ai |
| Peec AI | AI visibility monitoring + optimization suggestions | From €89/mo | https://peec.ai |
| ZipTie.dev | Google AIO + ChatGPT + Perplexity citation tracking. Content gap analysis. | From $59/mo | https://ziptie.dev |
| LLMrefs | LLM citation tracking across platforms | Contact | https://llmrefs.com |
| Clearscope | Content optimization for AI citation | From $129/mo | https://clearscope.io |

### Enterprise ($500+/mo) — Full Platforms

| Platform | Focus | URL |
|----------|-------|-----|
| Profound | Full AI visibility. Answer Engine Insights, content "Actions", llms.txt analytics, Profound Index. | https://tryprofound.com |
| BrightEdge | Enterprise SEO + AI search. Proprietary "generative parser", DataMind deep learning, AI Catalyst. | https://brightedge.com |
| Botify | Enterprise crawl management, render budget optimization, log file analysis. | https://botify.com |
| Lumar (DeepCrawl) | Cloud rendering service, partial render detection, CI/CD "Protect" product. | https://lumar.io |
| Screaming Frog | Desktop crawler — UA switching, JS rendering, structured data, custom headers. | https://screamingfrog.co.uk |
| Known Agents (Dark Visitors) | Bot analytics, verification, automatic robots.txt, LLM referral tracking. | https://darkvisitors.com |

### Bot Detection & Fingerprinting Research

| Source | Value for crawl-sim | URL |
|--------|-------------------|-----|
| krowdev 2026 article | 7-layer detection hierarchy with empirical captures. TCP→TLS(JA4)→HTTP/2→headers→Client Hints→IP reputation→behavioral. | https://krowdev.com/article/bot-detection-2026/ |
| Scrapfly HTTP/2 fingerprinting | Protocol-level bot detection guide. HTTP/2 SETTINGS frame fingerprinting. | https://scrapfly.io/blog/posts/http2-http3-fingerprinting-guide |
| DataDome GPTBot analysis | Documents GPTBot UA, reports potential robots.txt non-compliance. | Referenced in CrawlerCheck |
| Cloudflare Radar verified bots | 500+ crawlers as JSON dataset. | https://radar.cloudflare.com |

## Competitive Positioning

crawl-sim occupies a unique position:

```
                    Monitoring Only          Simulation Only
                    (what bots cited)        (how bots render)
                         │                        │
    Otterly ────────────►│                        │◄──── Screaming Frog
    ZipTie ─────────────►│                        │◄──── TametheBots
    Peec AI ────────────►│                        │◄──── Lumar
                         │                        │
                         │    ┌─────────────┐     │
                         │    │  crawl-sim  │     │
                         │    │             │     │
                         └────│ Agent-native│─────┘
                              │ Multi-bot   │
                              │ Interpreted │
                              │ Scored      │
                              │ Open source │
                              └─────────────┘
```

**What makes crawl-sim different:**
1. Multi-bot simulation in one run (not just Googlebot)
2. LLM interprets results (not just raw data dumps)
3. Quantified scoring (not just pass/fail)
4. Agent-native (skill, not SaaS dashboard)
5. Open source (not $500/mo enterprise)
6. Honest about evidence gaps (confidence levels on bot behavior)
