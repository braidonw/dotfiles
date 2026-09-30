---
name: plan-review
description: "Critique an implementation plan's scope, architecture, edge cases and tests before any code is written, with a hard eye for over-engineering. Use when a review agent is asked to review a plan, or when the user asks for an engineering or architecture review of a plan."
---

Review a plan before implementation starts. The question is whether this plan is the smallest one that solves the real problem safely. Finding problems now is cheaper than finding them in a diff.

**Read-only.** Report findings. Do not edit the plan, write code, or build prototypes. Bounded probes of current behaviour (reading code, `git log`, a read-only query) are fine when a finding depends on them.

## Inputs

The main session supplies the plan, as a path or pasted text, and the repo it targets. Locate the repo's agent docs per `~/.agents/skills/setup-braidon-skills/locate.md`, and read the glossary and any ADRs in the area the plan touches. Read the repo's `CLAUDE.md` files, since their conventions bound every recommendation.

## Evidence

A plan's steps are proposals, so findings about them are predictions. Quote the plan line each finding is about. Check claims about existing code against the code, and cite file and line. Label anything you could not verify as unverified.

## Checks

Run all five in order. Report at most 5 findings per check, ranked by severity, and say "No issues found" for an empty check. Every check hunts for over-engineering, as well as for its own concerns.

The audit tags name the kinds of over-engineering to look for:

- `delete`: a speculative feature, unused flexibility, or work nothing needs yet
- `stdlib`: something hand-rolled that the standard library or framework already ships
- `native`: code or a dependency doing what the platform already does (a database constraint, a framework feature)
- `yagni`: an abstraction with one implementation, config nobody sets, a layer with one caller
- `shrink`: the same outcome with fewer files, modules or steps

### 1. Scope challenge

- **What already exists?** For each part of the plan, search the codebase for something that already solves it, and cite it by name. Rebuilding what exists is the most common waste.
- **What is the minimum change?** Name steps that can be deferred without blocking the goal.
- **Complexity count.** Count the files the plan changes and the new modules, tables, workers and integrations it adds. At 8 or more files, or 2 or more new modules, propose a smaller arrangement that delivers the same features with fewer moving parts, or say why none exists.
- **Over-engineering hunt.** Speculative features, seams with one adapter, config nobody sets, new dependencies for what a few lines can do, factoring before the cut-points are visible, and big-bang refactors where small steps would do.

### 2. Architecture

- Module boundaries and coupling. Does each new public function sit on the context that owns the domain, behind its front door?
- Data flow. Where does data enter, where is it stored, and who reads it?
- Security at trust boundaries: authorisation, data access, external input.
- Anything built "for later" that no current requirement needs.

### 3. Edge cases and failure modes

For each new path or integration, name one realistic production failure. Say whether the plan tests it, handles it, and whether the outcome is loud or silent. A failure with no test, no handling and a silent outcome is a **critical gap**.

Flag missing bounds too: timeouts on external calls, retry ceilings, size limits on external input.

### 4. Tests

- One integration test through the context's public functions for each behaviour that could regress. Flag unit tests that reach past the interface, and mocks inside the boundary under test.
- Flag test scaffolding the plan proposes that no behaviour needs.

### 5. Performance

- N+1 queries and missing preloads.
- Anything unbounded: a list that grows without a limit, a job with no concurrency cap, a query with no index behind it.
- Skip speculative optimisation. Recommend a cache or index only when the plan's own numbers call for it.

## Output

```markdown
## Plan review: <plan title or path>

**Verdict:** <ready / ready after fixes / rethink scope>

### 1. Scope challenge
1. **[severity] <finding>**. <plan line quoted>. <evidence>. <recommendation, with its audit tag when it is a cut>.

### 2. Architecture
...

### 5. Performance
...

### Not in scope
- <work the plan could reasonably be expected to include but should defer, with one line each>
```

Severity is `critical`, `high`, `medium` or `low`. Recommend the smallest change that fixes each finding. A plan that is already lean gets a short report, and padding the report is a failure.
