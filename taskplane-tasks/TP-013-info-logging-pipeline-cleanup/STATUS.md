# TP-013: Info and Logging Pipeline Cleanup — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 5
**Iteration:** 2
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] TP-011 completed and current smoke is green

---

### Step 1: Decide logging product stance
**Status:** ✅ Complete

- [x] Current logging paths traced
- [x] Wire-vs-simplify decision made
- [x] Acceptance criteria defined

---

### Step 2: Implement cleanup
**Status:** ✅ Complete

- [x] Server/worker logging endpoint config and PUB/SUB frames are aligned to the documented `5557` path
- [x] Info storage retains and exposes worker log buffers in `/SimpleServer/info.workerLoggingsMap`
- [x] Smoke script emits a current-run log line and asserts it appears in `workerLoggingsMap`
- [x] Docs and sample config describe the wired logging behavior

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all --enable-tests` passes
- [x] `cabal test all` passes
- [x] `scripts/task-schedule-smoke.sh` passes
- [x] Logging behavior verified per selected stance

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] README/MVP docs updated
- [x] Context debt updated
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | plan | Step 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| R002 | plan | Step 2 | APPROVE | `.reviews/R002-plan-step2.md` |
| R003 | code | Step 2 | APPROVE | `.reviews/R003-code-step2.md` |
| R004 | plan | Step 3 | APPROVE | `.reviews/R004-plan-step3.md` |
| R005 | code | Step 3 | APPROVE | `.reviews/R005-code-step3.md` |

---

## Discoveries

| Date | Discovery | Action |
|---|---|---|
| 2026-06-01 | Server/worker logging is now a real demo contract, not a reserved placeholder; custom configs must keep `infoStorage.loggingAddr` and `loadBalancerLoggingAddr` aligned. | Documented in README/MVP docs and sample config; resolved debt recorded in `taskplane-tasks/CONTEXT.md`. |
| 2026-06-01 | Worker log visibility is snapshot-based: `/SimpleServer/info.workerLoggingsMap` reflects stdout/stderr and final `CommandResult` only after `infoFetchIntervalSec` refreshes. | Smoke script polls for current-run stdout plus `ExitSuccess`; docs call out the refresh timing. |

---

## Execution Log

| 2026-06-01 07:23 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 07:23 | Step 0 started | Preflight |
| 2026-06-01 07:24 | Step 0 paths | Required task/source/doc/config paths verified; created missing `.reviews/` directory |
| 2026-06-01 07:25 | Step 0 smoke | TP-011 is complete; `scripts/task-schedule-smoke.sh` passed with evidence `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T072436Z-483299/` |
| 2026-06-01 07:25 | Step 1 started | Decide logging product stance |
| 2026-06-01 07:31 | Step 1 path trace | Worker PUB uses `5557` but info storage SUB used inproc socket-layer address and expected an extra worker topic frame |
| 2026-06-01 07:32 | Step 1 stance | Chose to wire the documented `5557` worker logging endpoint and require smoke evidence in `workerLoggingsMap` |
| 2026-06-01 07:32 | Step 1 plan review | R001 APPROVE |
| 2026-06-01 07:32 | Step 2 started | Implement cleanup |
| 2026-06-01 07:38 | Step 2 plan review | R002 APPROVE |
| 2026-06-01 07:43 | Step 2 endpoint/frame wiring | Added `InfoStorageConfig.loggingAddr`, server/default broker `5557`, info-storage SUB bind, and worker-id PUB topic frames; `cabal build TaskSchedule:exe:ts-server TaskSchedule:exe:ts-worker` passed |
| 2026-06-01 07:44 | Step 2 log retention | Preserved `subscriberInfo` after info-storage snapshots so worker ring buffers remain exposed; `cabal build lotos` passed |
| 2026-06-01 07:46 | Step 2 smoke logging assertion | Smoke task now echoes the run id, polls `/info.workerLoggingsMap` for worker id/run id/`ExitSuccess`, and passed with evidence `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T074538Z-509471/` |
| 2026-06-01 07:50 | Step 2 docs/config | README and MVP docs now describe wired `5557` logging, required smoke evidence, and `infoStorage.loggingAddr`; sample broker config includes the endpoint |
| 2026-06-01 07:53 | Step 2 code review | R003 APPROVE |
| 2026-06-01 07:53 | Step 3 started | Testing & Verification |
| 2026-06-01 07:55 | Step 3 plan review | R004 APPROVE |
| 2026-06-01 07:58 | Step 3 build gate | `cabal build all --enable-tests` passed |
| 2026-06-01 08:02 | Step 3 full test gate | `cabal test all` passed (`test-conc-executor`, `test-zmq-worker-frames`, `test-zmq-client-ack-frames`, `test-worker-lifecycle`) |
| 2026-06-01 08:03 | Step 3 smoke gate | `scripts/task-schedule-smoke.sh` passed with evidence `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T075727Z-519892/` |
| 2026-06-01 08:04 | Step 3 logging evidence | `logging-info.json` and `final-info.json` contain `workerLoggingsMap.simpleWorker_1` with `STDOUT: task-schedule-smoke-20260601T075727Z-519892` and `CommandResult {cmdExitCode = ExitSuccess, ...}` |
| 2026-06-01 08:05 | Step 3 code review | R005 APPROVE |
| 2026-06-01 08:05 | Step 4 started | Documentation & Delivery |
| 2026-06-01 08:06 | Worker iter 1 | done in 2583s, tools: 122 |
| 2026-06-01 08:10 | Step 4 docs | README and MVP contract now point at the final TP-013 smoke evidence `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T075727Z-519892/` and describe verified `5557` worker logging in `/info.workerLoggingsMap` |
| 2026-06-01 08:11 | Step 4 context | `taskplane-tasks/CONTEXT.md` now records the TP-013 worker logging/info-storage debt as resolved with smoke-enforced evidence |
| 2026-06-01 08:12 | Step 4 discoveries | Logged delivery discoveries for aligned logging endpoints and info-storage refresh timing |
| 2026-06-01 08:13 | Step 4 complete | Documentation delivery verified with `git diff --check` and focused greps for final TP-013 logging evidence |
| 2026-06-01 08:11 | Worker iter 2 | done in 326s, tools: 25 |
| 2026-06-01 08:11 | Task complete | .DONE created |
---

## Blockers

---

## Notes

### Step 1 Logging Path Trace

- Worker TaskSchedule command output uses `TaskAcceptorAPI.taPubTaskLogging` in `applications/TaskSchedule/src/Worker.hs`; `mkWorkerService` currently sends `toZmq WorkerLogging` on a PUB socket connected to `WorkerServiceConfig.loadBalancerLoggingAddr` (`tcp://127.0.0.1:5557` in the sample/default worker config).
- `WorkerLogging` serializes as `[taskUuid, loggingText]`; no worker/topic frame is included by the datatype itself.
- Server info storage currently opens a SUB socket but connects it to `socketLayerSenderAddr` (`inproc://socketLayerSender`) instead of the worker logging endpoint. That inproc address is already bound by the socket-layer PAIR path, so it is not the documented external logging transport.
- `InfoStorage.infoLoop` expects incoming PUB/SUB frames shaped as `[workerTopic, taskUuid, loggingText]`, stores a per-worker ring buffer, and exposes it via `/SimpleServer/info.workerLoggingsMap`; however, with the current endpoint/frame mismatch the smoke evidence shows `workerLoggingsMap: {}`.

### Step 1 Product Stance

Decision: wire worker log collection end-to-end for the single-machine demo instead of de-scoping it. The code already emits command output through `taPubTaskLogging`, docs already reserve `tcp://127.0.0.1:5557`, and `InfoStorage` already has a `workerLoggingsMap`; the bounded cleanup is to make those existing pieces agree rather than leave a documented-but-dead path.

Planned implementation: add a server-side logging endpoint to `InfoStorageConfig`/broker config defaults, bind the info-storage SUB socket to that endpoint, send worker PUB messages with `workerId` as the first topic frame followed by the existing `WorkerLogging` frames, preserve accumulated subscriber ring buffers across info-storage refreshes, and update smoke/docs to require verified log collection for the demo.

Acceptance criteria:

1. Server and worker sample/default configs agree on `tcp://127.0.0.1:5557` as the worker logging endpoint.
2. Worker PUB frames include a worker-id topic plus the existing `WorkerLogging` payload so info storage can group logs by worker without changing the `WorkerLogging` payload contract.
3. `/SimpleServer/info.workerLoggingsMap.simpleWorker_1` contains command stdout and final command-result entries for a smoke task, and the smoke script fails if the current run's log line is missing.
4. README/MVP docs no longer describe worker logging as optional/reserved for the checked-in demo; any remaining caveats are framed as runtime timing/topology notes rather than unsupported behavior.
