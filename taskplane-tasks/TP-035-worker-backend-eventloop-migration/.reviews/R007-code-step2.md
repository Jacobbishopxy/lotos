## Code Review: Step 2: Implement EventLoop-backed worker backend loop

### Verdict: REVISE

### Summary
The EventLoop ownership migration compiles (`cabal build lotos` reports up to date) and no project-declared typecheck/lint/format commands are configured in `.pi/taskplane-config.json` or `package.json`. However, the new drain logic can starve internal task-status forwarding and periodic worker heartbeats whenever backend task frames are continuously queued, which violates the Step 1/Step 2 requirement that status traffic not be gated behind backend-task waits and that heartbeat cadence be preserved.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBW.hs:279] [important]** — `drainWorkerBackendFrames` drains until both queues are empty before the loop can send a periodic worker status, and `tryReadWorkerBackendFrames`/`orElse` always prefer `backendFrames` over `statusFrames` (`LBW.hs:316-330`, `LBW.hs:343-344`). Under a large or continuous backend task stream, the loop can keep enqueueing backend tasks indefinitely while internal `WorkerReportTaskStatus` frames and heartbeats are delayed indefinitely. This regresses the approved design requirement that task-status traffic be drained promptly and not gated by backend-task backlog. Fix by making the drain bounded/fair: process at most a small batch per iteration, alternate or explicitly drain both queues each cycle, and re-check the trigger between batches so heartbeats remain periodic.

### Pattern Violations
- None beyond the fairness/cadence regression above.

### Test Gaps
- Step 3 is expected to add the ordering/lifecycle tests; include coverage for status forwarding and heartbeat behavior while backend task frames are already queued or arriving continuously.

### Suggestions
- Keep `cabal build lotos` (or a narrower target if one emerges) in the verification notes for this Haskell-only change since no taskplane static-check commands are declared.
