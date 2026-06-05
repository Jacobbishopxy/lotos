# TP-054: Explicit protocol versioning plan — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-05
**Review Level:** 1
**Review Counter:** 4
**Iteration:** 2
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied

---

### Step 1: Assess current state and design
**Status:** ✅ Complete

- [x] Current ZMQ discriminators/routes and golden fixture coverage inventoried
- [x] Versioning decision matrix scope and placement chosen
- [x] Baseline targeted protocol fixture tests run where useful
- [x] README/mdBook cross-link touchpoints identified

---

### Step 2: Implement focused changes
**Status:** ✅ Complete

- [x] Protocol versioning matrix and migration test guidance added to mdBook docs
- [x] README and related mdBook cross-links updated without changing protocol behavior
- [x] Protocol fixture tests reviewed; no decoder widening or frame-order changes introduced
- [x] Targeted protocol tests pass after edits

---

### Step 3: Documentation alignment
**Status:** ✅ Complete

- [x] Must-update docs modified
- [x] Affected docs reviewed
- [x] Follow-up gaps logged if found

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Targeted protocol tests pass: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-log-protocol-config`
- [x] `make ci-check` passes
- [x] `make book-build` passes
- [x] All failures fixed or documented with evidence

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] "Must Update" docs modified
- [x] "Check If Affected" docs reviewed
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | plan | Step 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| R002 | plan | Step 2 | APPROVE | `.reviews/R002-plan-step2.md` |
| R003 | plan | Step 3 | APPROVE | `.reviews/R003-plan-step3.md` |
| R004 | plan | Step 4 | APPROVE | `.reviews/R004-plan-step4.md` |

---

## Notes

| 2026-06-04 16:20 | Task started | Runtime V2 lane-runner execution |
| 2026-06-04 16:20 | Step 0 started | Preflight |
| 2026-06-05 | Inventory | Frontend ClientRequest/ClientAck REQ-ROUTER envelope, backend WorkerStatusT/WorkerTaskStatusT discriminator, TaskStatus enum, legacy WorkerLogging, LogEvent/LogBatch/LogAck counted tails, Notify/Ack, and TaskSchedule WorkerState fallback are covered by exact worker/client/log fixtures plus scheduler WorkerState old-payload tests. |
| 2026-06-05 | Design | Put a concrete versioning decision matrix in `protocol-compatibility.md` after the append-only policy; link it from `zmq-protocol.md`, `compatibility.md`, and the README invariants without adding protocol-wide tags or widening decoders. |
| 2026-06-05 | Baseline tests | `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-log-protocol-config` passed (25, 5, and 10 cases respectively). |
| 2026-06-05 | Cross-links | Update README protocol invariants, `zmq-protocol.md` compatibility rule, and `compatibility.md` protocol frames to point maintainers at the new matrix; `SUMMARY.md` needs no change unless a new page is added. |
| 2026-06-05 | Docs edit | Added the versioning decision matrix and migration test plan to `docs/book/lotos/src/protocol-compatibility.md`. |
| 2026-06-05 | Cross-link edits | Linked README protocol invariants, `zmq-protocol.md`, and `compatibility.md` to the matrix; no runtime protocol behavior changed. |
| 2026-06-05 | Fixture review | Added comments to worker, client ACK, and log protocol fixtures to preserve exact-frame expectations; no decoder or frame-order code changed. |
| 2026-06-05 | Post-edit targeted tests | `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-log-protocol-config` passed after doc/test-comment edits. |
| 2026-06-05 | Docs alignment | Must-update docs touched: README, `protocol-compatibility.md`, `zmq-protocol.md`, and `compatibility.md`; `SUMMARY.md` unchanged because no new page was added. |
| 2026-06-05 | Affected docs reviewed | Reviewed `taskplane-tasks/CONTEXT.md`, README, and mdBook summary; updated context metadata/future-work wording and left `SUMMARY.md` unchanged because links still point to the same page. |
| 2026-06-05 | Follow-up gap | `taskplane-tasks/CONTEXT.md` now records that actual versioned wire surfaces remain future work only when an incompatible payload must coexist. |
| 2026-06-05 | Verification targeted | Step 4 targeted protocol command passed (`test-zmq-worker-frames`, `test-zmq-client-ack-frames`, `test-zmq-log-protocol-config`). |
| 2026-06-05 | Verification ci-check | `make ci-check` passed: compiled all components/tests/demos, ran bounded regression targets, and built the mdBook. |
| 2026-06-05 | Verification book | `make book-build` passed after the documentation edits. |
| 2026-06-05 | Failure review | No verification failures remained; generated `docs/book/lotos/book/` output was removed before delivery. |
| 2026-06-05 | Delivery docs | Must-update docs modified for delivery: README, `protocol-compatibility.md`, `zmq-protocol.md`, and `compatibility.md`. |
| 2026-06-05 | Delivery affected docs | Reviewed `taskplane-tasks/CONTEXT.md`, README, and `docs/book/lotos/src/SUMMARY.md`; context has the TP-054 future-work entry, README links the matrix, and SUMMARY needs no change because no new page was added. |
| 2026-06-05 | Delivery discovery | Logged the remaining protocol-versioning future work in `taskplane-tasks/CONTEXT.md`: add explicit versioned wire surfaces only when incompatible payloads must coexist; no additional doc pages or dependencies were introduced. |
| 2026-06-04 16:23 | Review R001 | plan Step 1: APPROVE |
| 2026-06-04 16:27 | Review R002 | plan Step 2: APPROVE |
| 2026-06-04 16:31 | Review R003 | plan Step 3: APPROVE |
| 2026-06-04 16:34 | Review R004 | plan Step 4: APPROVE |

| 2026-06-04 16:38 | Worker iter 1 | done in 1093s, tools: 105 |

| 2026-06-04 16:41 | Worker iter 2 | done in 157s, tools: 30 |
| 2026-06-04 16:41 | Task complete | .DONE created |