---
name: repo-review-stats
description: Per-contributor GitHub review and PR stats for a repo over a time window. Inline review comments, distinct PRs reviewed, approvals, reviewer-to-author matrix, PRs created with merge state and line counts. Use when the user asks who is reviewing whose PRs, review counts, approval counts, PR counts per author, or contribution stats for a period.
---

# Repo review stats

Run the bundled script and present its output as readable tables.

```
~/.claude/skills/repo-review-stats/review_stats.sh [owner/repo] [since-date]
```

Defaults are supersimplesuper/code and one month ago. It needs an authed `gh` and `jq`, makes one API call per PR with activity in the window (a few hundred calls, a couple of minutes), and prints labeled TSV sections.

Definitions the output relies on, restate them when presenting:

- Inline review comments are diff-anchored comments (`pulls/comments`), not top-level PR conversation comments.
- PRs reviewed means distinct PRs where the person submitted at least one formal review (approve, comment, request changes) in the window. Self-reviews are excluded.
- Approvals count submissions, so a re-approval after new pushes counts again.
- Bot-authored PRs (login ending in `[bot]`, plus renovate/dependabot) are excluded from the "excluded" variants and the matrix. Note that this repo's dependency bot is Renovate, not dependabot.
- PRs created uses creation date, while the review metrics use activity date, so the tables cover slightly different PR sets and won't reconcile exactly.
- Line counts are raw diff additions and deletions, so lockfiles and generated files inflate them.

When presenting, lead with whatever cut the user asked for, and call out distribution artifacts (for example a reviewer whose approvals are mostly bot dependency bumps, or a large average-to-median gap meaning a few huge PRs).
