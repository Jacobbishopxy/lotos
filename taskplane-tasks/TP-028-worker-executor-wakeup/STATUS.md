# TP-028: Make Worker Task Execution Wake on Enqueue — Status

**Current Step:** Final Verification
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 2
**Review Counter:** 5
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Define wakeup contract
**Status:** ✅ Complete

- [x] Plan-review checkpoint — define the worker wakeup primitive (STM/TMVar/TQueue/EventTrigger integration) and how task arrival wakes `tasksExecLoop`.
- [x] Define latency/correctness tests: no task should wait for the old 10-second sleep, and worker waiting/processing counts should remain accurate.
- [x] Add a concrete worker executor count-accuracy test scenario tied to `tasksExecLoop` wake behavior (blocking/deterministic acceptor or narrow internal helper), per R001 plan review.
- [x] Define how to remove or replace `putStrLn "> poll"` without losing useful diagnostics.

---

### Step 2: Implement wake-on-enqueue and cleanup
**Status:** ✅ Complete

- [x] Add a bounded/simple wake signal to `WorkerService` state and trigger it whenever `socketLoop` enqueues an incoming task.
- [x] Add an internal worker-runtime helper and `test-zmq-worker-wake` regression covering wake promptness, coalescing, and worker counter transitions.
- [x] Change `tasksExecLoop` to block/wait on the wake signal instead of fixed 10-second sleeps when the task queue is empty.
- [x] Remove broker socket-layer `putStrLn "> poll"` or convert it to structured DEBUG logging only if useful.
- [x] Preserve task status, worker status, and reliable log transport semantics.

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review concurrency changes and failure modes.
- [x] Run targeted worker lifecycle/scheduler/logging tests affected by worker behavior.
- [x] Run `cabal build all --enable-tests`.
- [x] Isolate multi-worker smoke LogIngest journal/config so it can run after the single-worker smoke without cross-run worker-count contamination.
- [x] Run `scripts/task-schedule-smoke.sh`; run multi-worker smoke if changes affect burst scheduling or worker state.

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update docs only if user-visible latency/runtime behavior changes.
- [x] Update `taskplane-tasks/CONTEXT.md` with remaining EventLoop follow-up.

---

### Final Verification
**Status:** ✅ Complete

- [x] Build/tests/smoke required by PROMPT.md pass
- [x] Documentation requirements satisfied
- [x] Exactly one final TP commit exists

---

## Notes / Discoveries

- Step 1 plan: add an internal bounded `TaskWakeSignal` backed by `TMVar ()`; `socketLoop` will signal it immediately after a successful worker task enqueue, while `tasksExecLoop` will dequeue first and only block on the signal when the queue is empty, eliminating the old 10-second sleep without changing task/status/log frame order.
- Step 1 test plan: add `lotos:test:test-zmq-worker-wake` against a narrow internal worker-runtime helper. The test will start executor dequeue on an empty `TSQueue`, enqueue a three-task burst, signal once, assert the batch wakes within 500ms instead of the old 10-second sleep, and assert worker counters transition to `processing=2/waiting=1` during the batch and `processing=0/waiting=1` after completion. A companion test will prove repeated notifications coalesce into one wake. Existing worker lifecycle, scheduler, worker-log/log-ingest tests, build-all, and smoke gates remain the broader regression coverage for statuses/log transport/end-to-end behavior.
- Step 1 diagnostics plan: remove broker socket-layer `putStrLn "> poll"`; existing `logApp DEBUG` calls around frontend/backend handling remain the structured diagnostics path without hot-loop stdout spam.
- R001 suggestion: keep the contract explicit that wake signalling uses non-blocking/coalescing `tryPutTMVar` semantics and that the executor always rechecks/dequeues the queue before blocking, so stale signals cannot lose work.
- Step 2 targeted check: `cabal test lotos:test:test-zmq-worker-wake` passed after adding the internal wake/count regression.
- Code review checkpoint: `review_step(step=2, type="code")` returned APPROVE in `R004-code-step2.md`, covering the Step 2 concurrency changes before verification.
- Step 3 targeted tests passed: `cabal test lotos:test:test-zmq-worker-wake TaskSchedule:test:test-worker-lifecycle TaskSchedule:test:test-scheduler lotos:test:test-zmq-worker-log-transport lotos:test:test-zmq-log-ingest lotos:test:test-zmq-worker-frames`.
- Step 3 build gate passed: `cabal build all --enable-tests`.
- Step 3 smoke discovery: `scripts/task-schedule-smoke.sh` passed, but the first `scripts/task-schedule-multi-worker-smoke.sh` run failed because `/logs/stats` counted prior `simpleWorker_1` events from the shared default `logs/worker-logs.journal`; the worker log events for both smoke workers were present and clean, so the script needs run-local LogIngest journal isolation.
- Step 3 smoke script fix: `scripts/task-schedule-multi-worker-smoke.sh` now writes broker `logIngest` and worker `workerLogging` configs with a run-local `$EVIDENCE_DIR/worker-logs.journal`; `bash -n` passed.
- Step 3 smoke gates passed: `scripts/task-schedule-smoke.sh` at `.tmp/task-schedule-smoke/task-schedule-smoke-20260603T040454Z-2303111/` and rerun `scripts/task-schedule-multi-worker-smoke.sh` at `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260603T041219Z-2312184/`.
- Step 3 code review: `review_step(step=3, type="code")` returned APPROVE after the smoke script isolation change.
- Step 4 docs: `docs/task-schedule-mvp.md` now documents worker wake-on-enqueue runtime behavior and TP-028 implementation status.
- Step 4 context: `taskplane-tasks/CONTEXT.md` now records TP-028 worker responsiveness as complete and narrows the remaining follow-up to optional `Zmqx.EventLoop`/socket-ownership runtime-loop work.

| 2026-06-03 03:39 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 03:39 | Step 0 started | Preflight |
| 2026-06-03 03:47 | Review R001 | plan Step 1: REVISE |
| 2026-06-03 03:51 | Review R002 | plan Step 1: APPROVE |
| 2026-06-03 03:55 | Review R003 | plan Step 2: APPROVE |
| 2026-06-03 04:02 | Review R004 | code Step 2: APPROVE |
| 2026-06-03 04:17 | Review R005 | code Step 3: APPROVE |

| 2026-06-03 04:22 | Worker iter 1 | done in 2593s, tools: 160 |
| 2026-06-03 04:22 | Task complete | .DONE created |