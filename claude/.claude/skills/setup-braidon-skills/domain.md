# Domain Docs

Location: <in-repo, or external with root `<absolute path>`>
Contexts: <none for single-context, or one line per context with its path>

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`**, or
- **`CONTEXT-MAP.md`** if it exists: it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **the ADR directory**: read ADRs that touch the area you're about to work in. In multi-context repos, also check the context-scoped ADR directory for context-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

In-repo, single-context (most repos):

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

In-repo, multi-context (presence of `CONTEXT-MAP.md` at the root):

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

External, single-context (`<root>` = `~/Developer/agent-docs/<owner>/<repo>`):

```
<root>/
├── CONTEXT.md
└── adr/
    ├── 0001-event-sourced-orders.md
    └── 0002-postgres-for-write-model.md
```

External, multi-context:

```
<root>/
├── CONTEXT-MAP.md
├── adr/                               ← system-wide decisions
├── ordering/
│   ├── CONTEXT.md
│   └── adr/                           ← context-specific decisions
└── billing/
    ├── CONTEXT.md
    └── adr/
```

Create files lazily in either location: only when you have something to write.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in the glossary. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
