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

# Working preferences

Avoid building any unnecessary features or functionality.
Ask me if you want me to clarify any of my instructions or if you want me to choose from various architectures or designs.
Please don't write any Demo or example code for anything you create for me.
Run tests with each project's `just test <file>` (or `just test-all` where it exists). To run something else in the container, check that project's `justfile` for the recipe. In super_api it's `just bash-run <command>`; elsewhere it's usually an interactive `just bash`.

# Elixir

Before writing, editing, or refactoring any Elixir code, load the `elixir-style` skill and follow its reference files. It is the canonical house rule catalog (control flow, error handling, OTP, Ecto, Oban, Phoenix, maintainability, testing) with rationale and examples. The `elixir-review` skill reads the same catalog for reviews. Project CLAUDE.md files override it where they conflict.

Non-negotiables, in force even before the skill loads:

- No `_ ->` catch-all clauses on `case` expressions over our own enums, statuses, or tagged tuples.
- No `with`/`else` for error translation. Use explicit `case` with the error-to-outcome clauses inlined; a `with` without `else` is fine.
- Two levels of nested conditionals is fine, three is not. Extract helpers that do real work, never one-line renamers or single-caller wrappers.
- No silent failures. Fail loudly on unknown input instead of defaulting.
- Don't handle errors that can't happen. Use the bang variant (`Oban.insert!`, `Repo.insert!`) and let it crash; functions whose contract is to raise carry a `!` suffix.
- Bound everything that can grow: explicit timeouts on user-facing external calls, back-pressure on producer/consumer pairs, ceilings on retries, size limits on external input.
- Queries live as named functions on the owning context module. No `query.ex` modules, no queries built inline at callsites.
- Units live in names (`timeout_ms`, `amount_cents`); predicates end in `?` and never start with `is_`.
- Prefer deep modules with small public surfaces. A context module is its domain's front door, and internal-only functions are `defp`.
- Integration tests through the context's public functions over unit tests; real DB via the sandbox and factories, Mox only at true external boundaries.
