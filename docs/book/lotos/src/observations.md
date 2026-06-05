# Observations

## Current state

The repository is a Cabal workspace with two packages:

- `lotos/lotos.cabal` provides the reusable load-balancer library.
- `applications/TaskSchedule/TaskSchedule.cabal` provides a shell-command demo with server, worker, and client executables.

The recent TP-032 through TP-041 work moved long-running broker and worker socket loops toward explicit `Zmqx.Monad` context ownership and `Zmqx.EventLoop`-registered sockets where that reduced direct polling without changing protocol frames. The public client path intentionally remains a direct synchronous REQ/ACK exchange because it is owned by one caller and already has explicit timeout semantics.

## Design invariants

- **Task IDs are broker-owned.** Clients may submit tasks with `taskID = null`; the broker fills UUIDs before scheduling or worker execution.
- **Frame order is the wire contract.** `ToZmq` and `FromZmq` instances decode multipart messages positionally. Any frame-order change must update both peers and bounded frame tests.
- **Task/status queues preserve no-drop semantics.** EventLoop callbacks hand off complete frame sets to owner-thread queues; task and status traffic should not silently drop under load. Queue depth/high-water counters, derived `overloadStatus`, and bounded WARN logs make overload visible without converting those protocol-critical queues into dropping queues.
- **Logging is at-least-once.** Worker log batches retry until the broker LogIngest service ACKs accepted records. Deduplication makes retries idempotent, but the project does not claim exactly-once delivery.
- **Capacity is heartbeat based.** TaskSchedule reports configured worker capacity in status payloads; schedulers should treat this as a snapshot that can lag rapid assignment/execution changes.

## Practical consequence for adopters

Most application code should stay behind the `Lotos.Zmq` facade: implement serialization for payloads, implement one scheduler, implement worker accept/status callbacks, and wire the standard server/worker/client services. Avoid opening raw ZMQ sockets in application code unless you are intentionally extending the framework.

For operator diagnosis of these invariants in a running TaskSchedule deployment, see the [Runtime Failure Runbook](runtime-failures.md).
