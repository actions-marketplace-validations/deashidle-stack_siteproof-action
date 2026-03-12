# SiteProof Website Quality Scanner

> Scan websites for WCAG accessibility and UX quality issues in your CI/CD pipeline. Get structured fix recipes with before/after code.

[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-SiteProof-blue?logo=github)](https://github.com/marketplace/actions/siteproof-website-quality-scanner)

## Features

- **WCAG 2.1 AA/AAA** accessibility scanning
- **UX quality** scoring (forms, performance, security, mobile readiness)
- Score breakdown: overall + WCAG + UX
- Configurable pass/fail thresholds
- Auto-updating PR comments with scan results
- Fix recipes with before/after code (Pro tier)
- Zero dependencies — pure bash + curl + jq

## Quick Start

```yaml
- uses: deashidle-stack/siteproof-action@v1
  with:
    url: 'https://example.com'
    api-key: ${{ secrets.SITEPROOF_API_KEY }}
```

Get your API key at [deveras.no/siteproof](https://deveras.no/siteproof).

## Usage Examples

### Scan on every PR

```yaml
name: Website Quality
on: [pull_request]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: deashidle-stack/siteproof-action@v1
        with:
          url: 'https://your-site.com'
          api-key: ${{ secrets.SITEPROOF_API_KEY }}
          fail-on: serious
```

### Scan a Vercel preview deployment

```yaml
name: Website Quality
on: [pull_request]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy preview
        id: deploy
        uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}

      - uses: deashidle-stack/siteproof-action@v1
        with:
          url: ${{ steps.deploy.outputs.preview-url }}
          api-key: ${{ secrets.SITEPROOF_API_KEY }}
          fail-on: critical
          threshold: 70
```

### Score threshold gate

```yaml
- uses: deashidle-stack/siteproof-action@v1
  with:
    url: 'https://your-site.com'
    api-key: ${{ secrets.SITEPROOF_API_KEY }}
    fail-on: score
    threshold: 85
```

### With fix recipes (Pro tier)

```yaml
- uses: deashidle-stack/siteproof-action@v1
  with:
    url: 'https://your-site.com'
    api-key: ${{ secrets.SITEPROOF_API_KEY }}
    recipe: true
    fail-on: serious
```

### Use outputs in subsequent steps

```yaml
- uses: deashidle-stack/siteproof-action@v1
  id: quality
  with:
    url: 'https://your-site.com'
    api-key: ${{ secrets.SITEPROOF_API_KEY }}
    fail-on: none

- run: |
    echo "Overall: ${{ steps.quality.outputs.score }} (Grade ${{ steps.quality.outputs.grade }})"
    echo "WCAG: ${{ steps.quality.outputs.wcag-score }}"
    echo "UX: ${{ steps.quality.outputs.ux-score }}"
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `url` | Yes | — | URL to scan (must be publicly accessible) |
| `api-key` | Yes | — | SiteProof API key (`sp_live_xxx` or `sp_test_xxx`) |
| `fail-on` | No | `none` | When to fail: `critical`, `serious`, `any`, `score`, `none` |
| `threshold` | No | `0` | Minimum score to pass (0-100). Only used when `fail-on` is `score`. |
| `comment` | No | `true` | Post results as a PR comment |
| `recipe` | No | `false` | Include fix recipes in output (Pro tier) |
| `api-url` | No | Production URL | Override API base URL (for testing) |

## Outputs

| Output | Description |
|--------|-------------|
| `score` | Overall quality score (0-100) |
| `grade` | Letter grade (A-F) |
| `issues` | Number of accessibility issues found |
| `passed` | Whether the check passed (`true`/`false`) |
| `wcag-score` | WCAG accessibility score (0-100) |
| `ux-score` | UX quality score (0-100) |

## Fail Modes

| Mode | Behavior |
|------|----------|
| `none` | Never fails (report only) |
| `critical` | Fails if any critical issues found |
| `serious` | Fails if any critical or serious issues found |
| `any` | Fails if any issues found |
| `score` | Fails if score is below `threshold` |

## PR Comments

When `comment: true` (default), the action posts a summary comment on the PR with:

- Overall score, WCAG score, and UX score
- Issue count by severity
- Pass/fail status
- Top fix recommendations (when `recipe: true`)

The comment is updated on subsequent runs instead of creating duplicates.

## Grading Scale

| Grade | Score |
|-------|-------|
| A | 85-100 |
| B | 70-84 |
| C | 55-69 |
| D | 35-54 |
| F | 0-34 |

## Requirements

- A publicly accessible URL to scan
- A SiteProof API key ([get one free](https://deveras.no/siteproof))
- `GITHUB_TOKEN` with `pull-requests: write` permission (for PR comments)

## License

MIT

## Links

- [SiteProof Documentation](https://deveras.no/siteproof)
- [API Reference](https://siteproof-public-api.andreas-everform.workers.dev/v1/docs)
- [Deveras](https://deveras.no)
