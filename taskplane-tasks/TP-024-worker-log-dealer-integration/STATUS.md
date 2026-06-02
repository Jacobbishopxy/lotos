# TP-024: Worker DEALER Log Transport Integration — Status

**Current Step:** Final Verification
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 8
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Plan worker-side reliability semantics
**Status:** ✅ Complete

- [x] Plan-review checkpoint — define worker queue limits, batch flush triggers, retry/ACK timeout behavior, and drop priority.
- [x] Define how dropped-log counts and sequence gaps surface to operators.
- [x] Ensure task execution cannot deadlock indefinitely on log transport failure.
- [x] R001: Pin concrete idle flush, ACK timeout, retry backoff, partial-acceptance, and rejection handling semantics.
- [x] R001: Pin worker-wide monotonic sequence counter semantics and visible dropped-range handling without reusing sequence numbers.

---

### Step 2: Implement worker transport switch
**Status:** ✅ Complete

- [x] Replace PUB send path with DEALER LogBatch sender and ACK reader, preferably on a separate logging socket/channel from task backend traffic.
- [x] Preserve task stdout/stderr/final-result logging semantics as LogEvent streams/levels.
- [x] Update broker startup/config to run LogIngest with the new logging address and keep or remove old SUB path according to compatibility needs.
- [x] Add tests for ACK/retry/drop behavior using bounded fakes where ZMQ integration would be slow.
- [x] R005: Map TaskSchedule `STDOUT:`/`STDERR:` command output prefixes to `LogStdout`/`LogStderr` with an stderr regression test.

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review runtime failure modes and config compatibility.
- [x] Run targeted worker/log transport tests.
- [x] Run `cabal build all --enable-tests` and terminating regression suites touched by the transport change.

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update docs/config examples with the new reliable log transport.
- [x] Update CONTEXT to mark PUB/SUB logging replacement status.

---

### Final Verification
**Status:** ✅ Complete

- [x] Build/tests/smoke required by PROMPT.md pass
- [x] Documentation requirements satisfied
- [x] Exactly one final TP commit exists

---

## Notes / Discoveries

- Preflight dependency check: TP-023 status file is `✅ Complete` and git history contains `merge: wave 3 lane 1 — TP-023`.
- Preflight git check: starting from `becd599` with only task STATUS runtime edits in the worktree; final TP-024 history must be squashed to one Lore commit.
- Step 1 reliability plan draft: worker task callbacks enqueue `LogEvent`s into a bounded in-memory buffer using `LogIngestConfig.logIngestWorkerQueueHWM` and never wait for broker ACKs; a dedicated logging DEALER drains ordered batches on `logIngestBatchMaxRecords`/`logIngestBatchMaxBytes` plus retry timeout, then retries the same in-flight `LogBatch` until a matching `LogAck` advances the accepted-through watermark.
- Step 1 drop/visibility plan draft: when the worker buffer overflows, drop contiguous low-priority stdout/stderr/info events first (falling back to oldest/newest according to `logIngestDropPolicy`) and replace the dropped span with a synthetic warn-level gap `LogEvent` whose `logEventDroppedFrom`/`logEventDroppedThrough` make `/logs/stats.droppedEvents` and sequence gaps visible; result/error logs and gap markers have higher retention priority than verbose lines.
- Step 1 deadlock plan draft: the logging socket is separate from backend task/status traffic, enqueue is bounded and quick, ACK waits happen only in the logging thread, and rejected/oversized batches are discarded or converted to visible gap markers rather than retried forever.
- R001 suggestion noted: prefer queued result/error events over verbose logs when choosing what survives buffer pressure and when forming the next batch.
- R001 concrete retry/ACK semantics: add optional `LogIngestConfig` timing knobs (`logIngestFlushIntervalMicros` default 100ms, `logIngestAckTimeoutMicros` default 1s, `logIngestRetryBackoffMicros` default 250ms). The worker logging thread flushes partial batches at least every flush interval, waits for matching `LogAck`s with bounded polling, sleeps the retry backoff before resending an unacked in-flight batch, removes ACKed events through `acceptedThrough`, and if an ACK reports rejection without progress it drops/converts that in-flight span to visible gap markers so an invalid batch is not retried forever.
- R001 worker sequence semantics: each worker owns one monotonic worker-wide sequence domain aligned with LogIngest `acceptedThroughByWorker`; normal stdout/stderr/result events, synthetic gap markers, and any replacement marker are ordered in that worker sequence. Dropped ranges describe unsent worker-sequence spans; a gap marker occupies the first dropped sequence and the discarded normal event for that sequence is never emitted, so no sequence number is emitted twice while broker coverage can advance over the visible dropped span.
- Step 1 operator visibility plan: synthetic gap `LogEvent`s are queryable through `/logs/recent`, `/logs/worker/:workerId`, and `/logs/task/:taskId`; aggregate loss is visible in `/logs/stats` via `droppedEvents`, `sequenceGaps`, and `acceptedThroughByWorker`, while legacy `/info.workerLoggingsMap` will be backfilled from LogIngest recent logs for compatibility.
- Step 1 deadlock guarantee: task execution callbacks perform bounded buffer mutation only; all ZMQ send/receive, ACK timeout, retry, and rejected-batch handling live in the dedicated logging loop, so broker/log endpoint outages cannot block `processTasks` or task-status reporting on the backend DEALER.
- Step 2 implementation evidence: `Lotos.Zmq.LBW.LogTransport` owns the bounded worker buffer, `LogBatch` creation, ACK polling/retry loop, and rejected-batch gap conversion; `LBW.mkWorkerService` now enqueues callbacks and `runWorkerService` starts a dedicated logging DEALER separate from the backend task/status DEALER.
- Step 2 log semantics evidence: `TaskAcceptorAPI` now offers structured `taSendTaskLog`; TaskSchedule live command output is sent as `LogStdout`/`LogInfo`, command final results are sent as `LogResult` with `LogInfo` or `LogError`, and legacy `taPubTaskLogging` maps `WorkerLogging` to stdout/info for compatibility.
- Step 2 broker/config evidence: old JSON without `logIngest`/`workerLogging` now derives a split reliable endpoint via `defaultReliableLogIngestAddr` (demo 5557 -> 5558), TaskSchedule defaults/configs set LogIngest to 5558, InfoStorage keeps the legacy SUB path, and `/info.workerLoggingsMap` is backfilled from recent LogIngest events for compatibility.
- Step 2 test evidence: added `lotos:test:test-zmq-worker-log-transport` covering in-flight retry, ACK prefix removal, visible drop markers, rejected no-progress ACK conversion, and low-priority preservation; targeted test run with log protocol config and TaskSchedule worker lifecycle passed.
- R005 suggestion noted: applying `logIngestSocketHWM` to ZMQ sockets is a follow-up hardening item; this TP keeps queue/batch bounds in code and docs.
- R005 fix evidence: TaskSchedule `classifyCommandOutput` maps `STDERR:` to `LogStderr`/`LogError` and `STDOUT:` to `LogStdout`/`LogInfo`; `applications/TaskSchedule:test:test-worker-lifecycle` now asserts stderr output is captured as `LogStderr` and passed.
- Step 3 code review checkpoint evidence: Step 2 code review R005 found stderr stream mapping; the fix was committed and Step 2 re-review R006 returned APPROVE for runtime failure modes/config compatibility.
- Step 3 targeted test evidence: `cabal test lotos:test:test-zmq-worker-log-transport lotos:test:test-zmq-log-protocol-config lotos:test:test-zmq-log-ingest applications/TaskSchedule:test:test-worker-lifecycle --test-show-details=direct` passed.
- Step 3 full build/regression evidence: `cabal build all --enable-tests` passed; additional terminating suites `cabal test lotos:test:test-conc-executor applications/TaskSchedule:test:test-scheduler --test-show-details=direct` passed.
- Step 4 documentation evidence: `docs/logging-redesign.md`, `applications/TaskSchedule/config/broker.json`, and `applications/TaskSchedule/config/worker.json` document/use the split reliable LogIngest endpoint and worker DEALER runtime caveats.
- Step 4 CONTEXT evidence: `taskplane-tasks/CONTEXT.md` now records TP-024's worker DEALER switch/backfill completion and narrows remaining logging work to recovery/retention, socket HWM, and legacy PUB/SUB removal/rename decisions.
- Final verification evidence: required builds/tests passed (`cabal build all --enable-tests`; targeted log/worker suites; `test-conc-executor`; `test-scheduler`). PROMPT.md lists no additional smoke script beyond build/tests.
- Final documentation evidence: `docs/logging-redesign.md` and `taskplane-tasks/CONTEXT.md` satisfy the PROMPT.md must-update requirements; TaskSchedule JSON configs document the split reliable endpoint.
- Final git evidence: after squashing temporary review/checkpoint commits, `git rev-list --count becd599..HEAD` returned `1`.

| 2026-06-01 18:32 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 18:32 | Step 0 started | Preflight |
| 2026-06-01 18:41 | Review R001 | plan Step 1: REVISE |
| 2026-06-01 18:45 | Review R002 | plan Step 1: APPROVE |
| 2026-06-01 18:48 | Review R003 | code Step 1: APPROVE |
| 2026-06-01 18:52 | Review R004 | plan Step 2: APPROVE |
| 2026-06-01 19:08 | Review R005 | code Step 2: REVISE |
| 2026-06-01 19:20 | Review R006 | code Step 2: APPROVE |
| 2026-06-01 19:21 | Review R007 | plan Step 3: APPROVE |
| 2026-06-01 19:27 | Review R008 | code Step 3: APPROVE |

| 2026-06-01 19:31 | Worker iter 1 | done in 3537s, tools: 177 |
| 2026-06-01 19:31 | Task complete | .DONE created |