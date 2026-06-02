# Worker Logging Redesign

**Status:** Broker LogIngest skeleton implemented in TP-023 with the TP-022 protocol/config surface. Runtime worker logging still uses the TP-013 InfoStorage PUB/SUB compatibility path by default until a later TP switches workers to the reliable DEALER transport.

## Decision

Move task-scoped worker logs out of the current InfoStorage PUB/SUB side channel and into a first-class broker subsystem named **LogIngest**.

The target wire topology is:

```text
Worker Log DEALER  ── log batches ──>  Broker LogIngest ROUTER
Worker Log DEALER  <── batch ACKs ───  Broker LogIngest ROUTER
                                      ├─ append-only durable log journal
                                      └─ bounded in-memory read cache for the info API
```

The existing worker task/status DEALER and broker backend ROUTER remain responsible for task delivery, worker status, and task status. LogIngest uses a separate endpoint so logging reliability and backpressure do not block task scheduling traffic.

## Reliability target

Target **at-least-once** log ingestion with idempotent broker-side handling. Do not claim exactly-once delivery.

Each log record carries enough identity for deduplication:

- `logEventWorkerId`
- `logEventTaskId`
- monotonically increasing per-worker or per-task `logEventSeq`
- worker-generated `logEventTimestamp`
- `logEventStream`, `logEventLevel`, and `logEventMessage`
- optional `logEventDroppedFrom` / `logEventDroppedThrough` fields for visible gap records

Workers buffer unsent records, transmit them as ordered batches, and retain each batch until LogIngest ACKs it. LogIngest persists records before ACKing the batch. If a worker retries an unacked batch, LogIngest accepts duplicate frames but stores/emits only records whose identity has not already been ingested.

## Transport and ACK protocol

Use DEALER/ROUTER rather than PUB/SUB:

1. The worker opens a dedicated logging DEALER socket with a stable routing id derived from `workerId`.
2. The broker opens a dedicated LogIngest ROUTER socket on a new logging endpoint.
3. Workers send `LogBatch` messages containing one or more ordered `LogEvent`s.
4. LogIngest writes the records to append-only persistence, updates its bounded read cache, then sends `LogAck` to the worker routing id.
5. The ACK includes the batch id and the highest contiguous sequence number durably accepted for that worker.

Sketch of the target message shapes, preserving the project's positional multipart style:

```haskell
data LogStream = LogStdout | LogStderr | LogProgress | LogResult

data LogLevel = LogDebug | LogInfo | LogWarn | LogError

data LogDropPolicy = LogDropNewest | LogDropOldest | LogDropLowPriority

-- frames: [workerId, taskUuid, seq, timestamp, stream, level, message, droppedFrom, droppedThrough]
data LogEvent = LogEvent
  { logEventWorkerId :: RoutingID
  , logEventTaskId :: TaskID
  , logEventSeq :: Word64
  , logEventTimestamp :: UTCTime
  , logEventStream :: LogStream
  , logEventLevel :: LogLevel
  , logEventMessage :: Text
  , logEventDroppedFrom :: Maybe Word64
  , logEventDroppedThrough :: Maybe Word64
  }

-- frames: [batchAck, workerId, firstSeq, eventCount, eventFrames...]
data LogBatch = LogBatch
  { logBatchAck :: Ack
  , logBatchWorkerId :: RoutingID
  , logBatchFirstSeq :: Word64
  , logBatchEvents :: [LogEvent]
  }

-- frames: [batchAck, workerId, acceptedThrough, rejectedCount, rejectedReasons...]
data LogAck = LogAck
  { logAckBatchAck :: Ack
  , logAckWorkerId :: RoutingID
  , logAckAcceptedThrough :: Word64
  , logAckRejected :: [Text]
  }
```

TP-022 locked these `ToZmq`/`FromZmq` frame orders with bounded frame tests. The legacy `WorkerLogging` payload remains `[taskUuid, loggingText]`; its worker-id PUB/SUB topic stays outside that payload until the transport switch rewires runtime logging.

## Backpressure and drop policy

Logging must be bounded at every layer:

- Worker memory: bounded per-worker pending-log queue.
- Wire payload: bounded records per `LogBatch` and bounded encoded batch size.
- Broker memory: bounded in-memory read cache per worker/task.
- Persistence: append-only journal with an explicit retention/compaction policy.

When the worker pending-log queue is full, prefer preserving task lifecycle/result logs over verbose stdout/stderr. The worker may coalesce or drop low-priority records, but it must emit an explicit synthetic gap `LogEvent` with `logEventDroppedFrom`, `logEventDroppedThrough`, and a reason in `logEventMessage` so downstream users can see the loss. Silent drops and hidden sequence gaps are forbidden.

If LogIngest cannot persist records, it must withhold the ACK. Workers retry with backoff until their bounded pending queue forces the visible drop policy above. Logging retry pressure must not stop task status reporting; task status still uses the worker backend DEALER path.

## Persistence and read cache plan

LogIngest owns durable log storage. InfoStorage remains an HTTP snapshot/read facade, not the ingest transport.

Planned responsibilities:

- **Append-only journal:** store accepted records and gap records before ACK. The initial implementation can use a local file under the broker runtime directory; future work may swap the backend without changing worker APIs.
- **Dedup index:** track the highest accepted contiguous sequence and recent batch ids per worker so retransmits are idempotent.
- **Bounded read cache:** maintain a configurable ring buffer keyed by `(workerId, taskId)` for the info API. This replaces the current InfoStorage subscriber ring buffer.
- **Info API compatibility:** expose recent logs through the existing info API shape where practical, but document any response-shape change in the implementation TP.
- **Recovery:** on broker restart, rebuild the dedup watermark and read cache from the journal or explicitly document which cache data is warm-only.

## Query API shape

TP-023 adds broker-side query routes to the existing InfoStorage HTTP server. The routes read from LogIngest's bounded cache and intentionally keep structured logs out of the main scheduler snapshot:

- `/<service>/logs/recent` — most recent accepted `LogEvent`s across workers/tasks.
- `/<service>/logs/worker/:workerId` — most recent accepted events for one worker routing id.
- `/<service>/logs/task/:taskId` — most recent accepted events for one task UUID.
- `/<service>/logs/stats` — counters for accepted events, duplicates, sequence gaps, visible dropped spans, rejected reasons, worker/task cache cardinality, and accepted-through watermarks by worker.

Each log query response has shape `{ "count": number, "events": LogEvent[] }`. Stats responses use stable counter keys such as `acceptedEvents`, `duplicateEvents`, `sequenceGaps`, `droppedEvents`, `rejectedEvents`, and `acceptedThroughByWorker`.

The legacy `/<service>/info` response still includes `workerLoggingsMap` from the PUB/SUB compatibility path for existing TaskSchedule smoke coverage. New structured LogIngest data is exposed through `/logs/...` rather than embedded into `/info`.

## Worker callback API shape

Keep application worker code using a callback surface instead of opening ZMQ sockets directly. Rename or supplement the current logging callback to describe the reliability semantics:

```haskell
data TaskAcceptorAPI = TaskAcceptorAPI
  { taSendTaskLog :: LogEvent -> IO LogEnqueueResult
  , taSendTaskStatus :: (TaskID, TaskStatus) -> IO ()
  }
```

`taSendTaskLog` should enqueue into the worker's bounded local log queue and return whether the event was accepted, coalesced, or dropped with a visible gap marker. It should not wait for broker durability on every log line; durability is batch-ACKed by the worker logging service.

Configuration should separate the logging endpoint from InfoStorage HTTP settings:

```haskell
data LogIngestConfig = LogIngestConfig
  { logIngestAddr :: Text
  , logIngestSocketHWM :: Int
  , logIngestBatchMaxRecords :: Int
  , logIngestBatchMaxBytes :: Int
  , logIngestLineMaxBytes :: Int
  , logIngestWorkerQueueHWM :: Int
  , logIngestReadCacheSize :: Int
  , logIngestReadCacheMaxTasks :: Int
  , logIngestJournalPath :: FilePath
  , logIngestRetentionBytes :: Int
  , logIngestDropPolicy :: LogDropPolicy
  }
```

TP-022 exposes `LogIngestConfig` and `defaultLogIngestConfig` through `Lotos.Zmq`. `BrokerServiceConfig.logIngest` is optional in broker JSON and defaults from `InfoStorageConfig.loggingAddr`; `WorkerServiceConfig.workerLogging` is optional in worker JSON and defaults from `WorkerServiceConfig.loadBalancerLoggingAddr`. Those legacy fields plus `taPubTaskLogging` remain current-state compatibility names, not the target architecture.

## Migration outline

1. **Done in TP-022:** add protocol types and frame/config regression tests for `LogEvent`, `LogBatch`, `LogAck`, `LogStream`, `LogLevel`, `LogDropPolicy`, and `LogIngestConfig`.
2. Introduce LogIngest broker service and durable journal behind a bounded cache.
3. Add a worker logging service with a bounded pending queue, batch retry, and explicit drop/gap records.
4. Rewire InfoStorage to read recent logs from LogIngest/cache instead of binding a SUB socket.
5. Rename public-facing callback/config fields only with a documented compatibility path for adopters.

## TP-023 implementation notes

TP-023 introduces `Lotos.Zmq.LBS.LogIngest` with:

- `newLogIngestState` / `ingestLogBatch` for deterministic unit-tested ingestion.
- `runLogIngest` for a broker ROUTER loop that decodes a DEALER `LogBatch`, persists accepted non-duplicate events, updates bounded caches, and sends a `LogAck` back to the ROUTER envelope identity.
- Append-only JSONL persistence at `logIngestJournalPath`, one accepted `LogEvent` JSON object per line. Duplicates and rejected invalid events are not rewritten to the journal.
- Bounded caches for recent global logs, per-worker logs, per-task logs, and `(worker, task)` logs. Per-cache sequence length is `logIngestReadCacheSize`; task-indexed bucket cardinality is capped by `logIngestReadCacheMaxTasks` with corresponding worker/task bucket eviction.
- Duplicate accounting based on each worker's accepted-through watermark plus bounded covered-ahead ranges. Hidden sequence gaps are counted and keep `LogAck.acceptedThrough` at the highest contiguous covered sequence; explicit gap/drop events with `droppedFrom`/`droppedThrough` count visible dropped spans and can advance the watermark through declared drops.

Conservative runtime integration details and limitations:

- `runLBS` creates LogIngest state for the `/logs/...` routes. It starts the ROUTER only when `logIngestAddr` differs from legacy `InfoStorageConfig.loggingAddr`; old configs default these to the same address, so the ROUTER is skipped to avoid breaking the existing PUB/SUB smoke path.
- Worker-side reliable logging DEALER, retry/backoff, queue drop policy, journal recovery on broker restart, retention/compaction, and full replacement of `workerLoggingsMap` remain follow-up work.
- `LogAck.acceptedThrough` is a contiguous durability watermark, not an exactly-once guarantee. Delivery remains at-least-once with idempotent broker ingestion.
