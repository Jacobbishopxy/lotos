## Code Review: Step 2: Implement non-dropping metrics

### Verdict: REVISE

### Summary
The previous R005 build issue is fixed: `cabal build lotos lotos:test:test-zmq-worker-frames TaskSchedule:exe:ts-worker` now reports `Up to date`. Project config still declares no typecheck/lint/format commands and there is no `package.json`, so there were no configured static quality checks to run. The implementation broadly preserves no-drop queues and exposes useful snapshots, but several stats updates are not synchronized with the queue mutations they describe, so `currentDepth` can permanently drift under normal producer/consumer interleavings.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBS/SocketLayer.hs:290] [important]** — The broker task/retry queue enqueues publish to the `TSQueue` before recording the metric, while the task processor can concurrently dequeue and record a drain (`TaskProcessor.hs:173-177`). If the dequeue happens between `enqueueTS` and `recordHandoffEnqueue`, `applyDrain` clamps the stats depth at 0 and the later enqueue stat leaves `hqsCurrentDepth` at 1 even though the queue is empty. The same race exists for failed-task enqueues at `SocketLayer.hs:448-450`, requeues at `TaskProcessor.hs:200-204`, worker task enqueues at `Internal/WorkerRuntime.hs:131-134`, and worker status-frame writes at `LBW.hs:431-440`. Fix by making queue mutation and stats mutation linearizable (preferably a single STM helper that updates both TVars/TQueues together), or at minimum by recording the enqueue before the item becomes drainable and preserving notification/order semantics.

### Pattern Violations
- None found.

### Test Gaps
- Step 3 still needs direct enqueue/drain/high-water tests and no-drop/protocol invariant coverage; include at least one interleaving/concurrency regression for stats depth so this race cannot recur.

### Suggestions
- Centralizing stats-aware enqueue/dequeue helpers for both `TSQueue` and `TQueue` would reduce the chance of future paths bypassing or mis-ordering metric updates.
