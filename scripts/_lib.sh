#!/usr/bin/env bash
# crawl-sim shared helpers. Source this from other scripts:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "$SCRIPT_DIR/_lib.sh"

# Extract "https://host" from any URL.
origin_from_url() {
  printf '%s' "$1" | sed -E 's#(^https?://[^/]+).*#\1#'
}

# Extract the host from a URL, stripping "www." prefix.
host_from_url() {
  printf '%s' "$1" | sed -E 's#^https?://##' | sed -E 's#/.*$##' | sed -E 's#^www\.##'
}

# Extract the path portion of a URL. Returns "/" if empty.
path_from_url() {
  local p
  p=$(printf '%s' "$1" | sed -E 's#^https?://[^/]+##')
  printf '%s' "${p:-/}"
}

# Extract the directory portion of a URL's path (everything up to the last /).
# Used for resolving relative URLs against a base page URL.
# Example: https://example.com/blog/index.html -> https://example.com/blog/
dir_from_url() {
  local url="$1"
  local origin
  origin=$(origin_from_url "$url")
  local p
  p=$(path_from_url "$url")
  # If path ends with /, keep as-is; otherwise strip last segment
  case "$p" in
    */) printf '%s%s' "$origin" "$p" ;;
    *)  printf '%s%s/' "$origin" "$(printf '%s' "$p" | sed -E 's#/[^/]*$##')" ;;
  esac
}

# Count visible words in an HTML file (strips tags, counts alnum tokens).
count_words() {
  sed 's/<[^>]*>//g' "$1" | tr -s '[:space:]' '\n' | grep -c '[a-zA-Z0-9]' || true
}

# Fetch a URL to a local file and return the HTTP status code on stdout.
# Usage: status=$(fetch_to_file <url> <output-file> [timeout-seconds])
fetch_to_file() {
  local url="$1"
  local out="$2"
  local timeout="${3:-15}"
  curl -sS -L -o "$out" -w '%{http_code}' --max-time "$timeout" "$url" 2>/dev/null || echo "000"
}
