# Lotos Architecture and API Runbook

This book collects the current operational and architectural observations for `lotos`, a Haskell/Cabal ZeroMQ load-balancer library, and the `TaskSchedule` demo application that exercises it.

If you are new to the repository, start with [Start Here](start-here.md). Use it with the short README for quick commands and with the existing focused guides when you need deeper source-level detail:

- [`docs/build-your-own-scheduler.md`](../../../build-your-own-scheduler.md) for the adopter checklist.
- `examples/minimal-scheduler/` for the smallest public-API-only scheduler fixture.
- [`docs/task-schedule-mvp.md`](../../../task-schedule-mvp.md) for the TaskSchedule runtime contract.
- [`docs/logging-redesign.md`](../../../logging-redesign.md) for reliable worker logging design history.

The book intentionally avoids changing any runtime contract. It documents the current public API surface, ZeroMQ frame-order constraints, EventLoop ownership rules, scheduling observations, and verification commands.
