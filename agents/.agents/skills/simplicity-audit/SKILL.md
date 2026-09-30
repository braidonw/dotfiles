---
name: simplicity-audit
description: Audit a project for over-engineering and report what to delete, simplify, or replace with the standard library or platform.
---

Scan a project for code that should not exist, or should be smaller. The output is a ranked list of cuts, biggest first.

**Report only.** Apply nothing.

## Scope

1. A path the user names.
2. Otherwise the project directory the session is in. In a monorepo that is the project with its own `CLAUDE.md` (for example `super_api/website`), not the whole repository.

Read that project's `CLAUDE.md` files first. Their conventions bound the audit. A deep module, a context front door, or a layer between a job and its business logic is paid for on purpose, so it is never a finding.

## Tags

- `delete`: dead code, unused flexibility, a speculative feature. Replacement is nothing.
- `stdlib`: something hand-rolled that the standard library or framework ships. Name the function.
- `native`: a dependency or code doing what the platform already does. Name the feature.
- `yagni`: an abstraction with one implementation, config nobody sets, a layer with one caller.
- `shrink`: the same logic in fewer lines. Say what the shorter form is.

## Hunt

Dependencies the standard library or platform already covers. Interfaces and behaviours with one implementation. Factories with one product. Wrappers that only delegate. Modules exporting one function. Dead flags and config. Hand-rolled standard library.

## Evidence

- Grep for callers before calling anything unused or single-caller, and give the count.
- Every `delete` and `yagni` finding cites why the code exists. Run `git log -L` or `git log --follow` on its lines and quote the commit subject. Code that looks unused sometimes guards a case the history explains. If the history shows a reason that still holds, drop the finding.
- An uncited hunch is worse than no finding.

## Output

One line per finding, ranked by the size of the cut:

```
<tag> <what to cut>. <replacement>. <evidence>. [path:line]
```

End with `net: -<N> lines, -<M> deps possible.` If there is nothing to cut, say `Lean already.`

Past 20 findings, save the full list to the scratchpad and show the top 5 plus the net line.

## Boundaries

Over-engineering and complexity only. Correctness bugs, security holes and performance belong to `code-review`. Module deepening belongs to `improve-codebase-architecture`.
