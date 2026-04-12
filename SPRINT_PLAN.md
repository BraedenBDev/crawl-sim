# Sprint Plan — v1.2.0 Triple Sprint (A + B + C)

**Branch:** `feat/v1.2-triple-sprint`
**Restore tag:** `restore/pre-sprint-*` on main at `b7bf903`
**Source:** Issues #11, #12; `docs/plans/2026-04-12-triple-sprint.md`
**Sprint goal:** Fix the parallel-fetch correctness bug, ship accuracy sprint 2 (C3+C4+H2+H3), and package crawl-sim as a Claude Code plugin.

## Acceptance Criteria

### Sprint A — fetch-as-bot.sh parallel fix (#11)

- [ ] AC-A1: `fetch-as-bot.sh` emits `[botId] fetching <url>` and `[botId] ok: status=... size=... words=... time=...` to stderr on success
- [ ] AC-A2: When curl fails (e.g., `example.invalid`), the script outputs JSON with `fetchFailed: true` and a non-empty `error` field, exits 0
- [ ] AC-A3: `compute-score.sh` treats `fetchFailed: true` as grade F with `score: 0` on all categories
- [ ] AC-A4: Parallel invocation of 4 fetches against a valid URL never produces a 0-byte file (manual smoke test)

### Sprint B — accuracy sprint 2 (#12)

- [ ] AC-B1: `extract-jsonld.sh` emits `blocks[]` with per-block `type` and `fields` arrays
- [ ] AC-B2: `compute-score.sh` validates required fields per schema type (C3) — `missing_required_field` violations reduce score
- [ ] AC-B3: `compute-score.sh` emits a `parity` object with `score`, `grade`, `minWords`, `maxWords`, `maxDeltaPct`, `interpretation` (C4)
- [ ] AC-B4: Parity score = 100 when single bot; parity < 50 when 10x word count divergence
- [ ] AC-B5: `compute-score.sh` emits `warnings[]` array; absent diff-render produces a `diff_render_unavailable` warning (H2)
- [ ] AC-B6: `fetch-as-bot.sh` emits `redirectCount`, `finalUrl`, and `redirectChain[]` in its JSON output (H3)

### Sprint C — plugin packaging

- [ ] AC-C1: `.claude-plugin/plugin.json` exists with correct name, version, metadata
- [ ] AC-C2: `.claude-plugin/marketplace.json` exists with valid marketplace schema
- [ ] AC-C3: `skills/crawl-sim/SKILL.md` exists and is the canonical skill file
- [ ] AC-C4: `skills/crawl-sim/scripts/` and `skills/crawl-sim/profiles/` contain all scripts/profiles
- [ ] AC-C5: Root-level symlinks (SKILL.md, scripts, profiles) point to `skills/crawl-sim/` — npm compat preserved
- [ ] AC-C6: `npm test` still passes through symlinks
- [ ] AC-C7: `bin/install.js` finds sources under new paths
- [ ] AC-C8: README documents `/plugin install BraedenBDev/crawl-sim@github`

## Files expected to change

| File | Sprint | Change |
|------|--------|--------|
| `scripts/fetch-as-bot.sh` | A, B | Curl error handling, progress lines, redirect chain |
| `scripts/compute-score.sh` | A, B | fetchFailed handling, field validation, parity, warnings |
| `scripts/extract-jsonld.sh` | B | Add blocks[].fields to output |
| `scripts/schema-fields.sh` | B | New — required fields per schema type |
| `test/run-scoring-tests.sh` | A, B | New assertions for all ACs |
| `test/fixtures/fetch-failed/` | A | New fixture |
| `test/fixtures/root-invalid-fields/` | B | New fixture |
| `test/fixtures/parity-mismatch/` | B | New fixture |
| `.claude-plugin/plugin.json` | C | New |
| `.claude-plugin/marketplace.json` | C | New |
| `skills/crawl-sim/` | C | Moved SKILL.md + scripts + profiles |
| `bin/install.js` | C | Path updates |
| `package.json` | C | files array, version bump |
| `README.md` | C | Plugin install docs |

## Dependency order

Sprint A first (correctness blocker), then B (builds on reliable fetches), then C (structural).

## Parking Lot

_Items discovered during sprint that are out of scope:_

