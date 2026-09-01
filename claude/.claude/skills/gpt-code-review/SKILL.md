---
name: gpt-code-review
description: "Get a second-opinion code review of the current git branch from OpenAI Codex, run through the Codex CLI, then triage its findings against the actual code. Use this whenever the user asks for a Codex review, a GPT/OpenAI review, a second opinion or external review on their branch/diff/PR, or wants another model to double-check their changes. Do NOT use it for ordinary review requests that don't mention Codex/GPT/second-opinion — the standard review skills own those."
---

# Codex review via the Codex CLI

Run OpenAI Codex as an external reviewer over the current branch, then act as
the triage layer: Codex is a strong second pair of eyes but it has no stake in
being right, so every finding gets verified against the real code before it
reaches the user.

## Step 1: Launch the review

Parse the user's request for three optional things: a base branch (default
`main`), a model override, and any focus area ("pay attention to the
migration", "mostly the auth changes"). Then run the bundled script from
anywhere inside the repo:

```bash
~/.claude/skills/gpt-code-review/scripts/codex_review.sh \
  [--base <branch>] [--model <model>] [--focus "<text>"]
```

Run it with `run_in_background: true` — a real review takes 2–10 minutes and
must not block the session. Tell the user the review is running and roughly
how long it takes. Do not poll; you'll be notified when it exits.

Notes:
- Default model is `gpt-5.6-sol`; pass `--model` to override with any model
  the user's Codex account offers.
- The script reviews everything since the merge-base with the base branch,
  including uncommitted changes, and lists untracked files for Codex to read.
- Exit code 3 means there is no diff against the base — report that instead
  of treating it as a failure.
- Codex runs in a read-only sandbox so it can explore callers and context
  but cannot modify anything; it picks up the repo's AGENTS.md automatically
  and the prompt points it at the CLAUDE.md conventions.

If the script fails (codex missing, not logged in — fix with `codex login` —
or a provider error), show the user
the actual error and stop — don't fall back to reviewing the code yourself as
a substitute, since the user specifically asked for Codex's opinion.

## Step 2: Triage the findings

The script prints the review and ends with `REVIEW_SAVED: <path>`. Read the
review, then verify each finding yourself before presenting it:

- Open the file at the cited line and read enough surrounding code to judge
  the claim. Check callers or tests when the claim depends on them.
- Classify each finding:
  - **Confirmed** — you checked and Codex is right.
  - **Plausible** — can't be fully verified from the code alone (needs a run,
    depends on prod data), but the reasoning holds.
  - **Rejected** — the code already handles it, the claim misreads the diff,
    or it contradicts a deliberate project convention. Keep a one-line reason.

Judge against this repo's conventions (CLAUDE.md), not generic taste: for
example, Codex may flag "unhandled error" on a deliberate let-it-crash bang
call, or suggest defensive branches this codebase explicitly avoids. Those
are rejections, not findings.

## Step 3: Present the result

Lead with the bottom line: Codex's verdict plus your triage counts (e.g.
"Codex found 5 issues; 2 confirmed, 1 plausible, 2 rejected"). Then:

1. Confirmed and plausible findings, most severe first — `file:line`, what's
   wrong, and the suggested fix, in your own words.
2. Rejected findings in a brief list with the one-line reason each was
   rejected, so the user can overrule you.
3. Mention the saved review path for the full unedited report.

Do not start fixing anything — this skill produces an assessment. Offer to
apply fixes only after presenting it.
