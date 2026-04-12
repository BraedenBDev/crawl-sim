#!/usr/bin/env bash
set -eu

# build-report.sh — Consolidate all crawl-sim outputs into a single JSON report
# Usage: build-report.sh <results-dir>
# Output: JSON to stdout

RESULTS_DIR="${1:?Usage: build-report.sh <results-dir>}"

if [ ! -f "$RESULTS_DIR/score.json" ]; then
  echo "Error: score.json not found in $RESULTS_DIR — run compute-score.sh first" >&2
  exit 1
fi

SCORE=$(cat "$RESULTS_DIR/score.json")

# Collect per-bot raw data
PER_BOT="{}"
for f in "$RESULTS_DIR"/fetch-*.json; do
  [ -f "$f" ] || continue
  bot_id=$(basename "$f" .json | sed 's/^fetch-//')

  BOT_RAW=$(jq -n \
    --argjson fetch "$(jq '{status, timing, size, wordCount, redirectCount, finalUrl, redirectChain, fetchFailed, error}' "$f" 2>/dev/null || echo '{}')" \
    --argjson meta "$(jq '.' "$RESULTS_DIR/meta-$bot_id.json" 2>/dev/null || echo '{}')" \
    --argjson jsonld "$(jq '{blockCount, types, blocks}' "$RESULTS_DIR/jsonld-$bot_id.json" 2>/dev/null || echo '{}')" \
    --argjson links "$(jq '.' "$RESULTS_DIR/links-$bot_id.json" 2>/dev/null || echo '{}')" \
    --argjson robots "$(jq '.' "$RESULTS_DIR/robots-$bot_id.json" 2>/dev/null || echo '{}')" \
    '{fetch: $fetch, meta: $meta, jsonld: $jsonld, links: $links, robots: $robots}')

  PER_BOT=$(printf '%s' "$PER_BOT" | jq --argjson raw "$BOT_RAW" --arg id "$bot_id" '.[$id] = $raw')
done

# Collect independent (non-per-bot) data
INDEPENDENT=$(jq -n \
  --argjson sitemap "$(jq '.' "$RESULTS_DIR/sitemap.json" 2>/dev/null || echo '{}')" \
  --argjson llmstxt "$(jq '.' "$RESULTS_DIR/llmstxt.json" 2>/dev/null || echo '{}')" \
  --argjson diffRender "$(jq '.' "$RESULTS_DIR/diff-render.json" 2>/dev/null || echo '{"skipped":true,"reason":"not_found"}')" \
  '{sitemap: $sitemap, llmstxt: $llmstxt, diffRender: $diffRender}')

# Merge score + raw data
printf '%s' "$SCORE" | jq \
  --argjson perBot "$PER_BOT" \
  --argjson independent "$INDEPENDENT" \
  '. + {raw: {perBot: $perBot, independent: $independent}}'
