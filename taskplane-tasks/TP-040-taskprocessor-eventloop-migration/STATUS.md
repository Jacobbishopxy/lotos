# TP-040: Migrate TaskProcessor internal transport to EventLoop — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 2
**Review Counter:** 4
**Iteration:** 2
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

### Step 1: Evaluate TaskProcessor EventLoop shape
**Status:** ✅ Complete

- [x] Plan-review checkpoint — decide whether TaskProcessor PAIR sockets should be sender/receiver/transceiver endpoints or whether SocketLayer migration already centralized ownership enough.
- [x] Map scheduler trigger timing and timeout behavior to EventLoop mailbox/timer logic.
- [x] Define success criteria and explicit no-op fallback if migration is not beneficial.

---

### Step 2: Implement migration or documented adaptation
**Status:** ✅ Complete

- [x] If migrating: register TaskProcessor PAIR sockets through EventLoop and use command/mailbox APIs for notify receive and worker-task sends.
- [x] If not migrating fully: adapt TaskProcessor to the new explicit context/socket ownership conventions and document the remaining direct path.
- [x] Preserve scheduler output ordering and retry-ready task dispatch behavior.

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review scheduler trigger, notify, and dispatch semantics.
- [x] Run scheduler/fairness/backpressure tests.
- [x] Run worker liveness/retry tests affected by dispatch timing.
- [x] Run `cabal build all --enable-tests` and smoke scripts if runtime dispatch changed.

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `taskplane-tasks/CONTEXT.md` with TaskProcessor EventLoop status.
- [x] Record any remaining direct socket ownership in STATUS.md.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|

---

## Notes / Discoveries

- Step 0 preflight verified the TP-040 prompt/status, area context, scoped source files, and TP-039 dependency status in the current worktree. Git status only shows TP-040 STATUS.md progress so far; final history must be squashed to one TP-040 commit.
- Step 1 evaluation: TP-039 already moved the SocketLayer-owned PAIR endpoints into the broker EventLoop, but `TaskProcessor` still opens its own PAIR sockets directly and blocks on `ZmqxM.receivesFor` before scheduling. A beneficial migration should make the TaskProcessor PAIR sockets EventLoop-owned in the TaskProcessor thread, using a mailbox `recv` timeout for notifications and `EventLoop.sends` for worker dispatches, while preserving the current trigger timeout and queue retry ordering.
- Scheduler trigger mapping: keep `mkCombinedTrigger`/`callTrigger` exactly as-is. Each processor loop iteration still calls `callTrigger` once, waits for one notification until `timeoutInterval newTrigger triggerNow` milliseconds via EventLoop mailbox `recv`, logs/decodes a received `Notify`, and only runs scheduling when `shouldProcess` from the pre-wait trigger call is true. No new EventLoop timer is needed because `recv` implements the same positive/zero/negative timeout behavior with a mailbox wait.
- Success criteria: `TaskProcessor` no longer sends/receives directly on its PAIR sockets while running; sockets are opened in the explicit `LotosApp` ZMQ context and registered under stable EventLoop endpoint names; notifications decode through EventLoop `recv`; worker dispatches use EventLoop `sends`; scheduler output ordering, left-task requeueing, retry readiness, and stale-worker recovery behavior stay unchanged. Fallback if migration proves harmful: retain direct `TaskProcessor` PAIR operations but document them as the only remaining direct TaskProcessor socket ownership path; current inspection suggests full migration is straightforward enough to implement.
- Step 2 adaptation status: full migration path implemented, so no TaskProcessor direct `ZmqxM.receivesFor`/`ZmqxM.sends` runtime path remains. The PAIR sockets are still opened with explicit type annotations in `LotosApp` only so they can be connected and registered into `withEventLoopIn` using the same `LotosEnv` ZMQ context.
- Step 2 ordering preservation: scheduler output still builds `workerTasks` from `tasksTodo` with the same list comprehension and sends it using `mapM_`; `EventLoop.sends` waits for each worker send reply, so dispatch remains sequential. Invalid new tasks and delayed/invalid retry tasks are re-enqueued after dispatch in the same order-preserving paths as before.
- Step 3 code review checkpoint: R003 approved the Step 2 EventLoop migration and explicitly reviewed trigger call/timeout placement, scheduler output ordering, retry re-enqueue paths, stale-worker recovery flow, and sequential EventLoop dispatch semantics.
- Step 3 scheduler/fairness/backpressure tests: `cabal test lotos:test:test-zmq-worker-frames --test-options='--select-tests "broker SocketLayer EventLoop preserves mixed protocol traffic" --select-tests "worker backend EventLoop receives task frames in order" --select-tests "retry task partition keeps delayed tasks out of scheduling batch"'` passed (21/21 cases; test runner executed the full suite despite select flags).
- Step 3 worker liveness/retry tests: `cabal test lotos:test:test-zmq-worker-wake lotos:test:test-zmq-worker-frames` passed (`test-zmq-worker-frames` 21/21; `test-zmq-worker-wake` 2/2), covering retry queues, stale-worker recovery, wake/liveness behavior, and dispatch frame timing.
- Step 3 full build/smoke verification: `cabal build all --enable-tests` passed. Runtime dispatch changed, so `scripts/task-schedule-smoke.sh` passed with evidence `.tmp/task-schedule-smoke/task-schedule-smoke-20260603T143529Z-3706071`, and `scripts/task-schedule-multi-worker-smoke.sh` passed with evidence `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260603T143621Z-3707929`.
- Step 4 remaining direct socket ownership: none remains in `LBS.TaskProcessor` while the processor is running. It opens/connects the two PAIR sockets in `LotosApp` only before registering them as EventLoop sender/receiver endpoints; notifications and worker dispatches then go through `EventLoop.recv`/`EventLoop.sends`.
- Step 4 final history: temporary step commits were squashed into one final TP-040 commit (`git rev-list --count f52c6c5..HEAD` = 1 before the final STATUS amend).

| 2026-06-03 14:18 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 14:18 | Step 0 started | Preflight |
| 2026-06-03 14:21 | Review R001 | plan Step 1: APPROVE |
| 2026-06-03 14:24 | Review R002 | plan Step 2: APPROVE |

| 2026-06-03 14:26 | Worker iter 1 | done in 480s, tools: 43 |
| 2026-06-03 14:32 | Review R003 | code Step 2: APPROVE |
| 2026-06-03 14:39 | Review R004 | code Step 3: APPROVE |

| 2026-06-03 14:42 | Worker iter 2 | done in 973s, tools: 81 |
| 2026-06-03 14:42 | Task complete | .DONE created |