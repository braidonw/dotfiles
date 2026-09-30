# Writing Agent Briefs

An agent brief is a structured comment posted on a tracker issue when it moves to `ready-for-agent`. It is the authoritative specification that an AFK agent will work from. The original body and discussion are context. The agent brief is the contract.

A **human brief** is the same comment for `ready-for-human`, headed `## Human Brief` instead of `## Agent Brief`, with one extra line under the summary: `**Why not delegated:**` naming the judgement call, external access, design decision or manual testing that needs a person. Everything below applies to both.

## Principles

### Durability over precision

The issue may sit in `ready-for-agent` for days or weeks. The codebase will change in the meantime. Write the brief so it stays useful even as files are renamed, moved, or refactored.

- **Do** describe interfaces, types, and behavioral contracts
- **Do** name specific types, function signatures, or config shapes that the agent should look for or modify
- **Don't** reference file paths, because they go stale
- **Don't** reference line numbers
- **Don't** assume the current implementation structure will remain the same

### Behavioral, not procedural

Describe **what** the system should do, not **how** to implement it. The agent will explore the codebase fresh and make its own implementation decisions.

- **Good:** "`Employees.list_active/1` should accept an `:employer_id` option"
- **Bad:** "Open lib/super_api/employees.ex and add a clause on line 42"
- **Good:** "An employer with a lapsed stapling authority should see a partner-actionable issue"
- **Bad:** "Add a case clause in the worker's perform function"

### Complete acceptance criteria

The agent needs to know when it's done. Every agent brief must have concrete, testable acceptance criteria. Each criterion should be independently verifiable.

- **Good:** "Calling the context with an ABN that is not active returns `{:error, :abn_inactive}`"
- **Bad:** "ABN handling should work correctly"

### Explicit scope boundaries

State what is out of scope. This prevents the agent from gold-plating or making assumptions about adjacent features.

## Template

```markdown
## Agent Brief

**Category:** bug / enhancement
**Summary:** one-line description of what needs to happen

**Current behavior:**
Describe what happens now. For bugs, this is the broken behavior. For enhancements, this is the status quo the feature builds on.

**Desired behavior:**
Describe what should happen after the agent's work is complete. Be specific about edge cases and error conditions.

**Key interfaces:**
- `TypeName`: what needs to change and why
- `function_name/1` return shape: what it currently returns vs what it should return
- Config shape: any new configuration options needed

**Acceptance criteria:**
- [ ] Specific, testable criterion 1
- [ ] Specific, testable criterion 2
- [ ] Specific, testable criterion 3

**Out of scope:**
- Thing that should NOT be changed or addressed in this issue
- Adjacent feature that might seem related but is separate
```

## Examples

### Good agent brief (bug)

```markdown
## Agent Brief

**Category:** bug
**Summary:** Fund name truncation cuts mid-word in the fund selection list

**Current behavior:**
When a fund's display name exceeds 60 characters, it is cut at exactly 60 characters regardless of word boundaries. Names end mid-word (e.g. "Australian Retirement Trust Super Savings Accumulation Acc").

**Desired behavior:**
Truncation breaks at the last word boundary before 60 characters and appends "..." to show the name was shortened.

**Key interfaces:**
- The fund display name the selection page renders. No schema change is needed, but the code that shortens it must respect word boundaries.

**Acceptance criteria:**
- [ ] Names of 60 characters or fewer are unchanged
- [ ] Longer names are cut at the last word boundary before 60 characters
- [ ] Truncated names end with "..."
- [ ] The total length including "..." does not exceed 60 characters

**Out of scope:**
- Changing the 60 character limit itself
- Wrapping names across two lines
```

### Good agent brief (enhancement)

```markdown
## Agent Brief

**Category:** enhancement
**Summary:** Let partners filter the employer list by onboarding status

**Current behavior:**
The partner portal lists every employer for the partner, newest first. A partner looking for employers stuck mid-onboarding has to page through the whole list.

**Desired behavior:**
The employer list accepts an onboarding status filter. With no filter, the list is unchanged. With a filter, only employers whose latest onboarding session is in that status appear, still newest first.

**Key interfaces:**
- The context function that lists a partner's employers gains a status option, rather than a sibling function
- The filter values are the existing onboarding session statuses. No new status is introduced.

**Acceptance criteria:**
- [ ] With no filter, the list matches today's output
- [ ] With a status filter, only employers whose latest session has that status are returned
- [ ] An unknown status value is rejected, not silently ignored
- [ ] An integration test covers the filtered and unfiltered cases through the context

**Out of scope:**
- Filtering by any field other than onboarding status
- Saving a partner's filter choice between visits
```

### Bad agent brief

```markdown
## Agent Brief

**Summary:** Fix the triage bug

**What to do:**
The triage thing is broken. Look at the main file and fix it. The function around line 150 has the issue.

**Files to change:**
- lib/super_api/triage.ex (line 150)
- lib/super_api/types.ex (line 42)
```

This is bad because:
- No category
- Vague description ("the triage thing is broken")
- References file paths and line numbers that will go stale
- No acceptance criteria
- No scope boundaries
- No description of current vs desired behavior
