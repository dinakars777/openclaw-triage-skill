#!/usr/bin/env bash
# triage-issue.sh — Fetch comprehensive issue metadata for triage
# Usage: bash triage-issue.sh <ISSUE_NUMBER> [--repo owner/name]

set -euo pipefail

ISSUE_NUMBER="${1:?Usage: triage-issue.sh <ISSUE_NUMBER> [--repo owner/name]}"
shift

REPO_FLAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_FLAG="--repo $2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "=== Issue #${ISSUE_NUMBER} Triage Data ==="
echo ""

# --- Basic issue info ---
echo "--- METADATA ---"
# shellcheck disable=SC2086
gh issue view "$ISSUE_NUMBER" $REPO_FLAG --json \
  number,title,state,author,createdAt,updatedAt,labels,assignees,\
milestone,body,url,comments,reactionGroups \
  --jq '{
    number,
    title,
    state,
    author: .author.login,
    created: .createdAt,
    updated: .updatedAt,
    labels: [.labels[].name],
    assignees: [.assignees[].login],
    milestone: .milestone.title,
    url,
    commentCount: (.comments | length),
    reactions: [.reactionGroups[] | select(.users.totalCount > 0) | {content, count: .users.totalCount}],
    bodyPreview: (.body[:500])
  }'

echo ""

# --- Linked PRs ---
echo "--- LINKED PULL REQUESTS ---"
# shellcheck disable=SC2086
gh issue view "$ISSUE_NUMBER" $REPO_FLAG --json \
  number --jq '.number' > /dev/null 2>&1

# Search for PRs that reference this issue
# shellcheck disable=SC2086
gh pr list $REPO_FLAG --search "closes #${ISSUE_NUMBER} OR fixes #${ISSUE_NUMBER} OR resolves #${ISSUE_NUMBER}" \
  --json number,title,state,url \
  --jq '.[] | "PR #\(.number): \(.title) [\(.state)] \(.url)"' \
  2>/dev/null || echo "(no linked PRs found)"

echo ""

# --- Similar issues (potential duplicates) ---
echo "--- POTENTIAL DUPLICATES ---"
ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" $REPO_FLAG --json title --jq '.title' 2>/dev/null || echo "")
if [[ -n "$ISSUE_TITLE" ]]; then
  # Extract key words (3+ chars) from title for search
  KEYWORDS=$(echo "$ISSUE_TITLE" | tr -cs '[:alnum:]' '\n' | awk 'length >= 4' | head -5 | tr '\n' ' ')
  if [[ -n "$KEYWORDS" ]]; then
    # shellcheck disable=SC2086
    gh issue list $REPO_FLAG --search "$KEYWORDS" --state all --limit 5 \
      --json number,title,state,url \
      --jq ".[] | select(.number != ${ISSUE_NUMBER}) | \"#\\(.number): \\(.title) [\\(.state)] \\(.url)\"" \
      2>/dev/null || echo "(search unavailable)"
  fi
fi

echo ""

# --- Completeness check ---
echo "--- COMPLETENESS CHECK ---"
BODY=$(gh issue view "$ISSUE_NUMBER" $REPO_FLAG --json body --jq '.body' 2>/dev/null || echo "")

has_repro=false
has_expected=false
has_env=false
has_screenshot=false

if echo "$BODY" | grep -qiE "(steps to reproduce|reproduction|repro steps|how to reproduce)"; then
  has_repro=true
fi
if echo "$BODY" | grep -qiE "(expected behavior|expected result|should)"; then
  has_expected=true
fi
if echo "$BODY" | grep -qiE "(os|operating system|platform|version|environment|node|python|go version)"; then
  has_env=true
fi
if echo "$BODY" | grep -qiE "(screenshot|screen shot|image|\.png|\.jpg|\.gif)"; then
  has_screenshot=true
fi

echo "Reproduction steps: $(if $has_repro; then echo '✅'; else echo '❌ missing'; fi)"
echo "Expected behavior:  $(if $has_expected; then echo '✅'; else echo '❌ missing'; fi)"
echo "Environment info:   $(if $has_env; then echo '✅'; else echo '❌ missing'; fi)"
echo "Screenshots:        $(if $has_screenshot; then echo '✅'; else echo '➖ none'; fi)"

if ! $has_repro && ! $has_expected; then
  echo ""
  echo "⚠️  NEEDS-INFO: Issue is missing reproduction steps and expected behavior"
fi

echo ""

# --- Age calculation ---
echo "--- AGE ---"
CREATED=$(gh issue view "$ISSUE_NUMBER" $REPO_FLAG --json createdAt --jq '.createdAt' 2>/dev/null)
UPDATED=$(gh issue view "$ISSUE_NUMBER" $REPO_FLAG --json updatedAt --jq '.updatedAt' 2>/dev/null)
NOW=$(date -u +%s)

if [[ -n "$CREATED" ]]; then
  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CREATED" +%s &>/dev/null; then
    CREATED_TS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$CREATED" +%s 2>/dev/null || echo "")
    UPDATED_TS=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$UPDATED" +%s 2>/dev/null || echo "")
  else
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
echo "=== END Issue #${ISSUE_NUMBER} ==="
