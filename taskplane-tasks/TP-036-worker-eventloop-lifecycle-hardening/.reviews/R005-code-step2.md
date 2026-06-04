## Code Review: Step 2: Implement lifecycle guards

### Verdict: REVISE

### Summary
The backend and log EventLoop command paths now stop retrying on `ETERM`, and `cabal build lotos` plus the worker frame/log transport suites pass. However, task-status callbacks still use raw blocking `Zmqx.Pair.sends` after the backend loop can stop, so task execution can still hang or silently enqueue to a dead transport instead of finishing/reporting failure predictably.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBW.hs:383] [important]** — `sendTaskStatusToWorkerPair` still performs a direct `ZmqxM.sends` on the internal PAIR from task execution callbacks. The upstream `Zmqx.Pair.sends` contract blocks until the peer can receive; once `socketLoop` exits and the EventLoop-owned PAIR peer is closed/stopped, later task callbacks have no bounded live-state check and may block indefinitely (or be accepted into a dead path) instead of returning/logging a predictable delivery failure. This misses the Step 2 requirement and the Step 1 decision that status sends after backend transport stop must not block indefinitely. Fix by routing task-status reports through a nonblocking/STM handoff owned by `WorkerService` with a backend-stopped flag, or otherwise add a bounded shutdown-aware send path that returns/logs failure once the backend transport is terminal.

### Pattern Violations
- None beyond the blocking raw PAIR send noted above.

### Test Gaps
- Add a regression that stops the backend EventLoop/PAIR peer and then invokes `taSendTaskStatus` or `sendTaskStatus`, asserting it returns within a short timeout and records/logs a failed delivery rather than hanging.

### Suggestions
- The `.pi` static quality-check configuration declares no typecheck/lint/format commands and there is no `package.json`, so no configured static checks were available. I did run `cabal build lotos` and `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-log-transport`; both passed.
