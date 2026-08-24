# Code structure and maintainability

These rules are about keeping the codebase easy to change six months from now: clear module boundaries, no duplicated logic that will drift, and code paths a reader can follow.

The guiding principle throughout is judgement over mechanical rules. Elixir codebases tolerate a little duplication and a few long functions; the job is to catch the cases that will actually cause pain, not to enforce metrics. When in doubt, ask "will the next person who changes this be misled or slowed down?" If not, leave it.

## Table of contents

1. Prefer deep modules
2. Context modules are the domain's front door
3. Demote context functions whose only callers are inside the domain
4. Duplicated logic (DRY, with restraint)
5. Overly complex code paths
6. Module cohesion and single responsibility
7. Naming for intent

---

## 1. Prefer deep modules

The full rule, the definition of interface, and the deletion test live in the monorepo root CLAUDE.md under "Module Design". Follow it in every project, including ones outside that monorepo. The `codebase-design` skill carries the full vocabulary. The short version: a module is deep when a lot of behaviour sits behind a small interface. Push complexity inward, keep the public surface as small as the job allows, and let the implementation be as large as it needs to be. Interface means everything a caller must know (invariants, ordering constraints, error modes), not just signatures.

## 2. Context modules are the domain's front door

The top-level module named after a domain (e.g. `SuperApi.Accounts` in `accounts.ex`) is that domain's public front door. It exposes only the functions meant to be called from outside the domain: `fetch`/`load`/`create`/mutations and the like. Everything that's purely internal plumbing is a `defp`, or lives in a clearly-internal submodule that outsiders aren't expected to reach into.

Why it matters: every `def` on a context is a promise to the rest of the codebase. A wide public surface means more callers to consider on every refactor, and it blurs which functions are safe to change freely.

Watch for:

- **Outside code reaching past the front door.** A web controller, LiveView, or another context calling a schema's queries directly, or `SuperApi.Accounts.SomeInternalThing.do_it/1`, instead of going through `SuperApi.Accounts.fetch_user/1`. Cross-domain access goes through the context's public functions, not its schemas or internals. If the function you need isn't there, add a `def` to the context rather than aliasing past it.
- **Business logic leaking into the schema module.** The schema file holds the schema and changesets; the context holds the operations.

A genuinely-public function with one current caller is fine. Public API is defined by intent, not call count. The smell is a function that is clearly internal plumbing yet exposed.

## 3. Demote context functions whose only callers are inside the domain

When touching a context, check whether any of its `def`s are called only from within the domain (e.g. an Oban worker in the same context). Grep the callers, don't assume. If so, move the function into its caller as a `defp` (transitively: if that leaves another context `def` with only internal callers, fold it too). Being directly unit-tested does not make a function public API. When the caller's integration tests already drive every branch, delete the direct unit tests as redundant; otherwise move the missing cases up to the caller's tests. While moving, drop defensive code the narrowed call site makes unreachable (e.g. a `Repo.preload` the caller's load already guarantees).

## 4. Duplicated logic (DRY, with restraint)

Extract logic that is genuinely duplicated and will drift out of sync: the same multi-step computation, validation, query shape, or transformation copy-pasted across functions or modules. Extracting it to one named function in the right context means a future change happens in one place, not three.

Hold this in tension with the inline-error-mapping rule (`style-and-idioms.md` rule 2), which prefers a little duplication over a one-line indirection. Two things that merely look similar but change for different reasons should stay separate; coupling them behind one abstraction is worse than the duplication.

- **Does count**: an identical 6-line balance calculation in three functions; the same `where`/`join` fragment rebuilt verbatim in five queries; a validation sequence pasted across changesets.
- **Doesn't count**: two short clauses that happen to share a shape but express different intent; incidental similarity that won't co-evolve.

When extracting (or flagging in review), name where the shared function should live and why the sites will change together.

## 5. Overly complex code paths

Code the reader has to hold too much in their head at once. Prompts to decompose:

- **Long functions doing several jobs.** Split into named steps, the same move as the nested-`case` rule. A function you have to scroll to read, or with clear "sections" separated by blank lines, usually wants splitting.
- **Deep nesting / high branching.** Stacked `case`/`if`/`cond`, long `with` chains, pipelines with branching mid-stream. Flatten by extracting (subject to the two-levels-is-fine rule).
- **Many positional arguments** (roughly 4+). Reach for a struct or keyword opts so call sites are self-documenting and adding a parameter doesn't reshuffle every caller.
- **Boolean or flag arguments that fork behaviour.** `def render(thing, true)` is unreadable at the call site. Two well-named functions usually read better than one with a mode flag.
- **Primitive obsession.** A bare tuple or map threaded through many functions where a small struct would name the fields and let pattern matching enforce shape.

These are judgement prompts, not metrics. A flat 40-line sequence is fine; a 15-line function nested three deep is not.

## 6. Module cohesion and single responsibility

A module should have one reason to change. A module that has accumulated unrelated responsibilities (HTTP client plus business rules plus formatting), or whose functions operate at wildly different abstraction levels, wants its seams found. Frame this as a direction, not a demand; splitting is a judgement call. Length alone is not complexity, so never split just because a file got long.

## 7. Naming for intent

Names are the cheapest documentation. Avoid names that mislead (a `fetch_*` that mutates, a `*?` that returns a non-boolean), names so generic they carry no information (`data`, `handle`, `process` on a domain function), and names that describe how rather than what. Tie back to the specific naming rules where relevant: `fetch` vs `load`, predicate `?` vs guard `is_`, the `!` contract, units in names.
