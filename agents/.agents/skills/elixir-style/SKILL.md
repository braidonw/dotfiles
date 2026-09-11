---
name: elixir-style
description: >-
  The canonical catalog of Elixir/Phoenix house rules for WRITING code. Load
  this BEFORE writing, editing, or refactoring any Elixir code (.ex/.exs),
  whatever the task: new features, bug fixes, refactors, tests, Oban workers,
  LiveViews, Ecto queries, GenServers, migrations. Trigger even when the user
  never says "Elixir" but the files or context make it obvious, and even for
  small edits. Not for reviewing or critiquing existing code (elixir-review
  owns that and reads this same catalog) and not for non-Elixir code.
---

# Elixir Style

The single source of truth for how Elixir gets written across this user's projects. The elixir-review skill reads the same reference files, so a rule followed here is the same rule a later review will check.

## How to use

1. Read the relevant reference files before writing code. `style-and-idioms.md` applies to almost everything, so always read it. Read the others when the work touches their area.
2. Project conventions override this catalog. Read the project's CLAUDE.md files (repo root and app level) and follow them where they conflict.
3. These are guidelines backed by rationale, not a linter. When a rule genuinely makes the code worse in a specific spot, deviate and say why.

## Reference files

- `references/style-and-idioms.md`: control flow (nesting, `with`/`else`, error-to-outcome mapping), error-handling philosophy (silent failures, can't-happen errors, bang contracts), pattern matching, naming, module organisation, comments and docs, misc gotchas. Read this for any Elixir work.
- `references/correctness-and-architecture.md`: Tiger Style operative rules (bounded resources, no catch-alls, failure domains, state ownership), external calls and timeouts, OTP, Ecto, Oban, Phoenix/LiveView, performance, security.
- `references/maintainability-and-structure.md`: deep modules and context front doors, demoting internal-only functions, duplication judgement, complexity prompts, naming for intent.
- `references/testing.md`: coverage that matters, tests that actually assert something, integration over unit, removing redundant tests, hygiene.

## Related skills

- `tiger-style` carries the full Tiger Style for Elixir essay. The operative rules distilled from it live in `references/correctness-and-architecture.md`.
- `codebase-design` carries the deep-module vocabulary behind the maintainability rules.
- `elixir-review` is the review lens over this same catalog.
