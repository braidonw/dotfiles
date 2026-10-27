---
name: tuicr-notes
description: "tuicr notes: publish review findings as comments in a live tuicr review session, and address the comments the user leaves there. Use when receiving-code-review or pr-review reaches its tuicr step, or when the user asks to address, read or go through their tuicr comments."
---

tuicr is the terminal review tool the user reads diffs in. This skill holds the workflow around its `tuicr review` commands. Three facts shape every step:

- **Paths are repo-root relative.** In a monorepo that differs from the cwd, so it is `apps/web/lib/foo.ex`, never `web/lib/foo.ex`.
- **A comment renders only on a line inside the diff.** tuicr accepts a comment on any other line, exits 0, and never shows it.
- **Comments keep their line numbers across reloads.** After an edit, a comment can sit beside different code. Match a comment to its code by content, reading around its line.

## Find the session

Run the script from the repo, outside the sandbox. herdr and tuicr's session store live on the host, so inside the sandbox the script sees neither.

- `~/.agents/skills/tuicr-notes/scripts/tuicr_session.sh <fixed-point>` finds or opens a local session. It shows the working tree, untracked files included, diffed against the fixed point's merge-base. tuicr re-reads it every second, so fixes show up as they land.
- `~/.agents/skills/tuicr-notes/scripts/tuicr_session.sh --pr <number>` finds or opens the PR session. tuicr fetches the PR from GitHub first, so this can take up to a minute.

Handle the exit code:

- **0**: the last line is `TUICR_SESSION: <slug>`. Pass that slug as `--session`, and `--repo <repo-root>`, to every later `tuicr review` command.
- **5**: several local sessions are active on the repo. Ask the user which window to keep and to quit the others, then run the script again.
- **6**: no session is open and you are outside herdr. Give the user the command after `TUICR_OPEN_MANUALLY:`, wait for them to say it is open, then run the script again.
- **7**: the active local session shows a different diff, named after `TUICR_MISMATCH:`. Ask the user to quit that tuicr window, then run the script again. Leave its pane alone, because the window holds deletes it has not saved yet.
- **anything else**: say in one line that tuicr failed, with the error. The chat report carries the findings alone.

## Publish comments

Each finding arrives from the caller with a file, a line and the comment text.

1. **Check for earlier drafts** in a PR session. When `tuicr review comments` lists entries with `author == "claude"` and `lifecycle_state == "local_draft"`, ask the user whether to keep them and skip publishing, or to delete each with `tuicr review delete --session <slug> --comment-id <id>` and publish fresh.
2. **Anchor every comment.** Open the file in the working tree and confirm the line holds the code the finding is about. Then confirm the line falls inside the diff. For a local session that is a hunk of `git diff <merge-base>`, or any line of a file listed by `git ls-files --others --exclude-standard`. For a PR session it is a hunk of `gh pr diff <number>`. A finding that fails either check stays in the chat report, marked "not in tuicr".
3. **Add one comment per finding**, since `--input` takes a single object. Build the JSON with `jq` so quotes and apostrophes in the text survive the shell:
   ```bash
   jq -n --arg file '<path>' --argjson line <n> --rawfile content <text-file> '{file: $file, line: $line, side: "new", content: $content}' |
     tuicr review add --repo <repo-root> --session <slug> --username claude --input -
   ```
   Write each comment's text to a scratch file first, so nothing in it is parsed by the shell.
   A range takes `start_line` and `end_line` in place of `line`. A file-level comment drops `line`, and a review-level comment drops `file` too. Leave `--type` off, because a type puts a `[TYPE]` tag on the comment when it is submitted to GitHub.
4. **Keep the comment ids** from the responses beside each finding. Then read `tuicr review comments` once and confirm it holds every comment you added.

Completion criterion: every finding is either a comment in tuicr or a line in the chat report marked "not in tuicr".

## Post an outcome

Outcomes go into local sessions only. In a PR session `:submit` posts every local draft whatever its author, so an outcome there would reach the PR author. Report PR-session outcomes in chat.

tuicr has no reply threads. An outcome is a new `claude` comment on the same file and line: `Fixed: <what changed>`, `Dismissed: <reason>`, an answer, or a question back. Anchor the line again first. When it has left the diff, post a file-level comment that reads `Fixed (line <n>): <what changed>` instead.

## Address the user's comments

Comments stay in tuicr's store after its window closes.

1. **Find the session** with `tuicr review list --repo <repo-root>`, which lists the local sessions and the repo's PR sessions. Prefer the `active` one. Ask when several could hold the comments.
2. **Read every comment** with `tuicr review comments`. It returns a flat array, each entry with `id`, `author`, `path`, `start_line`, `end_line`, `lifecycle_state` and `content`. The user's comments are the ones with `author != "claude"`. In a PR session they also carry `lifecycle_state == "local_draft"`, since the rest are GitHub threads. A user comment on the same line as one of yours answers it, and may overrule or question it.
3. **Weigh each comment** with the `receiving-code-review` skill. A comment can be a request, a claim or a question.
4. **Act, and post outcomes as you go.** Commit only when the user asks. In a `pr-review` PR session the user's drafts are their own review comments and go out on `:submit`, so leave them alone. Change PR drafts only when the user asks in chat, rewording one by deleting it and adding the new text, then hand back the final chat list.

Completion criterion: every user comment in a local session has an outcome comment on its line. Then report in chat how many comments ended in each outcome, and what is waiting on the user.
