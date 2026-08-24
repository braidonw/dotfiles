# Elixir
Write clear, concise and idiomatic Elixir code with a focus on clarity and maintainability.
Avoid building any unnecessary features or functionality.
Ask me if you want me to clarify any of my instructions or if you want me to choose from various architectures or designs.
Please don't write any Demo or example code for anything you create for me.
Tests will need to be run using the `just bash-run` command

**Tiger Style (safety, then performance, then developer experience)** — the full essay lives in the `tiger-style` skill; these are the operative rules:
- **Bound everything that can grow.** Every external call on a user-facing path has an explicitly chosen timeout; every producer/consumer pair has back-pressure (GenStage demand, Broadway, Oban, `Task.async_stream` with `max_concurrency` — never unbounded casts into a slow GenServer); every retry has a ceiling; every external input (list length, payload, batch) has a size limit enforced loudly.
- **No `_ ->` catch-all clauses** on `case` expressions over our own enums, statuses, or tagged tuples — exhaustive matching makes new variants surface as crashes at every site that must handle them.
- **Processes are units of concurrency, not code organization.** Stateless logic lives in plain modules; don't wrap it in a GenServer (a single process is a serialization point). Read-heavy shared state goes in ETS, not behind a GenServer.
- **Design supervision as failure domains.** State that must survive a crash lives outside the crashing process (DB, ETS); a process's state must be rebuildable on restart. `try`/`rescue` only at genuine boundaries to code we don't control — never as insulation around our own logic.
- **Don't duplicate state.** One authoritative home per fact; everything else derives from it (no assign mirroring another assign, no boolean column shadowing a status column).
- **Count your queries.** One round trip beats N: `Repo.insert_all` over N inserts, preloads/joins over N+1s, an aggregate over counting rows in Elixir.
- **Units live in names**: `timeout_ms`, `ttl_seconds`, `amount_cents`.

**No em dashes — plain ASCII in code**: Never use em/en dashes or other non-ASCII typography (curly quotes, ellipsis characters) in code you write: strings, comments, moduledocs, docstrings, log messages. This matters most for strings exposed to external consumers (API responses, webhook payloads, partner-facing copy), which must be plain ASCII. Rephrase with a colon, hyphen, parentheses, or a new sentence instead. (Prose in chat/markdown replies is fine.)

**Nesting conditionals: two levels is fine, three is not**: One `case` inside another (or a `case` inside a `with`/`if`) is acceptable when it keeps a short chain of related steps readable in one place — don't extract a helper just to eliminate a second level if the extraction would scatter the flow across functions for no gain in clarity. Go beyond two levels almost never — only when every alternative is genuinely worse. At three-plus levels, extract the inner levels into small helper functions so function names describe what each step does; function-head pattern matching is the natural way to fan out from there. Extracted helpers should do something meaningful (make a call, do real work); don't extract a helper whose only job is to map one value to another (see next rule).
```elixir
# Fine — two levels, short and readable in one place
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

**Inline error-to-outcome mappings in the `case`**: Don't extract a helper function whose only job is to rename one tagged tuple into another (e.g. `defp build_error_to_outcome(:not_found), do: {:cancel, :employee_not_found}`). Put the clause directly in the calling `case` — the mapping is right there at the site, and a stand-alone helper that just renames a value doesn't earn its keep. A small amount of duplication across two call sites is preferable to chasing a one-line indirection. Helper functions are for steps that do real work (a `Repo` call, a transform, branching), not for renaming.

**Avoid `with`/`else` for error translation**: When chaining multiple `{:ok, _} | {:error, _}` calls, prefer explicit `case` statements (a two-level nested `case`, or per-step helper functions for longer chains) with the error-to-outcome clauses inlined. An `else` clause on a `with` block conflates errors from different sources — readers can't tell which step produced which error, and adding a new failure mode to one step means inspecting every `else` clause to see whether it's already handled. A `with` block with no `else` is fine when the unmatched value is returned verbatim.
```elixir
# Preferred — case with inline error clauses
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

# Not preferred — with/else
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

**Plain returns over invented tags**: When an internal helper's outcomes all collapse to the same caller behaviour, return a plain value — a boolean from a `?`-named predicate, an integer with a documented sentinel — and branch with `if`. Don't mint tagged atoms (`:acquired | :not_acquired`) or `{:ok, _} | :error` shapes the caller never distinguishes. Tagged tuples are for outcomes the caller handles differently. (Watch the sentinel choice: `nil >= n` is truthy under Elixir term ordering — return `0`, not `nil`, when the caller compares.)

**Don't extract single-caller wrappers**: A private function with one caller whose only job is to pin a return value or host a `rescue` isn't earning its keep — use a function-level `rescue` and an explicit trailing return in the public function instead. Extraction is for branching steps that do real work.

**Pass along data the caller already has — don't re-fetch it downstream**: Before adding a lookup function so a downstream step can derive X from an id (e.g. `fetch_employer_for_employee/1` to get an ABN inside a policy check), check whether the call sites already hold X — a preloaded association, a value from an earlier query. If they do, thread the value through function arguments, or through Oban job args at enqueue time. Pass just the field needed (the ABN, not the whole employer). The re-fetch costs an extra query, mints a single-caller public function on a context, and drags in a not-found branch that can't legitimately fire. The exception is freshness: re-check downstream any state that may genuinely change between the caller and the downstream step (e.g. an eligibility window re-checked inside a worker); thread stable identifiers and values.

**No silent failures**: e.g. don't do `plan = Map.get(plan_map, frequency, "starter")` — instead fail loudly with an 'unknown frequency' error.

**Don't handle errors that can't happen — use the raising variant and let it crash**: When an operation only returns `{:error, _}` for malformed or programmer-error input that a well-formed call site never produces, don't write a `case`/log/`log_and_notify`/swallow branch for that error. Prefer the bang variant (`Oban.insert!`, `Repo.insert!`, `Jason.decode!` on data you built) and let it raise if the "impossible" ever occurs. A crash is a loud, located, debuggable signal; an elaborate branch for an unreachable error is dead code that obscures the happy path and misleads readers into thinking the failure is expected and handled. This is the flip side of "no silent failures": both say surface the unexpected loudly rather than papering over it — `Oban.insert` followed by `{:error, _} -> log(...); :ok` is a *silent* failure dressed up as handling. Distinguish genuine runtime errors (network down, not-found, validation of *user* input, a race) — those you match and handle — from errors that only fire on a bug at the call site, which you let raise. If a raising call sits inside a caller's transaction, raising rolls the work back atomically, which is usually what you want. Watch for: a `case Op.insert(...)` whose `{:error, _}` arm just logs and returns `:ok`; "outcome reporter" helpers built solely to log both arms of a call that won't fail.

**Presence guaranteed by DB constraints is not a runtime error**: When the schema guarantees the data exists — a NOT NULL foreign key with a required association (an employee always has an employer), a row the same transaction just inserted — don't return `{:error, :not_found}` for its absence or give callers a soft skip branch. Use `Repo.one!`/`Repo.get!` and let it crash: absence means a bug or corrupted data, and a soft not-found both hides that signal and conflates it with ordinary cases like "caller passed a bad id" (which, when the id comes from trusted internal plumbing such as job args built from a real record, is itself a can't-happen — same treatment). This is a special case of "don't handle errors that can't happen" above. Genuine not-founds — user-supplied ids, optional associations, records that can be deleted out from under you — keep the tuple form.

**A function whose contract is to raise carries a `!` suffix**: If a function is designed to raise on failure rather than return `{:error, _}`, name it with a trailing `!` — `enqueue!`, `fetch_user!`, `charge!`. This mirrors the stdlib pairing (`Map.fetch`/`Map.fetch!`, `Repo.insert`/`Repo.insert!`): the bang tells every call site "this raises, so handle it upstream or let it crash." It applies even with no tuple-returning sibling — a standalone helper that wraps a raising call (`Oban.insert!`) and never returns `{:error, _}` still gets the `!`. This is about the *contract* (a function meant to raise), not about whether some code path could theoretically raise a `MatchError` or `Repo` connection error — don't bang every function, only those whose documented behaviour is to raise on the failure a caller would otherwise pattern-match.

**Oban enqueue helpers: bare `new`, log context in `meta`**: Inside a worker module, build the job with the `new/2` that `use Oban.Worker` defines — `args |> new(...)` — never `__MODULE__.new(...)`; the module-qualified form is for external callers, and inside the module it's noise. Put identifiers wanted for observability (the ids you'd want attached to log lines, or visible in Oban Web when a job fails: employee_id, onboarding_session_id, etc.) in the job's `meta` at enqueue time. `meta` must be a map (`meta: %{employee_id: id}`) — a keyword list fails Oban's `:map` cast and the insert raises. Keep the split clean: `args` carries what `perform/1` consumes; `meta` carries trace/log context, so `perform` never pattern-matches fields it only logs.

**Comments and docs: only three kinds are allowed**. Default to writing no comment at all — most code should carry none. The only permitted forms:
1. **Short `@moduledoc`s** — a brief overview of what the module is for and where it sits in the domain (a few sentences at most). Never enumerate the module's functions, describe its internals, list its callers, or restate implementation details — that's what the code and "find references" are for, and it rots the moment the module changes. For internal plumbing modules (workers, helpers, submodules not meant to be called from outside their domain), `@moduledoc false` is the right choice — don't write filler prose just to have a moduledoc.
2. **`@doc` on public functions, only where needed** — when the contract isn't obvious from the name, args, and return shape (surprising behaviour, units, side effects, what `{:error, _}` values mean). A well-named `fetch_user/1` needs no `@doc`. Never `@doc` private functions.
3. **Inline comments on genuinely tricky code** — a constraint, invariant, workaround, or non-obvious decision that the code cannot express (e.g. "Stripe requires idempotency keys stable across retries"). If the code path is straightforward, no comment.

Never write a comment that restates what the code already says — no `# performs foo on the args` above `def foo`, no narrating the next line, no section banners, no annotating self-explanatory constructs. The test: if deleting the comment loses nothing but a paraphrase of the code, it should not exist. Prefer a clearer name or extracted function over a comment explaining an unclear one.

**No changelog or motivation-of-change comments**: Never write a comment that narrates the edit, its motivation, or prior behaviour — "previously...", "this used to...", "changed this to fix...", "that combination previously tripped `:on_replace: :raise`". Why a *change* was made belongs in the commit message and PR description, not the source: a comment describes the code as it stands now, never the diff that produced it. This is narrower than (3)'s allowance for a present-tense constraint or invariant (the Stripe example) — state the rule that still governs the code, never the bug the change fixed. If the only justification you can write for a comment starts with a past-tense verb about the code, delete it.

**`@spec` on public functions**: Add `@spec` to public functions; don't spec private helpers. A spec often makes a `@doc` unnecessary — if the name and spec together tell the caller everything, skip the doc.

**Single-use module attributes live next to their use site**: Module attributes can be declared anywhere before use, so put a single-use attribute directly above the function that uses it rather than at the top of the module. Conversely, an attribute is *required* when a compile-time-computed value (e.g. `inspect(SomeModule)`) goes into a function-head pattern match — function calls aren't allowed in patterns, so don't try to inline them there.

**Prefer the conventional one-liner over hand-rolled equivalents**: When the requirement is just "a unique string" (or similar), reach for the boring ecosystem-standard call — `Ecto.UUID.generate()` — not hand-rolled crypto/encoding like `Base.encode16(:crypto.strong_rand_bytes(8))`. A custom construction needs a requirement the conventional one can't meet (length limit, alphabet constraint), not a vague storage concern.

## Maintainability & structure

- **Context modules are the domain's front door.** The top-level module named after a domain (`accounts.ex` → `SuperApi.Accounts`) should expose only functions meant to be called from outside the domain. Internal plumbing should be `defp` or live in a clearly-internal submodule — every `def` on a context is a promise to the rest of the codebase, so keep the public surface tight. Don't reach past the front door from outside (a controller calling a context's schema queries or internal submodules directly); go through the context's public functions.
  - **Demote context functions whose only callers are inside the domain.** When touching a context, check whether any of its `def`s are called only from within the domain (e.g. an Oban worker in the same context) — grep the callers, don't assume. If so, move the function into its caller as a `defp` (transitively: if that leaves another context `def` with only internal callers, fold it too). Being directly unit-tested does not make a function public API — when the caller's integration tests already drive every branch, delete the direct unit tests as redundant; otherwise move the missing cases up to the caller's tests. While moving, drop defensive code the narrowed call site makes unreachable (e.g. a `Repo.preload` the caller's load already guarantees).
- **Extract genuinely duplicated logic that will drift** — the same multi-step computation, query shape, or validation copy-pasted across functions will fall out of sync. Hold this against the "a little duplication beats the wrong abstraction" rule above: two things that merely look similar but change for different reasons should stay separate. Flag duplication that will co-evolve, not incidental similarity.
- **Flag overly complex code paths** as a prompt to decompose: long functions doing several jobs (split into named steps — same move as the nested-`case` rule), deep nesting / high branching, 4+ positional arguments (reach for a struct or keyword opts), boolean/flag arguments that fork behaviour at the call site (two named functions usually read better), and primitive obsession where a small struct would name the fields. These are judgement prompts, not metrics — a flat 40-line sequence is fine; a 15-line one nested three deep is not.
- **Names should reveal intent** — flag misleading names (a `fetch_*` that mutates, a `*?` that returns a non-boolean) and generic ones (`data`, `handle`, `process` on a domain function).

## Testing
Focus on integration tests over plain unit tests unless there is some complex behaviour we want to ensure works as intended. Test through the public function of the context (not private helpers), use the real DB via the sandbox + ExMachina factories, and mock only true external boundaries with Mox.

- **Cover the cases that matter**, not just lines: the happy path (asserting on the real outcome — persisted record, returned value, side effect), every error branch the code deliberately handles (`{:error, _}`, not-found, validation failure, timeout), and representative edges/boundaries. New logic — especially a new error branch — that ships with no test driving it is a gap worth flagging.
- **A test must actually test something** — it should fail if the behaviour breaks. Watch for tautological tests (stub a mock to return X, then assert it returned X — that tests Mox, not your code), assert-nothing tests (`assert result`, or only "it didn't raise"), and over-mocking the system under test. Mock the boundaries, exercise the real thing in between.
- **Remove lower-level tests that duplicate integration coverage** — if an integration test already exercises a path end to end, a unit test asserting the same behaviour at a smaller scale is redundant maintenance cost. Keep it only if it covers a distinct edge or error branch the integration test skips.

### Running super_api tests from a git worktree
`just bash-run` / `just test` fail in a worktree (e.g. `code-wt-1/super_api`) because the worktree spins up its own Compose project (`code-wt-1_default`) that can't reuse the main checkout's `postgres` container (name conflict), can't reach `postgres`/`redis` by DNS (separate network), and has no Bitwarden secrets (the entrypoint runs `bws run` and needs `BWS_ACCESS_TOKEN`/`BWS_PROJECT_ID`, plus host-passthrough vars like `XERO_CLIENT_ID` that a non-interactive shell lacks). The workaround borrows the already-running main checkout's container env + shared service containers:

1. **Capture the main container's resolved env** (has `BWS_*` and all host-passthrough vars):
   `docker exec code-super-api-1 env > "$TMPENV"`  (`code-super-api-1` = main checkout's running container)
2. **Attach the shared services to the worktree network** with the aliases the test config hardcodes (`postgres`, `redis`):
   `docker network connect --alias postgres code-wt-1_default postgres`
   `docker network connect --alias redis code-wt-1_default code-redis-1`
3. **Run the test** with `--no-deps` (don't start a conflicting postgres) and the captured env as `-e` flags (skip `PATH HOME HOSTNAME PWD SHLVL TERM _`), keeping the normal entrypoint so `bws run` resolves the Bitwarden secrets:
   `docker compose --env-file ../.env --env-file .env -f ../docker-compose.shared.yml -f docker-compose.development.yml run --rm --no-deps -e KEY=VAL ... super-api mix test <path>`
4. **Clean up** (leave nothing attached): `docker network disconnect code-wt-1_default postgres`, `... code-redis-1`, `rm -f "$TMPENV"`.

Notes:
- Names are derived: worktree dir `code-wt-1` → network `code-wt-1_default`; main project `code` → containers `code-super-api-1`, `code-redis-1`, `postgres`. Adjust to the actual dir/project names.
- `--no-deps` skips **redis** too — if you forget step 2's redis attach, membership/cache tests fail with `Redix.ConnectionError{reason: :closed}` (a red herring, not a real failure).
- For a pure `mix compile --warnings-as-errors` (no DB/secrets needed) you can skip all of this and just bypass the entrypoint: `... run --rm --no-deps --entrypoint mix super-api compile --warnings-as-errors`.

# Project guidelines
HTTP Requests: Use the already included and available `:req` (`Req`) library for HTTP requests
Behaviours for API Clients: Define behaviours for API clients to allow easy mocking
Error Handling: Handle network failures and unexpected responses gracefully
Timeouts: Set explicit timeouts on external calls in user-facing / inline paths. In background jobs the library default is usually right — only override it for a measured reason, and match how existing call sites in the codebase handle it before deviating
Circuit Breakers: Use circuit breakers for critical external services

## Phoenix Best Practices
LiveView-First: Use LiveView as the primary UI technology
Function Components: Use function components for reusable UI elements
PubSub for Real-time: Use Phoenix PubSub for real-time features
Thin Controllers: Keep controllers thin, delegating business logic to contexts
Security First: Always consider security implications (CSRF, XSS, etc.)

## General Elixir guidelines
- `with` is fine for chaining `{:ok, _}` / `{:error, _}` operations when the unmatched value is returned verbatim (no `else`); otherwise prefer explicit `case` (see the `with`/`else` rule above)
- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option
