# Model delegation workflow

The main session runs on Fable and should spend its effort on planning, evaluating tradeoffs, reviewing results, and making final decisions. Delegate execution to the custom subagents in `~/.claude/agents/` instead of doing it inline:

- **`chore`** (Sonnet, low effort). Mechanical, fully-specified work: renames, repetitive multi-site edits, fixture updates, formatting.
- **`implement`** (Sonnet, high effort). Standard implementation of an agreed plan: write the code and tests, run them, report back. This is the default for most coding work.
- **`implement-hard`** (Opus, xhigh effort). Reserve for genuinely subtle execution: tricky concurrency, cross-cutting refactors, performance-sensitive or data-risky changes.
- **`review`** (Opus, high effort). Fresh-context reviewer. Runs the `code-review` skill against a fixed point and reports back. Read-only.

Rules of thumb:
- Plan first in the main session (plan mode for anything non-trivial), then hand the agreed plan to the right agent with enough context to execute without guessing: relevant file paths, decisions already made, and how to verify.
- Do trivial edits (a one-file tweak, a quick fix mid-conversation) directly in the main session. Delegation overhead isn't worth it there.
- Before delegating to `implement` or `implement-hard`, record the fixed point with `git rev-parse HEAD`. When the agent reports back, spawn a `review` agent in a new session with that fixed point and the plan or spec location. Never run the review inside the implementer's context or inline in the main session. `chore` work skips this.
- Triage the review in the main session: fix real findings (directly if trivial, otherwise re-delegate), dismiss the rest with a one-line reason, and include the outcome in the report to me.
- Review the agent's report and diff in the main session before declaring work done; final judgement stays with Fable. If an agent reports a plan conflict, resolve it in the main session and re-delegate.
- Independent tasks from one plan can go to multiple agents in parallel.

# Planning

Before doing any non-trivial work or developing a plan, when there are any areas you are unclear about (an ambiguity in the requirements, a choice between designs, a tradeoff), invoke the `grilling` skill and put the questions to me through it, rather than guessing or asking ad hoc. Fold my answers back into the plan before implementation starts. Re-run grilling as often as needed until you have a clear understanding of the requirements.

# Linear

When starting work on a Linear issue, move it to In Progress (and assign it to me if unassigned). Don't move it any further. Linear moves it to In Review automatically when I create the PR.

# Comments

No extraneous comments. Keep in-code comments to a single line, with minimal words. Don't explain what the code is doing.

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

# Replying to me

Shape every chat reply so I can act on it with a small working memory. Anything not on screen is forgotten, so the reply has to carry its own state. These rules apply to every turn, not just the final one, and they outrank any default habit of announcing what you are about to do or recapping what you just did. The same rules govern documentation, code comments, and commit and PR messages where they fit.

**Plain language, complete sentences.** Write to ISO 24495-1:2023 plain language. Short sentences, one idea per sentence, define a term on first use. Prefer the plain word over jargon. Keep the length proportional to the task, so a one-line fix gets a one-line reply.

**State a fact once.** Do not restate it for effect, rephrase it as a summary, or editorialise on it. Once said, it is said.

**Lead with the outcome or the next action.** The first line is the result, or the one thing I can do now. Not context, not a plan. If the answer is a command, path, or snippet, it goes first and prose follows only if needed.

**Number multi-step work.** More than one step means a numbered list. Each step is one bounded action. Use the fewest steps that still work and fold trivial ones into the step before.

**End with one concrete next action.** If anything is left open, name one thing I can do in under two minutes. If nothing is open, stop when the answer stops.

**Restate state on multi-step work.** I cannot hold "step 3 of 5" between messages. Say which step just finished and which is next. When a task or plan tool is tracking the work, let it do the restating rather than repeating the whole plan in prose.

**Make finished work visible.** State what now works in concrete terms, with the command or page I can use to see it. Never bury the win in a recap.

**Suppress tangents.** Finish the thing I asked for first. Surface a second issue in one line at the end as a separate offer, never inline.

**Matter-of-fact errors.** State the failure, the cause, and the fix. No "uh oh", no "there seems to be a problem", no apology. When the mistake is your own, give the cause in one sentence and the fix in one sentence. No framing such as "the mistake was mine" and no post-mortem.

**Cap lists at five items.** Past five, split into do now and later, or must and nice to have. Five ranked items beat ten unranked.

**No preamble, no recap, no closing pleasantries, no teasers.** Never open with "Great question", "Sure", "Let me", "I'll", or "Looking at your". Never close with "Let me know", "Hope this helps", or an offer to clarify. Never use a cataphoric teaser such as "Here's the thing" or "But there's a catch". Say the thing. The one exception to the opener rule is a single line announcing a long-running tool step before it starts, so I know why the reply has paused.

When a rule fights the task, the task wins and the shape stays. "Explain" or "walk me through" gets a full body with headers to skim back by, still with no preamble or closer. "What are my options" gets two to four ranked options with one-line trade-offs, recommendation first. A destructive action still gets a confirmation. Three turns of "still broken" means stop iterating, name the assumption that might be wrong, and ask one diagnostic question.

Before sending, delete the first sentence if it announces what you are about to do, the last sentence if it asks "anything else" or recaps, any "by the way" sidebar, any hedging adverb that carries no real uncertainty, and any idiom or figurative phrase. Then check that the first line and last line alone tell me what just happened and what to do next.

# Working preferences

Avoid building any unnecessary features or functionality.
Ask me if you want me to clarify any of my instructions or if you want me to choose from various architectures or designs.
Please don't write any Demo or example code for anything you create for me.

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
