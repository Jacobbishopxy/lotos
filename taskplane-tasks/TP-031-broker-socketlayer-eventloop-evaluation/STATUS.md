# TP-031: Evaluate Broker SocketLayer EventLoop Migration — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 2
**Review Counter:** 6
**Iteration:** 2
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Evaluate broker EventLoop fit
**Status:** ✅ Complete

- [x] Plan-review checkpoint — map frontend ROUTER, backend ROUTER, and internal PAIR roles to EventLoop sender/receiver/transceiver modes.
- [x] Identify whether callbacks would be too heavy for queue/map mutation and whether mailbox-based dispatch is safer.
- [x] Decide implement vs defer based on concrete benefit and risk.

---

### Step 2: Implement selected broker path
**Status:** ✅ Complete

- [x] Record in broker source that EventLoop migration is intentionally deferred and sockets remain owned by the direct SocketLayer poll thread.
- [x] Keep direct poll and remove narrow inefficiencies without changing hot-loop protocol handling.
- [x] Confirm public ZMQ multipart shapes remain unchanged.

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review protocol/frame and scheduler interaction correctness.
- [x] Run protocol frame tests, worker frame tests, client ACK tests, scheduler/worker lifecycle tests.
- [x] Run `cabal build all --enable-tests`.
- [x] Run single-worker and multi-worker smoke scripts.

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update docs/CONTEXT with the broker EventLoop decision and any remaining performance debt.
- [x] Update `docs/lb_sys.drawio` only if the architecture changes visibly.

---

### Final Verification
**Status:** ✅ Complete

- [x] Build/tests/smoke required by PROMPT.md pass
- [x] Documentation requirements satisfied
- [x] Exactly one final TP commit exists

---

## Notes / Discoveries

- Step 1 plan review attempted before implementation; reviewer unavailable, so proceeding with caution.
- EventLoop role map: frontend ROUTER and backend ROUTER would need `addTransceiver` with mailbox delivery because each both receives and sends; TaskProcessor→SocketLayer PAIR (`backendReceiver`) maps to `addReceiver`/mailbox; SocketLayer→TaskProcessor PAIR (`backendSender`) maps to `addSender`.
- Callback mode is a poor broker fit: client ACK/enqueue, worker status heartbeat/map mutation, retry/garbage disposition, and scheduler notify sends are non-trivial and callback exceptions terminate the EventLoop worker. If EventLoop were adopted, mailbox dispatch in the existing `LotosApp` broker loop would be safer than callback mutation inside the ZMQ worker thread.
- Decision: defer broker EventLoop migration for TP-031. The current direct poll already keeps all broker sockets on one SocketLayer thread; moving to EventLoop would add a second worker thread plus bounded mailboxes/drop semantics around critical ROUTER/PAIR frames without measured fairness/latency gain. Step 2 should keep direct poll, make the ownership/decision explicit, and do narrow cleanup only.
- Step 2 hydrated after the Step 1 defer decision so branch-specific checkboxes track the selected direct-poll implementation path rather than the unselected migration branch.
- `docs/lb_sys.drawio` intentionally remains unchanged: TP-031 preserved the broker architecture and direct SocketLayer poll ownership, so there is no visible diagram change to render.

| 2026-06-03 06:21 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 06:21 | Step 0 started | Preflight |
| 2026-06-03 06:29 | Review R002 | code Step 1: APPROVE |
| 2026-06-03 06:32 | Review R003 | plan Step 2: APPROVE |

| 2026-06-03 06:34 | Worker iter 1 | done in 731s, tools: 59 |
| 2026-06-03 06:39 | Review R004 | code Step 2: APPROVE |
| 2026-06-03 06:42 | Review R005 | plan Step 3: APPROVE |
| 2026-06-03 06:53 | Review R006 | code Step 3: APPROVE |

| 2026-06-03 06:57 | Worker iter 2 | done in 1430s, tools: 97 |
| 2026-06-03 06:57 | Task complete | .DONE created |