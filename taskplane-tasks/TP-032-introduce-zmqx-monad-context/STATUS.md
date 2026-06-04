# TP-032: Introduce explicit ZMQ context in LotosApp — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 2
**Review Counter:** 8
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

### Step 1: Map current runner/context usage
**Status:** ✅ Complete

- [x] Plan-review checkpoint — inventory every `runZmqContextIO`, `runZmqContextWithThreadIO`, `Zmqx.run`, and direct socket-open call site.
- [x] Decide the public runner shape (`runZmqApp`/compatibility wrappers) and how to preserve existing app entry points during migration.
- [x] Identify any tests or demos that depend on nested/global `Zmqx.run` behavior.

---

### Step 2: Add explicit context to the app environment
**Status:** ✅ Complete

- [x] Introduce a `LotosEnv` (or equivalent) that carries `LoggerEnv` plus `Zmqx.Context` while preserving logger helpers.
- [x] Implement `MonadZmqx LotosApp` using the explicit context.
- [x] Update `forkApp` so forked app actions retain the same logger and ZMQ context safely.

---

### Step 3: Adapt runners without changing socket behavior
**Status:** ✅ Complete

- [x] Add explicit-context app runners using `Zmqx.Monad.runZmqx` or `Zmqx.withContext` plus `runZmqxT` as appropriate.
- [x] Keep compatibility wrappers for current executable/test call sites if needed.
- [x] Update TaskSchedule executable wrappers and test helpers to use the new runner surface.
- [x] Fix worker log EventLoop to use the app-owned explicit ZMQ context instead of the legacy global EventLoop runner.

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — verify context lifetime, forked action behavior, and compatibility surface.
- [x] Run `cabal build lotos`.
- [x] Run representative frame tests: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames`.
- [x] Run explicit-context log transport regression: `cabal test lotos:test:test-zmq-worker-log-transport`.
- [x] Run `cabal build all --enable-tests`.

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `taskplane-tasks/CONTEXT.md` with the monad-context migration status and any compatibility notes.
- [x] Record any remaining global-context call sites in STATUS.md.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R004 | code | 3 | REVISE | .reviews/R004-code-step3.md |
| R005 | code | 3 | APPROVE | .reviews/R005-code-step3.md |
| R006 | plan | 4 | REVISE | .reviews/R006-plan-step4.md |
| R007 | plan | 4 | APPROVE | .reviews/R007-plan-step4.md |
| R008 | code | 4 | APPROVE | .reviews/R008-code-step4.md |

---

## Notes / Discoveries

- Step 1 inventory (plan review R001 APPROVE):
  - Global runners: `Lotos.Zmq.Util.runZmqContextIO`/`runZmqContextWithThreadIO` are the only `Zmqx.run` wrappers; executable callers are `TaskScheduleServer`, `TaskScheduleWorker`, and `TaskScheduleClient`; test/demo callers are `ZmqXT`, `ZmqLogIngest`, `ZmqWorkerLogTransport`, `ZmqWorkerFrames`, and `ZmqClientAckFrames`.
  - Direct library socket opens: `Lotos.Zmq.LBC` REQ; `Lotos.Zmq.LBW` DEALER/PAIR; `Lotos.Zmq.LBW.LogTransport` DEALER; `Lotos.Zmq.LBS.SocketLayer` ROUTER/PAIR; `Lotos.Zmq.LBS.TaskProcessor` PAIR; `Lotos.Zmq.LBS.LogIngest` ROUTER.
  - Direct test/demo socket opens: `ZmqWorkerFrames`, `ZmqClientAckFrames`, `ZmqLogIngest`, `ZmqWorkerLogTransport`, and demo `ZmqXT`.
- Step 1 runner decision: add `LotosEnv` with `LoggerEnv` + `Zmqx.Context`, keep `runApp :: LoggerEnv -> LotosApp a -> IO a` as a compatibility wrapper that creates a default context, add `runZmqApp`/`runZmqAppWithThread` for app-level context ownership, and add context/env runners for internal reuse (`runAppWithContext`/captured-env runner) so `forkApp` and EventLoop callbacks retain the original context instead of creating nested contexts.
- Step 1 nested/global dependency check: app entry points `TaskScheduleServer`, `TaskScheduleWorker`, and `TaskScheduleClient` currently rely on `runZmqContextIO` surrounding `runApp`; tests `ZmqLogIngest` and `ZmqWorkerLogTransport` do the same for LotosApp services. Frame tests `ZmqWorkerFrames`/`ZmqClientAckFrames` and demo `ZmqXT` only need a raw ZMQ context for direct socket tests and can keep `runZmqContextIO`.
- Step 4 plan review R006: add `cabal test lotos:test:test-zmq-worker-log-transport` as mandatory evidence for the explicit-context EventLoop/logging regression; TaskSchedule executable build evidence is useful compatibility evidence.
- Step 4 verification evidence:
  - `cabal build lotos` → PASS (`Up to date`).
  - `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames` → PASS (worker frames 13 cases, client ACK frames 2 cases).
  - `cabal test lotos:test:test-zmq-worker-log-transport` → PASS (6 cases; covers explicit app context handoff into EventLoop).
  - `cabal build all --enable-tests` → PASS (workspace/test targets compiled).
- Remaining global-context call sites after TP-032: compatibility wrappers `runZmqContextIO`/`runZmqContextWithThreadIO` in `lotos/src/Lotos/Zmq/Util.hs` still wrap `Zmqx.run`; direct raw frame tests `lotos/test/ZmqWorkerFrames.hs` and `lotos/test/ZmqClientAckFrames.hs` still use `runZmqContextIO` by design. No TaskSchedule executable call sites and no `Zmqx.EventLoop.withEventLoop` library call sites remain.

| 2026-06-03 08:31 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 08:31 | Step 0 started | Preflight |
| 2026-06-03 08:36 | Review R001 | plan Step 1: APPROVE |
| 2026-06-03 08:44 | Review R002 | plan Step 2: APPROVE |
| 2026-06-03 08:48 | Review R003 | plan Step 3: APPROVE |

| 2026-06-03 08:56 | Worker iter 1 | done in 1462s, tools: 118 |
| 2026-06-03 09:04 | Review R004 | code Step 3: REVISE — worker LogTransport EventLoop still used global context; reviewer noted `cabal test lotos:test:test-zmq-worker-log-transport` exposes the delayed ACK failure. |
| 2026-06-03 09:08 | Review R005 | code Step 3: APPROVE |
| 2026-06-03 09:10 | Review R006 | plan Step 4: REVISE |
| 2026-06-03 09:11 | Review R007 | plan Step 4: APPROVE |
| 2026-06-03 09:15 | Review R008 | code Step 4: APPROVE |

| 2026-06-03 09:18 | Worker iter 2 | done in 1345s, tools: 121 |
| 2026-06-03 09:18 | Task complete | .DONE created |