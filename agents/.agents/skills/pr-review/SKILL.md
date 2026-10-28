---
name: pr-review
description: >-
  Produce a fresh review of SOMEONE ELSE'S GitHub pull request: check the PR out
  (inside Herdr, into a throwaway review worktree with its own workspace and a new
  agent session; otherwise into the current worktree), run the code-review skill
  against it, and report the findings. The PR gets reviewed on all four axes at once, three Claude lenses
  (Standards, Spec, Language) plus an independent Codex review in parallel. Use
  whenever the user wants to review a PR from GitHub: "review PR 7401", "review
  this PR <url>", "run both reviewers on #7380", or discovery asks like "what PRs
  should I review?", "any PRs from the team to look at?", "show me PRs I haven't
  reviewed yet". It accepts a PR number or URL directly, or lists open PRs by
  other people (excluding bots like dependabot/renovate, drafts, and PRs the user
  already reviewed that have no new activity since) for the user to pick from.
  This is the opposite of pr-feedback, which reads the comments left on
  the USER'S OWN PR rather than producing a review of someone else's. For a
  status sweep across many PRs rather than a deep look at one, that's pr-board.
  Always ends with a severity-ranked file/line list of review comments in chat,
  marking the ones to hold the PR on, and the same comments as post-ready drafts
  in a tuicr PR session, so it also covers "give me comments I can leave on that
  PR". Does NOT push, comment, or approve on GitHub; the user submits the drafts
  from tuicr.
---

# PR review

Review a pull request off GitHub. This skill is the glue between `gh` and the
`code-review` skill: it works out which PR, checks its branch out into the
current worktree safely, runs the review against the PR's own base branch, and
reports back. The review logic itself is not reimplemented here. `code-review`
owns that, including the Codex axis and how an unavailable Codex is reported.

Two ways in:

- **Targeted**: the user names a PR (number or URL). Go straight to checkout.
- **Discovery**: the user asks which PRs to review. List candidates first, let
  them pick, then checkout and review each chosen one.

## Step 1: Choose the PR(s)

**If the user gave a PR number or URL**, use it directly. Skip to Step 2.

**If the user is asking what to review**, run the bundled discovery script
(from this skill's `scripts/` directory, using the skill base directory
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

- open PRs authored by **other people**. The viewer's own PRs are dropped.
- **bots excluded**. Dependabot, renovate, and anything GitHub flags as a Bot.
- **drafts excluded** (unless `--include-drafts`).
- **already-reviewed-and-quiet excluded**. If the viewer has an existing review
  and nothing has happened since, it is hidden (shown only with `--all`).

The `status` on each candidate is the point of the filtering:

- `unreviewed`: never reviewed by the user.
- `new_activity`: the user reviewed it, but there are **new commits or new
  comments/replies since** their last review. The `note` says what is new (e.g.
  "since your review: new commits pushed; new comments from @alice"). These are
  the "you've seen it, but there's something new to be aware of" cases.

Present the candidates as a short table (number, author, status, what's new,
title), `new_activity` first. Mention the skipped counts in a line so the user
knows what was filtered ("12 of your own, 4 bot PRs, 2 drafts hidden"). Then ask
which to review. Default to reviewing **one at a time**. A full review takes a
few minutes each; if the user wants several, confirm before looping, and do them
sequentially, since each needs the branch checked out.

## Step 2: Check the PR branch out (safely)

Read the PR's head commit first: `gh pr view <number> --json headRefOid,url`.

**Already at the head** (`git rev-parse HEAD` equals `headRefOid`): this is a review worktree, so skip to step 4 below and review in place.

**Inside Herdr** (`test "${HERDR_ENV:-}" = 1`), unless the user asked to review in the current worktree: hand the review to a throwaway worktree and a fresh session, then stop. The current checkout stays untouched.

1. From the repo, with `<main>` the parent of `git rev-parse --path-format=absolute --git-common-dir`:
   ```bash
   git fetch origin pull/<number>/head
   git worktree add --detach <main>/../<main-dirname>-review-pr-<number> <headRefOid>
   herdr worktree open --cwd <main> --path <that path> --label review-pr-<number> --no-focus
   ```
   Read the root pane id from `.result.root_pane.pane_id`.
2. Start a fresh agent of your own harness's kind there, and hand it the PR:
   ```bash
   herdr agent start pr-<number> --kind <claude|codex|pi> --pane <pane-id>
   herdr agent prompt pr-<number> "/pr-review <url>"
   ```
   Pass on any user instruction for the review (skip Codex, focus areas, the `new_activity` note) in the same prompt.
3. Start the cleanup watcher, detached so it outlives this session. Run it outside the sandbox, like every herdr call:
   ```bash
   nohup <skill-dir>/scripts/watch_pr_session.sh review <pane-id> <workspace-id> <that path> <main> <headRefOid> >/dev/null 2>&1 & disown
   ```
   `<workspace-id>` is `.result.workspace.workspace_id` from the `worktree open` result. When the review agent exits or its pane closes, the watcher stops any worktree preview and deletes its volumes, removes the worktree, then closes the workspace. It keeps everything, and raises a Herdr notification, when the worktree has uncommitted changes or its HEAD has moved off `headRefOid`.
4. Tell the user the workspace label and agent name, and that exiting the review session cleans up both, unless they leave changes or commits in the worktree.

Completion criterion: the agent shows as `working` and `pgrep -f watch_pr_session` finds the watcher. Steps 3 to 6 run in that session.

**Otherwise**, the user wants the PR in the current worktree, which means switching branches.
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
   say so and stop. Do not force it; the user can review it from that worktree
   instead.
4. **Read the PR metadata**, which supplies both the fixed point and the spec:
   ```bash
   gh pr view <number> --json number,title,url,body,baseRefName,headRefName,author
   ```
   `baseRefName` (usually `main`) is what the review must diff against, not the
   branch the user happened to be on before.

## Step 3: Run code-review against the PR's base

Invoke the `code-review` skill now that the PR branch is the
current branch, and carry it out fully. Two things it would otherwise have to
ask for, which this step supplies:

- **The fixed point is `baseRefName`.** Pass it explicitly so `code-review` skips
  its "ask the user" branch, and so every axis, Codex included, diffs the same
  range.
- **The spec comes from the PR.** Resolve it in this order, and pass whatever
  resolves as the Spec source: any issue the PR body or its commits reference
  (`#123`, `Closes #45`, a Linear key), fetched via the tracker workflow in
  `~/.agents/skills/setup-braidon-skills/locate.md`; failing that, the PR body
  itself, which is the author's own statement of intent and is a legitimate spec
  for "does the diff do what it claims". If neither resolves, say so and let
  `code-review` skip the Spec axis.

The Codex axis runs by default. If the user asked to skip it ("no codex",
"claude only"), pass that through.

If Step 1 flagged this PR as `new_activity`, add that context up front so the
review is framed usefully, e.g. "you last reviewed this on <date>; there are new
commits since, so focus on what changed", but still run the full review.

## Step 4: Report the axes

`code-review` produces the aggregated report. Prepend the PR's identity so it is
clear what was reviewed:

```
## Review of PR #<number>: <title> (@<author>)
<url>
Base: <baseRefName> | Spec: <issue ref, "PR body", or "none found">
<if new_activity: one line on what changed since the last review>
```

Then the `code-review` output as it stands: the per-axis sections, the summary,
and the corroboration list.

## Step 5: Consolidate the findings into PR comments

Step 4's report is organised for **reading**. This step produces the second artifact, organised for **posting**. It holds one deduplicated comment per issue, each anchored to a file and line, in two places. The chat list is the severity-ranked record of every comment. The tuicr PR session holds the same comments as post-ready drafts. Both artifacts ship, in this order, every time.

`code-review` keeps its axes separate and forbids merging or reranking them, and
Step 4's report stays exactly as it is. This step reads that report and builds a
different thing for a different purpose, so an issue three axes raised becomes
one comment here while still appearing three times above.

**Anchor every line number yourself.** The axis sub-agents cite lines from a
diff, and a diff's hunk numbering is not the file's. Open each file at the head
commit and confirm the line before writing the comment. A comment anchored to
the wrong line costs the author more than no comment. State the head SHA once at
the top of the list so the author knows what the numbers are relative to.

Then group by where GitHub can put them:

- **Inline comments**, for files in the diff. GitHub anchors a review comment to
  a line only in a file the PR touches.
- **Top-level comments**, for everything else: a finding about a file the PR does
  not touch (a caller it should have updated, a sibling it now duplicates), a
  missing migration or backfill, anything repo-wide. These are often the most
  important findings, so they get their own group rather than being dropped for
  want of a line to hang on.

Each chat entry is `file:line` and a severity, marked `hold` where you would hold the PR on it, then the comment body. Draft every body against `comment-style.md` in this skill's directory. The body is the text the author reads, so it carries no severity. Within each group, worst first.

Where a finding follows an existing pattern in the codebase, say so in the
comment. "This clones the module beside it" and "this author invented something
odd" call for different responses from the author, and only the first is true.

**Completion criterion**: every finding from every axis appears in the list
exactly once, or is dropped with a one-line reason. A corroborated finding
collapses into a single entry carrying the strongest evidence from each axis
that raised it.

**Publish to tuicr** once the list is complete. Run the `tuicr-notes` skill in PR mode, with `--pr <number>`. Each inline comment goes in as its body alone, and each top-level comment goes in as a review-level draft. Then tell the user to edit or delete drafts in tuicr and run `:submit` when they are ready.

Close with the caveats the user needs before posting in their own name: any axis
that did not run (a failed or skipped Codex leaves every finding as one model's
opinion), and what was read rather than executed.

## Step 6: Offer fixes, then restore

Offer to apply fixes only after presenting both artifacts, and note that the
fixes would land on the PR author's branch you have checked out. Make sure the
user actually wants to commit onto someone else's branch before editing
anything.

Finally, offer to put the worktree back where it was:
`git checkout <recorded-branch>` (and `git stash pop` if you stashed in Step 2).
Leave the worktree as you found it unless the user wants to keep exploring the PR.
The drafts live in tuicr's store rather than this checkout, and `tuicr pr <number>` reopens them from any checkout of the repo. They are tied to the PR's head commit, so tell the user to `:submit` before the author pushes again. After a push, `tuicr pr <number>` opens a new session, and drafts on changed files do not carry over.
In a review worktree there is nothing to restore. Exiting the session removes the worktree and its workspace. If you applied fixes there, tell the user the watcher will keep the worktree, so they push or discard the fixes and then run `git worktree remove <path>` from the main checkout and close the workspace.

## Notes

- **Never write to GitHub.** No `gh pr comment`, no `gh pr review`, no approve or request-changes, no push. This skill reviews locally and reports; posting the review back is a separate, explicit request. Step 5's comments are post-ready drafts on purpose, and the user submits them from tuicr in their own name. Hand over the drafts and stop there.
- **Bots are excluded by design**, because dependabot/renovate PRs are not what a
  full review is for. If the user explicitly wants one reviewed, take the number
  directly (Step 2) rather than going through discovery.
- **`new_activity` counts both new commits and new comments** since the user's
  last review. New commits usually matter most, because the code changed, so call
  them out. The bar for "new" is strictly after the timestamp of the user's most
  recent review on that PR.
- **Any language works.** `code-review` runs a Language axis only for languages
  with a `<language>-review` skill installed, and reports which languages in the
  diff had no lens. A PR in a language with no skill still gets Standards, Spec
  and Codex.
