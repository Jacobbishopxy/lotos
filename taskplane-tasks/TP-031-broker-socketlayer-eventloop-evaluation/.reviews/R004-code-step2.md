## Code Review: Step 2: Implement selected broker path

### Verdict: APPROVE

### Summary
The implementation follows the selected deferral path: broker traffic stays on the existing direct `Zmqx.poll` loop, the EventLoop rationale is recorded in `SocketLayer.hs`, and the removed `ReaderT` wrapper/unused `ver` field do not alter the frontend ACK, backend worker-task, worker-status, retry/garbage, or notify frame paths. `.pi/taskplane-config.json` declares no typecheck/lint/format-check commands and there is no `package.json` fallback; as an extra Haskell sanity check I ran `cabal build lotos`, which reported `Up to date`.

### Issues Found
- None.

### Pattern Violations
- None.

### Test Gaps
- None for this Step 2 code review. The required protocol frame tests, lifecycle tests, full `--enable-tests` build, and smoke scripts remain scheduled in Step 3.

### Suggestions
- Update the two remaining comments that still mention the removed Reader monad (`handleWorkerTaskStatus` / `handleTaskStatus`) so the source comments consistently describe the explicit direct-poll context.
- Consider dropping `tcWorkerStatusMap` from `TaskContext`, since task-status handling no longer uses it and the context is intended to be narrow.
