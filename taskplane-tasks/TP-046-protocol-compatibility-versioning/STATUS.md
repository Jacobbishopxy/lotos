# TP-046: Document and test protocol compatibility/versioning policy — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-04
**Review Level:** 2
**Review Counter:** 7
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Define compatibility policy
**Status:** ✅ Complete

- [x] Plan-review checkpoint — define append-only payload rules, old-frame fallback expectations, frame-order test requirements, and compatibility-break criteria.
- [x] Identify all current protocol payloads with positional decoding and note which have compatibility fallbacks.
- [x] Decide whether to add version tags now or explicitly defer them.
- [x] Revision R001: Add protocol payload inventory with fallback status to the Step 1 plan.

---

### Step 2: Harden tests/docs
**Status:** ✅ Complete

- [x] Add or improve tests for WorkerState old/new frame decoding and any other append-only payloads.
- [x] Add mdBook protocol compatibility chapter with examples and do/don’t guidance.
- [x] Update README protocol invariant summary.

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review policy/test alignment.
- [x] Run protocol/frame tests and TaskSchedule scheduler tests.
- [x] Run `cabal build all --enable-tests`.

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `taskplane-tasks/CONTEXT.md` with compatibility policy status.
- [x] Record remaining unversioned protocol risks.
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

- Step 1 plan: document positional multipart frames as stable wire ABI; allow compatible changes only by appending payload frames at the tail of a payload and adding a `FromZmq` fallback for the previous exact frame count. Route/envelope/discriminator frames and existing payload frame order are not reorderable. Every `ToZmq`/`FromZmq` payload shape should have regression coverage for frame order; append-only changes need tests for both new and old frame counts. Deliberate breaks require a new discriminator/endpoint/versioned payload plus docs/release notes rather than silently changing existing decoders. Version tags are deferred for now because current peers use discriminators and fixed endpoints; add them only when an incompatible alternate protocol must coexist.
- Current protocol payload inventory for Step 1: core scalar/discriminator payloads `()`, `Ack`, `TaskStatus`, `WorkerMsgType`, `LogStream`, `LogLevel`, and `LogDropPolicy` require exact current frame shapes and have no fallback; core composite payloads `Task t`, `RouterFrontendIn/Out`, `RouterBackendOut`, `RouterBackendIn`, `WorkerReportStatus`, `WorkerReportTaskStatus`, `Notify`, `WorkerLogging`, `LogEvent`, `LogBatch`, and `LogAck` decode by position with no old-frame fallback; variable-length `Task t`, `WorkerReportStatus`, `Notify`, `LogBatch`, and `LogAck` are extensible only through their nested/count-delimited tails, not by changing existing prefix frames. TaskSchedule `WorkerState` is the only current payload with an explicit fallback, accepting both the current 9-frame shape and the old 8-frame shape with `taskCapacity = 1`; TaskSchedule `ClientTask` requires its exact 2-frame shape. Route/envelope/discriminator frames are separate from application payload tails and are compatibility-breaking if reordered or removed.
- Step 2 plan: add TaskSchedule scheduler/frame tests that assert `WorkerState` serializes the current 9-frame shape and decodes the old 8-frame shape as `taskCapacity = 1`; add/extend protocol tests for other positional payloads where existing tests cover frame order but not compatibility policy wording. Add `docs/book/lotos/src/protocol-compatibility.md` and link it from `SUMMARY.md`; include append-only examples, route/envelope/discriminator do/don't guidance, explicit break criteria, and version-tag deferral. Update README with a concise protocol invariant and point readers to the mdBook chapter.
- Step 2 targeted verification: `cabal test TaskSchedule:test:test-scheduler` passed after the WorkerState frame-order/fallback test was tightened.
- Step 3 code-review checkpoint: R005 approved the Step 2 policy/test/doc alignment before the full verification gate.
- Step 3 protocol/frame verification passed: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-log-protocol-config TaskSchedule:test:test-scheduler`.
- Step 3 full build verification passed: `cabal build all --enable-tests`.
- Remaining unversioned protocol risk: protocol-wide version tags are intentionally deferred; most payloads still require exact current frame shapes, so any future incompatible coexistence must use a new discriminator, endpoint, or versioned payload instead of silently broadening positional decoders.

| 2026-06-04 06:26 | Task started | Runtime V2 lane-runner execution |
| 2026-06-04 06:26 | Step 0 started | Preflight |
| 2026-06-04 06:29 | Review R001 | plan Step 1: REVISE |
| 2026-06-04 06:31 | Review R002 | plan Step 1: APPROVE |
| 2026-06-04 06:33 | Review R003 | code Step 1: APPROVE |
| 2026-06-04 06:35 | Review R004 | plan Step 2: APPROVE |
| 2026-06-04 06:39 | Review R005 | code Step 2: APPROVE |
| 2026-06-04 06:41 | Review R006 | plan Step 3: APPROVE |
| 2026-06-04 06:45 | Review R007 | code Step 3: APPROVE |

| 2026-06-04 06:48 | Worker iter 1 | done in 1296s, tools: 121 |
| 2026-06-04 06:48 | Task complete | .DONE created |