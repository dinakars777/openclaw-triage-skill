# 🤖 OpenClaw PR & Issue Triage — Contribution Proposal

**From**: Dinakar
**Date**: February 17, 2026
**Re**: Joining the triage effort for OpenClaw's 3,600+ PRs

---

## Hi Peter 👋

I saw your mention about working on a way for clawdbots to triage issues and PRs to help narrow down the 3.6k+ PR backlog. I'd love to help — I've already been contributing to OpenClaw (PR [#6590](https://github.com/openclaw/openclaw/pull/6590) — security hardening of the control UI defaults) and I'm very familiar with the codebase and the skill system.

I've put together a **working triage skill** that I think could be a strong starting point or complement to whatever you're building. Here's what it does and how I'd like to contribute.

---

## What I've Built: `pr-issue-triage` Skill

A complete, ready-to-use OpenClaw skill for triaging PRs and issues at scale. It's structured to handle the volume of the OpenClaw repo specifically.

### Capabilities

| Feature | Description |
|---------|-------------|
| **Single PR Triage** | Classifies type (bug-fix, feature, refactor, etc.), estimates complexity & risk, checks CI/review status, flags security-sensitive changes, suggests reviewers |
| **Single Issue Triage** | Classifies priority (P0–P3), detects incomplete issues, finds potential duplicates, checks for linked PRs |
| **Batch Mode** | Processes up to 200 PRs/issues at once with filtering by state, recency, and labels — designed for the 3.6k+ backlog |
| **PR Dashboard** | Generates an action-prioritized overview: 🔴 Immediate, 🟡 Needs Review, 🟢 Ready to Merge, ⚪ Stale, 🔵 Deps |
| **🔍 Duplicate & Plagiarism Detection** | Compares PRs by file overlap, submission timing, authorship, title similarity, and branch names to flag copied or duplicate work |

### Architecture

```
openclaw-triage-skill/
├── SKILL.md                      # Skill definition with classification rules
├── scripts/
│   ├── triage-pr.sh              # Fetches PR metadata via gh CLI
│   ├── triage-issue.sh           # Fetches issue metadata + duplicate detection
│   ├── batch-triage.sh           # Bulk fetching with filters
│   └── detect-duplicates.sh      # 🔍 Duplicate/plagiarism detection across PRs
└── templates/
    └── triage-report.md          # Structured output template
```

All scripts use the `gh` CLI (no API tokens to manage separately), work cross-platform (macOS + Linux), and respect API rate limits with configurable batch sizes.

### Example: What a Triage Report Looks Like

```
## PR #1234 — Fix authentication bypass in OAuth flow

| Field       | Value                           |
|-------------|----------------------------------|
| Type        | 🐛 bug-fix                       |
| Complexity  | small (23 lines)                 |
| Risk        | 🔴 critical (touches auth code)  |
| CI          | ✅ passing                       |
| Review      | approved                         |
| Staleness   | 2 days                           |

Summary: Fixes a logic error in the OAuth callback handler that
could allow bypass of email verification under specific conditions.

→ Recommended action: **MERGE** (security fix, approved, CI green)
```

---

## Scaling Strategy for 3,600+ PRs

Here's my concrete plan for tackling the backlog if I join the team:

### Phase 1: Quick Wins (Week 1)
- **🔍 Flag duplicate/stolen PRs**: Run duplicate detection across the open PR queue to identify copied work — a known pain point for maintainers dealing with credit disputes and review waste
- **Close abandoned PRs**: Batch-filter for PRs with 90+ days of inactivity, no reviews, and failing CI → generate a "stale PR" report for maintainer approval before closing
- **Merge dependency bumps**: Batch-identify Dependabot/Renovate PRs with passing CI → flag for auto-merge
- **Label the unlabeled**: Run triage on all unlabeled PRs to auto-suggest labels

### Phase 2: Active Triage (Weeks 2-4)
- **Daily triage of new PRs**: Set up a recurring job that triages all PRs opened in the last 24 hours and posts summaries to the team channel
- **Priority queue**: Generate weekly "action needed" dashboards sorted by risk and impact
- **Reviewer routing**: Use git blame + CODEOWNERS to suggest the right reviewer for each PR area

### Phase 3: Automation & Integration (Month 2+)
- **GitHub Action integration**: Plug the skill into `openclaw-github-app` so every new PR gets auto-triaged on open
- **Metrics tracking**: Track triage throughput (PRs triaged/day, median time-to-first-review) to measure impact
- **Community-facing dashboard**: A public "PR status" page showing the health of the review queue

---

## What I Bring

- **Existing contributor** — Already familiar with the codebase from PR #6590 (security hardening)
- **Skill development experience** — The triage skill follows the OpenClaw SKILL.md format and is ready for ClawHub
- **Practical focus** — I've designed this specifically for OpenClaw's scale (3.6k PRs), not as a generic tool
- **Availability** — I can commit regular time to both active triage work and improving the triage tooling

---

## Next Steps

I'd love to discuss:

1. **Aligning with your existing triage work** — Happy to adapt the skill to fit whatever architecture you're building
2. **Access and permissions** — What level of repo access does the triage team need?
3. **Communication** — Which channel does the team use for triage coordination? (Slack? Telegram? Discord?)

The skill is ready to test — you can drop the `openclaw-triage-skill/` folder into your skills directory and try `triage PR #<any-number>`. Looking forward to working together on this!

— Dinakar
