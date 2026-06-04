# Protocol Compatibility and Versioning

Lotos treats ZeroMQ multipart frames as a stable wire ABI. `ToZmq` chooses the exact frame order that peers see on the wire, and `FromZmq` decodes by position. A frame-order change is therefore a protocol change even when the Haskell type keeps the same name.

## Compatibility policy

Compatible evolution is append-only at the tail of an application payload:

1. Keep every existing frame in the same position with the same meaning.
2. Append new fields after the old payload frames.
3. Teach the decoder to accept the previous exact frame count and choose a conservative default for the new field.
4. Add regression tests for both the new frame order and the old-frame fallback.

Golden frame fixtures now enforce this policy in code. Before changing any `ToZmq` or `FromZmq` instance, update the relevant exact-frame assertion in `lotos/test/ZmqWorkerFrames.hs`, `lotos/test/ZmqClientAckFrames.hs`, `lotos/test/ZmqLogProtocolConfig.hs`, or `applications/TaskSchedule/test/Scheduler.hs`, then run the targeted protocol suites. These tests intentionally use fixed UUID/ACK values so frame order changes show up as simple list diffs.

TaskSchedule's `WorkerState.taskCapacity` is the current example. New workers send nine status payload frames; old workers sent eight. The decoder still accepts the eight-frame shape and treats it as `taskCapacity = 1`, so old workers remain schedulable without over-assigning capacity.

```text
old WorkerState: load1 load5 load15 memTotal memUsed memAvailable processing waiting
new WorkerState: load1 load5 load15 memTotal memUsed memAvailable processing waiting taskCapacity
```

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
| TaskSchedule `WorkerState` | Nine-frame status payload with appended `taskCapacity`. | Accepts old eight-frame payload as single-slot capacity; covered both directly and inside worker-status wrapper frames. |
| TaskSchedule `ClientTask` | Command and timeout frames. | No fallback. |

## Deliberate compatibility breaks

A break is allowed only when old and new peers cannot safely share one decoder. Use a new discriminator, endpoint, or explicitly versioned payload so old peers fail clearly instead of mis-decoding frames. Document the migration, update both peers, and add tests that prove the old shape is either still accepted through a fallback or intentionally rejected.

## Version tags

Lotos does not add protocol-wide version tags yet. The current protocol already has role-specific endpoints, socket identities, and message-type discriminators, and the only live additive payload change is covered by an old-frame fallback. Add explicit version tags when an incompatible alternate protocol must coexist on the same route, not preemptively for every append-only payload addition.
