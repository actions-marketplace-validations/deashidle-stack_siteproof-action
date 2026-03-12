#!/usr/bin/env bash
set -euo pipefail

# ── SiteProof PR Comment — GitHub Action ──
# Creates or updates a PR comment with scan results.
# Called by scan.sh with positional args.

SCORE="$1"
GRADE="$2"
ISSUE_COUNT="$3"
CRITICAL="$4"
SERIOUS="$5"
MODERATE="$6"
MINOR="$7"
PASSED="$8"
FAIL_REASON="$9"
EST_SCORE="${10}"
EST_GRADE="${11}"
RESPONSE="${SCAN_RESPONSE:-}"

MARKER="<!-- siteproof-scan -->"

# ── Determine PR number ──
PR_NUMBER=""
if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" || "${GITHUB_EVENT_NAME:-}" == "pull_request_target" ]]; then
  PR_NUMBER=$(jq -r '.pull_request.number // empty' "${GITHUB_EVENT_PATH}" 2>/dev/null || true)
fi

if [[ -z "${PR_NUMBER}" ]]; then
  echo "Not a PR context — skipping comment."
  exit 0
fi

REPO="${GITHUB_REPOSITORY}"
API="https://api.github.com"

# ── Grade emoji ──
case "${GRADE}" in
  A) EMOJI="🟢" ;;
  B) EMOJI="🟡" ;;
  C) EMOJI="🟠" ;;
  *) EMOJI="🔴" ;;
esac

# ── Build comment body ──
BODY="${MARKER}
## ${EMOJI} SiteProof Accessibility Report

| Metric | Value |
|--------|-------|
| URL | \`${INPUT_URL}\` |
| Score | **${SCORE}/100** (Grade **${GRADE}**) |
| Issues | ${ISSUE_COUNT} (${CRITICAL} critical, ${SERIOUS} serious, ${MODERATE} moderate, ${MINOR} minor) |"

if [[ "${EST_SCORE}" != "N/A" ]]; then
  BODY="${BODY}
| Est. after fix | ${EST_SCORE}/100 (Grade ${EST_GRADE}) |"
fi

BODY="${BODY}

"

if [[ "${PASSED}" == "false" ]]; then
  BODY="${BODY}> :x: **Failed:** ${FAIL_REASON}"
else
  BODY="${BODY}> :white_check_mark: **Passed**"
fi

# ── Add top issues if recipe mode ──
if [[ "${INPUT_RECIPE}" == "true" ]]; then
  STEP_COUNT=$(echo "${RESPONSE}" | jq '.data.recipe.steps | length' 2>/dev/null || echo "0")
  if (( STEP_COUNT > 0 )); then
    BODY="${BODY}

### Top Issues to Fix

| # | Severity | Rule | Title |
|---|----------|------|-------|"
    ROWS=$(echo "${RESPONSE}" | jq -r '.data.recipe.steps[:5][] | "| \(.order) | \(.severity) | `\(.rule_id)` | \(.title) |"' 2>/dev/null || true)
    BODY="${BODY}
${ROWS}"
  fi
fi

BODY="${BODY}

---
<sub>Scanned with [SiteProof](https://deveras.no/siteproof) by [Deveras](https://deveras.no)</sub>"

# ── Find existing comment ──
EXISTING_ID=""
COMMENTS_JSON=$(curl -sf \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "${API}/repos/${REPO}/issues/${PR_NUMBER}/comments?per_page=100" 2>/dev/null || echo "[]")

EXISTING_ID=$(echo "${COMMENTS_JSON}" | jq -r --arg marker "${MARKER}" \
  '[.[] | select(.body | startswith($marker))] | first | .id // empty' 2>/dev/null || true)

# ── Create or update comment ──
PAYLOAD=$(jq -n --arg body "${BODY}" '{"body": $body}')

if [[ -n "${EXISTING_ID}" ]]; then
  curl -sf \
    -X PATCH \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${API}/repos/${REPO}/issues/comments/${EXISTING_ID}" \
    -d "${PAYLOAD}" > /dev/null 2>&1 && echo "Updated existing PR comment." || echo "::warning::Failed to update PR comment"
else
  curl -sf \
    -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${API}/repos/${REPO}/issues/${PR_NUMBER}/comments" \
    -d "${PAYLOAD}" > /dev/null 2>&1 && echo "Posted new PR comment." || echo "::warning::Failed to post PR comment"
fi
