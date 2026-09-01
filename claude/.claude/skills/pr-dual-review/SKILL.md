---
name: pr-dual-review
description: >-
  Check out a GitHub pull request into the current worktree and run the
  dual-review skill (elixir-review + Codex) against it, then report the merged
  findings. Use this whenever the user wants to REVIEW SOMEONE ELSE'S PR from
  GitHub: "dual-review PR 7401", "review this PR <url>", "run both reviewers on
  #7380", or discovery asks like "what PRs should I review?", "any PRs from the
  team to look at?", "show me PRs I haven't reviewed yet". It accepts a PR
  number or URL directly, or lists open PRs by other people (excluding bots like
  dependabot/renovate, drafts, and PRs the user already reviewed that have no new
  activity since) for the user to pick from. This is distinct from the plain
  dual-review skill, which reviews the CURRENT branch's own uncommitted work with
  no checkout. It is also the opposite of pr-review-feedback, which reads the
  comments left on the USER'S OWN PR rather than producing a fresh review of
  someone else's. Does NOT push, comment, or approve on GitHub -- it reviews
  locally and reports.
---

# PR dual review

Review a pull request off GitHub with both reviewers at once. This skill is the
glue between `gh` and the `dual-review` skill: it works out which PR, checks its
branch out into the current worktree safely, runs the dual review against the
PR's own base branch, and reports back. The review logic itself is not
reimplemented here -- `dual-review` owns that.

Two ways in:

- **Targeted** -- the user names a PR (number or URL). Go straight to checkout.
- **Discovery** -- the user asks which PRs to review. List candidates first,
  let them pick, then checkout and review each chosen one.

## Step 1: Choose the PR(s)

**If the user gave a PR number or URL**, use it directly -- skip to Step 2.

**If the user is asking what to review**, run the bundled discovery script
(from this skill's `scripts/` directory -- use the skill base directory
announced when the skill loaded). It shells out to `gh`, so `gh` must be
installed and authenticated:

```bash
python3 <skill-dir>/scripts/list_review_candidates.py            # actionable set
python3 <skill-dir>/scripts/list_review_candidates.py --author alice
python3 <skill-dir>/scripts/list_review_candidates.py --all      # + reviewed-and-quiet
python3 <skill-dir>/scripts/list_review_candidates.py --include-drafts
```

It returns JSON: the `viewer` login, `candidates` (each with `number`, `title`,
`author`, `status`, and a `note`), and `skipped` counts. It has already applied
the filters the user asked for:

- open PRs authored by **other people** -- the viewer's own PRs are dropped;
- **bots excluded** -- dependabot, renovate, and anything GitHub flags as a Bot;
- **drafts excluded** (unless `--include-drafts`);
- **already-reviewed-and-quiet excluded** -- if the viewer has an existing review
  and nothing has happened since, it is hidden (shown only with `--all`).

The `status` on each candidate is the point of the filtering:

- `unreviewed` -- never reviewed by the user.
- `new_activity` -- the user reviewed it, but there are **new commits or new
  comments/replies since** their last review. The `note` says what is new (e.g.
  "since your review: new commits pushed; new comments from @alice"). These are
  the "you've seen it, but there's something new to be aware of" cases the user
  asked for.

Present the candidates as a short table (number, author, status, what's new,
title), `new_activity` first. Mention the skipped counts in a line so the user
knows what was filtered ("12 of your own, 4 bot PRs, 2 drafts hidden"). Then ask
which to review. Default to reviewing **one at a time** -- a dual review takes a
few minutes each; if the user wants several, confirm before looping, and do them
sequentially (each needs the branch checked out).

## Step 2: Check the PR branch out (safely)

The user wants the PR in the current worktree, which means switching branches.
Do not clobber uncommitted work:

1. **Guard the working tree.** Run `git status --porcelain`. If it is not clean,
   stop and tell the user what is uncommitted, and ask whether to stash
   (`git stash push -u`) or abort. Never silently discard or stash their work.
2. **Record where they were** so you can offer to return: capture the current
   branch with `git rev-parse --abbrev-ref HEAD` (note it may be a detached HEAD).
3. **Check out the PR** in the current directory:
   ```bash
   gh pr checkout <number>
   ```
   If this fails because the branch is already checked out in another worktree,
   say so and stop -- do not force it; the user can review it from that worktree
   instead.
4. **Get the base branch** to review against:
   ```bash
   gh pr view <number> --json number,title,url,baseRefName,headRefName,author
   ```
   `baseRefName` (usually `main`) is what the review must diff against -- not the
   branch the user happened to be on before.

## Step 3: Run the dual review against the PR's base

Invoke the **`dual-review` skill** (Skill tool) now that the PR branch is the
current branch. Tell it to review against the PR's base branch -- pass the base
so both halves diff against the right thing, e.g. review with `--base <baseRefName>`
(pass just the branch name, e.g. `main`; the Codex script resolves `origin/<name>`
itself). Then carry out `dual-review` fully: it launches Codex in the background,
runs elixir-review inline, and merges into one report.

If Step 1 flagged this PR as `new_activity`, add that context up front so the
review is framed usefully -- e.g. "you last reviewed this on <date>; there are
new commits since, so focus on what changed" -- but still run the full review.

## Step 4: Report and restore

`dual-review` produces the merged report; prepend the PR's identity so it is
clear what was reviewed:

```
## Dual review — PR #<number>: <title>  (@<author>)
<url>
<if new_activity: one line on what changed since the last review>
```

Then the standard `dual-review` output (flagged-by-both, Codex-only,
Claude-only, rejected, looks-good). Offer to apply fixes exactly as `dual-review`
does -- but the fixes go on the PR author's branch you have checked out, so make
sure the user actually wants to commit onto someone else's branch before editing.

Finally, offer to put the worktree back where it was:
`git checkout <recorded-branch>` (and `git stash pop` if you stashed in Step 2).
Leave the worktree as you found it unless the user wants to keep exploring the PR.

## Notes

- **Never write to GitHub.** No `gh pr comment`, no `gh pr review`, no approve or
  request-changes, no push. This skill reviews locally and reports; posting the
  review back is a separate, explicit request.
- **Bots are excluded by design**, because dependabot/renovate PRs are not what a
  human dual review is for. If the user explicitly wants one reviewed, take the
  number directly (Step 2) rather than going through discovery.
- **`new_activity` counts both new commits and new comments** since the user's
  last review -- new commits usually matter most (the code changed), so call them
  out. The bar for "new" is strictly after the timestamp of the user's most
  recent review on that PR.
- **Non-Elixir PRs still work.** `dual-review` handles the split: if the PR has no
  `.ex`/`.exs` changes, the merged report is just the triaged Codex review. That
  is fine -- report it as-is.
