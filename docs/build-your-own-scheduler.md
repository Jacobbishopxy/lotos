# Build your own scheduler with `lotos`

This guide is the short path for turning the `lotos` load-balancer library into an application-specific scheduler. Start with the tiny public-API-only package in `examples/minimal-scheduler/`, then use the TaskSchedule source and [`docs/task-schedule-mvp.md`](task-schedule-mvp.md) for full runtime details.

## 1. Model your task and worker status payloads

Import the public facade and keep protocol details in your own payload types:

```haskell
import Lotos.Zmq
```

Define:

- a task payload type `t` that clients submit inside `Task t`,
- a worker-status payload type `w` that workers report to the broker,
- `ToJSON`/`FromJSON` instances for client task files when you want JSON submission,
- `ToZmq`/`FromZmq` instances for every payload that crosses ZeroMQ.

`ToZmq`/`FromZmq` frame order is the wire contract. Update both peers and bounded frame tests whenever you change it. Examples:

- `examples/minimal-scheduler/src/MinimalSchedulerExample.hs` — `MiniTask`, `submitMiniTask`, and `MiniWorkerStatus`, implemented through the public `Lotos.Zmq` facade only; `make example-minimal` prints a bounded assignment preview.
- `applications/TaskSchedule/src/Adt.hs` — richer `ClientTask`, `WorkerState`, and their ZMQ/JSON shapes.
- `examples/minimal-scheduler/test/MinimalSchedulerExampleTest.hs`, `lotos/test/ZmqWorkerFrames.hs`, and `lotos/test/ZmqClientAckFrames.hs` — frame-regression test patterns at different sizes.

## 2. Implement the server scheduler

Provide a scheduler state value and an instance of `LoadBalancerAlgo`:

```haskell
instance LoadBalancerAlgo MyScheduler MyTask MyWorkerStatus where
  scheduleTasks scheduler workers tasks = do
    -- workers :: [(RoutingID, MyWorkerStatus)]
    -- tasks   :: [Task MyTask]
    pure (scheduler, ScheduledResult assignments deferred)

  -- Optional capacity hooks. Leave the defaults when your status payload does
  -- not model occupied slots.
  applyCapacityReservations _ _ reservedSlots status =
    status { myWaitingOrReservedSlots = myWaitingOrReservedSlots status + reservedSlots }

  workerOccupiedSlots _ _ status =
    Just (myProcessingSlots status + myWaitingOrReservedSlots status)
```

Return assignments for tasks that should be sent to worker routing IDs now, and return deferred tasks when they should stay queued for a later scheduling pass. The broker owns UUID assignment; scheduler logic can assume scheduled/executing tasks have IDs. The `workers` list has already been filtered for broker-side liveness, so stale workers are removed before your algorithm sees the snapshot.

If your worker status reports capacity or occupied-slot counts, implement the two optional hooks instead of importing broker internals. `applyCapacityReservations` overlays broker-known reservations onto the status passed to `scheduleTasks`, preventing repeated scheduler passes from over-assigning while worker heartbeats lag. `workerOccupiedSlots` lets the broker conservatively reconcile reservations once later heartbeats demonstrably include them.

Minimal reference: `examples/minimal-scheduler/src/MinimalSchedulerExample.hs` sorts ready workers by routing id, expands each available capacity slot, assigns overflow as deferred work, overlays reservations onto `miniWorkerOccupied`, and exposes `workerOccupiedSlots` for reconciliation. TaskSchedule reference: `applications/TaskSchedule/src/Server.hs` prefers the lowest device-CPU/memory load score, overlays reservations onto `WorkerState.waitingTaskNum`, subtracts processing/waiting counts from `WorkerState.taskCapacity`, assigns fresh tasks across remaining slots in stable load-sorted rounds, and returns overflow as deferred work. If your application needs precise capacity, include the relevant limit or remaining-slot value in your worker status payload and test the resulting assignment/deferred-task contract.

## 3. Implement worker execution and status reporting

Workers implement two extension points:

```haskell
instance TaskAcceptor MyWorker MyTask where
  processTasks TaskAcceptorAPI{..} worker tasks = do
    -- call taSendTaskStatus (taskId, TaskProcessing) when work starts
    -- call taSendTaskLog stream level taskId text for reliable task logs
    -- taPubTaskLogging remains as a compatibility wrapper for plain stdout/info text
    -- call taSendTaskStatus (taskId, TaskSucceed/TaskFailed) when work ends
    pure worker

instance StatusReporter MyWorker MyWorkerStatus where
  gatherStatus StatusReporterAPI{..} worker = do
    -- include wiProcessingTaskNum/wiWaitingTaskNum/wiTaskCapacity from srReportInfo if useful
    pure (worker, status)
```

Minimal reference: `examples/minimal-scheduler/src/MinimalSchedulerExample.hs` exposes `submitMiniTask` as the client submission helper, reports `TaskProcessing`, enqueues one stdout/info log event, and reports `TaskSucceed` without opening sockets directly. TaskSchedule reference: `applications/TaskSchedule/src/Worker.hs` executes shell commands with `Lotos.Proc`, sends stdout/stderr and final command results through `taSendTaskLog`, reports `TaskProcessing`, and maps command results to `TaskSucceed` or `TaskFailed`. Reliable logging uses a separate LogIngest DEALER/ROUTER subsystem described in [`logging-redesign.md`](logging-redesign.md). Delivery is at-least-once with broker-side deduplication, so downstream log consumers should be idempotent and docs/tests must not assert exactly-once delivery.

## 4. Wire server, worker, and client services

Use `Lotos.Zmq` from executable entry points instead of importing lower-level implementation modules.

Server shape:

```haskell
runLBS @"MyServer" @MyScheduler @MyTask @MyWorkerStatus proxy brokerConfig scheduler
```

Worker shape:

```haskell
service <- mkWorkerService workerConfig acceptor reporter
runWorkerService service workerConfig
```

Client shape:

```haskell
service <- mkClientService clientConfig
ack <- sendTaskRequest service task
```

Config endpoints must align:

- clients send to the broker `frontendAddr`,
- workers connect to the broker `backendAddr`,
- reliable worker logging uses broker `logIngest.logIngestAddr` and worker `workerLogging.logIngestAddr` (the TaskSchedule demo uses `tcp://127.0.0.1:5558`), while new default-derivation hints (`infoStorage.logIngestDefaultAddr`, `infoStorage.logIngestDefaultBufferSize`, optional top-level `logIngestDefaultAddr`) replace legacy logging names in fresh JSON; old `infoStorage.loggingAddr`, `infoStorage.loggingsBufferSize`, and `loadBalancerLoggingAddr` remain accepted for compatibility,
- `taskProcessor.workerStaleTimeoutSec` is higher than the normal worker `workerStatusReportIntervalSec` plus expected jitter.

The TaskSchedule sample configs under `applications/TaskSchedule/config/` show the loopback defaults, including a 60-second stale-worker timeout for 5-second worker status reports. `applications/TaskSchedule/config/task-demo.json` is a copyable client task that writes `.tmp/task-schedule-demo.out`.

## 5. Handle retries and completion evidence explicitly

A client ACK means accepted/enqueued by the broker, not completed by a worker. Application-level completion proof should come from worker state, task status, logs, durable side effects, or the info API.

Retry behavior is controlled by the `Task` fields:

- `taskRetry > 0` allows failed tasks to be requeued with the retry count decremented,
- `taskRetry == 0` moves failed tasks to the garbage ring buffer,
- `taskRetryInterval > 0` delays retry eligibility by at least that many seconds,
- `taskRetryInterval <= 0` retries immediately when retries remain.

If a worker stops reporting status beyond `taskProcessor.workerStaleTimeoutSec`, the broker removes that worker before scheduling and treats its non-succeeded in-flight tasks as failures using the same retry/garbage rules. Use `TaskSucceed` only for work that really completed, because succeeded entries are dropped rather than retried during stale-worker cleanup.

## 6. Verify with bounded tests and intentional smokes

Recommended gates from the repository root follow the TP-049 CI/local profile:

```bash
make ci-check        # cabal build all --enable-tests + explicit bounded tests + mdBook
make ci-test         # rerun only the explicit bounded regression target list
make book-build      # docs-only gate
make example-minimal # bounded public-API scheduler preview
make smoke-single    # intentional end-to-end demo after the build gate
make smoke-multi     # intentional multi-worker/capacity smoke after the build gate
```

Avoid using `cabal test all` as the default gate for this workspace. The safe regression list is encoded in `Makefile` as `CI_TEST_TARGETS`, while long-running or no-assertion demos are Cabal `demo-*` executables and should be run intentionally, usually with `timeout`.

For a new application, add bounded tests like `examples/minimal-scheduler/test/MinimalSchedulerExampleTest.hs` for:

- payload `ToZmq`/`FromZmq` frame order,
- scheduler assignment/deferred-task decisions, including backpressure when workers report no remaining capacity,
- worker success/failure/status mapping,
- stale-worker recovery or scheduler behavior around disappearing workers when your app has custom retry expectations,
- client ACK shape or JSON validation if you add a custom client.
