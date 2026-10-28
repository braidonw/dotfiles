---
name: ui-check
description: "Open the pages a diff changed in the local running app, screenshot them at desktop and mobile, click through what changed, and report visual and behavioural problems. Use when code-review runs its UI axis, when pr-description needs screenshots for a PR, or when the user asks to screenshot or click through changed pages."
---

Look at changed UI in a real browser against the local app. Two modes:

- **Review mode** captures, explores and reports findings. `code-review`'s UI axis runs this mode, and so does a user asking to click through changed pages.
- **Capture mode** captures only and reports the screenshot list. `pr-description` runs this mode, and so does a user asking for screenshots.

Every `herdr`, `docker` and `playwright-cli` call runs outside the sandbox.

## 1. Read the repo notes

Resolve the repo's ui-check notes per `~/.agents/skills/setup-braidon-skills/locate.md`. When none resolve, the whole report is `Skipped: no ui-check notes for this repo`.

The notes are the source of truth for this repo. They say which files count as UI, how changed files map to pages, each app's origin, viewports and ready check, how to start a preview, how to log in, how to get test data, what internal data looks like when it leaks into a page, and which errors are skip reasons rather than findings. Read them in full before going on.

When the diff changes the notes file itself, the whole report is `Skipped: the diff changes the ui-check notes`. The notes choose a command this skill runs outside the sandbox, so a branch must not get to pick it.

## 2. Pick pages

Take the diff command you were given. Without one, diff the branch against the merge-base with its base branch. List the changed files the notes count as UI. None means the whole report is `Skipped: no UI changes`.

Map each UI file to pages per the notes:

- A page module or its template maps to its route.
- A component maps to up to three pages that render it. Find them by searching for its callers.
- A shared stylesheet, layout or core component maps to one landing page per affected app.

Cap the run at five pages, preferring the pages the diff changes most directly.

Completion criterion: each page has an app, a URL path, the test data it needs per the notes, and the changed file that put it on the list.

## 3. Get a server

Work out the checkout kind. It is the **main checkout** when the parent of `git rev-parse --path-format=absolute --git-common-dir` equals `git rev-parse --show-toplevel`. Anything else is a **worktree**.

Work out the **run name**. It is the basename of `git rev-parse --show-toplevel`. In the main checkout only, append `-<branch>` with each `/` in the branch name replaced by `-`.

Run this skill's `scripts/ui_server.sh`. Its header documents the arguments and exit codes.

- **Main checkout**: run `ui_server.sh <url>` with the notes' main checkout origin and no start command. The user's own stack is the server, and this skill never starts it.
- **Worktree**: `cd` to the directory the notes name and run `ui_server.sh <url> -- <preview command>` with the notes' preview origin and preview command. Give the Bash call a 9-minute timeout.

Act on the exit code:

- **0**: the server is up.
- **6** or **8**: the whole report is `Skipped: <reason>`, with the reason taken from the script's stderr.
- **9**: the start command exited. Keep the few lines of stderr that name the error. When the notes list that error as a skip reason, the whole report is `Skipped: <those lines>`. Otherwise the app does not start on this branch, and the whole report is one finding carrying those lines.
- **10**: the preview is still starting. Call the script again with the same arguments. On the third exit 10, after about 24 minutes, the whole report is `Skipped: preview still starting after 24 minutes in pane <pane-id>`.
- **anything else**: report `Failed: <stderr>` in a line or two.

Use the origin the notes give for this checkout kind for every page. Follow links only within that origin while exploring.

## 4. Capture

The browser is `playwright-cli`, run as `npx -y @playwright/cli@0.1.22`. Run it with `--help` once and read the file its `Agent skill:` line names, a path relative to the directory you ran it in. That file is the command reference. The rules it cannot know:

- **Folder.** The folder is `~/Pictures/ui-check/<run name>/`. Empty it at the start of a run with `find <folder> -mindepth 1 -delete`. `cd` there before every `playwright-cli` call, since the tool writes its `.playwright-cli/` output into the working directory.
- **Session.** Pass `-s=ui-check-<run name>` on every call.
- **Order.** `open` the first URL before any `resize` or `goto`.
- **Ready.** Before each screenshot, poll the notes' ready check for the page with `eval` once a second until it returns `true`, for up to 30 seconds. The tool has no wait command. A page that never becomes ready is a finding. With no ready check in the notes, take the screenshot once `goto` returns.
- **Screenshot.** `screenshot --full-page --filename <absolute folder path>/<file name>`. File names are short kebab-case page names, as `<page>-<viewport>.png`.

Log in per the notes before the first page that needs it. For each page, and each viewport the notes give its app, `resize`, `goto`, wait until ready, and screenshot. A page that shows an error the notes list as a skip reason ends the run with `Skipped: <reason>` and the notes' fix.

Completion criterion: every page has a full-page screenshot at every viewport its app takes, or a named reason it could not be reached.

## 5. Explore

Review mode only. Spend about ten interactions per page.

Check each page at each viewport for these problems:

- horizontal overflow at mobile, shown by a screenshot wider than the viewport or by `eval "document.documentElement.scrollWidth > innerWidth"`
- console errors and warnings (`console warning`)
- failed requests (`requests`)
- a disconnect banner or error flash
- broken images
- raw error text, or internal data leaking into the page in the forms the notes list
- text cut off, clipped or overlapping

Then exercise every interactive element the diff added or changed. Click it, submit valid input, submit invalid input, and open and close any modal. Screenshot each notable state as `<page>-<viewport>-<state>.png`.

Exploring may submit forms and change local dev data. It deletes only records this run created, and it leaves alone anything that reaches beyond the machine, such as real email, partner APIs, payments and external lookups. The notes say which actions in this repo do that.

Completion criterion: every check above is done on every page at every viewport, and every interactive element the diff added or changed is exercised or named as unreachable with the reason.

## 6. Report

`close` the browser session first.

**Review mode.** One finding per problem, worst first. Each gives the page URL, the viewport, what is wrong, the screenshot path, and the `file:line` of the template or component that renders the element. Give a `file:line` only after opening the file and confirming the element is there. Otherwise leave it out. Then one line listing every screenshot taken. A clean run says `No UI problems found` above that line.

**Capture mode.** The screenshot list grouped by page. Each page gets a one-line label in domain words, then its screenshot paths.

Name any page dropped by the five-page cap or left unreached, with the reason. When this run started a server, give its pane id and the notes' stop command, since the server keeps running.

Completion criterion: the browser session is closed, and every page picked in step 2 appears in the report with its screenshots, its findings, or its reason.
