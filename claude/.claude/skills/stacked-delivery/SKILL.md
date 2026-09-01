---
name: stacked-delivery
description: "Workflow for large pieces of work (anticipated diff roughly 1,000+ LOC, or multi-session tasks): build everything on a single wip/ branch, run the dual-review skill from a fresh context and fix findings until a clean pass, then split the result into a stack of ~1,000-LOC branches that each pass CI independently, and hand over a description document for the user to create the PRs from. Use this at the START of any large work item (to set up the wip branch) and again at DELIVERY time (review loop + split). Also triggers when the user says 'stacked PRs', 'split this branch/PR up', 'wip branch workflow', or asks to make a big diff reviewable. Do NOT use for ordinary small-to-medium tasks that fit in one reviewable PR — those follow the normal workflow. NEVER pushes or creates PRs; the user does that themselves."
---

# Stacked delivery: wip branch → dual-review loop → stacked branches

The goal is reviewability: a large work item is built in one place, made
correct via independent review, then re-cut into a stack of branches a human
can actually review (~1,000 LOC each). Nothing is ever pushed and no PRs are
created — the user reviews everything locally and creates PRs themselves.

## Phase A — Build on a single wip branch

- Branch `wip/<task-slug>` off `main` and do all the work there.
- Commit incrementally with meaningful messages — the split in Phase C is
  much easier when commits already group related changes.
- Normal rules apply inside this phase (plan first, delegate to
  implement/chore agents, tests alongside code). This skill only governs the
  container the work lands in.

## Phase B — Dual-review loop (fresh context)

The review must not be run by the context that wrote the code. When the work
on the wip branch is complete:

1. Spawn a fresh `general-purpose` subagent whose prompt contains only: the
   repo path, the wip branch name, the base branch, and the instruction to
   invoke the `dual-review` skill and return the merged report verbatim as
   its final output — explicitly telling it NOT to apply any fixes. Give it
   no implementation context, no summary of what the change "should" do
   beyond one neutral sentence.
2. Back in the main session, triage the returned report and fix the
   confirmed/agreed findings on the wip branch (delegating fixes as usual).
3. Re-run step 1 in another fresh subagent.
4. Repeat until a pass comes back with no confirmed findings. Cap at 3
   iterations — if findings still remain after that, stop and surface the
   residual list to the user rather than looping.

Findings you reject during triage go in the final handover doc so the user
can overrule.

## Phase C — Split into stacked branches

Only after a clean review pass. Keep the wip branch untouched as the
reference (never delete it; the split is validated against it).

**Sizing**: ~1,000 LOC of diff per branch is the target, not a hard rule.
Logical cohesion wins: a 1,400-LOC branch that is one coherent layer beats
two 700-LOC branches that split a concept in half. If the whole work item is
under ~1,200 LOC, skip the split — one branch is fine; say so and stop after
Phase D's description doc.

**Ordering**: each branch must build and pass CI on its own, so order by
dependency. The natural layering here is usually:

1. migrations + schemas + factories
2. context / business-logic modules (+ their tests)
3. workers, integrations, pipelines (+ their tests)
4. web layer: controllers/LiveViews/templates/routes (+ their tests)

**Mechanics**:

- Naming: `<type>/<task-slug>-1-<short>`, `<type>/<task-slug>-2-<short>`, …
  matching the repo's prefix conventions (`feat/`, `maint/`, `fix/`).
- Branch 1 is cut from `main`; branch N from branch N-1.
- Bring code over with `git checkout wip/<slug> -- <paths>` (or cherry-pick
  when commits already align), then commit. Partial-file splits are allowed
  when a file spans layers, but prefer whole files.
- After the last branch, verify completeness:
  `git diff <last-branch> wip/<slug>` must be empty (or explainably empty —
  e.g. scaffold tests that exist only in the stack).

**Per-branch gate** — every branch must independently pass what CI runs:

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- the test suite (at minimum every test file touched by or exercising the
  branch's code; full suite if the change is cross-cutting). Use the
  worktree test procedure from CLAUDE.md when running outside the main
  checkout.

**Scaffold tests**: if an early branch introduces code that only gets a real
caller in a later branch, and it needs tests to pass CI/coverage, write the
minimal test that exercises it directly. Every such test goes in the
handover doc's scaffold ledger: file/test name, which branch introduces it,
and which later branch's tests supersede it (so it can be removed or
replaced once the stack merges). Don't mark them with in-code comments —
the ledger is the record.

## Phase D — Handover document

Write a markdown doc and give both the file path and its full text in the
final message. It contains:

1. **Overall description** — PR-body-quality prose describing the whole
   work item: what it does, why, key design decisions, anything reviewers
   should know. This doubles as the description for the stack's anchor PR.
2. **Per-branch section** — for each branch in order: branch name, a
   suggested PR title, a summary of what it contains and why it's a
   coherent unit, its base branch, and how it was verified.
3. **Scaffold-test ledger** — from Phase C, or "none".
4. **Review residue** — dual-review findings that were rejected during
   triage (with the one-line reason), so the user can overrule.

Save the doc outside the repo working tree (scratchpad or the session
directory) so it can't be committed accidentally.

## Hard rules

- **Never `git push`. Never create PRs.** The user reviews locally and
  creates the PRs themselves — including for the wip branch.
- Never delete the wip branch; it's the reference the split is checked
  against and the fallback if the split goes wrong.
- Don't start Phase C before a clean (or user-accepted) Phase B pass —
  fixing findings after the split means re-cutting every branch above the
  fix.
