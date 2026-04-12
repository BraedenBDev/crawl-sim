#!/usr/bin/env bash
set -eu

# generate-report-html.sh — Generate a styled HTML audit report from crawl-sim-report.json
# Usage: generate-report-html.sh <report.json> [output.html]
# Output: HTML to stdout (or file if second arg given)

REPORT="${1:?Usage: generate-report-html.sh <report.json> [output.html]}"
OUTPUT="${2:-}"

if [ ! -f "$REPORT" ]; then
  echo "Error: report not found: $REPORT" >&2
  exit 1
fi

# Extract key data
URL=$(jq -r '.url' "$REPORT")
TIMESTAMP=$(jq -r '.timestamp' "$REPORT")
PAGE_TYPE=$(jq -r '.pageType' "$REPORT")
OVERALL_SCORE=$(jq -r '.overall.score' "$REPORT")
OVERALL_GRADE=$(jq -r '.overall.grade' "$REPORT")
PARITY_SCORE=$(jq -r '.parity.score' "$REPORT")
PARITY_GRADE=$(jq -r '.parity.grade' "$REPORT")
PARITY_INTERP=$(jq -r '.parity.interpretation' "$REPORT")

# Build per-bot table rows
BOT_ROWS=$(jq -r '
  .bots | to_entries[] |
  "<tr><td>\(.value.name)</td><td>\(.value.score)</td><td>\(.value.grade)</td>" +
  "<td>\(.value.categories.accessibility.score)</td>" +
  "<td>\(.value.categories.contentVisibility.score)</td>" +
  "<td>\(.value.categories.structuredData.score)</td>" +
  "<td>\(.value.categories.technicalSignals.score)</td>" +
  "<td>\(.value.categories.aiReadiness.score)</td>" +
  "<td>\(.value.purpose // "-")</td>" +
  "<td class=\"enforce-\(.value.robotsTxtEnforceability // "unknown")\">\(.value.robotsTxtEnforceability // "-")</td></tr>"
' "$REPORT")

# Build category averages
CAT_ROWS=$(jq -r '
  .categories | to_entries[] |
  "<tr><td>\(.key)</td><td>\(.value.score)</td><td>\(.value.grade)</td></tr>"
' "$REPORT")

# Build warnings
WARNINGS_HTML=$(jq -r '
  if (.warnings | length) > 0 then
    (.warnings[] | "<div class=\"warning\"><strong>⚠ \(.code)</strong>: \(.message)</div>")
  else
    "<div class=\"ok\">No warnings.</div>"
  end
' "$REPORT")

# Build structured data details for first bot
SD_DETAILS=$(jq -r '
  .bots | to_entries[0].value.categories.structuredData |
  "<p><strong>Page type:</strong> \(.pageType)</p>" +
  "<p><strong>Present:</strong> \(.present | join(", "))</p>" +
  "<p><strong>Missing:</strong> \(if (.missing | length) > 0 then (.missing | join(", ")) else "none" end)</p>" +
  "<p><strong>Violations:</strong> \(if (.violations | length) > 0 then (.violations | map("\(.kind): \(.schema // .field // "")") | join(", ")) else "none" end)</p>" +
  "<p><strong>Notes:</strong> \(.notes)</p>"
' "$REPORT")

# Generate HTML
HTML=$(cat <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>crawl-sim Audit — ${URL}</title>
<style>
  @page { size: A4; margin: 20mm; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: #1a1a1a; line-height: 1.5; padding: 40px; max-width: 900px; margin: 0 auto; }
  h1 { font-size: 28px; margin-bottom: 4px; }
  .subtitle { color: #666; font-size: 14px; margin-bottom: 24px; }
  .score-hero { display: flex; align-items: center; gap: 24px; background: #f8f9fa; border-radius: 12px; padding: 24px; margin-bottom: 24px; }
  .score-big { font-size: 64px; font-weight: 800; line-height: 1; }
  .grade-big { font-size: 48px; font-weight: 700; color: #2d7d46; }
  .score-meta { font-size: 14px; color: #666; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 24px; font-size: 13px; }
  th { background: #1a1a1a; color: white; padding: 8px 12px; text-align: left; font-weight: 600; }
  td { padding: 8px 12px; border-bottom: 1px solid #e0e0e0; }
  tr:nth-child(even) { background: #f8f9fa; }
  .enforce-advisory_only { color: #c0392b; font-weight: 600; }
  .enforce-stealth_risk { color: #e67e22; font-weight: 600; }
  .enforce-enforced { color: #27ae60; }
  h2 { font-size: 18px; margin: 32px 0 12px; border-bottom: 2px solid #1a1a1a; padding-bottom: 4px; }
  .warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 12px 16px; margin-bottom: 8px; border-radius: 4px; font-size: 13px; }
  .ok { color: #27ae60; font-size: 13px; }
  .parity { display: flex; gap: 16px; align-items: center; background: #e8f5e9; border-radius: 8px; padding: 16px; margin-bottom: 24px; }
  .parity.low { background: #ffebee; }
  .footer { margin-top: 40px; padding-top: 16px; border-top: 1px solid #e0e0e0; font-size: 11px; color: #999; }
  @media print { body { padding: 0; } .score-hero { break-inside: avoid; } table { break-inside: avoid; } }
</style>
</head>
<body>

<h1>crawl-sim — Bot Visibility Audit</h1>
<div class="subtitle">${URL} &middot; ${TIMESTAMP} &middot; Page type: ${PAGE_TYPE}</div>

<div class="score-hero">
  <div>
    <span class="score-big">${OVERALL_SCORE}</span><span style="font-size:24px;color:#666">/100</span>
  </div>
  <div>
    <div class="grade-big">${OVERALL_GRADE}</div>
    <div class="score-meta">Overall Score</div>
  </div>
</div>

<div class="parity${PARITY_SCORE:+ }$([ "$PARITY_SCORE" -lt 50 ] 2>/dev/null && echo 'low' || echo '')">
  <div><strong>Content Parity:</strong> ${PARITY_SCORE}/100 (${PARITY_GRADE})</div>
  <div>${PARITY_INTERP}</div>
</div>

${WARNINGS_HTML}

<h2>Per-Bot Scores</h2>
<table>
<tr><th>Bot</th><th>Score</th><th>Grade</th><th>Access</th><th>Content</th><th>Schema</th><th>Technical</th><th>AI</th><th>Purpose</th><th>robots.txt</th></tr>
${BOT_ROWS}
</table>

<h2>Category Averages</h2>
<table>
<tr><th>Category</th><th>Score</th><th>Grade</th></tr>
${CAT_ROWS}
</table>

<h2>Structured Data Details</h2>
${SD_DETAILS}

<div class="footer">
  Generated by crawl-sim v1.4.0 &middot; <a href="https://github.com/BraedenBDev/crawl-sim">github.com/BraedenBDev/crawl-sim</a>
</div>

</body>
</html>
HTMLEOF
)

if [ -n "$OUTPUT" ]; then
  printf '%s' "$HTML" > "$OUTPUT"
  printf '[generate-report-html] wrote %s\n' "$OUTPUT" >&2
else
  printf '%s' "$HTML"
fi
