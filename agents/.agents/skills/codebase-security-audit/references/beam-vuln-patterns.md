# BEAM / Elixir / Erlang vulnerability patterns

Read this during **Calibrate** (Workflow step 2) whenever the audit target runs on the BEAM
(Elixir, Erlang, Gleam, or an OTP release). It catalogs the vulnerability classes that are
specific to the runtime - the ones a reviewer coming from a C / JVM / Node background will not
think to look for - each anchored to the recent ecosystem CVE(s) that surfaced it.

Use it two ways:

1. **Prime the brief.** Fold the applicable entries into the per-project brief: the BEAM shapes
   into category (b)/(c), and each pattern's "Refuted when" guard into the DO NOT REPORT list so
   verifiers can dismiss the matching false positive by name.
2. **Version-pin triage.** Diff the project's `mix.lock` / `rebar.config` against the "Seen in"
   fixed versions below before deep reading. A dependency pinned under a fix is a finding on its
   own, and it tells agents to hunt the *adjacent* gap rather than re-report the known CVE.

The catalog is deliberately kept out of the per-agent prompts (it would bloat every review). The
orchestrator reads it here and distills the relevant parts into the brief, which is what actually
reaches each agent.

---

Reference patterns for auditing Elixir/Erlang/BEAM codebases, grouped by the three audit
categories. Each entry states why the bug bites *on the BEAM specifically*, the concrete
code shapes and grep terms to hunt, the specific guard whose presence refutes the finding,
and the verified CVEs (with fixed versions) that anchor it. Only CVE ids that survived
fact-checking are listed under "Seen in"; class-level patterns with no single CVE are
marked as such. Version pins in mix.lock / rebar.config are the fastest triage: compare
each dependency against the "Seen in" fixed versions before deep reading.

Two BEAM realities recur throughout: (1) atoms are interned in a global, fixed-size table
(default 1,048,576) and are NEVER garbage-collected, so any atom minted from untrusted
input is a whole-node crash primitive; (2) the runtime's fairness relies on reduction
counting, so one un-yielding operation (a NIF, a `:re` match, a giant `binary_to_term`)
pins a scheduler and there is no built-in match/parse timeout.

---

## (a) Unintended behaviour

Auth/authz bypass, path traversal, information disclosure, injection (header /
response-splitting / template / command), request smuggling, SSRF, transport spoofing.

**OTP SSH pre-authentication RCE**
- Mechanism: the SSH connection handler processes connection-protocol messages
  (channel-open, `exec`/`subsystem`/`shell` requests) before userauth completes (CWE-306),
  so an unauthenticated client runs the configured command handler; root daemon means root RCE.
- Audit for: `ssh:daemon`, `:ssh.daemon`, embedded SSH admin/management listeners; pinned OTP
  older than the fixed patch. Client-only (`ssh:connect`) use is not exposed.
- Refuted when: OTP >= 27.3.3 / 26.2.5.11 / 25.3.2.20; no daemon started; SSH port firewalled
  from untrusted networks.
- Seen in: CVE-2025-32433 (CVSS 10.0, CISA KEV; fixed OTP 27.3.3, 26.2.5.11, 25.3.2.20).

**inets httpd directory traversal / arbitrary file read**
- Mechanism: httpd did not fully normalize request paths, so `../` (or encoded traversal)
  escaped `document_root` and read any file readable by the BEAM OS user.
- Audit for: `inets:start(httpd, ...)`, `document_root`, `mod_get`, `mod_alias`; custom
  `mod_alias`/`mod_esi` path handling that concatenates request path to a base dir.
- Refuted when: inets >= 22.3.4.6 / 23.1; not serving files via inets (API-only or Cowboy/Bandit
  fronting); a reverse proxy normalizes paths.
- Seen in: CVE-2020-25623 (CVSS 7.5; fixed OTP 22.3.4.6 / 23.1).

**inets httpd ScriptAlias CGI auth bypass**
- Mechanism: when `script_alias` maps a URL to a dir outside `document_root`, `mod_auth`
  evaluates access controls against the document-root-relative path while `mod_cgi` executes at
  the ScriptAlias-resolved path; the two disagree, so directory auth guarding the CGI target is
  never applied and the script runs unauthenticated (CWE-863).
- Audit for: `script_alias`, `mod_cgi`, `mod_auth`, `mod_esi`; a directory `{auth}` block
  protecting a script_alias target outside document_root.
- Refuted when: inets >= 9.6.2 / 9.3.2.4 / 9.1.0.6 (OTP 28.4.2 / 27.3.4.10 / 26.2.5.19); no
  mod_cgi; no script_alias outside document_root; auth enforced at a proxy.
- Seen in: CVE-2026-28808 (CVSS 9.8; fixed inets 9.6.2 / 9.3.2.4 / 9.1.0.6).

**HTTP request smuggling via duplicate/ambiguous Content-Length (CL.CL)**
- Mechanism: a parser that resolves multiple `Content-Length` headers by picking the FIRST
  (`List.keyfind/3`) rather than rejecting the request desyncs framing versus a proxy that honors
  the LAST, smuggling a second pipelined request past edge WAF/ACL/rate-limit controls
  (RFC 9112 6.3 requires rejection).
- Audit for: `get_content_length`, `List.keyfind`, `:"content-length"` lookups that take the
  first match; keep-alive/pipelining loops re-reading buffered bytes; any parser resolving
  multi-valued CL / Transfer-Encoding by choosing a value instead of erroring. Also inets httpd
  behind a proxy.
- Refuted when: parser counts CL occurrences and 400s on more than one (or on CL+TE); Bandit >=
  1.11.0; inets version that rejects multiple differing CL.
- Seen in: CVE-2026-39805 (Bandit; fixed 1.11.0). inets ambiguous-framing hardening is
  class-level (no CVE).

**Bandit transport-state (scheme) spoofing via request-target URI**
- Mechanism: `determine_scheme/2` reflected the client's request-target scheme into
  `conn.scheme` while discarding the transport `secure?` flag, so an absolute-form
  `GET https://victim/path` over plaintext made the app see `conn.scheme = :https`. Downstream
  Plug.SSL redirect-skip, `secure` cookies, and CSRF/SameSite gating are misled.
- Audit for: `determine_scheme`, `conn.scheme`, absolute-form / h2c scheme handling; consumers:
  `Plug.SSL`, `put_secure_browser_headers`, secure-cookie flags keyed on `conn.scheme`.
- Refuted when: scheme derived from transport `secure?`; Bandit >= 1.11.0; TLS terminated at a
  trusted proxy that overwrites scheme.
- Seen in: CVE-2026-39807 (Bandit; fixed 1.11.0).

**Phoenix WebSocket check_origin wildcard mishandling**
- Mechanism: `socket/transport.ex` mishandled wildcard `check_origin` patterns, so an
  origin-validation entry could be satisfied by an unintended origin (CWE-346/863).
- Audit for: endpoint `check_origin:` wildcard entries (`"//*.example.com"`), `check_origin:
  false`, custom check_origin MFA.
- Refuted when: Phoenix >= 1.6.14; explicit non-wildcard host list; default LiveView (the join
  CSRF token is validated regardless of origin).
- Seen in: CVE-2022-42975 (CVSS 7.5; fixed Phoenix 1.6.14).

**HTTP response header / CRLF injection via cookie and header values**
- Mechanism: unvalidated CR/LF in a header/cookie value could inject additional response headers
  or split the response (response splitting, cache poisoning, reflected XSS).
- Audit for: `put_resp_header`, `put_resp_cookie`, `merge_resp_headers` with user-derived values;
  redirect `Location` built from input; `Set-Cookie` from request data.
- Refuted when: Plug >= 1.3.5 / 1.2.5 / 1.1.9 / 1.0.6 (modern Plug raises on CR/LF); values are
  constants or validated/encoded.
- Seen in: CVE-2018-1000883 (CVSS 6.5; fixed Plug 1.3.5 / 1.2.5 / 1.1.9 / 1.0.6).

**XML External Entity (XXE) injection via xmerl / sweet_xml**
- Mechanism: `xmerl_scan` on OTP < 27 resolves external entities by default; parsing
  attacker-controlled XML (SAML/SOAP/webhook/upload) BEFORE signature verification dereferences
  `SYSTEM`/`http` entities, disclosing local files or issuing SSRF. sweet_xml `xpath/2,3`,
  `xmap/2` and the `~x` sigil call xmerl and do not surface the safe `fetch_fun` knob.
- Audit for: `SweetXml`, `~x`, `xpath(`, `xmap(`, `:xmerl_scan.string`, `:xmerl_scan.file`,
  `xmerl_sax_parser` on request bodies / uploads / SAML / SOAP; absence of a `fetch_fun`/DTD trap.
- Refuted when: OTP >= 27 (xmerl entity expansion off by default); parsing via erlsom or Saxy (no
  external-entity resolution); xmerl called with a `fetch_fun` that throws on external fetch;
  signature verified on raw bytes before any entity-expanding parse; XML source fully trusted.
- Seen in: CVE-2026-28809 (esaml SAML SP and forks; the OTP < 27 xmerl default is the enabling
  precondition; mitigated by OTP >= 27 or a patched esaml).

**Zip-Slip / absolute-path archive extraction**
- Mechanism: `:zip.unzip`/`:zip.extract` writing to disk (no `:memory`) wrote entries whose names
  begin with `/` to that absolute path verbatim, an RCE-grade write primitive (overwrite
  authorized_keys, cron, config). Classic `../` traversal is the sibling class.
- Audit for: `:zip.unzip`, `:zip.extract`, `:zip.foldl`, `:erl_tar.extract`; manual
  `Path.join(dest, entry_name)` writing extracted bytes without per-entry name validation.
- Refuted when: OTP >= 28.0.1 / 27.3.4.1 / 26.2.5.13; extraction uses `:memory` and validates
  names; each dest path is `Path.expand`'d and asserted to start with the base dir; entries with
  absolute or `..` names rejected via `Path.safe_relative`.
- Seen in: CVE-2025-4748 (CVSS 4.8; fixed OTP 28.0.1 / 27.3.4.1 / 26.2.5.13).

**Runtime template/code injection via Code.eval / EEx compile on untrusted input**
- Mechanism: `Code.eval_string`, `Code.eval_quoted`, `Code.compile_string`, `EEx.compile_string`,
  `EEx.eval_string` compile and execute source at runtime with full VM privileges. Building a HEEx
  string by interpolating request data (e.g. `~s|#{name}="#{val}"|`) then compiling it is RCE.
  Each compiled identifier also grows the atom table.
- Audit for: `Code.eval_string`, `Code.eval_quoted*`, `Code.compile_string`,
  `EEx.compile_string`, `EEx.eval_*`, `:erl_eval`; any `~H`/HEEx string built by interpolating
  runtime values; `apply/3` with a computed module/function atom from input.
- Refuted when: templates are static module `~H` sigils compiled at build time with only data
  passed via assigns/bindings (assigns are data, not code); evaluated string is a compile-time
  constant; input confined to a whitelisted expression parser.
- Seen in: CVE-2026-8467 (phoenix_storybook, CVSS 9.5 unauthenticated RCE; fixed 1.1.0). Broader
  Code.eval class has no single CVE.

**Unescaped output bypassing HEEx auto-escaping (XSS)**
- Mechanism: HEEx/EEx auto-escape interpolated values via `Phoenix.HTML.Safe`; escaping is
  bypassed when a value is wrapped as already-safe (`raw/1`, hand-built `{:safe, iodata}`, markdown
  renderer output). User data through any of these is emitted verbatim, and LiveView re-renders
  persist it. Historically the `class` attribute had a separate, under-escaped rendering path.
- Audit for: `raw(`, `Phoenix.HTML.raw`, `{:safe,`, markdown/HTML renderer output (Earmark, MDEx)
  `raw`'d without a sanitizer; dynamic `class={@user_value}` on old phoenix_html; JS hooks setting
  innerHTML.
- Refuted when: the raw'd value is a developer-authored literal or passed through a sanitizer
  (HtmlSanitizeEx, MDEx `sanitize: true`); values rendered normally (auto-escaped);
  phoenix_html >= 3.0.4 for the class-attribute gap.
- Seen in: CVE-2021-46871 (phoenix_html class-attribute XSS, CVSS 6.1; fixed 3.0.4). The general
  `raw/1` bypass is class-level (no CVE).

**LiveView authorization enforced only at mount**
- Mechanism: `mount/3` runs for the initial static render and the socket connect, but every
  `handle_event/3` and `handle_params/3` afterward operates on client-supplied payloads. Authz
  placed only in mount (or data read once and trusted) lets an attacker push events referencing
  IDs/actions they are not entitled to.
- Audit for: `handle_event`/`handle_params` clauses that load an `id`/`slug` from params without
  scoping to `current_user`; auth only via a controller plug, not `on_mount`/`live_session`; a
  presence-of-`current_user` check standing in for a per-action policy.
- Refuted when: a `live_session ... on_mount:` hook authenticates the socket AND each mutating
  event re-scopes queries to `current_user` / runs a policy (Bodyguard, LetMe); resource loads
  are ownership-scoped (`where: r.user_id == ^uid`).
- Class-level (no CVE); central to the LiveView security model.

**CSRF bypass via GET-to-mutation action reuse**
- Mechanism: `protect_from_forgery` verifies the CSRF token only on non-GET requests. A `get`
  route mapped to a state-changing action (or an action reused across GET and POST) is triggerable
  by a cross-site GET carrying the victim's cookies with no token.
- Audit for: router `get` routes pointing at create/update/delete actions; actions referenced by
  both `get` and a mutating verb; `:browser` pipeline missing `protect_from_forgery`; custom JS/
  API clients omitting `_csrf_token`.
- Refuted when: all state-changing routes use POST/PUT/PATCH/DELETE behind `protect_from_forgery`;
  forms via `Phoenix.Component.form/1`/`form_for`; token-authenticated (non-cookie) APIs.
- Class-level (no CVE).

**Plug.Static / file-serving path traversal (null byte + dot segment)**
- Mechanism: null-byte injection truncated file-type checks and `../` escaped the static/upload
  root when serving user-controlled local paths.
- Audit for: `Plug.Static`, `send_file`, `File.read`/`File.stream!` on paths from `conn.params`/
  `path_info`; `Path.join` with untrusted segments; missing null-byte and canonicalization checks.
- Refuted when: `Path.safe_relative/2`, null bytes rejected, allowlisted segments, files served by
  fixed identifiers, or cloud object storage (no local FS join); modern Plug.Static rejects unsafe
  segments.
- Class-level (historical Plug fixes 1.0.4 / 1.1.7 / 1.2.3 / 1.3.2; no live CVE).

**Erlang distribution / EPMD / shared-cookie remote node takeover**
- Mechanism: EPMD (4369) reveals node names and dist ports; a peer authenticates only via an MD5
  challenge over the shared `~/.erlang.cookie`. A leaked/static/committed/brute-forced cookie is
  full RCE (`rpc:call(Node, os, cmd, [...])`); no per-message auth after handshake.
- Audit for: distribution enabled (`-name`/`-sname`, `RELEASE_DISTRIBUTION`, `RELEASE_COOKIE`);
  `setcookie` / committed `.erlang.cookie` in Dockerfiles/repo; `rpc:call`, `erpc:call`,
  `Node.spawn`; EPMD / dist port range exposed to untrusted networks; missing `proto_dist inet_tls`.
- Refuted when: distribution not enabled; EPMD + dist ports bound to loopback/private and
  firewalled; high-entropy per-deployment cookie plus TLS distribution.
- Class-level (BEAM-intrinsic, no CVE).

**Mix/Hex dependency install executes code at fetch/compile time (supply-chain)**
- Mechanism: `mix deps.get` + `mix compile` runs a dependency's `mix.exs`, macros, custom mix
  compilers, and rebar hooks on the dev/CI machine before any of your code. Typosquat / compromised
  / dependency-confusion packages achieve code execution in dev/CI.
- Audit for: unpinned deps, `:git` deps on mutable branches, typosquat-adjacent names, private+
  public registry mixing; uncommitted `mix.lock`; CI missing `mix deps.get --check-locked` and
  `mix hex.audit` / `mix deps.audit`.
- Refuted when: version-pinned deps with committed `mix.lock`, `--check-locked` in CI, git deps
  pinned to sha/tag, allowlisted private registry, and an audit gate in the build.
- Class-level (no CVE).

**Self-hosted hexpm registry-server defects (only if you run/fork hexpm)**
- Mechanism: a 2026 audit cluster - non-expiring password-reset tokens (account takeover), OAuth
  device-flow XSS, OAuth `client_credentials` scope escalation (read-only key to write), a local
  file-store path traversal, and an oversized-upload DoS.
- Audit for: only relevant to a self-hosted/forked hexpm or private registry: password-reset token
  expiry, OAuth scope checks on client_credentials, HTML escaping on device-flow screens, path
  confinement in the local file store, upload size caps.
- Refuted when: consuming hex.pm (all fixed server-side); a fork past the fix commits with the
  specific guard present.
- Seen in: CVE-2026-21622 (reset-token expiry, CVSS 9.5), CVE-2026-21618 (device-auth XSS, 8.5),
  CVE-2026-21621 (OAuth scope escalation, 7.0), CVE-2026-23939 (local file-store traversal, 6.9),
  CVE-2026-23940 (upload DoS, 7.1); all fixed server-side in the 2026 hexpm disclosures.

---

## (b) Resource exhaustion

CPU/memory disproportionate to input: algorithmic complexity, unbounded allocation/recursion/
spawn, atom-table growth, decompression bombs, scheduler starvation.

**FLAGSHIP - growing/large binary as map or ETS key => quadratic hashing**
- Mechanism: the BEAM hashes the FULL byte range of a binary key on every map/ETS
  put/get/update and does NOT cache the hash on the term. Any loop that keys a map/ETS on a binary
  that grows with accumulated input pays O(key_size) per op, giving O(n^2) overall. This is exactly
  the Plug nested-query-key DoS: `Plug.Conn.Query.decode/4` walks `a[a][a]...=1` and at each of N
  bracket levels does a Map op keyed on an ever-longer binary prefix, re-hashing the whole prefix
  each level. Within the default 1 MB urlencoded limit a single unauthenticated request encodes
  ~333,000 levels and pins a scheduler for minutes; a few concurrent requests saturate all
  schedulers. The root cause recurs in ANY hand-rolled dedup/interner/cache/accumulator that grows
  a binary and re-keys a map/ETS on it in a loop.
- Audit for: `Map.put`/`Map.get`/`Map.update`/`:ets.insert`/`:ets.lookup` inside a loop/recursion
  where the key is a binary built by `<>` concatenation / `binary_part` / accumulated prefix;
  `Plug.Conn.Query.decode`/`decode_each` on unbounded params; `reduce`/`Enum` building a map keyed
  on progressively longer binaries; caches keyed on full request bodies or concatenated paths;
  parsers for nested/bracketed structures.
- Refuted when: a hard cap on nesting depth / key length / element count BEFORE the keying loop
  (Plug's fix adds a max query-decode depth; a body byte-limit alone is NOT sufficient, 1 MB still
  yields ~333k levels); bounded-size keys (fixed-length ids, short hashes); integer/atom keys
  instead of growing binaries; structure built once from a bounded schema.
- Seen in: CVE-2026-54892 (Plug, CVSS 8.7; fixed 1.15.5 / 1.16.4 / 1.17.2 / 1.18.3 / 1.19.3).

**Generalized quadratic accumulation (`<>` / `++` / membership in a loop)**
- Mechanism: any loop over N attacker-controlled elements where each step touches the whole
  accumulator is O(n^2): `acc = acc <> chunk` (each `<>` copies the growing binary), `list ++ x` in
  a loop (each `++` walks the left list), `Enum.member?`/`Enum.uniq` against a growing list. One
  process runs the whole loop on one scheduler with no yield to shed load.
- Audit for: `<>` accumulator inside `Enum.reduce`/`for`/recursion; `++` inside a loop;
  `Enum.member?`/`Enum.uniq` inside iteration over user input; repeated `Map.merge` of growing maps.
- Refuted when: iolists (list of binaries flattened once) instead of `<>`; prepend-then-reverse
  instead of append; `MapSet`/map membership instead of list; element count capped before the loop.
- Class-level (the unifying principle behind the flagship CVE; no separate CVE).

**Unbounded recursion on nested attacker input (stack/heap exhaustion)**
- Mechanism: a recursive descent parser/walker with no depth limit recurses once per nesting
  level; deeply nested JSON/XML/query-params drives recursion proportional to depth, crashing the
  process (and, across a pool, degrading the node). Distinct from quadratic keying: cost is the
  DEPTH itself.
- Audit for: hand-written recursive parsers/validators/normalizers with no depth counter;
  `deep_merge`/recursive `Map.merge` on attacker params; JSON/XML decoders without a max-depth
  option; absence of a `depth`/`max_depth` argument.
- Refuted when: an enforced max nesting depth that rejects deeper input (Plug's post-fix cap,
  decoder max-depth option); validation against a bounded Ecto embedded schema; iterative parse
  with a bounded work-queue.
- Seen in: CVE-2026-54892 (Plug nested params, above). CVE-2026-54297 (Faraday NestedParamsEncoder,
  CVSS 7.5, fixed 1.10.6 / 2.14.3) is a Ruby cross-ecosystem analogue of the same class, not a BEAM
  CVE.

**Atom-table exhaustion from atoms created off untrusted input**
- Mechanism: atoms are interned globally, never GC'd, and capped (default 1,048,576). Any call
  turning unbounded input into fresh atoms lets a remote attacker fill the table; when full the
  ENTIRE VM crashes (system_limit) - unauthenticated, low-bandwidth. Non-obvious sinks: JSON
  `keys: :atoms`, XML/config atom-key options, `Module.concat` on user data, dynamic dispatch that
  atomizes a type field, LiveView `handle_event`/`phx-value-*` keys.
- Audit for: `String.to_atom`, `List.to_atom`, `:erlang.binary_to_atom`, `list_to_atom`,
  `Module.concat` on request data; `Jason.decode(..., keys: :atoms)` (WITHOUT `!`); Poison atom
  keys; `binary_to_term` missing `:safe`. Sobelow `DOS.StringToAtom` / `DOS.BinToAtom`. Cross-check
  the "never `String.to_atom` on user input" rule.
- Refuted when: `String.to_existing_atom` / `List.to_existing_atom` / `Module.safe_concat` against
  a closed compile-time set; validation against an allowlist before atomization; `keys: :atoms!`;
  `binary_to_term(_, [:safe])`; a fixed enum. (Monitoring `atom_count` is detection, not
  refutation. `to_existing_atom` still crashes with ArgumentError if fed a non-existent atom, but
  does not exhaust the table.)
- Seen in: CVE-2026-8469 (phoenix_storybook, CVSS 8.2; fixed 1.1.0); GHSA-h74c-q9j7-mpcm /
  CVE-2026-48597 (Tesla, Tesla.Adapter.Mint URL scheme via `String.to_atom`, CVSS 8.2; fixed
  1.18.3 - NOT 1.11.0); CVE-2026-21619 (hex_core/hex/rebar3 atomizing decoded ETF, fixed hex_core
  0.12.1 / hex 2.3.2 / rebar3 3.27.0).

**Decompression bomb - unbounded :zlib / gunzip / inflate on attacker-supplied compressed data**
- Mechanism: `:zlib.gunzip/1` / one-shot `:zlib.inflate` / `:zlib.uncompress` allocate the entire
  decompressed output as one BEAM binary with no size ceiling; gzip/zlib compress runs of repeated
  bytes at ~1000:1, so a few KB inflates to multiple GB on the shared binary heap and OOM-kills the
  node, usually pre-auth, from a single frame. Amplification compounds per content-encoding layer
  and per WebSocket permessage-deflate frame. Note: a `max_receive_message_length`-style limit
  applied AFTER decompression gives no protection.
- Audit for: `:zlib.gunzip`, `:zlib.uncompress`, `:zlib.inflate`, `permessage_deflate`,
  `IO.iodata_to_binary` near a decompress; `Content-Encoding` / `grpc-encoding` / `Accept-Encoding`
  handling that decompresses; recursive decompression over a comma-split header; upload/import
  paths that decompress before size-checking; Req `compressed: true` on untrusted endpoints.
- Refuted when: streaming inflate with a running output-byte cap that aborts past a threshold; a
  hard cap on encoding layers; a compressed+decompressed byte ceiling enforced while inflating;
  compression disabled. A cap on COMPRESSED input alone is insufficient at 1000:1 unless tiny.
- Seen in: CVE-2026-53430 (elixir-grpc gzip, CVSS 8.7; fixed 1.0.0); CVE-2026-48594 (Tesla response
  bodies, recursive layers, CVSS 8.2; fixed 1.18.3); CVE-2026-23943 (OTP SSH pre-auth zlib,
  ~1029:1; fixed OTP 28.4.1 / 27.3.4.9 / 26.2.5.18); CVE-2026-43970 (cowlib cow_spdy inflate; fixed
  cowlib 2.16.1); CVE-2026-39804 (Bandit WebSocket permessage-deflate; fixed 1.11.0).

**Compressed External-Term-Format memory bomb (`binary_to_term` on compressed ETF)**
- Mechanism: ETF has a compressed variant (`term_to_binary(t, compressed: 9)`, tag 131,80) that
  `binary_to_term` transparently zlib-inflates during decode. A tiny blob inflates to gigabytes of
  live terms BEFORE `:safe` checks bound anything - `:safe` restricts atoms/funs, not decoded size.
- Audit for: same call sites as unsafe `binary_to_term`; accepting ETF over sockets/queues without
  a raw byte-length cap; `term_to_binary(_, compressed: _)` anywhere (signals the decode side
  accepts compressed ETF).
- Refuted when: raw input is length-capped small BEFORE decode AND the source is MAC-authenticated;
  payload signed so only server-generated bytes reach the decoder. `[:safe]` alone does NOT refute.
- Class-level (BEAM-intrinsic, no CVE).

**XML entity-expansion DoS (billion laughs) via inline DTD**
- Mechanism: nested internal entity definitions expand exponentially at parse time; xmerl expands
  entities eagerly, so a tiny document balloons to gigabytes. No external fetch needed (distinct
  from XXE).
- Audit for: same call sites as XXE (`SweetXml.xpath`/`xmap`, `~x`, `:xmerl_scan`); sweet_xml
  version in mix.lock; parsing with no size accumulator and no DTD rejection.
- Refuted when: sweet_xml >= 0.7.0 (DTD off by default); OTP >= 27 (xmerl entities off);
  Saxy/erlsom (no internal expansion); xmerl with an `acc_fun` capping accumulated size; a hard
  byte/parse cap plus DOCTYPE rejection.
- Seen in: CVE-2019-15160 (sweet_xml, CWE-776; fixed 0.7.0).

**Unbounded multipart header buffer**
- Mechanism: `Plug.Conn.read_part_headers/2` accumulated multipart part headers with no upper
  bound (its sibling `read_part_body` has a `byte_size(acc) > length` guard, it did not). A single
  part with an enormous never-terminated header section forces unbounded memory (CWE-770).
- Audit for: `read_part_headers`, `Plug.Parsers` with `parsers: [:multipart]`, `Plug.Upload`;
  custom multipart readers looping over header bytes without a byte_size cap.
- Refuted when: Plug >= 1.15.4 / 1.16.3 / 1.17.1 / 1.18.2 / 1.19.2; multipart parser not enabled.
- Seen in: CVE-2026-8468 (Plug, CVSS 8.2; fixed 1.15.4 / 1.16.3 / 1.17.1 / 1.18.2 / 1.19.2).

**Bandit HTTP/1 chunked body ignores request size cap (single-request OOM)**
- Mechanism: the chunked-body reader forwarded only `:read_length`/`:read_timeout` and discarded
  the caller's `:length` cap (unlike the Content-Length path), buffering all chunks in memory and
  bypassing the Plug body-size limit - one `Transfer-Encoding: chunked` request grows the heap to OOM.
- Audit for: content-length vs chunked read paths with asymmetric option handling; `read_body`,
  `:length` vs `:read_length`, chunked handling; a max-body-size guard on only one framing.
- Refuted when: chunked reader threads the `:length` cap and errors when exceeded; Bandit >= 1.11.1.
- Seen in: CVE-2026-39803 (Bandit; fixed 1.11.1).

**Bandit HTTP/1 chunked-trailer infinite recursion (worker pin)**
- Mechanism: the chunk decoder matched the terminator only when `0\r\n` was immediately followed by
  an empty line, ignoring RFC 9112 trailer fields; a chunked request with trailers hit a default
  clause computing a negative `to_read` and recursed on `read_available!/2` without advancing the
  buffer, pinning the worker for the connection lifetime; a handful exhaust the acceptor pool.
- Audit for: `do_read_chunked_data`, `read_chunked`, `0\r\n`, `trailer`; chunk terminator clauses
  assuming no trailers; recursion where `to_read` can go negative and the buffer is not consumed.
- Refuted when: trailer lines consumed up to the final CRLF plus a positive-progress invariant on
  `to_read`; Bandit >= 1.11.1.
- Seen in: CVE-2026-39806 (Bandit; fixed 1.11.1).

**Bandit HTTP/2 frame-size limit bypass via late buffer check**
- Mechanism: the frame parser validated a frame's declared length only AFTER buffering the full
  payload (returned `{:more, msg}` and kept buffering). An attacker announces a 16 MiB frame on a
  16 KiB `SETTINGS_MAX_FRAME_SIZE` connection and drips the body; a few thousand connections
  exhaust node memory.
- Audit for: frame parsing `{:more, ...}`; length checks after the payload branch rather than on the
  9-byte header; `SETTINGS_MAX_FRAME_SIZE` / `max_frame_size` enforcement location.
- Refuted when: a header-only clause rejects an oversized frame on the 9-byte header
  (FRAME_SIZE_ERROR) before buffering; Bandit >= 1.11.0.
- Seen in: CVE-2026-42788 (Bandit; fixed 1.11.0).

**Bandit unbounded WebSocket continuation-frame accumulation**
- Mechanism: fragment reassembly appended continuation payloads to an unbounded iolist;
  `max_frame_size` limits only individual frames, not total message size, so an endless stream of
  continuation frames grows per-connection memory, and `IO.iodata_to_binary` on `fin=1` doubles the
  peak. Buffered before `WebSock.handle_in/2`, so the app cannot intervene.
- Audit for: `fragment_frame`, `continuation`, `fin`, `max_frame_size`, `IO.iodata_to_binary` in
  websocket code; continuation accumulation with no running total vs a max-message-size guard.
- Refuted when: a cumulative max-message-size check across fragments that closes the connection when
  exceeded; Bandit >= 1.11.0.
- Seen in: CVE-2026-42786 (Bandit; fixed 1.11.0).

**HTTP/2 Rapid Reset (Cowboy)**
- Mechanism: HEADERS immediately followed by RST_STREAM in a tight loop; reset streams do not count
  against `SETTINGS_MAX_CONCURRENT_STREAMS`, so the server does unbounded stream setup/teardown work
  (spawning/killing request processes) far faster than the concurrency cap intends.
- Audit for: RST_STREAM handling, `max_cancel_stream_rate`, reset-stream accounting in
  `cowboy_http2.erl` / any custom HTTP/2 server; absence of a rate limit on client cancellations.
- Refuted when: a rate limit on client RST_STREAM (Cowboy `max_cancel_stream_rate`) or counting
  reset streams toward concurrency; Cowboy >= 2.11.0.
- Seen in: CVE-2023-44487 (protocol class, CVSS 7.5; Cowboy fixed 2.11.0; requires OTP 24+).

**HTTP/2 CONTINUATION flood (Cowboy / cowlib)**
- Mechanism: HEADERS without END_HEADERS then an unbounded stream of CONTINUATION frames grows
  memory/CPU while the request never completes and leaves no access-log entry; Cowboy bounded
  individual frames but not the aggregate header block.
- Audit for: `CONTINUATION`, `END_HEADERS`, header-block assembly, `max_fragmented_header_block_size`;
  header-frame accumulation with no cap on concatenated size before HPACK decode.
- Refuted when: a cap on total fragmented header-block bytes (Cowboy `max_fragmented_header_block_size`);
  Cowboy >= 2.12.0 with cowlib >= 2.13.0.
- Class-level for Cowboy (part of the 2024 CONTINUATION-flood family; cf. CVE-2024-27316,
  CVE-2024-24549 in other servers).

**HTTP/2 MadeYouReset (server-induced reset accounting bypass)**
- Mechanism: instead of client RST_STREAM, the attacker sends malformed control frames (bad
  WINDOW_UPDATE/PRIORITY/DATA) that make the SERVER emit the reset; if the server frees the
  concurrency slot on reset emission while backend work continues, it bypasses
  MAX_CONCURRENT_STREAMS - a Rapid-Reset variant that evades client-RST rate limits.
- Audit for: whether server-initiated RST_STREAM decrements the concurrent-stream count while
  request work is still running; WINDOW_UPDATE/PRIORITY validation and stream-state transitions on
  protocol errors. The Rapid-Reset fix does NOT cover this.
- Refuted when: concurrency accounting keyed on actual work completion, not reset emission, plus a
  rate limit on server-emitted resets.
- Seen in: CVE-2025-8671 (protocol class; confirmed in Tomcat/Netty/gRPC/Varnish/etc.; Netty's
  instance is CVE-2025-55163). NOT confirmed for Cowboy/Bandit - treat as an audit hypothesis for
  any BEAM HTTP/2 server, not an assumed finding.

**cowlib chunked chunk-size parser DoS**
- Mechanism: cowlib's chunked parser read the hex chunk-size field with no limit on digit count;
  a multi-gigabyte hex size drives O(N^2) (rising to O(N^3) when drip-fed) bignum multiplication
  (`Len*16+digit`) - the primary impact is CPU exhaustion, not a single giant allocation.
- Audit for: chunk-size parsing, hex-digit loops, chunked Transfer-Encoding in
  `cow_http_te.erl` or any hand-rolled decoder; missing bound on hex-field length or decoded size.
- Refuted when: a max chunk size and a cap on hex-digit count; cowlib >= 2.16.1. (Note: Cowboy
  2.12.0 shipped cowlib 2.13.0; the 2.16.1 fix belongs to a later Cowboy line, not 2.12.0.)
- Seen in: CVE-2026-7790 (cowlib 0.6.0-2.16.0; fixed 2.16.1).

**Long-running / un-yielding NIF or BIF starving a scheduler**
- Mechanism: normal Erlang code is preempted after ~2000 reductions; a NIF does not bump reductions
  and cannot be preempted, so a NIF running > ~1ms blocks its scheduler thread. One slow NIF on
  attacker-sized input (crypto/compression/parsing/regex) freezes a scheduler; some pure BIFs on
  huge inputs behave similarly.
- Audit for: NIF libraries handling unbounded input (image/video/crypto/compression/JSON/regex);
  in C, absence of `enif_consume_timeslice`/`enif_schedule_nif` in a loop and no
  `ERL_NIF_DIRTY_JOB_*` flag; `term_to_binary`/`binary_to_term`/`:crypto`/`:zlib` one-shot on huge
  data; a single GenServer handling all traffic in a tight loop.
- Refuted when: the NIF is a dirty scheduler job, yields via `enif_consume_timeslice` and
  reschedules, input is capped before the native call, or work is offloaded to a bounded pool/port.
- Class-level (BEAM-intrinsic, no CVE).

**ReDoS - catastrophic backtracking in :re / Regex**
- Mechanism: Erlang `:re` (and Elixir `Regex`) is a backtracking PCRE engine; nested/overlapping
  quantifiers (`(a+)+`, `(.*)*`) take exponential time on adversarial input, and `:re.run` does not
  yield mid-match, freezing the scheduler. There is no built-in match timeout. Two surfaces:
  attacker supplies the subject, or attacker supplies the pattern (search/rule features).
- Audit for: `Regex.match?`/`run`/`scan`/`replace`, `:re.run`/`:re.compile` where pattern OR
  subject is user-influenced; `~r` sigils with nested quantifiers; regex on unbounded-length input;
  user-supplied regex; missing input length caps.
- Refuted when: input length capped before matching AND no nested quantifiers; static reviewed
  patterns (no user regex); a linear-time engine (RE2 NIF, `:re2`) for untrusted patterns; matching
  offloaded to a task with a hard timeout that actually kills the process.
- Class-level (BEAM-intrinsic, no CVE).

**Unbounded process / Task spawn from attacker input**
- Mechanism: each process has heap/stack/mailbox overhead and a bounded process-table slot (default
  ~262,144 / 1,048,576). Spawning one process per attacker element with no ceiling exhausts the
  process table (node crash) or memory. `Task.async_stream` without `max_concurrency`, or
  `Enum.map(items, &Task.async/1)` over an unbounded list, spins up N processes at once. Unbounded
  mailboxes are the sibling failure (a process receiving faster than it processes grows to OOM).
- Audit for: `Task.async`/`Task.start`/`spawn`/`Task.Supervisor.start_child`/`GenServer.start`
  inside `Enum.map`/`for` over request collections; `Task.async_stream` WITHOUT `max_concurrency`;
  `DynamicSupervisor.start_child` per message with no `max_children`; `handle_info`/`handle_cast`
  hot loops with no backpressure.
- Refuted when: bounded concurrency (`max_concurrency`, poolboy, fixed Task pool, DynamicSupervisor
  `max_children`); input length validated first; backpressure (GenStage/Flow, bounded queue).
- Class-level (BEAM-intrinsic, no CVE).

**Unbounded ETS table growth**
- Mechanism: ETS lives off-heap and is not GC'd; entries persist until deleted. A table inserting
  one row per attacker key (session/rate-limit/dedup/memo cache) with no eviction, TTL, or size cap
  grows to OOM. Off-heap growth is invisible to per-process GC and easy to miss.
- Audit for: `:ets.new` + `:ets.insert` on attacker-derived keys with no matching delete / size
  check; caches/rate-limiters on raw ETS without a sweeper or TTL; no `:ets.info(_, :size|:memory)`
  guard.
- Refuted when: bounded size with eviction (LRU / count / memory cap), a TTL sweeper, a bounding
  library (Cachex with `limit`, con_cache with ttl), or keys from a bounded domain.
- Class-level (BEAM-intrinsic, no CVE).

**Refc-binary leak via sub-binaries pinning large parents**
- Mechanism: binaries > 64 bytes are refc binaries on a shared heap, freed only when every
  referencing process is GC'd. A binary match / `:binary.part` / `String.slice` yields a sub-binary
  that is a pointer+offset into the original (no copy), so retaining a tiny slice keeps the ENTIRE
  parent alive. Many small sub-binaries stored long-term (ETS, GenServer state) leak memory
  proportional to the parents; per-process heap looks small while node memory climbs.
- Audit for: long-term storage of results of binary match / `:binary.part` / `binary_part` /
  `String.slice` without `:binary.copy`; extracted fields put in ETS/GenServer/Agent; long-lived
  router/proxy processes handling binaries. Prod symptom: high `erlang:memory(binary)` /
  `:recon.bin_leak`.
- Refuted when: retained slices passed through `:binary.copy/1` before storage; holder process is
  short-lived; hibernation / explicit `:erlang.garbage_collect` on long-lived binary-heavy processes.
- Class-level (BEAM-intrinsic, no CVE).

**GraphQL query depth / complexity / alias DoS (Absinthe)**
- Mechanism: GraphQL schemas are cyclic; a client can nest a self-referential relation arbitrarily
  deep, alias one expensive resolver hundreds of times, or fire large introspection. Absinthe
  enforces NO depth/complexity limit by default.
- Audit for: `use Absinthe.Schema`, `Absinthe.run`, `Absinthe.Plug`; ABSENCE of
  `analyze_complexity: true`/`max_complexity`, per-field `complexity:`, lexer `token_limit`,
  introspection gating; list fields taking a client `limit`/`first` with no server cap; N+1
  resolvers without Dataloader.
- Refuted when: `max_complexity` (with per-field complexity) AND a lexer `token_limit`, or a
  max-depth middleware, AND introspection disabled in prod; persisted-queries-only.
- Class-level (configuration, no CVE).

**Deeply-nested / oversized structure DoS in binary decoders (CBOR / msgpack / JSON / Floki / CSV)**
- Mechanism: self-describing formats let a small payload declare huge or deeply nested structure;
  CBOR/msgpack length-prefixes can claim multi-GB arrays; deep nesting recurses to exhaustion; Floki
  builds a full DOM tree; nimble_csv can accumulate an unterminated quoted field or a million-column
  row before a boundary.
- Audit for: `CBOR.decode`, `Msgpax.unpack(!)`, `Jason.decode` on large bodies,
  `Floki.parse_document`/`parse_fragment`, `NimbleCSV.*.parse_string`/`parse_stream`; missing
  `max_depth`/size option; no upstream `Plug.Parsers` `:length` cap.
- Refuted when: `Plug.Parsers`/router enforces a `:length` cap before decode, decoder sets a
  nesting/size limit, or input is streamed with bounded buffering.
- Class-level (usually mitigated by Plug body-size limits; no CVE).

---

## (c) Crypto / serialization

Unsafe deserialization, non-constant-time secret comparison, signature/verification gaps,
certificate/hostname validation flaws, token expiry.

**Unsafe :erlang.binary_to_term on untrusted data (RCE + atom/memory DoS)**
- Mechanism: ETF is a self-describing serialization of ANY term. `binary_to_term/1` (no options)
  creates new atoms (never GC'd - atom-table exhaustion) and anonymous funs. Critically, `[:safe]`
  is NOT enough against RCE: `:safe` only blocks new-atom and fun creation for DoS; a decoded term
  can still be type-confused when it flows into protocol dispatch - the Enumerable protocol is
  implemented for 2-arity funs, so passing a decoded value into `Enum.*`/`apply`/a stored callback
  can implicitly INVOKE attacker code. Attacker vectors: cursors, tokens, session/cookie blobs,
  cache values, queue payloads, gRPC frames, inter-node messages.
- Audit for: `binary_to_term`, `:erlang.binary_to_term`, `term_to_binary` round-trips of user data;
  Base64/hex decode immediately followed by `binary_to_term` (cursor/token/session patterns); a
  single-arg `binary_to_term` (no `[:safe]`); follow the decoded term to any `Enum.*`/`apply`/
  protocol dispatch/`String.to_atom` sink. Flag even `[:safe]` calls whose term reaches Enum/dispatch.
- Refuted when: `Plug.Crypto.non_executable_binary_to_term/1,2` (rejects funs AND, with `:safe`,
  atoms); OR the payload is MAC-verified before decode (Plug.Crypto MessageVerifier / signed cookie)
  so only server-produced bytes are decoded; OR a non-executable codec (JSON/protobuf). Full
  refutation for the RCE variant needs non_executable_binary_to_term, or `:safe` PLUS a size cap
  PLUS a post-decode type/shape guard - `:safe` alone leaves atom + memory DoS and the Enum RCE path.
- Seen in: CVE-2020-15150 (duffelhq/paginator, before/after cursor was Base64 ETF fed to
  binary_to_term even with `:safe`, CVSS 9.8; fixed 1.0.0); CVE-2026-48853 (elixir-grpc
  `GRPC.Codec.Erlpack.decode/2`, CVSS 9.2, only when the Erlpack codec is explicitly registered -
  NOT the default gRPC path; fixed 1.0.0, NOT 0.10.x). Also underlies CVE-2026-21619 (hex_core/hex/
  rebar3 decoding registry responses with `binary_to_term/1`; fixed hex_core 0.12.1 / hex 2.3.2 /
  rebar3 3.27.0).

**Cookie / session term deserialization (binary_to_term on signed cookies)**
- Mechanism: `Plug.Session.COOKIE` historically round-tripped the session via `term_to_binary` /
  `binary_to_term`; if signing is disabled/bypassed or the secret leaks, decoding attacker terms
  enables atom exhaustion and code execution when the term is later invoked.
- Audit for: `Plug.Session.COOKIE` serializer option, `binary_to_term` on cookie/cache/job-arg
  blobs, `String.to_atom` on request-derived data.
- Refuted when: `Plug.Crypto.non_executable_binary_to_term/2` (ideally `:safe`), or `binary_to_term(_,
  [:safe])`, or a JSON serializer with validation; a verified Plug.Crypto MAC over the cookie plus
  non-executable decode.
- Class-level (historical Plug fix 1.0.4 / 1.1.7 / 1.2.3 / 1.3.2; no live CVE).

**Non-constant-time comparison of tokens / MACs / secrets (timing side channel)**
- Mechanism: comparing a client-supplied token/HMAC/CSRF/API-key/session-MAC to the expected value
  with `==`/`===`/pattern match short-circuits on the first differing byte; on the BEAM the
  divergence is observable via response timing, letting an attacker recover the secret byte-by-byte.
- Audit for: `==`/`===`/`!=`/pattern match on values named token/mac/signature/digest/hmac/secret/
  api_key/csrf; `if signature == expected`, `case sig do ^expected ->`; hand-rolled HMAC/webhook
  (Stripe/GitHub/partner) verification.
- Refuted when: `Plug.Crypto.secure_compare/2` or `masked_compare/3` (CSRF double-submit) or
  `:crypto.hash_equals/2`; verification delegated to `Plug.Crypto.MessageVerifier`/`Phoenix.Token`
  (which use secure_compare internally); the compared value is not secret.
- Class-level (BEAM has the ready primitive; no CVE).

**Terrapin SSH prefix-truncation / handshake integrity downgrade**
- Mechanism: SSH BPP uses implicit sequence numbers not reset after initial KEX; with
  ChaCha20-Poly1305 or `*-etm@openssh.com` ciphers a MITM can inject/delete handshake packets
  undetected (sequence numbers desync silently), downgrading negotiated security (e.g. dropping
  SSH_MSG_EXT_INFO / server-sig-algs). Integrity/downgrade, not RCE.
- Audit for: OTP ssh app < 5.1.1; `preferred_algorithms` with chacha20-poly1305 or `*-etm` and no
  strict-KEX; grep `kex-strict-c-v00@openssh.com` / `kex-strict-s-v00@openssh.com` in
  `ssh_transport.erl`.
- Refuted when: OTP ssh >= 5.1.1 (OTP 26.2.1) or backport advertising strict KEX; strict KEX
  negotiated; only CBC/CTR with non-ETM MACs; no MITM-reachable path.
- Seen in: CVE-2023-48795 (broad multi-implementation Terrapin, CVSS 5.9; OTP tracked via
  GHSA-hx6w-xhph-454x, fixed ssh 5.1.1 / OTP 26.2.1 plus backports).

**TLS client-certificate authentication bypass**
- Mechanism: a TLS handshake state-machine error let a client certificate be accepted without
  proving possession of its private key (the CertificateVerify / key-ownership binding was not
  enforced), so an attacker presenting someone else's cert authenticated as that peer, bypassing mTLS.
- Audit for: `:ssl.listen`/`ssl:handshake` with `verify: verify_peer` + `fail_if_no_peer_cert` used
  as the sole auth (mTLS); a validated client cert treated as identity on pinned OTP below the fix.
- Refuted when: OTP >= 23.3.4.15 / 24.3.4.2 / 25.0.2; server does not request client certs;
  client-cert identity additionally bound by an application-layer proof.
- Seen in: CVE-2022-37026 (CVSS 9.8; fixed OTP 23.3.4.15 / 24.3.4.2 / 25.0.2).

**public_key nameConstraints bypass via subject CommonName fallback**
- Mechanism: `pubkey_cert:validate_names/6` checked only subjectAltName DNS entries against a CA's
  nameConstraints; a leaf that OMITS the SAN trivially satisfies any `permitted;DNS` constraint, and
  OTP hostname verification then falls back (pre-RFC-9525) to matching the requested host against
  the subject CN. A sub-CA constrained to `*.example.com` can mint a no-SAN leaf with
  `CN=victim.other-domain.com` and it validates out-of-scope, defeating name constraints.
- Audit for: ssl/public_key path validation trusting an intermediate CA with nameConstraints;
  `pkix_verify_hostname`, `verify_hostname`, `customize_hostname_check`; delegated sub-CAs in an
  mTLS/PKI trust hierarchy on OTP below the fix.
- Refuted when: OTP/public_key >= 26.2.5.21 / 27.3.4.12 / 28.5.0.1 / 29.0.1 (removes CN fallback per
  RFC 9525); no sub-CA/name-constraint trust model; SAN-only enforced by an app-level verify_fun.
- Seen in: CVE-2026-42790 (CVSS 8.1 HIGH - not Critical; fixed OTP 26.2.5.21 / 27.3.4.12 /
  28.5.0.1 / 29.0.1, public_key 1.15.1.7 / 1.17.1.3 / 1.20.3.1 / 1.21.1).

**Signed token used for auth without max_age expiry**
- Mechanism: `Phoenix.Token.sign`/`verify` and signed session cookies are tamper-proof but do not
  expire unless `max_age` is enforced; callers pass `max_age: :infinity` or reimplement verification
  and omit it, so a leaked token/cookie is valid indefinitely and stateless tokens cannot be revoked.
  A signed (not encrypted) token is Base64-readable, so confidential payloads leak.
- Audit for: `Phoenix.Token.verify`/`sign`, `max_age`, `:infinity`, `Plug.Crypto.verify`; session
  cookie config; `verify(..., max_age: :infinity)` on auth/reset/confirmation tokens; long-lived
  remember-me tokens with no revocation table; sensitive data in a signed-but-unencrypted token.
- Refuted when: auth tokens set a bounded `max_age` (reset tokens minutes, sessions hours/days)
  and/or are backed by a DB token table (the `mix phx.gen.auth` UserToken pattern); confidential
  payloads use `Phoenix.Token.encrypt`/`decrypt`.
- Class-level (no CVE).
