---
name: writing-fragments
description: "Mine raw writing fragments for a future article, with no structure yet. Use when the user wants to gather material for something they plan to write."
argument-hint: "What do you want to write about?"
---

<what-to-do>

In Claude Code, run this session on Fable 5.1. If the session model is anything else, ask the user to run `/model fable` and wait for them before going on.

This is pure **explore**. Widen the space of what could be written without committing to structure. Committing is **exploit**, and it belongs to `/writing-shape` and `/writing-beats`. Leave phases, outlines and article structure to them.

Run a relentless interview that produces fragments. Question the user about whatever they want to write about, one question at a time. As fragments emerge from either side of the conversation, append them to a single markdown file.

Resolve where the file lives per `~/.agents/writing/STORAGE.md`.

Capture fragments from the very first thing the user says, including the initial prompt.

On first write, put a single H1 at the top with a working title (it can change later) and nothing else. No metadata, no TOC, no date.

When the user wants to start drafting, point them to `/writing-shape` or `/writing-beats` with the pile's slug or location.

</what-to-do>

<supporting-info>

## What is a fragment

A fragment is any piece of text that might survive into the final article. It must be _readable by the author_ (the author can tell what it means), but it does not need to define its terms or be comprehensible to a cold reader. The bar is "is this a piece of good writing?", not "is this a self-contained argument?"

Fragments are deliberately heterogeneous. Examples of what could be a fragment:

- A sharp sentence you'd want to deploy somewhere but don't yet know where.
- A claim with a one-line justification.
- A vignette: a thing that happened, a code snippet, a scenario, an analogy.
- A half-thought: "something about how X feels like Y, work this out later."
- A quote, a piece of dialogue, an overheard line.
- A list of related observations that hang together by feel.
- A complaint, a confession, a punchline.
- A **leading word**: a compact metaphor or coinage the whole piece can hang on (one term that names the idea, the way _tracer bullets_ or _fog of war_ names a whole pattern).

Of these, the leading word is the most valuable fragment to land. It is load-bearing. Name the right one in explore and it shapes the structure, the transitions, and the title later, paying dividends through the entire exploit phase. When the conversation circles a recurring idea, push to coin a word for it.

The novelist's diary is the model. Years of unstructured noticings later get mined for raw material. Fragments are noticings.

## File format

```markdown
# Working title

A first fragment lives here.

It can be multiple paragraphs. It can include lists, code or quotes, in whatever shape the fragment naturally takes.

---

A second fragment.

---

> A quoted line that the user wants to keep around.

A reaction to it.

---

- A cluster of related observations
- That hang together by feel
- And want to be near each other
```

Fragments are separated by a horizontal rule (`\n---\n`). No headings inside the body. No tags. No order beyond the order they were added.

## Writing rhythm

Append silently, without asking permission for each fragment. Mention what you added in passing ("adding that") and keep the conversation moving.

Re-read the file before every write. The user may have edited, reordered, or deleted fragments between turns, so preserve their changes. Only append, unless the user asks you to edit a specific fragment in place.

The user can say "cut the last one", "rewrite that one sharper", "merge those two" at any time. Treat those as first-class instructions.

</supporting-info>
