# Sprint Plan — Bot Profile Enrichment + PDF/Compare

**Branch:** `feat/bot-profiles-pdf-compare`
**Sprint goal:** Enrich bot profiles with Cloudflare classification + robots.txt enforceability, add PDF report generation, and add comparative two-site audits.

## Acceptance Criteria

### Feature A — Bot Profile Enrichment

- [ ] AC-1: All 9 bot profiles have `purpose`, `cloudflareCategory`, and `robotsTxtEnforceability` fields
- [ ] AC-2: `compute-score.sh` propagates `robotsTxtEnforceability` to per-bot score output
- [ ] AC-3: SKILL.md narrative rules explain how to interpret enforceability when robots blocks a bot
- [ ] AC-4: Regression tests still pass (no scoring logic changes, just new fields)

### Feature B — PDF Report Generation

- [ ] AC-5: `scripts/generate-report-html.sh` produces a styled HTML audit report from `crawl-sim-report.json`
- [ ] AC-6: SKILL.md documents `--pdf` flag that calls `generate-report-html.sh` + `html-to-pdf.sh`
- [ ] AC-7: HTML template includes score card, category breakdown, per-bot details, and findings

### Feature C — Comparative Audits

- [ ] AC-8: SKILL.md documents `--compare <url2>` mode that runs two audits and produces a side-by-side report
- [ ] AC-9: `scripts/generate-compare-html.sh` produces a comparison HTML from two `crawl-sim-report.json` files
- [ ] AC-10: Comparison shows delta table, strengths/weaknesses, winner per category

## Parking Lot

_Items discovered during sprint that are out of scope:_

