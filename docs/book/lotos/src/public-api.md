# Public API Guide

Import the public facade from application code:

```haskell
import Lotos.Zmq
```

The facade re-exports the primary task/protocol ADTs, config readers, service constructors, and extension-point classes. This keeps applications away from lower-level broker, worker, and socket modules.

## Application runners

Use `runZmqApp` or `runZmqAppWithThread` for ZMQ-facing entry points. `runApp` remains a compatibility runner for logger-only code; ZMQ services should use the explicit ZMQ context path so worker threads and EventLoop registrations share the intended context lifetime.

A minimal application usually has three executables that all import `Lotos.Zmq`:

- broker/server: read `BrokerServiceConfig` (for example `applications/TaskSchedule/config/broker.json`) and call `runLBS @"MyServer" proxy brokerConfig scheduler`,
- worker: read `WorkerServiceConfig` (for example `applications/TaskSchedule/config/worker.json`), build `mkWorkerService workerConfig acceptor reporter`, then call `runWorkerService`,
- client: read `ClientServiceConfig` when overriding the frontend or ACK timeout (for example `applications/TaskSchedule/config/client.json`), then call `mkClientService` and `sendTaskRequest` with a `Task t` JSON payload.

For the smallest complete extension-point example, see `examples/minimal-scheduler/src/MinimalSchedulerExample.hs`. That package intentionally imports the public `Lotos.Zmq` facade instead of TaskSchedule or internal modules, and its test suite proves payload frames, a client `sendTaskRequest` helper, assignment/deferral, capacity reservation hooks, and `WorkerInfo` status derivation.

## Task payloads

Define a task payload type and implement:

- `ToJSON`/`FromJSON` if clients read task JSON files.
- `ToZmq`/`FromZmq` for every payload crossing the wire.

`ToZmq`/`FromZmq` frame order is the wire ABI. Compatible changes append fields at the payload tail and keep old-frame decoder tests; incompatible route, discriminator, or prefix changes need an explicit migration or versioned surface. See [Protocol Compatibility and Versioning](protocol-compatibility.md) before changing a public payload.

`Task t` is the framework envelope. The broker fills missing UUIDs via `fillTaskID`/`fillTaskID'`; worker-side code may rely on `unsafeGetTaskID` only after broker assignment.

## Server scheduler

Implement `LoadBalancerAlgo`:

```haskell
instance LoadBalancerAlgo MyScheduler MyTask MyWorkerStatus where
  scheduleTasks scheduler workers tasks = do
    pure (scheduler, ScheduledResult assignments deferred)

  -- Optional when your worker-status payload models capacity/occupied slots.
  applyCapacityReservations _ _ reservedSlots status =
    status { myWaitingOrReservedSlots = myWaitingOrReservedSlots status + reservedSlots }

  workerOccupiedSlots _ _ status =
    Just (myProcessingSlots status + myWaitingOrReservedSlots status)
```

`workers` has already been filtered for liveness and, when the optional capacity hooks are implemented, adjusted for broker-side reservations from tasks already dispatched but not yet reflected in heartbeats. Return `(RoutingID, Task MyTask)` assignments for immediate dispatch and return deferred tasks for later scheduling. Do not mutate ZMQ sockets from scheduler code. `examples/minimal-scheduler` keeps this pure with `planMiniAssignments`, making assignment and overflow behavior easy to regression-test without running a broker.

## Worker execution and status

Implement `TaskAcceptor` and `StatusReporter`:

```haskell
instance TaskAcceptor MyWorker MyTask where
  processTasks TaskAcceptorAPI{..} worker tasks = do
    -- taSendTaskStatus (taskId, TaskProcessing)
    -- taSendTaskLog stream level taskId message
    -- taSendTaskStatus (taskId, TaskSucceed or TaskFailed)
    pure worker

instance StatusReporter MyWorker MyStatus where
  gatherStatus StatusReporterAPI{..} worker = do
    pure (worker, status)
```

`StatusReporterAPI.srReportInfo` exposes framework-maintained processing, waiting, and configured capacity counts. Include these in your payload if scheduler decisions depend on them; the minimal example's `miniStatusFromWorkerInfo` maps these counters into occupied capacity. `StatusReporterAPI.srHandoffQueueStats` exposes worker-side no-drop handoff queue snapshots; use `classifyHandoffQueueStats` or the JSON `overloadStatus` field when surfacing operator diagnostics, but do not treat these observability signals as task/status frame drops or automatic backpressure.

The broker `/info` snapshot also exposes `workerLivenessMap` and `workerReservationMap` for operators. These are read-only diagnostics: heartbeat age and reservation counts explain scheduler behavior, but application code should still make scheduling decisions through `LoadBalancerAlgo` inputs and the capacity hooks rather than reading HTTP state back into the scheduler.

## Logging configuration compatibility

Runtime task logs use the broker `BrokerServiceConfig.logIngest` block and the worker `WorkerServiceConfig.workerLogging` block. New JSON should set `logIngest.logIngestAddr` and `workerLogging.logIngestAddr` explicitly. The old Haskell record fields remain exported for source compatibility, but their JSON names are now compatibility/default-derivation surfaces:

| Old JSON key | Preferred new JSON | Runtime behavior |
|---|---|---|
| `infoStorage.loggingAddr` | `infoStorage.logIngestDefaultAddr` plus explicit `logIngest.logIngestAddr` | Only derives a missing broker LogIngest endpoint; `logIngest` wins when present. |
| `infoStorage.loggingsBufferSize` | `infoStorage.logIngestDefaultBufferSize` | Retained compatibility value; LogIngest retention uses `logIngestReadCacheSize` and journal retention knobs. |
| `loadBalancerLoggingAddr` | `workerLogging.logIngestAddr` (or top-level `logIngestDefaultAddr` for derivation-only configs) | Old key still derives a missing worker logging block; explicit `workerLogging` wins. |
| `taPubTaskLogging` | `taSendTaskLog` | Compatibility callback wraps a stdout/info `LogEvent`; new acceptors should call `taSendTaskLog`. |

When both old and new derivation keys appear in the same JSON object, the new key wins. Partial explicit `logIngest` / `workerLogging` blocks inherit defaults from the selected derivation address instead of reverting to unrelated hard-coded endpoints.

Log delivery is at-least-once: workers retain unacknowledged batches and retry, while broker LogIngest deduplicates accepted worker sequence coverage before exposing `/logs/*` results. Treat log consumers and any downstream ingestion as idempotent; the project does not claim exactly-once delivery.

## Client requests

Use `mkClientService` and `sendTaskRequest`. `sendTaskRequest` returns `Maybe Ack`; `Nothing` means the configured request timeout elapsed or the ACK failed to decode. An ACK means accepted/enqueued by the broker, not completed by a worker.

## Package/release boundaries

Public API compatibility is source/protocol behavior; package metadata compatibility is handled separately in [Release Readiness](release.md). The current first-release bounds are conservative upper bounds for public-library dependencies, while `cabal.project` solver overrides and the pinned `zmqx` source repository remain workspace development settings.
