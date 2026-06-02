# TP-021: Logging Redesign Architecture — Status

**Current Step:** Step 3: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-02
**Review Level:** 1
**Review Counter:** 2
**Iteration:** 2
**Size:** S

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Document target logging architecture
**Status:** ✅ Complete

- [x] Create `docs/logging-redesign.md` with the selected DEALER/ROUTER batched-ACK design, reliability target, backpressure/drop policy, persistence/cache plan, and API shape.
- [x] Update `docs/lb_sys.drawio` so logging is shown as a separate LogIngest subsystem rather than InfoStorage SUB/PUB.
- [x] Update README or scheduler docs only if they currently imply PUB/SUB logs are the long-term design.

---

### Step 2: Testing & Verification
**Status:** ✅ Complete

- [x] Verify `docs/lb_sys.drawio` is well-formed XML.
- [x] Review documentation for consistency with current code and planned follow-up TPs.

---

### Step 3: Documentation & Delivery
**Status:** ✅ Complete

- [x] Mark logging redesign debt as planned in `taskplane-tasks/CONTEXT.md`.
- [x] Log any design discoveries in STATUS.md.

---

### Final Verification
**Status:** ✅ Complete

- [x] Build/tests/smoke required by PROMPT.md pass
- [x] Documentation requirements satisfied
- [x] Exactly one final TP commit exists

---

## Notes / Discoveries

- TP-021 is documentation-only: runtime still uses worker PUB plus InfoStorage SUB on `infoStorage.loggingAddr`, while the selected target is a separate LogIngest DEALER/ROUTER endpoint.
- Reliability target is at-least-once ingestion with idempotent deduplication, batched ACKs after persistence, bounded worker/broker queues, and explicit visible drop/gap records instead of silent log loss.
- InfoStorage should become an HTTP snapshot/read facade over LogIngest's bounded cache; durable ownership belongs to an append-only LogIngest journal.
- `docs/task-schedule-mvp.md` still describes the current PUB/SUB smoke/runtime contract; it was left unchanged because TP-021's file scope only called out README and `docs/build-your-own-scheduler.md` as conditional adopter-facing updates.

| 2026-06-01 16:23 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 16:23 | Step 0 started | Preflight |
| 2026-06-01 16:27 | Review R001 | plan Step 1: APPROVE |

| 2026-06-01 16:28 | Worker iter 1 | done in 243s, tools: 27 |
| 2026-06-01 16:34 | Review R002 | plan Step 2: APPROVE |

| 2026-06-01 16:39 | Worker iter 2 | done in 704s, tools: 83 |
| 2026-06-01 16:39 | Task complete | .DONE created |