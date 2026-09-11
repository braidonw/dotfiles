# Testing

Focus on integration tests over plain unit tests unless there is some complex behaviour we want to ensure works as intended. Test through the public function of the context (not private helpers), use the real DB via the sandbox plus ExMachina factories, and mock only true external boundaries with Mox.

Tests are code too and are judged by their own bar: do they pin down behaviour, do they cover the cases that matter, and are they at the right level? A passing suite that tests nothing is worse than no suite. It gives false confidence and slows every future change. When writing or reviewing a code change, hold its tests to this bar alongside it.

## Table of contents

1. Coverage that matters (happy + error + edges)
2. Tests must actually test something
3. Integration over unit
4. Remove lower-level tests that duplicate integration coverage
5. Test hygiene

---

## 1. Coverage that matters: happy, error, and edges

Cover the behaviour, not just the lines. For each unit of behaviour:

- **The happy path.** The main success case is exercised end to end, asserting on the real outcome (the persisted record, the returned value, the side effect), not just that it didn't crash.
- **Every error branch the code deliberately handles.** Validation failures, `{:error, :not_found}`, unauthorised, a downstream `{:error, _}`, timeouts, conflicts. If the code has an error clause or a `{:cancel, _}`/`{:error, _}` branch, a test should drive it. Untested error branches are where bugs hide, because they're rarely hit in manual testing.
- **Representative edges and boundaries.** Empty collections, zero/negative/maximum values, duplicate or missing input, the boundary between two behaviours (e.g. a `tenure_years > 5` cutoff). One representative edge per branch is plenty; don't chase exhaustive combinatorics.

New logic, especially a new error branch, that ships with no test driving it is a gap. Name the specific missing case ("no test for the `{:error, :no_active_connection}` branch in `settle/4`"), not a vague "needs more tests".

## 2. Tests must actually test something

A test earns its place only if it would fail when the behaviour breaks. Watch for tests that pass no matter what:

- **Tautological / mock-only assertions.** The test stubs a function to return X, then asserts it returned X. That tests Mox, not your code. Assert on what the code under test did with the boundary's response.
- **Assert-nothing tests.** Calling the function and asserting `assert result` or `assert is_map(result)` or only that it didn't raise. These pass for almost any implementation. Assert on the actual values that matter.
- **Asserting the setup.** Checking that a factory inserted what you told it to, rather than checking what the code did.
- **Over-mocking the system under test.** Mocking so much that the test exercises the mocks rather than the real logic. Mock the boundaries (external HTTP, the ATO, Xero), run the real thing in between.
- **Snapshot/shape tests with no meaningful assertion.** Asserting a giant map equals itself with all fields, such that any intended change reads as "broken". Assert the few fields the behaviour actually controls.

The test of a test: "if I introduced a plausible bug in the code, would this fail?" If not, it's not pulling its weight.

## 3. Integration over unit

Prefer higher-level tests that exercise a real path (context function + DB + boundary) over isolated unit tests of internal helpers. Integration-style tests survive refactors because they assert on behaviour rather than structure, they catch wiring bugs that unit tests miss, and they match how the code is actually used.

- Test through the **public function of the context**, not its private helpers. A test reaching for a private function (or one made public only to test it) is a signal the coverage belongs at the context boundary instead.
- Reserve dedicated **unit tests for genuinely complex, self-contained logic** (a tricky calculation, a parser, a state machine) where pinning the behaviour in isolation is worth it. That's the exception, not the default.
- Use the real DB via the sandbox and ExMachina factories rather than mocking the repo; mock only the true external boundaries with Mox.

A pile of small unit tests on internal functions is usually one integration test through the context waiting to be written.

## 4. Remove lower-level tests that duplicate integration coverage

If an integration test already exercises a path end to end, a lower-level unit test asserting the same behaviour at a smaller scale is redundant coverage. It adds maintenance cost (two tests to update on every change) without catching anything the integration test wouldn't. Remove it.

Be specific about why it's a duplicate: name the integration test that already covers the behaviour, and confirm the unit test asserts nothing additional (no unique edge case, no error branch the integration test skips). If the unit test does cover an edge the integration test doesn't, it stays. The goal is removing genuine duplication, not thinning coverage. When in doubt, keep it and note the overlap rather than deleting blindly.

## 5. Test hygiene

Quick checks that keep the suite trustworthy and readable:

- **Descriptive names.** `test "returns {:error, :not_found} for an unknown id"` beats `test "fetch works"`. The name states the behaviour.
- **One behaviour per test** (mostly). A test asserting five unrelated things is hard to diagnose when it fails. Multiple assertions about one outcome are fine.
- **Deterministic.** No dependence on wall-clock time, `:rand`, or test ordering; no `Process.sleep` to paper over async timing (use the proper sync/await helpers). Flaky tests erode trust in the whole suite.
- **Factories over hand-built fixtures.** Use the ExMachina factory for the domain rather than assembling structs by hand in each test. (`SuperApi.Factory.random_abn/0` exists for valid ABNs.)
- **No logic in tests.** A test with its own `if`/`Enum.reduce` computing the expected value can share the bug it's meant to catch. Prefer literal expected values.
