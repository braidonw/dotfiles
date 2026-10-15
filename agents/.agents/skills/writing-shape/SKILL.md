---
name: writing-shape
description: "Shape a pile of raw writing material into an article, block by block, arguing each format choice. Use when the user has fragments or notes and wants to argue the article's structure and format into shape."
argument-hint: "Pile: a slug, file path or Google Doc URL"
---

<what-to-do>

The user has passed (or will pass) a pile of raw material. It can be anything from a tidy list of fragments to a wall of unstructured prose to a transcript. The format does not matter. Read the pile and resolve where the article lives, both per `~/.agents/writing/STORAGE.md`.

Then run a shaping session that produces a separate article. This is **exploit**. The exploring is done and the pile is fixed. Commit to a structure and mine the pile to fill it.

</what-to-do>

<supporting-info>

## The loop

1. **Read the pile.** Read the input in full before anything else. Form a sense of what's in it.
2. **Establish the prerequisites.** Read `~/.agents/writing/GROUNDING.md` first. Settle with the user the prerequisites, the concepts the reader knows walking in.
3. **Draft 2 to 3 candidate openings.** Each opening should imply a different thesis or angle for the article. Show all of them. Force the user to pick or compose a hybrid. The chosen opening defines what the rest of the article must do.
4. **Grow block by block.** After the opening lands, ask "given this opening, what does the reader need to hear next?" Pull material from the pile to answer. The next block may only lean on grounded concepts, and grounds new ones as it lands. Argue about the form the next block takes. It could be a paragraph, a list, a table, a callout, a quote or a code block. Each format choice should be deliberate and defensible.
5. **Append to the article as you go.** Write each agreed block immediately so the user can see the article taking shape.
6. **Loop steps 4 and 5 until the article is done.** The user decides when it's done.

## Conversational feel

This is the `writing-fragments` interview, inverted. There the question was "what are you actually noticing?" Here it's "what is this article actually arguing, and in what order does the reader need to hear it?" Push back. Refuse to let weak transitions slide. If a paragraph doesn't earn its place, cut it.

Moves to keep using:

- "What does this paragraph do for the reader that the previous one didn't?"
- "If I cut this, what breaks?"
- "Is this prose, or should it be a list? Why prose?"
- "This sentence is doing two jobs. Split it or pick one."
- "The opening promised X. We've drifted to Y. Either re-thread it or change the opening."

## Pulling from the pile

Treat the raw material as a quarry, not a script. Pull a fragment, rework it to fit the surrounding paragraph, and place it. A fragment may be split across multiple paragraphs, merged with another, or paraphrased. The pile's job is to be mined. The article's job is to read as one voice.

If the pile lacks something the article needs, name the gap explicitly, for example "We need an example here and the pile doesn't have one. Give me one now or we cut this section."

## Format arguments to actually have

When choosing how to render a block, weigh these tradeoffs out loud with the user:

- **Prose vs. list.** Prose carries argument. Lists carry parallel items. If items aren't truly parallel, prose is better. If they are, a list is faster to scan.
- **Inline vs. callout.** Tips, warnings, and asides go in callouts (`> [!TIP]`, `> [!NOTE]`), but only if they'd genuinely derail the main argument inline. Otherwise leave them inline.
- **Table vs. repeated structure.** If the same shape repeats 3+ times with the same fields, use a table. Otherwise use prose with bold leads.
- **Quote vs. paraphrase.** Quote when the original wording is the point. Paraphrase when only the idea matters.
- **Code block vs. inline code.** Use a block for multi-line, runnable or illustrative code. Use inline code for a single token or identifier.

## Writing rhythm

Re-read the article before every write, because the user may have edited it between turns. Preserve the user's edits. If the user wants a block rewritten, edit that block in place and leave the rest alone.

## Out of scope

- Mining for new fragments that aren't in the pile (handle gaps as in [Pulling from the pile](#pulling-from-the-pile)).
- Editing the raw material.
- Publishing, formatting for a specific platform, or adding frontmatter the user didn't ask for.

</supporting-info>
