## Code Review: Step 2: Implement non-dropping metrics

### Verdict: REVISE

### Summary
The implementation preserves the unbounded/no-drop handoff queues and exposes useful broker `/info` snapshots plus worker reporter snapshots. Static/build checks passed (`cabal build lotos`, `cabal build lotos:test:test-zmq-worker-frames`, and `cabal build TaskSchedule:exe:ts-worker`); no project-config or package.json lint/typecheck scripts were available. One broker retry-queue instrumentation path can permanently overcount under concurrent failures, which undermines the stated current-depth metric.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs:165] [important]** — Stale-worker recovery records recovered retry enqueues by taking `failedTaskQueue` size before/after `recoverStaleWorkers`. `failedTaskQueue` is also mutated by `SocketLayer.handleFailedTask` (which already records its own enqueue), so a concurrent worker failure between the two size reads will be counted twice and leave `hqsCurrentDepth`/totals permanently higher than the real queue after drain. Fix by making recovery return the exact number of retry tasks it enqueued (or by adding a stats-aware recovery helper) and record that count directly, rather than inferring it from shared queue depth.

### Pattern Violations
- None found.

### Test Gaps
- Step 3 is still expected to add direct coverage for enqueue/drain/high-water behavior and no-drop/protocol invariants.

### Suggestions
- Consider centralizing enqueue/drain+stats helpers for `TSQueue` as well as `TQueue` so future queue paths cannot update the queue without updating stats.
