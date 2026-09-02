# Locating this repo's agent docs

How to find this repo's agent docs: the tracker file, the domain file, triage labels, the glossary (`CONTEXT.md`), and ADRs. Every consumer skill resolves the layout this way rather than assuming a path.

Run the lookup from the repo root of the current checkout. Every worktree of the same repo resolves to the same external directory.

## Resolution order

1. `docs/agents/` exists at the repo root. In-repo layout.
2. Else derive `<owner>/<repo>` from `git remote get-url origin`. The host may be GitHub, GitLab or anything else. Handle `https://<host>/owner/repo.git`, `https://<host>/owner/repo`, and `git@<host>:owner/repo.git`, stripping a trailing `.git`. A repo with no `origin` remote can only use the in-repo layout. If `~/Developer/agent-docs/<owner>/<repo>/` exists, external layout.
3. Else unconfigured. Tell the user to run `/setup-braidon-skills`. Skills that can proceed without a tracker (the review agent, wayfinder falling back to local markdown) keep doing so.

## In-repo layout

- tracker file: `docs/agents/issue-tracker.md`
- domain file: `docs/agents/domain.md`
- triage labels: `docs/agents/triage-labels.md`
- glossary: `CONTEXT.md`, ADRs: `docs/adr/`
- multi-context: `CONTEXT-MAP.md` at the root, `src/<context>/CONTEXT.md`, `src/<context>/docs/adr/` (existing convention, keep it)

## External layout

`<root>` is `~/Developer/agent-docs/<owner>/<repo>`.

- tracker file: `<root>/agents/issue-tracker.md`
- domain file: `<root>/agents/domain.md`
- triage labels: `<root>/agents/triage-labels.md`
- glossary: `<root>/CONTEXT.md`, ADRs: `<root>/adr/`
- multi-context: `<root>/CONTEXT-MAP.md`, `<root>/<context>/CONTEXT.md`, `<root>/<context>/adr/`, where `<context>` is the project's path relative to the repo root (for example `super_api`, `xonboard`, `scf`)

## Read the domain file

Whichever layout resolves, the domain file describes the actual paths for that repo. Read it rather than guessing.
