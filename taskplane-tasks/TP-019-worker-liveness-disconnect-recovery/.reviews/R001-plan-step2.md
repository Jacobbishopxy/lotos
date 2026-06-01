## Plan Review: Step 2: Implement recovery logic

### Verdict: APPROVE

### Summary
The Step 2 plan is aligned with TP-019's required outcomes: stale workers are detected from broker-side heartbeat metadata, removed before scheduling snapshots, and their in-flight tasks are recovered through the existing retry/garbage path. The fixed-clock test strategy addresses the prompt's no-long-sleeps constraint while preserving existing smoke behavior and config compatibility.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Keep the liveness/recovery helpers importable through a narrow internal module so bounded tests can exercise them without expanding the public `Lotos.Zmq` facade unnecessarily.
- When implementing the recovery pass, prefer a helper that returns the recovered retry/garbage dispositions from a supplied `now`; that will make race-sensitive behavior easier to test deterministically.
