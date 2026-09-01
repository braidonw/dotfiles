---
name: pr-board
description: >-
  Survey every open PR the user has on GitHub and report where each one stands,
  reconstructing stacked-branch chains so the report says what is actually
  blocking what and in which order things can safely merge. Read-only. It never
  merges, pushes, retargets a base, comments, or approves. Use this whenever the
  user wants a status sweep across their PRs rather than a deep look at one:
  "where are my PRs at?", "summarise my open PRs", "what should I merge next?",
  "what's blocking my stack?", "give me a PR status update", "anything ready to
  merge?", "did anyone review my stuff?", "refetch that summary", "what's the
  state of play on my branches?". Reach for it too when the user mentions
  stacked PRs, a chain of branches, PRs blocked behind each other, stranded
  approvals, or worries about re-review and merging down onto unreviewed bases.
  Also covers PRs awaiting the user's own review as a secondary section,
  including ones requested of a team they belong to rather than of them by name,
  which makes it the right skill for "anything I should be reviewing?", "what's
  waiting on the team?", or "any PRs I haven't looked at yet?". This is
  a BOARD-level tool, so prefer it over the single-PR skills whenever the ask
  spans more than one PR. Distinct from pr-review-feedback, which triages the
  comments on one PR the user authored, and from pr-dual-review, which produces
  a fresh review of somebody else's PR.
---

# PR board: where every open PR stands, and what can safely merge

The job is to turn a pile of open PRs into a decision about what to do next.
Anyone can list PRs. The value is reconstructing the stacked chains, naming the
one PR at the bottom of each that holds up everything above it, and costing the
unblock precisely enough that the user can act without opening a browser.

**Read-only.** Report and recommend, never act. No merging, no pushing, no
retargeting a base, no comments, no approvals, no closing. The user decides and
executes. If the report concludes something should merge, say so and stop.

## Step 1: gather

```bash
python3 ~/.claude/skills/pr-board/scripts/fetch_pr_board.py --pretty
```

One JSON document with every open PR the user authored, the chain graph, the
trunk's merge rules, PRs awaiting their review, and local branches stacked on an
open PR that have no PR of their own. Run it from inside the repo, or pass
`--repo owner/name`. Read the `warnings` array, since it is the only signal that
part of the picture is missing.

`review_queue` covers both ways a review lands on the user. A request addressed
to them personally, and a request addressed to a team they belong to. GitHub's
`review-requested:@me` only matches the first kind, so the script separately
queries `team-review-requested:` for every team in the org the user is a member
of, discovered from `/user/teams` and echoed back in `review_teams`. Each row
carries `requested_via` (`direct`, `team:<slug>`, or both) and `my_last_review`.

Two things follow when reading it. A row that is only `team:<slug>` was never
addressed to the user by name, so it is shared team load rather than a personal
ask, and it is the kind that silently rots because everyone assumes somebody
else has it. And a non-null `my_last_review` means the user already reviewed and
the request is still open, which for a team request is normal rather than a
signal, so say "already commented, waiting on the author" instead of listing it
as untouched work. Compare `my_last_review.submitted_at` against `updated_at` to
tell a stale request from one with new commits to look at.

Override the team list with `--review-team <slug>` (repeatable) or drop the team
queries entirely with `--no-team-review-queue`. A misspelled slug matches nothing
and produces no warning, so an override that suddenly empties the section is a
typo before it is good news.

**Read `trunk_rules` before interpreting anything else.** It decides what
"blocked" and "safe" actually mean in this repo, and the answers are not
guessable:

- `required_review_thread_resolution`: when true, an approved, green,
  `CLEAN` PR still cannot merge while any thread is open, including a bot's.
  This is the usual explanation for a PR that looks ready and will not go.
- `dismiss_stale_reviews_on_push`: when false, approvals survive pushes. That
  makes "rebase this approved PR and resolve the conflict" a free action, which
  changes what you can recommend. When true, every push costs a re-review and
  the advice inverts.
- `required_approving_review_count`: how many approvals actually gate merge.
- `has_merge_queue` with `strict_required_status_checks_policy`: a PR being
  `BEHIND` is then the queue's problem, not a task for the user. Do not tell
  them to update a branch the queue will update.

## Step 2: dig into what is red, blocked, or big

The script says a check failed or a PR conflicts. On its own that just tells the
user to go and click. Four follow-ups convert a status into a decision. Do them
only where the answer changes what the user does next.

**Failing CI.** Get the actual failure out of the job log:

```bash
gh run view --job <job_id> --log-failed | grep -B14 -A4 "test\|Error\|assert" | head -40
```

The job id is the trailing number in the check's `details_url`. You want the
test name, file, line and assertion, so the report says *what* broke. Then check
the run is current by comparing the PR's `headRefOid` and last commit date
against the run. A failure from a superseded commit is noise, and reporting it
as live is worse than not looking.

**Conflicts.** "Conflicts with base" is not actionable. Measure it:

```bash
git fetch -q origin <trunk> <head_ref>
git merge-tree --write-tree --name-only origin/<trunk> origin/<head_ref>
```

The first output line is a tree hash, and the lines after it are the genuinely
conflicting files. Exit status is non-zero when conflicts exist. This touches no
working tree and checks nothing out, so it is safe to run against any PR. "This
PR conflicts" and "this PR conflicts in one test file, and the other side of the
collision is purely additive" are completely different asks, and the second one
often turns an intimidating PR into a ten-minute job.

**Changes requested.** Fetch the reviewer's words, since the reason sets the
size of the fix:

```bash
gh pr view <n> --json reviews \
  --jq '.reviews[] | select(.author.login=="<reviewer>") | .state + "\n" + .body'
```

A review body is often empty because the substance sits in an inline thread. The
script returns thread excerpts; pull the full thread when the excerpt is
ambiguous. Quote the reviewer directly when the ask is substantive. "Fix the
typo" and "de-duplicate this before applying the fix" are both
CHANGES_REQUESTED and are days apart in effort, and only their words show that.

**Size and title.** Never describe a PR from its title. Check what is really in
it:

```bash
gh pr view <n> --json files --jq '[.files[].path] | length,
  (group_by(split(".")|last) | map({ext: .[0]|split(".")|last, n: length}))'
```

A PR called "update claude.md" that turns out to be 257 files, 248 of them
Elixir, is a codebase-wide sweep, and calling it "just docs" in the report
actively misleads. Titles drift from content, especially on long-lived branches.
For a large PR, it is also worth checking how much it overlaps the user's other
open PRs, since that is the real blast radius of landing it.

## Step 3: reason about the stacks

This is where the skill earns its keep. The mechanics are simple, the
consequences are not.

**A stack merges bottom-up into the trunk, and only that way.** When the root
merges, GitHub retargets the next PR onto the trunk automatically, and so on up.

**Never merge an upper PR into its base branch.** This is the hazard the skill
exists to prevent. Merging an approved PR down into the branch below moves that
approved diff into a PR nobody has approved. The lower PR balloons and its
reviewer is now staring at hundreds of lines somebody already signed off. It
lengthens the review and wastes the approval already earned. If a chain is
stuck, the fix is never to merge downward.

**Retargeting a base does not dismiss approvals, but verify before suggesting
it.** This is the escape hatch: when a mid-stack PR is blocked or should be
abandoned, point the PR above it at the blocked PR's base and the approvals
above survive. It only works if the upper branch does not physically contain
the lower one's commits. Check before recommending it:

```bash
git merge-base --is-ancestor origin/<lower_head> origin/<upper_head> && echo "contains it"
```

If the upper branch contains the lower branch's commits, retargeting drags them
along and the suggestion is wrong. Recommending an escape hatch that cannot work
is worse than not mentioning one, so run the check and say which way it came out.

**The bottleneck is the lowest PR in the chain that is not ready.** Everything
above is blocked however healthy it looks. Approved PRs above a bottleneck are
*stranded*, and they are the most important thing on the board, because they are
review effort already spent that is earning nothing. Name them and total them
up.

**Check what got folded down into a stacked PR.** A long-lived branch often has
sibling PRs merged into it, so a PR can carry two or three PRs' worth of content
and its approval may predate most of it. Look at the merge commits. If the
folded-in PRs were independently approved before landing, say so explicitly,
because it looks like stale-approval risk and is not. If they were not, that is
a real gap.

**Pushing commits may dismiss reviews.** A `DISMISSED` state means a prior
review was invalidated, by a push or a base change. It is neither a standing
approval nor a rejection. Whether future pushes will do the same is in
`trunk_rules.dismiss_stale_reviews_on_push`.

**Bot reviews are not sign-off.** Keep cubic, coderabbit and friends out of the
approval picture. Their unresolved threads still matter, both because thread
resolution may gate merge and because they are unaddressed findings. When a bot
and a human independently reach the same conclusion, say so, since that
combination is usually right.

**Look for the fix that already exists.** Users frequently have local work that
answers a reviewer's ask. When `local_stacked_branches` shows an un-PR'd branch
whose subject matches what a reviewer requested, point it out. If a reviewer
asked for de-duplication *before* a fix and the de-duplication is sitting on top
of the fix, the stack is upside down relative to the review, and reordering
answers the review where stacking another PR on top does not.

## Step 4: write the report

Lead with what is actionable. Tables are supporting evidence, not the point.

```markdown
## What changed since last time     <- only when a prior report is in context
## Ready to merge now               <- approved, green, on the trunk. Say "none" if empty.
## Stack: <name> (N PRs)            <- one section per chain, bottom to top
## Standalone, needing review
## Awaiting my review               <- omit if empty; mark team-only rows
## Suggested order
```

Order each stack table root-first, because merge order is the thing being
communicated and the reader should be able to read straight down the column.
After the table, a short paragraph naming the bottleneck and exactly what
unblocks it.

**Match the length to the ask.** This matters more than any other formatting
rule. A broad "where is everything at" earns the full structure. A terse "what
should I merge next?" earns three or four lines and a stop. If a short question
genuinely needs supporting detail, put the answer in the first three lines and
let the rest follow for anyone who wants it. Reproducing the whole board in
answer to a one-line question is the most common failure mode here.

Beyond that:

- **Name the single cheapest unblock.** Across the board, one action usually
  frees the most work. "Resolve a one-file conflict and 1,900 lines of
  twice-approved work can merge" is the sentence the user is looking for.
- **Quantify.** Stranded approvals, days without a reviewer, conflicting file
  counts, files in the PR. Numbers are what make a recommendation arguable.
- **Flag review-capacity problems.** One reviewer carrying half the board, or
  two 100-file PRs queued for the same person, is a real finding that no
  per-PR view surfaces.
- **Call out staleness as a decision.** A two-week-old PR with conflicts and no
  review is usually a choice between rebasing and closing, not a task.
- **Note what did not move.** On a refetch, "no movement on this stack in three
  days" is information.
- Do not pad. A green approved PR gets one line. Depth is for what is stuck.

When re-run after a previous report, lead with the delta. What moved, what newly
broke, what is still sitting. That is what "refetch" is asking for.

## Notes on the GitHub API

Gotchas the script already handles, recorded so nobody re-derives them when
working outside it:

- **Mergeability is computed lazily.** A bulk `gh pr list` returns `UNKNOWN` for
  `mergeable` on some PRs. Fetching that PR individually forces the computation.
  Never report `UNKNOWN` as "fine".
- **`author` is not a field on `PullRequestReviewThread`.** Requesting it fails
  the whole GraphQL query. The author is at `comments.nodes[0].author.login`.
- **Branch protection lives at `repos/{repo}/rules/branches/{branch}`.** The
  legacy `branches/{branch}/protection` endpoint returns 404 on repos using
  rulesets, and for tokens without admin. Rulesets stack, so the same rule type
  can appear more than once and the strictest value wins.

`gh pr list` supports `reviews` and `statusCheckRollup` in bulk, so the whole
board is one call. Do not loop `gh pr view` per PR.
