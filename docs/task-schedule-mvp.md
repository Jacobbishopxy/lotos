# TaskSchedule MVP Runtime Contract

This document is the product-facing runtime contract for the `applications/TaskSchedule` demo. Downstream tasks should treat it as the source of truth for CLI shape, default addresses, task JSON, observability, and end-to-end acceptance.

TP-002 defined the contract, TP-003 implemented client submission, and TP-004 aligned the server/worker/client runtime config defaults plus sample JSON config files.

## MVP scope

The MVP is a single-machine demo with one broker, one or more workers, and a one-shot client that submits a shell-command task. It proves the framework can accept a task, schedule it to a worker, execute the command, and expose enough state to verify the run.

For reusable-library guidance, keep this document focused on the checked-in demo contract and use the README plus [`docs/build-your-own-scheduler.md`](build-your-own-scheduler.md) for the adoption checklist and API extension points. The concrete demo implementations are still the best examples: `applications/TaskSchedule/src/Server.hs` shows `LoadBalancerAlgo`, `applications/TaskSchedule/src/Worker.hs` shows `TaskAcceptor`/`StatusReporter`, and `applications/TaskSchedule/src/Adt.hs` shows task/status payload serialization.

## Command UX

All commands must create/use `./logs/` for their local log file and should fail fast with a clear usage message on invalid arguments.

### Server

```bash
mkdir -p logs
cabal run TaskSchedule:exe:ts-server -- [BROKER_CONFIG_JSON]
```

- `BROKER_CONFIG_JSON` is optional.
- With no argument, the server uses the built-in MVP defaults below.
- With one argument, it reads `BrokerServiceConfig` JSON using the existing `readBrokerConfig` shape.
- The checked-in sample config is `applications/TaskSchedule/config/broker.json`.

Server defaults:

| Field | Default |
|---|---:|
| `socketLayer.frontendAddr` | `tcp://127.0.0.1:5555` |
| `socketLayer.backendAddr` | `tcp://127.0.0.1:5556` |
| `infoStorage.httpPort` | `8081` |
| `infoStorage.logIngestDefaultAddr` | `tcp://127.0.0.1:5557` (default derivation only; legacy `infoStorage.loggingAddr` accepted) |
| `logIngest.logIngestAddr` | `tcp://127.0.0.1:5558` |
| `logIngest.logIngestWorkerQueueHWM` | `10000` |
| `logIngest.logIngestReadCacheSize` | `1000` |
| `logIngest.logIngestReadCacheMaxTasks` | `1000` |
| `taskScheduler.taskQueueHWM` | `1000` |
| `taskScheduler.failedTaskQueueHWM` | `1000` |
| `taskScheduler.garbageBinSize` | `100` |
| `taskProcessor.taskQueuePullNo` | `10` |
| `taskProcessor.failedTaskQueuePullNo` | `10` |
| `taskProcessor.triggerAlgoMaxNotifyCount` | `10` |
| `taskProcessor.triggerAlgoMaxWaitSec` | `10` |
| `taskProcessor.workerStaleTimeoutSec` | `60` |
| `infoStorage.logIngestDefaultBufferSize` | `1000` (compatibility value; legacy `infoStorage.loggingsBufferSize` accepted) |
| `infoStorage.infoFetchIntervalSec` | `10` |
| Log file | `./logs/taskScheduleServer.log` |

### Worker

```bash
mkdir -p logs
cabal run TaskSchedule:exe:ts-worker -- [WORKER_CONFIG_JSON]
```

- `WORKER_CONFIG_JSON` is optional.
- With no argument, the worker uses the built-in MVP defaults below.
- With one argument, it reads `WorkerServiceConfig` JSON using the existing `readWorkerConfig` shape.
- The checked-in sample config is `applications/TaskSchedule/config/worker.json`.

Worker defaults:

| Field | Default |
|---|---:|
| `workerId` | `simpleWorker_1` |
| `workerDealerPairAddr` | `inproc://TaskScheduleWorker` |
| `loadBalancerBackendAddr` | `tcp://127.0.0.1:5556` |
| `workerLogging.logIngestAddr` | `tcp://127.0.0.1:5558` |
| `logIngestDefaultAddr` | optional derivation hint; legacy `loadBalancerLoggingAddr` accepted |
| `workerLogging.logIngestWorkerQueueHWM` | `10000` |
| `workerStatusReportIntervalSec` | `5` |
| `parallelTasksNo` | `4` |
| Log file | `./logs/taskScheduleWorker.log` |

`loadBalancerBackendAddr` is the task/status backend and must match the server backend (`5556`). TP-004 corrected the prior demo mismatch that pointed the worker backend at `5555`. The broker treats worker status reports as liveness heartbeats; keep `taskProcessor.workerStaleTimeoutSec` comfortably above `workerStatusReportIntervalSec` so healthy workers are not recovered prematurely.

Once the broker assigns a task to a worker, the worker executor wakes immediately from a bounded STM enqueue signal instead of waiting for the former fixed 10-second empty-queue sleep. Scheduler batching before assignment is still controlled by the broker `taskProcessor` trigger knobs above; the wake signal only removes worker-local dispatch latency after the task has reached the worker process.

New configs should set the reliable `workerLogging.logIngestAddr` / broker `logIngest.logIngestAddr` endpoint explicitly (`5558` in the checked-in demo). `infoStorage.logIngestDefaultAddr` is only a broker default-derivation hint (`5557` in the checked-in demo), and old `infoStorage.loggingAddr`, `infoStorage.loggingsBufferSize`, and `loadBalancerLoggingAddr` JSON remain accepted for migration. Each worker opens a dedicated logging DEALER with `workerId` as its routing id, sends bounded `LogBatch`es, and retries until the broker LogIngest ROUTER returns `LogAck`s. Files written before the LogIngest migration may omit `logIngest`/`workerLogging`, in which case defaults derive a split reliable endpoint from the legacy logging endpoint.

TaskSchedule's `SimpleServer` now reports configured worker capacity through `WorkerState.taskCapacity` and device CPU usage through `WorkerState.cpuUsagePercent`. In each scheduler pass it subtracts reported `processingTaskNum` and `waitingTaskNum` from that capacity, sorts workers by combined CPU-percent/memory load, assigns fresh tasks across remaining slots in stable rounds, and returns any overflow to the broker queue for a later pass. The broker also overlays dispatch reservations onto `waitingTaskNum` between heartbeats, so back-to-back scheduler passes cannot over-assign a worker while its status payload is still catching up. Older eight- or nine-frame worker-status payloads still decode conservatively; this is the append-only compatibility example documented in `docs/book/lotos/src/protocol-compatibility.md`.

### Client

```bash
cabal run TaskSchedule:exe:ts-client -- TASK_JSON
cabal run TaskSchedule:exe:ts-client -- CLIENT_CONFIG_JSON TASK_JSON
```

- `TASK_JSON` is required.
- With one argument, the client uses the built-in MVP client config.
- With two arguments, it reads `ClientServiceConfig` JSON from the first path and the task from the second path.
- The checked-in sample config is `applications/TaskSchedule/config/client.json`.

Client defaults:

| Field | Default |
|---|---:|
| `clientId` | `simpleClient_1` |
| `loadBalancerFrontendAddr` | `tcp://127.0.0.1:5555` |
| `reqTimeoutSec` | `5` |
| Log file | `./logs/taskScheduleClient.log` |

ACK semantics:

- A client ACK means **accepted/enqueued by the broker**, not completed by a worker.
- The client exits `0` after receiving an ACK and prints the ACK timestamp.
- If parsing fails, arguments are invalid, or no ACK arrives within `reqTimeoutSec`, the client exits non-zero and prints a clear error.
- The server frontend sends the ACK only after it successfully decodes the client request, assigns/fills the task UUID, and enqueues the task.

## JSON config shapes

The MVP config files use existing record field names. The checked-in samples under `applications/TaskSchedule/config/` mirror the built-in defaults and were verified with the exported `readBrokerConfig`, `readWorkerConfig`, and `readClientConfig` readers.

### Server config example

```json
{
  "taskScheduler": {
    "taskQueueHWM": 1000,
    "failedTaskQueueHWM": 1000,
    "garbageBinSize": 100
  },
  "socketLayer": {
    "frontendAddr": "tcp://127.0.0.1:5555",
    "backendAddr": "tcp://127.0.0.1:5556"
  },
  "taskProcessor": {
    "taskQueuePullNo": 10,
    "failedTaskQueuePullNo": 10,
    "triggerAlgoMaxNotifyCount": 10,
    "triggerAlgoMaxWaitSec": 10,
    "workerStaleTimeoutSec": 60
  },
  "infoStorage": {
    "httpPort": 8081,
    "logIngestDefaultAddr": "tcp://127.0.0.1:5557",
    "logIngestDefaultBufferSize": 1000,
    "infoFetchIntervalSec": 10
  },
  "logIngest": {
    "logIngestAddr": "tcp://127.0.0.1:5558",
    "logIngestSocketHWM": 1000,
    "logIngestBatchMaxRecords": 100,
    "logIngestBatchMaxBytes": 1048576,
    "logIngestLineMaxBytes": 65536,
    "logIngestWorkerQueueHWM": 10000,
    "logIngestFlushIntervalMicros": 100000,
    "logIngestAckTimeoutMicros": 1000000,
    "logIngestRetryBackoffMicros": 250000,
    "logIngestReadCacheSize": 1000,
    "logIngestReadCacheMaxTasks": 1000,
    "logIngestJournalPath": "logs/worker-logs.journal",
    "logIngestRetentionBytes": 104857600,
    "logIngestDropPolicy": "drop-oldest"
  }
}
```

### Worker config example

```json
{
  "workerId": "simpleWorker_1",
  "workerDealerPairAddr": "inproc://TaskScheduleWorker",
  "loadBalancerBackendAddr": "tcp://127.0.0.1:5556",
  "workerStatusReportIntervalSec": 5,
  "parallelTasksNo": 4,
  "workerLogging": {
    "logIngestAddr": "tcp://127.0.0.1:5558",
    "logIngestSocketHWM": 1000,
    "logIngestBatchMaxRecords": 100,
    "logIngestBatchMaxBytes": 1048576,
    "logIngestLineMaxBytes": 65536,
    "logIngestWorkerQueueHWM": 10000,
    "logIngestFlushIntervalMicros": 100000,
    "logIngestAckTimeoutMicros": 1000000,
    "logIngestRetryBackoffMicros": 250000,
    "logIngestReadCacheSize": 1000,
    "logIngestReadCacheMaxTasks": 1000,
    "logIngestJournalPath": "logs/worker-logs.journal",
    "logIngestRetentionBytes": 104857600,
    "logIngestDropPolicy": "drop-oldest"
  }
}
```

### Client config example

```json
{
  "clientId": "simpleClient_1",
  "loadBalancerFrontendAddr": "tcp://127.0.0.1:5555",
  "reqTimeoutSec": 5
}
```

## Task JSON contract

The client submits a `Task ClientTask` JSON object. The server owns UUID assignment, so MVP task files set `taskID` to `null`.

Required fields:

| Field | Meaning |
|---|---|
| `taskID` | `null`; server assigns the UUID before scheduling. |
| `taskContent` | Human-readable label/description for the task. |
| `taskRetry` | Remaining retry count after worker failure. Use `0` for the happy-path demo. |
| `taskRetryInterval` | Retry delay in seconds after worker failure when `taskRetry > 0`; `0` or less preserves immediate retry. Use `0` for the happy-path demo. |
| `taskTimeout` | Authoritative execution timeout in seconds. `0` means no timeout. |
| `taskProp.command` | Shell command executed by the worker. |
| `taskProp.executeTimeoutSec` | Required by the current `ClientTask` schema and must equal `taskTimeout`; it is not separately authoritative. |

Failure and retry semantics:

- Worker execution reports `TaskProcessing` when a command starts and `TaskSucceed` or `TaskFailed` when it finishes.
- `ExitSuccess` maps to `TaskSucceed`; any non-zero exit, including timeout termination (`ExitFailure 124`), maps to `TaskFailed`.
- On `TaskFailed`, the broker removes the task from the worker task map. If `taskRetry > 0`, it decrements `taskRetry` and requeues the task on the failed-task queue; if `taskRetry == 0`, it writes the task to `/SimpleServer/garbage`.
- Worker status reports are broker liveness heartbeats. When a worker has not reported within `taskProcessor.workerStaleTimeoutSec`, the task processor removes that worker from liveness, status, and task maps before the next scheduling snapshot. Tasks left in `TaskInit`, `TaskPending`, `TaskProcessing`, `TaskRetrying`, or `TaskFailed` are recovered as failures through the same retry/garbage path; `TaskSucceed` entries are dropped with the stale worker instead of re-executed.
- Requeued failures with `taskRetryInterval > 0` are not passed back to the scheduler until the interval has elapsed from broker failure handling. `taskRetryInterval <= 0` keeps the historical immediate retry behavior. The delay metadata is broker-local and does not change the task JSON or ZMQ frame shape.

Checked-in sample task (`applications/TaskSchedule/config/task-demo.json`):

```json
{
  "taskID": null,
  "taskContent": "write a TaskSchedule MVP marker file",
  "taskRetry": 0,
  "taskRetryInterval": 0,
  "taskTimeout": 5,
  "taskProp": {
    "command": "mkdir -p .tmp && printf 'task-schedule-ok\\n' > .tmp/task-schedule-demo.out",
    "executeTimeoutSec": 5
  }
}
```

## Info API checks

With default config, the server exposes these endpoints:

- `http://127.0.0.1:8081/SimpleServer/info`
- `http://127.0.0.1:8081/SimpleServer/tasks`
- `http://127.0.0.1:8081/SimpleServer/garbage`
- `http://127.0.0.1:8081/SimpleServer/worker_tasks`
- `http://127.0.0.1:8081/SimpleServer/worker_stats`
- `http://127.0.0.1:8081/SimpleServer/logs/recent`
- `http://127.0.0.1:8081/SimpleServer/logs/worker/<workerId>`
- `http://127.0.0.1:8081/SimpleServer/logs/task/<taskUuid>`
- `http://127.0.0.1:8081/SimpleServer/logs/stats`

Expected MVP observations:

1. Server liveness: `/SimpleServer/info` returns a JSON object with queue, worker, and garbage fields. It is a lightweight scheduler snapshot and intentionally does not embed worker log payloads.
2. Worker registration: `/SimpleServer/worker_stats` returns `type: "WorkerStat"` and a `stats` object containing `simpleWorker_1` after one status interval. If that worker stops heartbeating past `workerStaleTimeoutSec`, subsequent snapshots remove it and any non-succeeded tasks are retried or garbage-collected according to the task retry fields.
3. Task acceptance/assignment: after the client receives an ACK, `/SimpleServer/worker_tasks` or `/SimpleServer/info.workerTasksMap` contains the submitted task under a worker ID, or `/SimpleServer/tasks` briefly shows it queued before assignment.
4. Successful execution: `.tmp/task-schedule-demo.out` exists and contains `task-schedule-ok`.
5. Failure absence for the happy path: `/SimpleServer/garbage` does not contain the demo task.
6. Worker logging: `/SimpleServer/logs/worker/simpleWorker_1` contains stdout/stderr `LogEvent`s and a final `LogResult` event whose message includes `ExitSuccess`; `/SimpleServer/logs/stats` shows zero `droppedEvents`, `rejectedEvents`, and `sequenceGaps` for the happy path.

ACK alone is not proof of completion; it only proves broker acceptance. Log delivery is at-least-once: workers retry unacked batches, LogIngest deduplicates accepted worker sequence coverage, and exactly-once delivery is not claimed. For operator triage of stuck workers, stale heartbeats, LogIngest backlog, broker overload, capacity reservations, and smoke failures, see the mdBook [Runtime Failure Runbook](book/lotos/src/runtime-failures.md).

## End-to-end acceptance script

Run the repeatable smoke helpers from the repository root after compiling the workspace and all test targets:

```bash
cabal build all --enable-tests
scripts/task-schedule-smoke.sh
scripts/task-schedule-multi-worker-smoke.sh
```

For the normal regression gate, `cabal test all` is safe: the `lotos` package registers only bounded, assertion-based regression suites as Cabal tests, and TaskSchedule's worker lifecycle test is also bounded. Long-running or no-assertion examples live under `lotos:exe:demo-*` and should be run intentionally, usually with `timeout` for server demos.

The single-worker helper generates a per-run broker config under `.tmp/task-schedule-smoke/<run-id>/` by default so LogIngest reads a run-local journal instead of stale shared smoke evidence; set `SMOKE_BROKER_CONFIG` to exercise a caller-provided broker config. It starts `ts-server` with that broker config plus one `ts-worker`/`ts-client` using the checked-in sample configs, waits for `/SimpleServer/info` and `/SimpleServer/worker_stats`, submits a fresh per-run task with `ts-client`, snapshots scheduler and `/logs` endpoints, checks a per-run marker written by the worker command, polls `/SimpleServer/logs/worker/simpleWorker_1` for the current run id and final `ExitSuccess` result event, verifies clean `/SimpleServer/logs/stats`, and preserves logs plus `result.env` under the evidence directory. It bypasses local proxy settings for loopback `curl` probes and cleans up only the process IDs/process groups it started.

The multi-worker helper generates per-run broker, worker, client, and task JSON files under `.tmp/task-schedule-multi-worker-smoke/<run-id>/`. By default it starts one server, two workers (`smokeWorker_1` and `smokeWorker_2`), and four distinct clients/tasks. It verifies both workers in `/SimpleServer/worker_stats`, all client ACKs, current-run task evidence in every worker-specific stdio log, fresh per-task marker files, current-run stdout plus `ExitSuccess` result events in `/SimpleServer/logs/worker/<workerId>` for every worker, clean `/SimpleServer/logs/stats`, and absence from `/SimpleServer/garbage`, then cleans up its tracked process groups. Exact burst distribution is protected by the bounded `TaskSchedule:test:test-scheduler` suite rather than by timing-sensitive smoke assertions.

Exit codes:

- `0`: full smoke pass; expected worker stats are visible, clients received ACKs, marker/logging proof exists, and the current run is absent from garbage.
- `1`: hard runtime failure, including readiness, ACK, marker, per-worker evidence, worker-logging, garbage-check, or cleanup-safety failures; inspect the run evidence directory.

Current TP-025 smoke evidence is a full MVP pass for both paths after the reliable logging cleanup: single-worker run `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T203413Z-1363172/` records `status=PASS`, and multi-worker run `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260601T203500Z-1380820/` records `status=PASS`, `worker_count=2`, `task_count=4`, per-worker current-run processing evidence, fresh markers, `/logs` worker/result evidence, and no current-run garbage.

Manual fallback, if the helper is unavailable, is the same sequence:

```bash
rm -f .tmp/task-schedule-demo.out
mkdir -p logs .tmp

# Terminal 1
cabal run TaskSchedule:exe:ts-server -- applications/TaskSchedule/config/broker.json

# Terminal 2
cabal run TaskSchedule:exe:ts-worker -- applications/TaskSchedule/config/worker.json

# Terminal 3
cabal run TaskSchedule:exe:ts-client -- applications/TaskSchedule/config/client.json applications/TaskSchedule/config/task-demo.json
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/worker_stats
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/worker_tasks
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/garbage
cat .tmp/task-schedule-demo.out
```

Pass criteria:

- Server and worker stay running without uncaught exceptions.
- Client prints an accepted/enqueued ACK and exits `0`.
- Worker stats include `simpleWorker_1` for the single-worker helper, or every generated `smokeWorker_N` for the multi-worker helper.
- The demo task is visible in queue/worker state during or after scheduling.
- The worker marker file contains the current run ID (or `.tmp/task-schedule-demo.out` contains exactly `task-schedule-ok` for the manual fallback); the multi-worker helper requires every generated task marker to match the current run.
- `/SimpleServer/logs/worker/<workerId>` contains the worker id plus stdout/stderr or `LogResult` entries for the task, and `/SimpleServer/logs/stats` exposes zero hidden loss (`droppedEvents`, `rejectedEvents`, and `sequenceGaps`) for the happy path.
- The happy-path task is not in garbage.

TP-009 verification status: `cabal build all --enable-tests` and `scripts/task-schedule-smoke.sh` passed. The smoke run `.tmp/task-schedule-smoke/tp009-final-20260601T043107Z-241489/` proves the client ACK path, worker stats, fresh marker proof, and no current-run garbage entry under the default sample configs. TP-010 keeps that smoke command intentional while making `cabal test all` a safe bounded regression gate.

## Implementation status by task

- **TP-002 (contract):** this MVP contract defines the canonical CLI, address, config, task JSON, and acceptance expectations.
- **TP-003 (client submission):** `ts-client` accepts `TASK_JSON` or `CLIENT_CONFIG_JSON TASK_JSON`, sends the task to frontend `5555`, exits non-zero on parse/argument/ACK timeout failures, and exits `0` after broker acceptance ACK.
- **TP-004 (runtime config alignment):** `ts-server`, `ts-worker`, and `ts-client` use the defaults above; server/worker accept zero or one config argument; worker backend/logging defaults are aligned to `5556`/`5557`; checked-in sample configs load through the exported config readers.
- **TP-005 (end-to-end smoke):** `scripts/task-schedule-smoke.sh` provides the repeatable local smoke path and captures per-run evidence.
- **TP-007 (worker status frame decoding):** worker DEALER sockets now use the configured worker ID as the ZeroMQ routing id, preserving the existing payload frame order while making backend `RouterBackendIn` decode worker status frames as UTF-8.
- **TP-008 (client ACK path):** frontend ROUTER decoding now preserves the REQ routing-id, binary request-id, and empty delimiter frames, enqueues the task, and echoes a `ClientAck` so `ts-client` receives an acceptance ACK and exits successfully.
- **TP-009 (green smoke):** the smoke helper now treats any missing ACK as a hard failure and the default sample-config run exits `0` with client ACK, worker stats, fresh marker proof, and no current-run garbage entry.
- **TP-010 (test-suite reclassification):** demo and server examples are Cabal `demo-*` executables instead of default test suites, leaving `cabal test all` for bounded assertion-based regressions.
- **TP-011 (protocol frame coverage):** worker task-status frames round-trip their payload order and decode through the backend ROUTER path, protecting failure/status reports from frame regressions.
- **TP-012 (worker lifecycle/failure semantics):** bounded tests cover retry decrement, garbage after retry exhaustion, command success/failure/timeout mapping, and worker `TaskProcessing` start reports; smoke run `.tmp/task-schedule-smoke/tp012-step3-20260601T071329Z-471004/` passed.
- **TP-013 (worker logging/info storage):** the original demo logging path used the configured `infoStorage.loggingAddr` (`5557`) and an info-snapshot log map; later logging redesign tasks moved smoke evidence to `/SimpleServer/logs/*`.
- **TP-015 (retry delay semantics):** `taskRetryInterval` is now enforced for retryable failures with broker-local readiness metadata; fixed-clock tests cover delayed, due, and immediate retry behavior, and smoke run `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T094502Z-746207/` passed.
- **TP-017 (multi-worker smoke):** `scripts/task-schedule-multi-worker-smoke.sh` proves bounded local scheduling with at least two distinct worker IDs, unique client IDs, multiple fresh tasks, per-worker current-run stdio evidence, marker/logging checks, endpoint snapshots, and tracked cleanup; run `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260601T110611Z-1239027/` passed with 2 workers and 4 tasks.
- **TP-019 (worker liveness recovery):** broker-side status heartbeats now remove stale workers from scheduling/info maps and recover their in-flight non-succeeded tasks through retry-delay or garbage semantics; bounded fixed-clock tests cover stale detection, retry readiness, exhausted garbage, and succeeded-task dropping, and smoke runs `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T140959Z-1455662/` plus `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260601T141128Z-1457758/` passed.
- **TP-020 (scheduler fairness/backpressure):** `SimpleServer` began assigning at most one fresh task to each idle worker per scheduler pass, deferring overflow and skipping workers that reported processing or waiting work. Later capacity-aware scheduling added `WorkerState.taskCapacity`, remaining-slot assignment, and backward-compatible status decoding while preserving the same deferred-overflow contract.
- **TP-044 (broker capacity reservations):** the broker now records per-worker occupied-slot reservations immediately after dispatch and overlays them onto TaskSchedule `WorkerState.waitingTaskNum` until terminal status, conservative reconciliation, or stale-worker recovery releases them. This prevents repeated scheduler wake-ups between heartbeats from exceeding reported worker capacity; verification covered the dedicated reservation suite, scheduler/frame/liveness tests, a full test-enabled build, and both smoke helpers.
- **TP-028 (worker wake-on-enqueue):** worker-side task execution now wakes from a coalescing STM signal when the socket loop enqueues broker-assigned work, eliminating the old fixed 10-second empty-queue sleep without changing worker task/status/log frames. `test-zmq-worker-wake` covers wake promptness, coalescing, and worker counter transitions; the smoke helpers passed after the multi-worker helper was isolated to a run-local LogIngest journal.
- **TP-031 (broker EventLoop decision):** broker `LBS.SocketLayer` stays on the direct ZMQ poll thread for frontend ROUTER, backend ROUTER, and TaskProcessor PAIR sockets. EventLoop migration was deferred because the current thread already owns those sockets and migration would introduce mailbox/drop semantics around ACKs, worker dispatch, retry/garbage handling, and scheduler notifications without measured benefit. The single-worker smoke now also defaults to a run-local LogIngest journal to avoid stale accepted sequence state across repeated verification runs.

## Non-goals and known risks

Non-goals for the MVP:

- No protocol/frame redesign beyond what is necessary for the CLI contract.
- No distributed deployment matrix; loopback defaults are the only required topology.
- No authentication, authorization, or TLS.
- No production scheduler policy beyond the TaskSchedule demo's capacity-aware load ordering.
- No new CLI parsing or configuration dependencies unless a downstream task explicitly approves them.
- No guarantee that client ACK means task completion.

Known risks/gaps for downstream work:

- The client ACK path depends on preserving ZeroMQ ROUTER/REQ frame ordering, including the binary REQ request-id frame; changing this shape can reintroduce ACK timeouts.
- Worker log transport is wired for the single-machine sample configs; custom topologies must keep broker `logIngest.logIngestAddr` and worker `workerLogging.logIngestAddr` aligned. Preferred new JSON uses `infoStorage.logIngestDefaultAddr` / `logIngestDefaultBufferSize` only as broker derivation hints; legacy `infoStorage.loggingAddr`, `infoStorage.loggingsBufferSize`, and `loadBalancerLoggingAddr` fields are retained for compatibility/default derivation, not active log ingestion.
- The info API currently exposes worker task membership but not a dedicated task-status history or failure-reason field; the file side effect is the required completion proof for the MVP happy path.
- `taskTimeout` and `taskProp.executeTimeoutSec` duplicate timeout data; the MVP resolves ambiguity by making `taskTimeout` authoritative and requiring equality.
- Positive `taskRetryInterval` values defer retry scheduling, but the retry is checked by the task processor's normal wake-up/trigger loop rather than an exact per-task timer; availability is therefore not-before the requested delay, not a precise dispatch deadline.
- Worker liveness is heartbeat based, not socket-presence based; set `taskProcessor.workerStaleTimeoutSec` higher than normal `workerStatusReportIntervalSec` plus expected scheduling/host jitter.
- `WorkerState.taskCapacity` is heartbeat-based, so capacity snapshots can still lag behind rapid assignment/execution changes between status reports. Applications with stricter admission-control needs should add stronger reservation/backpressure semantics around their scheduler decisions.
