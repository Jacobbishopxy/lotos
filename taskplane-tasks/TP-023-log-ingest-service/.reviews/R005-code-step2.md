## Code Review: Step 2: Implement LogIngest service and tests

### Verdict: REVISE

### Summary
The new LogIngest module, ROUTER loop, `/logs/...` routes, and targeted test suite are in place, and `cabal test lotos:test:test-zmq-log-ingest` passes. Static quality commands were skipped because `.pi/taskplane-config.json` declares no typecheck/lint/format commands and there is no `package.json`. However, the implementation still has blocking correctness gaps around bounded memory, ROUTER identity validation, and rejection accounting.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBS/LogIngest.hs:283] [important]** — `logIngestReadCacheMaxTasks` is only enforced on `storeByWorkerTask`; `storeByTask` keeps a `Seq` for every task ID ever seen, so a long-running broker can still grow memory without bound despite the task requirement to avoid unbounded log memory. Fix: enforce the bucket cap consistently for task-indexed caches (and evict corresponding worker-task buckets if needed), then add a test ingesting more than `logIngestReadCacheMaxTasks` distinct task IDs.
2. **[lotos/src/Lotos/Zmq/LBS/LogIngest.hs:203] [important]** — The ROUTER envelope worker ID is checked only after `ingestLogBatch` has already persisted and cached the batch. A sender connected as worker A can submit a batch claiming worker B, poison B's log/state, and then receive no ACK. Fix: validate `routingId == logBatchWorkerId` before ingestion, or reject/ACK the envelope without mutating state; add a regression test for mismatched ROUTER identity.
3. **[lotos/src/Lotos/Zmq/LBS/LogIngest.hs:218] [important]** — Invalid event rejection stats are double-counted: `applyEvent` increments `counterRejectedEvents`, then `applyBatch` increments again by `length rejectedReasons`. Fix: collect rejection reasons during the fold and increment the rejected counter in exactly one place; add a limit/invalid-event test that asserts the stats value.

### Pattern Violations
- None beyond the blocking issues above.

### Test Gaps
- Missing coverage for task-bucket cap eviction, mismatched ROUTER identity, and validation-limit/rejection-stat accounting.

### Suggestions
- Consider applying `logIngestSocketHWM` to the ROUTER socket when the ZMQ wrapper supports it, so the new config knob has runtime effect.
