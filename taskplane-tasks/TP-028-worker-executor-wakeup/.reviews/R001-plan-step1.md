## Plan Review: Step 1: Define wakeup contract

### Verdict: REVISE

### Summary
The wakeup contract itself is sound: a coalescing `TMVar ()` signal, enqueue-before-signal ordering, and dequeue-before-block behavior should eliminate the 10-second empty-queue latency without touching protocol frame ordering. The diagnostics plan also meets the requirement by removing the hot-loop `putStrLn "> poll"` while retaining structured DEBUG logs. The test plan needs one correction before implementation because it claims existing tests cover worker waiting/processing counts, but those tests do not exercise `WorkerService` counter transitions.

### Issues Found
1. **[Severity: important]** — `STATUS.md:71` defines only a wake-signal promptness/coalescing unit test, then relies on existing worker lifecycle/scheduler/logging/smoke gates for worker count correctness. The existing lifecycle test calls `processTasks` directly and only asserts task statuses/logs, while the scheduler test uses fabricated `WorkerState` values; neither proves `wiProcessingTaskNum` / `wiWaitingTaskNum` remain accurate through the new executor wake path. Fix: add an explicit planned scenario that observes the worker executor/count path, e.g. enqueue a burst with a blocking/deterministic acceptor and assert processing/waiting counts during a batch and after completion, or expose a narrow internal executor helper so the test can verify the same counter transitions without a full smoke run.

### Missing Items
- A concrete count-accuracy test tied to the changed `tasksExecLoop`/enqueue wake behavior, not just scheduler behavior with prebuilt count values.

### Suggestions
- In the contract notes, spell out that signalling uses non-blocking `tryPutTMVar`/equivalent coalescing semantics and that `tasksExecLoop` always rechecks/dequeues the queue before blocking, so stale signals cannot cause lost work.
