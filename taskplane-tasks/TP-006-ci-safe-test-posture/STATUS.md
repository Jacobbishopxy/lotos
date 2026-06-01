# TP-006: CI-Safe Test Posture — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-05-31
**Review Level:** 1
**Review Counter:** 3
**Iteration:** 1
**Size:** S

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] TP-005 completion criteria are satisfied

---

### Step 1: Define safe test posture
**Status:** ✅ Complete

- [x] Current test suites classified
- [x] Docs-only vs metadata/script changes decided
- [x] Recommended verification commands defined

---

### Step 2: Apply docs/metadata updates
**Status:** ✅ Complete

- [x] README updated
- [x] MVP contract updated if affected
- [x] Cabal metadata adjusted only if necessary

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all --enable-tests` passes
- [x] `cabal test lotos:test:test-conc-executor` passes
- [x] Smoke status documented

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] Discoveries logged
- [x] Remaining debt appended to context if needed

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | plan | 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| R002 | plan | 2 | APPROVE | `.reviews/R002-plan-step2.md` |
| R003 | plan | 3 | APPROVE | `.reviews/R003-plan-step3.md` |

---

## Discoveries

- 2026-06-01: `test-conc-executor` is the only assertion-based quick regression suite; the other Cabal test suites are demo-style or long-running/server executables and should be built but not run by default CI-safe verification.
- 2026-06-01: TP-006 is docs-only by design; Cabal test metadata remains unchanged so demo suites stay visible while README/MVP docs steer CI-safe commands.

---

## Execution Log

| 2026-05-31 17:28 | Task started | Runtime V2 lane-runner execution |
| 2026-05-31 17:28 | Step 0 started | Preflight |
| 2026-05-31 17:40 | Worker iter 1 | done in 677s, tools: 73 |
| 2026-05-31 17:40 | Task complete | .DONE created |
---

## Blockers

---

## Notes

### Step 3 verification evidence

- `cabal build all --enable-tests` passed on 2026-06-01, compiling `lotos` library, all `lotos` test executables, TaskSchedule libraries, and `ts-server`/`ts-worker`/`ts-client` executables.
- `cabal test lotos:test:test-conc-executor` passed on 2026-06-01: 5 HUnit cases tried, 0 errors, 0 failures; Cabal reported `Test suite test-conc-executor: PASS`.
- Smoke status is documented in README and `docs/task-schedule-mvp.md`: `scripts/task-schedule-smoke.sh` is the bounded MVP smoke command, and current TP-005 evidence is a hard worker-registration failure before client submission due the server worker-status UTF-8 decode blocker.

### Step 3 verification plan

- Run `cabal build all --enable-tests` to compile all packages and test targets without executing demo suites.
- Run `cabal test lotos:test:test-conc-executor` as the safe assertion-based regression command.
- Document TP-005 smoke status from existing evidence instead of rerunning the multi-process helper unless needed; the current smoke status is a bounded command with a known worker-registration blocker before client submission.

### Step 2 documentation update plan

- README: replace/expand the existing "Tests and demos" guidance with a compact CI-safe table covering quick regression, compile-all-tests, intentional MVP smoke, and commands to avoid as defaults; preserve TaskSchedule smoke details and make the current worker-registration blocker explicit.
- MVP contract: add a concise verification posture note near the acceptance script so readers know the smoke helper is bounded but currently exits hard failure before client submission because worker status parsing blocks registration; clarify that exit `2` is only the later ACK-blocker classification after marker proof.
- Cabal metadata: leave unchanged unless documentation work reveals a low-risk metadata-only improvement; current Step 1 decision is docs-only.

### Step 1 proposed safe test posture

- Test suite classification:
  - `lotos:test:test-conc-executor` (`lotos/test/ConcExecutor.hs`) — **regression**. HUnit assertions cover `executeConcurrently` success, failure, callbacks, timeout, and bounded 1–3s concurrent commands; suitable as the quick safe regression command.
  - `lotos:test:test-conc-executor2` (`lotos/test/ConcExecutor2.hs`) — **demo/longer exercise**. No assertions; runs helper scripts with sleeps/timeouts around 5–10s and writes demo output under `../.tmp`; build it with tests but do not recommend as the default regression gate.
  - `lotos:test:test-event-trigger` (`lotos/test/EventTrigger.hs`) — **demo**. Prints trigger timing behavior and sleeps about 10s total without assertions; terminating, but not a regression gate.
  - `lotos:test:test-logger` (`lotos/test/Logger.hs`) — **long-running demo**. Sleeps 10×5s while writing logs; terminating but CI-hostile for quick checks.
  - `lotos:test:test-simple-servant` (`lotos/test/SimpleServant.hs`) — **long-running demo/server**. Starts Warp on port 8080 and does not exit by itself.
  - `lotos:test:test-zmq-xt` (`lotos/test/ZmqXT.hs`) — **long-running demo/server**. Starts ZMQ loops and does not exit by itself.
  - `scripts/task-schedule-smoke.sh` — **MVP smoke**. Bounded multi-process smoke helper from TP-005; should be run intentionally after builds, not by default CI broad test commands.
- Proposed change type: docs-only. Cabal metadata should stay unchanged because disabling/renaming demo suites would hide known behavior and risk changing developer workflows; the safe posture can be expressed by documenting commands and avoiding `cabal test all` as the default.
- Step 2 result: Cabal metadata was intentionally left unchanged after R002 approved the docs-only plan; README and MVP docs now carry the CI-safe posture instead of renaming or disabling existing test suites.
- Recommended commands:
  - Quick regression: `cabal test lotos:test:test-conc-executor`.
  - Compile all components/tests without running demo suites: `cabal build all --enable-tests`.
  - MVP smoke: `scripts/task-schedule-smoke.sh` after the build; interpret exit `0` as full pass, `2` as known ACK-blocker-with-marker proof, and `1` as hard runtime failure. Current TP-005 evidence documents a worker-registration blocker before client submission.
| 2026-05-31 17:32 | Review R001 | plan Step 1: APPROVE |
| 2026-05-31 17:34 | Review R002 | plan Step 2: APPROVE |
| 2026-05-31 17:36 | Review R003 | plan Step 3: APPROVE |
