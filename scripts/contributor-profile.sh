#!/usr/bin/env bash
# contributor-profile.sh — Show contributor insights for a PR author
# Usage: bash contributor-profile.sh <PR_NUMBER> [--repo owner/name]
#
# Helps maintainers contextualize PRs by showing:
#   - Is this a first-time contributor?
#   - How many PRs have they submitted / merged / closed?
#   - What's their merge rate?
#   - How many currently open PRs do they have?
#   - Average review turnaround time

set -euo pipefail

PR_NUMBER="${1:?Usage: contributor-profile.sh <PR_NUMBER> [--repo owner/name]}"
shift

REPO_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG="--repo $2"; shift 2 ;;
    *)      echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "=== Contributor Profile — PR #${PR_NUMBER} ==="
echo ""

# --- Step 1: Get PR author ---
# shellcheck disable=SC2086
PR_DATA=$(gh pr view "$PR_NUMBER" $REPO_FLAG --json number,title,author,createdAt \
  --jq '{number, title, author: .author.login, created: .createdAt}' 2>/dev/null)

if [[ -z "$PR_DATA" ]]; then
  echo "Error: Could not fetch PR #${PR_NUMBER}" >&2
  exit 1
fi

AUTHOR=$(echo "$PR_DATA" | jq -r '.author')
PR_TITLE=$(echo "$PR_DATA" | jq -r '.title')

echo "PR: #${PR_NUMBER} — ${PR_TITLE}"
echo "Author: @${AUTHOR}"
echo ""

# --- Step 2: Get all PRs by this author ---
echo "--- CONTRIBUTION HISTORY ---"

# Merged PRs
# shellcheck disable=SC2086
MERGED_PRS=$(gh pr list $REPO_FLAG --author "$AUTHOR" --state merged --limit 100 \
  --json number,title,createdAt,mergedAt \
  --jq 'length' 2>/dev/null) || MERGED_PRS="0"

# Closed (not merged) PRs
# shellcheck disable=SC2086
CLOSED_PRS=$(gh pr list $REPO_FLAG --author "$AUTHOR" --state closed --limit 100 \
  --json number,mergedAt \
  --jq '[.[] | select(.mergedAt == null)] | length' 2>/dev/null) || CLOSED_PRS="0"

# Open PRs
# shellcheck disable=SC2086
OPEN_PRS_DATA=$(gh pr list $REPO_FLAG --author "$AUTHOR" --state open --limit 100 \
  --json number,title,createdAt,updatedAt \
  2>/dev/null) || OPEN_PRS_DATA="[]"

OPEN_PRS=$(echo "$OPEN_PRS_DATA" | jq 'length')

TOTAL_PRS=$((MERGED_PRS + CLOSED_PRS + OPEN_PRS))

# Calculate merge rate
if [[ "$TOTAL_PRS" -gt 0 ]]; then
  MERGE_RATE=$(( (MERGED_PRS * 100) / TOTAL_PRS ))
else
  MERGE_RATE=0
fi

# Determine contributor tier
if [[ "$TOTAL_PRS" -eq 1 ]] && [[ "$MERGED_PRS" -eq 0 ]]; then
  TIER="🆕 First-time contributor"
  TIER_NOTE="Extra guidance recommended — welcome message, point to CONTRIBUTING.md"
elif [[ "$TOTAL_PRS" -le 3 ]]; then
  TIER="🌱 New contributor"
  TIER_NOTE="Still learning the codebase — may need mentoring on conventions"
elif [[ "$MERGE_RATE" -ge 80 ]] && [[ "$MERGED_PRS" -ge 10 ]]; then
  TIER="⭐ Trusted contributor"
  TIER_NOTE="High merge rate, many contributions — fast-track review recommended"
elif [[ "$MERGE_RATE" -ge 60 ]]; then
  TIER="✅ Regular contributor"
  TIER_NOTE="Solid track record — standard review process"
elif [[ "$MERGE_RATE" -lt 30 ]] && [[ "$TOTAL_PRS" -ge 5 ]]; then
  TIER="⚠️ Low merge rate"
  TIER_NOTE="Many PRs rejected/closed — review carefully for quality patterns"
else
  TIER="👤 Occasional contributor"
  TIER_NOTE="Moderate activity — standard review process"
fi

echo ""
echo "  Contributor Tier: ${TIER}"
echo "  ${TIER_NOTE}"
echo ""
echo "  Total PRs:    ${TOTAL_PRS}"
echo "  Merged:       ${MERGED_PRS} ✅"
echo "  Closed:       ${CLOSED_PRS} ❌"
echo "  Open:         ${OPEN_PRS} 🔄"
echo "  Merge Rate:   ${MERGE_RATE}%"
echo ""

# --- Step 3: Show currently open PRs ---
if [[ "$OPEN_PRS" -gt 1 ]]; then
  echo "--- OTHER OPEN PRs BY @${AUTHOR} ---"
  echo ""
  echo "$OPEN_PRS_DATA" | jq -r ".[] | select(.number != ${PR_NUMBER}) | \"  #\\(.number) — \\(.title)\"" 2>/dev/null
  echo ""

  if [[ "$OPEN_PRS" -gt 5 ]]; then
    echo "  ⚠️ Note: @${AUTHOR} has ${OPEN_PRS} open PRs — consider reviewing together"
    echo ""
  fi
fi

# --- Step 4: Show merged PR titles for context ---
if [[ "$MERGED_PRS" -gt 0 ]]; then
  echo "--- RECENT MERGED PRs (last 5) ---"
  echo ""
  # shellcheck disable=SC2086
  gh pr list $REPO_FLAG --author "$AUTHOR" --state merged --limit 5 \
    --json number,title,mergedAt \
    --jq '.[] | "  #\(.number) — \(.title) (merged \(.mergedAt | split("T")[0]))"' \
    2>/dev/null || echo "  (could not fetch)"
  echo ""
fi

# --- Step 5: Check for bot/automated PRs ---
LOWER_AUTHOR=$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')
if echo "$LOWER_AUTHOR" | grep -qE "(bot|dependabot|renovate|snyk|github-actions|codecov)"; then
  echo "--- ⚙️ AUTOMATED ACCOUNT DETECTED ---"
  echo "  @${AUTHOR} appears to be a bot/automated service."
  echo "  Apply automated PR review policies if available."
  echo ""
fi

# --- Step 6: Summary recommendation ---
echo "--- REVIEW RECOMMENDATION ---"
echo ""

if [[ "$TOTAL_PRS" -eq 1 ]] && [[ "$MERGED_PRS" -eq 0 ]]; then
  echo "  🆕 FIRST-TIME CONTRIBUTOR"
  echo "  → Leave a welcoming, constructive review"
  echo "  → Point to contribution guidelines if code style differs"
  echo "  → Be specific about what needs changing and why"
  echo "  → Consider assigning a mentor reviewer"
elif [[ "$MERGE_RATE" -ge 80 ]] && [[ "$MERGED_PRS" -ge 10 ]]; then
  echo "  ⭐ TRUSTED CONTRIBUTOR — Fast-track"
  echo "  → High historical merge rate (${MERGE_RATE}%)"
  echo "  → ${MERGED_PRS} previous PRs successfully merged"
  echo "  → Can likely be reviewed with lighter scrutiny"
elif [[ "$MERGE_RATE" -lt 30 ]] && [[ "$TOTAL_PRS" -ge 5 ]]; then
  echo "  ⚠️ LOW MERGE RATE — Extra scrutiny"
  echo "  → Only ${MERGE_RATE}% of PRs have been merged"
  echo "  → Check for recurring quality issues"
  echo "  → May need guidance on project conventions"
else
  echo "  👤 STANDARD REVIEW"
  echo "  → Apply normal review process"
  echo "  → Merge rate: ${MERGE_RATE}% across ${TOTAL_PRS} PRs"
fi

echo ""
echo "=== END Contributor Profile ==="
