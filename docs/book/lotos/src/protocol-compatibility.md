# Protocol Compatibility and Versioning

Lotos treats ZeroMQ multipart frames as a stable wire ABI. `ToZmq` chooses the exact frame order that peers see on the wire, and `FromZmq` decodes by position. A frame-order change is therefore a protocol change even when the Haskell type keeps the same name.

## Compatibility policy

Compatible evolution is append-only at the tail of an application payload:

1. Keep every existing frame in the same position with the same meaning.
2. Append new fields after the old payload frames.
3. Teach the decoder to accept the previous exact frame count and choose a conservative default for the new field.
4. Add regression tests for both the new frame order and the old-frame fallback.

Golden frame fixtures now enforce this policy in code. Before changing any `ToZmq` or `FromZmq` instance, update the relevant exact-frame assertion in `lotos/test/ZmqWorkerFrames.hs`, `lotos/test/ZmqClientAckFrames.hs`, `lotos/test/ZmqLogProtocolConfig.hs`, or `applications/TaskSchedule/test/Scheduler.hs`, then run the targeted protocol suites. These tests intentionally use fixed UUID/ACK values so frame order changes show up as simple list diffs.

TaskSchedule's `WorkerState` append-only payload is the current example. Current workers send eleven status payload frames: the old eight-frame load/memory/task-count prefix, appended `taskCapacity`, appended `cpuUsagePercent`, then appended JSON worker tags. The decoder still accepts the ten-frame CPU shape, nine-frame capacity shape, and original eight-frame shape; old workers remain schedulable as `taskCapacity = 1` with unknown CPU reported as `0` and no tags.

```text
old WorkerState:      load1 load5 load15 memTotal memUsed memAvailable processing waiting
capacity WorkerState: load1 load5 load15 memTotal memUsed memAvailable processing waiting taskCapacity
current WorkerState:  load1 load5 load15 memTotal memUsed memAvailable processing waiting taskCapacity cpuUsagePercent
```

## Versioning decision matrix

Use this matrix before editing any `ToZmq` or `FromZmq` instance. The safe default is to keep the current route and append only when old peers can still decode the old prefix exactly.

| Change shape | Compatibility decision | Required tests |
|---|---|---|
| Add an optional application field after all existing payload frames. | Keep the same route/discriminator. Append the field at the tail and keep an old-frame `FromZmq` case with a conservative default. | Exact-frame golden test for the new shape plus an old-frame fallback test. |
| Add records to a count-delimited tail such as `LogBatch` events or `LogAck` rejected messages. | Keep the count field authoritative. Do not accept surplus frames that are not represented by the count. | Round-trip the new counted shape and keep negative/mismatched-count rejection tests. |
| Insert, remove, reorder, or reinterpret an existing frame. | Treat as incompatible. Do not widen the existing decoder to guess both meanings. | Prove the old shape either remains accepted by an explicit fallback or fails with a bounded negative fixture. |
| Add a new message semantic on an existing socket where peers can branch by type. | Prefer a new discriminator frame, for example alongside `WorkerStatusT` / `WorkerTaskStatusT`, so old peers reject unknown messages clearly. | Exact-frame tests for the new discriminator and negative tests that old/wrong discriminators do not decode as existing messages. |
| Change routing, socket ownership, envelope placement, or transport lifecycle. | Prefer a new endpoint or socket path so old and new peers do not share ambiguous frames. | Peer-to-peer smoke or integration coverage plus exact envelope tests for both sides. |
| Need old and new incompatible payload schemas to coexist on the same route/discriminator during a rolling migration. | Add an explicit versioned payload surface near the discriminator/prefix, document the supported versions, and fail closed for unknown versions. | Version-specific fixtures, old-peer rejection or fallback proof, and migration tests covering mixed-version peers. |

Do not use a protocol-wide version tag for append-only additions. Add version tags only when an incompatible alternate schema must coexist with the old one and a route/discriminator/endpoint split would be more confusing than an explicit version frame.

## Migration test plan

Every incompatible protocol plan should state which peers can talk during rollout:

1. **Old sender → new receiver:** accepted only through a named fallback, or rejected with a clear parse failure.
2. **New sender → old receiver:** rejected before side effects unless the rollout guarantees old receivers are gone.
3. **New sender → new receiver:** exact golden frames match the documented order.
4. **Mixed runtime path:** if endpoints or discriminators change, run the smallest broker/client/worker or LogIngest smoke that proves routing and ACK behavior.

Keep these tests bounded. They should live next to the current frame fixtures, not in long-running demo executables.

## What may not change silently

Route envelopes, request-id delimiters, message-type discriminators, count fields, and existing payload prefixes are not append-only extension points. Reordering or removing any of these can make peers decode the wrong value or route replies to the wrong socket.

Do:

- append optional payload fields at the end;
- keep old-frame `FromZmq` cases when old peers may still run;
- use conservative defaults for missing appended fields;
- assert exact frame lists in bounded tests.

Do not:

- insert a field in the middle of a payload;
- change `WorkerStatusT`/`WorkerTaskStatusT` or ROUTER/REQ envelope placement without a migration;
- reinterpret a frame's type or unit in place;
- make a decoder accept unknown trailing frames unless the payload has an explicit count-delimited tail.

## Current payload inventory

Most current payloads decode only the current frame shape. The explicit compatibility fallback is TaskSchedule `WorkerState`.

| Payload surface | Shape notes | Fallback status |
|---|---|---|
| `Task t` | Fixed task prefix followed by nested task payload frames. | No fallback; covered by worker golden fixtures. |
| Client frontend `ClientRequest` / `ClientAck` | ROUTER/REQ routing id, request id, delimiter, and task/ack payloads. | No fallback; envelope placement is stable and covered by client golden fixtures. |
| Backend `WorkerTask`, `WorkerStatus`, `WorkerTaskStatus` | Worker routing id plus task payload or `WorkerMsgType`, `Ack`, and status payload. | No fallback; discriminator and prefix frames are stable and covered by worker golden fixtures. |
| `WorkerReportStatus`, `WorkerReportTaskStatus` | Worker DEALER payloads before ZeroMQ adds the routing envelope. | No fallback except through nested worker-status payloads; covered by worker golden fixtures. |
| `WorkerLogging` | Legacy task id plus text line. | No fallback; retained as a compatibility surface and covered by log compatibility tests. |
| `LogEvent`, `LogBatch`, `LogAck` | Fixed log event frames; batches/acks include count-delimited variable tails. | No old-frame fallback; counts must match tails exactly and are covered by log golden/negative fixtures. |
| `Notify`, `Ack`, scalar enums/discriminators | Small exact positional payloads. | No fallback. |
| TaskSchedule `WorkerState` | Eleven-frame status payload with appended `taskCapacity`, `cpuUsagePercent`, and JSON worker tags. | Accepts old ten-frame CPU payload, old nine-frame capacity payload, and old eight-frame payload as untagged/single-slot/unknown-CPU compatibility shapes; covered both directly and inside worker-status wrapper frames. |
| TaskSchedule `ClientTask` | Command and timeout frames. | No fallback. |

## Deliberate compatibility breaks

A break is allowed only when old and new peers cannot safely share one decoder. Use a new discriminator, endpoint, or explicitly versioned payload so old peers fail clearly instead of mis-decoding frames. Document the migration, update both peers, and add tests that prove the old shape is either still accepted through a fallback or intentionally rejected.

## Version tags

Lotos does not add protocol-wide version tags yet. The current protocol already has role-specific endpoints, socket identities, and message-type discriminators, and the only live additive payload change is covered by an old-frame fallback. Add explicit version tags when an incompatible alternate protocol must coexist on the same route, not preemptively for every append-only payload addition.
