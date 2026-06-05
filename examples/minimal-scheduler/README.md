# Minimal scheduler example

This package is intentionally small: it imports the public `Lotos.Zmq` facade,
defines one task payload, one worker-status payload, a small client submission
helper, and implements the three application extension points:

- `LoadBalancerAlgo` for server-side assignment and deferral.
- `TaskAcceptor` for worker-side lifecycle/status callbacks.
- `StatusReporter` for heartbeat payload construction from `WorkerInfo`.

It is a compile/test fixture rather than a long-running demo service. Run its
bounded assignment preview or tests from the repository root with:

```bash
make example-minimal
cabal test lotos-minimal-scheduler-example:test:test-minimal-scheduler-example
```

The preview only exercises the pure scheduler plan; it does not start a broker,
worker, or client. Use the TaskSchedule application for full runtime config,
process execution, and smoke-test examples.

## Copy this package shape

For a new app, keep the same separation even if you split it across files:

1. **Payloads** — define your task and worker-status types plus `ToZmq` / `FromZmq` frame order.
2. **Scheduler** — implement `LoadBalancerAlgo` and keep the assignment core pure enough to unit test.
3. **Worker and client helpers** — implement `TaskAcceptor`, `StatusReporter`, and small `sendTaskRequest` wrappers without opening framework sockets directly.
