## Plan Review: Step 2: Add golden protocol tests

### Verdict: APPROVE

### Summary
The Step 2 plan is aligned with the PROMPT and with the corrected Step 1 inventory: it targets exact golden frame assertions for core request/status/ACK payloads, legacy append-only WorkerState fallback coverage, and malformed/wrong-order negative decoding cases. The existing Step 1 notes provide enough specificity about missing coverage areas without over-prescribing implementation details.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- If Step 2 modifies or duplicates the TaskSchedule `WorkerState` fallback fixture in `applications/TaskSchedule/test/Scheduler.hs`, also run `cabal test TaskSchedule:test:test-scheduler` in addition to the listed lotos protocol suites.
- Consider clarifying in STATUS.md whether the WorkerState fallback checkbox is satisfied by the existing TaskSchedule fixture or by an added wrapper-level backend-status fixture, to avoid accidental duplicate coverage.
