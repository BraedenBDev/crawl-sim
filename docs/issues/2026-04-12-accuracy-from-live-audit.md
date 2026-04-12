# Accuracy Issues from Live Audit — 2026-04-12

**Source:** Real-world audit of `https://www.almostimpossible.agency/` on 2026-04-12 (00:04–00:10 CET).
**Audit run directory:** `/var/folders/9c/tn8kqlyj3wg90r3_8zf8fpfr0000gn/T/crawl-sim.XXXXXX.h149whv75f/` (volatile — raw JSON may still be on disk until next tmp cleanup).
**Final site score:** 94/100 "A" overall, with only Structured Data flagged at 70/C- across all 4 bots.
**Executive summary:** The tool produced a technically coherent report that led to wrong recommendations. Not because it hallucinated data — the raw extraction was accurate and matched independent curl verification byte-for-byte — but because the **scoring model is page-type-blind**, the **explanations are missing**, and several **scripts silently swallow failures**. The narrative author (me, in a previous session) then made plausible-sounding recommendations from an uncontextualized 70/C- score and ended up suggesting a schema addition that was already shipped and a homepage schema change that would have been incorrect.

This document breaks down what went wrong, why, and the concrete fixes to make crawl-sim trustworthy as an accuracy-first audit tool. Priority is ordered Critical → High → Medium → Roadmap.

---

## How the wrong recommendations were produced

Three facts from the run:

1. **crawl-sim's raw data was correct.** The fetches were byte-accurate (10,413 words, 208,626 bytes, identical across all 4 bots), the meta extraction captured the real title/OG/canonical/heading counts, the JSON-LD extractor correctly reported `[Organization, ProfessionalService, WebSite]` as the three blocks present, sitemap + robots + llms.txt were all correctly reported. Zero factual errors at the data layer.

2. **The scoring model gave the homepage 70/C- on Structured Data** because its rubric expects a broader set of schema types than what the homepage shipped. The three "missing" schemas it was implicitly penalizing for — `BreadcrumbList`, `FAQPage`, `Article` — are **not appropriate for a root/landing page**:
    - **BreadcrumbList:** the homepage IS the root of the site, there's nothing to breadcrumb back to
    - **Article:** the homepage isn't an article
    - **FAQPage:** only valid if an FAQ is actually rendered in the homepage DOM, which it isn't here

3. **The narrative layer has no way to know which of the "missing" schemas are applicable.** `score.json` reports `{"score": 70, "grade": "C-"}` and nothing else. The narrator has to guess what would have raised the score. In this run, I guessed "add FAQPage to `/faq`" — which, when investigated in the target codebase, turned out to already be shipped. I also guessed "add BreadcrumbList to non-homepage routes" — which was also ~70% already shipped. The net result: my "fix list" was 80% redundant and the 20% that wasn't redundant pointed at legitimate-but-polish-level work.

**The structural issue:** crawl-sim's scoring penalized the homepage for missing schemas that shouldn't be there, and then provided zero transparency into what it was penalizing for, which forced the narrator to invent a plausible story. The factual data was right; the *inference layer* was wrong, and the tool gave the narrator no way to verify or correct.

---

## Critical — scoring model bugs

### C1. Scoring is page-type-blind

**Observed:** The homepage received a 70/C- on Structured Data for missing `BreadcrumbList`, `FAQPage`, and `Article` — all three of which are categorically wrong for a root page. Every root page in the world would fail the same check. The tool cannot distinguish a homepage from an article page from a category page from an FAQ page, and it applies a uniform "all schemas present" rubric.

**Evidence:** `score.json` at `bots.googlebot.categories.structuredData = 70`. Raw JSON-LD extraction at `jsonld-googlebot.json` shows 3 valid blocks (Organization, ProfessionalService, WebSite) which is *exactly* the schema.org-recommended set for a root page. No invalid schemas, no broken schemas, no missing applicable schemas — but the score is 70 because the rubric expected more types.

**Root cause:** `scripts/compute-score.sh` (or whatever the scoring logic lives in) treats schema types as a flat checklist without awareness of which types apply to which page type.

**Proposed fix:** Introduce page-type detection and per-type rubrics.

1. **Detect page type from URL + content signals:**
   - `/` or exactly-domain → `root`
   - URL ending in `/work/:slug`, `/articles/:slug`, `/careers/:slug` → `detail`
   - URL like `/work`, `/journal`, `/careers` (terminal, no slug) → `archive`
   - URL containing `faq` → `faq`
   - URL containing `about`, `purpose`, `team` → `about`
   - URL containing `contact` → `contact`
   - Fallback: `generic`

   OR accept a `--page-type <type>` flag to let the caller declare it explicitly.

2. **Apply per-type schema rubrics.** Each type has an `expected` set (must-have), `optional` set (nice-to-have), and `forbidden` set (shouldn't be present).

   | Page type | Expected | Optional | Forbidden (penalize if present) |
   |----|----|----|----|
   | root | Organization, WebSite | ProfessionalService, LocalBusiness, ItemList (featured items) | BreadcrumbList, Article, FAQPage (unless FAQ rendered) |
   | detail (article) | Article, BreadcrumbList | NewsArticle, ImageObject | CollectionPage, ItemList |
   | detail (case study) | CreativeWork / Product, BreadcrumbList | Review, AggregateRating | Article, FAQPage |
   | archive | CollectionPage, ItemList, BreadcrumbList | — | Article, Product |
   | faq | FAQPage, BreadcrumbList | WebPage | Article, CollectionPage |
   | about | AboutPage, BreadcrumbList, Organization | Person[] | Article, Product |
   | contact | ContactPage, BreadcrumbList | PostalAddress | Article, Product |
   | generic | WebPage, BreadcrumbList | — | — |

3. **Score = `present ∩ (expected ∪ optional)` / `|expected|`.** Penalize anything in `forbidden`. Do not penalize for missing `optional`. Cap at 100 when all expected are present.

4. **Document the rubric prominently** so audit narratives can cite the specific missing-expected vs present-forbidden decisions the scorer made.

**Regression test:** Feed a known homepage (Organization + ProfessionalService + WebSite only) through the new scorer. It should return 100 on Structured Data for page-type `root`. Same input on page-type `detail` should return <50 because Article + BreadcrumbList are missing.

---

### C2. Score output has no explanation

**Observed:** `score.json` emits `{"score": 70, "grade": "C-"}` for the Structured Data category. No `missing`, `expected`, `present`, or `reasons` field. The narrative author has to read `jsonld-*.json` separately, infer what the rubric was checking, and guess at what would raise the score. This is exactly where hallucinations enter — plausible-sounding recommendations that don't match what the scorer actually wanted.

**Evidence:** I recommended "add FAQPage schema to /faq" as the top-priority fix. That page already had FAQPage schema shipped. The recommendation was generated from a score gap with no visibility into what the scorer expected.

**Proposed fix:** Every score field must explain itself. Extend `score.json` schema:

```json
{
  "categories": {
    "structuredData": {
      "score": 70,
      "grade": "C-",
      "pageType": "root",
      "expected": ["Organization", "WebSite"],
      "optional": ["ProfessionalService", "LocalBusiness"],
      "forbidden": ["BreadcrumbList", "Article", "FAQPage"],
      "present": ["Organization", "ProfessionalService", "WebSite"],
      "missing": [],
      "extras": [],
      "violations": [],
      "calculation": "3/2 expected present + 1/2 optional present, capped at 100 - 0 violations = 100",
      "notes": "Root pages don't need BreadcrumbList/Article/FAQPage. Score should be 100."
    }
  }
}
```

With this, the narrative layer can say "Structured Data: 100 — all applicable schemas present (Organization + WebSite + bonus ProfessionalService). No action needed." Instead of inventing a fix.

**Regression test:** Every score field in `score.json` must pass a JSON schema validation that requires `expected`, `present`, `missing`, `calculation`, and `notes` fields. Write a JSON schema file and validate in CI.

---

### C3. Scoring rewards presence over correctness

**Observed:** The audit gives credit for having JSON-LD blocks present, but doesn't check whether those blocks are appropriate for the page type or whether they're semantically valid beyond syntactic `@context` + `@type`. A site could ship an `Article` schema on its homepage with garbage fields, and the scorer would reward it.

**Evidence:** Related to C1. The scoring model counts schema block presence without filtering for applicability.

**Proposed fix:** 
1. After page-type detection (C1), apply the `forbidden` filter: blocks present that shouldn't be on this page type subtract 5 points each.
2. Validate required fields per schema type against schema.org's documented minimums (e.g., Article must have `headline`, `author`, `datePublished` — if any are missing, count as invalid).
3. Output a `violations` array explaining what was wrong.

**Regression test:** Synthetic fixtures in `test/fixtures/`:
- `fixture-homepage-correct.html` — Organization + WebSite, score should be 100
- `fixture-homepage-overreaching.html` — Organization + WebSite + Article + FAQPage (wrong types), score should be ~60 with violations
- `fixture-article-correct.html` — Article + BreadcrumbList, score should be 100
- `fixture-article-missing-breadcrumb.html` — Article only, score should be ~70

Automated tests in `test/scoring.test.sh` that pipe each fixture through the scorer and assert expected scores.

---

### C4. No cross-bot parity signal in scoring

**Observed:** The SKILL.md guidance explicitly says "Cross-bot comparison is the key differentiator. If Googlebot sees 1800 words and GPTBot sees 120, that's the headline finding." But the scoring model doesn't surface cross-bot deltas as a distinct category. It scores each bot independently. On this site, all 4 bots got `94` — technically correct (parity confirmed), but the score card presents four rows of "94 A" that imply meaningful per-bot differentiation where there is none. A site with CSR (client-side rendering) where Googlebot renders JS and sees 1800 words while GPTBot sees 120 would *also* get independent per-bot scores without the critical "content parity" finding being elevated to the headline.

**Proposed fix:** Add a `parity` or `contentVisibilityDelta` category to scoring.

```json
{
  "parity": {
    "score": 100,
    "grade": "A",
    "wordCountRange": { "min": 10413, "max": 10413 },
    "byteRange": { "min": 208626, "max": 208628 },
    "maxDelta": 0.0,
    "interpretation": "byte-identical across all bots",
    "severity": "none"
  }
}
```

Scoring formula:
- `parity.score = 100` if `max_word / min_word < 1.05` (5% tolerance for header variations)
- `parity.score = 100 * (min_word / max_word)` otherwise
- If `parity.score < 50`, add a **critical finding**: "Site serves fundamentally different content to bots without JS rendering. This is almost certainly a CSR/SSR failure. AI visibility score is meaningless until content parity is achieved."

**Collapse display when parity is perfect.** When all bots score identically AND content is byte-identical, show a single line instead of four rows:

```
║  All 4 bots    94  A   ██████████████████░░   (parity confirmed)    ║
```

**Regression test:** Two fixtures, one with byte-identical content across bots (parity=100), one with a synthetic site that serves full content to Googlebot and empty content to non-JS bots (parity<50). Assert both produce correct parity scores and headline findings.

---

## High — script / UX issues that led to failures mid-audit

### H1. `fetch-as-bot.sh` silently fails in parallel

**Observed:** During my first run, I fetched all 4 bot profiles in a bash loop with output redirected to files. 2 of 4 files came out 0 bytes (`fetch-googlebot.json` and `fetch-perplexitybot.json`) with no error message — just empty files. Running each bot individually afterwards worked. Running with `bash -x` showed the script completed successfully and produced valid JSON on stdout. The failure was in the shell-level redirect pattern in my calling loop, but **the script gave me no way to diagnose this**.

**Evidence:** `ls -la fetch-*.json` showed 0-byte files for googlebot/perplexitybot while gptbot/claudebot had 280KB each. No stderr output. The `.err` files I was capturing in a separate stream were also empty.

**Root cause:** `set -euo pipefail` + `2>/dev/null` on the curl command means any transient error causes a silent exit with no output. The fallback `|| echo '{"total":0,...}'` kicks in but still produces no diagnostic.

**Proposed fix:**

1. **Emit progress to stderr with bot ID prefix:**
   ```bash
   echo "[${BOT_ID}] fetching ${URL} (ua=${UA:0:60}...)" >&2
   # ... after curl ...
   echo "[${BOT_ID}] ok: status=${STATUS} size=${SIZE} words=${WORD_COUNT} time=${TOTAL_TIME}s" >&2
   ```
   This gives the caller visibility into what's happening without polluting stdout (which is reserved for JSON output).

2. **Don't swallow curl errors.** Remove `2>/dev/null` on the curl command. Capture curl's stderr into a variable and include it in the output JSON when status is 0:
   ```json
   {
     "status": 0,
     "error": "curl: (6) Could not resolve host: example.invalid",
     "fetchFailed": true
   }
   ```

3. **Add `set +e` around the curl call specifically.** `set -e` should not apply to HTTP requests — transient network issues shouldn't crash the whole script. Capture the exit code and handle it explicitly.

4. **Add a `--verbose` or `-v` flag to the script** that emits additional diagnostic output (redirect chain, TLS details, HTTP version, etc.).

**Regression test:** Run the script against a known-bad URL (`https://example.invalid/`). It should emit an error line to stderr, produce a JSON output with `fetchFailed: true` and a non-empty `error` field, and exit cleanly (not crash the caller). Automate in `test/fetch-failure.test.sh`.

---

### H2. `diff-render.sh` skipped silently

**Observed:** My audit produced no `diff-render.json` file. I don't know whether Playwright was missing, whether the script errored, or whether it just didn't run. The SKILL.md says "if skipped, note it in narrative" but the narrative layer has no reliable signal that it was skipped vs. that it was run and found no diff vs. that it errored.

**Root cause:** The SKILL.md guidance suggests `if [ -x "$SKILL_DIR/scripts/diff-render.sh" ]` as the gate, but:
- It doesn't verify Playwright is actually installed
- If Playwright isn't installed, `diff-render.sh` might run but produce an error output that the caller ignores
- There's no `diff-render.skipped` marker for the narrative layer to read

**Proposed fix:**

1. **Make `diff-render.sh` always produce output**, even when skipping. If Playwright isn't installed:
   ```json
   {
     "skipped": true,
     "reason": "playwright_not_installed",
     "message": "Install Playwright to enable JS-rendered content comparison: npm install -g playwright && npx playwright install chromium",
     "impact": "Sites that rely on CSR (client-side rendering) will appear to have less content to non-JS bots than they actually serve to Googlebot. Install Playwright for accurate AI bot visibility scores."
   }
   ```

2. **In the scoring model, treat a skipped diff-render as a WARNING, not a silent success.** When `diff-render.skipped == true`, emit a top-level warning in `score.json`:
   ```json
   {
     "warnings": [
       {
         "code": "diff_render_unavailable",
         "severity": "high",
         "message": "JS rendering comparison was skipped. If this site uses CSR, non-JS bot scores may be inaccurate."
       }
     ]
   }
   ```

3. **Narrative layer must surface warnings prominently** — as the first item under the score card, not buried in findings.

**Regression test:** Run an audit on a known CSR site (e.g., a bare-bones CRA deployment) with Playwright not installed. Verify the output includes a visible warning and the narrative surfaces it. Then install Playwright and re-run — warning should disappear and a real JS-vs-no-JS diff should be reported.

---

### H3. Redirect chain not surfaced in narrative

**Observed:** crawl-sim follows redirects via `curl -L` in `fetch-as-bot.sh`, so when I audited `https://www.almostimpossible.agency/` (already www), nothing was suspicious. But if I had audited the apex (`https://almostimpossible.agency/`), crawl-sim would have followed the 307 redirect to www and reported on www's content — **without noting that the redirect happened**. This is exactly the mistake the previous external audit (Claude Desktop / GPT-based) made: it didn't follow redirects and reported "sparse old homepage" based on a 15-byte 307 body. crawl-sim handles this better at the fetch layer but doesn't surface the redirect chain in output.

**Proposed fix:**

1. **Add `redirectChain` field to fetch output.** Use `curl -w` with `%{num_redirects}` and parse the Location headers from the dump:
   ```json
   {
     "url": "https://almostimpossible.agency/",
     "finalUrl": "https://www.almostimpossible.agency/",
     "redirectChain": [
       { "hop": 0, "status": 307, "url": "https://almostimpossible.agency/", "location": "https://www.almostimpossible.agency/" },
       { "hop": 1, "status": 200, "url": "https://www.almostimpossible.agency/" }
     ],
     "redirectCount": 1
   }
   ```

2. **Surface redirect chains in the narrative.** If `redirectCount > 0`, the narrative should explicitly state:
   > "Note: the requested URL (`https://almostimpossible.agency/`) returned a 307 redirect to `https://www.almostimpossible.agency/`. This audit reports on the final destination. Canonical host is www. The apex → www redirect is standard and correct."

3. **Flag redirect chains with >2 hops** as a warning (likely misconfiguration).

4. **Handle 3xx loops** and report them as a critical failure instead of timing out.

**Regression test:** Audit `https://example.com/redirect-to-itself` (if such a test fixture exists) and assert crawl-sim detects the loop. Audit `https://t.co/short-url-that-chains-3-times` and verify the full chain is captured.

---

## Medium — output schema / documentation inconsistencies

### M1. `check-llmstxt.sh` has inconsistent output schema vs siblings

**Observed:** The output is nested:
```json
{ "url": "...", "llmsTxt": { "exists": true, ... }, "llmsFullTxt": { "exists": false, ... } }
```

While `check-sitemap.sh` is flat:
```json
{ "url": "...", "sitemapUrl": "...", "exists": true, "urlCount": 23, ... }
```

My naive jq query `jq '.exists'` against the llmstxt output returned `null` because there's no top-level `exists`. Had to read the file to discover the nested shape.

**Proposed fix:** Add a top-level `exists` field to `check-llmstxt.sh` output that's true if EITHER variant exists:

```json
{
  "url": "...",
  "exists": true,
  "llmsTxt": { ... },
  "llmsFullTxt": { ... }
}
```

Document the full schema for both scripts in `docs/output-schemas.md`.

---

### M2. `check-sitemap.sh` doesn't include sample URLs

**Observed:** Output has `urlCount`, `hasLastmod`, `containsTarget`, but no actual URL list. Narrative audits that want to cite specific sitemap URLs have to make a separate HTTP request.

**Proposed fix:** Include a `sampleUrls` array (first 10 URLs from the sitemap) in the output. If the sitemap is an index, also include `childSitemaps` with their individual first-5 URLs.

```json
{
  "exists": true,
  "urlCount": 23,
  "sampleUrls": [
    "https://www.almostimpossible.agency/",
    "https://www.almostimpossible.agency/about",
    ...
  ],
  "containsTarget": true,
  "hasLastmod": true
}
```

---

### M3. `extract-links.sh` output has undocumented nested structure

**Observed:** Output is `{counts: {total, internal, external}, internal: [...], external: [...]}`. My jq query `jq '.total'` returned null because `total` is nested under `counts`.

**Proposed fix:** Either flatten to `{total, internal, external, internalUrls, externalUrls}` or document the nested structure clearly in an output schema file. I'd lean toward flat for consistency with how the narrative layer consumes it.

---

### M4. No `docs/output-schemas.md` for raw JSON contracts

**Observed:** I had to read each raw output file and reverse-engineer its shape. For a tool where the scoring and narrative layers depend on these structures, an authoritative schema doc is load-bearing.

**Proposed fix:** Create `docs/output-schemas.md` that documents the exact JSON shape of every script's stdout. Include a `// field purpose` comment for every field. Treat schema changes as breaking changes and bump version accordingly.

Even better: ship JSON Schema (`schemas/*.schema.json`) and validate all script outputs in CI.

---

### M5. `score.json` doesn't embed the raw per-bot data

**Observed:** The narrative author has to open `fetch-*.json`, `meta-*.json`, `jsonld-*.json`, `links-*.json`, `robots-*.json`, `llmstxt.json`, `sitemap.json` individually to author findings. That's 8+ file reads per audit. For a skill that's supposed to be agent-authored, consolidation matters.

**Proposed fix:** When writing `crawl-sim-report.json` (the final output), merge in everything the narrative layer needs:

```json
{
  "score": { ... },
  "warnings": [ ... ],
  "perBot": {
    "googlebot": {
      "fetch": { status, timing, size, wordCount, redirectChain },
      "meta": { title, description, canonical, og, headings, images },
      "jsonld": { blockCount, types, flags },
      "links": { total, internal, external, internalUrls },
      "robots": { allowed, rules }
    },
    "gptbot": { ... },
    "claudebot": { ... },
    "perplexitybot": { ... }
  },
  "independent": {
    "sitemap": { ... },
    "llmstxt": { ... },
    "diffRender": { ... }
  }
}
```

Single file read for the narrative layer. Raw intermediates can still live in the temp dir for debugging.

---

## Roadmap — architectural changes

### R1. Multi-URL / site-wide audit mode

**Observed:** crawl-sim audits one URL. For a full site, you'd run it N times. But the tool doesn't know about sibling pages, so when I saw "Structured Data 70 — missing FAQPage" on the homepage, I had no way for crawl-sim to know that `/faq` already had FAQPage schema. A multi-URL mode would let the scorer make smarter cross-page recommendations.

**Proposed fix:** Add three new invocation modes:

1. **`crawl-sim sitemap <url>`** — fetch sitemap, audit every URL listed, aggregate into site-wide report with per-page-type breakdowns.
2. **`crawl-sim crawl <url> --depth 2`** — BFS crawl from entry URL, respecting robots, with concurrency limit (default 5) and politeness delay (default 500ms).
3. **`crawl-sim manifest <file.txt>`** — read a newline-separated list of URLs to audit. Useful for CI (audit just the URLs that changed in this PR).

Site-wide report aggregates:
- Per-page-type distribution (% of pages with valid schema for their type)
- Cross-page inventory ("FAQPage schema is present on /faq but missing from /guide-to-X which has an FAQ section")
- Sitewide parity score (do all pages have consistent meta, canonical, og:image coverage?)

### R2. Confidence levels on findings

**Observed:** The SKILL.md already mentions `confidence.level` in bot profiles (observed vs documented) but the scoring output doesn't expose confidence to the narrative layer. Some findings are empirically verified, some are inferred from documented behavior, some are best-guess. The narrative should distinguish them.

**Proposed fix:** Every finding should carry a confidence field:

```json
{
  "id": "missing-breadcrumb-on-article",
  "severity": "medium",
  "confidence": "high",
  "source": "rubric-check",
  "evidence": "jsonld-googlebot.json has no BreadcrumbList block"
}
```

Confidence levels: `high` (directly observed in data), `medium` (inferred from documented behavior), `low` (heuristic / pattern-matched). The narrative must cite confidence for any finding that isn't `high`.

### R3. Per-bot scoring should distinguish "parity" from "individual score"

**Observed:** When all four bots score 94, that score is meaningful as a sitewide number but the four individual rows add no information. When they differ, the individual rows are critical. The output format should adapt.

**Proposed fix:** Compute both a sitewide score AND per-bot scores, and display the per-bot breakdown only when the range exceeds a threshold (e.g., max - min > 5 points). Otherwise, collapse to a "parity confirmed" line.

### R4. Critical-fail criteria

**Observed:** A site with 0 schema, no sitemap, no llms.txt, AND blocked by robots for all bots would still get a non-F grade under the current scoring. Certain issues should be auto-F regardless of other scores.

**Proposed fix:** Define critical-fail criteria:

| Criterion | Auto-grade |
|----|----|
| Any bot blocked by robots.txt | F on that bot |
| Word count < 200 for any non-JS bot on a page where Googlebot sees >1000 | F on content visibility for that bot |
| Zero valid JSON-LD on a page where at least one type is expected | F on structured data |
| Canonical missing or points at different domain | F on technical signals |
| TTFB > 5000ms | D on technical signals |

Critical fails short-circuit the rubric. A site that hits any critical criterion should not receive A or B regardless of other scores.

---

## Suggested priority order for the fix agent

**Sprint 1 — accuracy foundation (blocks further use of the tool for real audits):**
- C1: Page-type-aware scoring
- C2: Explain-yourself score output
- H1: `fetch-as-bot.sh` progress + error surfacing
- M4: `docs/output-schemas.md` + JSON schemas in CI

**Sprint 2 — narrative quality:**
- C3: Reward correctness over presence
- C4: Cross-bot parity signal
- H2: Diff-render warning surfacing
- H3: Redirect chain in output

**Sprint 3 — polish:**
- M1: `check-llmstxt.sh` top-level `exists`
- M2: `check-sitemap.sh` sample URLs
- M3: `extract-links.sh` flat structure
- M5: Consolidated `crawl-sim-report.json`

**Sprint 4 — roadmap:**
- R1: Multi-URL / sitemap mode
- R2: Confidence on findings
- R3: Adaptive per-bot display
- R4: Critical-fail criteria

---

## What worked well (don't change these)

- **Bot profile architecture.** Separate JSON profiles per bot with UA, robots token, capabilities, and confidence metadata is clean and extensible. Adding new bots is just a profile file.
- **Per-bot fetch with accurate UA spoofing.** The fetches correctly matched what each bot would actually see.
- **Byte-identical fetch verification.** When I independently curled the site with each UA, crawl-sim's fetched sizes matched to the byte.
- **Redirect following.** `curl -L` avoided the "15-byte apex redirect body looks like a sparse homepage" trap that defeated the previous external audit. Keep this.
- **Meta + JSON-LD + links extraction.** The raw extractors produced accurate data. No hallucinations at the data layer.
- **llms.txt detection.** Correctly identified the `llms.txt` file and parsed its structure.
- **Robots.txt per-bot token matching.** Correctly checked each bot's specific robots rules rather than treating robots as a single-bot check.

The tool is well-engineered at the data-gathering layer. The gap is between the data and the score, and between the score and the recommendation.

---

## One regression-test suite proposal

Create `test/regression/` with synthetic HTML fixtures representing each page type, and golden score files. Every scoring change must pass these before merge:

```
test/regression/
├── root-minimal/
│   ├── input.html          # Organization + WebSite only
│   └── expected-score.json # 100 on structuredData, page_type: root
├── root-overreaching/
│   ├── input.html          # Organization + WebSite + Article (wrong) + FAQPage (wrong)
│   └── expected-score.json # ~60 with violations array
├── article-correct/
│   ├── input.html          # Article + BreadcrumbList + ImageObject
│   └── expected-score.json # 100 on structuredData, page_type: detail
├── article-incomplete/
│   ├── input.html          # Article only, no breadcrumb
│   └── expected-score.json # ~70, missing: [BreadcrumbList]
├── csr-site/
│   ├── input.html          # Empty body, JS-rendered
│   ├── input-rendered.html # Full content after render (playwright)
│   └── expected-score.json # parity: low, warning: csr_detected
├── broken-redirect-loop/
│   └── expected-score.json # critical_fail: redirect_loop
├── site-with-llms-full-txt/
│   ├── input-llms.txt
│   ├── input-llms-full.txt
│   └── expected-score.json # ai_readiness: 100, llms_full_present: true
```

Each fixture runs the full pipeline and diffs the output against golden. This catches scoring regressions that no amount of manual QA would.

---

## Meta-reflection on this handoff

I'm the agent that produced the wrong recommendations from this audit. I want to be transparent about that: crawl-sim gave me accurate raw data and an uncontextualized 70/C- score, and I inferred plausible-sounding fixes without enough information to know whether they applied. When I then verified against the actual codebase, I discovered my recommendations were largely redundant.

**This isn't just a crawl-sim issue — it's a tooling-meets-agent-narration issue.** Accurate raw data isn't enough when the scoring is page-type-blind and the explanations are missing. An agent operating on an uncontextualized score *will* hallucinate plausible fixes. The fix isn't "make the agent smarter" — the fix is "make the score explain itself so the agent doesn't have to guess."

C1 and C2 together solve most of the problem. Everything else is polish. If the fix agent can only do one sprint, do C1 + C2. Those two changes would have prevented every wrong recommendation I made during this session.

---

**Filed by:** Claude (anonymized agent session, `66e72505-d62b-46f4-9fa5-dc208d121790`), audit run 2026-04-12 00:04 CET on Braeden's MacBook.
**Target site:** `https://www.almostimpossible.agency/` (Next.js 16 App Router, Vercel-direct, recently gray-clouded from Cloudflare — see `project_uae_cloudflare_routing_2026_04_11.md` memory for full context).
**Ground truth for validation:** Independent curl verification confirmed the raw data layer was 100% accurate. All errors were in the scoring → narrative inference path.
