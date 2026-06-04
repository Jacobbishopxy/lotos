# Public API Guide

Import the public facade from application code:

```haskell
import Lotos.Zmq
```

The facade re-exports the primary task/protocol ADTs, config readers, service constructors, and extension-point classes. This keeps applications away from lower-level broker, worker, and socket modules.

## Application runners

Use `runZmqApp` or `runZmqAppWithThread` for ZMQ-facing entry points. `runApp` remains a compatibility runner for logger-only code; ZMQ services should use the explicit ZMQ context path so worker threads and EventLoop registrations share the intended context lifetime.

## Task payloads

Define a task payload type and implement:

- `ToJSON`/`FromJSON` if clients read task JSON files.
- `ToZmq`/`FromZmq` for every payload crossing the wire.

`Task t` is the framework envelope. The broker fills missing UUIDs via `fillTaskID`/`fillTaskID'`; worker-side code may rely on `unsafeGetTaskID` only after broker assignment.

## Server scheduler

Implement `LoadBalancerAlgo`:

```haskell
instance LoadBalancerAlgo MyScheduler MyTask MyWorkerStatus where
  scheduleTasks scheduler workers tasks = do
    pure (scheduler, ScheduledResult assignments deferred)
```

`workers` has already been filtered for liveness. Return `(RoutingID, Task MyTask)` assignments for immediate dispatch and return deferred tasks for later scheduling. Do not mutate ZMQ sockets from scheduler code.

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

`StatusReporterAPI.srReportInfo` exposes framework-maintained processing, waiting, and configured capacity counts. Include these in your payload if scheduler decisions depend on them.

## Client requests

Use `mkClientService` and `sendTaskRequest`. `sendTaskRequest` returns `Maybe Ack`; `Nothing` means the configured request timeout elapsed or the ACK failed to decode. An ACK means accepted/enqueued by the broker, not completed by a worker.
