# TaskSchedule MVP Runtime Contract

This document is the product-facing runtime contract for the `applications/TaskSchedule` demo. TP-003 through TP-006 should treat it as the source of truth for CLI shape, default addresses, task JSON, observability, and end-to-end acceptance.

TP-002 only defines the contract; it does not implement the CLI or framework changes.

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

`loadBalancerBackendAddr` is the task/status backend and must match the server backend (`5556`). Current demo literals that point the worker backend at `5555` are out of contract.

`loadBalancerLoggingAddr` reserves `5557` for worker PUB log messages. Worker log collection is not required for MVP pass/fail because the current broker config has no external logging address and info storage currently subscribes to an in-process source. If downstream implementation wires log collection, it should use `5557` and expose entries in `/SimpleServer/info.workerLoggingsMap`; otherwise `workerLoggingsMap` may be empty.

### Client

```bash
cabal run TaskSchedule:exe:ts-client -- TASK_JSON
cabal run TaskSchedule:exe:ts-client -- CLIENT_CONFIG_JSON TASK_JSON
```

- `TASK_JSON` is required.
- With one argument, the client uses the built-in MVP client config.
- With two arguments, it reads `ClientServiceConfig` JSON from the first path and the task from the second path.

Client defaults:

| Field | Default |
|---|---:|
| `clientId` | `simpleClient_1` |
| `loadBalancerFrontendAddr` | `tcp://127.0.0.1:5555` |
| `reqTimeoutSec` | `5` |

ACK semantics:

- A client ACK means **accepted/enqueued by the broker**, not completed by a worker.
- The client exits `0` after receiving an ACK and prints the ACK timestamp.
- If parsing fails, arguments are invalid, or no ACK arrives within `reqTimeoutSec`, the client exits non-zero and prints a clear error.
- Current framework/client code waits for an ACK while the server frontend currently only enqueues; downstream implementation must close that gap.

## JSON config shapes

The MVP config files use existing record field names.

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

A downstream implementation is acceptable when this flow works from a clean checkout after building the executables:

```bash
rm -f .tmp/task-schedule-demo.out
mkdir -p logs .tmp

# Terminal 1
cabal run TaskSchedule:exe:ts-server

# Terminal 2
cabal run TaskSchedule:exe:ts-worker

# Terminal 3
cabal run TaskSchedule:exe:ts-client -- task-demo.json
curl -fsS http://127.0.0.1:8081/SimpleServer/worker_stats
curl -fsS http://127.0.0.1:8081/SimpleServer/worker_tasks
curl -fsS http://127.0.0.1:8081/SimpleServer/garbage
cat .tmp/task-schedule-demo.out
```

Pass criteria:

- Server and worker stay running without uncaught exceptions.
- Client prints an accepted/enqueued ACK and exits `0`.
- Worker stats include `simpleWorker_1`.
- The demo task is visible in queue/worker state during or after scheduling.
- `.tmp/task-schedule-demo.out` contains exactly `task-schedule-ok`.
- The happy-path task is not in garbage.

## Downstream acceptance by task

- **TP-003 (server runtime):** server accepts zero/one config argument, uses the defaults above, creates/logs to `./logs/taskScheduleServer.log`, binds frontend `5555`, backend `5556`, and serves the info API on `8081`.
- **TP-004 (worker runtime):** worker accepts zero/one config argument, uses backend `5556`, reports `simpleWorker_1` in `/worker_stats`, executes shell commands with `parallelTasksNo`, and treats `5557` logging as reserved/optional rather than reusing the task backend.
- **TP-005 (client runtime):** client accepts `TASK_JSON` or `CLIENT_CONFIG_JSON TASK_JSON`, validates the timeout fields, sends the task to frontend `5555`, prints accepted/enqueued ACKs, and exits non-zero on parse/argument/ACK timeout failures.
- **TP-006 (end-to-end verification):** the demo task above passes the end-to-end acceptance script and documents any remaining non-MVP limitations.

## Non-goals and known risks

Non-goals for the MVP:

- No protocol/frame redesign beyond what is necessary for the CLI contract.
- No distributed deployment matrix; loopback defaults are the only required topology.
- No authentication, authorization, or TLS.
- No scheduler algorithm changes.
- No new CLI parsing or configuration dependencies unless a downstream task explicitly approves them.
- No guarantee that client ACK means task completion.

Known risks/gaps for downstream work:

- `ts-client` is currently a placeholder.
- Current worker hardcoded addresses appear inverted relative to the server; the contract corrects the worker backend to `5556`.
- Current server frontend enqueues requests but does not yet send the client ACK required by this contract.
- Worker log transport is not fully wired to an external server endpoint; `5557` is reserved and log-based acceptance is optional.
- The info API currently exposes worker task membership but not a dedicated task-status field; the file side effect is the required completion proof for the MVP happy path.
- `taskTimeout` and `taskProp.executeTimeoutSec` duplicate timeout data; the MVP resolves ambiguity by making `taskTimeout` authoritative and requiring equality.
