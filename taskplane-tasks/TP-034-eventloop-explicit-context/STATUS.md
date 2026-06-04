# TP-034: Convert EventLoop usage to explicit context — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 2
**Review Counter:** 7
**Iteration:** 1
**Size:** M

> **Hydration:** Checkboxes represent meaningful outcomes, not individual code
> changes. Workers expand steps when runtime discoveries warrant it.

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Design explicit EventLoop context access
**Status:** ✅ Complete

- [x] Plan-review checkpoint — decide whether EventLoop context is obtained via `askContext`, `LotosEnv`, or a helper wrapper.
- [x] Record concrete Step 1 design: worker log EventLoop obtains context via `ZmqxM.askContext`; the forked loop captures `LotosEnv` via `ask` only to rerun `LotosApp`, and all EventLoop sockets opened through monadic `open` must be registered only with `withEventLoopIn` using that same context.
- [x] Ensure EventLoop sockets are opened in the same explicit context that `withEventLoopIn` receives.
- [x] Document constraints for future EventLoop migrations.

---

### Step 2: Update worker log EventLoop
**Status:** ✅ Complete

- [x] Replace `Zmqx.EventLoop.withEventLoop` with `withEventLoopIn` in worker log transport.
- [x] Preserve mailbox ACK draining, retry, in-flight, and drop accounting semantics.
- [x] Ensure forked logging loop receives the same explicit context as the worker service.

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review context handoff and socket ownership boundaries.
- [x] Run `cabal test lotos:test:test-zmq-worker-log-transport lotos:test:test-zmq-log-ingest lotos:test:test-zmq-log-protocol-config`.
- [x] Run `cabal build all --enable-tests`.
- [x] Run `scripts/task-schedule-smoke.sh`.

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `taskplane-tasks/CONTEXT.md` with explicit EventLoop context status.
- [x] Record any EventLoop helper conventions in STATUS.md.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | Plan | 1 | REVISE | `.reviews/R001-plan-step1.md` |
| R002 | Plan | 1 | APPROVE | `.reviews/R002-plan-step1.md` |
| R003 | Code | 1 | APPROVE | `.reviews/R003-code-step1.md` |
| R004 | Plan | 2 | APPROVE | `.reviews/R004-plan-step2.md` |
| R005 | Code | 2 | APPROVE | `.reviews/R005-code-step2.md` |
| R006 | Plan | 3 | APPROVE | `.reviews/R006-plan-step3.md` |
| R007 | Code | 3 | APPROVE | `.reviews/R007-code-step3.md` |

---

## Notes / Discoveries

- Plan review R001 suggestion: prefer existing `MonadZmqx`/`askZmqContext` path for context access; add helper wrapper only if multiple EventLoop migrations create duplication.
- Step 1 design decision: use `ZmqxM.askContext` inside `runWorkerLogEventLoop` to obtain the exact `LotosApp` `Zmqx.Context`; keep `ask` only for capturing `LotosEnv` across `forkApp`; do not introduce a helper wrapper until a second EventLoop migration creates duplication.
- Step 1 ownership rule: EventLoop-registered sockets must be opened through monadic context-aware open operations and handed to `Zmqx.EventLoop.withEventLoopIn` with that same context; once registered, the socket is owned by the EventLoop worker and callers interact only via `EventLoop.sends`/`recv`.
- Step 2 targeted verification: `cabal test lotos:test:test-zmq-worker-log-transport` passed (6/6) after changing EventLoop context acquisition, covering ACK draining, retry/drop, in-flight accounting, and worker log transport behavior.
- Step 3 code review checkpoint: R005 approved the context handoff and EventLoop socket ownership boundary before full verification.
- Step 3 targeted test gate passed: `cabal test lotos:test:test-zmq-worker-log-transport lotos:test:test-zmq-log-ingest lotos:test:test-zmq-log-protocol-config` passed (worker log transport 6/6, log protocol config 6/6, log ingest 13/13).
- Step 3 build gate passed: `cabal build all --enable-tests` completed successfully.
- Step 3 smoke gate passed: `scripts/task-schedule-smoke.sh` completed PASS with evidence at `.tmp/task-schedule-smoke/task-schedule-smoke-20260603T100642Z-2971786`; client received ACK, marker was written, and worker logging reached `/logs`.
- EventLoop helper convention: do not add a wrapper for a single EventLoop call site; inside `LotosApp`, obtain the explicit context via `ZmqxM.askContext`, capture `LotosEnv` separately only when a forked thread must rerun `LotosApp`, and pass that same context to `Zmqx.EventLoop.withEventLoopIn`.

| 2026-06-03 09:50 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 09:50 | Step 0 started | Preflight |
| 2026-06-03 09:54 | Review R001 | plan Step 1: REVISE |
| 2026-06-03 09:56 | Review R002 | plan Step 1: APPROVE |
| 2026-06-03 09:58 | Review R003 | code Step 1: APPROVE |
| 2026-06-03 10:00 | Review R004 | plan Step 2: APPROVE |
| 2026-06-03 10:03 | Review R005 | code Step 2: APPROVE |
| 2026-06-03 10:05 | Review R006 | plan Step 3: APPROVE |
| 2026-06-03 10:10 | Review R007 | code Step 3: APPROVE |

| 2026-06-03 10:13 | Worker iter 1 | done in 1356s, tools: 101 |
| 2026-06-03 10:13 | Task complete | .DONE created |