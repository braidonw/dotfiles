---
name: setup-braidon-skills
description: "Configure this repo for the engineering skills: set up its issue tracker, docs location, triage label vocabulary, and domain doc layout. Run once before first use of the other engineering skills."
disable-model-invocation: true
---

# Setup Braidon's Skills

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker**: where issues live (GitHub by default; GitLab, Linear, and local markdown are also supported out of the box)
- **Docs location**: whether agent docs live in-repo or in the external `~/Developer/agent-docs/<owner>/<repo>/` tree
- **Triage labels**: the strings used for the five canonical triage roles
- **Domain docs**: where `CONTEXT.md` and ADRs live, and the consumer rules for reading them

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## Process

### 1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config`: is this a GitHub repo? Which one?
- `AGENTS.md` and `CLAUDE.md` at the repo root: does either exist? Is there already an `## Agent skills` section in either?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/`: does this skill's prior output already exist in-repo?
- `~/Developer/agent-docs/<owner>/<repo>/` (owner and repo from `git remote get-url origin`): does this skill's prior output already exist externally?
- `.scratch/`: a sign that a local-markdown issue tracker convention is already in use
- Is the `triage` skill installed? (a `triage` skill folder alongside this one, or `triage` in your available skills.) This decides whether Section C runs at all.
- Monorepo signals: a `pnpm-workspace.yaml`, a `workspaces` field in `package.json`, a populated `packages/*` with its own `src/`, or several project directories each carrying their own `CLAUDE.md`, `justfile`, `mix.exs`, `Gemfile`, or `package.json` (a repo with per-project `CLAUDE.md` files and no pnpm workspace is still a monorepo). These are present only in a genuinely large multi-package repo; their absence means single-context, which is almost every repo.

### 2. Present findings and ask

Summarise what's present and what's missing. Then take the sections in order. One section, one answer, then the next.

Lead each section with the recommended answer so the user can accept it in a word. Give a one-line explainer only when the choice genuinely branches; skip the section entirely when exploration already settled it (Section C when `triage` isn't installed, Section D when there's no monorepo).

**Section A: Issue tracker.**

> Explainer: The "issue tracker" is where issues live for this repo. Skills like `to-tickets`, `triage`, and `to-spec` read from and write to it. They need to know whether to call `gh issue create`, create a Linear issue through the connector, write a markdown file under `.scratch/`, or follow some other workflow you describe. Pick the place you actually track work for this repo.

Default posture: these skills were designed for GitHub. If a `git remote` points at GitHub, propose that. If a `git remote` points at GitLab (`gitlab.com` or a self-hosted host), propose GitLab. Offer Linear whenever the user tracks work outside the forge, regardless of what the remote points at. Otherwise (or if the user prefers), offer:

- **GitHub**: issues live in the repo's GitHub Issues (uses the `gh` CLI)
- **GitLab**: issues live in the repo's GitLab Issues (uses the [`glab`](https://gitlab.com/gitlab-org/cli) CLI)
- **Linear**: issues live in Linear, via the Linear MCP connector (tool names starting `mcp__claude_ai_Linear__`). Once the user picks Linear, ask which team, listing the available teams via the connector. When writing the Linear template, replace `<team>` with the team name and `<TEAMKEY>` and `<teamkey>` with the team's issue key.
- **Local markdown**: issues live as files under `.scratch/<feature>/` in this repo (good for solo projects or repos without a remote)
- **Other** (Jira, etc.): ask the user to describe the workflow in one paragraph; the skill will record it as freeform prose

Record the choice in the tracker file (see Section B for where that file lives). The GitHub and GitLab templates carry a "PRs as a request surface" flag, defaulted **off**. Leave it off and don't raise it: a user who wants external PRs in the triage queue can flip the flag in the file later. See [issue-tracker-linear.md](./issue-tracker-linear.md) for the Linear template.

**Section B: Docs location.**

> Explainer: agent docs (the tracker file, domain file, triage labels, glossary, ADRs) can live inside this checkout or in an external directory outside it. External keeps everything out of the checkout, and every worktree of this repo resolves to the same directory.

Default to **in-repo** (today's behaviour, described in Section D). Propose **external** when the repo is shared with a team whose conventions the user does not own.

- **In-repo**: `docs/agents/`, `CONTEXT.md`, and `docs/adr/` at the repo root.
- **External**: `~/Developer/agent-docs/<owner>/<repo>/`, where owner and repo come from `git remote get-url origin`. Nothing is written into the checkout: no `CLAUDE.md` block, no pointer file, no `.gitignore` change.

**Section C: Triage label vocabulary.** Skip this section entirely if the `triage` skill isn't installed (exploration told you), since an uninstalled skill needs no labels.

If it is installed, ask exactly one question:

> Do you want to keep the default triage labels? (recommended: **yes**)

The defaults are the five canonical roles, each label string equal to its name: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. On **yes**, write them as-is. Only if the user says no, usually because their tracker already uses other names (e.g. `bug:triage` for `needs-triage`), collect the overrides so `triage` applies existing labels instead of creating duplicates.

**Section D: Domain docs.** Default to **single-context** (one glossary + one ADR directory at the domain docs root). This fits almost every repo; write it without asking.

Offer **multi-context** (a root `CONTEXT-MAP.md` pointing to per-context `CONTEXT.md` files) only when exploration found monorepo signals. Then confirm which layout they want.

Either way, the written `domain.md` states the actual root and per-context paths for the location chosen in Section B.

### 3. Confirm and edit

In-repo mode, show the user a draft of:

- The `## Agent skills` block to add to whichever of `CLAUDE.md` / `AGENTS.md` is being edited (see step 4 for selection rules)
- The contents of `docs/agents/issue-tracker.md`, `docs/agents/domain.md`, and `docs/agents/triage-labels.md` (the last only when `triage` is installed)

External mode has no `CLAUDE.md` block to show. Show the files instead, each with its absolute path under `~/Developer/agent-docs/<owner>/<repo>/`.

Let them edit before writing.

### 4. Write

**In-repo mode:**

Pick the file to edit:

- If `CLAUDE.md` exists, edit it.
- Else if `AGENTS.md` exists, edit it.
- If neither exists, ask the user which one to create; don't pick for them.

Never create `AGENTS.md` when `CLAUDE.md` already exists (or vice versa); always edit the one that's already there.

If an `## Agent skills` block already exists in the chosen file, update its contents in-place rather than appending a duplicate. Don't overwrite user edits to the surrounding sections.

The block:

```markdown
## Agent skills

### Issue tracker

[one-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Triage labels

[one-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Domain docs

[one-line summary of layout: "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

Include the `### Triage labels` sub-block, and write `docs/agents/triage-labels.md`, only when `triage` is installed and Section C ran. When it isn't, both are omitted.

Then write the docs files using the seed templates in this skill folder as a starting point:

- [issue-tracker-github.md](./issue-tracker-github.md): GitHub issue tracker
- [issue-tracker-gitlab.md](./issue-tracker-gitlab.md): GitLab issue tracker
- [issue-tracker-linear.md](./issue-tracker-linear.md): Linear issue tracker
- [issue-tracker-local.md](./issue-tracker-local.md): local-markdown issue tracker
- [triage-labels.md](./triage-labels.md): label mapping (only if `triage` is installed)
- [domain.md](./domain.md): domain doc consumer rules + layout

For "other" issue trackers, write the tracker file from scratch at the location chosen in Section B, using the user's description. This applies in both modes.

In both modes, fill in the `Location:` and `Contexts:` lines at the top of `domain.md` with the real values (in-repo, or external with the absolute root, and one line per context with its path for multi-context). No placeholder text ships in the written file.

**External mode:**

If `~/Developer/agent-docs/` does not exist, `git init` it and tell the user to create the private remote themselves (for example `gh repo create braidonw/agent-docs --private --source ~/Developer/agent-docs`). Never create a remote yourself.

Write `<root>/agents/issue-tracker.md`, `<root>/agents/domain.md`, and `<root>/agents/triage-labels.md` (only if `triage` is installed), where `<root>` is `~/Developer/agent-docs/<owner>/<repo>/`, using the same seed templates as in-repo mode. For multi-context, also write an initial `<root>/CONTEXT-MAP.md` listing the contexts with their paths. Create the per-context directories lazily, not at setup.

Commit the scaffold in the agent-docs repo with a short message.

Do not touch the project checkout: no `CLAUDE.md` or `AGENTS.md` edit, no pointer file, no `.gitignore` change.

### 5. Done

Tell the user the setup is complete, which location was written (in-repo, or the external root), and that the other engineering skills find it via [locate.md](./locate.md). Mention they can edit the docs files directly later; re-running this skill is only necessary if they want to switch issue trackers, switch locations, or restart from scratch.
