# TP-033: Convert core socket operations to Zmqx.Monad — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 3
**Review Counter:** 8
**Iteration:** 1
**Size:** L

> **Hydration:** Checkboxes represent meaningful outcomes, not individual code
> changes. Workers expand steps when runtime discoveries warrant it.

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Convert low-risk socket creation sites
**Status:** ✅ Complete

- [x] Plan-review checkpoint — group socket sites by module and decide conversion order to keep build failures local.
- [x] Convert `LBC` client REQ open/connect/send/receive to `Zmqx.Monad` wrappers where available.
- [x] Convert straightforward test helper socket opens to the monadic surface.

---

### Step 2: Convert broker and worker service sockets
**Status:** ✅ Complete

- [x] Convert `LBS.LogIngest`, `LBS.TaskProcessor`, `LBS.SocketLayer`, and `LBW` direct opens/connects/binds to `Zmqx.Monad.open` and monadic helpers where applicable.
- [x] Preserve existing `zmqUnwrap`/error handling semantics or introduce a minimal monadic wrapper with equivalent behavior.
- [x] Keep direct protocol handler code behavior-equivalent; do not introduce EventLoop migration in this TP.

---

### Step 3: Convert send/receive/poll call sites consistently
**Status:** ✅ Complete

- [x] Replace direct `Zmqx.sends`, `Zmqx.receives`, `Zmqx.poll`, and `Zmqx.pollFor` with `Zmqx.Monad` operations where the API supports them.
- [x] Leave any EventLoop command calls unchanged until TP-034.
- [x] Verify no remaining direct global socket operations exist except deliberately documented exceptions.

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Test-review checkpoint — verify frame ordering coverage is sufficient before finalizing.
- [x] Run frame/protocol tests: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-log-protocol-config`.
- [x] Run worker/log/lifecycle tests touched by conversion.
- [x] Run `cabal build all --enable-tests`.

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `taskplane-tasks/CONTEXT.md` with the direct-socket-to-monad conversion status.
- [x] List intentional remaining direct `Zmqx.*` calls in STATUS.md with rationale.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | plan | 1 | APPROVE | .reviews/R001-plan-step1.md |
| R002 | code | 1 | APPROVE | .reviews/R002-code-step1.md |
| R003 | plan | 2 | APPROVE | .reviews/R003-plan-step2.md |
| R004 | code | 2 | APPROVE | .reviews/R004-code-step2.md |
| R005 | plan | 3 | APPROVE | .reviews/R005-plan-step3.md |
| R006 | code | 3 | APPROVE | .reviews/R006-code-step3.md |
| R007 | plan | 4 | APPROVE | .reviews/R007-plan-step4.md |
| R008 | code | 4 | APPROVE | .reviews/R008-code-step4.md |

---

## Notes / Discoveries

- Step 1 socket-site grouping before plan review: start with `Lotos.Zmq.LBC` (REQ `connect`/`sends`/`receives` already uses `ZmqxM.open`), then convert low-risk frame/helper tests (`ZmqClientAckFrames`, `ZmqWorkerFrames`, targeted LogIngest DEALER helpers, worker-log router helper) to `Zmqx.Monad` bind/connect/send/receive wrappers while preserving existing `unwrap` assertions. Broker/worker runtime loops stay for Steps 2-3; demo `ZmqXT` can remain outside low-risk tests until direct-call exception sweep.
- Step 2 plan before review: convert only bind/connect/open-adjacent service setup calls in `LBS.LogIngest`, `LBS.TaskProcessor`, `LBS.SocketLayer`, `LBW`, and `LBW.LogTransport` from direct `Zmqx.bind`/`Zmqx.connect` to `ZmqxM.bind`/`ZmqxM.connect`; keep socket options in `liftIO`, keep `zmqUnwrap` around `Either Error`, and defer `poll`/`sends`/`receives` body conversions to Step 3.
- Step 3 plan before review: convert `Zmqx.poll`/`pollFor`, `sends`, `receives`, `receivesFor`, and simple `send` uses to `ZmqxM.*` in core runtime loops and already-monadic tests/demos; leave `Zmqx.EventLoop.*` calls and socket option/subscription APIs unchanged; after conversion use grep to document any remaining direct `Zmqx.*` exceptions by category.
- Step 4 test plan before review: first run the required protocol frame/log-protocol suites, then run touched worker/log/lifecycle suites (`test-zmq-worker-frames`, `test-zmq-client-ack-frames`, `test-zmq-log-ingest`, `test-zmq-worker-log-transport`, `test-zmq-worker-wake`, `test-conc-executor` as a terminating lifecycle-adjacent baseline), and finish with `cabal build all --enable-tests`.
- Remaining direct `Zmqx.*` references after Step 3 are intentional exceptions, not global socket operations: `Zmqx.withContext` in app/context runners, `Zmqx.defaultOptions`/`ioThreads` passed to `ZmqxM.runZmqx`, socket type names (`Zmqx.Router`, `Zmqx.Dealer`, etc.), socket option/subscription setup (`setSocketOpt`, `Sub.subscribe`), and existing `Zmqx.EventLoop.*` commands in worker log transport deferred to TP-034. Grep found no remaining direct `Zmqx.open`/`bind`/`connect`/`send(s)`/`receive(s)`/`poll*`/`run` global operations in `lotos/src`, `lotos/test`, or `applications/TaskSchedule`.

| 2026-06-03 09:19 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 09:19 | Step 0 started | Preflight |
| 2026-06-03 | R001 plan Step 1 | APPROVE |
| 2026-06-03 09:22 | Review R001 | plan Step 1: APPROVE |
| 2026-06-03 09:30 | Review R002 | code Step 1: APPROVE |
| 2026-06-03 09:32 | Review R003 | plan Step 2: APPROVE |
| 2026-06-03 09:36 | Review R004 | code Step 2: APPROVE |
| 2026-06-03 09:37 | Review R005 | plan Step 3: APPROVE |
| 2026-06-03 09:42 | Review R006 | code Step 3: APPROVE |
| 2026-06-03 09:43 | Review R007 | plan Step 4: APPROVE |
| 2026-06-03 09:47 | Review R008 | code Step 4: APPROVE |

| 2026-06-03 09:50 | Worker iter 1 | done in 1845s, tools: 143 |
| 2026-06-03 09:50 | Task complete | .DONE created |