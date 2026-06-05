# Start Here

Use this page as the shortest path through the Lotos docs.

## I want to understand the project

1. Read the repository [`README.md`](../../../README.md) for layout and commands.
2. Read [Architecture](architecture.md) for the broker/worker/client shape.
3. Read [ZMQ Protocol Architecture](zmq-protocol.md) before changing multipart frames.

## I want to build my own scheduler

1. Read [`docs/build-your-own-scheduler.md`](../../../build-your-own-scheduler.md) for the concise checklist.
2. Inspect `examples/minimal-scheduler/src/MinimalSchedulerExample.hs` for the smallest public-API-only scheduler, client helper, acceptor, and reporter.
3. Run the bounded preview and fixture:

   ```bash
   make example-minimal
   cabal test lotos-minimal-scheduler-example:test:test-minimal-scheduler-example
   ```

4. Use [Public API Guide](public-api.md) for facade details and [TaskSchedule](task-schedule.md) for the full runtime example.

## I want to run or diagnose the demo

1. Run the standard verification gate:

   ```bash
   make ci-check
   ```

2. Run an intentional smoke:

   ```bash
   make smoke-single
   make smoke-multi
   ```

3. Use [Dashboard Operations Manual](dashboard-operations.md) for the read-only dashboard startup path:

   ```bash
   make task-schedule-server
   make task-schedule-worker
   make task-schedule-submit
   make dashboard-dev
   ```

4. Use [Operations Runbook](operations.md) for normal probes and [Runtime Failure Runbook](runtime-failures.md) for stuck workers, stale heartbeats, queue pressure, LogIngest issues, or capacity surprises.

## I want to change runtime behavior safely

- Use [Verification Guide](verification.md) to choose the narrowest proof command before widening to `make ci-check`.
- Use [Protocol Compatibility and Versioning](protocol-compatibility.md) before modifying any `ToZmq`/`FromZmq` frame order.
- Use [Compatibility Notes](compatibility.md) before removing legacy JSON names or public aliases.
