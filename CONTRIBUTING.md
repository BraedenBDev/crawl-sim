# Contributing to crawl-sim

Thanks for your interest in improving crawl-sim! This document explains how to contribute effectively.

## Ways to contribute

- **Report a bug** — open an [issue](https://github.com/BraedenBDev/crawl-sim/issues) with a minimal reproduction (URL + command + observed vs expected output).
- **Request a feature** — open an issue describing the use case. "X tool does Y; we should too" is a good framing.
- **Add or update a bot profile** — when a vendor updates their docs, the profile JSON in `profiles/` needs to follow.
- **Write a new check script** — think of new signals worth scoring.
- **Improve docs** — README, SKILL.md, research notes — all fair game.
- **Share real-world audit results** — even anonymized examples help validate the scoring model.

## Ground rules

### 1. Keep the core dependency-free

The shell scripts use **only `curl` and `jq`**. No Node, no Python, no Ruby, no Go, no Docker. `diff-render.sh` is the **single exception** because comparing server HTML vs JS-rendered DOM genuinely requires a browser.

If you think you need another tool, open an issue first to discuss. The dependency constraint is load-bearing — it's why the skill installs with one `npx` command and runs everywhere `bash` runs.

### 2. Every script outputs valid JSON to stdout

```bash
./scripts/your-new-check.sh https://example.com | jq empty
```

Must exit 0 with parseable JSON. No mixed log-lines-and-JSON. Errors go to stderr (non-zero exit is fine) but successful runs must produce clean JSON.

### 3. Scripts must be testable against a live URL

Test against at least two sites: a sparse one (`https://example.com`) and a rich one (try your own site or `https://www.almostimpossible.agency`). Paste the output in your PR.

### 4. Cite sources for bot profile changes

Every behavioral claim (`rendersJavaScript`, `respectsRobotsTxt`, crawl-delay support) needs a vendor doc link or a reproducible observation. Add the source to `research/bot-profiles-verified.md`. Use the `confidence` levels:

- **`official`** — documented by the vendor on their own site
- **`observed`** — consistent third-party testing confirms it
- **`inferred`** — logical deduction from UA string or related bot behavior

When you add an `observed` or `inferred` claim, document the reasoning in the profile's `notes` field.

## Development workflow

### Setup

```bash
git clone https://github.com/BraedenBDev/crawl-sim.git
cd crawl-sim
# No install step — scripts are directly runnable
```

### Running the full pipeline locally

```bash
TARGET="https://example.com"
RUN_DIR=$(mktemp -d -t crawl-sim-dev.XXXXXX)

for bot in googlebot gptbot claudebot perplexitybot; do
  ./scripts/fetch-as-bot.sh --out-dir "$RUN_DIR" "$TARGET" "profiles/${bot}.json" > "$RUN_DIR/fetch-${bot}.json"
  body_file=$(jq -r '.bodyFile' "$RUN_DIR/fetch-${bot}.json")
  ./scripts/extract-meta.sh   "$RUN_DIR/$body_file" > "$RUN_DIR/meta-${bot}.json"
  ./scripts/extract-jsonld.sh "$RUN_DIR/$body_file" > "$RUN_DIR/jsonld-${bot}.json"
  ./scripts/extract-links.sh  "$TARGET" "$RUN_DIR/$body_file" > "$RUN_DIR/links-${bot}.json"
  token=$(jq -r '.robotsTxtToken' "profiles/${bot}.json")
  ./scripts/check-robots.sh "$TARGET" "$token" > "$RUN_DIR/robots-${bot}.json"
done
./scripts/check-llmstxt.sh "$TARGET" > "$RUN_DIR/llmstxt.json"
./scripts/check-sitemap.sh "$TARGET" > "$RUN_DIR/sitemap.json"
./scripts/compute-score.sh "$RUN_DIR" | jq .
```

### Validating JSON output

```bash
for f in "$RUN_DIR"/*.json; do jq empty "$f" && echo "OK: $f"; done
```

### Coding standards for shell scripts

- Start every script with `#!/usr/bin/env bash` and `set -eu`
- Do **not** use `set -o pipefail` unless you explicitly handle grep-returns-1-on-no-match cases (use `|| true`)
- Use portable awk/sed — no GNU-only extensions. macOS has BSD tools
- Quote all variable expansions: `"$var"`, not `$var`
- Use `mktemp` and `trap '...' EXIT` for temp file cleanup
- Use `jq --arg` / `--argjson` to safely inject shell values into JSON templates
- Use `set -e` defensively — prefer explicit error handling over relying on exit propagation

### Commit conventions

Prefix commits with a type:

- `feat:` — new feature or script
- `fix:` — bug fix
- `docs:` — docs-only change
- `refactor:` — code change that neither fixes a bug nor adds a feature
- `test:` — adding or fixing tests
- `chore:` — build, tooling, or housekeeping

Keep the first line under 72 characters. Write in the imperative mood ("add X" not "added X").

### Pull request checklist

- [ ] Branch is up to date with `main`
- [ ] All modified scripts pass `bash -n` (syntax check)
- [ ] Integration test passes against `https://example.com` and one richer site
- [ ] All new JSON outputs validated with `jq empty`
- [ ] If adding a bot profile, sources are cited in `research/bot-profiles-verified.md`
- [ ] If changing scoring, the rationale is explained in the PR description
- [ ] README or SKILL.md updated if user-visible behavior changed

## Architecture decisions

When proposing a larger change, read the design spec at [`docs/specs/2026-04-11-crawl-sim-design.md`](./docs/specs/2026-04-11-crawl-sim-design.md) and the implementation plan at [`docs/plans/2026-04-11-crawl-sim-v1.md`](./docs/plans/2026-04-11-crawl-sim-v1.md).

Non-goals for v1 (please don't PR these without discussion):

- Full-site crawling (v1 is single-page audit)
- Historical tracking dashboards (JSON output enables this externally)
- Automated fixing — the agent recommends, the human applies
- TLS/HTTP2 fingerprint simulation

## Code of conduct

Be respectful. Assume good intent. If you disagree with a design decision, open an issue and explain your reasoning — don't just submit a PR that rewrites things silently.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](./LICENSE).

## Questions?

Open a [GitHub Discussion](https://github.com/BraedenBDev/crawl-sim/discussions) or an issue tagged `question`.
