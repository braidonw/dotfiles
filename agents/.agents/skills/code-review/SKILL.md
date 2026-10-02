---
name: code-review
description: "Review the changes since a fixed point (commit, branch, tag, or merge-base) along five axes: Standards (does the code follow this repo's documented coding standards?), Spec (does the code match what the originating issue/spec asked for?), Language (does it pass the language-specific review skill, such as elixir-review, when one is installed for the languages in the diff?), Codex (an independent second-model review via the OpenAI Codex CLI, skipped cleanly when Codex is unavailable), and Simplification (is there less code that does the same job?). Runs the reviews in parallel sub-agents and reports them side by side. Use when the user wants to review a branch, a PR, work-in-progress changes, a dual or two-model review, asks whether the code can be simplified, or asks to \"review since X\"."
---

Five-axis review of the diff between `HEAD` and a fixed point the user supplies:

- **Standards**: does the code conform to this repo's documented coding standards?
- **Spec**: does the code faithfully implement the originating issue / spec?
- **Language**: does the code pass the language-specific review skill (for example `elixir-review`) for each language in the diff? Only runs when such a skill is installed.
- **Codex**: what does a different model, with no stake in this session, see? OpenAI Codex reviews the same diff through the Codex CLI and its findings are triaged against the real code.
- **Simplification**: is there less code that does the same job? Single-caller indirection, handling for errors that cannot happen, and work the repo already does elsewhere.

Standards, Spec and Language are in-house lenses pointed at conventions. Codex is the outside eye, and it tends to catch cross-cutting things the lenses skip (build wiring, infra, config, plain correctness bugs). Simplification is pointed at subtraction rather than at conformance or correctness, so it is the axis with something to say about a diff the other four pass. Where two axes independently flag the same site, that agreement is the strongest signal in the report.

All axes run as **parallel sub-agents** so they don't pollute each other's context, then this skill aggregates their findings.

Locate this repo's agent docs per `~/.agents/skills/setup-braidon-skills/locate.md`. If no tracker file resolves, tell the user to run the setup-braidon-skills skill.

## Process

### 1. Pin the fixed point

Whatever the user said is the fixed point (a commit SHA, branch name, tag, `main`, `HEAD~5`, etc.). If they didn't specify one, ask for it.

Capture the diff command once: `git diff <fixed-point>...HEAD` (three-dot, so the comparison is against the merge-base). Also note the list of commits via `git log <fixed-point>..HEAD --oneline`.

If the working tree has uncommitted changes (`git status --porcelain` is non-empty), they are part of the review. Use `git diff $(git merge-base <fixed-point> HEAD)` instead, which compares the working tree against the merge-base, and say in the final report that uncommitted work was included.

Before going further, confirm the fixed point resolves (`git rev-parse <fixed-point>`) and the diff is non-empty. A bad ref or empty diff should fail here, not inside two parallel sub-agents.

### 2. Identify the spec source

Look for the originating spec, in this order:

1. Issue references in the commit messages (`#123`, `Closes #45`, GitLab `!67`, etc.), fetched via the workflow in the tracker file.
2. A path the user passed as an argument.
3. A spec file under `docs/`, `specs/`, `.scratch/`, or the external agent docs root from the lookup above, matching the branch name or feature.
4. If nothing is found, ask the user where the spec is. If they say there isn't one, the **Spec** sub-agent will skip and report "no spec available".

### 3. Identify the standards sources

Anything in the repo that documents how code should be written, such as `CODING_STANDARDS.md` or `CONTRIBUTING.md`.

On top of whatever the repo documents, the Standards axis always carries the **smell baseline** below: a fixed set of Fowler code smells (_Refactoring_, ch.3) that applies even when a repo documents nothing. Two rules bind it:

- **The repo overrides.** A documented repo standard always wins; where it endorses something the baseline would flag, suppress the smell.
- **Always a judgement call.** Each smell is a labelled heuristic ("possible Feature Envy"), never a hard violation. Like any standard here, skip anything tooling already enforces.

Each smell reads *what it is* → *how to fix*; match it against the diff:

- **Mysterious Name**: a function, variable, or type whose name doesn't reveal what it does or holds. → rename it; if no honest name comes, the design's murky.
- **Duplicated Code**: the same logic shape appears in more than one hunk or file in the change. → extract the shared shape, call it from both.
- **Feature Envy**: a method that reaches into another object's data more than its own. → move the method onto the data it envies.
- **Data Clumps**: the same few fields or params keep travelling together (a type wanting to be born). → bundle them into one type, pass that.
- **Primitive Obsession**: a primitive or string standing in for a domain concept that deserves its own type. → give the concept its own small type.
- **Repeated Switches**: the same `switch`/`if`-cascade on the same type recurs across the change. → replace with polymorphism, or one map both sites share.
- **Shotgun Surgery**: one logical change forces scattered edits across many files in the diff. → gather what changes together into one module.
- **Divergent Change**: one file or module is edited for several unrelated reasons. → split so each module changes for one reason.
- **Speculative Generality**: abstraction, parameters, or hooks added for needs the spec doesn't have. → delete it; inline back until a real need shows.
- **Message Chains**: long `a.b().c().d()` navigation the caller shouldn't depend on. → hide the walk behind one method on the first object.
- **Middle Man**: a class or function that mostly just delegates onward. → cut it, call the real target direct.
- **Refused Bequest**: a subclass or implementer that ignores or overrides most of what it inherits. → drop the inheritance, use composition.

### 4. The simplification baseline

The Simplification axis carries its own fixed catalog, the way Standards carries the smell baseline. It answers one question and no other. Is there less code that does the same job? Codex asks whether the code is wrong, Language whether it is idiomatic, Standards whether it conforms, Spec whether it is what was asked. Runtime efficiency (an N+1, a missing preload, repeated work in a loop) belongs to the language review skill and to Codex. Keeping the question this narrow is what stops the axis becoming a second Codex.

Scope is the diff, plus pre-existing code whose simplification opportunity the diff *created*. A helper that had two callers and has one now because the diff removed the other is in scope. A messy module the diff merely sits beside is not.

Each item reads *what it is* → *what to remove*:

- **Single-caller indirection**: a private function, wrapper, module, or params struct with one caller and no meaning of its own. → inline it into the caller.
- **Unnecessary error handling**: a branch for an error that cannot happen, a defensive nil check on a value a contract guarantees, an error mapped to itself. → delete the branch, take the bang variant, let it crash.
- **Dead on arrival**: a clause, branch, or function no path reaches after this change. → delete it.
- **Ceremony**: an option, parameter, or default that carries the same value at every call site. → drop the parameter, hard-code the value.
- **Verbose control flow**: a `case`, `cond`, or `if` chain that collapses to a pattern match or a lookup with no loss of clarity. → collapse it.
- **Redundant binding**: a name bound once and used once on the next line. → inline the expression.
- **Reimplemented stdlib or framework**: hand-rolled what the standard library, the ORM, or the framework already does. → call the existing function.
- **Platform already does it**: app code or a new dependency doing what the platform provides (a database constraint, a unique index, a framework feature, a few lines in place of a package). → use the platform feature, drop the dependency.
- **Reinvented in-repo**: the diff builds something this codebase already provides. → call what exists. Search for it and cite it by name, or stay quiet. An uncited hunch that "a helper probably exists" is worse than no finding.
- **Test verbosity**: setup repeated across cases, mocking past the boundary under test, assertions that only restate the factory. Test files are in scope for every item above too.

Three rules bind the catalog:

- **Clarity outranks brevity.** Fewer lines is the measure only where the shorter version reads at least as well. A dense one-liner replacing a legible branch is a finding not worth making, and so is any merge of two things that change for different reasons.
- **Behaviour is fixed.** Every proposal is behaviour-identical. A change in what the code does belongs to another axis.
- **Documented rules are hard limits.** The standards sources from step 3 bind this axis as boundaries rather than as a checklist. A repo that documents deep modules, context front doors, or a layer between a job and its business logic pays for that indirection on purpose, and the axis reports such a site under "blocked by a documented rule" rather than proposing the breach.

Over-generalisation and comment pruning belong to Standards, as Speculative Generality and as the repo's own comment rule. This axis leaves both to it.

### 5. Identify language review skills

List the file extensions in the diff and map each to a language (`.ex`/`.exs` is Elixir, `.ts`/`.tsx` is TypeScript, `.rb` is Ruby, `.py` is Python, `.go` is Go, `.rs` is Rust, and so on). For each language, check whether a skill named `<language>-review` is available (`~/.agents/skills/<language>-review/SKILL.md`, `.agents/skills/<language>-review/SKILL.md` or `.claude/skills/<language>-review/SKILL.md` in the repo, or in your listed skills). Each match becomes one Language sub-agent, scoped to that language's files. Languages with no matching skill get no Language axis; say so in the final report so the user knows what wasn't covered.

### 6. Spawn all sub-agents in parallel

**Standards sub-agent prompt** should include:

- The full diff command and commit list.
- The list of standards-source files you found in step 3, **plus the smell baseline from step 3** pasted in full (the sub-agent has no other access to it).
- The brief: "Report, per file/hunk where relevant, (a) every place the diff violates a documented standard: cite the standard (file + the rule); and (b) any baseline smell you spot: name it and quote the hunk. Distinguish hard violations from judgement calls: documented-standard breaches can be hard, but baseline smells are always judgement calls, and a documented repo standard overrides the baseline. Skip anything tooling enforces. Under 400 words."
- When a Language sub-agent is running, the list of files it covers and the note: "Language idioms and conventions for those files are reviewed separately. Confine yourself to the documented standards and the smell baseline for them."

**Spec sub-agent prompt** should include:

- The diff command and commit list.
- The path or fetched contents of the spec.
- The brief: "Report: (a) requirements the spec asked for that are missing or partial; (b) behaviour in the diff that wasn't asked for (scope creep); (c) requirements that look implemented but where the implementation looks wrong. Quote the spec line for each finding. Under 400 words."

If the spec is missing, skip the Spec sub-agent and note this in the final report.

**Codex sub-agent prompt.** This axis is **on by default**. Skip it only when the request says to ("no codex", "no second model", "skip the second model"), and say in the final report that it was skipped by request. Also skip it when the host harness running this review is itself Codex, since the reviewer is then already the second model, and say so in the final report. Its prompt should include:

- The fixed point, and any focus area the user gave.
- The brief:

  > Run `~/.agents/skills/gpt-code-review/scripts/codex_review.sh --base <fixed-point>` (add `--focus "<text>"` if a focus was given). It takes 2-10 minutes. Run it in the foreground and wait for it. Then handle the exit code:
  >
  > - **0**: the last line is `REVIEW_SAVED: <path>`. Read that review, then invoke the `receiving-code-review` skill to weigh the findings. Apply no fixes. Open each cited line, read enough surrounding code and callers to judge the claim, and classify every finding Confirmed, Plausible (the reasoning holds but needs a run or prod data to verify), or Rejected against this repo's instruction files (AGENTS.md or CLAUDE.md) rather than generic taste. Report confirmed and plausible findings first, most severe first, as `file:line` plus what is wrong and the fix. Then rejected findings, one line each with the reason, so they can be overruled. Under 400 words, ending with the saved review path.
  > - **4**: Codex is unavailable, and its stderr carries `CODEX_UNAVAILABLE: <reason>`. Your whole report is one line, `Skipped: <reason>`.
  > - **3**: no diff against the base. Your whole report is one line, `Skipped: no diff against <fixed-point>`.
  > - **anything else**: report `Failed: <the error>` in a line or two.
  >
  > Whatever the exit code, your report is what the script produced. Reviewing the code yourself in Codex's place would put a second opinion from the host model where an independent one is supposed to be, and the other axes already cover the host model's view.

**Language sub-agent prompt** (one per language found in step 5) should include:

- The diff command from step 1, restricted to that language's files (append `-- <files>`), and the commit list.
- The instruction: "Invoke the `<language>-review` skill and carry it out fully against exactly this diff. Read enough surrounding code to judge each finding in context."
- The brief: "Report findings only, in the skill's own format and severity markers. Do not offer or apply fixes; that decision belongs to the aggregating session. Under 400 words."

**Simplification sub-agent prompt.** This axis is **on by default**. Skip it only when the request says to ("no simplification", "correctness only", "just the bugs"), and say in the final report that it was skipped by request. Its prompt should include:

- The full diff command and commit list.
- The **simplification baseline from step 4 pasted in full** (the sub-agent has no other access to it), and the list of standards-source files from step 3 as the boundaries it may not cross.
- The brief:

  > Apply the baseline to the diff. Verify every claim against the code before you make it. Grep the repo for callers before calling something single-caller and give the count. Read the callee's contract before calling an error branch unreachable. An unverified claim is a wrong finding.
  >
  > Report under three headings. **Clear wins**: behaviour-identical, strictly less code, no clarity cost. Name what gets deleted and give the line delta. Start each finding with its tag: `delete` (dead or single-caller code), `stdlib` (standard library or framework ships it), `native` (the platform does it), or `shrink` (same logic, fewer lines). **Judgement calls**: a real tradeoff exists, stated in one line so it can be overruled. **Blocked by a documented rule**: a simplification you would otherwise propose, with the rule that forbids it named.
  >
  > Each finding is `file:line`, what goes, and why, in a line or two. No code snippets. "Nothing worth simplifying" is a valid and expected report on a clean diff. Padding the section is a failure.
  >
  > Other axes cover idiom, conformance and correctness. Where one of them would flag a site you found, report it anyway. Agreement between axes is the most useful signal in this report, so suppressing your own finding destroys it. Under 400 words.

### 7. Aggregate

Present the reports under `## Standards`, `## Spec`, `## Codex`, `## Simplification`, and one `## Language: <name>` heading per Language sub-agent, verbatim or lightly cleaned. Do **not** merge or rerank findings, because the axes are deliberately separate (see _Why separate axes_). If the same defect shows up under Standards and Language, keep it in both and say so; agreement is signal, not duplication.

End with a summary: total findings per axis, and the worst issue _within each axis_ (if any). Don't pick a single winner across axes: that's the reranking the separation exists to prevent.

Under the summary, add a **corroboration** list: every site two or more axes flagged, one line each, naming the site and which axes raised it.

```
Corroborated: `lib/foo.ex:42` (Codex and Language). `lib/bar.ex:9` (Standards and Codex).
```

These are pointers, not findings. They preserve the agreement signal, which is the most reliable thing in the report, while every finding stays in the section that owns it.

## Why separate axes

A change can pass one axis and fail another:

- Code that follows every standard but implements the wrong thing → **Standards pass, Spec fail.**
- Code that does exactly what the issue asked but breaks the project's conventions → **Spec pass, Standards fail.**
- Code that meets the repo's documented standards and the spec but leans on a language anti-pattern the repo never wrote down → **Standards pass, Spec pass, Language fail.**
- Code that satisfies all three in-house lenses but carries a plain correctness bug, because every lens was pointed at conventions rather than behaviour → **Codex fail.**
- Code that is conformant, idiomatic, correct and exactly what the issue asked for, and still takes forty lines to say what fifteen would → **four passes, Simplification fail.**

Reporting them separately stops one axis from masking another.
