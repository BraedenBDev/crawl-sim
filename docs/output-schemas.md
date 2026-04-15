# Output Schemas

Every crawl-sim script writes JSON to stdout. This document specifies the exact shape of each script's output. Schema changes are treated as breaking changes and require a version bump.

---

## fetch-as-bot.sh

### Success

```jsonc
{
  "url": "string — requested URL",
  "bot": {
    "id": "string — profile ID (e.g., 'googlebot')",
    "name": "string — display name",
    "userAgent": "string — full UA string",
    "rendersJavaScript": "boolean"
  },
  "status": "number — HTTP status code",
  "timing": {
    "total": "number — total request time in seconds",
    "ttfb": "number — time to first byte in seconds"
  },
  "size": "number — bytes downloaded",
  "wordCount": "number — visible words in HTML (tags stripped)",
  "redirectCount": "number — number of redirect hops (0 if direct)",
  "finalUrl": "string — URL after all redirects",
  "redirectChain": "array — [{hop: number, status: number, location: string}]",
  "headers": "object — response headers as key-value pairs",
  "bodyFile": "string — relative file name when --out-dir is supplied, otherwise an absolute temp path",
  "bodyBytes": "number — bytes written to bodyFile"
}
```

### Failure (fetchFailed)

```jsonc
{
  "url": "string",
  "bot": { /* same shape as success */ },
  "fetchFailed": true,
  "error": "string — curl error message",
  "curlExitCode": "number — curl exit code",
  "status": 0,
  "timing": { "total": 0, "ttfb": 0 },
  "size": 0,
  "wordCount": 0,
  "headers": {},
  "bodyFile": "",
  "bodyBytes": 0
}
```

---

## extract-meta.sh

```jsonc
{
  "title": "string | null",
  "description": "string | null",
  "canonical": "string | null",
  "og": {
    "title": "string | null",
    "description": "string | null",
    "image": "string | null"
  },
  "headings": {
    "h1": { "count": "number", "text": "string | null" },
    "h2": { "count": "number" }
  },
  "images": {
    "total": "number",
    "withAlt": "number"
  }
}
```

---

## extract-jsonld.sh

```jsonc
{
  "blockCount": "number — total JSON-LD script blocks found",
  "validCount": "number — blocks that parse as valid JSON",
  "invalidCount": "number — blocks that fail JSON parsing",
  "types": ["string — deduplicated schema.org @type values"],
  "blocks": [
    {
      "type": "string — primary @type of this block",
      "fields": ["string — top-level semantic field names (excluding @context, @type)"]
    }
  ],
  "flags": {
    "hasOrganization": "boolean",
    "hasBreadcrumbList": "boolean",
    "hasWebSite": "boolean",
    "hasArticle": "boolean",
    "hasFAQPage": "boolean",
    "hasProduct": "boolean",
    "hasProfessionalService": "boolean"
  }
}
```

---

## extract-links.sh

```jsonc
{
  "total": "number — internal + external count",
  "internal": "number — same-host link count",
  "external": "number — different-host link count",
  "internalUrls": ["string — first 50 internal URLs"],
  "externalUrls": ["string — first 50 external URLs"]
}
```

---

## check-robots.sh

```jsonc
{
  "url": "string — target URL",
  "robotsUrl": "string — robots.txt URL",
  "exists": "boolean",
  "allowed": "boolean — whether the bot's UA token is allowed for the target path",
  "rules": [
    {
      "userAgent": "string",
      "directives": ["string — e.g., 'Disallow: /'"]
    }
  ]
}
```

---

## check-llmstxt.sh

```jsonc
{
  "url": "string — target URL",
  "exists": "boolean — true if either llms.txt or llms-full.txt exists",
  "llmsTxt": {
    "url": "string — llms.txt URL",
    "exists": "boolean",
    "lineCount": "number",
    "hasTitle": "boolean",
    "title": "string | null",
    "hasDescription": "boolean",
    "urlCount": "number — markdown links found"
  },
  "llmsFullTxt": {
    "url": "string — llms-full.txt URL",
    "exists": "boolean",
    "lineCount": "number",
    "hasTitle": "boolean",
    "hasDescription": "boolean",
    "urlCount": "number"
  }
}
```

---

## check-sitemap.sh

```jsonc
{
  "url": "string — target URL",
  "sitemapUrl": "string — sitemap.xml URL",
  "exists": "boolean",
  "isIndex": "boolean — true if sitemap index (contains <sitemapindex>)",
  "urlCount": "number — total <loc> tags",
  "childSitemapCount": "number — child sitemaps (index only)",
  "containsTarget": "boolean — whether target URL appears in sitemap",
  "hasLastmod": "boolean",
  "sampleUrls": ["string — first 10 <loc> URLs"]
}
```

---

## diff-render.sh

### Success

```jsonc
{
  "skipped": false,
  "serverWordCount": "number",
  "renderedWordCount": "number",
  "deltaPct": "number — percentage difference",
  "deltaWords": "number — absolute word difference"
}
```

### Skipped

```jsonc
{
  "skipped": true,
  "reason": "string — e.g., 'playwright_not_installed', 'failed to fetch server HTML'"
}
```

---

## compute-score.sh

```jsonc
{
  "url": "string",
  "timestamp": "string — ISO 8601 UTC",
  "version": "string",
  "pageType": "string — root|detail|archive|faq|about|contact|generic",
  "pageTypeOverridden": "boolean",
  "overall": { "score": "number 0-100", "grade": "string" },
  "parity": {
    "score": "number 0-100",
    "grade": "string",
    "minWords": "number",
    "maxWords": "number",
    "maxDeltaPct": "number",
    "interpretation": "string"
  },
  "warnings": [
    {
      "code": "string — e.g., 'diff_render_unavailable'",
      "severity": "string — high|medium|low",
      "message": "string",
      "reason": "string"
    }
  ],
  "bots": {
    "<bot_id>": {
      "id": "string",
      "name": "string",
      "rendersJavaScript": "boolean",
      "score": "number 0-100",
      "grade": "string",
      "visibility": {
        "serverWords": "number",
        "effectiveWords": "number",
        "missedWordsVsRendered": "number",
        "hydrationPenaltyPts": "number"
      },
      "categories": {
        "accessibility": { "score": "number", "grade": "string" },
        "contentVisibility": { "score": "number", "grade": "string" },
        "structuredData": {
          "score": "number",
          "grade": "string",
          "pageType": "string",
          "expected": ["string"],
          "optional": ["string"],
          "forbidden": ["string"],
          "present": ["string"],
          "missing": ["string"],
          "extras": ["string"],
          "violations": [
            {
              "kind": "string — forbidden_schema|invalid_jsonld|missing_required_field|fetch_failed",
              "impact": "number — negative",
              "confidence": "string — high|medium|low",
              "schema": "string? — for schema-related violations",
              "field": "string? — for missing_required_field",
              "count": "number? — for invalid_jsonld"
            }
          ],
          "calculation": "string",
          "notes": "string"
        },
        "technicalSignals": { "score": "number", "grade": "string" },
        "aiReadiness": { "score": "number", "grade": "string" }
      }
    }
  },
  "categories": {
    "accessibility": { "score": "number", "grade": "string" },
    "contentVisibility": { "score": "number", "grade": "string" },
    "structuredData": { "score": "number", "grade": "string" },
    "technicalSignals": { "score": "number", "grade": "string" },
    "aiReadiness": { "score": "number", "grade": "string" }
  }
}
```

---

## build-report.sh

Merges `compute-score.sh` output with raw per-bot data:

```jsonc
{
  /* ...all compute-score.sh fields... */
  "raw": {
    "perBot": {
      "<bot_id>": {
        "fetch": { /* subset of fetch-as-bot.sh output (no body payload) */ },
        "meta": { /* extract-meta.sh output */ },
        "jsonld": { /* extract-jsonld.sh output (blockCount, types, blocks) */ },
        "links": { /* extract-links.sh output */ },
        "robots": { /* check-robots.sh output */ }
      }
    },
    "independent": {
      "sitemap": { /* check-sitemap.sh output */ },
      "llmstxt": { /* check-llmstxt.sh output */ },
      "diffRender": { /* diff-render.sh output */ }
    }
  }
}
```
