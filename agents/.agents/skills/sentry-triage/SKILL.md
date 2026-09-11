---
name: sentry-triage
description: >-
  Triage a Sentry error against the actual codebase and recommend a concrete
  remediation. Takes a Sentry issue — either pasted as formatted markdown (the
  "Issue ID / Tags / Exception / Stacktrace" dump) or as a Sentry issue ID or
  URL it will fetch live via the Sentry MCP — then maps the stacktrace to the
  real source, reads the failing code, works out the root cause, classifies
  severity and whether it's transient vs a real bug, and proposes what to do.
  Read-only: it never edits code or files tickets. Use whenever the user pastes
  or links a Sentry error, an Oban.PerformError, a crash report, an exception
  with a stacktrace, or asks "what's causing this error?", "how do I fix this
  Sentry issue?", "is this worth fixing?", "triage this exception", "what should
  we do about this crash?". Especially apt for Elixir/Phoenix + Oban worker
  failures in super_api, but works for any stacktrace it can map to source.
  Does NOT apply to writing new code, reviewing a diff (use elixir-review), or
  general debugging where there is no error report to start from.
---

# Sentry Triage

Turn a Sentry error report into a grounded root-cause analysis and a concrete
remediation recommendation. The value over a generic "what does this error
mean?" is that this skill **reads the real code the stacktrace points at**
before concluding, understands Oban/OTP failure semantics, and distinguishes a
transient infrastructure blip from a code bug that needs a fix.

This skill is **read-only**. It produces analysis and a recommendation. It does
not edit code, open PRs, or create tickets. Offer those as next steps; don't do
them as part of the triage.

## Workflow

### 1. Get the issue details

Two input modes — detect which you were given:

- **Pasted markdown** (the formatted Sentry dump with `Issue ID`, `Tags`,
  `Exception`, `Stacktrace` sections): parse it directly. No fetching needed.
- **A Sentry issue ID or URL** (e.g. `7482673695` or a `sentry.io/...` link):
  fetch the full issue via the Sentry MCP. The Sentry tools are deferred — find
  them with `ToolSearch` (query `"sentry issue"` or `"select:..."`), authenticate
  if prompted, then pull the issue, its latest event, stacktrace, tags, and
  (importantly) the **event frequency / first-and-last-seen**. Live fetch gets
  you breadcrumbs and occurrence counts the paste usually lacks.

If given an ID/URL but the Sentry MCP isn't connected or auth fails, say so and
ask the user to paste the dump instead — don't guess at the contents.

Extract and note: **error type**, **message/value**, **culprit module +
function** (from the stacktrace, top in-app frame), and the **tags that change
the diagnosis** — `environment`, `release`, `handled`, and for Oban:
`oban_worker`, `oban_queue`, `oban_state`, plus any attempt/retry count.

### 2. Locate the code

Map the culprit frame to real source. Don't trust the path Sentry prints (it's
often `unknown file [Line null]` for Oban workers) — find it yourself:

- Heuristic path for super_api: `SuperApi.Foo.Bar` → `website/lib/super_api/foo/bar.ex`
  (drop the top namespace, snake_case the rest, under `website/lib/`).
- Robust approach: `grep`/Glob for the module name (`defmodule SuperApi.…`) and
  the function from the frame (`def process`, `def perform`). Use the heuristic
  as a starting guess, but confirm by reading the file.

Read the failing function **and enough around it** — the callers, the functions
it calls that could produce the error value, the changeset/query/HTTP call that
actually raises or returns `{:error, _}`. A root cause you can't see in the code
is a guess, not a finding.

### 3. Diagnose — read `references/analysis-playbook.md`

Read the playbook fully before concluding. It covers:

- **Error taxonomy** — transient/infrastructure (`:connection_error`, timeouts,
  `Redix.ConnectionError`, 5xx) vs deterministic code bugs (`MatchError`,
  `FunctionClauseError`, `KeyError`, `Ecto.*`, nil deref) vs expected-but-noisy
  (handled errors being reported that maybe shouldn't be).
- **Oban semantics** — what `oban_state`, queue, attempt count and "handled: yes"
  imply about whether the job retries, whether this is already self-healing, and
  whether the alert is signal or noise.
- **Frequency & blast radius** — one-off vs sustained, tied to a `release` or not.
- **Severity rubric** and the **decision matrix** (fix now / make resilient /
  downgrade the alert / no action).

Hold the project conventions in mind (root + `super_api/CLAUDE.md`): e.g. "no
silent failures", "use the raising variant for impossible errors", timeouts on
user-facing external calls, circuit breakers for critical services. A good
remediation usually aligns with one of these.

### 4. Report

Keep it tight and grounded in the code you read. Use this shape:

```
## Sentry triage — <error type>: <culprit>

**Issue:** <id> · **env:** <prod> · **release:** <rel> · **handled:** <y/n>
<for Oban: queue / state / attempt>

### What's happening
<1-3 sentences: the failing line at `file:line`, what produces the error value,
under what condition. Cite the actual code.>

### Root cause
<transient | code bug | noisy-but-expected> — <why, from the code + tags>.

### Severity & blast radius
<🔴/🟡/🟢> — <who/what is affected, how often, whether Oban retries cover it>.

### Recommended remediation
1. <concrete action tied to a file/function and a project convention>
2. <follow-ups: alert tuning, test to add, monitoring, related code to check>

### Confidence & open questions
<what you're sure of vs what needs a log line, a repro, or Sentry breadcrumbs to
confirm. Flag if you couldn't find the source.>
```

Lead with the most likely root cause; if two are plausible, give both ranked,
with what would disambiguate them. Don't manufacture certainty — for an Oban
`unknown file` frame with empty variable values, the honest output is often "the
error comes from one of these two calls; a log line at X would confirm which".

### 5. Offer next steps (don't take them)

Close by offering, not doing: "Want me to implement the fix?" (then it's an
edit, optionally via elixir-review), or "draft a Linear ticket?". Wait for the
user — this skill stops at the recommendation.
