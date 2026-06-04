# TP-043: Add overload observability for EventLoop handoff queues — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-04
**Review Level:** 3
**Review Counter:** 14
**Iteration:** 2
**Size:** L

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Inventory unbounded handoff queues
**Status:** ✅ Complete

- [x] Plan-review checkpoint — list worker backend, task-status, SocketLayer frontend/backend/TaskProcessor queues, and any existing bounded LogIngest queue metrics.
- [x] Choose observable fields: current depth where cheap, high-water marks, and warning thresholds.
- [x] Define where metrics are exposed: logs, `/info`, `/logs/stats`, or a small broker runtime stats endpoint.

---

### Step 2: Implement non-dropping metrics
**Status:** ✅ Complete

- [x] Add queue-depth/high-water tracking around enqueue/drain operations without converting protocol-critical queues to dropping/bounded queues.
- [x] Emit bounded warning logs when high-water thresholds are crossed.
- [x] Expose enough stats for smoke/manual diagnosis without making info snapshots too heavy.
- [x] Revision R004: record exact stale-worker retry enqueue counts instead of inferring from shared failed-queue depth.
- [x] Revision R005: update stale-worker regression test for `recoverStaleWorkers` returning `(staleWorkerIds, recoveredRetryCount)` and assert the exact retry count.
- [x] Revision R006: make enqueue/dequeue queue metric updates linearizable so `currentDepth` cannot drift under producer/consumer interleavings.

---

### Step 3: Add regression coverage
**Status:** ✅ Complete

- [x] Test that enqueue/drain updates high-water metrics.
- [x] Test that metrics do not change protocol frame ordering or scheduling semantics.
- [x] Keep existing LogIngest rejected/drop accounting distinct from no-drop task/status metrics.
- [x] Plan revision R008: add an explicit current-depth linearizability/interleaving regression for the R006 drift fix.
- [x] Revision R010: add a deterministic producer/consumer interleaving regression that would fail if queue and stats updates were split across transactions.

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Test-review checkpoint — review observability coverage and no-drop invariants.
- [x] Run worker frame/wake tests and broker SocketLayer frame tests.
- [x] Plan revision R012: run `cabal test lotos:test:test-zmq-log-ingest` to exercise LogIngest/no-drop stats-separation coverage.
- [x] Run `cabal build all --enable-tests`.
- [x] Run single/multi-worker smoke if info/log stats changed.

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update mdBook operations/architecture pages with overload metrics and their meaning.
- [x] Update `taskplane-tasks/CONTEXT.md` with remaining overload/backpressure risks.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|

---

## Notes / Discoveries

- Step 1 inventory: worker backend EventLoop hands incoming backend frames to `LBW.socketLoop` via unbounded `backendFrames :: TQueue [ByteString]`; task-status callbacks hand status frames to the same socket-loop via unbounded `workerStatusFrames :: TQueue [ByteString]`; decoded worker tasks then enter `taskQueue :: TSQueue (Task t)` before executor wake. Broker SocketLayer EventLoop hands frontend ROUTER frames, backend ROUTER frames, and TaskProcessor PAIR frames to unbounded `TQueue`s before owner-thread parsing; decoded client tasks enter broker `taskQueue :: TSQueue`, failed retries enter `failedTaskQueue :: TSQueue`, and TaskProcessor notifications remain a separate bounded wake mailbox from TP-040. Existing bounded LogIngest dispatch uses `TBQueue` and records rejected/drop accounting in `/logs/stats`; those semantics must stay distinct from no-drop task/status queues.
- Step 1 fields: track per no-drop queue name, current depth (maintained by enqueue/drain counters, avoiding O(n) snapshots), high-water depth, total enqueued, total drained, configured warning threshold, and last warning depth. Warnings should emit only when a new high-water reaches the threshold and then at least doubles the previous warned depth, so overload is visible without log spam. Use existing `taskQueueHWM` / `failedTaskQueueHWM` for broker durable queues and conservative fixed thresholds for EventLoop handoff queues.
- Step 1 exposure choice: emit throttled WARN logs from worker and broker owner threads when no-drop queues cross thresholds; expose broker queue stats as a small `runtimeQueueStats` list in `/info`; leave `/logs/stats` as LogIngest-only rejected/drop accounting so bounded logging semantics are not conflated with task/status no-drop queues. Worker handoff stats are exposed to worker status reporters through `StatusReporterAPI` for adopters that want to include them in custom heartbeat payloads, but TaskSchedule protocol frames should not be extended for this TP.
- R004 suggestion: consider centralizing stats-aware `TSQueue` helpers in future cleanup so queue mutations cannot bypass metrics.
- Step 4 verification evidence: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-wake` PASS; `cabal test lotos:test:test-zmq-log-ingest` PASS; `cabal build all --enable-tests` PASS; `scripts/task-schedule-smoke.sh` PASS with evidence `.tmp/task-schedule-smoke/task-schedule-smoke-20260604T041010Z-237525/`; `scripts/task-schedule-multi-worker-smoke.sh` PASS with evidence `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260604T041101Z-237524/`.

| 2026-06-04 02:49 | Task started | Runtime V2 lane-runner execution |
| 2026-06-04 02:49 | Step 0 started | Preflight |
| 2026-06-04 02:54 | Review R001 | plan Step 1: APPROVE |
| 2026-06-04 02:56 | Review R002 | code Step 1: APPROVE |
| 2026-06-04 02:58 | Review R003 | plan Step 2: APPROVE |
| 2026-06-04 03:14 | Review R004 | code Step 2: REVISE |
| 2026-06-04 03:33 | Review R005 | code Step 2: REVISE |
| 2026-06-04 03:37 | Review R006 | code Step 2: REVISE |
| 2026-06-04 03:45 | Review R007 | code Step 2: APPROVE |
| 2026-06-04 03:47 | Review R008 | plan Step 3: REVISE |
| 2026-06-04 03:48 | Review R009 | plan Step 3: APPROVE |
| 2026-06-04 03:57 | Review R010 | code Step 3: REVISE |
| 2026-06-04 04:02 | Review R011 | code Step 3: APPROVE |
| 2026-06-04 04:03 | Review R012 | plan Step 4: REVISE |
| 2026-06-04 04:04 | Review R013 | plan Step 4: APPROVE |
| 2026-06-04 04:13 | Review R014 | code Step 4: APPROVE |

| 2026-06-04 03:30 | Worker iter 1 | done in 2459s, tools: 117 |
| 2026-06-04 03:34 | Review R005 | code Step 2: REVISE |
| 2026-06-04 03:38 | Review R006 | code Step 2: REVISE |
| 2026-06-04 03:47 | Review R007 | code Step 2: APPROVE |
| 2026-06-04 03:51 | Review R008 | plan Step 3: REVISE |
| 2026-06-04 03:52 | Review R009 | plan Step 3: APPROVE |
| 2026-06-04 03:59 | Review R010 | code Step 3: REVISE |
| 2026-06-04 04:03 | Review R011 | code Step 3: APPROVE |
| 2026-06-04 04:05 | Review R012 | plan Step 4: REVISE |
| 2026-06-04 04:07 | Review R013 | plan Step 4: APPROVE |
| 2026-06-04 04:17 | Review R014 | code Step 4: APPROVE |

| 2026-06-04 04:20 | Worker iter 2 | done in 3010s, tools: 193 |
| 2026-06-04 04:20 | Task complete | .DONE created |