#!/usr/bin/env bash
set -eu

# diff-render.sh — Compare server HTML word count vs JS-rendered word count
# Usage: diff-render.sh <url>
# Requires Playwright. Gracefully outputs { skipped: true } if unavailable.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

URL="${1:?Usage: diff-render.sh <url>}"
printf '[diff-render] comparing server HTML vs Playwright render for %s\n' "$URL" >&2

emit_skipped() {
  local reason="$1"
  jq -n \
    --arg url "$URL" \
    --arg reason "$reason" \
    '{
      url: $url,
      skipped: true,
      reason: $reason,
      serverWordCount: null,
      renderedWordCount: null,
      deltaWords: null,
      deltaPct: null,
      significantDelta: null
    }'
  exit 0
}

# Check for Node.js
if ! command -v node >/dev/null 2>&1; then
  emit_skipped "node not installed"
fi

# Check for Playwright — try to require it from the current dir or globally
PLAYWRIGHT_CHECK=$(node -e "
try {
  require('playwright');
  console.log('ok');
} catch (e) {
  try {
    require('playwright-core');
    console.log('ok');
  } catch (e2) {
    console.log('missing');
  }
}" 2>/dev/null || echo "missing")

if [ "$PLAYWRIGHT_CHECK" != "ok" ]; then
  emit_skipped "playwright not installed (run: npm install playwright && npx playwright install chromium)"
fi

# Fetch server HTML and count words
TMPDIR="${TMPDIR:-/tmp}"
SERVER_HTML=$(mktemp "$TMPDIR/crawlsim-server.XXXXXX")
RENDERED_HTML=$(mktemp "$TMPDIR/crawlsim-rendered.XXXXXX")
RENDER_STDERR=$(mktemp "$TMPDIR/crawlsim-render-stderr.XXXXXX")
trap 'rm -f "$SERVER_HTML" "$RENDERED_HTML" "$RENDER_STDERR"' EXIT

# Fetch server HTML with Googlebot UA
UA="Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
curl -sS -L -A "$UA" -o "$SERVER_HTML" --max-time 30 "$URL" 2>/dev/null || {
  emit_skipped "failed to fetch server HTML"
}

SERVER_WORDS=$(count_words "$SERVER_HTML")
[ -z "$SERVER_WORDS" ] && SERVER_WORDS=0

# Use Playwright to render and capture the final DOM
# Avoid a hard dependency on `networkidle` because analytics-heavy sites often
# keep the network busy indefinitely, causing false skips on otherwise healthy pages.
node -e "
(async () => {
  const playwright = (() => {
    try {
      return require('playwright');
    } catch (e) {
      return require('playwright-core');
    }
  })();
  const { chromium } = playwright;
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({
      userAgent: 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'
    });
    const page = await context.newPage();
    await page.goto(process.argv[1], { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(3000);
    const html = await page.content();
    const fs = require('fs');
    fs.writeFileSync(process.argv[2], html);
  } finally {
    await browser.close();
  }
})().catch(err => {
  console.error('RENDER_ERROR:', err.message);
  process.exit(1);
});
" "$URL" "$RENDERED_HTML" 2>"$RENDER_STDERR" || {
  # Surface the first line of Playwright's stderr so the caller can
  # distinguish a launch failure from a navigation timeout from a page bug.
  DETAIL=$(head -c 500 "$RENDER_STDERR" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^RENDER_ERROR: //; s/^ +//; s/ +$//')
  if [ -n "$DETAIL" ]; then
    emit_skipped "playwright render failed: $DETAIL"
  else
    emit_skipped "playwright render failed"
  fi
}

RENDERED_WORDS=$(count_words "$RENDERED_HTML")
[ -z "$RENDERED_WORDS" ] && RENDERED_WORDS=0

# Compute deltas (rendered - server)
DELTA_WORDS=$((RENDERED_WORDS - SERVER_WORDS))
DELTA_PCT=0
SIGNIFICANT=false
if [ "$SERVER_WORDS" -gt 0 ]; then
  DELTA_PCT=$(awk -v s="$SERVER_WORDS" -v r="$RENDERED_WORDS" \
    'BEGIN { printf "%.1f", ((r - s) / s) * 100 }')
  ABS_DELTA=$(awk -v d="$DELTA_PCT" 'BEGIN { printf "%d", (d < 0 ? -d : d) }')
  if [ "$ABS_DELTA" -gt 20 ]; then
    SIGNIFICANT=true
  fi
elif [ "$RENDERED_WORDS" -gt 0 ]; then
  # Server had nothing, rendered has content — significant
  DELTA_PCT=100
  SIGNIFICANT=true
fi

jq -n \
  --arg url "$URL" \
  --argjson serverWords "$SERVER_WORDS" \
  --argjson renderedWords "$RENDERED_WORDS" \
  --argjson deltaWords "$DELTA_WORDS" \
  --argjson deltaPct "$DELTA_PCT" \
  --argjson significant "$SIGNIFICANT" \
  '{
    url: $url,
    skipped: false,
    serverWordCount: $serverWords,
    renderedWordCount: $renderedWords,
    deltaWords: $deltaWords,
    deltaPct: $deltaPct,
    significantDelta: $significant,
    interpretation: (
      if $significant and $deltaPct > 0 then
        "JS rendering reveals significantly more content than server HTML — non-rendering bots (GPTBot/ClaudeBot/Perplexity) will see less."
      elif $significant and $deltaPct < 0 then
        "Server HTML has more content than rendered DOM — unusual, possibly JS removing content."
      else
        "Server HTML and rendered DOM word counts are close — no significant hydration delta."
      end
    )
  }'
