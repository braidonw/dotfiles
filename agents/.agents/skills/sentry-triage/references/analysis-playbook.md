# Analysis playbook

The methodology for turning a stacktrace into a root cause and a remediation.
Read this before concluding.

## Error taxonomy — what kind of failure is it?

Classify first; the class drives the remediation.

### Transient / infrastructure (usually NOT a code bug)
The code is fine; a dependency was briefly unavailable. Hallmarks:

- Error values: `{:error, :connection_error}`, `{:error, :timeout}`,
  `{:error, :closed}`, `Redix.ConnectionError`, `DBConnection.ConnectionError`,
  `Mint.TransportError`, `Finch` pool timeouts, HTTP 429/5xx from a partner.
- The frame is at an external boundary: an HTTP call (`Req`), a DB call, Redis,
  S3/MinIO, SFTP, the ATO/Xero/SuperSend integrations.
- It's intermittent and not pinned to a single `release`.

Remediation leans toward **resilience, not a logic fix**: confirm the call has a
sensible timeout (project rule: explicit timeouts on user-facing/inline external
calls; library default usually fine in background jobs), a retry/backoff (Oban
already retries — see below), and a circuit breaker for *critical* services. If
Oban already retries and the job ultimately succeeds, the right move may be to
**tune the alert** (don't report handled, self-healing retries as errors) rather
than touch code.

### Deterministic code bug (WILL recur until fixed)
Same input always fails. Hallmarks:

- `MatchError`, `FunctionClauseError`, `CaseClauseError`, `KeyError`,
  `ArgumentError`, `Protocol.UndefinedError`, nil being passed where a struct is
  expected, `Ecto.NoResultsError`, `Ecto.StaleEntryError`,
  `Ecto.ConstraintError`, `Ecto.Query.CastError`.
- Often correlates with a specific `release` (a recent deploy introduced it).
- Variable values in the frame (when present) show the offending shape.

Remediation is a **code fix**: handle the missing clause / nil / not-found,
correct the pattern, add the constraint check. Tie it to a project convention:
"no silent failures" (fail loudly, don't `Map.get(..., default)` over an unknown
key), "use the raising variant + let it crash for impossible errors" vs
genuinely handle errors that *can* happen (not-found, validation of user input,
a race).

### Expected-but-noisy (handled error that's being reported)
`handled: yes` and the error is a normal business outcome (a partner returned
"no record", a validation the code deliberately rejects). The code is doing the
right thing; Sentry is just loud.

Remediation: **downgrade or filter the alert** — drop the Sentry report for this
outcome, lower its level, or stop treating an expected `{:error, _}` as
exception-worthy. Don't "fix" working code to silence an alert.

## Oban failure semantics

Most super_api Sentry noise is `Oban.PerformError`. The tags tell you a lot:

- **`oban_state`**: `executing` at capture is normal (it failed mid-run).
  `retryable` → it will try again. `discarded` → it exhausted retries (`max_attempts`)
  — *that's* the alarming state, the job gave up. `cancelled` → the worker
  returned `{:cancel, _}` on purpose (usually fine).
- **attempt / max_attempts**: attempt 1 of N on a transient error is self-healing
  noise. Attempt == max_attempts that failed is a real, persistent failure.
- **`handled: yes`** on an `Oban.PerformError`: the worker returned `{:error, _}`
  (Oban turns that into a reported error) rather than crashing. Read the worker to
  see whether that `{:error, _}` is a transient signal Oban should just retry, or
  a permanent failure that should be `{:cancel, _}` / `{:discard, _}` so it stops
  retrying and stops alerting.
- **`oban_queue`**: tells you the domain and blast radius (e.g. `auto_stapling`
  → ATO stapling for onboarding members).

Key question: *does Oban already recover from this?* If yes and it eventually
succeeds, the bug is in the alerting, not the job. If the job discards, it's a
real failure that dropped work — high severity.

`return`/`{:cancel, _}`/`{:discard, _}`/`{:error, _}` and `max_attempts` are
defined in the worker's `use Oban.Worker` line and `perform/1`/`process/1` —
read them.

## Mapping the stacktrace to source

- Top **in-app** frame is the culprit; skip framework frames (`Oban.*`,
  `Phoenix.*`, `Ecto.Adapters.*`) unless that's all there is.
- Oban worker frames often show `unknown file [Line null]` and empty variable
  values — normal, not a clue. Go to the source by module+function name.
- super_api path heuristic: `SuperApi.A.B.C` → `website/lib/super_api/a/b/c.ex`,
  snake_cased. Confirm by reading; some modules live in unexpected trees
  (`super_api_web/`, `xero_adapter/`, etc.). Falling back to `grep -r "defmodule
  SuperApi.A.B.C"` always works.
- Once in the file, find which call inside the culprit function can produce the
  reported error value. Trace one level down if the value bubbles up from a
  helper or a context call.

## Frequency & blast radius

- **One-off, single event, no release correlation** → likely transient; watch,
  don't necessarily act.
- **Sustained / rising count** → real problem; prioritise.
- **Spikes at a deploy (`release` correlation)** → regression in that release;
  check the diff around the culprit (`git log`/`git blame` on the file).
- **Who is affected** — a background reconciliation failing is lower urgency than
  a user-facing onboarding step or anything touching money/compliance. The
  `oban_queue` / module domain tells you which.

## Severity rubric

- **🔴 High** — drops or corrupts work (Oban `discarded`, data loss, money/
  compliance/onboarding-blocking), or a deterministic bug hitting many
  users/records, or correlated with a recent release (active regression).
- **🟡 Medium** — recurring but self-healing or limited blast radius; a handled
  error that's masking a real edge case; missing resilience (no timeout/breaker)
  on an important call that will bite under load.
- **🟢 Low** — one-off transient, expected-but-noisy handled outcome, or cosmetic.
  Often the action is "tune the alert" or "no action, monitor".

## Decision matrix

| Class | Recurs? | Recommended action |
|-------|---------|--------------------|
| Transient, Oban retries & succeeds | No (self-heals) | Tune alert / no code change |
| Transient, but Oban discards / user-facing inline | Yes | Add timeout, retry/backoff, or circuit breaker |
| Code bug | Yes | Fix the code (handle nil/not-found/clause); add a test for the branch |
| Expected-but-noisy handled error | n/a | Downgrade/filter the Sentry report; consider `{:cancel,_}` |
| Can't locate source / ambiguous | unknown | State both candidates; recommend a log line or repro to confirm |

## Anti-patterns to avoid in the recommendation

- Don't recommend silencing a real failure (catch-all rescue that swallows, a
  default value over an unknown key) — that's a "silent failure" the project
  forbids.
- Don't recommend handling an error that can't actually happen — for
  programmer-error inputs, the project prefers the raising variant and letting it
  crash loudly. Reserve `case`/handle for errors that genuinely occur at runtime.
- Don't over-engineer a circuit breaker for a non-critical, rarely-failing call.
- Don't claim a root cause you didn't see in the code. If the frame is opaque and
  variable values are empty, say which calls are the candidates and what would
  disambiguate.
