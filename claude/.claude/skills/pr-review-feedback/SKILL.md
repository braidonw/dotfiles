---
name: pr-review-feedback
description: >-
  Pull the review comments left on a GitHub PR, evaluate each one on its
  merits, and recommend concrete fixes — read-only, no code changes, no
  write-back. Use this whenever the user wants to act on feedback *someone else*
  left on their pull request: "what did the reviewer say?", "go through the PR
  comments", "what do I need to address on my PR?", "any unresolved comments?",
  "did CodeRabbit / the reviewer flag anything?", "help me respond to the
  review", "triage the review feedback". Defaults to the PR open on the current
  branch; also accepts a PR number or URL. This is the INVERSE of the
  review-producing skills (elixir-review, code-review, review-pr) where Claude
  *is* the reviewer — reach for this one instead whenever the review already
  exists on GitHub and the user is the author deciding what to do about it. Does
  NOT apply to producing a fresh review of code, nor to posting replies or
  resolving threads on GitHub (this skill never writes back).
---

# PR Review Feedback

Help the author of a pull request work through the review comments others have
left on it. The skill fetches the **unresolved** feedback from GitHub, then for
each comment forms an independent judgement — is the reviewer right, partly
right, or mistaken given how the code actually looks now? — and recommends a
concrete fix. It stops at recommendations: no edits to the working tree, no
replies or thread-resolves on GitHub.

The point of a dedicated skill (rather than "read my PR comments") is twofold.
First, *which* comments still matter is non-trivial — resolution and outdated
state live behind GitHub's GraphQL API, so a naive fetch drowns the author in
already-handled threads. Second, review comments deserve evaluation, not
stenography: a reviewer (human or bot) can be wrong, out of date, or flagging
something already fixed in a later commit. The author wants a considered
take per comment, not a list read back to them.

## Workflow

### 1. Resolve the PR

Default to the PR open on the **current branch** — that's almost always what
"my PR" means. The bundled script does this automatically when given no
argument.

Accept an explicit target when the user gives one: a PR number ("address the
comments on 1482") or a full URL. Pass it straight through to the script.

If the script reports no PR for the current branch, say so plainly and ask for
a number/URL rather than guessing — don't fall back to a different branch's PR.

### 2. Fetch the feedback

Run the bundled script — it lives in this skill's `scripts/` directory (use
the skill base directory announced when the skill loaded). It shells out to
`gh`, so it needs `gh` installed and authenticated:

```bash
python3 <skill-dir>/scripts/fetch_pr_comments.py            # current branch
python3 <skill-dir>/scripts/fetch_pr_comments.py 1482       # by number
python3 <skill-dir>/scripts/fetch_pr_comments.py <pr-url>   # by URL
```

It returns JSON with:

- `pr` — number, title, url, head/base branch, state.
- `unresolved_threads` — each with `path`, `line`, the `diff_hunk` the comment
  was anchored to, and the full `comments` chain (author, association, body).
- `review_summaries` — top-level review verdicts and bodies
  (`CHANGES_REQUESTED`, `APPROVED`, or any review with a written summary).
- `skipped` — counts of `resolved` and `outdated` threads left out.

By default it returns only unresolved, non-outdated threads — that's the
actionable set. Mention the skipped counts to the user so they know what was
filtered (e.g. "3 resolved threads omitted"). If they want everything, re-run
with `--all`.

One important exception: if the user is asking about a *specific* comment or
suggestion ("is this suggestion worth taking?", "what about the comment on
foo.ex?") and the default fetch comes back empty or doesn't include it, don't
conclude there's no feedback — the comment is probably resolved or outdated.
Re-run with `--all`, surface it, and note that it's already marked
resolved/outdated on GitHub so the author knows it may already be handled.

### 3. Read the code each comment is about

A review comment is only as good as the code it points at — and that code may
have moved or changed since the comment was written. For each thread, open the
file at `path` around `line` and read enough context (the function, its
callers) to judge the point yourself. The `diff_hunk` shows what the reviewer
*saw*; compare it to what's there *now*. If the relevant code has already
changed, that materially changes your assessment — say so.

Load the project's conventions too (`CLAUDE.md` at the repo root and the
relevant project root). A comment that contradicts a documented project rule,
or one a project rule already settles, is worth calling out — the author's
codebase conventions win over a reviewer's general preference.

### 4. Evaluate each comment

Judge every comment on its merits, regardless of who left it. A bot or a senior
reviewer can both be wrong, and "the reviewer said so" is not a reason to
recommend a change the author shouldn't make. Assign each one a verdict:

- **Agree** — the reviewer is right; the fix is worth making. Give the concrete
  change.
- **Partly** — there's a real point, but the suggested fix isn't quite right,
  or only part applies. Explain what you'd actually do.
- **Disagree** — the comment is mistaken, based on a misreading, or contrary to
  a project convention. Explain why, so the author can reply with confidence.
- **Already addressed** — the code has changed since the comment and the
  concern no longer applies. Note what changed.
- **Needs author judgement** — a real tradeoff or a question only the author can
  answer (product intent, naming preference, scope). Frame the decision rather
  than pretending there's one right answer.

Be honest and specific. The author is going to act on this and may quote you
back to the reviewer — a vague "consider refactoring" helps no one. When you
agree, the recommended fix should be concrete enough to implement directly.

### 5. Report

Lead with a short summary, then one entry per comment grouped by file. Keep it
scannable — the author wants to triage quickly.

```markdown
## Review feedback on #<number> — <title>

<one-line orientation: N unresolved comments across M files; overall review
verdict if any (e.g. "CodeRabbit requested changes"); note skipped counts.>

| # | File:line | Reviewer | Verdict | Gist |
|---|-----------|----------|---------|------|
| 1 | lib/foo.ex:42 | @alice | Agree | Missing error branch |
| 2 | lib/bar.ex:88 | coderabbitai | Disagree | Project forbids query.ex |

---

### 1. `lib/foo.ex:42` — @alice — **Agree**

> <the reviewer's comment, quoted>

<your assessment: why they're right, referencing the current code.>

**Recommended fix:** <concrete change, with a code snippet where it helps.>

---

### 2. `lib/bar.ex:88` — coderabbitai — **Disagree**

> <quoted comment>

<why it's mistaken — e.g. cites the project rule that overrides it.>

**Suggested reply:** <a sentence the author could post back, if useful.>
```

Adapt the shape to the volume — for one or two comments, skip the table. For a
review summary with no inline threads (just a `CHANGES_REQUESTED` body), address
the summary's points directly.

Finally, since the skill is read-only, you may *offer* next steps ("want me to
apply the fixes for the ones you agree with?") but don't take them as part of
this skill — that's a separate, explicit request from the author.

## Notes

- **Bots are reviewers too.** PRs here often carry automated reviews (CodeRabbit
  and similar). Treat their comments exactly like a human's: evaluate, agree or
  push back. They're frequently noisy or stylistic — don't rubber-stamp them.
- **Outdated ≠ resolved.** GitHub marks a thread *outdated* when its lines moved,
  even if the concern stands. The script skips outdated-and-unresolved by
  default; if a user says a real comment seems missing, re-run with `--all` and
  look at the outdated ones.
- **Never write back.** No `gh pr comment`, no resolving threads, no pushing
  edits. This skill reads and advises only.
