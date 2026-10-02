---
name: hunk-notes
description: "Hunk notes: publish review findings as notes in a live Hunk diff session, and address the comments the user leaves there. Use when receiving-code-review or pr-review reaches its Hunk step, or when the user asks to address, read or go through their Hunk comments."
---

Hunk is the terminal diff viewer the user reviews in. The `hunk-review` skill is its command reference. This skill holds the workflow around it. Three facts shape every step:

- **Paths are repo-root relative.** In a monorepo that differs from the cwd, so it is `super_api/website/lib/foo.ex`, never `website/lib/foo.ex`. `hunk session review <id> --json` lists each path exactly as Hunk takes it.
- **A note sits only on a line inside a diff hunk.** A file outside the diff, or a line outside every hunk, has no place in Hunk.
- **Notes keep their line numbers across reloads.** After an edit, a note can sit beside different code. Match a note to its code by content, reading around its line.

## Find the session

Run `~/.agents/skills/hunk-notes/scripts/hunk_session.sh <fixed-point>` from the repo, outside the sandbox. Inside it the Hunk daemon is unreachable, so the script sees no session and opens a duplicate. The script points the session at the working tree diffed against the fixed point's merge-base, in watch mode, so fixes show up as they land. Handle the exit code:

- **0**: the last line is `HUNK_SESSION: <id>`. Pass that id to every later command.
- **5**: several sessions are open on the repo. Ask the user which one, then run `hunk session reload <id> -- diff <merge-base> --watch` yourself.
- **6**: no session is open and you are outside herdr. Give the user the command after `HUNK_OPEN_MANUALLY:`, wait for them to say it is open, then run the script again.
- **anything else**: say in one line that Hunk failed, with the error. The chat report carries the findings alone.

## Publish notes

Each finding arrives from the caller with a file, a line, a summary and a rationale.

1. **Anchor every note.** Open the file in the working tree and confirm the line holds the code the finding is about. Then confirm the line falls inside a hunk listed by `hunk session review <id> --json`. A finding that fails either check stays in the chat report, marked "not in Hunk".
2. **Send one batch** to `hunk session comment apply <id> --stdin --json`, each item `{"filePath", "newLine", "summary", "rationale", "author": "claude"}`. Hunk rejects the whole batch when one item fails, and the error names that item. Fix or drop it, then resend.
3. **Keep the note ids** from the response beside each finding. A later reply goes to `hunk session comment add <id> --reply-to <note-id> --summary "<text>"`.

Completion criterion: every finding is either a note in Hunk or a line in the chat report marked "not in Hunk".

## Address the user's comments

The user's comments live only in the open Hunk window. Closing it discards them.

1. **Find the session** with `hunk session list --json`, matching `repoRoot` to `git rev-parse --show-toplevel`. Leave its diff as it is. Ask when several match. When none is open, tell the user the comments closed with the window.
2. **Read every thread** with `hunk session comment list <id> --type all --json`. The user's notes carry `"source": "user"`. A note with a `parentId` is a reply, so read its parent to see what it answers. A user reply under one of your verdicts overrules it or questions it.
3. **Weigh each comment** with the `receiving-code-review` skill. A comment can be a request, a claim or a question.
4. **Act, and reply as you go.** Reply on each thread as its outcome lands: `Fixed: <what changed>`, `Dismissed: <reason>`, an answer, or a question back. Commit only when the user asks. When the notes are a `pr-review` of someone else's PR, the comments revise the paste-ready list rather than the code. Drop, reword or add entries, then hand back the final list.

Completion criterion: every user note has your reply beneath it. Then report in chat how many comments ended in each outcome, and what is waiting on the user.
