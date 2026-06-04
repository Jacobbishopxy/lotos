## Plan Review: Step 4: Testing & Verification

### Verdict: REVISE

### Summary
The plan covers the broad verification gates from the task prompt: scheduler tests, frame/liveness checks, full test-enabled build, and single/multi-worker smoke. However, it does not explicitly run the newly added broker reservation regression suite; `cabal build all --enable-tests` will compile that suite but will not execute its assertions.

### Issues Found
1. **[Severity: important]** — Add an explicit run for the new capacity-reservation regression suite, e.g. `cabal test lotos:test:test-zmq-capacity-reservations`. Step 3 added broker lifecycle/reconciliation assertions in `lotos/test/ZmqCapacityReservations.hs`, and the suite is registered in `lotos/lotos.cabal`; without running it, Step 4 can miss the core over-assignment/release regressions this TP is meant to prove.

### Missing Items
- Record the executed command list and pass/fail evidence in `STATUS.md`, including the dedicated reservation suite, TaskSchedule scheduler suite, frame/liveness/retry suites, full `cabal build all --enable-tests`, and smoke run artifact paths/results.

### Suggestions
- Make the targeted test list concrete in the plan, for example: `TaskSchedule:test:test-scheduler`, `lotos:test:test-zmq-capacity-reservations`, `lotos:test:test-zmq-worker-frames`, and the relevant wake/lifecycle/retry suite(s), before the full build and smoke gates.
