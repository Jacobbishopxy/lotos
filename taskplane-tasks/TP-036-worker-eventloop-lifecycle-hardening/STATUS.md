# TP-036: Harden worker EventLoop lifecycle and failure behavior — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 2
**Review Counter:** 14
**Iteration:** 1
**Size:** M

> **Hydration:** Checkboxes represent meaningful outcomes, not individual code
> changes. Workers expand steps when runtime discoveries warrant it.

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Inventory worker EventLoop failure modes
**Status:** ✅ Complete

- [x] Plan-review checkpoint — enumerate stopped-loop, callback exception, mailbox full, broker disconnect, and context termination paths.
- [x] Decide which failures are logged/retried, which terminate loops, and which are safe no-ops.
- [x] Map failure modes to tests.
- [x] R001: Document source-grounded EventLoop API/current uses.
- [x] R001: Document concrete failure-mode behavior decisions.
- [x] R001: Document failure-mode-to-test matrix.

---

### Step 2: Implement lifecycle guards
**Status:** ✅ Complete

- [x] Add bounded handling for stopped-loop and `ETERM` errors in backend/log EventLoop command paths.
- [x] Ensure worker task execution can finish or report failure predictably when transport loops stop.
- [x] Avoid coupling logging failures to task/status backend progress.
- [x] R005: Replace blocking task-status PAIR sends with backend-owned bounded handoff plus stopped-transport failure reporting.

---

### Step 3: Add regression coverage
**Status:** ✅ Complete

- [x] Add tests or harnesses for backend EventLoop stopped-loop behavior and logging EventLoop stopped-loop behavior.
- [x] Verify mailbox-full/drop accounting remains visible for logs and does not apply to task/status semantics unless explicitly designed.
- [x] Confirm forked app actions do not outlive context teardown in tests.
- [x] R007: Add explicit task-status callback stopped-backend regression for `taSendTaskStatus`/`sendTaskStatus` returning promptly.
- [x] R009: Exercise actual worker log loop stopped-`ETERM` classification and `TaskAcceptorAPI.taSendTaskStatus` callback path without exposing test hooks in the public facade.
- [x] R010: Wait for forked LotosApp children before context teardown and preserve the public two-field `LotosEnv` record surface.

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review lifecycle and failure semantics.
- [x] Run worker frame/wake/log transport tests.
- [x] Run `cabal build all --enable-tests`.
- [x] Run smoke scripts if runtime loops changed materially.

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `taskplane-tasks/CONTEXT.md` with worker EventLoop lifecycle guarantees and gaps.
- [x] Record any remaining lifecycle debt in STATUS.md.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | Plan | 1 | REVISE | `.reviews/R001-plan-step1.md` |
| R002 | Plan | 1 | APPROVE | `.reviews/R002-plan-step1.md` |
| R003 | Code | 1 | APPROVE | `.reviews/R003-code-step1.md` |
| R004 | Plan | 2 | APPROVE | `.reviews/R004-plan-step2.md` |
| R005 | Code | 2 | REVISE | `.reviews/R005-code-step2.md` |
| R006 | Code | 2 | APPROVE | `.reviews/R006-code-step2.md` |
| R007 | Plan | 3 | REVISE | `.reviews/R007-plan-step3.md` |
| R008 | Plan | 3 | APPROVE | `.reviews/R008-plan-step3.md` |
| R009 | Code | 3 | REVISE | `.reviews/R009-code-step3.md` |
| R010 | Code | 3 | REVISE | `.reviews/R010-code-step3.md` |
| R011 | Code | 3 | APPROVE | `.reviews/R011-code-step3.md` |
| R012 | Plan | 4 | APPROVE | `.reviews/R012-plan-step4.md` |
| R013 | Code | 4 | APPROVE | `.reviews/R013-code-step4.md` |
| R014 | Code | 4 | APPROVE | `.reviews/R014-code-step4.md` |

---

## Notes / Discoveries

### Step 1 source-grounded EventLoop inventory

- `Zmqx.EventLoop.withEventLoopIn` brackets worker-owned sockets; public `send`/`sends`/`recv` fail with `ETERM` "event loop is stopped" after normal shutdown, and rethrow the recorded worker exception after callback/socket-loop failure. Callback exceptions terminate the EventLoop worker. Mailbox receivers use bounded `TBQueue` delivery and silently drop newest messages when full.
- `LBW.runWorkerService` starts three loops from one app context: `tasksExecLoop`, independent `runWorkerLogTransport`, and backend `withEventLoopIn`. Backend callbacks only `writeTQueue` raw frames to unbounded STM queues; socket-loop thread parses task frames, forwards internal task-status frames, and sends heartbeat frames via `sendWorkerBackendDealerFrames`.
- `LBW.sendTaskStatus`/`taSendTaskStatus` currently send to the internal PAIR from task execution code. The backend EventLoop owns the connected PAIR side and forwards valid task-status frames to the broker backend DEALER.
- `LBW.LogTransport.runWorkerLogEventLoop` owns a separate LogIngest DEALER/EventLoop with bounded ACK mailbox capacity derived from `logIngestSocketHWM`. Log enqueue/drop accounting lives in `WorkerLogTransport` memory and is intentionally separate from backend task/status traffic.
- `WorkerRuntime.dequeueOrWaitForTasks` waits on an STM wake signal; forked task execution can otherwise wait indefinitely if context teardown only stops transport loops.

### Step 1 failure-mode inventory

| Failure mode | Trigger/source | Current/desired affected path |
|---|---|---|
| Backend EventLoop stopped | `sendWorkerBackendDealerFrames` returns `Left ETERM` or worker exception after bracket exit | Backend socket-loop must log once and terminate rather than recurse; task/status sends must not be treated as successful after transport stop. |
| Log EventLoop stopped | `Zmqx.EventLoop.sends`/`recv` in `workerLogLoop` returns `Left ETERM` after stop | Logging loop must log and exit/back off without crashing task execution or backend status progress. |
| Backend callback exception | `Callback` throws while writing backend/status frames | Callback should remain non-throwing STM `writeTQueue`; if EventLoop still fails, backend loop logs terminal failure. |
| Log callback/mailbox full | ACK mailbox full drops newest ACK; `recv` can timeout or stop | Log transport retries in-flight batches and keeps visible enqueue/drop markers; no task/status semantics change. |
| Broker disconnect or no ACK | DEALER send succeeds locally but broker unavailable; log ACK timeout | Backend heartbeat/task-status send is best-effort local send unless EventLoop reports error; log batches retry with backoff and remain pending until ACK/drop policy changes. |
| Context termination / `ETERM` | App context teardown while EventLoops or task fork are active | EventLoop API wakes blocked send/recv with `ETERM`; worker code should classify this as shutdown/stopped-loop and avoid accepting more frames or leaving forked actions running past scoped teardown in tests. |

### Step 1 behavior decisions

| Case | Decision |
|---|---|
| Backend task-status/heartbeat `sends` returns stopped-loop/`ETERM` | Log at WARN/ERROR as transport-terminal, stop backend socket-loop, and do not continue draining/accepting backend/status frames. Treat as failed delivery, not retry-in-loop, to avoid reordering or infinite recursion after shutdown. |
| Backend EventLoop worker exception/callback exception | Log terminal backend EventLoop failure. Keep callbacks limited to STM writes so ordinary frame handling exceptions remain on socket-loop thread where they can be bounded. |
| Task execution reports status after backend transport stopped | Return/log predictable failure from status send instead of silently succeeding. Task callback should be able to finish or report local failure without blocking indefinitely on stopped PAIR/backend transport. |
| Logging `sends`/`recv` stopped-loop/`ETERM` | Log once per stopped operation and terminate the logging loop (or stop retrying) because retries against a stopped bracket cannot succeed. This must never stop `tasksExecLoop` or backend status loop. |
| Logging broker disconnect/ACK timeout | Safe retry with existing in-flight batch and backoff; enqueue/drop visibility remains in `WorkerLogTransport`. No task/status semantics change. |
| Logging ACK mailbox full | Safe lossy ACK delivery; retry later makes broker ACK idempotence recover. Preserve visible worker-log queue drop markers; do not apply bounded/drop mailbox semantics to backend task/status queues. |
| Context teardown/forked app actions | Scoped tests should prove worker-owned child actions are cancelled/finished before context exits; no fork should keep using ZMQ context after teardown. |

### Step 2 implementation notes

- Implemented backend send continuation guards so stopped/`ETERM` backend EventLoop sends log and stop `socketLoop` recursion instead of throwing through `zmqUnwrap`; task-status PAIR sends now log failures from task callbacks without crashing task execution.
- Implemented logging EventLoop stopped-loop guards so `send`/`recv` `ETERM` terminates the log loop while ordinary send/recv errors continue retry/backoff behavior.
- Verification during Step 2: `cabal build lotos`; `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-log-transport` passed before and after the R005 nonblocking status-handoff revision.
- R005 revision: task-status callbacks now enqueue status frames directly into an unbounded backend-owned STM queue guarded by a backend-running `TVar`; once backend transport stops, callbacks return/log `ETERM` instead of blocking on a raw PAIR send.
- Step 3 verification: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-log-transport` passed with backend stopped-send, task-status stopped-callback timeout, forked-action teardown, and log stopped-loop coverage. R009/R010 revised coverage now exercises `TaskAcceptorAPI.taSendTaskStatus` through a live worker harness, `workerLogLoopStep` stopped-loop classification, waits for forked children before `runZmqApp` returns, and keeps the public `LotosEnv` constructor shape unchanged.
- Step 4 targeted worker tests: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-wake lotos:test:test-zmq-worker-log-transport` passed.
- Step 4 build gate: `cabal build all --enable-tests` completed successfully.
- Step 4 smoke gates: `scripts/task-schedule-smoke.sh` passed with evidence `.tmp/task-schedule-smoke/task-schedule-smoke-20260603T121919Z-3402080`; `scripts/task-schedule-multi-worker-smoke.sh` passed with evidence `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260603T122007Z-3402079`.
- Remaining lifecycle debt: backend task/status STM queues remain intentionally unbounded to avoid dropping protocol-critical work; future production overload work should add observability/backpressure without changing no-drop semantics silently.

### Step 1 failure-mode-to-test matrix

| Coverage target | Planned test/harness |
|---|---|
| Backend stopped-loop send | Extend `test-zmq-worker-frames` with a `withEventLoopIn` backend loop captured outside its bracket; after bracket exits, call `sendWorkerBackendDealerFrames`/status-forward helper and assert `Left ETERM` or bounded terminal behavior without frame delivery. |
| Backend callback/frame handling remains nonblocking | Keep backend callback tests queue-based; add regression around stopped backend send so no callback exception is needed to terminate normal path. |
| Logging stopped-loop send/recv | Extend `test-zmq-worker-log-transport` or add exported/testable helper to run a log EventLoop action after bracket stop and assert the loop classifies `ETERM` as terminal rather than infinite retry. |
| Logging mailbox/drop accounting | Existing `drop-oldest pressure creates a visible gap marker`, `low-priority drop policy preserves result logs`, and delayed ACK tests cover visible drop/in-flight accounting; keep them targeted and ensure no equivalent bounded mailbox is introduced for backend task/status queues. |
| Context teardown/forked actions | Add bounded harness around worker app execution (or a narrow helper in `Internal.WorkerRuntime`) proving forked app actions are cancelled or have finished before context exits; run under timeout to catch leaked use-after-teardown. |
| Protocol frame ordering | Re-run `test-zmq-worker-frames` plus existing round-trip tests; do not change multipart shape without updating those assertions. |
| R007 task-status callback stopped-backend path | Add a direct `sendTaskStatus`/`taSendTaskStatus` regression around the `workerBackendRunning` guard: mark backend stopped, invoke the callback under a short timeout, and assert it returns without enqueuing a dead status frame. |

| 2026-06-03 11:19 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 11:19 | Step 0 started | Preflight |
| 2026-06-03 11:21 | Review R001 | plan Step 1: REVISE |
| 2026-06-03 11:25 | Review R002 | plan Step 1: APPROVE |
| 2026-06-03 11:26 | Review R003 | code Step 1: APPROVE |
| 2026-06-03 11:27 | Review R004 | plan Step 2: APPROVE |
| 2026-06-03 11:36 | Review R005 | code Step 2: REVISE |
| 2026-06-03 11:42 | Review R006 | code Step 2: APPROVE |
| 2026-06-03 11:45 | Review R007 | plan Step 3: REVISE |
| 2026-06-03 11:46 | Review R008 | plan Step 3: APPROVE |
| 2026-06-03 11:59 | Review R009 | code Step 3: REVISE |
| 2026-06-03 12:06 | Review R010 | code Step 3: REVISE |
| 2026-06-03 12:12 | Review R011 | code Step 3: APPROVE |
| 2026-06-03 12:13 | Review R012 | plan Step 4: APPROVE |
| 2026-06-03 12:17 | Review R013 | code Step 4: APPROVE |
| 2026-06-03 12:27 | Review R014 | code Step 4: APPROVE |

| 2026-06-03 12:30 | Worker iter 1 | done in 4262s, tools: 242 |
| 2026-06-03 12:30 | Task complete | .DONE created |