# TaskSchedule MVP Runtime Contract

This document is the product-facing runtime contract for the `applications/TaskSchedule` demo. Downstream tasks should treat it as the source of truth for CLI shape, default addresses, task JSON, observability, and end-to-end acceptance.

TP-002 defined the contract, TP-003 implemented client submission, and TP-004 aligned the server/worker/client runtime config defaults plus sample JSON config files.

## MVP scope

The MVP is a single-machine demo with one broker, one or more workers, and a one-shot client that submits a shell-command task. It proves the framework can accept a task, schedule it to a worker, execute the command, and expose enough state to verify the run.

For reusable-library guidance, keep this document focused on the checked-in demo contract and use the README plus Haddocks for API extension points. The concrete demo implementations are still the best examples: `applications/TaskSchedule/src/Server.hs` shows `LoadBalancerAlgo`, `applications/TaskSchedule/src/Worker.hs` shows `TaskAcceptor`/`StatusReporter`, and `applications/TaskSchedule/src/Adt.hs` shows task/status payload serialization.

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
| `infoStorage.loggingAddr` | `tcp://127.0.0.1:5557` |
| `taskScheduler.taskQueueHWM` | `1000` |
| `taskScheduler.failedTaskQueueHWM` | `1000` |
| `taskScheduler.garbageBinSize` | `100` |
| `taskProcessor.taskQueuePullNo` | `10` |
| `taskProcessor.failedTaskQueuePullNo` | `10` |
| `taskProcessor.triggerAlgoMaxNotifyCount` | `10` |
| `taskProcessor.triggerAlgoMaxWaitSec` | `10` |
| `infoStorage.loggingsBufferSize` | `1000` |
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
| `loadBalancerLoggingAddr` | `tcp://127.0.0.1:5557` |
| `workerStatusReportIntervalSec` | `5` |
| `parallelTasksNo` | `4` |
| Log file | `./logs/taskScheduleWorker.log` |

`loadBalancerBackendAddr` is the task/status backend and must match the server backend (`5556`). TP-004 corrected the prior demo mismatch that pointed the worker backend at `5555`.

`loadBalancerLoggingAddr` is the worker PUB logging endpoint and must match the server `infoStorage.loggingAddr` (`5557` in the checked-in demo). The worker sends its `workerId` as the PUB/SUB topic and the existing `WorkerLogging` payload as `[taskUuid, logText]`; server info storage binds a SUB socket on this endpoint and exposes entries in `/SimpleServer/info.workerLoggingsMap` after the next `infoFetchIntervalSec` refresh. Broker JSON files written before TP-013 must add `infoStorage.loggingAddr` or they will not match the current `InfoStorageConfig` schema.

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
    "triggerAlgoMaxWaitSec": 10
  },
  "infoStorage": {
    "httpPort": 8081,
    "loggingAddr": "tcp://127.0.0.1:5557",
    "loggingsBufferSize": 1000,
    "infoFetchIntervalSec": 10
  }
}
```

### Worker config example

```json
{
  "workerId": "simpleWorker_1",
  "workerDealerPairAddr": "inproc://TaskScheduleWorker",
  "loadBalancerBackendAddr": "tcp://127.0.0.1:5556",
  "loadBalancerLoggingAddr": "tcp://127.0.0.1:5557",
  "workerStatusReportIntervalSec": 5,
  "parallelTasksNo": 4
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
| `taskRetryInterval` | Present for schema compatibility; no MVP behavior is guaranteed. Use `0`. |
| `taskTimeout` | Authoritative execution timeout in seconds. `0` means no timeout. |
| `taskProp.command` | Shell command executed by the worker. |
| `taskProp.executeTimeoutSec` | Required by the current `ClientTask` schema and must equal `taskTimeout`; it is not separately authoritative. |

Failure and retry semantics:

- Worker execution reports `TaskProcessing` when a command starts and `TaskSucceed` or `TaskFailed` when it finishes.
- `ExitSuccess` maps to `TaskSucceed`; any non-zero exit, including timeout termination (`ExitFailure 124`), maps to `TaskFailed`.
- On `TaskFailed`, the broker removes the task from the worker task map. If `taskRetry > 0`, it requeues the task on the failed-task queue with `taskRetry` decremented by one; if `taskRetry == 0`, it writes the task to `/SimpleServer/garbage`.
- `taskRetryInterval` remains schema-only in the MVP; retries are not delayed by that field.

Example task (`task-demo.json`):

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

Expected MVP observations:

1. Server liveness: `/SimpleServer/info` returns a JSON object with queue, worker, and garbage fields.
2. Worker registration: `/SimpleServer/worker_stats` returns `type: "WorkerStat"` and a `stats` object containing `simpleWorker_1` after one status interval.
3. Task acceptance/assignment: after the client receives an ACK, `/SimpleServer/worker_tasks` or `/SimpleServer/info.workerTasksMap` contains the submitted task under a worker ID, or `/SimpleServer/tasks` briefly shows it queued before assignment.
4. Successful execution: `.tmp/task-schedule-demo.out` exists and contains `task-schedule-ok`.
5. Failure absence for the happy path: `/SimpleServer/garbage` does not contain the demo task.
6. Worker logging: `/SimpleServer/info.workerLoggingsMap.simpleWorker_1` contains stdout/stderr lines and a final `CommandResult` entry for the task after the info-storage refresh interval. Empty worker log maps fail the checked-in smoke path.

ACK alone is not proof of completion; it only proves broker acceptance.

## End-to-end acceptance script

Run the repeatable smoke helper from the repository root after compiling the workspace and all test targets:

```bash
cabal build all --enable-tests
scripts/task-schedule-smoke.sh
```

For the normal regression gate, `cabal test all` is safe: the `lotos` package registers only bounded, assertion-based regression suites as Cabal tests, and TaskSchedule's worker lifecycle test is also bounded. Long-running or no-assertion examples live under `lotos:exe:demo-*` and should be run intentionally, usually with `timeout` for server demos.

The helper starts `ts-server` and `ts-worker` with the checked-in sample configs, waits for `/SimpleServer/info` and `/SimpleServer/worker_stats`, submits a fresh per-run task with `ts-client`, snapshots the info endpoints, checks a per-run marker written by the worker command, polls `/SimpleServer/info.workerLoggingsMap` for the current run id and final `ExitSuccess` command result, and preserves logs plus `result.env` under `.tmp/task-schedule-smoke/<run-id>/`. It bypasses local proxy settings for loopback `curl` probes and cleans up only the process IDs/process groups it started.

Exit codes:

- `0`: full MVP pass; client received ACK, worker stats are visible, the worker marker proof exists, worker logging reached `/info.workerLoggingsMap`, and the current run is absent from garbage.
- `1`: hard runtime failure, including readiness, ACK, marker, worker-logging, or garbage-check failures; inspect the run evidence directory.

Current TP-013 smoke evidence is a full MVP pass with wired worker logging: run `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T075727Z-519892/` records `status=PASS`, `client_exit=0`, `/SimpleServer/worker_stats` contained `simpleWorker_1`, the worker wrote the fresh marker file, `logging-info.json` and `final-info.json` contained both `STDOUT: task-schedule-smoke-20260601T075727Z-519892` and `ExitSuccess` under `workerLoggingsMap.simpleWorker_1`, and `final-garbage.json` did not contain the run id.

Manual fallback, if the helper is unavailable, is the same sequence:

```bash
rm -f .tmp/task-schedule-demo.out
mkdir -p logs .tmp

# Terminal 1
cabal run TaskSchedule:exe:ts-server -- applications/TaskSchedule/config/broker.json

# Terminal 2
cabal run TaskSchedule:exe:ts-worker -- applications/TaskSchedule/config/worker.json

# Terminal 3
cabal run TaskSchedule:exe:ts-client -- applications/TaskSchedule/config/client.json task-demo.json
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/worker_stats
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/worker_tasks
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/garbage
cat .tmp/task-schedule-demo.out
```

Pass criteria:

- Server and worker stay running without uncaught exceptions.
- Client prints an accepted/enqueued ACK and exits `0`.
- Worker stats include `simpleWorker_1`.
- The demo task is visible in queue/worker state during or after scheduling.
- The worker marker file contains the current run ID (or `.tmp/task-schedule-demo.out` contains exactly `task-schedule-ok` for the manual fallback).
- `/SimpleServer/info.workerLoggingsMap` contains the worker id plus stdout/stderr or `CommandResult` entries for the task after the info-storage refresh interval.
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
- **TP-013 (worker logging/info storage):** info storage binds the configured `infoStorage.loggingAddr` (`5557` in the demo), workers publish `workerId` topic frames plus `WorkerLogging` payloads, and the smoke helper now requires current-run stdout plus `ExitSuccess` evidence in `/SimpleServer/info.workerLoggingsMap`.

## Non-goals and known risks

Non-goals for the MVP:

- No protocol/frame redesign beyond what is necessary for the CLI contract.
- No distributed deployment matrix; loopback defaults are the only required topology.
- No authentication, authorization, or TLS.
- No scheduler algorithm changes.
- No new CLI parsing or configuration dependencies unless a downstream task explicitly approves them.
- No guarantee that client ACK means task completion.

Known risks/gaps for downstream work:

- The client ACK path depends on preserving ZeroMQ ROUTER/REQ frame ordering, including the binary REQ request-id frame; changing this shape can reintroduce ACK timeouts.
- Worker log transport is wired for the single-machine sample configs; custom topologies must keep server `infoStorage.loggingAddr` and worker `loadBalancerLoggingAddr` aligned, and HTTP snapshots reflect logs after `infoFetchIntervalSec` refreshes.
- The info API currently exposes worker task membership but not a dedicated task-status history or failure-reason field; the file side effect is the required completion proof for the MVP happy path.
- `taskTimeout` and `taskProp.executeTimeoutSec` duplicate timeout data; the MVP resolves ambiguity by making `taskTimeout` authoritative and requiring equality.
- `taskRetryInterval` is not enforced yet; retry attempts are requeued immediately when the failed-task queue is scheduled.
