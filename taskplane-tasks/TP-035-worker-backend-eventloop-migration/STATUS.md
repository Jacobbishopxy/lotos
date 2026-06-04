# TP-035: Migrate worker backend transport to EventLoop — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 3
**Review Counter:** 14
**Iteration:** 2
**Size:** L

> **Hydration:** Checkboxes represent meaningful outcomes, not individual code
> changes. Workers expand steps when runtime discoveries warrant it.

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Design worker backend EventLoop ownership
**Status:** ✅ Complete

- [x] Plan-review checkpoint — define endpoint names, mailbox capacities, heartbeat timing, and internal PAIR handling.
- [x] Keep EventLoop callbacks lightweight; prefer mailbox drain on the worker socket-loop thread.
- [x] Specify how status reports are sent through EventLoop without directly touching registered sockets.

**Design draft:** Register backend DEALER as EventLoop transceiver endpoint `worker-backend-dealer` with a lightweight `Callback` that only atomically writes raw multipart frames into a worker-owned `TQueue`, and register internal PAIR connect-side as EventLoop receiver endpoint `worker-backend-status-pair` with the same callback-to-`TQueue` pattern. This deliberately avoids EventLoop `Mailbox` delivery for loss-sensitive task/status frames because the current `Mailbox` mode silently drops newest frames when full; therefore there are no EventLoop mailbox capacities for these endpoints. The handoff queues are unbounded `TQueue`s, matching the existing worker task queue's no-drop behavior and keeping callbacks nonblocking so the EventLoop worker can continue processing synchronous `EventLoop.sends` commands and shutdown. Parsing, task enqueueing, task wake notification, and status forwarding remain on the worker socket-loop thread. Start the loop with `withEventLoopIn` using the active `LotosApp` ZMQ context, matching the TP-034 ownership pattern. The socket loop preserves poll-on-either-socket behavior by draining both STM queues nonblocking each iteration, then waiting only in short bounded slices (minimum of remaining heartbeat timeout and a small status-drain slice) so internal task-status traffic is not gated behind backend-task waits. EventLoop callbacks are intentionally lightweight frame handoffs; queue drain preserves enqueue-then-wake ordering and keeps heavy parsing/status forwarding off the EventLoop worker. Any backend EventLoop `send` failure stops the socket-loop with a logged error rather than continuing to accept PAIR status frames that would be silently lost after the backend transport is gone.

**Plan review R001 revisions:**
- [x] Prevent task-status traffic from being gated by backend-task mailbox waits; drain both mailboxes promptly and use a bounded wait slice.
- [x] Define stopped-loop policy so backend EventLoop failure stops the worker socket-loop instead of silently losing statuses sent to the local PAIR.

**Plan review R002 revisions:**
- [x] Avoid silent EventLoop mailbox overflow for backend task and internal task-status frames by using callback-to-STM queues instead of `Mailbox` delivery.

**Plan review R003 revisions:**
- [x] Keep EventLoop callbacks nonblocking by using unbounded `TQueue` handoff rather than blocking `TBQueue` writes, avoiding send/shutdown deadlocks.

**Suggestions logged:** Consider bounded/observable overload metrics in a follow-up if production task/status bursts require memory caps; use `withEventLoopIn` with the `LotosApp` ZMQ context.

---

### Step 2: Implement EventLoop-backed worker backend loop
**Status:** ✅ Complete

- [x] Register worker backend DEALER as a transceiver and internal PAIR as receiver/transceiver as needed.
- [x] Forward task-status frames from internal callbacks/API to backend DEALER through EventLoop commands.
- [x] Receive task frames via mailbox, enqueue to the worker task queue, and notify the wake signal in the same ordering as before.
- [x] Preserve periodic worker status reporting cadence.
- [x] Fix R007 fairness regression so backend task drains cannot starve internal task-status forwarding or heartbeat trigger checks.

---

### Step 3: Protect ordering and lifecycle behavior
**Status:** ✅ Complete

- [x] Add or update tests for task receive ordering, task-status frame forwarding, heartbeat send behavior, and wake-on-enqueue after EventLoop migration.
- [x] Ensure logging EventLoop remains independent from backend EventLoop so logging backpressure cannot block task/status traffic.
- [x] Handle stopped-loop errors without silent task loss.
- [x] R010: Add worker backend drain/handle coverage that exercises actual enqueue order and wake-on-enqueue behavior.
- [x] R010: Add migrated LBW forwarding/heartbeat/stopped-loop coverage that drives backend send paths and drain fairness instead of only raw EventLoop callbacks.
- [x] R011: Route `LBW.handleWorkerBackendFrames` task enqueue/wake through the shared tested helper so the test covers production behavior.
- [x] R011: Move backend endpoint/send helpers into shared worker runtime coverage and update tests to use the real backend endpoint path.

**Step 3 test/lifecycle plan:** Add testable worker-runtime helpers for bounded/fair backend drain ordering and no-drop enqueue/wake behavior, then cover them from the existing worker wake/frame suites without starting long-running demo services. Keep the backend EventLoop in `LBW` separate from `LBW.LogTransport` by retaining distinct endpoint names, loops, queues, and threads. Treat `EventLoop.sends` failures through `zmqUnwrap` as visible socket-loop termination/logging instead of swallowing stopped-loop errors.

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Test-review checkpoint — review worker task/status traffic correctness and lifecycle coverage.
- [x] Run `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-wake lotos:test:test-zmq-worker-log-transport`.
- [x] Run relevant TaskSchedule worker lifecycle/scheduler tests.
- [x] Run `cabal build all --enable-tests`.
- [x] Run `scripts/task-schedule-smoke.sh` and `scripts/task-schedule-multi-worker-smoke.sh`.

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `taskplane-tasks/CONTEXT.md` with worker backend EventLoop migration status and remaining risks.
- [x] Update source comments to describe EventLoop ownership boundaries.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|

---

## Notes / Discoveries

- Preflight verified required task/source/test/script paths exist; TP-034 dependency is merged/done; cabal-install 3.16.1.0 and GHC 9.14.1 are available.
- Git status before implementation only showed STATUS.md progress edits; final delivery must squash TP work to one commit on top of the orchestrator task-file staging commit.
- Step 2 implementation built with `cabal build lotos` after migrating LBW backend socket ownership to EventLoop callbacks plus socket-loop STM drains; R007 fairness fix rebuilt with `cabal build lotos` after bounding/alternating drains.
- Step 3 regression coverage added in `test-zmq-worker-frames` for EventLoop task receive order, heartbeat sends, task-status PAIR forwarding, and stopped-loop send errors; `test-zmq-worker-wake` revalidated wake-on-enqueue behavior.
- Backend task/status EventLoop independence from worker LogIngest EventLoop is now documented at the launch boundary; `cabal build lotos` passed after the LBW lifecycle edits.
- Stopped backend EventLoop sends now log operation-specific errors before `zmqUnwrap` terminates the socket-loop; `cabal test lotos:test:test-zmq-worker-frames --test-show-details=direct` passed (16 cases).
- R010 suggestion: keep lightweight inproc EventLoop protocol smoke tests, but add tests that fail on backend/status drain starvation or swallowed stopped-loop sends.
- R010 worker backend drain/enqueue coverage added through shared `WorkerRuntime` helpers used by `LBW.socketLoop`; `test-zmq-worker-frames` passed with 18 cases.
- R010 status/heartbeat/stopped-loop coverage now calls the shared backend send helper and verifies alternating status/backend drain order in `test-zmq-worker-frames`.
- R011 issues: enqueue/wake helper was not yet used by `LBW`, and heartbeat/status tests still used a test endpoint instead of shared real backend endpoint helpers.
- R011 enqueue/wake fix: `LBW.handleWorkerBackendFrames` now routes backend tasks through the shared `enqueueBackendTaskAndNotify` helper covered by `test-zmq-worker-frames`.
- R011 endpoint/send fix: production backend endpoint names and DEALER send helper now live in `WorkerRuntime`; frame/status/stopped-loop tests use the real endpoint helper. Targeted frame and wake suites passed.
- Step 4 worker transport suites passed: `test-zmq-worker-frames` (18), `test-zmq-worker-wake` (2), and `test-zmq-worker-log-transport` (6).
- TaskSchedule targeted tests passed: `test-worker-lifecycle` (4) and `test-scheduler` (4).
- Full build gate passed: `cabal build all --enable-tests`.
- Smoke gates passed: `scripts/task-schedule-smoke.sh` (run `task-schedule-smoke-20260603T110753Z-3276552`) and `scripts/task-schedule-multi-worker-smoke.sh` (run `task-schedule-multi-worker-smoke-20260603T110842Z-3276551`).
- Documentation updated in `taskplane-tasks/CONTEXT.md` for TP-035 migration status, logging independence, verification evidence, and unbounded queue overload risk.
- Source comments now call out the worker backend EventLoop endpoint ownership boundary and separation from worker LogIngest EventLoop backpressure.
- Final delivery squashes TP-035 work into one Lore-format commit on top of the orchestrator staging commit.

| 2026-06-03 10:14 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 10:14 | Step 0 started | Preflight |
| 2026-06-03 10:19 | Review R001 | plan Step 1: REVISE |
| 2026-06-03 10:21 | Review R002 | plan Step 1: REVISE |
| 2026-06-03 10:24 | Review R003 | plan Step 1: REVISE |
| 2026-06-03 10:27 | Review R004 | plan Step 1: APPROVE |
| 2026-06-03 10:28 | Review R005 | code Step 1: APPROVE |
| 2026-06-03 10:30 | Review R006 | plan Step 2: APPROVE |
| 2026-06-03 10:36 | Review R007 | code Step 2: REVISE |
| 2026-06-03 10:39 | Review R008 | code Step 2: APPROVE |
| 2026-06-03 10:42 | Review R009 | plan Step 3: APPROVE |
| 2026-06-03 11:03 | Review R010 | code Step 3: REVISE |
| 2026-06-03 11:14 | Review R011 | code Step 3: REVISE |
| 2026-06-03 11:24 | Review R012 | code Step 3: APPROVE |
| 2026-06-03 11:25 | Review R013 | plan Step 4: APPROVE |
| 2026-06-03 11:43 | Review R014 | code Step 4: APPROVE |

| 2026-06-03 10:47 | Worker iter 1 | done in 1965s, tools: 129 |
| 2026-06-03 10:52 | Review R010 | code Step 3: REVISE |
| 2026-06-03 10:59 | Review R011 | code Step 3: REVISE |
| 2026-06-03 11:04 | Review R012 | code Step 3: APPROVE |
| 2026-06-03 11:05 | Review R013 | plan Step 4: APPROVE |
| 2026-06-03 11:13 | Review R014 | code Step 4: APPROVE |

| 2026-06-03 11:16 | Worker iter 2 | done in 1784s, tools: 113 |
| 2026-06-03 11:16 | Task complete | .DONE created |