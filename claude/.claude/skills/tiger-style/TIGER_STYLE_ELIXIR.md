# Tiger Style, for Elixir

*Adapted from TigerBeetle's [TIGER_STYLE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md) for Elixir and the BEAM. The original was written for a single-process, statically-allocated Zig database. This version keeps the philosophy and re-derives the practice for a runtime built on immutable data, cheap processes, and crash-driven fault tolerance.*

## The Essence of Style

Style is not what the code looks like. Style is how the system works: how it fails, how it degrades, how it holds up under load nobody predicted, and how the next person reasons about it at 2am. Syntax is the least of it.

Our design goals, in order:

1. **Safety**
2. **Performance**
3. **Developer experience**

The order matters. Where the goals conflict, the earlier one wins. It is easier to make a correct system fast than a fast system correct, and easier to make a correct system pleasant than a pleasant system correct.

## Safety

### Let it crash is a discipline, not a shrug

"Let it crash" is the most misquoted idea in Erlang. It does not mean "don't handle errors." It means: **partition all failures into two kinds, and never confuse them.**

- **Expected errors** are part of your domain: the network is down, the record was deleted, the user typed a bad TFN. These get a `{:error, reason}` tuple, a matching `case` clause, and a designed response.
- **Unexpected errors** are bugs: the "impossible" state, the constraint violation, the malformed data you built yourself. These get a crash — loud, located, and contained by a supervisor.

The failure mode to fear is the third category people invent under pressure: log-and-continue. An error that is logged and swallowed is a bug that has been laundered into an "event." It will page nobody, corrupt something quietly, and surface three weeks later as data you cannot explain.

```elixir
# A designed response to an expected error:
case Stapling.deliver_request(request) do
  {:ok, response} -> handle_response(request, response)
  {:error, :no_active_connection} -> {:cancel, :no_active_ato_connection}
end

# A crash on an impossible one — this insert cannot fail unless we have a bug:
Oban.insert!(job)

# The laundered bug. Never this:
case Oban.insert(job) do
  {:ok, job} -> {:ok, job}
  {:error, reason} ->
    Logger.error("insert failed: #{inspect(reason)}")
    :ok
end
```

Every error is either **handled** or **fatal**. There is no middle setting.

### Pattern matching is your assertion language

TigerBeetle asks for at least two assertions per function. Elixir gives you a better deal: the assertion *is* the code. A function head that matches the exact shape it expects asserts that shape on every call, for free, forever.

- Match the precise shape: `%{"request_id" => id}`, not `Map.get(args, "request_id")`. The former crashes at the boundary with a clear error; the latter threads a `nil` through six functions before something else crashes with a confusing one.
- Match on success when failure is impossible: `{:ok, session} = create_session(attrs)` in a context where creation cannot legitimately fail. If it fails anyway, you want the `MatchError`, not a propagated tuple.
- Never give an assertion a default. `Map.get(plan_map, frequency, "starter")` is not a fallback, it is a silent failure with a business consequence. Fail loudly on the unknown frequency.
- Assert both sides of a boundary. The caller validates what it sends; the callee matches what it receives. This looks redundant. It is redundant. That is the point — the two sides of an interface drift, and paired assertions catch the drift.

The compiler participates too: avoid `_ ->` catch-all clauses on `case` expressions over your own enums and tagged tuples. An exhaustive match means adding a new variant produces a crash (or a Dialyzer error) at every site that must now handle it — the codebase tells you where the work is. A catch-all means new variants are silently absorbed by whatever the default arm does.

### The `!` is a contract

A function whose job is to raise on failure carries a `!`. This is not decoration; it is the type system for failure semantics that Elixir actually has. `fetch_user/1` tells the caller "absence is a case you handle." `fetch_user!/1` tells the caller "absence is a bug." Choosing between them is a design decision about whose problem the failure is — make it deliberately, at every call site.

Corollary: when the schema guarantees presence — a NOT NULL foreign key, a row this transaction just inserted — use `Repo.one!` and let absence crash. Returning `{:error, :not_found}` for data that cannot be absent gives callers a branch that can never legitimately execute, and dead branches are where bugs hide.

### Bound everything

This is the heart of Tiger Style, and the part the BEAM most wants you to forget. TigerBeetle statically allocates all memory at startup, so every queue, buffer, and loop has a hard limit by construction. The BEAM does the opposite: mailboxes grow without limit, binaries grow without limit, the atom table grows without limit — right up until the node dies. **The runtime will not stop you. Limits are your job.**

Put an explicit bound on every resource that can grow:

- **Every external call has a timeout**, and on user-facing paths you chose the number — you did not inherit a library default you have never read. `GenServer.call/2` defaults to 5 seconds; that is a decision someone made for a different system. In background jobs the library default is usually right, but that too should be a decision, not an accident.
- **Every queue has back-pressure.** An unbounded mailbox is an unbounded queue with no dashboard. If producers can outrun a consumer, use something that pushes back: GenStage demand, Broadway, Oban, `Task.async_stream/3` with `max_concurrency`. Casting into a slow GenServer in a loop is how nodes fall over.
- **Every retry has a ceiling.** `max_attempts` on Oban jobs, a bounded backoff on HTTP retries. Infinite retries against a dead dependency is a self-inflicted DoS.
- **Every external input has a size limit.** The list you decode from a request body, the file you accept, the batch you process — cap it, and reject over-limit input loudly rather than trying to be heroic.
- **Every pool is sized on purpose.** DB pool, Finch pools, concurrency limits — these numbers encode an assumption about load. Write the assumption down where the number lives.

The exercise generalizes: for any process you write, ask "what here can grow, and what stops it?" If the answer is "nothing stops it," you have found the outage.

### Atoms are memory you never free

The atom table is the one allocation on the BEAM that is never garbage collected. `String.to_atom/1` on user input is a slow memory leak with a remote trigger. Use `String.to_existing_atom/1` when you must cross the string/atom boundary with external data, or better, keep external data as strings and match on strings.

### Supervision trees are failure-domain design

The supervision tree is not boilerplate; it is your blast-radius diagram. Design it the way TigerBeetle designs its memory layout — deliberately, up front:

- **Group by failure domain, not by module topic.** Things that should die together share a supervisor; things that must survive each other do not. `rest_for_one` and `one_for_all` encode dependency; use them when a restart genuinely invalidates a sibling's state.
- **Keep state that must survive a crash out of the process that crashes.** A process's state is a cache whose invalidation strategy is called crashing. Anything that cannot be rebuilt from the database (or ETS, or a peer) on restart does not belong in a GenServer's state.
- **Restart intensity is a circuit breaker.** The `max_restarts`/`max_seconds` pair decides when localized crashing escalates into "this whole subtree is unhealthy." Defaults are rarely what a production system wants; choose them.
- **Crashing is not failure. Crashing is failure containment.** A supervisor restarting a worker into a known-good state is the system healing. The pathology is not the crash — it is the process that limps on with corrupted state because someone wrapped its loop in a rescue.

Which is the rule on `try`/`rescue`: it belongs at genuine boundaries (a boundary to code you don't control, a place where you convert a crash into a designed response for an external caller) — never as insulation around your own logic. Rescuing your own bug converts a contained crash into an uncontained corruption.

### Explicit beats implicit, everywhere

- Explicit `case` over `with`/`else` when errors need translation — an `else` clause conflates failures from different steps, and the reader can no longer tell which operation produced which error. (`with` without `else`, returning the unmatched value verbatim, is fine.)
- Explicit timeouts with the unit in the name: `timeout_ms`, `ttl_seconds`. A bare `timeout: 30` is a bug wearing a trench coat — 30 what?
- Explicit control flow: no `Process.sleep/1` as synchronization, no `send/2` to a PID whose lifecycle you don't control, no implicit ordering assumptions between async operations. If two things must happen in order, make the code say so.

### The compiler is your first reviewer

Run with every check turned up: `mix compile --warnings-as-errors`, `mix format --check-formatted`, Dialyzer, Credo — in CI, on every commit. A warning is a bug that has not chosen its moment. `@spec` every public function: specs are assertions about interfaces that Dialyzer checks while you sleep.

## Performance

### Do the napkin math first

Performance is designed, not profiled in later. Before building, sketch the arithmetic: how many rows, how many round trips, how many bytes, how many messages per second. Two minutes of back-of-envelope work is the cheapest optimization you will ever perform, and it happens at design time — when changing course costs nothing.

### Sort your resources by cost: network, then disk, then memory, then CPU

Optimize the most expensive resource first. In a typical Elixir service the ranking is stark: a network round trip to Postgres costs ~1ms; a `Map.get` costs nanoseconds. Six orders of magnitude. Which yields the prime directive of Ecto performance:

**Count your queries.** The N+1 is the canonical sin — `Repo.preload/2` and joins exist to turn N round trips into one. But the same logic governs everything: `Repo.insert_all/3` over N inserts, one query with a `where ... in` over N `Repo.get`s, one aggregate over loading rows to count them in Elixir.

### Batch, batch, batch

Amortize fixed costs over many units of work. This is TigerBeetle's central performance idea and it survives the translation intact: batch DB writes, batch external API calls where the API allows it, batch messages through Broadway batchers, buffer-and-flush instead of write-per-event. The fixed cost of a round trip divided by a batch of 1,000 rounds to zero.

### Back-pressure beats buffering

When producers outrun consumers, a buffer does not solve the problem — it schedules the outage for later, with interest, at a worse time. Prefer mechanisms where the consumer pulls (GenStage demand, Broadway, Oban's queue limits) over designs where producers push and hope. The system that slows its intake under load degrades; the system that buffers under load explodes.

### A process is a unit of concurrency, not a unit of code organization

Modules and functions organize code. Processes organize *runtime* concerns: shared state, concurrency, fault isolation. Reaching for a GenServer to "encapsulate" logic that has no state and no concurrency requirement buys you nothing and costs you a serialization point — every call through a single process is a queue, and that queue is invisible until it is on fire.

- Stateless logic lives in plain modules. It is faster, testable without OTP ceremony, and cannot become a bottleneck.
- Read-heavy shared state belongs in ETS (`read_concurrency: true`), not behind a GenServer that serializes every reader.
- When a process must exist and gets hot, shard it or pull reads out of it.

### Know what copying costs

Message passing copies the term — sending a large map to another process duplicates it, and ETS reads copy the stored term out. Binaries over 64 bytes are the exception: they are reference-counted and shared, which cuts both ways — passing them is cheap, but a small sub-binary can pin a huge parent binary in memory (`:binary.copy/1` when you keep a slice of something large). Build output with IO lists and let the runtime write them scatter-gather; `Enum.join/2` in a loop is allocation you did not need.

None of this justifies contorting code before the napkin math says it matters. It justifies knowing which operations are free and which are not, so the expensive ones are a choice.

## Developer Experience

### Name things with intent

The great thing about a name is that it is documentation the compiler makes you keep. Spend time on names; they are the highest-leverage characters in the file.

- Units and qualifiers live in the name: `timeout_ms`, `ttl_seconds`, `amount_cents`.
- Predicates end in `?` and return booleans — nothing else. Functions that raise by contract end in `!`.
- A name states what a thing is or does, not its type or its history: no `data`, `handle`, `process`, `manager`, `util` on domain concepts.
- A misleading name is worse than a bad one: a `fetch_*` that mutates or a `*?` that returns a tuple will be trusted, and the trust will be repaid with a bug.

### Simple control flow

Control flow should be boring. `case` with all clauses visible beats clever piping through `then/2` and conditional lambdas. Two levels of nesting is the ceiling — at the third, extract a named function so the name documents the step. Keep the happy path down the left margin. Small functions, but not micro-functions: extracting a helper whose only job is to rename one tuple into another scatters the logic without abstracting anything. A helper earns its name by doing real work.

### Dependencies are liabilities with good marketing

TigerBeetle's zero-dependency policy does not port literally — nobody should hand-roll Ecto. But the posture ports exactly: **every dependency is code you now own without having read.** It is a supply-chain risk, an upgrade treadmill, and a constraint on every future version bump, purchased in exchange for not writing some functions.

The standard library and OTP are deeper than you think: `:queue`, `:ets`, `:counters`, `:persistent_term`, `:atomics`, DynamicSupervisor, Registry, `gen_statem`. Check what you already have before adding what you don't. When a hundred lines of stdlib would do the job, a hex package is not a convenience; it is a lien.

### Do not duplicate state

Every fact should have one authoritative home, and everything else should derive from it. Two copies of the same fact is a race condition with a delivery date. In practice: the database is the source of truth; process state and caches are derived and must be rebuildable; a LiveView assign that mirrors another assign is a sync bug waiting for its trigger; a boolean column that duplicates what a status column already implies will disagree with it eventually.

### Write it right the first time

The moment of writing is when context is at its maximum — you know the constraints, the edge cases, the reason for the weird branch. Code deferred to "clean up later" will be cleaned up by someone with less context than you have right now, which usually means never. Do not ship TODOs for correctness. A TODO for a future feature is a note; a TODO for a known defect is a defect.

The same logic makes tests non-optional at write time: the cases that matter — the happy path asserting on real outcomes, every error branch the code deliberately handles, the boundaries — are cheapest to cover while the design is still in your head. Tests must be deterministic: no sleeps as synchronization, no time-of-day dependence, no ordering assumptions between async operations. A flaky test is worse than no test — it trains the team to ignore the signal, and the signal is the only thing a test is for.

### The style serves the system

Rules are compression: each exists because some class of outage, bug, or 2am page keeps happening, and the rule is cheaper than the recurrence. When a rule and the system's safety conflict, the rule loses — but be honest about which situation you are in. Most of the time the rule is right and the shortcut is the thing that keeps happening.

---

*Safety first. Then performance. Then developer experience. Then, and only then, everything else.*
