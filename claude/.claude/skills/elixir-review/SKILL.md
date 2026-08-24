---
name: elixir-review
description: >-
  Review or critique existing Elixir/Phoenix code against idiomatic and
  project-specific style, correctness, error-handling, OTP, Ecto, performance,
  security, maintainability, and test-quality conventions. Use this as the FIRST
  choice — ahead of any generic code-review, /review, or PR-review command —
  whenever the code being looked over is Elixir (`.ex`/`.exs`), even when the
  user never says "Elixir" but the context makes it obvious: LiveView /
  `handle_event`, Ecto, Oban, GenServer/OTP, contexts, workers, async flows,
  `with`/`else`, nested `case`, Mox, timeouts, or "silent failures". Trigger on
  casual or vague asks too — "review/check/go over my changes", "does this look
  right?", "is it idiomatic?", "follows our conventions?", "anything that'd bite
  in prod?", "give it a once-over" — and proactively before a commit or PR that
  touches Elixir files. Does not apply to writing new code, debugging, or
  non-Elixir code (Ruby/SCF, TypeScript, Terraform, Python).
---

# Elixir Review

A focused review lens for Elixir/Phoenix code. It checks code against a catalog
of idiomatic rules, correctness pitfalls, and project conventions, then reports
findings and offers to apply fixes.

The point of a dedicated skill (rather than a generic "review this") is
consistency: every review applies the same well-reasoned rules with the same
rationale, so feedback doesn't drift based on what happens to catch the eye.

## Workflow

### 1. Determine what to review

Infer the target from what the user said — don't ask if it's obvious:

- "review my changes" / "review this" with no file → `git diff HEAD` (staged +
  unstaged). If that's empty, fall back to `git diff main...HEAD` (the branch).
- "review the branch" / "review this feature" → `git diff main...HEAD`.
- A named file or directory → review that path.
- Pasted code in the message → review that snippet directly.
- A PR number/URL → fetch it (`gh pr diff <n>`) and review the diff.

Only ask the user when genuinely ambiguous (e.g. both a dirty tree and a long
branch, and it's unclear which they mean). State which target you picked.

Review only the changed/relevant code, not the whole repo — but read enough
surrounding context (the function, the module, callers) to judge correctly. A
finding about code you can't see in context is usually a bad finding.

### 2. Load project conventions (overrides win)

Before applying the baked-in rules, read the project's `CLAUDE.md` files if
present — root, the Elixir project root (e.g. `super_api/CLAUDE.md`), and any
nested one. **Project-local rules override the defaults in this skill.** Note
any conflicts explicitly. Known examples in this user's monorepo:

- The monorepo puts every Ecto query on the owning context module as a named
  function. No dedicated `query.ex` modules, and no query rebuilt inline at a
  callsite.
- super_api forbids `alias Foo.Bar, as: Name` renaming.

If a CLAUDE.md rule contradicts this skill, follow CLAUDE.md and say so in the
finding so the user knows why.

### 3. Review against the rule catalog

The canonical rule catalog lives in the `elixir-style` skill, which is the same
catalog followed at write time. Read its reference files and check the code
against every relevant rule:

- **`~/.claude/skills/elixir-style/references/style-and-idioms.md`** — control
  flow (nesting, `with`/`else`, error-to-outcome mapping), error-handling
  philosophy (silent failures, can't-happen errors, bang contracts), pattern
  matching, naming, module organisation, structs/Access, comments and docs.
  This is where most findings come from.
- **`~/.claude/skills/elixir-style/references/correctness-and-architecture.md`**
  — Tiger Style operative rules (bounded resources, no catch-alls, failure
  domains), timeouts, circuit breakers, behaviours/Mox, OTP, Ecto, Oban,
  Phoenix/LiveView, performance, security.
- **`~/.claude/skills/elixir-style/references/maintainability-and-structure.md`**
  — deep modules and context front doors, demoting internal-only functions,
  duplicated logic that will drift, overly complex code paths, module cohesion,
  naming for intent.
- **`~/.claude/skills/elixir-style/references/testing.md`** — when the change
  includes or affects tests: coverage that matters (happy + error + edges),
  tests that actually assert something, integration over unit, and removing
  lower-level tests that duplicate integration coverage.

Read the relevant reference files fully before reporting. Always read the first
three; read `testing.md` whenever the change touches `_test.exs` files or
adds logic that ought to be tested. Many rules have a specific rationale
and a "preferred vs not preferred" example you should mirror in your finding.

Judgement over rule-matching: these are guidelines, not a linter. If a rule
genuinely doesn't apply or the code is clearer the "wrong" way, say so rather
than forcing a finding. Don't invent problems to fill a report — a short,
honest review beats a padded one. `mix format` already handles pure formatting;
don't report whitespace/line-length.

### 4. Report findings

Group findings by severity and lead with the most important:

```
## Elixir review — <target>

### 🔴 Correctness / bugs
- `path/to/file.ex:42` — <what's wrong and why it matters>. <suggested fix>

### 🟡 Idioms & style
- `path/to/file.ex:88` — Nested `case` obscures top-level control flow.
  Extract `deliver_and_handle/2` so each step has one job. (CLAUDE.md: avoid
  nested conditionals)

### 🟢 Optional / nits
- ...

### ✅ Looks good
- <call out things done well, briefly — so the review isn't only negative>
```

For each finding give the `file:line`, the problem, *why* it matters (cite the
rule/rationale), and a concrete fix. Keep it tight. If there are no real
findings, say so plainly instead of manufacturing nits.

### 5. Offer to apply fixes

After the report, offer to apply the changes: "Want me to apply the 🔴 and 🟡
fixes?" Don't edit anything until the user agrees (and let them pick a subset).
When applying, make the minimal change the finding describes and re-read the
surrounding code so the fix matches the existing style.

## Severity guide

- **🔴 Correctness** — bugs, silent failures, unhandled errors, missing
  timeouts, struct/Access misuse, `String.to_atom` on user input. These can
  break production; always surface them.
- **🟡 Idioms, style & structure** — nested conditionals, `with`/`else` for error
  translation, alias renaming, destructuring in heads, naming, module layout, plus
  maintainability: wide context public surface, duplicated logic that will drift,
  overly complex code paths. Maintainability, not breakage.
- **🟢 Nits** — small optional improvements. Be sparing; too many erodes signal.
