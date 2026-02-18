#!/usr/bin/env bash
# batch-triage.sh — Batch-fetch PR or issue data for bulk triage
# Usage: bash batch-triage.sh [prs|issues] [OPTIONS]
#
# Options:
#   --repo owner/name    Target repository
#   --state open|closed|all  Filter by state (default: open)
#   --since Nd           Only items updated in the last N days
#   --limit N            Max items to fetch (default: 50, max: 200)
#   --label "name"       Filter by label (use "" for unlabeled)

set -euo pipefail

TYPE="${1:-prs}"
shift 2>/dev/null || true

REPO_FLAG=""
STATE="open"
SINCE=""
LIMIT=50
LABEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   REPO_FLAG="--repo $2"; shift 2 ;;
    --state)  STATE="$2"; shift 2 ;;
    --since)  SINCE="$2"; shift 2 ;;
    --limit)  LIMIT="$2"; shift 2 ;;
    --label)  LABEL="$2"; shift 2 ;;
    *)        echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Cap limit at 200 to avoid API rate limits
if [[ "$LIMIT" -gt 200 ]]; then
  LIMIT=200
  echo "⚠️  Capped limit at 200 to avoid API rate limits" >&2
fi

# Build search query
SEARCH=""
if [[ -n "$SINCE" ]]; then
  DAYS="${SINCE%d}"
  if date -v -1d +%Y-%m-%d &>/dev/null; then
    # macOS
    SINCE_DATE=$(date -v "-${DAYS}d" +%Y-%m-%d)
  else
    # Linux
    SINCE_DATE=$(date -d "${DAYS} days ago" +%Y-%m-%d)
  fi
  SEARCH="updated:>=${SINCE_DATE}"
fi

if [[ -n "$LABEL" ]]; then
  SEARCH="${SEARCH} label:\"${LABEL}\""
elif [[ "$LABEL" == "" ]] && [[ "${LABEL+set}" == "set" ]]; then
  SEARCH="${SEARCH} no:label"
fi

echo "=== Batch Triage: ${TYPE} (state=${STATE}, limit=${LIMIT}) ==="
echo ""

SEARCH_FLAG=""
if [[ -n "$SEARCH" ]]; then
  SEARCH_FLAG="--search ${SEARCH}"
fi

if [[ "$TYPE" == "prs" ]]; then
  echo "--- FETCHING PRs ---"
  # shellcheck disable=SC2086
  gh pr list $REPO_FLAG \
    --state "$STATE" \
    --limit "$LIMIT" \
    $SEARCH_FLAG \
    --json number,title,state,author,createdAt,updatedAt,labels,\
reviewDecision,additions,deletions,changedFiles,isDraft,\
mergeStateStatus,headRefName,url \
    --jq '
      .[] | {
        number,
        title: (.title[:80]),
        author: .author.login,
        created: .createdAt,
        updated: .updatedAt,
        labels: [.labels[].name] | join(","),
        review: .reviewDecision,
        additions,
        deletions,
        files: .changedFiles,
        draft: .isDraft,
        mergeStatus: .mergeStateStatus,
        url
      }
    ' 2>/dev/null

  echo ""
  echo "--- SUMMARY STATS ---"
  # shellcheck disable=SC2086
  TOTAL=$(gh pr list $REPO_FLAG --state "$STATE" --limit 1 --json number --jq 'length' 2>/dev/null || echo "?")
  echo "Showing: up to ${LIMIT}"
  echo "Total ${STATE} PRs: ${TOTAL} (approximate)"

elif [[ "$TYPE" == "issues" ]]; then
  echo "--- FETCHING ISSUES ---"
  # shellcheck disable=SC2086
  gh issue list $REPO_FLAG \
    --state "$STATE" \
    --limit "$LIMIT" \
    $SEARCH_FLAG \
    --json number,title,state,author,createdAt,updatedAt,labels,\
assignees,comments,reactionGroups,url \
    --jq '
      .[] | {
        number,
        title: (.title[:80]),
        author: .author.login,
        created: .createdAt,
        updated: .updatedAt,
        labels: [.labels[].name] | join(","),
        assignees: [.assignees[].login] | join(","),
        comments: (.comments | length),
        reactions: [.reactionGroups[] | select(.users.totalCount > 0) | "\(.content):\(.users.totalCount)"] | join(","),
        url
      }
    ' 2>/dev/null

  echo ""
  echo "--- SUMMARY STATS ---"
  # shellcheck disable=SC2086
  TOTAL=$(gh issue list $REPO_FLAG --state "$STATE" --limit 1 --json number --jq 'length' 2>/dev/null || echo "?")
  echo "Showing: up to ${LIMIT}"
  echo "Total ${STATE} issues: ${TOTAL} (approximate)"

else
  echo "Error: TYPE must be 'prs' or 'issues', got '${TYPE}'" >&2
  exit 1
fi

echo ""
echo "=== END Batch Triage ==="
