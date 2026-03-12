#!/usr/bin/env bash
set -euo pipefail

# ── SiteProof Website Quality Scanner — GitHub Action ──
# Calls the SiteProof API, parses results, posts PR comments, and gates builds.
# Returns both WCAG accessibility and UX quality scores.

API_URL="${INPUT_API_URL}"
ENDPOINT="/v1/scan"

# Use recipe endpoint if requested (Pro tier)
if [[ "${INPUT_RECIPE}" == "true" ]]; then
  ENDPOINT="/v1/recipe"
fi

echo "::group::SiteProof Scan"
echo "Scanning: ${INPUT_URL}"
echo "Endpoint: ${ENDPOINT}"

# ── Call API (mask the API key) ──
set +x
RESPONSE=$(curl -sf --max-time 120 \
  -X POST "${API_URL}${ENDPOINT}" \
  -H "x-api-key: ${INPUT_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"${INPUT_URL}\"}" 2>&1) || {
  echo "::error::SiteProof API request failed"
  echo "${RESPONSE}" | head -5
  exit 1
}

# ── Parse response ──
SUCCESS=$(echo "${RESPONSE}" | jq -r '.success // false')
if [[ "${SUCCESS}" != "true" ]]; then
  ERROR_MSG=$(echo "${RESPONSE}" | jq -r '.error.message // .error // "Unknown error"')
  echo "::error::SiteProof scan failed: ${ERROR_MSG}"
  exit 1
fi

# Extract scores and issues based on endpoint
if [[ "${INPUT_RECIPE}" == "true" ]]; then
  SCORE=$(echo "${RESPONSE}" | jq -r '.data.current_score // 0')
  ISSUE_COUNT=$(echo "${RESPONSE}" | jq -r '.data.recipe.total_issues // 0')
  EST_SCORE=$(echo "${RESPONSE}" | jq -r '.data.recipe.estimated_score_after // "N/A"')
  EST_GRADE=$(echo "${RESPONSE}" | jq -r '.data.recipe.estimated_grade_after // "N/A"')
  WCAG_SCORE="N/A"
  UX_SCORE="N/A"
else
  SCORE=$(echo "${RESPONSE}" | jq -r '.data.score.overall // 0')
  WCAG_SCORE=$(echo "${RESPONSE}" | jq -r '.data.score.wcag // "N/A"')
  UX_SCORE=$(echo "${RESPONSE}" | jq -r '.data.score.human // "N/A"')
  ISSUE_COUNT=$(echo "${RESPONSE}" | jq -r '(.data.issues // []) | length')
  EST_SCORE="N/A"
  EST_GRADE="N/A"
fi

# Calculate grade from score
if   (( SCORE >= 85 )); then GRADE="A"
elif (( SCORE >= 70 )); then GRADE="B"
elif (( SCORE >= 55 )); then GRADE="C"
elif (( SCORE >= 35 )); then GRADE="D"
else GRADE="F"
fi

echo "Score: ${SCORE}/100 (Grade ${GRADE})"
[[ "${WCAG_SCORE}" != "N/A" ]] && echo "  WCAG: ${WCAG_SCORE}/100 | UX: ${UX_SCORE}/100"
echo "Issues: ${ISSUE_COUNT}"

# ── Count issues by severity ──
if [[ "${INPUT_RECIPE}" == "true" ]]; then
  CRITICAL=$(echo "${RESPONSE}" | jq '[.data.recipe.steps[] | select(.severity == "critical")] | length')
  SERIOUS=$(echo "${RESPONSE}" | jq '[.data.recipe.steps[] | select(.severity == "serious")] | length')
  MODERATE=$(echo "${RESPONSE}" | jq '[.data.recipe.steps[] | select(.severity == "moderate")] | length')
  MINOR=$(echo "${RESPONSE}" | jq '[.data.recipe.steps[] | select(.severity == "minor")] | length')
else
  CRITICAL=$(echo "${RESPONSE}" | jq '[(.data.issues // [])[] | select(.severity == "critical")] | length')
  SERIOUS=$(echo "${RESPONSE}" | jq '[(.data.issues // [])[] | select(.severity == "serious")] | length')
  MODERATE=$(echo "${RESPONSE}" | jq '[(.data.issues // [])[] | select(.severity == "moderate")] | length')
  MINOR=$(echo "${RESPONSE}" | jq '[(.data.issues // [])[] | select(.severity == "minor")] | length')
fi

echo "  Critical: ${CRITICAL}, Serious: ${SERIOUS}, Moderate: ${MODERATE}, Minor: ${MINOR}"
echo "::endgroup::"

# ── Set outputs ──
echo "score=${SCORE}" >> "${GITHUB_OUTPUT}"
echo "grade=${GRADE}" >> "${GITHUB_OUTPUT}"
echo "issues=${ISSUE_COUNT}" >> "${GITHUB_OUTPUT}"
echo "wcag-score=${WCAG_SCORE}" >> "${GITHUB_OUTPUT}"
echo "ux-score=${UX_SCORE}" >> "${GITHUB_OUTPUT}"

# ── Determine pass/fail ──
PASSED="true"
FAIL_REASON=""

case "${INPUT_FAIL_ON}" in
  critical)
    if (( CRITICAL > 0 )); then
      PASSED="false"
      FAIL_REASON="${CRITICAL} critical issue(s) found"
    fi
    ;;
  serious)
    if (( CRITICAL > 0 || SERIOUS > 0 )); then
      PASSED="false"
      FAIL_REASON="${CRITICAL} critical + ${SERIOUS} serious issue(s) found"
    fi
    ;;
  any)
    if (( ISSUE_COUNT > 0 )); then
      PASSED="false"
      FAIL_REASON="${ISSUE_COUNT} issue(s) found"
    fi
    ;;
  score)
    if (( SCORE < INPUT_THRESHOLD )); then
      PASSED="false"
      FAIL_REASON="Score ${SCORE} is below threshold ${INPUT_THRESHOLD}"
    fi
    ;;
  none)
    PASSED="true"
    ;;
esac

echo "passed=${PASSED}" >> "${GITHUB_OUTPUT}"

# ── Write job summary ──
{
  echo "## SiteProof Website Quality Report"
  echo ""
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| URL | \`${INPUT_URL}\` |"
  echo "| Overall Score | **${SCORE}/100** (Grade **${GRADE}**) |"
  if [[ "${WCAG_SCORE}" != "N/A" ]]; then
    echo "| WCAG Accessibility | ${WCAG_SCORE}/100 |"
    echo "| UX Quality | ${UX_SCORE}/100 |"
  fi
  echo "| Issues | ${ISSUE_COUNT} (${CRITICAL} critical, ${SERIOUS} serious, ${MODERATE} moderate, ${MINOR} minor) |"
  if [[ "${EST_SCORE}" != "N/A" ]]; then
    echo "| Est. after fix | ${EST_SCORE}/100 (Grade ${EST_GRADE}) |"
  fi
  echo ""
  if [[ "${PASSED}" == "false" ]]; then
    echo "> :x: **Failed:** ${FAIL_REASON}"
  else
    echo "> :white_check_mark: **Passed**"
  fi
  echo ""

  # Show top issues (recipe steps or scan issues)
  if [[ "${INPUT_RECIPE}" == "true" ]]; then
    STEP_COUNT=$(echo "${RESPONSE}" | jq '.data.recipe.steps | length')
    if (( STEP_COUNT > 0 )); then
      echo "### Fix Recipe (top 10)"
      echo ""
      echo "| # | Severity | Rule | Title | Effort |"
      echo "|---|----------|------|-------|--------|"
      echo "${RESPONSE}" | jq -r '.data.recipe.steps[:10][] | "| \(.order) | \(.severity) | `\(.rule_id)` | \(.title) | \(.fix.effort) |"'
      echo ""
    fi
  fi

  echo ""
  echo "> Scanned with [SiteProof](https://deveras.no/siteproof) by [Deveras](https://deveras.no)"
} >> "${GITHUB_STEP_SUMMARY}"

# ── Post PR comment ──
if [[ "${INPUT_COMMENT}" == "true" ]]; then
  SCAN_RESPONSE="${RESPONSE}" bash "$(dirname "$0")/comment.sh" \
    "${SCORE}" "${GRADE}" "${ISSUE_COUNT}" \
    "${CRITICAL}" "${SERIOUS}" "${MODERATE}" "${MINOR}" \
    "${PASSED}" "${FAIL_REASON}" "${EST_SCORE}" "${EST_GRADE}" \
    "${WCAG_SCORE}" "${UX_SCORE}"
fi

# ── Exit with appropriate code ──
if [[ "${PASSED}" == "false" ]]; then
  echo "::error::${FAIL_REASON}"
  exit 1
fi

echo "Quality check passed (score: ${SCORE}, grade: ${GRADE})"
