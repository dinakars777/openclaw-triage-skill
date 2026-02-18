#!/usr/bin/env bash
# ci-blockers.sh — Find CI failures blocking multiple PRs and prioritize fixes
# Usage: bash ci-blockers.sh [--repo owner/name] [--limit 50]
#
# Groups open PRs by CI failure pattern and ranks by "blast radius" —
# how many PRs each fix would unblock. Shows which PRs fix CI issues
# and recommends priority merges.

set -euo pipefail

REPO_FLAG=""
LIMIT=50

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)  REPO_FLAG="--repo $2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    *)       echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "=== CI Blocker Analysis ==="
echo ""

# --- Step 1: Fetch open PRs with CI status ---
echo "--- FETCHING PRs WITH CI STATUS ---"
echo "Scanning up to ${LIMIT} open PRs..."
echo ""

# shellcheck disable=SC2086
PRS=$(gh pr list $REPO_FLAG --state open --limit "$LIMIT" \
  --json number,title,author,headRefName,labels,createdAt,updatedAt \
  --jq '.[] | {number, title, author: .author.login, branch: .headRefName, labels: [.labels[].name], created: .createdAt, updated: .updatedAt}' \
  2>/dev/null)

if [[ -z "$PRS" ]]; then
  echo "No open PRs found."
  exit 0
fi

# Temp files for tracking
FAILING_FILE=$(mktemp)
FIXING_FILE=$(mktemp)
FAILURE_GROUPS=$(mktemp)
trap 'rm -f "$FAILING_FILE" "$FIXING_FILE" "$FAILURE_GROUPS"' EXIT

TOTAL=0
FAILING=0
PASSING=0

echo "$PRS" | jq -c '.' | while IFS= read -r pr_json; do
  PR_NUM=$(echo "$pr_json" | jq -r '.number')
  PR_TITLE=$(echo "$pr_json" | jq -r '.title')
  PR_AUTHOR=$(echo "$pr_json" | jq -r '.author')
  PR_BRANCH=$(echo "$pr_json" | jq -r '.branch')

  TOTAL=$((TOTAL + 1))

  # Get CI check status for this PR
  # shellcheck disable=SC2086
  CHECKS=$(gh pr checks "$PR_NUM" $REPO_FLAG 2>/dev/null) || CHECKS=""

  if [[ -z "$CHECKS" ]]; then
    continue
  fi

  # Extract failing checks
  FAILED_CHECKS=$(echo "$CHECKS" | grep -E "^(X|✗|-)\s" 2>/dev/null || true)

  if [[ -n "$FAILED_CHECKS" ]]; then
    FAILING=$((FAILING + 1))

    # Extract check names that failed
    while IFS= read -r check_line; do
      # Extract the check name (first column after the status symbol)
      CHECK_NAME=$(echo "$check_line" | sed 's/^[^[:alpha:]]*//' | awk '{print $1}' | head -1)
      # Also get the full check name for grouping
      FULL_CHECK=$(echo "$check_line" | sed 's/^[^[:alpha:]]*//' | cut -d$'\t' -f1 | xargs 2>/dev/null || echo "$CHECK_NAME")

      if [[ -n "$FULL_CHECK" ]]; then
        echo "${FULL_CHECK}|${PR_NUM}|${PR_TITLE}|${PR_AUTHOR}" >> "$FAILING_FILE"
      fi
    done <<< "$FAILED_CHECKS"

    # Check if this PR title/branch suggests it's a CI fix
    LOWER_TITLE=$(echo "$PR_TITLE" | tr '[:upper:]' '[:lower:]')
    LOWER_BRANCH=$(echo "$PR_BRANCH" | tr '[:upper:]' '[:lower:]')

    if echo "$LOWER_TITLE $LOWER_BRANCH" | grep -qE "(ci|workflow|github.action|pipeline|build|lint|format|test.fix|fix.test|fix.ci|fix.build|fix.lint|satisfy.lint)"; then
      echo "${PR_NUM}|${PR_TITLE}|${PR_AUTHOR}|${PR_BRANCH}" >> "$FIXING_FILE"
    fi
  fi
done

echo ""

# --- Step 2: Group failures by check name ---
echo "--- CI FAILURE GROUPS ---"
echo "(Grouped by failing check — higher count = more PRs blocked)"
echo ""

if [[ ! -s "$FAILING_FILE" ]]; then
  echo "✅ No CI failures found across scanned PRs!"
  echo ""
  echo "=== END CI Blocker Analysis ==="
  exit 0
fi

# Count unique check failures and sort by frequency
cut -d'|' -f1 "$FAILING_FILE" | sort | uniq -c | sort -rn > "$FAILURE_GROUPS"

while IFS= read -r group_line; do
  COUNT=$(echo "$group_line" | awk '{print $1}')
  CHECK=$(echo "$group_line" | sed 's/^[[:space:]]*[0-9]* //')

  # Determine priority based on blast radius
  if [[ "$COUNT" -ge 10 ]]; then
    PRIORITY="🔴 CRITICAL"
    LABEL="Fixing this unblocks ${COUNT} PRs"
  elif [[ "$COUNT" -ge 5 ]]; then
    PRIORITY="🟡 HIGH"
    LABEL="Fixing this unblocks ${COUNT} PRs"
  elif [[ "$COUNT" -ge 2 ]]; then
    PRIORITY="🟢 MEDIUM"
    LABEL="Affects ${COUNT} PRs"
  else
    PRIORITY="⚪ LOW"
    LABEL="Affects 1 PR"
  fi

  echo "┌─────────────────────────────────────────"
  echo "│ ${PRIORITY} — ${CHECK}"
  echo "│ ${LABEL}"
  echo "│"

  # List affected PRs
  grep "^${CHECK}|" "$FAILING_FILE" | head -5 | while IFS='|' read -r _check pr_num pr_title pr_author; do
    echo "│   #${pr_num} — ${pr_title} (@${pr_author})"
  done

  REMAINING=$(grep -c "^${CHECK}|" "$FAILING_FILE" 2>/dev/null || echo "0")
  if [[ "$REMAINING" -gt 5 ]]; then
    echo "│   ... and $((REMAINING - 5)) more"
  fi

  echo "└─────────────────────────────────────────"
  echo ""
done < "$FAILURE_GROUPS"

# --- Step 3: Find PRs that fix CI issues ---
echo "--- CI FIX PRs (HIGH PRIORITY CANDIDATES) ---"

if [[ -s "$FIXING_FILE" ]]; then
  echo "These PRs appear to fix CI/build/lint issues — merging them may unblock others:"
  echo ""

  while IFS='|' read -r pr_num pr_title pr_author pr_branch; do
    # Count how many failing PRs share the same failure category
    # Try to match the fix PR to a failure group
    LOWER_TITLE=$(echo "$pr_title" | tr '[:upper:]' '[:lower:]')

    REASON=""
    if echo "$LOWER_TITLE" | grep -qE "(lint|format)"; then
      MATCH_COUNT=$(grep -ciE "lint|format|check" "$FAILURE_GROUPS" 2>/dev/null || echo "0")
      REASON="May fix lint/format failures"
    elif echo "$LOWER_TITLE" | grep -qE "(test|spec)"; then
      MATCH_COUNT=$(grep -ciE "test|check|spec" "$FAILURE_GROUPS" 2>/dev/null || echo "0")
      REASON="May fix test failures"
    elif echo "$LOWER_TITLE" | grep -qE "(ci|workflow|pipeline|action)"; then
      MATCH_COUNT=$(grep -ciE "ci|build|workflow" "$FAILURE_GROUPS" 2>/dev/null || echo "0")
      REASON="May fix CI pipeline issues"
    elif echo "$LOWER_TITLE" | grep -qE "(build|compile)"; then
      MATCH_COUNT=$(grep -ciE "build|compile" "$FAILURE_GROUPS" 2>/dev/null || echo "0")
      REASON="May fix build failures"
    else
      MATCH_COUNT="?"
      REASON="CI-related fix"
    fi

    echo "  ⭐ PR #${pr_num} — ${pr_title}"
    echo "     Author: @${pr_author} | Branch: ${pr_branch}"
    echo "     📌 ${REASON}"
    echo "     💡 Prioritize this PR — if merged, it may unblock multiple other PRs"
    echo ""
  done < "$FIXING_FILE"
else
  echo "No PRs found that specifically fix CI issues."
  echo "Consider creating a dedicated CI fix PR to unblock the queue."
fi

echo ""

# --- Step 4: Overall summary ---
echo "--- SUMMARY ---"
TOTAL_GROUPS=$(wc -l < "$FAILURE_GROUPS" | xargs)
TOTAL_FAILING=$(cut -d'|' -f2 "$FAILING_FILE" | sort -u | wc -l | xargs)
TOTAL_FIXING=$(wc -l < "$FIXING_FILE" 2>/dev/null | xargs || echo "0")
CRITICAL_GROUPS=$(awk '$1 >= 10' "$FAILURE_GROUPS" | wc -l | xargs)

echo "PRs scanned: ${LIMIT}"
echo "PRs with CI failures: ${TOTAL_FAILING}"
echo "Unique failure types: ${TOTAL_GROUPS}"
echo "Critical blockers (10+ PRs): ${CRITICAL_GROUPS}"
echo "CI-fix PRs found: ${TOTAL_FIXING}"
echo ""

if [[ "$CRITICAL_GROUPS" -gt 0 ]]; then
  echo "⚠️  RECOMMENDATION: Focus on critical CI blockers first."
  echo "   Each fix unblocks 10+ PRs — highest leverage work available."
fi

echo ""
echo "=== END CI Blocker Analysis ==="
