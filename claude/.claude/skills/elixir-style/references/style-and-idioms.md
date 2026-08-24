# Elixir style and idioms

The core rules. Each carries its rationale, so apply the reasoning rather than pattern-matching the letter, and cite the rationale when reviewing. Write clear, concise, idiomatic Elixir with a focus on clarity and maintainability.

## Table of contents

1. Nesting conditionals: two levels is fine, three is not
2. Inline error-to-outcome mappings in the `case`
3. Avoid `with`/`else` for error translation
4. `with` for happy-path chaining (no `else`)
5. No silent failures
6. Don't handle errors that can't happen. Use the raising variant and let it crash
7. Presence guaranteed by DB constraints is not a runtime error
8. Plain returns over invented tags
9. Don't extract single-caller wrappers
10. Pass along data the caller already has
11. A function whose contract is to raise carries a `!` suffix
12. Predicate naming (`?`, not `is_`)
13. Pattern matching in function heads: struct guards
14. Destructure in the body, not the arguments
15. No `alias ..., as:` renaming
16. Module organisation: schema vs business logic, `fetch/1` vs `load/1`
17. Structs don't implement Access
18. Don't `String.to_atom/1` on user input
19. Date/time: use the stdlib
20. Never nest multiple modules in one file
21. Single-use module attributes live next to their use site
22. `@spec` on public functions
23. Prefer the conventional one-liner over hand-rolled equivalents
24. Comments and documentation

---

## 1. Nesting conditionals: two levels is fine, three is not

One `case` inside another (or a `case` inside a `with`/`if`) is acceptable when it keeps a short chain of related steps readable in one place. Don't extract a helper just to eliminate a second level if the extraction would scatter the flow across functions for no gain in clarity. Go beyond two levels almost never, only when every alternative is genuinely worse. At three-plus levels, extract the inner levels into small helper functions so function names describe what each step does. Function-head pattern matching is the natural way to fan out from there. Extracted helpers should do something meaningful (make a call, do real work); don't extract a helper whose only job is to map one value to another (see rule 2).

```elixir
# Fine. Two levels, short and readable in one place
defp run(employee_id) do
  case Stapling.build_request(employee_id) do
    {:ok, request} ->
      case Stapling.deliver_request(request) do
        {:ok, response} -> handle_response(employee_id, request, response)
        {:error, :no_active_connection} -> {:cancel, :no_active_ato_connection}
      end

    {:error, :not_found} ->
      {:cancel, :employee_not_found}
  end
end

# When a third step appears, extract rather than nest a third level
defp run(employee_id) do
  case Stapling.build_request(employee_id) do
    {:ok, request} -> deliver_and_handle(employee_id, request)
    {:error, :not_found} -> {:cancel, :employee_not_found}
  end
end

defp deliver_and_handle(employee_id, request) do
  case Stapling.deliver_request(request) do
    {:ok, response} -> handle_response(employee_id, request, response)
    {:error, :no_active_connection} -> {:cancel, :no_active_ato_connection}
  end
end
```

The same applies to nested `if`/`cond`/`case` mixes. Two levels can stay together when short; at three, flatten by extracting.

## 2. Inline error-to-outcome mappings in the `case`

Don't extract a helper function whose only job is to rename one tagged tuple into another (e.g. `defp build_error_to_outcome(:not_found), do: {:cancel, :employee_not_found}`). Put the clause directly in the calling `case`. The mapping is right there at the site, and a stand-alone helper that just renames a value doesn't earn its keep. A small amount of duplication across two call sites is preferable to chasing a one-line indirection. Helper functions are for steps that do real work (a `Repo` call, a transform, branching), not for renaming.

## 3. Avoid `with`/`else` for error translation

When chaining multiple `{:ok, _} | {:error, _}` calls, prefer explicit `case` statements (a two-level nested `case`, or per-step helper functions for longer chains) with the error-to-outcome clauses inlined. An `else` clause on a `with` block conflates errors from different sources. Readers can't tell which step produced which error, and adding a new failure mode to one step means inspecting every `else` clause to see whether it's already handled.

```elixir
# Preferred. Case with inline error clauses
defp run(employee_id) do
  case Stapling.build_request(employee_id) do
    {:ok, request} ->
      deliver_and_handle(employee_id, request)

    {:error, :not_found} ->
      {:cancel, :employee_not_found}

    {:error, reason} when reason in [:missing_tfn, :missing_data] ->
      {:cancel, reason}
  end
end

# Not preferred. With/else
defp run(employee_id) do
  with {:ok, request} <- Stapling.build_request(employee_id),
       {:ok, response} <- Stapling.deliver_request(request) do
    handle_response(employee_id, request, response)
  else
    {:error, :not_found} -> {:cancel, :employee_not_found}
    {:error, :no_active_connection} -> {:cancel, :no_active_ato_connection}
    {:error, reason} when reason in [:missing_tfn, :missing_data] -> {:cancel, reason}
  end
end
```

## 4. `with` for happy-path chaining (no `else`)

`with` is the right tool for chaining `{:ok, _}`/`{:error, _}` operations when there's no `else`, that is, when an unmatched value should be returned verbatim to the caller. The tension with rule 3 resolves cleanly. `with` without `else` is good; `with` plus an `else` that translates errors is the smell.

## 5. No silent failures

Fail loudly rather than papering over an unexpected state with a default. The canonical anti-pattern:

```elixir
# Not preferred. Silently treats an unknown frequency as "starter"
plan = Map.get(plan_map, frequency, "starter")

# Preferred. Unknown input fails loudly
case Map.fetch(plan_map, frequency) do
  {:ok, plan} -> plan
  :error -> raise ArgumentError, "unknown frequency: #{inspect(frequency)}"
end
```

Watch for: `Map.get/3` with a default that hides missing keys, `rescue`/`catch` that swallows everything, `_ -> :ok` catch-all clauses that discard errors, `{:error, _} -> nil`, and default function clauses that mask unexpected input. A silent fallback reads as "handled everything" when it hasn't. This is a correctness concern, not just style.

## 6. Don't handle errors that can't happen. Use the raising variant and let it crash

When an operation only returns `{:error, _}` for malformed or programmer-error input that a well-formed call site never produces, don't write a `case`/log/`log_and_notify`/swallow branch for that error. Prefer the bang variant (`Oban.insert!`, `Repo.insert!`, `Jason.decode!` on data you built) and let it raise if the "impossible" ever occurs. A crash is a loud, located, debuggable signal. An elaborate branch for an unreachable error is dead code that obscures the happy path and misleads readers into thinking the failure is expected and handled.

This is the flip side of rule 5. Both say surface the unexpected loudly rather than papering over it. `Oban.insert` followed by `{:error, _} -> log(...); :ok` is a silent failure dressed up as handling.

```elixir
# Not preferred. Defends against an error that can't occur, then swallows it
case AutoResolveWorker.enqueue(employee_id) do
  {:ok, _job} ->
    :ok

  {:error, changeset} ->
    SuperApi.Logger.log_and_notify("failed to enqueue", errors: inspect(changeset.errors))
    :ok
end

# Preferred. Bang variant; let it raise if the impossible happens
AutoResolveWorker.enqueue!(employee_id)
:ok
```

Distinguish genuine runtime errors (network down, not-found, validation of user input, a race) from errors that only fire on a bug at the call site. You match and handle the first kind. You let the second kind raise. If a raising call sits inside a caller's transaction, raising rolls the work back atomically, which is usually what you want over committing half the operation.

Watch for: a `case Op.insert(...)` whose `{:error, _}` arm just logs and returns `:ok`; "outcome reporter" helpers built solely to log both arms of a call that won't fail.

## 7. Presence guaranteed by DB constraints is not a runtime error

A NOT NULL foreign key with a required association (an employee always has an employer), or a row the same transaction just inserted, means the schema guarantees the data exists. In that case don't return `{:error, :not_found}` for its absence or give callers a soft skip branch. Use `Repo.one!`/`Repo.get!` and let it crash. Absence means a bug or corrupted data, and a soft not-found both hides that signal and conflates it with ordinary cases like "caller passed a bad id" (which, when the id comes from trusted internal plumbing such as job args built from a real record, is itself a can't-happen, same treatment). This is a special case of rule 6. Genuine not-founds (user-supplied ids, optional associations, records that can be deleted out from under you) keep the tuple form.

## 8. Plain returns over invented tags

When an internal helper's outcomes all collapse to the same caller behaviour, return a plain value (a boolean from a `?`-named predicate, an integer with a documented sentinel) and branch with `if`. Don't mint tagged atoms (`:acquired | :not_acquired`) or `{:ok, _} | :error` shapes the caller never distinguishes. Tagged tuples are for outcomes the caller handles differently. Watch the sentinel choice. `nil >= n` is truthy under Elixir term ordering, so return `0`, not `nil`, when the caller compares.

## 9. Don't extract single-caller wrappers

A private function with one caller whose only job is to pin a return value or host a `rescue` isn't earning its keep. Use a function-level `rescue` and an explicit trailing return in the public function instead. Extraction is for branching steps that do real work.

## 10. Pass along data the caller already has. Don't re-fetch it downstream

Before adding a lookup function so a downstream step can derive X from an id (e.g. `fetch_employer_for_employee/1` to get an ABN inside a policy check), check whether the call sites already hold X (a preloaded association, a value from an earlier query). If they do, thread the value through function arguments, or through Oban job args at enqueue time. Pass just the field needed (the ABN, not the whole employer). The re-fetch costs an extra query, mints a single-caller public function on a context, and drags in a not-found branch that can't legitimately fire. The exception is freshness. Re-check downstream any state that may genuinely change between the caller and the downstream step (e.g. an eligibility window re-checked inside a worker); thread stable identifiers and values.

## 11. A function whose contract is to raise carries a `!` suffix

If a function is designed to raise on failure rather than return `{:error, _}`, name it with a trailing `!` (`enqueue!`, `fetch_user!`, `charge!`). This mirrors the stdlib pairing (`Map.fetch`/`Map.fetch!`, `Repo.insert`/`Repo.insert!`). The bang tells every call site "this raises, so handle it upstream or let it crash." It applies even with no tuple-returning sibling. A standalone helper that wraps a raising call (`Oban.insert!`) and never returns `{:error, _}` still gets the `!`. This is about the contract (a function meant to raise), not about whether some code path could theoretically raise a `MatchError` or a `Repo` connection error. Don't bang every function, only those whose documented behaviour is to raise on the failure a caller would otherwise pattern-match.

## 12. Predicate naming (`?`, not `is_`)

Predicate function names should end in a question mark and not start with `is_`. Names like `is_thing` should be reserved for guards (macros usable in guard clauses), e.g. `is_admin/1` as a guard vs `admin?/1` as a regular function.

## 13. Pattern matching in function heads: struct guards

Only add a struct guard (`%OnboardingSession{} = session`) when the function accepts multiple types and needs to discriminate. If only one type is ever passed, the guard is noise; omit it.

## 14. Destructure in the body, not the arguments

Prefer destructuring inside the function body over in the arguments, to signal there's no dynamic dispatch on the shape:

```elixir
# Preferred
def name(user) do
  %{first_name: first_name, last_name: last_name} = user
  "#{first_name} #{last_name}"
end

# Not preferred
def name(%{first_name: first_name, last_name: last_name}) do
  "#{first_name} #{last_name}"
end
```

Exception: when the match in the head is the dispatch (multiple clauses matching different shapes), keep it in the head.

## 15. No `alias ..., as:` renaming

Don't rename aliases. The trailing segment that `alias` gives you by default (or the full module name) is fine. `as:` rewrites force the reader to keep a mental map between two names for one module. If two in-scope modules share a trailing segment, alias one with its full name and use the other fully qualified, not `alias Baz.Bar, as: BazBar`. This is a hard rule in super_api; existing `as:` aliases there are legacy, not precedent. Check the project CLAUDE.md elsewhere.

## 16. Module organisation: schema vs business logic, `fetch/1` vs `load/1`

Keep schema/changeset definitions separate from the functions that operate on them:

- `users/user.ex`: schema and changesets
- `users.ex`: functions to work with users (`fetch`, `load`, `create`, mutations)

`fetch/1` returns `{:ok, record}` without preloads. `load/1` returns `{:ok, record}` with preloaded associations. A `fetch` that preloads or a `load` that doesn't is misnamed.

Oban: the enqueue/convenience function lives alongside `perform/1` in the worker module, not in the context module. See the Oban section of `correctness-and-architecture.md` for the full layering rule.

## 17. Structs don't implement Access

Never use map-access syntax (`changeset[:field]`, `struct[:field]`) on a struct. Structs don't implement the Access behaviour by default, so this raises at runtime. Access fields directly (`my_struct.field`) or via the proper API (`Ecto.Changeset.get_field(changeset, :field)`).

## 18. Don't `String.to_atom/1` on user input

`String.to_atom/1` on untrusted or user-controlled input is a memory-leak (atom table exhaustion) risk. Use `String.to_existing_atom/1`, keep it a string, or map to a known set.

## 19. Date/time: use the stdlib

Elixir's `Time`, `Date`, `DateTime`, and `Calendar` cover date/time manipulation. Never install additional dependencies for it, with one sanctioned exception: `date_time_parser` for parsing.

## 20. Never nest multiple modules in one file

Defining more than one module in a single `.ex` file invites cyclic dependencies and compilation ordering problems. One module per file.

## 21. Single-use module attributes live next to their use site

Module attributes can be declared anywhere before use, so put a single-use attribute directly above the function that uses it rather than at the top of the module. Conversely, an attribute is required when a compile-time-computed value (e.g. `inspect(SomeModule)`) goes into a function-head pattern match. Function calls aren't allowed in patterns, so don't try to inline them there.

## 22. `@spec` on public functions

Add `@spec` to public functions; don't spec private helpers. A spec often makes a `@doc` unnecessary. If the name and spec together tell the caller everything, skip the doc.

## 23. Prefer the conventional one-liner over hand-rolled equivalents

When the requirement is just "a unique string" (or similar), reach for the boring ecosystem-standard call, `Ecto.UUID.generate()`, not hand-rolled crypto/encoding like `Base.encode16(:crypto.strong_rand_bytes(8))`. A custom construction needs a requirement the conventional one can't meet (length limit, alphabet constraint), not a vague storage concern.

## 24. Comments and documentation

The full rule lives in the monorepo root CLAUDE.md under "Comments and Documentation". Follow it in every project, including ones outside that monorepo. The short version: only three kinds of comment are allowed (a short module-level doc, an API doc on a public function where the contract isn't obvious, an inline comment on genuinely tricky code), default to none, never narrate the edit or restate the code, and use `@moduledoc false` for internal plumbing.
