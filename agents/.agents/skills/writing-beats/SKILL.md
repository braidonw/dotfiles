---
name: writing-beats
description: "Assemble a pile of raw writing material into an article as a journey of beats, choosing each next beat from a few options. Use when the user has fragments or notes and wants to pick the article's path from offered options."
argument-hint: "Pile: a slug, file path or Google Doc URL"
---

<what-to-do>

The user has passed (or will pass) a pile of raw material. Read the pile and resolve where the article lives, both per `~/.agents/writing/STORAGE.md`. This is **exploit**. The exploring is done and the pile is fixed. Commit to a path through it and mine the pile to fill each beat.

Then run a beat-by-beat journey, choose-your-own-adventure style:

1. **Establish the prerequisites.** Read `~/.agents/writing/GROUNDING.md` first. Before any beats, settle with the user the prerequisites, the concepts the audience knows walking in.
2. Write 2 to 3 candidate **starting beats**, drawn from the raw material. Each is a different entry point into the article. Each may only lean on grounded concepts. Note what new concepts each one grounds. Show the user the beats before writing to the article. The user picks one. Preview what beats that pick unlocks, as if the user is seeing a little way down the path.
3. Once the user picks a beat, write **only that beat** to the article. A beat may be one sentence or several paragraphs, whatever that beat naturally is. Stop there.
4. Re-read the article. Then offer 2 to 3 candidate **next beats**, each a different direction the journey could pivot to from where the article now stands. Each must be [reachable](#reachability). Note what each one grounds, so the user can see which paths it opens.
5. Repeat steps 3 and 4 until the article reaches a natural end. The user decides when it's there.

</what-to-do>

<supporting-info>

## Reachability

Reachability is what shapes the choose-your-own-adventure. A candidate beat is only reachable if everything it requires is already grounded. Picking a beat that grounds concept X unlocks every beat that was waiting on X.

## What is a beat

A beat is one move in the journey. It does one thing: sets a scene, lands a point, asks a question, drops an aside, twists the angle. Then it stops, leaving the reader at a place where the next beat can pivot.

A beat is sized by what it needs:

- A single sentence if that's all the move is ("And then nothing happened for three weeks.").
- A short paragraph if the move needs setup.
- Multiple paragraphs if the beat is a self-contained vignette, argument, or example.

If a "beat" needs five paragraphs and three subheadings, it's not a beat. It's two beats glued together. Split it.

## Pulling from the pile

Pull material from the raw pile to populate each beat. You can paraphrase, split, recombine, or quote. The pile is a quarry.

## Ending the journey

The article ends when the journey is complete, not when the pile is empty. Most piles will have leftover fragments that don't make it in. That is fine. It is the point of having more raw material than you need.

## Writing rhythm

- Re-read the article before every write. Preserve user edits absolutely.
- If the user edits a previous beat substantially, let it change what comes next.
- If the user says "rewrite that beat" or "go back and try a different beat 3", do it. Edit in place and leave the rest alone.

</supporting-info>
