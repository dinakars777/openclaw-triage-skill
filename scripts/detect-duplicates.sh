#!/usr/bin/env bash
# detect-duplicates.sh — Detect duplicate/plagiarized PRs by comparing file overlap and timing
# Usage: bash detect-duplicates.sh <PR_NUMBER> [--repo owner/name] [--threshold 50]
#
# Compares the target PR against other open PRs to find:
#   1. File overlap — PRs touching the same files
#   2. Timing — Who submitted first
#   3. Authorship — Different authors with suspiciously similar changes
#   4. Copy patterns — Near-identical titles, branch names, or commit messages

set -euo pipefail

PR_NUMBER="${1:?Usage: detect-duplicates.sh <PR_NUMBER> [--repo owner/name] [--threshold 50]}"
shift

REPO_FLAG=""
REPO_ARG=""
THRESHOLD=50  # minimum % file overlap to flag

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)      REPO_FLAG="--repo $2"; REPO_ARG="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    *)           echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "=== Duplicate/Plagiarism Detection — PR #${PR_NUMBER} ==="
echo ""

# --- Step 1: Get the target PR's metadata ---
echo "--- TARGET PR ---"
# shellcheck disable=SC2086
TARGET_DATA=$(gh pr view "$PR_NUMBER" $REPO_FLAG --json \
  number,title,author,createdAt,headRefName,files \
  --jq '{
    number,
    title,
    author: .author.login,
    created: .createdAt,
    branch: .headRefName,
    files: [.files[].path]
  }' 2>/dev/null)

if [[ -z "$TARGET_DATA" ]]; then
  echo "Error: Could not fetch PR #${PR_NUMBER}" >&2
  exit 1
fi

TARGET_AUTHOR=$(echo "$TARGET_DATA" | jq -r '.author')
TARGET_TITLE=$(echo "$TARGET_DATA" | jq -r '.title')
TARGET_CREATED=$(echo "$TARGET_DATA" | jq -r '.created')
TARGET_BRANCH=$(echo "$TARGET_DATA" | jq -r '.branch')
TARGET_FILE_COUNT=$(echo "$TARGET_DATA" | jq '.files | length')

echo "$TARGET_DATA" | jq '.'
echo ""
echo "Files in PR: ${TARGET_FILE_COUNT}"
echo ""

# --- Step 2: Get the target PR's file list ---
TARGET_FILES=$(echo "$TARGET_DATA" | jq -r '.files[]')

# --- Step 3: Search for other PRs touching the same files ---
echo "--- SCANNING FOR OVERLAPPING PRs ---"
echo "Searching open PRs for file overlap (threshold: ${THRESHOLD}%)..."
echo ""

# Get open PRs (exclude the target)
# shellcheck disable=SC2086
OPEN_PRS=$(gh pr list $REPO_FLAG --state open --limit 100 \
  --json number,title,author,createdAt,headRefName \
  --jq ".[] | select(.number != ${PR_NUMBER}) | {number, title, author: .author.login, created: .createdAt, branch: .headRefName}" \
  2>/dev/null)

DUPLICATE_COUNT=0
SUSPICIOUS_COUNT=0

# Temp file for results
RESULTS_FILE=$(mktemp)
trap 'rm -f "$RESULTS_FILE"' EXIT

echo "$OPEN_PRS" | jq -c '.' | while IFS= read -r pr_json; do
  OTHER_NUM=$(echo "$pr_json" | jq -r '.number')
  OTHER_AUTHOR=$(echo "$pr_json" | jq -r '.author')
  OTHER_TITLE=$(echo "$pr_json" | jq -r '.title')
  OTHER_CREATED=$(echo "$pr_json" | jq -r '.created')
  OTHER_BRANCH=$(echo "$pr_json" | jq -r '.branch')

  # Get files for this PR
  # shellcheck disable=SC2086
  OTHER_FILES=$(gh pr view "$OTHER_NUM" $REPO_FLAG --json files \
    --jq '[.files[].path]' 2>/dev/null) || continue

  OTHER_FILE_LIST=$(echo "$OTHER_FILES" | jq -r '.[]' 2>/dev/null) || continue
  OTHER_FILE_COUNT=$(echo "$OTHER_FILES" | jq 'length' 2>/dev/null) || continue

  [[ "$OTHER_FILE_COUNT" -eq 0 ]] && continue

  # Calculate file overlap
  OVERLAP=0
  while IFS= read -r file; do
    if echo "$OTHER_FILE_LIST" | grep -qxF "$file"; then
      OVERLAP=$((OVERLAP + 1))
    fi
  done <<< "$TARGET_FILES"

  [[ "$TARGET_FILE_COUNT" -eq 0 ]] && continue
  OVERLAP_PCT=$(( (OVERLAP * 100) / TARGET_FILE_COUNT ))

  if [[ "$OVERLAP_PCT" -ge "$THRESHOLD" ]]; then
    # Determine who submitted first
    if [[ "$TARGET_CREATED" < "$OTHER_CREATED" ]]; then
      FIRST="TARGET (#${PR_NUMBER})"
      SECOND="OTHER (#${OTHER_NUM})"
      TIME_ORDER="⚠️  #${OTHER_NUM} was submitted AFTER #${PR_NUMBER}"
    else
      FIRST="OTHER (#${OTHER_NUM})"
      SECOND="TARGET (#${PR_NUMBER})"
      TIME_ORDER="ℹ️  #${OTHER_NUM} was submitted BEFORE #${PR_NUMBER}"
    fi

    # Check for suspicious patterns
    SUSPICIOUS=""
    RISK="low"

    # Different author + high overlap = suspicious
    if [[ "$OTHER_AUTHOR" != "$TARGET_AUTHOR" ]] && [[ "$OVERLAP_PCT" -ge 75 ]]; then
      SUSPICIOUS="🔴 SUSPICIOUS: Different author ($OTHER_AUTHOR) with ${OVERLAP_PCT}% file overlap"
      RISK="high"
    elif [[ "$OTHER_AUTHOR" != "$TARGET_AUTHOR" ]] && [[ "$OVERLAP_PCT" -ge 50 ]]; then
      SUSPICIOUS="🟡 NOTABLE: Different author ($OTHER_AUTHOR) with ${OVERLAP_PCT}% file overlap"
      RISK="medium"
    fi

    # Similar title check
    # Normalize titles for comparison (lowercase, remove common prefixes)
    NORM_TARGET=$(echo "$TARGET_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/^(fix|feat|chore|refactor|docs|test)[:( ]//g')
    NORM_OTHER=$(echo "$OTHER_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/^(fix|feat|chore|refactor|docs|test)[:( ]//g')
    if [[ "$NORM_TARGET" == "$NORM_OTHER" ]]; then
      SUSPICIOUS="${SUSPICIOUS}\n🔴 IDENTICAL TITLE after normalizing prefixes"
      RISK="high"
    fi

    # Similar branch name check
    # Strip common prefixes like username/, fix/, feat/
    NORM_TARGET_BRANCH=$(echo "$TARGET_BRANCH" | sed 's|^[^/]*/||')
    NORM_OTHER_BRANCH=$(echo "$OTHER_BRANCH" | sed 's|^[^/]*/||')
    if [[ "$NORM_TARGET_BRANCH" == "$NORM_OTHER_BRANCH" ]]; then
      SUSPICIOUS="${SUSPICIOUS}\n🟡 SIMILAR BRANCH NAME: $OTHER_BRANCH"
    fi

    # Output result
    {
      echo "┌──────────────────────────────────────────────"
      echo "│ 🔍 MATCH: PR #${OTHER_NUM} — ${OTHER_TITLE}"
      echo "│ Author: @${OTHER_AUTHOR} | Created: ${OTHER_CREATED}"
      echo "│ Branch: ${OTHER_BRANCH}"
      echo "│"
      echo "│ 📁 File Overlap: ${OVERLAP}/${TARGET_FILE_COUNT} files (${OVERLAP_PCT}%)"
      echo "│ ⏱️  ${TIME_ORDER}"
      if [[ -n "$SUSPICIOUS" ]]; then
        echo -e "│ ${SUSPICIOUS}"
      fi
      echo "│"
      echo "│ Risk Level: ${RISK}"
      echo "│ Same author: $([ "$OTHER_AUTHOR" = "$TARGET_AUTHOR" ] && echo 'yes (self-duplicate)' || echo 'NO — different authors')"
      echo "└──────────────────────────────────────────────"
      echo ""
    } | tee -a "$RESULTS_FILE"
  fi
done

# --- Step 4: Summary ---
echo ""
echo "--- SUMMARY ---"
MATCH_COUNT=$(grep -c "^│ 🔍 MATCH:" "$RESULTS_FILE" 2>/dev/null || echo "0")
HIGH_RISK=$(grep -c "Risk Level: high" "$RESULTS_FILE" 2>/dev/null || echo "0")
MEDIUM_RISK=$(grep -c "Risk Level: medium" "$RESULTS_FILE" 2>/dev/null || echo "0")

echo "PRs scanned: ~100 open PRs"
echo "Overlapping PRs found: ${MATCH_COUNT}"
echo "High risk (possible plagiarism): ${HIGH_RISK}"
echo "Medium risk (notable overlap): ${MEDIUM_RISK}"

if [[ "$HIGH_RISK" -gt 0 ]]; then
  echo ""
  echo "⚠️  RECOMMENDATION: Manually review high-risk matches."
  echo "   Compare diffs side-by-side with: gh pr diff <PR_NUMBER>"
  echo "   Check commit timestamps and git blame for original authorship."
fi

if [[ "$MATCH_COUNT" -eq 0 ]]; then
  echo ""
  echo "✅ No duplicate or overlapping PRs found for #${PR_NUMBER}"
fi

echo ""
echo "=== END Duplicate Detection — PR #${PR_NUMBER} ==="
