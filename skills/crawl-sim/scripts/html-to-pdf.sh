#!/usr/bin/env bash
set -eu

# html-to-pdf.sh — Convert an HTML file to PDF using the best available renderer.
# Usage: html-to-pdf.sh <input.html> <output.pdf>
#
# Detection order:
#   1. Chrome/Chromium at known system paths
#   2. Playwright's bundled Chromium (npx playwright pdf)
#   3. Neither → exit 1 with instructions
#
# This script is intentionally renderer-agnostic. Callers don't need to know
# which engine is available — they just pass HTML in and get PDF out.

INPUT="${1:?Usage: html-to-pdf.sh <input.html> <output.pdf>}"
OUTPUT="${2:?Usage: html-to-pdf.sh <input.html> <output.pdf>}"

if [ ! -f "$INPUT" ]; then
  echo "Error: input file not found: $INPUT" >&2
  exit 1
fi

# Convert to file:// URL for Chrome (needs absolute path)
case "$INPUT" in
  /*) INPUT_URL="file://$INPUT" ;;
  *)  INPUT_URL="file://$(pwd)/$INPUT" ;;
esac

# --- Strategy 1: System Chrome/Chromium ---

find_chrome() {
  # macOS
  for path in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary" \
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"; do
    [ -x "$path" ] && echo "$path" && return 0
  done
  # Linux / WSL
  for cmd in google-chrome chromium-browser chromium google-chrome-stable; do
    command -v "$cmd" >/dev/null 2>&1 && command -v "$cmd" && return 0
  done
  return 1
}

if CHROME=$(find_chrome); then
  printf '[html-to-pdf] using Chrome: %s\n' "$CHROME" >&2
  "$CHROME" \
    --headless \
    --disable-gpu \
    --no-sandbox \
    --print-to-pdf="$OUTPUT" \
    --no-margins \
    "$INPUT_URL" 2>/dev/null
  if [ -s "$OUTPUT" ]; then
    printf '[html-to-pdf] wrote %s (%s bytes)\n' "$OUTPUT" "$(wc -c < "$OUTPUT" | tr -d ' ')" >&2
    exit 0
  fi
  printf '[html-to-pdf] Chrome produced empty output, trying Playwright fallback\n' >&2
fi

# --- Strategy 2: Playwright's bundled Chromium ---

if command -v npx >/dev/null 2>&1; then
  # Check if playwright is installed (don't auto-install)
  if npx playwright --version >/dev/null 2>&1; then
    printf '[html-to-pdf] using Playwright bundled Chromium\n' >&2
    npx playwright pdf "$INPUT_URL" "$OUTPUT" 2>/dev/null
    if [ -s "$OUTPUT" ]; then
      printf '[html-to-pdf] wrote %s (%s bytes)\n' "$OUTPUT" "$(wc -c < "$OUTPUT" | tr -d ' ')" >&2
      exit 0
    fi
    printf '[html-to-pdf] Playwright produced empty output\n' >&2
  fi
fi

# --- No renderer available ---

echo "Error: no PDF renderer found." >&2
echo "  Install one of:" >&2
echo "    - Google Chrome (recommended — already handles print CSS)" >&2
echo "    - Playwright: npx playwright install chromium" >&2
echo "  The HTML report is still available at: $INPUT" >&2
exit 1
