# Issue tracker: Linear

Issues and specs for this repo live in Linear, team `<team>`. Issue identifiers look like `<TEAMKEY>-123`. Branch names of the form `<user>/<teamkey>-123-<slug>` refer to that issue.

## Conventions

- **Create**: create the issue with the connector, setting the title, the description as markdown, the team from this file, the state `Backlog`, and no assignee. Choose the project per the rule below.
- **Read**: fetch the issue by identifier with the connector, including its comments and its blocking relations.
- **List**: list issues with the connector, filtered by team, state, parent, label, or query as needed.
- **Comment**: add a comment to the issue with the connector.
- **State changes**: only what a skill explicitly asks for. Starting work on an issue moves it to `In Progress` and assigns it to me (this is the standing rule in `~/.claude/CLAUDE.md`). Never move an issue further than asked.
- **Labels**: apply triage labels only if a triage labels mapping file exists alongside this one. Otherwise skip the `ready-for-agent` step entirely; a fully specified issue sitting in Backlog is the agent-ready signal. Never create labels other than `wayfinder:map`.

## Choosing a project

1. **Inherit**. Tickets broken out of a spec issue take that issue's project. Wayfinder children take the map's project.
2. **Infer**. If the current branch or the conversation names a Linear issue, use that issue's project.
3. **Ask**. Otherwise list the team's active projects with the connector and ask the user to pick one or say none. Never pick silently and never store a default project in this file.

## When a skill says "publish to the issue tracker"

Create a Linear issue as above.

## When a skill says "fetch the relevant ticket"

Fetch the issue by identifier with comments.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`. Create the label in the team the first time it is needed if it doesn't exist. Body holds Destination / Notes / Decisions so far / Fog.
- **Child ticket**: a sub-issue of the map, parent set to the map. First line of the description is `Type: research|prototype|grilling|task`. No per-type labels.
- **Blocking**: Linear's native blocked-by relation, set when creating the child. A ticket is unblocked when every blocker is Done or Canceled.
- **Frontier**: list the map's open children, drop any with an open blocker or an assignee, first in map order wins.
- **Claim**: assign the ticket to me. The session's first write.
- **Resolve**: comment the answer on the ticket, move it to Done, then append a gist and link to the map's Decisions so far.
