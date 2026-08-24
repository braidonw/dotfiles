# Model delegation workflow

The main session runs on Fable and should spend its effort on planning, evaluating tradeoffs, reviewing results, and making final decisions. Delegate execution to the custom subagents in `~/.claude/agents/` instead of doing it inline:

- **`chore`** (Sonnet, low effort). Mechanical, fully-specified work: renames, repetitive multi-site edits, fixture updates, formatting.
- **`implement`** (Sonnet, high effort). Standard implementation of an agreed plan: write the code and tests, run them, report back. This is the default for most coding work.
- **`implement-hard`** (Opus, xhigh effort). Reserve for genuinely subtle execution: tricky concurrency, cross-cutting refactors, performance-sensitive or data-risky changes.

Rules of thumb:
- Plan first in the main session (plan mode for anything non-trivial), then hand the agreed plan to the right agent with enough context to execute without guessing: relevant file paths, decisions already made, and how to verify.
- Do trivial edits (a one-file tweak, a quick fix mid-conversation) directly in the main session. Delegation overhead isn't worth it there.
- Review the agent's report and diff in the main session before declaring work done; final judgement stays with Fable. If an agent reports a plan conflict, resolve it in the main session and re-delegate.
- Independent tasks from one plan can go to multiple agents in parallel.

# Planning

Before doing any non-trivial work or developing a plan, when there are any areas you are unclear about (an ambiguity in the requirements, a choice between designs, a tradeoff), invoke the `grilling` skill and put the questions to me through it, rather than guessing or asking ad hoc. Fold my answers back into the plan before implementation starts. Re-run grilling as often as needed until you have a clear understanding of the requirements.

# Linear

When starting work on a Linear issue, move it to In Progress (and assign it to me if unassigned). Don't move it any further. Linear moves it to In Review automatically when I create the PR.

# Git commits

Keep commit messages short: a one-line subject (~50-72 chars, imperative mood), plus at most a few body lines when the why genuinely needs stating. No exhaustive change lists, no test-plan sections, no attribution footers.

# PR descriptions

Keep them short. A ticket reference on its own line when there is one, then three parts:

1. One or two sentences on what the change is and why it was needed. Lead with the problem, not the diff.
2. A few brief bullets under a `What changed:` label, one line each. Describe the change in plain terms with no file paths, module names, function names, or line numbers. The diff already carries that detail, and prose that duplicates it goes stale.
3. One or two sentences under a `Notes:` label for what the reviewer needs. Where to start reviewing, known follow-ups, anything deliberately left out of scope.

Never put backticks around a file, module, or function name in a PR body. No test-plan sections, no exhaustive change lists, no attribution footers.

Depth belongs in the review conversation, not the description. If something genuinely needs a paragraph of mechanism to review safely, say so in the notes and let the reviewer ask.

# Worktrees

Never create a git worktree unless I explicitly ask for one. Work on a branch in the checkout the session started in.

Background jobs enforce worktree isolation for edits. When that forces a worktree, finish by committing to a normally named branch and removing the worktree with `git worktree remove`, which keeps the branch. Report the branch name so I can check it out in my main checkout.

# Writing style

Everything here applies to every word you write, not just code. Chat replies, markdown, plans, commit messages, PR descriptions, code comments, moduledocs, docstrings, log messages, and strings.

**No dashes as punctuation. Use a full stop.**

- Never use em or en dashes, or other non-ASCII typography (curly quotes, ellipsis characters). In strings exposed to external consumers (API responses, webhook payloads, partner-facing copy) plain ASCII is a hard requirement, not a preference.
- Avoid the ASCII substitutes for the same job. No ` - `, no ` -- `, no hyphen standing in as a pause between clauses.
- Almost every dash is a full stop in disguise. Split the sentence.
- Hyphens stay correct in compound words (`user-facing`, `well-formed`), CLI flags, ranges, and identifiers. The rule is about dashes used as punctuation between clauses.

**No colons as punctuation either. Use a full stop.**

- Don't join two clauses with a colon where a full stop would do. "A crash is a loud signal: an elaborate branch for it is dead code" should be two sentences.
- A colon after a label is fine, because that's structure rather than punctuation. Commit prefixes (`feat:`, `fix:`), a bold rule heading (`**Units live in names**: ...`), and lead-ins like `Reason:` or `Note:` all stay.
- In a list of term-plus-description items, the label colon is the right mark and a full stop is wrong. Write ``- `SuperApi.Chronicle.Pipeline`: audit log``, not ``- `SuperApi.Chronicle.Pipeline`. Audit log``. The description is a fragment, so a full stop dresses it up as a sentence it isn't.
- A colon introducing a list or an enumeration also stays.
- Colons in code are syntax. Atoms, map keys, and keyword lists are untouched by this.

Never swap one banned mark for the other. A dash doesn't become a colon and a colon doesn't become a dash. Both become a full stop.

Short sentences are good in their own right. Don't pad a sentence to avoid ending one, and don't recombine two clean sentences into a longer one.

**Markdown prose is unwrapped. One paragraph is one line.**

- Never hard-wrap prose to a column width. A paragraph is a single long line, and the editor or GitHub soft-wraps it for the reader. This covers PR descriptions, plans, handover docs, issue and ticket bodies, review write-ups, and any markdown file.
- Hard-wrapped prose is miserable to edit, because changing one sentence forces a manual reflow of the whole paragraph and produces a diff that touches every line of it.
- Line breaks that carry structure stay. Headings, list items, table rows, code fences, and the blank line between paragraphs are all real and none of them are affected by this.
- Commit messages are the exception. Git tooling does not soft-wrap, so keep wrapping those bodies at roughly 72 columns per the Git commits section.

# Elixir
Write clear, concise and idiomatic Elixir code with a focus on clarity and maintainability.
Avoid building any unnecessary features or functionality.
Ask me if you want me to clarify any of my instructions or if you want me to choose from various architectures or designs.
Please don't write any Demo or example code for anything you create for me.
Run tests with each project's `just test <file>` (or `just test-all` where it exists). To run something else in the container, check that project's `justfile` for the recipe. In super_api it's `just bash-run <command>`; elsewhere it's usually an interactive `just bash`.

**Tiger Style (safety, then performance, then developer experience)**. The full essay lives in the `tiger-style` skill; these are the operative rules:
- **Bound everything that can grow.** Every external call on a user-facing path has an explicitly chosen timeout; every producer/consumer pair has back-pressure (GenStage demand, Broadway, Oban, `Task.async_stream` with `max_concurrency`, never unbounded casts into a slow GenServer); every retry has a ceiling; every external input (list length, payload, batch) has a size limit enforced loudly.
- **No `_ ->` catch-all clauses** on `case` expressions over our own enums, statuses, or tagged tuples. Exhaustive matching makes new variants surface as crashes at every site that must handle them.
- **Processes are units of concurrency, not code organization.** Stateless logic lives in plain modules; don't wrap it in a GenServer (a single process is a serialization point). Read-heavy shared state goes in ETS, not behind a GenServer.
- **Design supervision as failure domains.** State that must survive a crash lives outside the crashing process (DB, ETS); a process's state must be rebuildable on restart. `try`/`rescue` only at genuine boundaries to code we don't control, never as insulation around our own logic.
- **Don't duplicate state.** One authoritative home per fact; everything else derives from it (no assign mirroring another assign, no boolean column shadowing a status column).
- **Count your queries.** One round trip beats N: `Repo.insert_all` over N inserts, preloads/joins over N+1s, an aggregate over counting rows in Elixir.
- **Units live in names**: `timeout_ms`, `ttl_seconds`, `amount_cents`.

**Nesting conditionals: two levels is fine, three is not**: One `case` inside another (or a `case` inside a `with`/`if`) is acceptable when it keeps a short chain of related steps readable in one place. Don't extract a helper just to eliminate a second level if the extraction would scatter the flow across functions for no gain in clarity. Go beyond two levels almost never, only when every alternative is genuinely worse. At three-plus levels, extract the inner levels into small helper functions so function names describe what each step does; function-head pattern matching is the natural way to fan out from there. Extracted helpers should do something meaningful (make a call, do real work); don't extract a helper whose only job is to map one value to another (see next rule).
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

**Inline error-to-outcome mappings in the `case`**: Don't extract a helper function whose only job is to rename one tagged tuple into another (e.g. `defp build_error_to_outcome(:not_found), do: {:cancel, :employee_not_found}`). Put the clause directly in the calling `case`. The mapping is right there at the site, and a stand-alone helper that just renames a value doesn't earn its keep. A small amount of duplication across two call sites is preferable to chasing a one-line indirection. Helper functions are for steps that do real work (a `Repo` call, a transform, branching), not for renaming.

**Avoid `with`/`else` for error translation**: When chaining multiple `{:ok, _} | {:error, _}` calls, prefer explicit `case` statements (a two-level nested `case`, or per-step helper functions for longer chains) with the error-to-outcome clauses inlined. An `else` clause on a `with` block conflates errors from different sources. Readers can't tell which step produced which error, and adding a new failure mode to one step means inspecting every `else` clause to see whether it's already handled. A `with` block with no `else` is fine when the unmatched value is returned verbatim.
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

**Plain returns over invented tags**: When an internal helper's outcomes all collapse to the same caller behaviour, return a plain value (a boolean from a `?`-named predicate, an integer with a documented sentinel) and branch with `if`. Don't mint tagged atoms (`:acquired | :not_acquired`) or `{:ok, _} | :error` shapes the caller never distinguishes. Tagged tuples are for outcomes the caller handles differently. (Watch the sentinel choice. `nil >= n` is truthy under Elixir term ordering. Return `0`, not `nil`, when the caller compares.)

**Don't extract single-caller wrappers**: A private function with one caller whose only job is to pin a return value or host a `rescue` isn't earning its keep. Use a function-level `rescue` and an explicit trailing return in the public function instead. Extraction is for branching steps that do real work.

**Pass along data the caller already has. Don't re-fetch it downstream**: Before adding a lookup function so a downstream step can derive X from an id (e.g. `fetch_employer_for_employee/1` to get an ABN inside a policy check), check whether the call sites already hold X (a preloaded association, a value from an earlier query). If they do, thread the value through function arguments, or through Oban job args at enqueue time. Pass just the field needed (the ABN, not the whole employer). The re-fetch costs an extra query, mints a single-caller public function on a context, and drags in a not-found branch that can't legitimately fire. The exception is freshness. Re-check downstream any state that may genuinely change between the caller and the downstream step (e.g. an eligibility window re-checked inside a worker); thread stable identifiers and values.

**No silent failures**: e.g. don't do `plan = Map.get(plan_map, frequency, "starter")`. Instead, fail loudly with an 'unknown frequency' error.

**Don't handle errors that can't happen. Use the raising variant and let it crash**: When an operation only returns `{:error, _}` for malformed or programmer-error input that a well-formed call site never produces, don't write a `case`/log/`log_and_notify`/swallow branch for that error. Prefer the bang variant (`Oban.insert!`, `Repo.insert!`, `Jason.decode!` on data you built) and let it raise if the "impossible" ever occurs. A crash is a loud, located, debuggable signal; an elaborate branch for an unreachable error is dead code that obscures the happy path and misleads readers into thinking the failure is expected and handled. This is the flip side of "no silent failures". Both say surface the unexpected loudly rather than papering over it. `Oban.insert` followed by `{:error, _} -> log(...); :ok` is a *silent* failure dressed up as handling. Distinguish genuine runtime errors (network down, not-found, validation of *user* input, a race) from errors that only fire on a bug at the call site. You match and handle the first kind. You let the second kind raise. If a raising call sits inside a caller's transaction, raising rolls the work back atomically, which is usually what you want. Watch for: a `case Op.insert(...)` whose `{:error, _}` arm just logs and returns `:ok`; "outcome reporter" helpers built solely to log both arms of a call that won't fail.

**Presence guaranteed by DB constraints is not a runtime error**: A NOT NULL foreign key with a required association (an employee always has an employer), or a row the same transaction just inserted, means the schema guarantees the data exists. In that case don't return `{:error, :not_found}` for its absence or give callers a soft skip branch. Use `Repo.one!`/`Repo.get!` and let it crash. Absence means a bug or corrupted data, and a soft not-found both hides that signal and conflates it with ordinary cases like "caller passed a bad id" (which, when the id comes from trusted internal plumbing such as job args built from a real record, is itself a can't-happen, same treatment). This is a special case of "don't handle errors that can't happen" above. Genuine not-founds (user-supplied ids, optional associations, records that can be deleted out from under you) keep the tuple form.

**A function whose contract is to raise carries a `!` suffix**: If a function is designed to raise on failure rather than return `{:error, _}`, name it with a trailing `!` (`enqueue!`, `fetch_user!`, `charge!`). This mirrors the stdlib pairing (`Map.fetch`/`Map.fetch!`, `Repo.insert`/`Repo.insert!`). The bang tells every call site "this raises, so handle it upstream or let it crash." It applies even with no tuple-returning sibling. A standalone helper that wraps a raising call (`Oban.insert!`) and never returns `{:error, _}` still gets the `!`. This is about the *contract* (a function meant to raise), not about whether some code path could theoretically raise a `MatchError` or `Repo` connection error. Don't bang every function, only those whose documented behaviour is to raise on the failure a caller would otherwise pattern-match.

**Oban enqueue helpers: bare `new`, log context in `meta`**: Inside a worker module, build the job with the `new/2` that `use Oban.Worker` defines (`args |> new(...)`), never `__MODULE__.new(...)`; the module-qualified form is for external callers, and inside the module it's noise. Put identifiers wanted for observability (the ids you'd want attached to log lines, or visible in Oban Web when a job fails: employee_id, onboarding_session_id, etc.) in the job's `meta` at enqueue time. `meta` must be a map (`meta: %{employee_id: id}`). A keyword list fails Oban's `:map` cast and the insert raises. Keep the split clean: `args` carries what `perform/1` consumes; `meta` carries trace/log context, so `perform` never pattern-matches fields it only logs.

**Comments and docs**: the rule lives in the monorepo root `CLAUDE.md` under "Comments and Documentation" (only three kinds are allowed, default to none, never narrate the edit, `@moduledoc false` for internal plumbing). Follow it in every project, including ones outside that monorepo.

**`@spec` on public functions**: Add `@spec` to public functions; don't spec private helpers. A spec often makes a `@doc` unnecessary. If the name and spec together tell the caller everything, skip the doc.

**Single-use module attributes live next to their use site**: Module attributes can be declared anywhere before use, so put a single-use attribute directly above the function that uses it rather than at the top of the module. Conversely, an attribute is *required* when a compile-time-computed value (e.g. `inspect(SomeModule)`) goes into a function-head pattern match. Function calls aren't allowed in patterns, so don't try to inline them there.

**Prefer the conventional one-liner over hand-rolled equivalents**: When the requirement is just "a unique string" (or similar), reach for the boring ecosystem-standard call, `Ecto.UUID.generate()`, not hand-rolled crypto/encoding like `Base.encode16(:crypto.strong_rand_bytes(8))`. A custom construction needs a requirement the conventional one can't meet (length limit, alphabet constraint), not a vague storage concern.

## Maintainability & structure

- **Prefer deep modules.** The rule, the definition of interface, and the deletion test live in the monorepo root `CLAUDE.md` under "Module Design". Follow it in every project, including ones outside that monorepo. The `codebase-design` skill carries the full vocabulary when you need it. The rule below is this rule's Elixir form.
- **Context modules are the domain's front door.** Stated at the end of root's "Module Design" and expanded for queries in `super_api/CLAUDE.md`. The sub-rule below is the part neither of them covers.
  - **Demote context functions whose only callers are inside the domain.** When touching a context, check whether any of its `def`s are called only from within the domain (e.g. an Oban worker in the same context). Grep the callers, don't assume. If so, move the function into its caller as a `defp` (transitively: if that leaves another context `def` with only internal callers, fold it too). Being directly unit-tested does not make a function public API. When the caller's integration tests already drive every branch, delete the direct unit tests as redundant; otherwise move the missing cases up to the caller's tests. While moving, drop defensive code the narrowed call site makes unreachable (e.g. a `Repo.preload` the caller's load already guarantees).
- **Extract genuinely duplicated logic that will drift**. The same multi-step computation, query shape, or validation copy-pasted across functions will fall out of sync. Hold this against the inline-error-mapping rule above, which prefers a little duplication over a one-line indirection. Two things that merely look similar but change for different reasons should stay separate. Flag duplication that will co-evolve, not incidental similarity.
- **Flag overly complex code paths** as a prompt to decompose: long functions doing several jobs (split into named steps, same move as the nested-`case` rule), deep nesting / high branching, 4+ positional arguments (reach for a struct or keyword opts), boolean/flag arguments that fork behaviour at the call site (two named functions usually read better), and primitive obsession where a small struct would name the fields. These are judgement prompts, not metrics. A flat 40-line sequence is fine; a 15-line one nested three deep is not.
- **Names should reveal intent**. Flag misleading names (a `fetch_*` that mutates, a `*?` that returns a non-boolean) and generic ones (`data`, `handle`, `process` on a domain function).

## Testing
Focus on integration tests over plain unit tests unless there is some complex behaviour we want to ensure works as intended. Test through the public function of the context (not private helpers), use the real DB via the sandbox + ExMachina factories, and mock only true external boundaries with Mox.

- **Cover the cases that matter**, not just lines: the happy path (asserting on the real outcome, e.g. persisted record, returned value, side effect), every error branch the code deliberately handles (`{:error, _}`, not-found, validation failure, timeout), and representative edges/boundaries. New logic, especially a new error branch, that ships with no test driving it is a gap worth flagging.
- **A test must actually test something**. It should fail if the behaviour breaks. Watch for tautological tests (stub a mock to return X, then assert it returned X; that tests Mox, not your code), assert-nothing tests (`assert result`, or only "it didn't raise"), and over-mocking the system under test. Mock the boundaries, exercise the real thing in between.
- **Remove lower-level tests that duplicate integration coverage**. If an integration test already exercises a path end to end, a unit test asserting the same behaviour at a smaller scale is redundant maintenance cost. Keep it only if it covers a distinct edge or error branch the integration test skips.

# Project guidelines (Elixir projects)
HTTP Requests: Use the already included and available `:req` (`Req`) library for HTTP requests
Behaviours for API Clients: Define behaviours for API clients to allow easy mocking
Error Handling: Handle network failures and unexpected responses gracefully
Timeouts: Set explicit timeouts on external calls in user-facing / inline paths. In background jobs the library default is usually right. Only override it for a measured reason, and match how existing call sites in the codebase handle it before deviating
Circuit Breakers: Use circuit breakers for critical external services

## Phoenix Best Practices
LiveView-First: Use LiveView as the primary UI technology
Function Components: Use function components for reusable UI elements
PubSub for Real-time: Use Phoenix PubSub for real-time features
Thin Controllers: Keep controllers thin, delegating business logic to contexts
Security First: Always consider security implications (CSRF, XSS, etc.)

## General Elixir guidelines
- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- `Task.async_stream(collection, callback, options)` is the tool for the bounded-concurrency rule above. The majority of times you will want to pass `timeout: :infinity` as an option
