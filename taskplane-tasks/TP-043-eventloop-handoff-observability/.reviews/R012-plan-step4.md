## Plan Review: Step 4: Testing & Verification

### Verdict: REVISE

### Summary
The plan covers the core worker/broker frame and build gates, and it correctly carries the smoke requirement for public info/log stat changes. However, Step 3 added/relies on LogIngest stats-separation coverage, and the Step 4 plan only builds that suite rather than running it.

### Issues Found
1. **[Severity: important]** — Add a targeted run for `cabal test lotos:test:test-zmq-log-ingest` (or an equivalent targeted command) to exercise the “LogIngest stats remain distinct from no-drop handoff queue stats” regression. `cabal build all --enable-tests` only compiles that suite, so leaving it out would miss a stated Step 3 invariant if the test fails at runtime.

### Missing Items
- Targeted execution of the LogIngest regression suite that covers rejected/drop accounting staying distinct from no-drop handoff queue metrics.

### Suggestions
- Because `/info` now exposes `runtimeQueueStats`, treat the smoke checkbox as triggered and record single-/multi-worker smoke evidence in STATUS.md.
