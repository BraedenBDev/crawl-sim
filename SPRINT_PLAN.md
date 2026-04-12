# Sprint Plan — v1.3.0 Quick Wins + Polish + Roadmap

**Branch:** `feat/v1.3-polish-sprint`
**Restore tag:** `restore/pre-sprint-*` on main at `0e42ec6`
**Source:** `docs/plans/2026-04-12-quick-wins-plus-polish.md`, issues #1, #3, #12
**Sprint goal:** Ship all remaining accuracy items (M1–M5, R2–R4), parallelize fetches (#1), batch jq (#3), bump CI, and close the #12 umbrella.

## Acceptance Criteria

### Wave 1 — Quick Wins

- [ ] AC-1: `.github/workflows/publish.yml` uses `actions/checkout@v5` and `actions/setup-node@v5`
- [ ] AC-2: SKILL.md Stage 1 fetches run in parallel (`&` + `wait`) with serial retry fallback
- [ ] AC-3: `compute-score.sh` per-bot jq calls batched (~34 → ~10); golden file still passes

### Wave 2 — Sprint 3 Polish

- [ ] AC-4: `check-llmstxt.sh` emits top-level `exists` field (true if either variant exists)
- [ ] AC-5: `check-sitemap.sh` emits `sampleUrls` array (first 10 `<loc>` values)
- [ ] AC-6: `extract-links.sh` uses flat schema (`total`, `internal`, `external`, `internalUrls`, `externalUrls`)
- [ ] AC-7: `docs/output-schemas.md` documents JSON contract for all 9 scripts
- [ ] AC-8: `build-report.sh` consolidates score + raw data into single `crawl-sim-report.json`

### Wave 3 — Sprint 4 Roadmap

- [ ] AC-9: SKILL.md has parity-aware display guidance (collapse bot rows when parity ≥ 95)
- [ ] AC-10: Robots-blocked bots get 0/F on accessibility (critical-fail override)
- [ ] AC-11: Violations carry `confidence` field (`high`/`medium`/`low`)

## Files expected to change

- `.github/workflows/publish.yml` — AC-1
- `skills/crawl-sim/SKILL.md` — AC-2, AC-8, AC-9
- `skills/crawl-sim/scripts/compute-score.sh` — AC-3, AC-6, AC-10, AC-11
- `skills/crawl-sim/scripts/check-llmstxt.sh` — AC-4
- `skills/crawl-sim/scripts/check-sitemap.sh` — AC-5
- `skills/crawl-sim/scripts/extract-links.sh` — AC-6
- `skills/crawl-sim/scripts/build-report.sh` — AC-8 (new)
- `docs/output-schemas.md` — AC-7 (new)
- `test/run-scoring-tests.sh` — AC-3, AC-4, AC-6, AC-8, AC-10, AC-11
- `test/fixtures/` — updated fixtures for new schemas

## Parking Lot

_Items discovered during sprint that are out of scope:_

