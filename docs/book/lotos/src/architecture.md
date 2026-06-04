# Architecture

Lotos is a Cabal workspace with a reusable load-balancer library and the checked-in TaskSchedule demo application.

The broker sits between client requests and worker heartbeats. It owns task IDs, task queues, worker liveness snapshots, retry/garbage handling, and the scheduler loop that decides which worker routing IDs receive tasks.

Key invariants are documented across the protocol and operations chapters:

- multipart ZMQ frame order is the wire contract;
- task/status handoff queues preserve no-drop semantics;
- logging is at-least-once rather than exactly-once;
- capacity-aware scheduling uses heartbeat snapshots that may lag fast broker dispatches.

## Broker-side capacity reservations

The broker owns a reservation map alongside the worker task/status maps. When the task processor dispatches a task to a worker, it records a broker-known occupied slot before the next heartbeat can report the worker's updated waiting/processing counts. Scheduler input is then adjusted from this broker state instead of changing the public `LoadBalancerAlgo.scheduleTasks` contract.

Reservations are conservative: non-terminal task statuses such as `TaskPending` and `TaskProcessing` keep consuming capacity, and heartbeat/liveness updates do not blindly clear the broker-known slot if the snapshot may be stale. Capacity is released when terminal task status (`TaskSucceed`/`TaskFailed`) or stale-worker recovery proves the worker is no longer holding that slot.

