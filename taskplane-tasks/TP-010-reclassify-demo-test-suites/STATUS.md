# TP-010: Reclassify Demo Test Suites — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 5
**Iteration:** 2
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] TP-009 completion status understood

---

### Step 1: Plan test classification
**Status:** ✅ Complete

- [x] Test suites classified
- [x] Metadata/code strategy decided
- [x] Safe regression/full compile commands preserved

---

### Step 2: Apply test metadata/code/docs changes
**Status:** ✅ Complete

- [x] Cabal/test code updated where practical
- [x] Terminating regression tests remain easy to run
- [x] Docs updated
- [x] Context debt updated
- [x] Fix `demo-conc-executor2` helper paths/failure behavior so the documented repo-root command works
- [x] Update `hie.yaml` cradle mappings for reclassified demo executables and remaining regression tests

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all --enable-tests` passes
- [x] Safe regression command passes
- [x] Demo command status documented

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] README verification section current
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | plan | 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| R002 | plan | 2 | APPROVE | `.reviews/R002-plan-step2.md` |
| R003 | code | 2 | REVISE | `.reviews/R003-code-step2.md` |
| R004 | plan | 3 | APPROVE | `.reviews/R004-plan-step3.md` |
| R005 | code | 3 | APPROVE | `.reviews/R005-code-step3.md` |

---

## Discoveries

| Date | Finding |
|------|---------|
| 2026-06-01 | TP-009 is `✅ Complete`; its final smoke run `.tmp/task-schedule-smoke/tp009-final-20260601T043107Z-241489/` passed with `status=PASS`, client ACK, worker `simpleWorker_1` stats, fresh marker proof, and no current-run garbage entry. |
| 2026-06-01 | After TP-010 reclassification, `cabal test all` is bounded and ran only `test-zmq-client-ack-frames`, `test-zmq-worker-frames`, and `test-conc-executor`; demo/server examples are `lotos:exe:demo-*` components and remain intentionally run via documented commands. |

---

## Execution Log

| 2026-06-01 04:40 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 04:40 | Step 0 started | Preflight |
| 2026-06-01 05:03 | Worker iter 1 | done in 1373s, tools: 86 |
| 2026-06-01 05:03 | Step 3 started | Testing & Verification |
| 2026-06-01 04:48 | Review R001 | plan Step 1: APPROVE |
| 2026-06-01 04:51 | Review R002 | plan Step 2: APPROVE |
| 2026-06-01 05:00 | Review R003 | code Step 2: REVISE |
| 2026-06-01 05:04 | Review R004 | plan Step 3: APPROVE |
| 2026-06-01 05:12 | Review R005 | code Step 3: APPROVE |
| 2026-06-01 05:12 | Step 4 started | Documentation & Delivery |
| 2026-06-01 05:18 | Step 4 completed | Documentation & Delivery |
| 2026-06-01 05:18 | Task completed | All steps complete; final history will be squashed to one TP commit |
| 2026-06-01 05:16 | Worker iter 2 | done in 754s, tools: 64 |
| 2026-06-01 05:16 | Task complete | .DONE created |
---

## Blockers

---

## Notes

### Step 1 proposed test-suite classification

| Cabal component | Source | Classification | Rationale |
|---|---|---|---|
| `test-conc-executor` | `lotos/test/ConcExecutor.hs` | Regression | HUnit assertions cover concurrent process success/failure, callbacks, timeout handling, and bounded concurrent execution; should remain a test suite. |
| `test-zmq-worker-frames` | `lotos/test/ZmqWorkerFrames.hs` | Regression | HUnit protocol-frame assertion with bounded inproc ZMQ receive timeout; should remain a test suite. |
| `test-zmq-client-ack-frames` | `lotos/test/ZmqClientAckFrames.hs` | Regression | HUnit client ACK/envelope assertions with bounded inproc ZMQ receive timeouts; should remain a test suite. |
| `test-conc-executor2` | `lotos/test/ConcExecutor2.hs` | Bounded demo | Prints concurrent executor behavior, writes under `.tmp` from the repository root, uses helper scripts and timeouts, and has no assertions; should not run under default tests. |
| `test-event-trigger` | `lotos/test/EventTrigger.hs` | Bounded demo | Prints timing/trigger behavior, sleeps roughly 11.5 seconds, and has no assertions. |
| `test-logger` | `lotos/test/Logger.hs` | Long-running demo | Writes rotating logs and sleeps roughly 50 seconds without assertions. |
| `test-simple-servant` | `lotos/test/SimpleServant.hs` | Server demo | Starts a Warp server on port 8080 and does not exit by itself. |
| `test-zmq-xt` | `lotos/test/ZmqXT.hs` | Server demo | Starts PUB/SUB/PAIR loops and does not exit by itself. |

### Step 1 proposed metadata/code strategy

- Keep the three bounded assertion suites as Cabal `test-suite` components: `test-conc-executor`, `test-zmq-worker-frames`, and `test-zmq-client-ack-frames`.
- Reclassify the five no-assertion/demo components from `test-suite` stanzas to Cabal `executable` demo components named `demo-conc-executor2`, `demo-event-trigger`, `demo-logger`, `demo-simple-servant`, and `demo-zmq-xt`, still using their existing `lotos/test/*.hs` entry points so the demos remain runnable.
- Tighten `lotos/test/ConcExecutor.hs` so HUnit errors/failures exit non-zero like the newer ZMQ regression suites.
- Update README/MVP docs to recommend `cabal test all` only after the Cabal metadata makes it safe, keep `cabal build all --enable-tests` as the full compile gate, and document demo run commands with `timeout` for server/long-running demos.
- Update `taskplane-tasks/CONTEXT.md` to mark the TP-006 demo-suite debt resolved, with any remaining caveat that demos are executable components rather than default tests.

### Step 1 proposed verification commands

- Full compile gate: `cabal build all --enable-tests` (builds libraries, executables, demo executables, and regression test executables without running demos).
- Safe regression gate after reclassification: `cabal test all` (only assertion-based, bounded test suites remain registered as tests).
- Focused quick regression remains available: `cabal test lotos:test:test-conc-executor`.
- Intentional demo examples: `cabal run lotos:exe:demo-conc-executor2`, `cabal run lotos:exe:demo-event-trigger`, and `timeout 15s cabal run lotos:exe:demo-simple-servant`/`timeout 15s cabal run lotos:exe:demo-zmq-xt` for server loops; docs should say these are demos, not default CI gates.
- Intentional TaskSchedule smoke remains `scripts/task-schedule-smoke.sh` after the full compile gate; TP-009 evidence is green.

### Step 2 implementation notes

- Reclassified the five demo/no-assertion Cabal `test-suite` components as `executable` demos while leaving `test-conc-executor`, `test-zmq-worker-frames`, and `test-zmq-client-ack-frames` as regression tests.
- Updated `test-conc-executor` to exit non-zero when HUnit records errors or failures.
- `cd lotos && cabal check` parsed the revised package description; it still exits non-zero on pre-existing Hackage metadata issues (`synopsis`/`description`, upper bounds), not on Cabal syntax.
- `lotos/lotos.cabal` now exposes the terminating regression suites under the standard `test-suite` stanzas (`test-conc-executor`, `test-zmq-worker-frames`, `test-zmq-client-ack-frames`) so developers can run them through Cabal test targets, while demos are `demo-*` executables.
- README now documents `cabal test all` as the full safe regression gate, preserves `cabal build all --enable-tests` as the compile gate, lists the remaining regression suites, and gives intentional `demo-*` run commands with timeouts for long-lived demos.
- `docs/task-schedule-mvp.md` now notes that TaskSchedule smoke remains intentional and separate from `cabal test all`, and records TP-010 in the MVP implementation status.
- `taskplane-tasks/CONTEXT.md` marks the TP-006 demo-suite debt resolved by the TP-010 Cabal reclassification.

### R003 revision plan

- Fix `demo-conc-executor2` to resolve helper scripts and `.tmp` output from the repository root (or fail clearly before running commands) so the README command is accurate.
- Fixed `demo-conc-executor2` to require repo-root helper scripts before running and to call `scripts/rand.sh`/`scripts/fail.sh` with `.tmp` repo-root output; `timeout 60s cabal run lotos:exe:demo-conc-executor2` passed from the repository root after adding the needed `directory` dependency.
- Update `hie.yaml` so HLS references active Cabal components after demo test suites became `demo-*` executables.
- Updated `hie.yaml` to use file-specific cradles for the three remaining `lotos:test:*` regression suites and five `lotos:exe:demo-*` executable demos; no stale `test-logger`/`test-conc-executor2`/demo-suite test components remain.
- Suggestion logged for Step 3: record the intentional demo command status after the helper-path fix.

### Step 3 verification evidence

- `cabal build all --enable-tests` passed on 2026-06-01, compiling `lotos` library, the three remaining test suites, five `demo-*` executables, and `TaskSchedule` libraries/executables.
- `cabal test all` passed on 2026-06-01; Cabal ran only `test-zmq-client-ack-frames` (2 cases), `test-zmq-worker-frames` (1 case), and `test-conc-executor` (5 cases), all PASS.
- Demo command status documented on 2026-06-01: `timeout 60s cabal run lotos:exe:demo-conc-executor2` passed from the repository root, confirming helper scripts and `.tmp` paths work; `timeout 30s cabal run lotos:exe:demo-event-trigger` passed. Long-running/server demos (`demo-logger`, `demo-simple-servant`, `demo-zmq-xt`) were not run during verification beyond the compile gate because their documented behavior intentionally sleeps or serves indefinitely; README lists timeout-wrapped commands for intentional manual runs.

### Step 4 delivery notes

- README verification section checked on 2026-06-01 after the Step 3 commands passed; updated the `demo-conc-executor2` bullet to say the command should be run from the repository root so helper-script and `.tmp` paths match the verified behavior.
