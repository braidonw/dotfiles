---
name: tiger-style
description: Apply the Tiger Style for Elixir philosophy (safety, then performance, then developer experience) as a design and review lens. Use when reviewing a design or architecture, assessing whether a system will hold up under load or failure ("will this fall over?", "what happens when X dies?", "is this resilient?"), designing a new process tree / worker / pipeline / integration, or whenever the user mentions Tiger Style. Complements code-style review skills (elixir-review) - this one judges systemic properties (bounded resources, failure domains, back-pressure, state ownership), not line-level idiom.
---

# Tiger Style review lens

Read `TIGER_STYLE_ELIXIR.md` in this skill's directory - it is the full philosophy and the authority for this review. Apply it with the priority order it mandates: **safety first, then performance, then developer experience**. A safety finding always outranks a performance one, which outranks an ergonomic one.

## How to run the review

Work through the design or code asking the document's core questions, in this order:

1. **Error partitioning.** Is every failure either handled (a designed `case` clause for an expected domain error) or fatal (a crash for an impossible state)? Hunt for the forbidden third category: log-and-continue, defaulted lookups, rescued own-logic, `{:error, _}` arms that swallow.
2. **Bounds.** For every process, queue, buffer, retry loop, and external input: what can grow, and what stops it? No answer = finding. Check timeouts are explicit and chosen on user-facing paths, producers can't outrun consumers, retries have ceilings, inputs have size limits, atoms are never minted from external data.
3. **Failure domains.** Does the supervision tree group things that should die together and isolate things that must survive each other? Is every process's state rebuildable on restart, with durable facts living outside the process? Would a crash here corrupt or merely restart?
4. **Performance shape.** Napkin math before verdicts. Count round trips (N+1s, insert vs insert_all), look for missing batching, buffering where back-pressure belongs, GenServers serializing work that needs no serialization, large-term copying on hot paths.
5. **State ownership.** One authoritative home per fact; flag mirrored assigns, shadow columns, caches with no rebuild story.

## Output

Report findings ordered by the priority ladder (safety > performance > DX), each one citing the specific Tiger Style principle it violates, the concrete failure it enables (what breaks, under what load or fault), and the bounded/handled/owned alternative. Don't restate line-level style issues covered by other review skills unless they are also safety findings.
