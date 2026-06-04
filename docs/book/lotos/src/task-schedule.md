# TaskSchedule

`applications/TaskSchedule` is the checked-in example application. It schedules shell-command tasks across one or more workers and exposes HTTP state for local verification.

## Executables

```bash
mkdir -p logs
cabal run TaskSchedule:exe:ts-server -- [BROKER_CONFIG_JSON]
cabal run TaskSchedule:exe:ts-worker -- [WORKER_CONFIG_JSON]
cabal run TaskSchedule:exe:ts-client -- TASK_JSON
cabal run TaskSchedule:exe:ts-client -- CLIENT_CONFIG_JSON TASK_JSON
```

Default loopback endpoints:

| Traffic | Endpoint |
| --- | --- |
| Client frontend | `tcp://127.0.0.1:5555` |
| Worker backend | `tcp://127.0.0.1:5556` |
| LogIngest default-derivation hint (`infoStorage.logIngestDefaultAddr`; legacy keys accepted) | `tcp://127.0.0.1:5557` |
| Reliable LogIngest | `tcp://127.0.0.1:5558` |
| Info HTTP | `http://127.0.0.1:8081/SimpleServer/...` |

## Scheduler behavior

`SimpleServer` sorts workers by combined CPU/memory load, computes remaining slots from reported status payloads, assigns tasks to available worker slots, and returns overflow to the broker queue. Before `scheduleTasks` runs, the broker overlays its capacity reservations onto each `WorkerState` by adding reserved slots to `waitingTaskNum`; this prevents repeated scheduler passes from assigning past `taskCapacity` while worker heartbeat counts have not caught up. Older eight-frame worker status payloads still decode as single-slot workers, preserving compatibility with workers that do not report capacity.

## Worker behavior

`SimpleWorker` executes shell commands with `Lotos.Proc`, reports `TaskProcessing` at command start, streams stdout/stderr through reliable task logs, emits a final `LogResult`, and reports `TaskSucceed` or `TaskFailed` based on the command result.

## Completion evidence

A client ACK only proves broker acceptance. For task completion, check a worker side effect, worker task/status state, `/logs/worker/<workerId>`, `/logs/task/<taskUuid>`, or the smoke-script evidence directories.

See [`docs/task-schedule-mvp.md`](../../../task-schedule-mvp.md) for the full product-facing runtime contract.
