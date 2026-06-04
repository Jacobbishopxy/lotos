## Code Review: Step 1: Design golden fixture shape

### Verdict: REVISE

### Summary
Step 1 records the selected fixture approach and the targeted frame tests pass, but the inventory note has a material accuracy problem for worker-state coverage. No configured typecheck/lint/format commands were available in `.pi/taskplane-config.json` or `package.json`; I ran the step's targeted tests and they passed.

### Issues Found
1. **[taskplane-tasks/TP-048-golden-protocol-frame-fixtures/STATUS.md:83] [important]** — The inventory says TaskSchedule `WorkerState` old/new payload fixtures are missing, but `applications/TaskSchedule/test/Scheduler.hs:135-150` already has `workerStateFramesAppendCapacityAndDecodeOldPayloads`, which asserts exact new frames, decodes the old 8-frame payload with default capacity, and rejects an extra future frame. This means the Step 1 coverage map is inaccurate for one of the required protocol areas. Fix: update the Step 1 notes/assertion design to classify WorkerState old/new fallback as existing coverage (or specify the genuinely missing delta, if any) so Step 2 does not duplicate or misdirect the fixture work.

### Pattern Violations
- None.

### Test Gaps
- Not applicable for this design/status-only step. Verification run: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames` passed.

### Suggestions
- Consider marking Step 1 complete once the inventory correction is made, since all Step 1 checkboxes are already checked.
