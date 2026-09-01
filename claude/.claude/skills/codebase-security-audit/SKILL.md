---
name: codebase-security-audit
description: >-
  Exhaustive, module-by-module security audit of an entire library, package, service, or
  codebase using multi-agent fan-out plus adversarial verification, producing a
  severity-ranked (CVSS) findings report with CVE candidates and independently reproduced
  proof-of-concepts. Use this whenever the user wants to security-audit, pentest, threat-model,
  find vulnerabilities or CVEs in, or assess the attack surface of a whole codebase - ESPECIALLY
  when they mention auditing "each module", spawning an agent per file/module, or hunting for
  DoS / CPU / memory exhaustion, injection, path traversal, request smuggling, or auth/crypto
  weaknesses. Reach for this for breadth-first audits of existing code. It is distinct from a
  quick review of pending changes (/security-review): use this skill when the target is the
  whole codebase rather than a diff.
---

# Codebase security audit

Audit an entire codebase for security vulnerabilities by reviewing it **one module at a time**
with a dedicated agent per module, then **adversarially verifying** every candidate finding
before it reaches the report. The two ideas that make this work:

- **Fan-out for breadth.** A single agent reading a large codebase loses focus and misses the
  fifth parser while obsessing over the first. One agent per module keeps each review deep and
  bounded, and they run concurrently.
- **Adversarial verification for signal.** Security reviews are notoriously false-positive
  heavy - plausible-sounding findings that aren't actually reachable. So every candidate is
  handed to skeptic agents whose job is to *refute* it (is it reachable? does the exploit
  really work? already mitigated?). Only findings that survive are reported. This is the
  difference between a report the user trusts and a wall of noise they have to re-triage.

The orchestration runs through the **`Workflow`** tool. Invoking this skill is itself the
explicit opt-in for multi-agent orchestration, so calling `Workflow` here is expected and
correct. A proven, parameterized script ships with this skill at
`scripts/audit-workflow.js` - you pass it the modules and a brief; you do not rewrite it.

## Before you start: three decisions

These change what you build, so settle them with the user up front (use `AskUserQuestion` if
unstated). Sensible defaults are marked.

1. **Output** - what should the audit produce?
   - *Internal report only* (default): a findings report saved as markdown; flag CVE-worthy
     items but file nothing.
   - *Report + disclosure drafts*: also draft responsible-disclosure / advisory text for the
     maintainers to submit.
   - *File advisories*: push back hard. Filing a public CVE / GitHub Security Advisory against
     a third-party project is outward-facing and normally needs coordinated disclosure with the
     maintainers. Never do this without explicit, specific confirmation of targets.
2. **Scope** - which modules get an agent? Default to the **attack surface** (files that touch
   untrusted input or do crypto/auth), not every file. Reviewing trivial helpers, test
   doubles, and deprecated shims burns budget for little signal - but offer "every module" if
   the user wants exhaustiveness.
3. **Rigor** - default to **adversarial verification** (the script already does this). Offer a
   faster single-pass mode only if the user wants speed over precision.

## Workflow

### 1. Map the codebase and pick the attack surface

List the source files (e.g. under `lib/`, `src/`, `app/`). For breadth, spawn a couple of
`Explore` agents in parallel: one to inventory every module with a one-line purpose, one to
locate the untrusted-input / crypto / auth code paths. From that, choose the module list to
audit and note which are large/complex/critical (they get high reasoning effort).

### 2. Calibrate - build the threat-model brief

This is the highest-leverage step. Read `references/threat-model-brief.md` and fill in the four
sections for *this* project: the threat model (what the attacker controls vs what is trusted),
already-known/fixed issues (read the CHANGELOG, security advisories, recent commits - so agents
don't re-report old CVEs and instead hunt adjacent gaps), the false-positive suppression list,
and output discipline. A sharp brief is what keeps the findings high-signal. Keep this brief;
you pass it verbatim to every agent.

**If the target runs on the BEAM (Elixir / Erlang / Gleam / an OTP release), read
`references/beam-vuln-patterns.md` first.** It catalogs the runtime-specific vulnerability
classes - the ones a reviewer from a C / JVM / Node background will not look for - each anchored
to the recent ecosystem CVE that surfaced it. Use it to (1) seed the brief's category (b)/(c)
with the BEAM-canonical shapes (growing-binary map/ETS keys, atom-table exhaustion,
`binary_to_term`, decompression bombs, un-yielding NIFs, ...) and the DO NOT REPORT list with
that catalog's named "Refuted when" guards, and (2) populate ALREADY-KNOWN by diffing the
project's `mix.lock` / `rebar.config` against the catalog's "Seen in" fixed versions - a
dependency pinned under a fix is itself a finding, and it points agents at the adjacent gap
instead of re-reporting the known CVE.

### 3-5. Run the audit workflow

Call `Workflow` with the bundled script and your inputs:

```
Workflow({
  scriptPath: "<skills>/codebase-security-audit/scripts/audit-workflow.js",
  args: {
    brief: "<the threat-model brief from step 2>",
    modules: ["/abs/path/mod_a.ex", "/abs/path/mod_b.ex", ...],   // absolute paths
    high_effort: ["/abs/path/big_complex_mod.ex", ...]            // optional subset
  }
})
```

The script runs three phases (see the file header for details):
- **Review** - one agent per module, returns structured findings split into real
  *vulnerabilities* vs *hardening* notes, plus a `clean_note` for the coverage table.
- **Verify** - each finding is attacked by skeptics told to refute it. High/critical findings
  get 3 independent verifiers (different refutation angles) with a strict-majority vote; lower
  severity gets 1. Runs as a pipeline so verification starts as soon as each review lands.
- **Synthesize** - dedupes cross-module root causes, assigns CVSS 3.1 scores/vectors, and
  writes the report body with a coverage table, per-finding PoCs, CVE-worthiness, and a
  hardening appendix.

The workflow runs in the background and returns
`{ report: { markdown, cve_candidates }, confirmed_count, refuted_count, coverage }`. Watch
progress with `/workflows`.

If the user has not opted into multi-agent orchestration in a context where `Workflow` is
unavailable, fall back to spawning the per-module reviews as parallel `Agent` calls and verify
findings the same way - the structure is identical, just less deterministic.

### 6. Independently reproduce confirmed High/Critical findings

Do not trust a finding you have not reproduced. For each confirmed High/Critical issue, build a
concrete proof-of-concept against the **real, compiled code** - a crafted input expressed in
the project's own test harness (e.g. a `Plug.Test` conn, a unit test, a small script) - and run
it. For resource-exhaustion findings, demonstrate the scaling (time/memory at increasing input
sizes) rather than asserting it; for logic bugs, show the wrong outcome. Fold your measured
numbers into the report - they are far more convincing than an agent's estimate, and
occasionally they refute a finding the verification round let through.

On the BEAM, measure **reductions alongside wall-clock time**: a finding whose time grows
super-linearly while reductions stay linear is the signature of un-billed C-level work (a BIF or
NIF - binary hashing, `:re`, `:crypto`, `:zlib`) that the scheduler cannot preempt. That is
exactly how the Plug nested-key quadratic (CVE-2026-54892) pinned a scheduler for minutes, and it
is why "the scheduler will just preempt it" is *not* a valid refutation for a BIF-hot-path DoS.

Confirm the run command before running (don't assume `mix test` / `npm test` / `pytest` - check
the project; some repos use a wrapper or a version manager).

### 7. Write the report and summarize

Write `report.markdown` to a file (the workflow agents can't write files) - default
`security-audit-report.md` at the repo root. Insert your independent reproduction results into
the relevant findings. Then give the user a tight summary: confirmed findings by severity, what
was reproduced, which items are CVE-worthy, and the agreed next step (report only / draft
disclosure / etc.). Be honest about what was refuted and what was out of scope.

## Report structure

The synthesis agent produces this; verify it came through intact:

```
# <Project> Security Audit
<exec summary: modules reviewed, findings by severity, headline risk, "internal report only">
## Scope & method
## Coverage          <- table: Module | Confirmed findings | Notes (clean_note per module)
## Findings          <- per finding: CVSS score+vector, category, file:line, attacker input,
                        preconditions, PoC, impact, suggested fix; ordered by severity.
                        When there are zero confirmed findings this becomes a
                        "Probes (not a finding)" log instead of going empty.
## CVE-worthiness    <- conservative recommendation; "none" is a valid answer
## Hardening suggestions
## Refuted / out of scope  <- each refuted candidate + the one-line reason it was dismissed
```

A **clean audit is still a record of what was checked**, not a blank page. The synthesis step
is given the refuted candidates (with the strongest refutation reason for each), so even a
zero-finding report documents the highest-value paths that were probed and why each is not
exploitable - that is what lets a future reader re-trace the reasoning instead of re-deriving
it. The `plug_crypto` audit is the worked example: 0 findings, but five probes recorded.

## Notes on scaling and cost

This audit spawns many agents (roughly: #modules + verifiers + 1). That is the point - breadth
and verification are what make it trustworthy - but it is not cheap. Scale to the ask: a quick
"any obvious holes?" wants a small module list and single-vote verification; "thoroughly audit
this for CVEs" wants the full attack surface and 3-vote adversarial verification. The synthesis
agent occasionally stalls on very large finding sets and retries; the report still comes through.
