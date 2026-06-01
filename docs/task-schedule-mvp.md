# TaskSchedule MVP Runtime Contract

This document is the product-facing runtime contract for the `applications/TaskSchedule` demo. Downstream tasks should treat it as the source of truth for CLI shape, default addresses, task JSON, observability, and end-to-end acceptance.

TP-002 defined the contract, TP-003 implemented client submission, and TP-004 aligned the server/worker/client runtime config defaults plus sample JSON config files.

## MVP scope

The MVP is a single-machine demo with one broker, one or more workers, and a one-shot client that submits a shell-command task. It proves the framework can accept a task, schedule it to a worker, execute the command, and expose enough state to verify the run.

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

`loadBalancerLoggingAddr` reserves `5557` for worker PUB log messages. Worker log collection is not required for MVP pass/fail because the current broker config has no external logging address and info storage currently subscribes to an in-process source. If downstream implementation wires log collection, it should use `5557` and expose entries in `/SimpleServer/info.workerLoggingsMap`; otherwise `workerLoggingsMap` may be empty.

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
6. Optional logging: if log collection is wired, `/SimpleServer/info.workerLoggingsMap` may contain stdout/stderr and final command-result entries for the task. Empty worker log maps do not fail the MVP.

ACK alone is not proof of completion; it only proves broker acceptance.

## End-to-end acceptance script

Run the repeatable smoke helper from the repository root after compiling the workspace and all test targets:

```bash
cabal build all --enable-tests
scripts/task-schedule-smoke.sh
```

The helper starts `ts-server` and `ts-worker` with the checked-in sample configs, waits for `/SimpleServer/info` and `/SimpleServer/worker_stats`, submits a fresh per-run task with `ts-client`, snapshots the info endpoints, checks a per-run marker written by the worker command, and preserves logs plus `result.env` under `.tmp/task-schedule-smoke/<run-id>/`. It bypasses local proxy settings for loopback `curl` probes and cleans up only the process IDs/process groups it started.

Exit codes:

- `0`: full MVP pass; client received ACK, worker stats are visible, the worker marker proof exists, and the current run is absent from garbage.
- `1`: hard runtime failure, including readiness, ACK, marker, or garbage-check failures; inspect the run evidence directory.

Current TP-009 smoke evidence is a full MVP pass: run `.tmp/task-schedule-smoke/tp009-final-20260601T043107Z-241489/` records `status=PASS`, `client_exit=0`, `ts-client` printed `accepted/enqueued ACK: Ack 2026-06-01 04:31:40 UTC`, `/SimpleServer/worker_stats` contained `simpleWorker_1`, the worker wrote the fresh marker file, and `final-garbage.json` did not contain the run id. The previous worker-registration and client-ACK blockers are resolved.

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
- The happy-path task is not in garbage.

TP-009 verification status: `cabal build all --enable-tests` and `scripts/task-schedule-smoke.sh` passed. The smoke run `.tmp/task-schedule-smoke/tp009-final-20260601T043107Z-241489/` proves the client ACK path, worker stats, fresh marker proof, and no current-run garbage entry under the default sample configs.

## Implementation status by task

- **TP-002 (contract):** this MVP contract defines the canonical CLI, address, config, task JSON, and acceptance expectations.
- **TP-003 (client submission):** `ts-client` accepts `TASK_JSON` or `CLIENT_CONFIG_JSON TASK_JSON`, sends the task to frontend `5555`, exits non-zero on parse/argument/ACK timeout failures, and exits `0` after broker acceptance ACK.
- **TP-004 (runtime config alignment):** `ts-server`, `ts-worker`, and `ts-client` use the defaults above; server/worker accept zero or one config argument; worker backend/logging defaults are aligned to `5556`/`5557`; checked-in sample configs load through the exported config readers.
- **TP-005 (end-to-end smoke):** `scripts/task-schedule-smoke.sh` provides the repeatable local smoke path and captures per-run evidence.
- **TP-007 (worker status frame decoding):** worker DEALER sockets now use the configured worker ID as the ZeroMQ routing id, preserving the existing payload frame order while making backend `RouterBackendIn` decode worker status frames as UTF-8.
- **TP-008 (client ACK path):** frontend ROUTER decoding now preserves the REQ routing-id, binary request-id, and empty delimiter frames, enqueues the task, and echoes a `ClientAck` so `ts-client` receives an acceptance ACK and exits successfully.
- **TP-009 (green smoke):** the smoke helper now treats any missing ACK as a hard failure and the default sample-config run exits `0` with client ACK, worker stats, fresh marker proof, and no current-run garbage entry.

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
- Worker log transport is not fully wired to an external server endpoint; `5557` is reserved and log-based acceptance is optional.
- The info API currently exposes worker task membership but not a dedicated task-status field; the file side effect is the required completion proof for the MVP happy path.
- `taskTimeout` and `taskProp.executeTimeoutSec` duplicate timeout data; the MVP resolves ambiguity by making `taskTimeout` authoritative and requiring equality.
