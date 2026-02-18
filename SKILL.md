---
name: pr-issue-triage
description: Triage GitHub pull requests and issues — classify, prioritize, detect staleness, estimate complexity, and generate structured reports. Designed for high-volume repos with thousands of open PRs.
---

# PR & Issue Triage Skill

You are an expert code reviewer and project maintainer. Your job is to triage GitHub pull requests and issues efficiently, producing structured assessments that help maintainers prioritize their review queue.

## Prerequisites

- `gh` CLI must be authenticated (`gh auth status`)
- The current directory should be a clone of the target repository, OR the user specifies a `--repo owner/name` flag

## Commands

### 1. Triage a Single PR

When the user asks to triage a PR (e.g., "triage PR #1234"), run the following steps:

#### Step 1: Fetch PR metadata

```bash
bash scripts/triage-pr.sh <PR_NUMBER> [--repo owner/name]
```

#### Step 2: Analyze and classify

Using the fetched metadata, produce a triage report with these fields:

| Field | Description |
|---|---|
| **Type** | One of: `bug-fix`, `feature`, `refactor`, `docs`, `deps`, `ci`, `test`, `chore` |
| **Complexity** | `trivial` (1-10 lines), `small` (11-50), `medium` (51-200), `large` (201-500), `epic` (500+) |
| **Risk** | `low`, `medium`, `high`, `critical` — based on files touched, test coverage, and scope |
| **Staleness** | Days since last update. Flag as `stale` if >30 days, `abandoned` if >90 days |
| **CI Status** | `passing`, `failing`, `pending`, `none` |
| **Review Status** | `needs-review`, `changes-requested`, `approved`, `conflicting` |
| **Security** | Flag if PR touches auth, crypto, env vars, secrets, permissions, or dependency lockfiles |
| **Suggested Labels** | Based on file paths and PR title/body |
| **Suggested Reviewers** | Based on CODEOWNERS and git blame of touched files |
| **Summary** | 2-3 sentence plain-English summary of what the PR does |
| **Action** | Recommended next step: `merge`, `review`, `request-changes`, `close-stale`, `needs-rebase`, `needs-ci-fix` |

#### Step 3: Output

Format the report using the template in `templates/triage-report.md`. If reporting via a messaging platform (Slack, Telegram, etc.), use a condensed single-message format.

---

### 2. Triage a Single Issue

When the user asks to triage an issue (e.g., "triage issue #567"), run:

```bash
bash scripts/triage-issue.sh <ISSUE_NUMBER> [--repo owner/name]
```

Then produce:

| Field | Description |
|---|---|
| **Type** | `bug`, `feature-request`, `question`, `discussion`, `docs`, `enhancement` |
| **Priority** | `P0-critical`, `P1-high`, `P2-medium`, `P3-low` — based on impact keywords, reporter activity, and linked PRs |
| **Staleness** | Days since last activity |
| **Completeness** | Does the issue have reproduction steps, expected behavior, environment info? Flag as `needs-info` if missing |
| **Duplicates** | Search open issues for title/keyword similarity and flag potential duplicates |
| **Linked PRs** | List any PRs that reference this issue |
| **Suggested Labels** | Based on title, body keywords, and file paths mentioned |
| **Summary** | 2-3 sentence summary |
| **Action** | `assign`, `label`, `close-duplicate`, `request-info`, `escalate` |

---

### 3. Batch Triage

When the user asks to triage multiple PRs or issues at once (e.g., "triage all open PRs" or "triage PRs from the last week"), use batch mode:

```bash
bash scripts/batch-triage.sh [prs|issues] [--repo owner/name] [--state open] [--since 7d] [--limit 50] [--label "needs-triage"]
```

#### Batch output format

Produce a **summary table** sorted by recommended action priority:

```markdown
## Batch Triage Report — [repo] — [date]

| # | Title | Type | Complexity | Risk | Staleness | CI | Action |
|---|-------|------|-----------|------|-----------|-----|--------|
| #1234 | Fix auth bypass | bug-fix | small | critical | 2d | ✅ | merge |
| #1200 | Add dark mode | feature | large | medium | 45d | ❌ | close-stale |
| ... | ... | ... | ... | ... | ... | ... | ... |

### Statistics
- Total triaged: N
- Ready to merge: N
- Needs review: N
- Stale (>30d): N
- Abandoned (>90d): N
- CI failing: N
- Security-sensitive: N
```

Follow the summary table with individual reports for any `critical` or `high-risk` items.

---

### 4. PR Queue Dashboard

When the user asks for a "PR dashboard" or "triage overview", produce a high-level snapshot:

```bash
bash scripts/batch-triage.sh prs --repo owner/name --state open --limit 100
```

Group results into action buckets:

1. **🔴 Immediate Action** — Security-sensitive, CI failing with approved reviews, critical bugs
2. **🟡 Needs Review** — Awaiting first review, recently updated
3. **🟢 Ready to Merge** — Approved, CI passing, no conflicts
4. **⚪ Stale/Abandoned** — No activity in 30+ days, candidates for closing
5. **🔵 Dependencies** — Dependabot / Renovate / automated dependency PRs

---

## Classification Rules

### Type Detection
- **bug-fix**: Title/body contains "fix", "bug", "crash", "error", "regression"; touches test files alongside source
- **feature**: Title/body contains "add", "implement", "new", "support", "introduce"
- **refactor**: Title/body contains "refactor", "cleanup", "reorganize", "rename"; no new tests added
- **docs**: Only touches `.md`, `.txt`, `.rst`, or `docs/` paths
- **deps**: Only touches lockfiles, `package.json`, `Cargo.toml`, `go.mod`, `requirements.txt`, etc.
- **ci**: Only touches `.github/workflows/`, `Makefile`, `Dockerfile`, CI config files
- **test**: Only touches test files
- **chore**: Doesn't fit other categories

### Risk Assessment
- **critical**: Touches auth/security code, modifies CI pipelines, changes database schemas, alters encryption
- **high**: Touches core business logic, modifies public APIs, changes >200 lines across >5 files
- **medium**: Touches application logic, changes 50-200 lines, modifies 2-5 files
- **low**: Docs-only, test-only, single-file changes under 50 lines, dependency bumps (minor/patch)

### Priority Heuristics (Issues)
- **P0**: Contains "security", "vulnerability", "data loss", "production down", "crash on startup"
- **P1**: Contains "regression", "blocker", "breaking", issue reporter is a maintainer/collaborator
- **P2**: General bugs with reproduction steps, feature requests with significant engagement (>5 reactions)
- **P3**: Questions, minor enhancements, issues with no reproduction steps

---

## Tips for Efficient Bulk Triage

When triaging large backlogs (hundreds or thousands of items):

1. **Start with quick wins** — Batch-filter for `stale` + `no-ci` items to bulk-close
2. **Prioritize security** — Always surface security-sensitive PRs first
3. **Group dependency PRs** — These can often be batch-merged or batch-closed
4. **Use label filters** — Triage unlabeled items first (`--label ""`)
5. **Incremental triage** — Process in weekly batches with `--since 7d` to stay on top of new items
