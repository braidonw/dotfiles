// Per-module security audit with adversarial verification.
//
// Invoke with: Workflow({ scriptPath: "<this file>", args: { brief, modules, high_effort } })
//   args.brief        (string)   - the project-specific threat-model brief (see references/threat-model-brief.md)
//   args.modules      (string[]) - absolute paths of the source files to review, one review agent each
//   args.high_effort  (string[]) - OPTIONAL subset of `modules` to review at high reasoning effort
//                                   (large/complex/critical files). Defaults to none.
//
// Returns { report: {markdown, cve_candidates}, confirmed_count, refuted_count, coverage }.
// The caller (main loop) writes report.markdown to a file - workflow agents can't write files.
//
// Pipeline: Review (1 agent/module) -> Verify (adversarial, per finding) -> Synthesize (1 agent).
// Verify runs as a true pipeline stage (no barrier), so each module's findings are attacked the
// moment that module's review lands. High/critical findings get 3 independent skeptics with a
// strict-majority vote (each given a different refutation angle); lower-severity get 1.

export const meta = {
  name: 'codebase-security-audit',
  description: 'Per-module security review of a codebase with adversarial verification of each finding',
  phases: [
    { title: 'Review', detail: 'one security-review agent per module' },
    { title: 'Verify', detail: 'adversarial skeptics try to refute each finding' },
    { title: 'Synthesize', detail: 'dedupe, score (CVSS), write report body' },
  ],
}

// args may arrive as an object or a JSON string depending on the caller - handle both.
const input = typeof args === 'string' ? JSON.parse(args) : args
const brief = input.brief
const MODULES = input.modules
const HIGH_EFFORT = new Set(input.high_effort || [])

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['module', 'clean_note', 'findings'],
  properties: {
    module: { type: 'string' },
    clean_note: {
      type: 'string',
      description: 'What you checked in this module that looks SAFE/correctly-mitigated. One or two sentences for the coverage table.',
    },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'title', 'file', 'lines', 'category', 'kind', 'severity_guess', 'attacker_input', 'preconditions', 'exploit_sketch', 'suggested_fix', 'confidence'],
        properties: {
          id: { type: 'string', description: 'short slug, unique within module, e.g. query-nested-recursion' },
          title: { type: 'string' },
          file: { type: 'string' },
          lines: { type: 'string', description: 'line or range, e.g. 215-228' },
          category: { type: 'string', enum: ['a_unintended_behaviour', 'b_resource_exhaustion', 'c_crypto_serialization'] },
          kind: { type: 'string', enum: ['vulnerability', 'hardening'] },
          severity_guess: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          attacker_input: { type: 'string', description: 'the literal request element / input the attacker controls' },
          preconditions: { type: 'string', description: 'config / deployment conditions required for this to be exploitable' },
          exploit_sketch: { type: 'string', description: 'concrete input and expected impact' },
          suggested_fix: { type: 'string' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['verdict', 'reasoning', 'corrected_severity', 'refutation_attempt'],
  properties: {
    verdict: { type: 'string', enum: ['real', 'refuted', 'needs_info'] },
    reasoning: { type: 'string' },
    corrected_severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low', 'none'] },
    refutation_attempt: { type: 'string', description: 'the strongest argument you found that this is NOT exploitable' },
  },
}

const REPORT_SCHEMA = {
  type: 'object',
  required: ['markdown', 'cve_candidates'],
  properties: {
    markdown: { type: 'string', description: 'the complete report body in GitHub-flavored markdown' },
    cve_candidates: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'module', 'severity', 'cvss_vector', 'rationale'],
        properties: {
          title: { type: 'string' },
          module: { type: 'string' },
          severity: { type: 'string' },
          cvss_vector: { type: 'string' },
          rationale: { type: 'string' },
        },
      },
    },
  },
}

function reviewPrompt(m) {
  return `You are a senior application-security auditor reviewing ONE module of a codebase for vulnerabilities.

${brief}

YOUR TARGET MODULE: ${m}

Steps:
1. Read the ENTIRE target file. Then read any closely-related files it calls into that handle the same untrusted input, to confirm whether a concern is real or already mitigated. Use Grep to trace how attacker input flows in.
2. Hunt specifically for the three vulnerability categories (a) unintended behaviour, (b) resource exhaustion, (c) crypto/serialization, as defined in the threat model.
3. For each genuine issue, produce a finding with an exact file:line, the attacker-controlled input, the control-flow path, and a concrete exploit sketch. Verify the bad path is actually reachable before reporting it.
4. Record a one-to-two sentence clean_note summarizing what you checked that looks correctly handled (used for the coverage table).

Be rigorous and concrete. Prefer a few high-confidence findings over many speculative ones. If the module is genuinely clean, return an empty findings array with a clean_note. Return ONLY the structured output.`
}

function verifyPrompt(f, idx) {
  const angles = [
    'Focus on REACHABILITY: trace the actual call graph from an inbound request/input and prove whether attacker input can reach the cited line in a default deployment. If a guard sits in the path, the finding is refuted.',
    'Focus on IMPACT REALISM: even if reachable, does the claimed effect actually occur? For DoS, estimate the real cost vs input size and existing limits. For logic bugs, construct the exact input and reason about the true outcome.',
    'Focus on PRIOR MITIGATION and DUPLICATION: is this already fixed/bounded in the code as written, already a documented/known issue, or only triggerable by misconfiguration rather than a remote attacker?',
  ]
  return `You are a skeptical security reviewer. Your job is to REFUTE the following candidate finding, not to confirm it.

${brief}

CANDIDATE FINDING (JSON):
${JSON.stringify(f, null, 2)}

${angles[idx % angles.length]}

Read the ACTUAL code at ${f.file} (lines ${f.lines}) and any functions in the data path. Try hard to show the finding is NOT a real, remotely-exploitable vulnerability. Only return verdict='real' if, after a genuine refutation attempt, you are convinced an attacker can trigger it with the described impact. Default to 'refuted' when the exploit cannot be constructed or is already mitigated; use 'needs_info' only if reachability genuinely cannot be determined from the source. Set corrected_severity to your independent assessment ('none' if refuted). Return ONLY the structured output.`
}

const SEV_RANK = { critical: 4, high: 3, medium: 2, low: 1, none: 0 }
function pickSeverity(realVotes, fallback) {
  const sevs = realVotes.map((v) => v.corrected_severity).filter((s) => s && s !== 'none')
  if (sevs.length === 0) return fallback
  return sevs.reduce((best, s) => (SEV_RANK[s] > SEV_RANK[best] ? s : best), 'low')
}

async function verifyFinding(f) {
  const n = f.severity_guess === 'critical' || f.severity_guess === 'high' ? 3 : 1
  const votes = await parallel(
    Array.from({ length: n }, (_unused, i) => () =>
      agent(verifyPrompt(f, i), { label: `verify:${f.id}#${i + 1}`, phase: 'Verify', schema: VERDICT_SCHEMA })
    )
  )
  const real = votes.filter(Boolean)
  const realCount = real.filter((v) => v.verdict === 'real').length
  const confirmed = realCount * 2 > n // strict majority
  return {
    ...f,
    confirmed,
    votes_real: realCount,
    votes_total: n,
    final_severity: pickSeverity(real.filter((v) => v.verdict === 'real'), f.severity_guess),
    verdicts: real,
  }
}

phase('Review')
const results = await pipeline(
  MODULES,
  (m) =>
    agent(reviewPrompt(m), {
      label: `review:${m.split('/').slice(-2).join('/')}`,
      phase: 'Review',
      schema: FINDINGS_SCHEMA,
      effort: HIGH_EFFORT.has(m) ? 'high' : 'medium',
    }),
  (review, m) => {
    const findings = (review && review.findings) || []
    return parallel(findings.map((f) => () => verifyFinding(f))).then((verified) => ({
      module: (review && review.module) || m,
      clean_note: (review && review.clean_note) || '',
      findings: verified.filter(Boolean),
    }))
  }
)

const rows = results.filter(Boolean)
const confirmed = rows.flatMap((r) => r.findings.filter((f) => f.confirmed))
// Keep the refuted candidates (with the strongest refutation reason) so the report can
// document WHY each was dismissed, not just a count - this is what makes a clean audit
// re-traceable instead of a bare "0 findings".
const refuted = rows.flatMap((r) =>
  r.findings
    .filter((f) => !f.confirmed)
    .map((f) => ({
      title: f.title,
      file: f.file,
      lines: f.lines,
      severity_guess: f.severity_guess,
      refutation: ((f.verdicts || []).map((v) => v.refutation_attempt || v.reasoning).filter(Boolean))[0] || '',
    }))
)
const refutedCount = refuted.length
const coverage = rows.map((r) => ({
  module: r.module,
  clean_note: r.clean_note,
  total: r.findings.length,
  confirmed: r.findings.filter((f) => f.confirmed).length,
}))

log(`Review+verify complete: ${confirmed.length} confirmed, ${refutedCount} refuted across ${rows.length} modules`)

phase('Synthesize')
const synthPrompt = `You are the lead auditor compiling the final internal security report for this codebase.

${brief}

CONFIRMED FINDINGS (survived adversarial verification), JSON:
${JSON.stringify(confirmed, null, 2)}

PER-MODULE COVERAGE (what was reviewed and per-module clean notes), JSON:
${JSON.stringify(coverage, null, 2)}

REFUTED CANDIDATES (investigated during verification and dismissed - these must NOT appear as findings, but you SHOULD document why they were dismissed), JSON:
${JSON.stringify(refuted, null, 2)}

Produce a complete, well-structured internal report in GitHub-flavored markdown ('markdown' field). It MUST contain, in order:
1. A title and a 2-4 sentence executive summary (how many modules reviewed, confirmed findings by severity, headline risk). If there are zero confirmed findings, say so plainly and frame it as the expected, high-confidence outcome rather than an absence of work.
2. '## Scope & method' - per-module review, adversarial verification, threat model in one paragraph. State this is an internal report and that nothing was filed/published.
3. '## Coverage' - a markdown table: Module | Confirmed findings | Notes (use clean_note). One row per module in the coverage data.
4. '## Findings' - for EACH confirmed finding, a '###' subsection with: severity (assign a CVSS 3.1 base score AND vector string), category, affected code as file:line, attacker input, preconditions, a concrete proof-of-concept (literal input + a short runnable snippet if useful), impact, and a suggested fix. Order by severity (critical first). Dedupe findings that are the same root cause surfaced via multiple modules into one finding noting all entry points.
   - IMPORTANT - never leave this section empty. When there are NO confirmed findings, replace the finding subsections with a 'Probes (not a finding)' log: a '###' subsection for the highest-value paths that were examined and dismissed (drawn from the REFUTED CANDIDATES above and the most security-relevant points in the per-module clean notes), each stating the path (file:line), what was suspected, and the concrete reason it is NOT attacker-reachable. The goal is that a future reader can re-trace the reasoning instead of re-deriving it - a clean audit is a record of what was checked, not a blank.
5. '## CVE-worthiness' - which findings, if any, would justify a CVE / coordinated disclosure, and why. Be conservative and honest; if none rise to that bar, say so explicitly.
6. '## Hardening suggestions' - an appendix listing kind='hardening' items briefly (or "None" with a one-line justification).
7. '## Refuted / out of scope' - summarize the ${refutedCount} refuted candidate(s) with the one-line reason each was dismissed (use the REFUTED CANDIDATES data; if a probe is already detailed in the Findings 'Probes' log, a back-reference is fine), plus what was out of scope per the threat model.

Also fill 'cve_candidates' with the subset of findings you judge CVE-worthy (empty array if none). Be precise and cite real line numbers. Return ONLY the structured output.`

const report = await agent(synthPrompt, { label: 'synthesize-report', phase: 'Synthesize', schema: REPORT_SCHEMA })

return { report, confirmed_count: confirmed.length, refuted_count: refutedCount, coverage }
