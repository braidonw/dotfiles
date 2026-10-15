# Storage

Shared by `writing-fragments`, `writing-shape` and `writing-beats`. A **piece** is one article in progress, named by a short kebab-case **slug**. If the user gives no slug, derive one from the topic or working title and say which you picked. Resolve the location once and reuse it for the rest of the session.

## Local default

Each piece lives in its own folder:

- `~/Documents/writing/<slug>/fragments.md`: the pile `writing-fragments` builds.
- `~/Documents/writing/<slug>/article.md`: the article `writing-shape` or `writing-beats` writes.

An output path or doc the user names overrides the default.

## Google Docs

Before creating an output file, check whether a Google Docs connector is available (tools that create, read and update Google Docs). If it is, and the user has not already named a location, ask once whether to save locally or in a Google Doc. If it is not, save locally without asking.

For a Google Doc:

- Load the Google Workspace skill, if the harness has one, before the first write.
- Title the doc `<slug> fragments` or `<slug> article`, and give the user its link.
- Append new material at the end of the body. Edit a targeted block in place when the user asks for a rewrite, cut or merge.
- Appended text arrives as plain text. Apply headings, lists and tables with formatting requests rather than markdown syntax. Fragment separators stay as a plain `---` line.

## Reading the pile

`writing-shape` and `writing-beats` take the pile in any of three forms:

- A slug: read `~/Documents/writing/<slug>/fragments.md`.
- A file path: read it as given.
- A Google Doc URL: read it through the connector. Take the slug from the doc title minus its ` fragments` suffix, or derive one if the title has no such suffix.

The pile is read-only to both skills.
