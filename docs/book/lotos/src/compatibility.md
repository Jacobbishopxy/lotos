# Compatibility Notes

## Protocol frames

All ZeroMQ payloads use positional multipart frames. Preserve frame order for `Task`, client ACK, backend worker status/task-status, and logging frames unless a task explicitly scopes a protocol migration with tests for both peers.

## Worker status capacity

TaskSchedule's `WorkerState` now appends `taskCapacity` to the status payload. The decoder accepts both the new nine-frame shape and the older eight-frame shape. Older workers are treated as conservative single-slot workers.

## Logging names

Several legacy names remain for configuration compatibility:

- `infoStorage.loggingAddr`
- `infoStorage.loggingsBufferSize`
- `loadBalancerLoggingAddr`
- `taPubTaskLogging`

Runtime ingestion uses `logIngest.logIngestAddr`, `workerLogging.logIngestAddr`, and `taSendTaskLog`. Keep legacy fields aligned in older JSON files because defaults may derive the reliable logging endpoint from them.

## Client ACK semantics

`ClientAck` means accepted/enqueued, not completed. The direct REQ path preserves the REQ routing id and request-id envelope so broker replies reach the waiting client. `ClientServiceConfig.reqTimeoutSec` bounds how long the client waits for that ACK.

## EventLoop migration boundaries

Registered EventLoop sockets are worker-owned. Do not reintroduce direct raw sends/receives inside EventLoop brackets. The direct client REQ path is the intentional exception because it is single-owner and synchronous.

## Public facade stability

Application code should import `Lotos.Zmq`. Lower-level modules exist for implementation and tests, but public adopter examples should stay on the facade unless they intentionally test an internal behavior.
