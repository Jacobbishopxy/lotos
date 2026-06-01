# General — Context

**Last Updated:** 2026-05-31
**Status:** Active
**Next Task ID:** TP-007

---

## Current State

This is the default task area for lotos. Tasks that don't belong
to a specific domain area are created here.

Taskplane is configured and ready for task execution. Use `/orch all` for
parallel batch execution or `/orch <path/to/PROMPT.md>` for a single task.

---

## Key Files

| Category | Path |
|----------|------|
| Tasks | `taskplane-tasks/` |
| Config | `.pi/taskplane-config.json` |

---

## Technical Debt / Future Work

_Items discovered during task execution are logged here by agents._

- [x] **Expose client config reader** — Resolved during TP-004 by exporting `readBrokerConfig`, `readWorkerConfig`, and `readClientConfig` from the `Lotos.Zmq` facade so downstream executables can use the existing config readers.
- [ ] **Fix worker status frame decoding** — TP-005 smoke reaches server HTTP readiness, but the server logs repeated backend `ZmqParsing "Text decode error: Cannot decode byte '\\xe4'"` while handling worker status frames, leaving `/SimpleServer/worker_stats` empty before client submission.
- [ ] **Complete live client ACK path** — After worker registration is fixed, verify or implement the server `ClientAck` response so `ts-client` can exit successfully during the end-to-end smoke (discovered during TP-005).
- [ ] **Separate demo suites from regression tests** — `test-conc-executor2`, `test-event-trigger`, `test-logger`, `test-simple-servant`, and `test-zmq-xt` are Cabal test suites but behave as demos/long-running servers; split or reclassify them before making `cabal test all` a CI default (discovered during TP-006).
