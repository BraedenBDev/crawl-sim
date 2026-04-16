# Sprint: crawl-sim v1.5.0

**Goal:** Fix sitemap canonical-host false negative, surface render-diff failures, tighten Stage 3 orchestration, align schema with implementation, and close outstanding v1.4.5 bugs.

**Restore tag:** `restore/pre-sprint-1776330135`
**Branch:** `feat/v1.5.0`
**Worktree:** `.worktrees/v1.5.0/`

---

## Acceptance Criteria

Each becomes a failing test first (RED), then passes (GREEN), then refactors cleanly.

### AC-1 — HIGH — `check-sitemap.sh` canonical-host normalization
- Probing sitemap must follow redirects to resolve canonical host before constructing `$ORIGIN/sitemap.xml`.
- `containsTarget` must compare against the final URL, not the raw input.
- Acceptance: bare-domain and www-domain inputs for a www-canonical site return identical sitemap results (urls > 0, containsTarget true).
- **Files:** `skills/crawl-sim/scripts/check-sitemap.sh`, new fixture test in `test/run-scoring-tests.sh`.

### AC-2 — HIGH — `check-robots.sh` + `check-llmstxt.sh` canonical-host parity
- Same treatment as AC-1 for consistency; shared pattern identified by Codex.
- Acceptance: bare-domain vs www-domain inputs yield identical robots + llms results for a canonicalizing site.
- **Files:** `check-robots.sh`, `check-llmstxt.sh`, `_lib.sh` if shared helper emerges.

### AC-3 — MEDIUM — Compare report `-ge` tie bug
- `generate-compare-html.sh:89` → `-gt`.
- Acceptance: two reports with identical scores produce HTML where neither card has `winner` class.
- **Files:** `generate-compare-html.sh`, regression test.

### AC-4 — MEDIUM — `root-minimal` fixture drift
- Fixture must match `docs/output-schemas.md` (fields: `timing.ttfb`, `timing.total`, `redirectCount`, `redirectChain`, `headers`, `bot.userAgent`; remove `timing.connect`, `timing.firstByte`, `bot.robotsTxtToken`).
- Acceptance: fixture JSON validates against schema; `npm test` still green.
- **Files:** `test/fixtures/root-minimal/fetch-googlebot.json`, plus any other `fetch-<bot>.json` fixtures showing same drift.

### AC-5 — MEDIUM — `diff-render.sh` surface Playwright error detail
- Capture Playwright stderr; include first 500 chars in the skip reason.
- Acceptance: forcing an error surfaces specific message (e.g., "Timeout 30000ms exceeded"); schema still valid; `skipped:true` still set.
- **Files:** `diff-render.sh`, regression test with mocked failing render.

### AC-6 — MEDIUM — Stage 3 bounded retries + per-subcheck visibility
- `_lib.sh`: tighten retry timeout (15s initial, 10s retry → 25s max instead of 30s).
- Acceptance: a simulated hung subcheck doesn't exceed 25s; partial results still returned; timed-out subcheck marked.
- **Files:** `skills/crawl-sim/scripts/_lib.sh`, regression test with local hung server.

### AC-7 — LOW — `fetch-as-bot.sh` cross-device mv trap leak
- Clear `BODY_TMP_FILE=""` after successful `mv`.
- Acceptance: code-level only (grep + inspection); no regression in existing tests.
- **Files:** `skills/crawl-sim/scripts/fetch-as-bot.sh`.

### AC-8 — LOW — `deltaWords` schema drift
- `diff-render.sh` emits `deltaWords: rendered - server`.
- Schema in `docs/output-schemas.md` matches.
- Acceptance: success-path `diff-render.json` contains integer `deltaWords`; doc matches byte-for-byte.
- **Files:** `diff-render.sh`, `docs/output-schemas.md`, regression test.

### AC-9 — RELEASE — Version bump to 1.5.0
- Bump in all 7 locations (`package.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`, `compute-score.sh` `scoringVersion`, `generate-report-html.sh` `REPORT_VERSION`, `generate-compare-html.sh` `REPORT_VERSION`).
- CHANGELOG entry added (if CHANGELOG exists; else README Release Notes section).

---

## Files Expected to Touch

- `skills/crawl-sim/scripts/check-sitemap.sh`
- `skills/crawl-sim/scripts/check-robots.sh`
- `skills/crawl-sim/scripts/check-llmstxt.sh`
- `skills/crawl-sim/scripts/_lib.sh`
- `skills/crawl-sim/scripts/diff-render.sh`
- `skills/crawl-sim/scripts/fetch-as-bot.sh`
- `skills/crawl-sim/scripts/generate-compare-html.sh`
- `skills/crawl-sim/scripts/generate-report-html.sh`
- `skills/crawl-sim/scripts/compute-score.sh`
- `docs/output-schemas.md`
- `test/run-scoring-tests.sh`
- `test/fixtures/root-minimal/fetch-googlebot.json` (+ any other drifted fixtures)
- `package.json`, `.claude-plugin/*.json`, `.codex-plugin/plugin.json`

---

## Risks

- **Canonical-host probing (AC-1/2)** could introduce extra HTTP round-trips; must bound with short HEAD timeout.
- **Stage-3 retry timing change (AC-6)** could cause flaky CI on slow runners; use reasonable defaults.
- **Playwright stderr capture (AC-5)** may include multibyte or control chars — must be JSON-safe.
- **Fixture regeneration (AC-4)** risks invalidating other tests that read the same fixture; need to audit every `root-minimal` consumer.

---

## Content Parity Touchpoints

No CMS/Supabase — data layer is `test/fixtures/`. Parity = schema alignment between fixtures and `docs/output-schemas.md`. Covered by AC-4.

---

## Parking Lot

Items deferred to future releases:
- #26 version-drift automation (still manual after this release, same as before)
- Branch protection toggle (UI only, not code)
- `@crawl-sim` Codex host routing (not a repo defect)
- SKILL.md fabrication guardrails (already warns against speculation)

---

## Progress Log

Updated after each criterion completes.

- [ ] AC-1 sitemap canonical-host
- [ ] AC-2 robots + llms canonical-host
- [ ] AC-3 compare tie bug
- [ ] AC-4 fixture drift
- [ ] AC-5 render-diff error surfacing
- [ ] AC-6 stage-3 orchestration
- [ ] AC-7 trap leak
- [ ] AC-8 deltaWords schema
- [ ] AC-9 version bump + release commit
