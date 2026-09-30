# Triage Labels: Linear

The skills speak in terms of two category roles and five state roles. On Linear, states are workflow states plus a comment heading, so no triage labels are created. This file maps each role onto team `<team>`.

| Role | In Linear |
| --- | --- |
| `bug` | `<bug label>` label |
| `enhancement` | `<feature label>` label for new behaviour, `<improvement label>` label for changes to existing behaviour |
| `needs-triage` | `Triage` state |
| `needs-info` | `Triage` state, and the latest triage comment is headed `## Triage Notes` |
| `ready-for-agent` | `Backlog` state, with a comment headed `## Agent Brief` |
| `ready-for-human` | `Backlog` state, with a comment headed `## Human Brief` |
| `wontfix` | `Canceled` state, or `Duplicate` state for a duplicate |

A skill that says "apply the `ready-for-agent` label" moves the issue to the state and posts the comment in the right-hand column.
