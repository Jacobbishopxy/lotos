# ZMQ Protocol Architecture

Lotos uses ZeroMQ multipart messages between three runtime roles:

```text
Client REQ  -> Broker frontend ROUTER -> Task queue
Worker DEALER <-> Broker backend ROUTER
Worker log DEALER <-> Broker LogIngest ROUTER
Info HTTP readers -> Broker InfoStorage/LogIngest state
```

## Client to broker

Clients send `Task t` frames through a REQ socket with a stable routing id. The broker frontend ROUTER receives the REQ envelope, preserves the binary request-id delimiter sequence, fills the task UUID, enqueues the task, and replies with a `ClientAck`. The ACK is an acceptance signal only.

## Broker to worker

Workers connect with DEALER sockets whose routing id is the worker id. Worker status heartbeats update liveness and scheduler snapshots. Broker-assigned task messages and worker task-status reports retain their existing `RouterBackendOut`/`RouterBackendIn` multipart shapes.

## Task processor and socket layer

The broker socket layer owns frontend, backend, and TaskProcessor PAIR traffic through EventLoop-registered sockets. EventLoop callbacks only hand complete multipart frames to the socket-layer owner thread. The owner thread runs the decode, enqueue, dispatch bookkeeping, retry/garbage handling, and scheduler notification logic.

The TaskProcessor also uses EventLoop-registered PAIR sockets for worker dispatch and scheduling notifications. Notify reads are wake hints; the normal trigger timeout still guarantees eventual scheduling if hints are coalesced or dropped at the bounded notify mailbox.

## Reliable logging

Runtime task logs use a separate LogIngest path. Workers send ordered `LogBatch` messages, the broker persists accepted `LogEvent`s, updates bounded read caches, and replies with `LogAck`. If dispatch or persistence fails, the broker withholds the ACK so workers retry. Visible drop/gap records are required when worker-side log queues overflow.

## Compatibility rule

Do not change multipart frame ordering casually. If an application changes a payload frame shape, update both the `ToZmq` and `FromZmq` instances, then add bounded frame regression coverage for the new shape.
