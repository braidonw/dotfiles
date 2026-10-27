# Comment style

How the user writes a review comment. Step 5 drafts every comment against this file, because the comments are posted under the user's name.

## Rules

- **One sentence, usually a question.** Half the user's comments are under 100 characters and two thirds are questions. A question lets the author answer "deliberate" in one word, where a paragraph reads as a verdict they have to argue with.
- **Name the existing thing.** "Don't we already have `Billing.without_voided/1`?" The author can open the identifier, so six words do the work of sixty. This is also how Step 5's "follows an existing pattern" gets said.
- **Statement for a settled rule, question for intent.** "This should be a radio group, not buttons." is a rule the codebase already has, so it is said flat. "Is dropping the index correct?" is checking intent, so it is a question. Softeners ("I think", "right?", "no?") go on the questions, and the rules stay bare.
- **Attach the fix in the same sentence with "i.e." or "e.g."** "can this be a named var? e.g. `@retry_window_ms 30_000`". The alternative rides on the question instead of needing a second paragraph. Two or three alternatives go as a short list with one marked "(preferred)".
- **State the cost only when the question does not already carry it.** "is this used?" needs no cost. "This drops the error, so a failed charge looks like a success." does.
- **De-escalate in the user's own words.** "Ok if intentional, but just checking", "Not a huge deal", "can fix later, maybe leave a note", "not a blocker for this PR", and `nit:` for an optional item or a real issue that can wait for a follow-up. Those phrases are voice and stay in. The chat list carries the severity and the body carries the finding, so words like critical, major or minor stay out of the body.
- **Back-reference instead of repeating.** "Per above", "Same as below", "See earlier comment on the preload". Once said, said.
- **"we" for the codebase, "you" for this diff.** "Can we just use `Billing.update/2` here?" is the team's code. "You've already preloaded this above" is what the author did. "I'd rather" and "I would much rather" carry a firm preference without an order.

A GitHub `suggestion` block is for a one-line concrete fix, such as a changed attribute or a renamed route. A longer alternative goes in a fenced code block after a one-line lead-in.

## When longer is warranted

A longer comment is for a mechanism the author cannot see from the line: a state stuck between two transactions, a lock that conflicts with another, a socket half-mutated before a save fails, rows a cursor silently skips. It is also for architecture pushback where the reason has to travel with it, such as a module boundary and why it exists. It runs three to six sentences. State what happens, numbered when it takes more than two steps, then the fix. Open with "hmm," when the diagnosis itself is uncertain, and close with a one-line invitation to correct it.

## Review body

The review body holds the approach-level concern, in two to four sentences. "What are we trying to do here?", a naming scheme that will cause confusion later, or a simpler shape for the whole change. Approach concerns tied to one line can sit inline instead. The approval or changes-requested state, and any one-line approval, are the user's to write at `:submit`.

## Punctuation and spelling

The writing rules in CLAUDE.md apply to every comment. A full stop goes where a dash or a clause-joining colon would, and spelling is correct. The user's past comments carry casual dashes and typos. Those are habits, not voice.

## Before and after

Agent draft: "The function `format_due_date/1` is defined in `Billing.Invoices` but I could not find any call sites across the codebase. Consider removing it to reduce dead code and maintenance burden."

User voice: "is this used?"

Agent draft: "This introduces a hand-rolled set of table styles in `UserCard`. The design system already provides a description list primitive that covers this layout and keeps styling consistent across pages. Recommend replacing the custom markup with that primitive."

User voice: "Can we use the standard description list component for this one?"

Agent draft: "On this line the result of `Billing.record_payment/2` is discarded. If the insert fails, the failure is swallowed and the caller continues as though the payment was recorded, which could leave the account inconsistent. Consider matching on `:ok` so that a failure raises."

User voice: "Should this match the :ok? A failed payment record should crash, not carry on."

Agent draft: "The anchor sets `target=\"_blank\"` without `rel=\"noreferrer\"`. This is a minor privacy concern because the opened page can read `window.opener`. It is not critical for this PR but should be addressed before release."

User voice: "nit: needs `rel=\"noreferrer\"` with the target. Can fix later."

Agent draft: "The `complete_subscription/1` function applies a changeset to the subscription struct held in socket assigns and then calls `Repo.update!/1`. Because the struct was loaded at mount time, a concurrent completion from the background worker will already have written a newer state to the database, and this update will overwrite those fields with stale values. I recommend wrapping the operation in a transaction that re-fetches the row with a lock before applying the change."

User voice: "This updates the copy of the subscription in assigns, so if the worker completed it first we overwrite those fields with stale ones. Can the lock, re-read and update sit inside one transaction in `Billing`?"

Agent draft (a mechanism, so the length is earned): "The export paginates on `updated_at` using a strictly-greater-than comparison against the cursor. When two or more rows share the same `updated_at` value and the page boundary falls between them, the rows after the boundary are never returned by any page, which results in silent data loss in the export. I recommend adding a secondary sort key and using a tuple comparison."

User voice: "hmm, I think this skips rows. The cursor is `updated_at` and the query is `>`, so two rows saved in the same second with the page boundary between them only export the first one. Either page on `(updated_at, id)` with a tuple compare, or page on id alone. Might be misreading this one."

## Completion criterion

Every comment in the Step 5 list is one or two sentences unless it names a mechanism or carries an architecture reason, names the existing identifier where one exists, is a question or an unhedged statement of a settled rule, and passes the CLAUDE.md punctuation rules.
