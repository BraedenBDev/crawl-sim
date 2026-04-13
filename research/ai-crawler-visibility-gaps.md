# AI Crawler Visibility Gaps — Why Sites Disappear from AI Search

Research compiled 2026-04-13. Documents the known causes of content being visible to Googlebot but invisible to AI crawlers (GPTBot, ClaudeBot, PerplexityBot). Each category includes the mechanism, why it's hard to catch, and which crawl-sim check surfaces it.

---

## 1. Infrastructure Silently Filtering by Bot Tier

### Cloudflare Default Bot Blocking (since July 2025)

Cloudflare classifies crawlers into three tiers: verified search engines (Googlebot, Bingbot), AI training crawlers (GPTBot, ClaudeBot), and unverified bots. Since July 2025, the "AI Scrapers and Crawlers" toggle in Cloudflare dashboard is **on by default** for all plans, including free. Cloudflare reports this affects approximately 20% of the web.

A site behind Cloudflare serves full HTML to Googlebot (tier 1, whitelisted) but returns a challenge page or 403 to GPTBot and ClaudeBot (tier 2, blocked by default). The site owner sees normal behavior in their browser. Every SEO tool reports green because they check the Google view.

**Why it's hard to catch:** No error appears in server logs (Cloudflare intercepts before the request reaches origin). The site owner never opted into blocking — it's the default. Browser-based testing never reveals it because browsers aren't classified as bots.

**crawl-sim detection:** `fetch-as-bot.sh` fetches with each bot's verified UA string. A 403 or challenge page for AI bots while Googlebot returns 200 is the signal. Cross-bot parity scoring flags the content delta.

**Sources:**
- Cloudflare Docs: https://developers.cloudflare.com/bots/concepts/bot/
- Cloudflare Radar: https://radar.cloudflare.com/bots
- Cloudflare Blog on AI bot management (2025)

### CDN Edge Logic and A/B Testing Layers

Edge-computed content (Cloudflare Workers, Vercel Edge Middleware, AWS CloudFront Functions) can serve different responses based on UA classification. A/B testing platforms that bucket by UA string may route bots to control variants with less content. Personalization layers that depend on cookies or JS-set flags serve the unpersonalized (often minimal) version to stateless crawlers.

**Why it's hard to catch:** The origin server returns correct content. The transformation happens at the edge, invisible to application-level debugging. Different CDN providers have different bot classification logic.

**crawl-sim detection:** Comparing response bodies across bot profiles. If Googlebot gets 2,000 words and GPTBot gets 200 from the same URL, edge logic is the likely cause.

---

## 2. Framework Defaults That Create the Gap by Design

### Suspense Boundaries and Streaming SSR Fallbacks

React's `<Suspense>` with streaming SSR sends the fallback content immediately and streams the resolved content as it becomes available. Googlebot's Web Rendering Service (WRS) executes JavaScript and waits for hydration. AI crawlers that read only the initial server HTML see the fallback — loading skeletons, spinners, or empty containers — not the actual content.

This is the **recommended pattern** in React 18+, Next.js App Router, and Remix. Developers using the framework correctly produce content that is invisible to non-rendering crawlers.

**Why it's hard to catch:** The page renders correctly in every browser. Googlebot indexes the full content. Lighthouse shows no issues. The fallback HTML is valid markup — it just has no meaningful content. View Source shows the shell, but developers rarely check that against what bots actually receive.

**crawl-sim detection:** Word count and heading comparison across bots. `diff-render.sh` compares server HTML (what AI bots see) against JS-rendered DOM (what Googlebot sees). A 10x word-count gap is the flagship finding.

### Framework-Specific Client Boundaries

| Framework | Pattern | What AI Bots See |
|-----------|---------|-----------------|
| Next.js | `dynamic(() => import('./Component'), { ssr: false })` | Nothing (component not in server HTML) |
| Next.js | `'use client'` + data fetching in useEffect | Empty container |
| Nuxt 3 | `<ClientOnly>` wrapper | Fallback slot content or nothing |
| SvelteKit | `browser` check guarding content | Server-rendered fallback only |
| Remix/React Router | `clientLoader` without `HydrateFallback` | Empty until JS executes |
| Astro | `client:only` directive | Placeholder element |

These are all **documented, recommended patterns** for code-splitting and performance optimization. The framework docs encourage their use. None of the framework docs warn about AI crawler implications.

**Why it's hard to catch:** The developer followed the documentation. The page works perfectly in production. Performance scores are good specifically because these patterns reduce initial bundle size. The side effect — AI crawler invisibility — is undocumented.

**crawl-sim detection:** Cross-bot content parity. Server HTML word count vs JS-rendered word count surfaces the delta regardless of which framework pattern caused it.

### Intersection Observer and Lazy Loading

Content below the fold loads via `IntersectionObserver` — images, embedded components, infinite scroll sections. Googlebot's WRS scrolls the virtual viewport and triggers intersection callbacks. AI crawlers fetch HTML and get empty placeholders with `data-src` attributes but no actual content.

Native lazy loading (`loading="lazy"` on images) is specifically handled by Googlebot's renderer but invisible to HTML-only crawlers — the `src` may be a placeholder or blank.

**Why it's hard to catch:** Lazy loading is a Core Web Vitals best practice. Google explicitly recommends it. The interaction between lazy loading and non-rendering crawlers is not documented by any framework or by Google's own guidance.

**crawl-sim detection:** Image count comparison (images with `src` vs images with only `data-src`). Content section comparison showing missing sections in server HTML that appear in rendered DOM.

---

## 3. Content Architectures That Assume JavaScript

### Shadow DOM and Web Components

Content inside Shadow DOM is encapsulated by design. Googlebot traverses shadow roots during rendering. AI crawlers reading server HTML see the custom element tags (`<my-component>`) but not their shadow content. If the component doesn't use Declarative Shadow DOM (DSD), the server HTML contains zero content for that component.

**Why it's hard to catch:** Web Components are a web standard. Shadow DOM encapsulation is the intended behavior. DSD adoption is still low (requires explicit server-side support).

**crawl-sim detection:** Word count delta between server HTML and rendered DOM. Custom elements present in HTML with no text content inside them.

### iframe-Embedded Content

Content loaded via iframes (embedded videos, third-party widgets, but also primary content in some architectures like micro-frontends) is indexed by Googlebot (which follows iframe src URLs separately) but skipped by AI crawlers reading the parent page's HTML.

**Why it's hard to catch:** The iframe src is right there in the HTML, but AI crawlers don't follow it as a content source for the parent page.

**crawl-sim detection:** Presence of iframes in server HTML flagged in content audit. Content within iframes not counted toward parent page word count for AI bot profiles.

### Client-Side Data Fetching (SPA Patterns)

Single-page applications that fetch content via API calls after `DOMContentLoaded` — the traditional SPA model — serve an empty shell to non-rendering crawlers. Googlebot's WRS executes the JavaScript, waits for API responses, and indexes the rendered content. AI crawlers see the shell.

This is becoming less common as frameworks move to SSR/SSG, but legacy SPAs, dashboard-style apps with public pages, and hybrid architectures still rely on it.

**Why it's hard to catch:** It's the fundamental architecture of the application. The "fix" is a migration to SSR, which is a major architectural change, not a config tweak.

**crawl-sim detection:** Near-zero word count for AI bot profiles with full content visible in Googlebot rendered view.

---

## 4. robots.txt Complexity and Enforceability Gaps

### Blocking Resources but Allowing the Bot

A robots.txt that allows GPTBot access to pages but blocks the `/static/` or `/assets/` directory prevents the bot from loading CSS and JavaScript resources needed for any rendering attempt. Googlebot may still render from cached resources or degrade gracefully. AI crawlers that attempt any resource loading get broken pages.

**Why it's hard to catch:** The robots.txt looks correct — the bot is allowed. Testing the page URL works. The resource blocking is a separate rule that isn't surfaced by page-level access checks.

**crawl-sim detection:** `check-robots.sh` tests both the page URL and common resource paths against each bot's UA token.

### Advisory-Only Enforceability

ChatGPT-User and Perplexity-User officially ignore or may ignore robots.txt for user-initiated fetches. A site owner who blocks these bots in robots.txt believes they've opted out, but user-initiated queries still fetch and display their content. The "block" is advisory, not enforced.

**Why it's hard to catch:** The robots.txt rule exists and appears to work. No tool distinguishes between enforced and advisory-only compliance. The vendor documentation buries this distinction.

**crawl-sim detection:** Each bot profile includes an `enforceability` field (enforced, advisory_only, stealth_risk). The score card surfaces this classification per bot. A robots.txt block on an advisory_only bot is flagged as ineffective.

### Stealth Crawling and Undeclared User Agents

PerplexityBot claims robots.txt compliance, but Cloudflare and independent researchers have documented bypass behavior via undeclared crawlers that don't identify as PerplexityBot. The robots.txt block works against the declared bot but not against the undeclared variant.

**Why it's hard to catch:** The declared bot respects the block. The undeclared bot uses a generic or browser-like UA string. Server logs show the access but it's indistinguishable from normal traffic without IP correlation.

**crawl-sim detection:** PerplexityBot profile carries `stealth_risk` enforceability classification. Narrative output explains the limitation — blocking in robots.txt is necessary but may not be sufficient.

**Sources:**
- Cloudflare blog on Perplexity crawling behavior
- DataDome analysis of undeclared AI crawlers
- See `bot-profiles-verified.md` for per-bot enforceability details

---

## Summary: The Visibility Gap Is Systemic

The gap between what Googlebot sees and what AI crawlers see is not primarily caused by developer mistakes. It's a structural consequence of:

1. **Google invested in rendering; AI vendors didn't.** Googlebot runs a full headless Chrome. AI crawlers read server HTML. Every JavaScript-dependent content pattern works for Google and fails for AI bots.

2. **Infrastructure treats bots differently by default.** Cloudflare, CDNs, and WAFs whitelist Googlebot and block or challenge AI crawlers without the site owner's knowledge or action.

3. **Framework best practices create the gap.** Code splitting, lazy loading, Suspense boundaries, and client components are recommended patterns that happen to produce content invisible to non-rendering crawlers.

4. **robots.txt enforcement is not uniform.** Some bots enforce, some advise, some bypass. A single robots.txt cannot express the nuance needed, and no standard tool audits enforceability per bot.

The common thread: every existing tool audits the Google view. The AI crawler view is a different thing entirely, and until you fetch as each bot and compare, the gap is invisible.
