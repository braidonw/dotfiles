# Threat-model brief template

The brief is the single most important input to the audit: it is prepended to every review
and verification agent's prompt, so it defines what counts as a vulnerability, what to ignore,
and how to report. A vague brief produces a flood of low-signal findings; a sharp one keeps
agents focused on attacker-reachable issues and suppresses the usual false positives.

Build the brief **per project** during the Calibrate step. Fill the four sections below, keep
it concrete, and pass it as `args.brief` to the workflow. The example values are from an HTTP
library audit (Plug) - replace them with the realities of the codebase you're auditing.

**BEAM targets (Elixir / Erlang / Gleam / OTP):** pull the runtime-specific shapes into
sections 1 and the named refuting guards into section 3 from `references/beam-vuln-patterns.md`,
and populate section 2 by diffing the project's `mix.lock` / `rebar.config` against that
catalog's "Seen in" fixed versions.

---

## 1. THREAT MODEL - who the attacker is and what they control

State precisely which inputs are attacker-controlled vs trusted. This is what makes findings
reachable-or-not. Examples of the distinction:

- **Attacker-controlled** (a finding here is real): for a web library - method, path, query
  string, all request headers, cookies, request body up to limits. For a CLI/parser - file
  contents, argv, env an unprivileged caller sets. For a service - the API payloads, message
  queue contents, anything crossing a trust boundary.
- **Semi-trusted** (issues here are usually *hardening*, not vulns, unless a dangerous
  default): adapter/transport-supplied values, developer configuration, build-time route
  definitions, values another internal service vouches for.

Then define the three vulnerability categories the audit targets:
- **(a) Unintended behaviour** - auth/authz bypass, path traversal, information disclosure,
  injection (SQL/command/header/response-splitting), request smuggling, open redirect, SSRF,
  incorrect access control.
- **(b) Resource exhaustion** - CPU/memory/disk disproportionate to input size: algorithmic
  complexity (quadratic+), unbounded recursion or allocation, atom/interned-string table
  growth, file-descriptor or temp-file exhaustion, decompression/zip bombs. On the BEAM, name
  the runtime-specific shapes explicitly (see `references/beam-vuln-patterns.md`): growing/large
  binaries used as map or ETS keys (O(n^2) because the VM re-hashes the whole key each op and
  does not cache binary hashes - the CVE-2026-54892 Plug root cause), atom-table exhaustion from
  `String.to_atom` / `binary_to_atom` / `keys: :atoms` on input, one-shot `:zlib` decompression
  bombs, unbounded `Task` / process spawn or ETS growth, refc-binary leaks from retained
  sub-binaries, ReDoS via `:re` (no match timeout), and un-yielding NIF/BIF scheduler starvation.
- **(c) Crypto / serialization** - non-constant-time comparison of secrets, unsafe
  deserialization, weak/predictable token or ID generation, signature/verification gaps. On the
  BEAM: `:erlang.binary_to_term` on untrusted bytes (note `[:safe]` alone is NOT sufficient - a
  decoded term can still reach an `Enum` / `apply` / protocol-dispatch sink and invoke code),
  secrets compared with `==` / pattern-match instead of `Plug.Crypto.secure_compare` or
  `:crypto.hash_equals`, IDs from `:rand` rather than `:crypto.strong_rand_bytes`, and signed
  tokens with no `max_age`.

## 2. ALREADY-KNOWN / ALREADY-FIXED - calibration

List issues already fixed or publicly known, drawn from the CHANGELOG, security advisories,
and recent commits. Instruct agents NOT to re-report these as new - only to flag them if the
fix is **absent or incomplete** in the code they actually read, and to look for **adjacent
gaps** the known fix did not close. This is what stops the audit from rediscovering last
year's CVE and calling it new.

## 3. DO NOT REPORT - false-positive suppression

The recurring noise classes. Tailor to the stack, but the shape is always:
- Input that looks attacker-controlled but is resolved at build/compile time or comes from a
  trusted component (e.g. interning strings from a route name, not from a request).
- Errors reachable only via programmer misuse / malformed internal config, not a real attacker.
- Paths already guarded by a named, verified mitigation (size limits, input validation,
  constant-time compare). Name the specific guards so agents can recognise them.
- (BEAM) Paths guarded by a named runtime mitigation: `String.to_existing_atom` /
  `Module.safe_concat` / `keys: :atoms!` (bounded atom set), `Plug.Crypto.non_executable_binary_to_term`
  or a MAC-verified-before-decode payload, `Plug.Crypto.secure_compare` / `masked_compare`,
  `Path.safe_relative`, a query-decode / nesting-depth cap, or a streaming decompress with an
  output-byte cap. See the "Refuted when" line of each pattern in `references/beam-vuln-patterns.md`.
- Internals of a dependency you treat as sound and out of scope (name it).

## 4. OUTPUT DISCIPLINE

- Cite exact `file:line`. Describe the precise attacker input and the control-flow path from
  the input to the vulnerable code. Give a concrete exploit sketch (the literal value sent).
  If you cannot construct attacker input that reaches the code, it is NOT a finding.
- Separate genuine vulnerabilities (`kind: vulnerability`) from defense-in-depth ideas
  (`kind: hardening`).
- Prefer a few high-confidence findings over many speculative ones.

---

## Worked example (Plug HTTP library)

A filled-in brief for the Plug audit is reproduced below as a concrete model. Note how the
THREAT MODEL names the exact request surface, the calibration section cites real CHANGELOG
entries, and the suppression list names specific guard functions.

```
THREAT MODEL
- Plug parses untrusted HTTP requests. Assume a remote, unauthenticated attacker fully
  controls: method, path / path_info, query string, ALL request headers (Cookie, Range,
  Content-Type, Content-Disposition, Accept-Encoding, X-Forwarded-*, Authorization,
  If-None-Match), and the request body up to configured limits.
- Adapter-supplied values (scheme, peer/transport/SSL data) and application-developer
  configuration + route definitions are SEMI-TRUSTED. Issues requiring developer
  misconfiguration are 'hardening', not vulnerabilities, UNLESS they are dangerous defaults.
- A VULNERABILITY = something a remote attacker can trigger to cause (a) unintended behaviour,
  (b) resource exhaustion disproportionate to request size, or (c) crypto/serialization
  weakness. [...full category list...]

ALREADY-KNOWN / ALREADY-FIXED (do NOT re-report; only if the fix is absent/incomplete):
- Plug.Conn.Query: quadratic decode of deeply nested bracketed query/body keys, fixed by a
  max query-decode DEPTH cap (CVE-2026-54892; fixed 1.15.5 / 1.16.4 / 1.17.2 / 1.18.3 / 1.19.3).
  Confirm the depth cap is present; a :length byte-limit ALONE does NOT mitigate it (1MB still
  encodes ~333k nesting levels). Look for the same growing-binary-key shape elsewhere.
- Plug.Parsers.MULTIPART: unbounded per-part header buffer fixed (CVE-2026-8468; fixed
  1.15.4 / 1.16.3 / 1.17.1 / 1.18.2 / 1.19.2), and multipart header decoding now considers
  OVERALL length. Confirm present; look for ADJACENT gaps (e.g. part-count floods).
- Plug.Debugger: XSS in the debug error page was fixed (v1.16.2).
- Cookie parsing was optimized for memory/CPU (v1.16.1).

DO NOT REPORT (known false-positive classes):
- Compile-time String.to_atom on route param names, or scheme atom from the trusted adapter.
- Errors only reachable via programmer misuse / malformed developer config.
- Paths already guarded by validate_utf8!, Plug.Parsers :length limits,
  Plug.Static.invalid_path?/1, or Plug.Crypto.secure_compare / masked_compare.
- Plug.Crypto internals (separate package) - treat its guarantees as sound.

OUTPUT DISCIPLINE
- Cite exact file:line, the attacker input, the control-flow path, a concrete exploit sketch.
  If you cannot construct reaching input, it is NOT a finding.
- Separate vulnerabilities from hardening. Prefer few high-confidence findings.
```
