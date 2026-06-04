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

`SimpleServer` sorts workers by combined CPU/memory load, computes remaining slots from reported status payloads, assigns tasks to available worker slots, and returns overflow to the broker queue. Its `LoadBalancerAlgo` instance implements the public capacity hooks described in the [Public API Guide](public-api.md#server-scheduler): before `scheduleTasks` runs, the broker overlays capacity reservations onto each `WorkerState` by adding reserved slots to `waitingTaskNum`; after later heartbeats include those occupied slots, `workerOccupiedSlots` lets the broker reconcile the reservations conservatively. Non-terminal task-status updates refresh active reservations, but if heartbeat reconciliation has already removed a reservation, a duplicate or late `TaskPending`/`TaskProcessing` update does not recreate it. This prevents repeated scheduler passes from assigning past `taskCapacity` while worker heartbeat counts have not caught up, without keeping safely reconciled slots hidden until terminal status. Older eight-frame worker status payloads still decode as single-slot workers, preserving compatibility with workers that do not report capacity.

## Worker behavior

`SimpleWorker` executes shell commands with `Lotos.Proc`, reports `TaskProcessing` at command start, streams stdout/stderr through reliable task logs, emits a final `LogResult`, and reports `TaskSucceed` or `TaskFailed` based on the command result.

## Completion evidence

A client ACK only proves broker acceptance. For task completion, check a worker side effect, worker task/status state, `/logs/worker/<workerId>`, `/logs/task/<taskUuid>`, or the smoke-script evidence directories.

Use `make smoke-single` / `scripts/task-schedule-smoke.sh` for the single-worker path and `make smoke-multi` / `scripts/task-schedule-multi-worker-smoke.sh` for capacity-aware multi-worker dispatch after `make ci-check` or at least `make ci-build` has passed. The smoke expectations are summarized in the [Verification Guide](verification.md#task-schedule-smoke-checks), and the full product-facing runtime contract remains in [`docs/task-schedule-mvp.md`](../../../task-schedule-mvp.md).
