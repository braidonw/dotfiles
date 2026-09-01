---
name: gpt-plan-review
description: "Get a second-opinion review of an implementation plan from OpenAI Codex (via the Codex CLI) before any work starts: Codex checks the plan's assumptions against the actual repository, then the findings are triaged and folded back into the plan. Use this whenever the user asks for a GPT/Codex review of a plan, a second opinion on a plan or approach, wants a plan double-checked or sanity-checked before implementation begins, or says things like 'run the plan past gpt first'. Do NOT use it for reviewing code or diffs (that's gpt-code-review), nor for writing the plan itself."
---

# GPT plan review via the Codex CLI

Run OpenAI Codex as an external reviewer over an implementation plan before
work starts. The point is to catch the failures that are cheap to fix now and
expensive mid-build: assumptions that don't match the codebase, missing
steps, risky orderings. As with code review, Codex's findings are a second
opinion, not a verdict — verify each one before it changes the plan.

## Step 1: Get the plan into a file

The plan usually lives in the conversation (e.g. just drafted in plan mode).
Write it verbatim to a markdown file in the scratchpad directory — don't
summarize or clean it up, since dropping a detail hides it from review.
Include everything the reviewer needs to judge it: the goal, known
constraints or decisions already made, the steps, and the files involved. If
the user points at an existing plan document instead, use that path directly.

## Step 2: Launch the review

Parse the user's request for an optional model override and focus area, then
run the bundled script from anywhere inside the repo:

```bash
~/.claude/skills/gpt-plan-review/scripts/codex_plan_review.sh \
  --plan <plan-file> [--model <model>] [--focus "<text>"]
```

Run it with `run_in_background: true` — the review takes 2–10 minutes and
must not block the session. Tell the user it's running and roughly how long
it takes. Do not poll; you'll be notified when it exits.

Notes:
- Default model is `gpt-5.6-sol`; pass `--model` to override with any model
  the user's Codex account offers.
- Codex runs in a read-only sandbox and is instructed to verify the plan's
  claims against the repo — file paths, named functions, existing
  conventions — rather than proofread the prose. It picks up the repo's
  AGENTS.md automatically and the prompt points it at CLAUDE.md.
- Findings come back as [BLOCKER|MAJOR|MINOR] with the plan step concerned,
  evidence from the repo, and a suggested amendment, plus an overall verdict
  (ready as written / ready with amendments / needs a rethink).

If the script fails (codex missing, not logged in — fix with `codex login` —
or a provider error), show the user
the actual error and stop — don't substitute your own review for the second
opinion the user asked for.

## Step 3: Triage the findings

The script prints the review and ends with `REVIEW_SAVED: <path>`. Verify
each finding before presenting it:

- Check the evidence yourself: open the files Codex cites, confirm the
  claimed mismatch or gap is real. For "missing step" findings, check whether
  the plan genuinely omits it or handles it under different wording.
- Classify each finding:
  - **Confirmed** — you checked and Codex is right.
  - **Plausible** — depends on information neither of you has (prod data,
    product intent), but the reasoning holds; worth flagging to the user.
  - **Rejected** — the plan already covers it, the claim misreads the repo,
    or it contradicts a decision the user already made deliberately. Keep a
    one-line reason.

Findings that second-guess decisions the user explicitly made (architecture
choices, scope cuts) are not defects — surface them at most as a brief note,
not as amendments.

## Step 4: Present the result and amend the plan

Lead with the bottom line: Codex's verdict plus triage counts. Then:

1. Confirmed and plausible findings, most severe first — the plan step
   affected, what's wrong, and the amendment, in your own words.
2. Rejected findings in a brief list with the one-line reason each, so the
   user can overrule you.
3. A concrete amended version of the affected plan steps (not a full
   rewrite) incorporating the confirmed findings, for the user to accept or
   edit.
4. The saved review path for the full unedited report.

Do not start implementing — the deliverable is the reviewed, amended plan.
Wait for the user to approve it.
