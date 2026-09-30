---
name: retro
description: "Conduct a retrospective on a coding session."
---

The user has asked for a **retrospective**. You are suggesting improvements to the coding agent's **environment** to improve future runs.

## Steps

1. Load the `writing-for-agents` skill for the writing style guide.

2. Read the primary sources for the session the user specifies. Claude Code transcripts live at `~/.claude/projects/<cwd-slug>/<session-id>.jsonl`, where the slug is the working directory with `/` replaced by `-`. Search them with `grep` or `jq` rather than reading whole files, since one session can run to megabytes. If the user doesn't specify a session, default to the current one. Also read the memory index for that project (`~/.claude/projects/<cwd-slug>/memory/MEMORY.md`), because a memory that should have prevented a mistake and didn't is itself a finding.

3. Look for candidates for improvement in these categories.

- **Navigation**: how easy was it for the agent to find the right files? Are there hidden dependencies between files? Would a **navigation pointer** make it easier? _Use when_ the session took a long time to find a piece of information.
- **Automated checks**: are there automated checks that could catch errors the agent made? Read the repo's existing **guardrails** first (its `lefthook.yml`, `.credo.exs` and `.credo/checks/`, `biome.json` and its GritQL plugins, the CI workflows under `.github/workflows/`), so a check that already exists but sits unwired or silently broken is the finding, not a reinvention. A repo with no guardrail (no pre-commit hook and no CI job running its lint, typecheck or test command) is itself a finding. _Use when_ the agent made a mistake an automated check could have caught, or the repo has no guardrail at all.
- **Coding standards**: should the **reviewer agent** be given a new rule to enforce? Should an existing rule be removed or clarified? Classify the violation first. A **mechanical** one (a fixed syntactic pattern, a banned API, an alias shape, a file-location rule) gets a deterministic check. For Elixir that means a custom Credo check in `<app>/.credo/checks/`. For JS, TS and CSS it means a Biome GritQL plugin. For anything else, a lefthook hook. Default to building the check over writing the rule. Reserve prose rules for genuine **judgement calls** (cross-file consistency, matching the surrounding style, anything no guardrail could substitute for). Elixir judgement rules go in the `elixir-style` skill's reference files, which `elixir-review` reads during review. _Use when_ the reviewer agent failed to catch a mistake.
- **Steering files**: are there instructions in `CLAUDE.md` (repo, project, or the global `~/.agents/AGENTS.md`) that should move into a coding standard, a skill, or an automated check instead? _Use when_ a steering file is particularly large.
- **Tool economy**: did the agent make expensive tool calls that could be streamlined? Is there any custom tooling (CLIs, MCPs) that is particularly token-inefficient? _Use when_ the agent made an expensive tool call.
- **No-ops**: look for instructions in steering files that don't modify the agent's behavior. _Use when_ the steering files are large and unwieldy.
- **Information access**: look for opportunities to increase the agent's access to information. Teeing dev server logs, readonly access to third-party services. _Use when_ a crucial piece of information was not available to the agent.

4. Present these candidates to the user, in order of severity.

## Reference

### Implementation vs review

All work goes through two stages: implementation and review. The implementation agent has the most **context pressure**. It is responsible for exploration, writing code, and debugging failures.

The review agent (the `review` sub-agent running the `code-review` skill) has the least context pressure. It receives a diff, so no exploration is needed, and it often does not need to write code or debug.

So the review agent should be responsible for imposing coding standards, not the implementation agent.

### Files

- `CLAUDE.md` / `AGENTS.md`: pushed to the context window of every agent working in the repo, and the global `~/.agents/AGENTS.md` into every session on the machine. Use them sparingly, mostly for **navigation pointers** to other files.
- Coding standards: the `elixir-style` reference files for Elixir, and the Standards axis of `code-review`, which reads the repo's `CLAUDE.md` files. Both are read during review, not implementation.
- Docs: reference files, pointed to by other files. Look for existing docs before writing new ones. Agent docs for a repo (glossary, ADRs) are located per `~/.agents/skills/setup-braidon-skills/locate.md`.
- Skills: live in `~/.agents/skills/` (the dotfiles `agents` package) with a per-skill symlink in `~/.claude/skills/`. Use skills for reference whose description earns its place in context, or for user-invoked commands. Follow the `writing-for-agents` skill.
- Memory: `~/.claude/projects/<cwd-slug>/memory/`. For facts about the user or a project that no repo file should carry.
