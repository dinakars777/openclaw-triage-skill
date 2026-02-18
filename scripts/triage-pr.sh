#!/usr/bin/env bash
# triage-pr.sh — Fetch comprehensive PR metadata for triage
# Usage: bash triage-pr.sh <PR_NUMBER> [--repo owner/name]

set -euo pipefail

PR_NUMBER="${1:?Usage: triage-pr.sh <PR_NUMBER> [--repo owner/name]}"
shift

REPO_FLAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG="--repo $2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "=== PR #${PR_NUMBER} Triage Data ==="
echo ""

# --- Basic PR info ---
echo "--- METADATA ---"
# shellcheck disable=SC2086
gh pr view "$PR_NUMBER" $REPO_FLAG --json \
  number,title,state,author,createdAt,updatedAt,baseRefName,headRefName,\
isDraft,mergeable,mergeStateStatus,labels,reviewDecision,reviewRequests,\
additions,deletions,changedFiles,body,url,milestone,assignees \
  --jq '{
    number,
    title,
    state,
    author: .author.login,
    created: .createdAt,
    updated: .updatedAt,
    base: .baseRefName,
    head: .headRefName,
    draft: .isDraft,
    mergeable,
    mergeStatus: .mergeStateStatus,
    labels: [.labels[].name],
    reviewDecision,
    reviewers: [.reviewRequests[].login],
    additions,
    deletions,
    changedFiles,
    url,
    milestone: .milestone.title,
    assignees: [.assignees[].login],
    bodyPreview: (.body[:500])
  }'

echo ""

# --- Files changed ---
echo "--- FILES CHANGED ---"
# shellcheck disable=SC2086
gh pr diff "$PR_NUMBER" $REPO_FLAG --stat 2>/dev/null || echo "(diff stats unavailable)"

echo ""

# --- CI / Check status ---
echo "--- CI STATUS ---"
# shellcheck disable=SC2086
gh pr checks "$PR_NUMBER" $REPO_FLAG 2>/dev/null || echo "(no CI checks)"

echo ""

# --- Review threads ---
echo "--- REVIEWS ---"
# shellcheck disable=SC2086
gh pr view "$PR_NUMBER" $REPO_FLAG --json reviews --jq \
  '[.reviews[] | {author: .author.login, state, submittedAt}] | sort_by(.submittedAt) | reverse | .[:10]' \
  2>/dev/null || echo "(no reviews)"

echo ""

# --- Linked issues ---
echo "--- LINKED ISSUES ---"
# shellcheck disable=SC2086
gh pr view "$PR_NUMBER" $REPO_FLAG --json closingIssuesReferences --jq \
  '[.closingIssuesReferences[] | {number, title, url}]' \
  2>/dev/null || echo "(no linked issues)"

echo ""

# --- Age calculation ---
echo "--- AGE ---"
CREATED=$(gh pr view "$PR_NUMBER" $REPO_FLAG --json createdAt --jq '.createdAt' 2>/dev/null)
UPDATED=$(gh pr view "$PR_NUMBER" $REPO_FLAG --json updatedAt --jq '.updatedAt' 2>/dev/null)
NOW=$(date -u +%s)

if [[ -n "$CREATED" ]]; then
  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CREATED" +%s &>/dev/null; then
    # macOS
    CREATED_TS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CREATED" +%s 2>/dev/null || echo "")
    UPDATED_TS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$UPDATED" +%s 2>/dev/null || echo "")
  else
    # Linux
    CREATED_TS=$(date -d "$CREATED" +%s 2>/dev/null || echo "")
    UPDATED_TS=$(date -d "$UPDATED" +%s 2>/dev/null || echo "")
  fi

  if [[ -n "$CREATED_TS" ]]; then
    AGE_DAYS=$(( (NOW - CREATED_TS) / 86400 ))
    STALE_DAYS=$(( (NOW - UPDATED_TS) / 86400 ))
    echo "Created: ${AGE_DAYS} days ago"
    echo "Last updated: ${STALE_DAYS} days ago"
    if [[ $STALE_DAYS -gt 90 ]]; then
      echo "⚠️  STATUS: ABANDONED (>90 days inactive)"
    elif [[ $STALE_DAYS -gt 30 ]]; then
      echo "⚠️  STATUS: STALE (>30 days inactive)"
    else
      echo "✅ STATUS: ACTIVE"
    fi
  fi
fi

echo ""
echo "=== END PR #${PR_NUMBER} ==="
