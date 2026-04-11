# Sprint Plan — C1 + C2 Accuracy Foundation

**Branch:** `feat/page-type-aware-scoring`
**Restore tag:** `restore/pre-sprint-1775951553`
**Source:** `docs/issues/2026-04-12-accuracy-from-live-audit.md` (sections C1, C2)
**Sprint goal (one sentence):** Make crawl-sim's structuredData scoring page-type-aware and self-explaining so the narrative layer never has to guess what was penalized.

## Why these two only

From the handoff doc's meta-reflection: *"C1 and C2 together solve most of the problem. Everything else is polish. If the fix agent can only do one sprint, do C1 + C2. Those two changes would have prevented every wrong recommendation I made during this session."* The other 13 items (H1–H3, M1–M5, R1–R4) are explicitly out of scope for this sprint and are parked.

## Acceptance criteria

Each becomes a test in `test/scoring.test.sh`. Tests are bash assertions over the JSON emitted by `scripts/compute-score.sh` against synthetic fixtures in `test/fixtures/`.

1. **AC1 — page type detection from URL.** `compute-score.sh` derives a page type from the URL in the first `fetch-*.json` file:
   - `https://example.com/` or exactly the origin → `root`
   - URL containing `/work/<slug>`, `/articles/<slug>`, `/journal/<slug>`, `/blog/<slug>`, `/case/<slug>` → `detail`
   - Terminal `/work`, `/journal`, `/blog`, `/articles`, `/careers` (no slug after) → `archive`
   - URL containing `faq` → `faq`
   - URL containing `about`, `team`, `purpose` → `about`
   - URL containing `contact` → `contact`
   - Anything else → `generic`

2. **AC2 — `--page-type <type>` override.** When the flag is passed, it overrides URL-based detection. Used by callers who know the page type already.

3. **AC3 — per-page-type rubrics applied.** Structured-data scoring uses per-type `expected` / `optional` / `forbidden` schema sets:

   | type    | expected                                  | optional                              | forbidden                                  |
   |---------|-------------------------------------------|---------------------------------------|--------------------------------------------|
   | root    | Organization, WebSite                     | ProfessionalService, LocalBusiness    | BreadcrumbList, Article, FAQPage           |
   | detail  | Article, BreadcrumbList                   | NewsArticle, ImageObject              | CollectionPage, ItemList                   |
   | archive | CollectionPage, ItemList, BreadcrumbList  | (none)                                | Article, Product                           |
   | faq     | FAQPage, BreadcrumbList                   | WebPage                               | Article, CollectionPage                    |
   | about   | AboutPage, BreadcrumbList, Organization   | Person                                | Article, Product                           |
   | contact | ContactPage, BreadcrumbList               | PostalAddress                         | Article, Product                           |
   | generic | WebPage, BreadcrumbList                   | (none)                                | (none)                                     |

4. **AC4 — root page with Organization+WebSite scores 100.** A root page with exactly the schema.org-recommended root set must score 100 on `structuredData`. This is the regression that the live audit produced 70/C-.

5. **AC5 — same JSON-LD scored as `detail` scores <70.** Same Organization+WebSite content, when the page type is forced to `detail`, must score below 70 because `Article` and `BreadcrumbList` are missing.

6. **AC6 — forbidden schemas penalize.** A root page that ships `Article` + `FAQPage` schemas (forbidden for root) must score below the perfect-root score and the violation must appear in the explained output.

7. **AC7 — score output is self-explaining.** Every per-bot `categories.structuredData` block in `score.json` must include:
   - `score`, `grade` (existing)
   - `pageType` (string)
   - `expected` (array), `optional` (array), `forbidden` (array)
   - `present` (array), `missing` (array), `extras` (array), `violations` (array)
   - `calculation` (string explaining how the score was derived)
   - `notes` (string with a human-readable summary)

8. **AC8 — top-level `pageType` field.** `score.json` exposes the detected page type at the top level so the narrative layer can read it without descending into a per-bot block.

9. **AC9 — non-structured categories untouched.** Accessibility, contentVisibility, technicalSignals, aiReadiness scores must be byte-identical to the baseline scoring for an unchanged input. Verified by golden file comparison on a representative fixture.

10. **AC10 — schema discovery uses raw `types[]`, not flag list.** The current `extract-jsonld.sh` only flags 7 types. The new scorer reads the full `types[]` array so the `present` set isn't artificially capped at the 7 hardcoded flags. (Without this, AC4 would never see `WebSite` if extract-jsonld stopped flagging it.) Implementation note: `types[]` is already populated correctly — the change is purely in `compute-score.sh`'s consumer logic.

## Files expected to touch

- `scripts/compute-score.sh` — major rewrite of the structuredData category; add page-type detection; emit explained block
- `scripts/_lib.sh` — add `page_type_for_url()` helper if it stays small enough; otherwise inline
- `test/` (new directory) — fixture files + test runner
- `test/run-scoring-tests.sh` (new) — bash test runner with assertion helpers
- `test/fixtures/` (new) — synthetic results dirs that mirror the real `RUN_DIR` shape (one fetch-*.json + meta-*.json + jsonld-*.json + links-*.json + robots-*.json + llmstxt.json + sitemap.json per case)
- `package.json` — wire `npm test` to the runner
- `SKILL.md` — document the `--page-type` flag and the new score.json shape
- `README.md` — update sample output snippet if it shows structuredData

## Risks

- **Bash 3.2 compatibility (macOS default).** No associative arrays. Rubric tables must be encoded as space-delimited strings or function-dispatched. I'll use functions per page type to avoid `declare -A`.
- **jq complexity creep.** The explained-output JSON construction will be a single big `jq -n` call. Risk of typos breaking everything — mitigated by tests.
- **Synthetic fixtures must match real script output exactly.** If I get the input shape wrong, tests pass against fiction. Mitigation: capture one real fixture from a known-clean fetch and use it as the structural template.
- **`extract-jsonld.sh` flag list is finite.** AC10 requires consuming `types[]` directly. The flag fields stay (other code may use them) but they're not the source of truth for scoring.

## Out of scope (parking lot)

- C3 (correctness over presence — semantic field validation per schema type)
- C4 (cross-bot parity signal as a distinct category)
- H1, H2, H3 (script error surfacing)
- M1–M5 (output schema docs, sample URLs, link flattening, consolidated report)
- R1–R4 (multi-URL mode, confidence levels, adaptive display, critical-fail criteria)
- Updating `compute-score.sh` to read `types[]` from a different source — the existing `types[]` is correct
- Refactoring `compute-score.sh` outside of the structuredData category
- Adding any feature flag — change the format directly, no backwards-compat shim

## Parking Lot

(empty — populate during the sprint if blocked)

## Content parity (Phase 4)

Not applicable in the traditional sense — no CMS / Supabase / DB. The "content layer" for this CLI is `SKILL.md`, `README.md`, and the bot profile JSONs. Phase 4 will:
1. Update `SKILL.md` to document the `--page-type` flag and the explained score output shape (so the narrative layer instructions stay aligned with the data layer).
2. Update `README.md` if it shows a sample `structuredData` block.
3. Verify all bot profile JSONs still parse and the scorer accepts them unchanged.
