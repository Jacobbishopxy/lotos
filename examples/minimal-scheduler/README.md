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
