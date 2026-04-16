#!/usr/bin/env bash
set -eu

# generate-report-html.sh — Generate a styled HTML audit report from crawl-sim-report.json
# Usage: generate-report-html.sh <report.json> [output.html]
# Output: HTML to stdout (or file if second arg given)

REPORT="${1:?Usage: generate-report-html.sh <report.json> [output.html]}"
OUTPUT="${2:-}"
REPORT_VERSION="1.5.0"

if [ ! -f "$REPORT" ]; then
  echo "Error: report not found: $REPORT" >&2
  exit 1
fi

html_escape() {
  printf '%s' "${1:-}" | jq -Rr @html
}

# Extract key data
URL=$(jq -r '.url' "$REPORT")
TIMESTAMP=$(jq -r '.timestamp' "$REPORT")
PAGE_TYPE=$(jq -r '.pageType' "$REPORT")
OVERALL_SCORE=$(jq -r '.overall.score' "$REPORT")
OVERALL_GRADE=$(jq -r '.overall.grade' "$REPORT")
PARITY_SCORE=$(jq -r '.parity.score' "$REPORT")
PARITY_GRADE=$(jq -r '.parity.grade' "$REPORT")
PARITY_INTERP=$(jq -r '.parity.interpretation' "$REPORT")
# Detect whether all bots are blocked (non-200) — changes parity interpretation
ALL_BLOCKED=$(jq -r '.raw.perBot | [.[] | .fetch.status] | all(. != 200)' "$REPORT")
if [ "$ALL_BLOCKED" = "true" ]; then
  PARITY_INTERP="All bots receive the same error response. Parity here reflects uniform blocking, not uniform visibility."
fi

PARITY_CLASS="parity"
if [ "$ALL_BLOCKED" = "true" ] || { [ "${PARITY_SCORE:-0}" -lt 50 ] 2>/dev/null; }; then
  PARITY_CLASS="$PARITY_CLASS low"
fi

URL_ESC=$(html_escape "$URL")
TIMESTAMP_ESC=$(html_escape "$TIMESTAMP")
PAGE_TYPE_ESC=$(html_escape "$PAGE_TYPE")
OVERALL_SCORE_ESC=$(html_escape "$OVERALL_SCORE")
OVERALL_GRADE_ESC=$(html_escape "$OVERALL_GRADE")
PARITY_SCORE_ESC=$(html_escape "$PARITY_SCORE")
PARITY_GRADE_ESC=$(html_escape "$PARITY_GRADE")
PARITY_INTERP_ESC=$(html_escape "$PARITY_INTERP")

# Build per-bot table rows
BOT_ROWS=$(jq -r '
  def eh: tostring | @html;
  def css_token: tostring | gsub("[^A-Za-z0-9_-]"; "_");
  .bots | to_entries[] |
  "<tr><td>\(.value.name | eh)</td><td>\(.value.score)</td><td>\(.value.grade | eh)</td>" +
  "<td>\(.value.categories.accessibility.score)</td>" +
  "<td>\(.value.categories.contentVisibility.score)</td>" +
  "<td>\(.value.categories.structuredData.score)</td>" +
  "<td>\(.value.categories.technicalSignals.score)</td>" +
  "<td>\(.value.categories.aiReadiness.score)</td>" +
  "<td>\((.value.purpose // "-") | eh)</td>" +
  "<td class=\"enforce-\((.value.robotsTxtEnforceability // "unknown") | css_token)\">\((.value.robotsTxtEnforceability // "-") | eh)</td></tr>"
' "$REPORT")

# Build category averages
CAT_ROWS=$(jq -r '
  def eh: tostring | @html;
  .categories | to_entries[] |
  "<tr><td>\(.key | eh)</td><td>\(.value.score)</td><td>\(.value.grade | eh)</td></tr>"
' "$REPORT")

# Build warnings
WARNINGS_HTML=$(jq -r '
  def eh: tostring | @html;
  if (.warnings | length) > 0 then
    (.warnings[] | "<div class=\"warning\"><strong>⚠ \(.code | eh)</strong>: \(.message | eh)</div>")
  else
    "<div class=\"ok\">No warnings.</div>"
  end
' "$REPORT")

# Build structured data details for first bot
SD_DETAILS=$(jq -r '
  def eh: tostring | @html;
  def join_html: map(tostring | @html) | join(", ");
  .bots | to_entries[0].value.categories.structuredData |
  "<p><strong>Page type:</strong> \(.pageType | eh)</p>" +
  "<p><strong>Present:</strong> \(.present | join_html)</p>" +
  "<p><strong>Missing:</strong> \(if (.missing | length) > 0 then (.missing | join_html) else "none" end)</p>" +
  "<p><strong>Violations:</strong> \(if (.violations | length) > 0 then (.violations | map((("\(.kind): \(.schema // .field // "")") | @html)) | join(", ")) else "none" end)</p>" +
  "<p><strong>Notes:</strong> \(.notes | eh)</p>"
' "$REPORT")

# Auto-generate findings from the JSON data
# Each finding has: severity (high/medium/low), title, category, observed, fix, impact
FINDINGS_JSON=$(jq '
  # Detect the "all bots blocked" state first — suppresses content-level findings
  (.raw.perBot | [.[] | .fetch.status] | all(. != 200)) as $all_blocked |
  (.raw.perBot | [.[] | .fetch.status] | map(select(. != 200)) | length) as $blocked_count |
  (.raw.perBot | [.[] | .fetch.status] | first) as $first_status |

  [
    # 0. All bots blocked (critical — supersedes other content findings)
    (if $all_blocked then
      {
        severity: "high",
        title: "Every bot is blocked from fetching this page (HTTP \($first_status))",
        category: "Accessibility",
        observed: "All \($blocked_count) bots receive a non-200 response. robots.txt allows them, but the origin server or its edge/WAF returns \($first_status). This is typically Akamai Bot Manager, Cloudflare Bot Fight Mode, or similar protection using TLS/HTTP-2 fingerprinting.",
        fix: "Work with your infrastructure team to verify each legitimate bot by IP range. Whitelist Googlebot (verified via reverse DNS), GPTBot (openai.com/gptbot.json), ClaudeBot (anthropic.com IP ranges), PerplexityBot (perplexity.ai IP ranges). Most WAFs have built-in bot verification you can enable.",
        impact: "Without this, every other recommendation below is moot. AI search engines see nothing. Your site is absent from ChatGPT, Claude, and Perplexity."
      }
    else empty end),

    # 1. Missing structured data (only if page is actually fetchable)
    (if $all_blocked then empty
    else .bots | to_entries[0].value.categories.structuredData as $sd |
      if ($sd.missing | length) > 0 then
        {
          severity: "high",
          title: "Missing required structured data (\($sd.missing | join(", ")))",
          category: "Structured Data",
          observed: "Page type detected as \($sd.pageType). Expected schemas: \($sd.expected | join(", ")). Missing: \($sd.missing | join(", ")).",
          fix: "Add the missing JSON-LD block(s) to the page head. For \($sd.missing | join(" and ")), include @context, @type, and the required fields per schema.org.",
          impact: "Structured Data score \($sd.score) -> 100."
        }
      else empty end
    end),

    # 2. No llms.txt (skip when all bots blocked — fix the block first)
    (if $all_blocked then empty
    elif .raw.independent.llmstxt.exists == false and .categories.aiReadiness.score < 80 then
      {
        severity: "high",
        title: "No llms.txt",
        category: "AI Readiness",
        observed: "No /llms.txt or /llms-full.txt found at the domain root.",
        fix: "Create /llms.txt with a site description and links to key pages (Products, About, Docs, etc.). Add /llms-full.txt with expanded content for LLM context. See llmstxt.org for spec.",
        impact: "AI Readiness score \(.categories.aiReadiness.score) -> 80+."
      }
    else empty end),

    # 3. Cross-bot content gap (when parity is low)
    (if .parity.score < 80 then
      {
        severity: "high",
        title: "Content not visible to AI crawlers",
        category: "Content Visibility",
        observed: "Max word-count delta between bots: \(.parity.maxDeltaPct)%. Some bots see significantly less content than others.",
        fix: "Identify components rendered client-side (dynamic imports with ssr:false, Suspense fallbacks, lazy-loaded sections). Move to server-rendered or implement streaming SSR so AI bots without JS execution still see the content.",
        impact: "Parity \(.parity.score) -> 95+ and per-bot scores converge."
      }
    else empty end),

    # 4. Significant hydration gap (when diff-render shows divergence)
    (.raw.independent.diffRender as $dr |
      if ($dr.skipped // true) == false and ($dr.significantDelta // false) == true and ($dr.deltaPct // 0) > 20 then
        {
          severity: "high",
          title: "JavaScript hides content from non-rendering bots",
          category: "Content Visibility",
          observed: "Server HTML: \($dr.serverWordCount) words. Playwright-rendered: \($dr.renderedWordCount) words. Delta: \($dr.deltaPct)%. AI bots (GPTBot, ClaudeBot, PerplexityBot) don\u0027t run JS and only see the server HTML.",
          fix: "Convert client-only components to server-rendered. On Next.js, move dynamic() imports to SSR. On React, ship content before Suspense fallbacks. On Vue/Nuxt, avoid <ClientOnly> for primary content.",
          impact: "Per-bot content score gap of \($dr.deltaPct)% closes."
        }
      else empty end),

    # 5. Robots.txt blocks with advisory_only enforceability — only when actually disallowed
    . as $root |
    ($root.bots | to_entries | map(
      (.value.id) as $id |
      (.value.robotsTxtEnforceability) as $enf |
      ($root.raw.perBot[$id].robots.allowed // true) as $allowed |
      select($enf == "advisory_only" and $allowed == false) | {
        severity: "medium",
        title: "\(.value.name) blocked via robots.txt (advisory only)",
        category: "Accessibility",
        observed: "\(.value.name) is disallowed in robots.txt, but this bot officially ignores robots.txt for user-initiated fetches.",
        fix: "If you actually want to block this bot, add network-level rules (Cloudflare WAF, nginx UA matching). robots.txt alone has no enforcement.",
        impact: "Signal correctness. The robots.txt rule is currently a false sense of control."
      }
    ) | .[]),

    # 6. PerplexityBot stealth risk — only trigger when robots.txt actually disallows
    (.bots.perplexitybot as $p |
      (.raw.perBot.perplexitybot.robots.allowed // true) as $perp_allowed |
      if $p and $p.robotsTxtEnforceability == "stealth_risk" and $perp_allowed == false then
        {
          severity: "medium",
          title: "PerplexityBot blocked, but stealth crawling documented",
          category: "Accessibility",
          observed: "robots.txt explicitly disallows PerplexityBot, but Cloudflare has documented Perplexity using undeclared crawlers with generic UA strings to access blocked sites.",
          fix: "For reliable blocking, combine robots.txt with Cloudflare WAF rules or IP reputation-based blocking.",
          impact: "Meaningful enforcement vs nominal enforcement."
        }
      else empty end),

    # 7. Missing image alt text
    (.raw.perBot | to_entries[0].value.meta.images as $img |
      if $img and $img.total > 0 and ($img.total - $img.withAlt) > 0 then
        {
          severity: ($img.total > 10 and ($img.total - $img.withAlt) > ($img.total / 4) | if . then "medium" else "low" end),
          title: "\($img.total - $img.withAlt) images missing alt text",
          category: "Content Visibility",
          observed: "\($img.withAlt) of \($img.total) images have alt attributes. \($img.total - $img.withAlt) missing.",
          fix: "Add descriptive alt text to remaining images. For decorative images, use alt=\"\".",
          impact: "Content visibility and accessibility. Alt text is indexed by all crawlers."
        }
      else empty end),

    # 8. Sitemap not containing target URL
    (.raw.independent.sitemap as $sm |
      if $sm.exists == true and $sm.containsTarget == false and $sm.isIndex != true then
        {
          severity: "low",
          title: "Sitemap exists but does not list this URL",
          category: "Technical Signals",
          observed: "\($sm.sitemapUrl) exists (\($sm.urlCount) URLs) but this page is not in it.",
          fix: "Add this URL to sitemap.xml or regenerate from CMS with this page included.",
          impact: "Crawl discoverability."
        }
      elif $sm.exists == true and $sm.containsTarget == false and $sm.isIndex == true then
        {
          severity: "low",
          title: "Sitemap is an index — target URL may live in a child sitemap",
          category: "Technical Signals",
          observed: "\($sm.sitemapUrl) is a sitemap index pointing to \($sm.childSitemapCount) child sitemaps. The target URL was not found in the index itself (expected — homepage is usually in a child sitemap like /sitemap_pages_1.xml).",
          fix: "Verify manually by inspecting the child sitemaps. If the URL is missing, add it via your CMS SEO settings.",
          impact: "Likely a false positive on this check. Low priority."
        }
      else empty end),

    # 9. Diff-render skipped (only when site is actually reachable)
    (if $all_blocked then empty
    else .raw.independent.diffRender as $dr |
      if ($dr.skipped // false) == true then
        {
          severity: "medium",
          title: "JS render comparison was skipped",
          category: "Tooling",
          observed: "Reason: \($dr.reason). Without this stage, per-bot content scoring cannot differentiate JS-rendering bots from non-rendering ones.",
          fix: "Install Playwright: npx playwright install chromium. Re-run the audit.",
          impact: "Enables differentiation of Googlebot (renders JS) from GPTBot/ClaudeBot/PerplexityBot (don\u0027t)."
        }
      else empty end
    end)
  ]
' "$REPORT")

# Build findings HTML (sorted by severity: high, medium, low)
FINDINGS_HTML=$(echo "$FINDINGS_JSON" | jq -r '
  def eh: tostring | @html;
  def sev_order: if . == "high" then 1 elif . == "medium" then 2 else 3 end;
  sort_by(.severity | sev_order) |
  if length == 0 then
    "<p class=\"ok\">No prioritized findings. All categories at expected thresholds.</p>"
  else
    to_entries | map(
      "<div class=\"finding severity-\(.value.severity)\">" +
      "<h3><span class=\"badge badge-\(.value.severity)\">\(.value.severity | ascii_upcase | eh)</span> \(.key + 1). \(.value.title | eh)</h3>" +
      "<p><strong>Category:</strong> \(.value.category | eh)</p>" +
      "<p><strong>Observed:</strong> \(.value.observed | eh)</p>" +
      "<p><strong>Fix:</strong> \(.value.fix | eh)</p>" +
      "<p><strong>Impact:</strong> \(.value.impact | eh)</p>" +
      "</div>"
    ) | join("")
  end
')

# Build "What's working" summary — the green stuff
WORKING_HTML=$(jq -r '
  (.raw.perBot | [.[] | .fetch.status] | all(. != 200)) as $all_blocked |
  [
    (if .categories.accessibility.score >= 95 then "Accessibility: all bots can reach the page (robots.txt allows, HTTP 200, good TTFB)." else empty end),
    (if .categories.contentVisibility.score >= 90 then "Content visibility: rich server-side HTML with proper headings and images." else empty end),
    (if .categories.structuredData.score >= 90 then "Structured data: all expected schemas present for this page type." else empty end),
    (if .categories.technicalSignals.score >= 90 then "Technical signals: title, description, canonical, OG tags all present." else empty end),
    (if .parity.score >= 95 and $all_blocked == false then "Cross-bot parity: all bots see identical content." else empty end)
  ] | if length == 0 then
        "<p>Nothing to highlight here yet. Address the findings above first.</p>"
      else
        "<ul>" + (map("<li>\(.)</li>") | join("")) + "</ul>"
      end
' "$REPORT")

# Generate HTML
HTML=$(cat <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>crawl-sim Audit — ${URL_ESC}</title>
<style>
  @page { size: A4; margin: 15mm; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: #1a1a1a; line-height: 1.4; padding: 32px; max-width: 900px; margin: 0 auto; font-size: 13px; }
  h1 { font-size: 24px; margin-bottom: 2px; }
  .subtitle { color: #666; font-size: 13px; margin-bottom: 16px; }
  .score-hero { display: flex; align-items: center; gap: 20px; background: #f8f9fa; border-radius: 10px; padding: 16px; margin-bottom: 12px; }
  .score-big { font-size: 48px; font-weight: 800; line-height: 1; }
  .grade-big { font-size: 36px; font-weight: 700; color: #2d7d46; }
  .score-meta { font-size: 13px; color: #666; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 12px; font-size: 12px; }
  th { background: #1a1a1a; color: white; padding: 6px 10px; text-align: left; font-weight: 600; }
  td { padding: 6px 10px; border-bottom: 1px solid #e0e0e0; }
  tr:nth-child(even) { background: #f8f9fa; }
  .enforce-advisory_only { color: #c0392b; font-weight: 600; }
  .enforce-stealth_risk { color: #e67e22; font-weight: 600; }
  .enforce-enforced { color: #27ae60; }
  h2 { font-size: 16px; margin: 16px 0 8px; border-bottom: 2px solid #1a1a1a; padding-bottom: 3px; }
  h3 { font-size: 13px; margin-bottom: 4px; }
  .warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 8px 12px; margin-bottom: 6px; border-radius: 4px; font-size: 12px; }
  .ok { color: #27ae60; font-size: 12px; margin-bottom: 4px; }
  .parity { display: flex; gap: 12px; align-items: center; background: #e8f5e9; border-radius: 8px; padding: 10px 14px; margin-bottom: 10px; font-size: 13px; }
  .parity.low { background: #ffebee; }
  .sd-details p { margin-bottom: 2px; }
  .finding { border-left: 3px solid #999; padding: 10px 14px; margin-bottom: 8px; background: #fafafa; border-radius: 0 6px 6px 0; break-inside: avoid; }
  .finding.severity-high { border-left-color: #dc3545; background: #fef5f5; }
  .finding.severity-medium { border-left-color: #fd7e14; background: #fff8f0; }
  .finding.severity-low { border-left-color: #6c757d; background: #f8f9fa; }
  .finding p { margin-bottom: 2px; font-size: 12px; }
  .badge { display: inline-block; padding: 1px 6px; border-radius: 3px; font-size: 10px; font-weight: 700; margin-right: 6px; vertical-align: middle; }
  .badge-high { background: #dc3545; color: white; }
  .badge-medium { background: #fd7e14; color: white; }
  .badge-low { background: #6c757d; color: white; }
  .working ul { margin-left: 18px; }
  .working li { font-size: 12px; margin-bottom: 2px; }
  .footer { margin-top: 16px; padding-top: 8px; border-top: 1px solid #e0e0e0; font-size: 11px; color: #999; }
  @media print { body { padding: 0; } .score-hero, table, .sd-section, .finding { break-inside: avoid; } .footer { break-before: avoid; } }
</style>
</head>
<body>

<h1>crawl-sim — Bot Visibility Audit</h1>
<div class="subtitle">${URL_ESC} &middot; ${TIMESTAMP_ESC} &middot; Page type: ${PAGE_TYPE_ESC}</div>

<div class="score-hero">
  <div>
    <span class="score-big">${OVERALL_SCORE_ESC}</span><span style="font-size:24px;color:#666">/100</span>
  </div>
  <div>
    <div class="grade-big">${OVERALL_GRADE_ESC}</div>
    <div class="score-meta">Overall Score</div>
  </div>
</div>

<div class="${PARITY_CLASS}">
  <div><strong>Content Parity:</strong> ${PARITY_SCORE_ESC}/100 (${PARITY_GRADE_ESC})</div>
  <div>${PARITY_INTERP_ESC}</div>
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

<h2>Prioritized Findings</h2>
${FINDINGS_HTML}

<h2>What Is Working</h2>
<div class="working">${WORKING_HTML}</div>

<div class="sd-section">
<h2>Structured Data Details</h2>
<div class="sd-details">${SD_DETAILS}</div>
<div class="footer">
  Generated by crawl-sim v${REPORT_VERSION} &middot; <a href="https://github.com/BraedenBDev/crawl-sim">github.com/BraedenBDev/crawl-sim</a>
</div>
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
