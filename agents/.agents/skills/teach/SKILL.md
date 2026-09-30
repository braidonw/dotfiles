---
name: teach
description: Teach the user a new skill or concept in a guided learning workspace.
argument-hint: "What would you like to learn about?"
---

The user has asked you to teach them something. This is a stateful request. They intend to learn the topic over multiple sessions.

## Teaching workspace

Pick the workspace first:

1. If the user names a directory, use it.
2. Else if the current directory has a `MISSION.md`, use the current directory.
3. Else use `~/Developer/learning/<topic-slug>/`, creating it if it doesn't exist. List `~/Developer/learning/` first, and when an existing workspace already covers the topic, confirm with the user before starting a new one.

One topic per workspace. The state of the user's learning lives in these files:

- `MISSION.md`: the _reason_ the user is interested in the topic. Ground all teaching in it. Use the format in [MISSION-FORMAT.md](./MISSION-FORMAT.md).
- `GLOSSARY.md`: the canonical language for this topic. Use the format in [GLOSSARY-FORMAT.md](./GLOSSARY-FORMAT.md). This is a teaching glossary, separate from any code repo's `CONTEXT.md`.
- `RESOURCES.md`: the trusted sources that ground your teaching. Use the format in [RESOURCES-FORMAT.md](./RESOURCES-FORMAT.md).
- `./learning-records/*.md`: what the user has learned. Use the format in [LEARNING-RECORD-FORMAT.md](./LEARNING-RECORD-FORMAT.md).
- `./lessons/*.html`: the lessons. A **lesson** is a single, self-contained HTML file that teaches one tightly scoped thing tied to the mission. This is the primary unit of teaching.
- `./reference/*.html`: reference documents, the compressed learnings from the lessons. Cheat sheets, reference algorithms, syntax, glossaries. They should print well and be designed for quick reference.
- `./assets/*`: reusable **components** shared across lessons. See [Assets](#assets).
- `NOTES.md`: a scratchpad for the user's teaching preferences and your working notes.

## Philosophy

To learn at a deep level, the user needs three things:

- **Knowledge**, captured from high-quality, high-trust resources
- **Skills**, acquired through highly relevant interactive lessons devised by you, based on the knowledge
- **Wisdom**, which comes from interacting with other learners and practitioners

Until `RESOURCES.md` is well populated, focus on finding high-quality resources that will help the user acquire knowledge. Never trust your parametric knowledge. Search the web and prefer primary sources: official documentation, specifications, recognised experts, peer-reviewed work.

Some topics need more skills than knowledge. Theoretical physics is more knowledge-based. Yoga is more skills-based.

### Fluency vs storage strength

Separate two types of learning:

- **Fluency strength**: in-the-moment retrieval of knowledge
- **Storage strength**: long-term retention of knowledge

Fluency can give the user an illusory sense of mastery. Storage strength is the real goal. Design lessons that build long-term retention through desirable difficulty:

- Retrieval practice (recall from memory)
- Spacing (distributing practice over time)
- Interleaving (mixing different but related topics in practice, for skills practice only)

## Lessons

A lesson is the main thing you produce: the unit in which knowledge and skills reach the user. Each lesson is one HTML file saved to `./lessons/`, titled `0001-<dash-case-name>.html` with the number incrementing each time.

A lesson should be **beautiful**, with clean, readable typography and layout, since the user will return to it later to review. Think Tufte.

Keep the lesson short and completable quickly. Working memory is small, and the lesson must stay within it. Each lesson gives the user a single tangible win to build on. It ties directly to the mission and sits in the user's zone of proximal development.

When the lesson is written, open it for the user with `open <path>`.

Each lesson:

- links via HTML anchors to other lessons and reference documents, by relative path
- recommends one primary source to read or watch, the highest-quality, highest-trust resource you found on the topic
- reminds the user to ask you follow-up questions, since you are their teacher and can help with anything unclear

## Assets

Lessons are built from reusable **components** stored in `./assets/`: stylesheets, quiz widgets, simulators, diagram helpers, and anything else a second lesson could reuse.

Reuse is the default. Before authoring a lesson, read `./assets/` and build from the components already there. When a lesson needs something new and reusable, write it as a component in `./assets/` and link to it. Code a future lesson would need belongs in a component, not inline.

A shared stylesheet is the first component every workspace earns. Every lesson links it, so the lessons look like one consistent course rather than a pile of one-offs. As the workspace grows, so does the component library.

## The mission

Every lesson ties into the mission, the reason the user wants to learn the topic.

If the user is unclear about the mission, or `MISSION.md` is not populated, your first job is to question the user on why they want to learn this.

Without the mission, knowledge acquisition is not grounded in real-world goals. Lessons feel too abstract, and you have no way of judging what the user should do next.

Missions change as the user develops more skills and knowledge. When that happens, confirm with the user, update `MISSION.md`, and add a learning record to capture the change.

## Zone of proximal development

In each lesson the user should feel challenged just enough.

The user may name exactly what they want to learn. If they don't, find their zone of proximal development:

- Read their learning records
- Work out the right thing to teach next from their mission
- Teach the most relevant thing that fits in that zone

## Knowledge

Design each lesson around a skill the user is going to learn. Include only the knowledge that skill requires. Teach the knowledge first, then have the user practise the skill through an interactive feedback loop.

Gather knowledge from trusted resources first, and track them in `RESOURCES.md`. Litter lessons with citations: links to external resources backing each claim. Citations make the lesson trustworthy.

For acquiring knowledge, difficulty is the enemy. It eats the working memory the user needs for understanding.

## Skills

Knowledge is about acquisition. Skills are about durability and flexibility. Make the knowledge stick.

For skill acquisition, difficulty is the tool. Effortful retrieval builds storage strength. Teach skills through interactive lessons:

- Interactive lessons, using quizzes and light in-browser tasks
- Lessons that guide the user through a list of real-world steps (for instance, yoga poses)

Each is built on a **feedback loop** in which the user receives feedback on their performance. Make the loop as tight as possible, with feedback immediately and ideally automatically.

For quizzes, make every answer option exactly the same number of words (and characters, if possible). Formatting must give no clue to the answer.

## Acquiring wisdom

Wisdom comes from real-world interaction, testing skills outside the learning environment.

When the user asks a question that appears to require wisdom, attempt an answer, then delegate to a **community**.

A community is a place, online or offline, where the user can test their skills in the real world. A forum, a subreddit, a real-world class (budget permitting), or a local interest group.

Find high-reputation communities the user can join. If the user says they don't want to join a community, respect it and record the preference in `RESOURCES.md`.

## Reference documents

While creating lessons, also create reference documents. Lessons link to them. They track raw units of knowledge used across lessons.

Lessons are rarely revisited. Reference documents are revisited often. They are the compressed essence of the lessons, in a format designed for quick reference.

Topics that lend themselves to reference:

- Syntax and code snippets for programming
- Algorithms and flowcharts for processes
- Poses and sequences for yoga
- Exercises and routines for fitness
- Glossaries for any topic with its own nomenclature

## `NOTES.md`

The user will sometimes state how they want to be taught, or things you should keep in mind. Record those preferences here and refer back to them when designing lessons.
