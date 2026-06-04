# EventLoop Ownership

Recent work moved long-running ZMQ loops to explicit-context `Zmqx.EventLoop` ownership where it clarified socket access and shutdown behavior.

## Ownership rules

- Open sockets under the same explicit monadic ZMQ context that will run the EventLoop.
- Register long-running sockets with the EventLoop, then send through `Zmqx.EventLoop.sends` and receive through EventLoop callbacks or mailboxes.
- Do not touch raw registered sockets from application threads after registration.
- Keep EventLoop callbacks lightweight. Decode complete frame sets enough to hand them off, then perform application state mutation on the owning service thread.
- Treat stopped-loop/`ETERM` errors as shutdown signals for the affected service loop rather than as ordinary application failures.

## Current EventLoop paths

- Worker reliable-log DEALER send/ACK receive ownership.
- Worker backend DEALER for task receive, heartbeat sends, and task-status forwarding.
- Broker LogIngest ROUTER dispatch to ingestion state.
- Broker SocketLayer frontend/backend ROUTERs and TaskProcessor PAIR traffic.
- Broker TaskProcessor internal PAIR notification and worker-dispatch sockets.

## Intentional direct path

The public client request path remains direct: a caller-owned REQ socket sends one task and waits for an ACK with `reqTimeoutSec`. An EventLoop mailbox would add cancellation/drop semantics without improving routing for this synchronous exchange.

## Queue semantics

Task and status handoff queues are intentionally no-drop in the current architecture. Some notification paths use bounded wake mailboxes because they are hints and the trigger timeout remains the correctness fallback. Logging queues are bounded by design and must surface visible gap records when they drop low-priority records.
