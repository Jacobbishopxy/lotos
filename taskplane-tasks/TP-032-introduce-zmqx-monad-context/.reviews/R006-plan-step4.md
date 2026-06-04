## Plan Review: Step 4: Testing & Verification

### Verdict: REVISE

### Summary
The plan covers the baseline library build, frame-order regression tests, and compiling the full workspace with tests enabled. However, it does not include execution of the known explicit-context EventLoop/logging regression that blocked Step 3 in R004, so the verification step could pass while missing the context-lifetime behavior this task is meant to prove.

### Issues Found
1. **[Severity: important]** — The verification commands omit `cabal test lotos:test:test-zmq-worker-log-transport`, the existing regression that exposed the Step 3 global-context/EventLoop bug. The current planned build plus worker/client frame tests would not fail if worker log transport regressed again. Add this targeted test to Step 4 evidence; `test-zmq-log-ingest` is also a useful companion if you want coverage of both log service sides.

### Missing Items
- Targeted runtime coverage for the app-owned ZMQ context in the worker log transport/EventLoop path, not just frame serialization and test compilation.

### Suggestions
- If time permits, also include the TaskSchedule executable build evidence from R005 (`ts-server`, `ts-worker`, `ts-client`) in STATUS.md as compatibility-surface evidence, but this is secondary to the missing log transport regression test.
