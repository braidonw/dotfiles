---
name: dual-review
description: "Run two independent code reviews of the current branch at once — the elixir-review skill (Claude, rule-catalog based) and gpt-code-review (OpenAI Codex via the Codex CLI) — then merge them into one triaged report where findings both reviewers agree on are flagged as highest confidence. Use this whenever the user wants both reviews, a dual/combined/full review, 'claude and gpt to review this', 'both reviewers', or a thorough pre-merge review with a second opinion built in. Do NOT use it when the user asks for only one reviewer by name — plain 'review my changes' belongs to elixir-review alone, and 'codex review' to gpt-code-review alone."
---

# Dual review: elixir-review + Codex in parallel

Two reviewers with different blind spots: the elixir-review skill applies
this codebase's specific rule catalog with full session context; Codex looks
with fresh outside eyes and tends to catch cross-cutting things (build
wiring, infra, config) the Elixir lens skips. Running both and merging beats
either alone — and where they independently flag the same thing, that
agreement is the strongest signal in the report.

## Step 1: Launch the Codex review first

It's the long pole (2–10 minutes), so start it before anything else. Parse
the user's request for the optional base branch / model / focus, then launch
the gpt-code-review script in the background (`run_in_background: true`):

```bash
~/.claude/skills/gpt-code-review/scripts/codex_review.sh \
  [--base <branch>] [--model <model>] [--focus "<text>"]
```

Tell the user both reviews are underway. Do not poll the background task —
you'll be notified when it exits. Exit code 3 means no diff against the
base; report that and stop (there's nothing for either reviewer).

## Step 2: Run elixir-review inline while Codex works

Invoke the `elixir-review` skill (Skill tool) and carry it out fully now, in
this session — this is what fills the waiting time. Two adjustments so the
halves line up:

- Review the same target the script is reviewing: the diff against the
  merge-base with the base branch, including uncommitted changes — not just
  `git diff HEAD`.
- Complete the review through its findings, but do not present its report or
  offer fixes yet. Hold the findings for the merge.

elixir-review only covers `.ex`/`.exs` files. If the branch touches other
things (Terraform, JS, config, SQL), note that those are covered by the
Codex half only. If the branch has no Elixir changes at all, skip this step
and say so — the merged report is then just the triaged Codex review.

## Step 3: Triage Codex and merge

When the background task completes, read its review (it ends with
`REVIEW_SAVED: <path>`). Triage the Codex findings exactly as
gpt-code-review prescribes (its Step 2: verify each against the actual code,
classify Confirmed / Plausible / Rejected, judging against this repo's
CLAUDE.md conventions rather than generic taste).

Two shortcuts the dual setup earns you:

- A Codex finding that matches one of your own elixir-review findings is
  already verified — mark it agreed, don't re-check it.
- A Codex finding that contradicts one of yours means one of you is wrong:
  re-read the code and settle it rather than reporting both sides.

Match findings on substance (same defect at the same site), not wording.

## Step 4: Present one merged report

One report, not two pasted together. Lead with the bottom line: both
verdicts and the combined counts. Then:

```
## Dual review — <branch>

### Flagged by both reviewers        <- highest confidence, lead with these
- `file:line` — <finding, fix>

### Codex only (confirmed / plausible)
- `file:line` — <finding, fix> [confirmed|plausible]

### Claude only (elixir-review)      <- keep its 🔴/🟡/🟢 severity markers
- 🔴 `file:line` — <finding, fix>

### Rejected Codex findings
- <one-line reason each, so the user can overrule>

### Looks good
- <brief, from either reviewer>
```

Within each section order by severity. Note the saved Codex review path at
the end for the unedited original. Then offer to apply fixes (the user picks
a subset) — but don't edit anything until they agree.
