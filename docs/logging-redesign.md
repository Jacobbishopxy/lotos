# Worker Logging Redesign

**Status:** The reliable logging migration is hardened through TP-026. Runtime workers enqueue bounded `LogEvent`s, send `LogBatch`es on a dedicated logging DEALER with configured socket HWM, and retry until broker LogIngest persists/rebuilds state and returns `LogAck`s. TaskSchedule smoke tests prove logs through `/logs/*`; `/info` is a lightweight scheduler snapshot and no longer carries worker log payloads.

## Decision

Move task-scoped worker logs out of the former InfoStorage side channel and into a first-class broker subsystem named **LogIngest**.

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
- monotonically increasing per-worker `logEventSeq`
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

TP-022 locked these `ToZmq`/`FromZmq` frame orders with bounded frame tests. The legacy `WorkerLogging` payload remains `[taskUuid, loggingText]` as a compatibility wrapper; current runtime logging converts it into structured LogIngest events instead of publishing it on a worker-id topic.

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

Current responsibilities:

- **Append/checkpoint journal:** store accepted records and gap records before ACK. The local JSONL journal normally contains one accepted `LogEvent` object per line; retention compaction may rewrite it to a LogIngest checkpoint line plus the newest valid event suffix.
- **Dedup index:** track each worker's highest accepted contiguous sequence plus bounded covered-ahead ranges so retransmits are idempotent. Checkpoints preserve that coverage across broker restarts and compaction.
- **Bounded read cache:** maintain configurable buffers for recent global logs, per-worker logs, per-task logs, and `(workerId, taskId)` views served by `/logs/*`. Restart recovery rebuilds those caches from retained valid event lines; old compacted-away events are intentionally no longer queryable.
- **Info API boundary:** keep `/info` focused on scheduler state and expose worker log reads through dedicated `/logs` endpoints.
- **Recovery:** on broker restart, `newLogIngestState` replays the journal/checkpoint, skips malformed or partial JSONL lines, increments `malformedJournalLines`, restores accepted-through watermarks, and keeps already-covered worker retries from appending duplicate events.

## Query API shape

TP-023 adds broker-side query routes to the existing InfoStorage HTTP server. The routes read from LogIngest's bounded cache and intentionally keep structured logs out of the main scheduler snapshot:

- `/<service>/logs/recent` — most recent accepted `LogEvent`s across workers/tasks.
- `/<service>/logs/worker/:workerId` — most recent accepted events for one worker routing id.
- `/<service>/logs/task/:taskId` — most recent accepted events for one task UUID.
- `/<service>/logs/stats` — counters for accepted events, duplicates, sequence gaps, visible dropped spans, rejected reasons, worker/task cache cardinality, and accepted-through watermarks by worker.

Each log query response has shape `{ "count": number, "events": LogEvent[] }`. Stats responses use stable counter keys such as `acceptedEvents`, `duplicateEvents`, `sequenceGaps`, `droppedEvents`, `rejectedEvents`, `malformedJournalLines`, and `acceptedThroughByWorker`.

The `/<service>/info` response is intentionally scheduler-only. Structured LogIngest data is exposed through `/logs/...` rather than embedded into `/info`, keeping snapshots lightweight while preserving worker/task log queryability.

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

TP-022 exposes `LogIngestConfig` and `defaultLogIngestConfig` through `Lotos.Zmq`. `BrokerServiceConfig.logIngest` is optional in broker JSON and defaults from the legacy `InfoStorageConfig.loggingAddr`; `WorkerServiceConfig.workerLogging` is optional in worker JSON and defaults from `WorkerServiceConfig.loadBalancerLoggingAddr`. Those legacy address fields plus `taPubTaskLogging` remain compatibility names; runtime ingestion uses LogIngest.

## Migration outline

1. **Done in TP-022:** add protocol types and frame/config regression tests for `LogEvent`, `LogBatch`, `LogAck`, `LogStream`, `LogLevel`, `LogDropPolicy`, and `LogIngestConfig`.
2. **Done in TP-023:** introduce LogIngest broker service and durable journal behind a bounded cache.
3. **Done in TP-024:** add a worker logging service with a bounded pending queue, batch retry, and explicit drop/gap records.
4. **Done in TP-025:** remove the InfoStorage full-log snapshot coupling, update smoke tests to assert `/logs/worker/<workerId>` and `/logs/stats`, and document `/info` as scheduler-only.
5. **Done in TP-026:** reload LogIngest state from the JSONL journal/checkpoint on broker startup, tolerate malformed/partial journal lines, compact oversized journals under `logIngestRetentionBytes`, and apply `logIngestSocketHWM` to logging sockets.
6. Rename public-facing callback/config fields only with a documented compatibility path for adopters.

## TP-024/TP-025/TP-026 implementation notes

TP-024 introduces `Lotos.Zmq.LBW.LogTransport` and rewires `TaskAcceptorAPI` with:

- Bounded worker memory via `logIngestWorkerQueueHWM`; enqueue callbacks mutate only local state and never wait for broker durability.
- Dedicated worker logging DEALER sockets connected to `workerLogging.logIngestAddr`, separate from the backend task/status DEALER.
- Partial-batch flushing and retry behavior controlled by `logIngestFlushIntervalMicros`, `logIngestAckTimeoutMicros`, and `logIngestRetryBackoffMicros`.
- Worker-wide monotonic sequence numbers aligned with broker `acceptedThroughByWorker`. Overflow replaces contiguous low-priority spans with warn-level synthetic gap `LogEvent`s containing `droppedFrom`/`droppedThrough` so `/logs/stats.droppedEvents`, `/logs/stats.sequenceGaps`, and query endpoints expose loss.
- TaskSchedule command output mapping: `STDOUT:` lines become `LogStdout`/`LogInfo`, `STDERR:` lines become `LogStderr`/`LogError`, and final command results become `LogResult` with success/failure severity.
- Config compatibility: old broker/worker JSON that omits `logIngest`/`workerLogging` derives a split reliable endpoint from the legacy logging endpoint (demo `tcp://127.0.0.1:5557` -> `tcp://127.0.0.1:5558`). The sample TaskSchedule configs now set the reliable endpoint explicitly.
- TP-025 keeps worker `LogAck` matching at wire precision so whole-second ACK serialization does not strand accepted in-flight batches; this preserves at-least-once retry semantics without changing the global ACK frame shape.
- TP-026 applies `logIngestSocketHWM` as both `Z_SndHWM` and `Z_RcvHWM` on the broker LogIngest ROUTER before bind and the worker logging DEALER before connect.
- TP-026 enforces journal retention after accepted appends. If the configured byte cap is smaller than the checkpoint plus required retained suffix, correctness wins and the cap remains approximate; malformed/partial lines are dropped during replay/compaction with `malformedJournalLines` evidence.

Runtime caveats:

- `infoStorage.loggingAddr`, `infoStorage.loggingsBufferSize`, and `loadBalancerLoggingAddr` remain in config for compatibility/default derivation, but InfoStorage no longer binds a worker-log socket or retains full worker logs.
- Delivery remains at-least-once. Workers retry unacked batches, and LogIngest deduplicates accepted sequence coverage across restart/compaction; exactly-once delivery is not claimed.

## TP-023 implementation notes

TP-023 introduces `Lotos.Zmq.LBS.LogIngest` with:

- `newLogIngestState` / `ingestLogBatch` for deterministic unit-tested ingestion.
- `runLogIngest` for a broker ROUTER loop that decodes a DEALER `LogBatch`, persists accepted non-duplicate events, updates bounded caches, and sends a `LogAck` back to the ROUTER envelope identity.
- Append-only JSONL persistence at `logIngestJournalPath`, one accepted `LogEvent` JSON object per line. Duplicates and rejected invalid events are not rewritten to the journal.
- Bounded caches for recent global logs, per-worker logs, per-task logs, and `(worker, task)` logs. Per-cache sequence length is `logIngestReadCacheSize`; task-indexed bucket cardinality is capped by `logIngestReadCacheMaxTasks` with corresponding worker/task bucket eviction.
- Duplicate accounting based on each worker's accepted-through watermark plus bounded covered-ahead ranges. Hidden sequence gaps are counted and keep `LogAck.acceptedThrough` at the highest contiguous covered sequence; explicit gap/drop events with `droppedFrom`/`droppedThrough` count visible dropped spans and can advance the watermark through declared drops.

Conservative runtime integration details and limitations:

- `runLBS` creates LogIngest state for the `/logs/...` routes and starts the ROUTER on `logIngestAddr` even when explicit configs reuse the legacy logging address; there is no active InfoStorage logging socket to collide with.
- Public compatibility-name cleanup remains follow-up work; the legacy logging address/callback names still derive defaults while runtime ingestion uses LogIngest.
- `LogAck.acceptedThrough` is a contiguous durability watermark, not an exactly-once guarantee. Delivery remains at-least-once with idempotent broker ingestion.
