---
name: receiving-code-review
description: "Weigh review findings before acting on them. Use whenever review feedback arrives: a review agent's report, a code-review, plan-review or Codex pass, or a teammate's PR comments."
---

Review feedback is a claim about the code, not an instruction. Verify it, then act on what holds. Technical correctness outranks agreement.

## Steps

1. **Read all of it** before acting on any of it. Items are often related.
2. **Clarify first.** If any item is unclear, ask about it before implementing anything, including the items you do understand. Partial understanding produces the wrong fix. Say which items are clear and which need clarifying.
3. **Verify each finding against the code.** Open the cited line and read enough around it to judge. For each one, ask:
   - Is it correct for this codebase and its documented conventions?
   - Would the fix break existing behaviour?
   - Is there a reason the current code is the way it is? Check `git log` on the lines.
   - Did the reviewer have the full context?
4. **Run the YAGNI check.** When a finding asks to "implement it properly", grep for real usage first. If nothing calls it, the right fix is deleting it, not completing it.
5. **Give each finding a disposition:**
   - **Fix**: correct and worth doing.
   - **Dismiss**: wrong, already handled, or contrary to a documented convention. Give a one-line technical reason.
   - **Ask the user**: it contradicts a decision the user already made, or it is an architecture or product call. Stop and raise it rather than applying it.
   - **Can't verify**: say what would verify it (a run, prod data, access) and ask whether to proceed.
6. **Fix in order.** Blocking issues (breakage, security) first, then simple fixes, then complex ones. Verify each fix before starting the next.
7. **Report** what was fixed, what was dismissed with its reason, and what is waiting on the user.

## Tone

Skip performative agreement and thanks. State the fix, or show it in the code. When you pushed back and turn out to be wrong, say what you checked and what you found, then fix it. No apology and no defence of the earlier position.

Reviewers are wrong in predictable ways. They flag a deliberate let-it-crash bang call as unhandled, ask for defensive branches the codebase avoids on purpose, or propose an abstraction for one caller. Those are dismissals, not findings.
