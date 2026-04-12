#!/usr/bin/env bash
set -eu

# generate-compare-html.sh — Generate a side-by-side comparison HTML from two crawl-sim reports
# Usage: generate-compare-html.sh <report-a.json> <report-b.json> [output.html]

REPORT_A="${1:?Usage: generate-compare-html.sh <report-a.json> <report-b.json> [output.html]}"
REPORT_B="${2:?Usage: generate-compare-html.sh <report-a.json> <report-b.json> [output.html]}"
OUTPUT="${3:-}"

for f in "$REPORT_A" "$REPORT_B"; do
  [ -f "$f" ] || { echo "Error: report not found: $f" >&2; exit 1; }
done

# Extract key data from both reports
URL_A=$(jq -r '.url' "$REPORT_A")
URL_B=$(jq -r '.url' "$REPORT_B")
SCORE_A=$(jq -r '.overall.score' "$REPORT_A")
SCORE_B=$(jq -r '.overall.score' "$REPORT_B")
GRADE_A=$(jq -r '.overall.grade' "$REPORT_A")
GRADE_B=$(jq -r '.overall.grade' "$REPORT_B")
PARITY_A=$(jq -r '.parity.score' "$REPORT_A")
PARITY_B=$(jq -r '.parity.score' "$REPORT_B")

# Build category comparison rows
CAT_COMPARE=$(jq -r --slurpfile b "$REPORT_B" '
  .categories | to_entries[] |
  . as $cat |
  ($b[0].categories[$cat.key]) as $bcat |
  (if $cat.value.score > $bcat.score then "winner-a"
   elif $cat.value.score < $bcat.score then "winner-b"
   else "tie" end) as $cls |
  ($cat.value.score - $bcat.score) as $delta |
  "<tr class=\"\($cls)\"><td>\($cat.key)</td>" +
  "<td>\($cat.value.score) (\($cat.value.grade))</td>" +
  "<td>\($bcat.score) (\($bcat.grade))</td>" +
  "<td>\(if $delta > 0 then "+\($delta)" elif $delta < 0 then "\($delta)" else "=" end)</td></tr>"
' "$REPORT_A")

# Build per-bot comparison (using the 4 main bots)
BOT_COMPARE=$(jq -r --slurpfile b "$REPORT_B" '
  ["googlebot", "gptbot", "claudebot", "perplexitybot"] | .[] |
  . as $id |
  (input.bots[$id] // {score: 0, grade: "N/A"}) as $ba |
  ($b[0].bots[$id] // {score: 0, grade: "N/A"}) as $bb |
  ($ba.score - $bb.score) as $delta |
  "<tr><td>\($id)</td>" +
  "<td>\($ba.score) (\($ba.grade))</td>" +
  "<td>\($bb.score) (\($bb.grade))</td>" +
  "<td>\(if $delta > 0 then "+\($delta)" elif $delta < 0 then "\($delta)" else "=" end)</td></tr>"
' "$REPORT_A")

# Determine overall winner
if [ "$SCORE_A" -gt "$SCORE_B" ]; then
  WINNER="Site A leads by $((SCORE_A - SCORE_B)) points"
elif [ "$SCORE_B" -gt "$SCORE_A" ]; then
  WINNER="Site B leads by $((SCORE_B - SCORE_A)) points"
else
  WINNER="Both sites tied at ${SCORE_A}/100"
fi

# Count category wins
WINS_A=$(jq --slurpfile b "$REPORT_B" '
  [.categories | to_entries[] | select(.value.score > ($b[0].categories[.key].score))] | length
' "$REPORT_A")
WINS_B=$(jq --slurpfile b "$REPORT_B" '
  [.categories | to_entries[] | select(.value.score < ($b[0].categories[.key].score))] | length
' "$REPORT_A")

HTML=$(cat <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>crawl-sim Comparison</title>
<style>
  @page { size: A4 landscape; margin: 15mm; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: #1a1a1a; line-height: 1.5; padding: 40px; max-width: 1100px; margin: 0 auto; }
  h1 { font-size: 24px; margin-bottom: 4px; }
  .subtitle { color: #666; font-size: 13px; margin-bottom: 24px; }
  .vs-hero { display: grid; grid-template-columns: 1fr auto 1fr; gap: 20px; align-items: center; margin-bottom: 32px; }
  .site-card { background: #f8f9fa; border-radius: 12px; padding: 24px; text-align: center; }
  .site-card.winner { background: #e8f5e9; border: 2px solid #27ae60; }
  .site-score { font-size: 56px; font-weight: 800; line-height: 1; }
  .site-grade { font-size: 36px; font-weight: 700; color: #2d7d46; }
  .site-url { font-size: 12px; color: #666; word-break: break-all; margin-top: 8px; }
  .vs { font-size: 32px; font-weight: 800; color: #999; }
  .verdict { text-align: center; font-size: 16px; font-weight: 600; margin-bottom: 24px; padding: 12px; background: #f0f0f0; border-radius: 8px; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 24px; font-size: 13px; }
  th { background: #1a1a1a; color: white; padding: 8px 12px; text-align: left; }
  td { padding: 8px 12px; border-bottom: 1px solid #e0e0e0; }
  tr:nth-child(even) { background: #f8f9fa; }
  .winner-a td:nth-child(2) { color: #27ae60; font-weight: 600; }
  .winner-b td:nth-child(3) { color: #27ae60; font-weight: 600; }
  .winner-a td:last-child { color: #27ae60; }
  .winner-b td:last-child { color: #c0392b; }
  h2 { font-size: 18px; margin: 24px 0 12px; border-bottom: 2px solid #1a1a1a; padding-bottom: 4px; }
  .footer { margin-top: 40px; padding-top: 16px; border-top: 1px solid #e0e0e0; font-size: 11px; color: #999; }
  @media print { body { padding: 0; } }
</style>
</head>
<body>

<h1>crawl-sim — Comparative Audit</h1>
<div class="subtitle">Generated $(date -u +"%Y-%m-%d %H:%M UTC")</div>

<div class="vs-hero">
  <div class="site-card$([ "$SCORE_A" -ge "$SCORE_B" ] && echo ' winner' || echo '')">
    <div style="font-size:12px;font-weight:600;color:#666;margin-bottom:8px">SITE A</div>
    <div class="site-score">${SCORE_A}</div>
    <div class="site-grade">${GRADE_A}</div>
    <div class="site-url">${URL_A}</div>
  </div>
  <div class="vs">VS</div>
  <div class="site-card$([ "$SCORE_B" -gt "$SCORE_A" ] && echo ' winner' || echo '')">
    <div style="font-size:12px;font-weight:600;color:#666;margin-bottom:8px">SITE B</div>
    <div class="site-score">${SCORE_B}</div>
    <div class="site-grade">${GRADE_B}</div>
    <div class="site-url">${URL_B}</div>
  </div>
</div>

<div class="verdict">${WINNER} &middot; Site A wins ${WINS_A} categories, Site B wins ${WINS_B}</div>

<h2>Category Breakdown</h2>
<table>
<tr><th>Category</th><th>Site A</th><th>Site B</th><th>Delta</th></tr>
${CAT_COMPARE}
<tr style="font-weight:600;border-top:2px solid #1a1a1a">
  <td>Content Parity</td>
  <td>${PARITY_A}</td>
  <td>${PARITY_B}</td>
  <td>$([ "$PARITY_A" -gt "$PARITY_B" ] 2>/dev/null && echo "+$((PARITY_A - PARITY_B))" || ([ "$PARITY_B" -gt "$PARITY_A" ] 2>/dev/null && echo "-$((PARITY_B - PARITY_A))" || echo "="))</td>
</tr>
</table>

<h2>Per-Bot Scores</h2>
<table>
<tr><th>Bot</th><th>Site A</th><th>Site B</th><th>Delta</th></tr>
${BOT_COMPARE}
</table>

<div class="footer">
  Generated by crawl-sim v1.4.0 &middot; <a href="https://github.com/BraedenBDev/crawl-sim">github.com/BraedenBDev/crawl-sim</a>
</div>

</body>
</html>
HTMLEOF
)

if [ -n "$OUTPUT" ]; then
  printf '%s' "$HTML" > "$OUTPUT"
  printf '[generate-compare-html] wrote %s\n' "$OUTPUT" >&2
else
  printf '%s' "$HTML"
fi
