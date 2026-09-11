# Correctness, architecture, performance and security

Style lives in `style-and-idioms.md`. This file covers everything that can break in production or make the system harder to operate.

## Table of contents

1. Tiger Style operative rules
2. Error handling and resilience for external calls
3. Behaviours for mockable clients
4. HTTP via `Req`
5. OTP primitives
6. Ecto
7. Oban
8. Phoenix / LiveView
9. Performance
10. Security

---

## 1. Tiger Style operative rules

Safety, then performance, then developer experience. The full essay lives in the `tiger-style` skill; these are the operative rules:

- **Bound everything that can grow.** Every external call on a user-facing path has an explicitly chosen timeout; every producer/consumer pair has back-pressure (GenStage demand, Broadway, Oban, `Task.async_stream` with `max_concurrency`, never unbounded casts into a slow GenServer); every retry has a ceiling; every external input (list length, payload, batch) has a size limit enforced loudly.
- **No `_ ->` catch-all clauses** on `case` expressions over our own enums, statuses, or tagged tuples. Exhaustive matching makes new variants surface as crashes at every site that must handle them. (Messages arriving across a process boundary are the opposite situation. A LiveView or GenServer receiving messages it didn't ask for may need a catch-all `handle_info/2`; see the project CLAUDE.md.)
- **Processes are units of concurrency, not code organization.** Stateless logic lives in plain modules; don't wrap it in a GenServer (a single process is a serialization point). Read-heavy shared state goes in ETS, not behind a GenServer.
- **Design supervision as failure domains.** State that must survive a crash lives outside the crashing process (DB, ETS); a process's state must be rebuildable on restart. `try`/`rescue` only at genuine boundaries to code we don't control, never as insulation around our own logic.
- **Don't duplicate state.** One authoritative home per fact; everything else derives from it (no assign mirroring another assign, no boolean column shadowing a status column).
- **Count your queries.** One round trip beats N: `Repo.insert_all` over N inserts, preloads/joins over N+1s, an aggregate over counting rows in Elixir.
- **Units live in names**: `timeout_ms`, `ttl_seconds`, `amount_cents`.

## 2. Error handling and resilience for external calls

Any call leaving the BEAM (HTTP, SFTP, third-party API, DB over network) must assume failure:

- **Timeouts on user-facing / inline paths are mandatory.** Set an explicit timeout on every external call there; a hung dependency otherwise stalls a process indefinitely. In background jobs the library default is usually right. Only override it for a measured reason, and match how existing call sites in the codebase handle it before deviating.
- **Handle network failures and unexpected responses gracefully.** Match on `{:error, _}`, non-2xx statuses, and malformed bodies. Don't assume a 200 with the shape you expect.
- **Circuit breakers** for critical external services, so one struggling dependency doesn't cascade. A new critical integration with no breaker deserves a hard look.

## 3. Behaviours for mockable clients

API clients for real external services should be defined behind a `@behaviour` so they can be swapped for a Mox mock in tests. That means a `@callback` definition and a config/option that selects the implementation.

Apply this with restraint. A new client for a critical external integration (ATO, Xero, SuperStream, a payment provider) called concretely with no seam needs one, as does code that can't be tested because the HTTP call is hard-wired. A one-off internal fetch, a script, or a call that isn't on a path anyone needs to mock doesn't; that's ceremony for its own sake. The trigger is "this should be tested and can't be", not "this touches the network".

## 4. HTTP via `Req`

Use the already-included `Req` library for HTTP requests. New uses of `HTTPoison`, `Tesla`, `:hackney`, or raw `:httpc` need a documented reason.

## 5. OTP primitives

- `DynamicSupervisor`, `Registry`, and similar require a `name` in the child spec: `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then call `DynamicSupervisor.start_child(MyApp.MyDynamicSup, spec)`.
- `Task.async_stream(collection, callback, options)` is the tool for concurrent enumeration with back-pressure. The majority of times you will want `timeout: :infinity` as an option; the default 5s silently kills slow tasks, which is a silent failure.
- New long-running processes, Broadway pipelines, and supervisors must be registered in `Application.start/2`, with a test sandbox setup if they touch the DB or external HTTP (super_api convention).

## 6. Ecto

- **Transactions**: prefer `Repo.transact` (`SuperApi.Repo.transact` / `XonboardBackend.Repo.transact`) over `Ecto.Multi.new` for simple transactions. Reach for `Ecto.Multi` only when composing multiple dependent steps. A single-step `Ecto.Multi.new |> ... |> Repo.transaction` is the smell.
- **Queries have exactly one legal location**: a named function on the context module for the schema they query, alongside `fetch/1`, `load/1`, and the mutations. No dedicated `query.ex` modules, and no query rebuilt inline at a callsite. Before writing a query, check whether the context already has a function returning this data (call it), or one returning almost this (extend it with an `opts` keyword parameter rather than adding a sibling). The application layer (controllers, LiveViews, Oban workers, business logic modules) must never build a query directly. See the project CLAUDE.md for the full rationale.
- **Named bindings** within a query: `from(User, as: :user) |> where([user: user], ...)`, not positional bindings.
- **`fetch` vs `load`**: see `style-and-idioms.md` rule 17. `fetch/1` no preloads, `load/1` preloads.
- **Watch for N+1s**: a `Repo` call inside an `Enum.map` or comprehension over query results is usually a missing preload or a query that should be batched. Ties to Tiger Style's "count your queries".

## 7. Oban

- **Three layers, one responsibility each** (full rule in the monorepo root CLAUDE.md): the business logic module owns validation, computation, gating, and the action itself; the worker is plumbing (`enqueue` then `perform/1`, in that order in the file); calling code fire-and-forgets the worker's `enqueue`. A "should this happen" check in a worker or caller is a bug; move it to the business logic module.
- **Enqueue helpers**: inside a worker module, build the job with the `new/2` that `use Oban.Worker` defines (`args |> new(...)`), never `__MODULE__.new(...)`; the module-qualified form is for external callers. Put identifiers wanted for observability (ids you'd want on log lines or visible in Oban Web when a job fails: employee_id, onboarding_session_id, etc.) in the job's `meta` at enqueue time. `meta` must be a map (`meta: %{employee_id: id}`); a keyword list fails Oban's `:map` cast and the insert raises. Keep the split clean: `args` carries what `perform/1` consumes; `meta` carries trace/log context, so `perform` never pattern-matches fields it only logs.
- **Prefer `Oban.insert!` over handling an unreachable `{:error, _}`.** A statically-built job inserted from a well-formed call site doesn't fail validation, so a `case Oban.insert(...)` whose error arm logs and returns `:ok` defends against an error that can't happen and swallows it if it somehow does (see `style-and-idioms.md` rule 6). Enqueuing inside a caller's transaction then rolls back atomically instead of committing a half-done operation.
- **Workers should be idempotent** (jobs retry) and handle the `{:error, _}`/`{:cancel, _}`/`:discard` outcomes deliberately rather than letting an unexpected raise drive retry behaviour.

## 8. Phoenix / LiveView

- **LiveView-first** for UI; reach for controllers and dead views only when LiveView doesn't fit.
- **Function components** for reusable UI elements; **PubSub** for real-time features.
- **Thin controllers and LiveViews.** Delegate business logic to contexts. A `Repo` call or domain logic embedded directly in a controller action or LiveView callback belongs in a context function.
- **Authorise at the boundary** via the policy module (`SuperApi.Policy` / `LetMe.Policy`), not with role checks sprinkled through contexts.
- **Security first**: CSRF protection on state-changing forms, output escaping (avoid `raw/1` on user content), no secrets in assigns sent to the client.

## 9. Performance

- Prefer streaming (`Stream`, `Task.async_stream`) over building large intermediate lists for big collections.
- Avoid repeated `Enum` passes where one pass (or `Enum.reduce`) does; avoid `length(list)` for emptiness (`list == []` or a pattern match) and `++` in a loop (quadratic).
- Pre-size or reuse Finch pools for hot external hosts (super_api does this in `Application`).
- Don't micro-optimise cold code. These matter on hot paths.

## 10. Security

- No `String.to_atom/1` on user input (`style-and-idioms.md` rule 19).
- Don't interpolate user input into raw SQL. Use parameterised Ecto queries or `fragment` with `?` placeholders.
- Don't log secrets, tokens, TFNs, or PII. Australian super data (TFN, member details) is sensitive; keep it out of logs and error messages.
- Validate and scope ids against the current actor (avoid IDOR). Authorise, don't just fetch by id from params.
- Constant-time comparison for API keys, tokens, and signatures (not `==`).
