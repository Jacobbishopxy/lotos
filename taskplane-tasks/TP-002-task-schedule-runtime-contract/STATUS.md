# TP-002: TaskSchedule Runtime Contract — Status

**Current Step:** Step 2: Documentation & handoff
**Status:** ✅ Complete
**Last Updated:** 2026-05-31
**Review Level:** 1
**Review Counter:** 2
**Iteration:** 1
**Size:** S

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied

---

### Step 1: Define the contract
**Status:** ✅ Complete

- [x] Current TaskSchedule entry points and config types inspected
- [x] MVP UX decisions documented
- [x] Non-goals and risks documented
- [x] R001 plan revision: worker logging/observability endpoint and acceptance check are explicit
- [x] R001 plan revision: authoritative timeout field, ACK semantics, and client timeout/exit behavior are explicit

---

### Step 2: Documentation & handoff
**Status:** ✅ Complete

- [x] README pointer added if useful
- [x] Downstream acceptance criteria are clear
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | plan | 1 | REVISE | `.reviews/R001-plan-step1.md` |
| R002 | plan | 1 | APPROVE | `.reviews/R002-plan-step1.md` |

---

## Discoveries

| 2026-05-31 15:22 | Step 1 inspection | `ts-server` hardcodes frontend `tcp://127.0.0.1:5555`, backend `tcp://127.0.0.1:5556`, info port `8081`; `ts-worker` currently points backend/logging at `5555`/`5556`, which appears inverted relative to the server; `ts-client` is a stub while `Client.getTaskFromFile` parses `Task ClientTask` JSON. |
| 2026-05-31 15:22 | Step 1 inspection | Existing config readers: `readBrokerConfig`, `readWorkerConfig`, `readClientConfig`; config records are FromJSON only and not used by current TaskSchedule entry points. |
| 2026-05-31 15:22 | Step 1 inspection | Info API endpoints are served under `/SimpleServer/{info,tasks,garbage,worker_tasks,worker_stats}` and expose worker state, queues, garbage bin, worker task map, and worker logs. |
| 2026-05-31 15:34 | Step 2 handoff | `docs/task-schedule-mvp.md` now records downstream implementation gaps: client stub, missing broker ACK reply, worker backend default mismatch, optional/reserved log transport, and timeout-field duplication. |

---

## Execution Log

| 2026-05-31 15:22 | Task started | Runtime V2 lane-runner execution |
| 2026-05-31 15:22 | Step 0 started | Preflight |
| 2026-05-31 15:22 | Step 0 complete | Preflight paths verified; cabal 3.14.2.0, GHC 9.14.1, git available; no external task dependencies |
| 2026-05-31 15:22 | Step 1 started | Define the contract |
| 2026-05-31 15:29 | R001 plan review | REVISE: clarify logging/observability, timeout semantics, ACK/client behavior, and include an example task JSON |
| 2026-05-31 15:33 | R002 plan review | APPROVE after R001 clarifications |
| 2026-05-31 15:33 | Step 1 complete | `docs/task-schedule-mvp.md` defines the MVP runtime contract, risks, and downstream acceptance |
| 2026-05-31 15:33 | Step 2 started | Documentation & handoff |
| 2026-05-31 15:34 | Step 2 complete | README pointer added, downstream acceptance criteria verified, discoveries logged |
| 2026-05-31 15:34 | Task complete | All TP-002 steps complete; documentation contract ready for downstream tasks |
| 2026-05-31 15:39 | Worker iter 1 | done in 990s, tools: 79 |
| 2026-05-31 15:39 | Task complete | .DONE created |
---

## Blockers

---

## Notes

### Step 1 plan-review proposal

- Contract artifact: create `docs/task-schedule-mvp.md` as the downstream source of truth; no Haskell implementation changes in TP-002.
- Server UX: `ts-server [broker-config.json]`, defaulting to built-in MVP values when omitted. MVP addresses: client frontend `tcp://127.0.0.1:5555`, worker backend `tcp://127.0.0.1:5556`, info HTTP `http://127.0.0.1:8081/SimpleServer/*`; create `logs/` before starting.
- Worker UX: `ts-worker [worker-config.json]`, defaulting to one local worker with id `simpleWorker_1`, `parallelTasksNo = 4`, status interval `5s`, task/status backend `tcp://127.0.0.1:5556`, and a reserved worker-log PUB endpoint `tcp://127.0.0.1:5557`. Current demo literals that point the worker task backend at `5555` are out of contract.
- Logging/observability decision: worker log collection is a known implementation risk and is not required for MVP pass/fail because the broker config currently lacks an external logging address and info storage subscribes to in-process `socketLayerSenderAddr`. If downstream work wires logs, it should use the reserved `5557` endpoint and surface entries in `/SimpleServer/info.workerLoggingsMap`; otherwise `workerLoggingsMap` may be empty.
- Client UX: `ts-client TASK_JSON` uses default client config, and `ts-client CLIENT_CONFIG_JSON TASK_JSON` overrides it. The task file is a `Task ClientTask` JSON object with `taskID: null`, task metadata fields, and `taskProp.command`/`taskProp.executeTimeoutSec`. Top-level `taskTimeout` is the authoritative execution timeout for MVP; `taskProp.executeTimeoutSec` must be present for schema compatibility and must match `taskTimeout`.
- ACK/client decision: client ACK means "accepted/enqueued by the broker", not task completion. The client exits 0 after ACK; if no ACK arrives within `ClientServiceConfig.reqTimeoutSec`, it exits non-zero and prints a timeout/no-ack error. Current server enqueue-without-reply behavior is a downstream implementation gap.
- Observability/verification: use info endpoints `/info`, `/tasks`, `/worker_tasks`, `/worker_stats`, `/garbage` plus a local file-producing demo command to prove server up, worker registered, task accepted/assigned, and command execution. Worker logs are optional evidence only.
- Non-goals: no protocol redesign, no distributed deployment matrix, no auth/TLS, no scheduler algorithm changes, no new dependency choices.
- R001 suggestion carried into the artifact: `docs/task-schedule-mvp.md` includes a task JSON example and exact info endpoints/fields that prove a file-producing task moved through the MVP path.
