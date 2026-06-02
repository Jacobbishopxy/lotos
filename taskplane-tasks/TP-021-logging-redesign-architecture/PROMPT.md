# Task: TP-021 - Logging Redesign Architecture

**Created:** 2026-06-01
**Size:** S

## Review Level: 1 (Plan Only)

**Assessment:** Defines the target logging architecture and updates the system diagram/roadmap without runtime changes. It touches docs/task tracking only, but sets direction for several implementation TPs.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-021-logging-redesign-architecture/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Refresh the load-balancer architecture documentation so reliable worker logs are treated as a first-class subsystem, not an InfoStorage side channel. Capture the decision to replace PUB/SUB with a separate DEALER/ROUTER log channel using batched ACKs, bounded caches, and append-only persistence.

## Dependencies

- **None**

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `AGENTS.md` — repository rules, especially Cabal verification and 1 TP = 1 commit expectations
- `docs/logging-redesign.md` — logging migration design, once created by TP-021
- `docs/lb_sys.drawio` — current architecture diagram
- `lotos/src/Lotos/Zmq/Adt.hs` — protocol frame contracts
- `lotos/src/Lotos/Zmq/Config.hs` — broker/worker config records
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs` — current logging coupling to replace
- `lotos/src/Lotos/Zmq/LBW.hs` — current worker logging send path

## Environment

- **Workspace:** lotos core library, TaskSchedule demo, and docs as scoped below
- **Services required:** None for implementation; smoke scripts for final verification where listed

## File Scope

- `docs/lb_sys.drawio`
- `docs/logging-redesign.md`
- `docs/build-your-own-scheduler.md`
- `README.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-021-logging-redesign-architecture/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Document target logging architecture


- [ ] Create `docs/logging-redesign.md` with the selected DEALER/ROUTER batched-ACK design, reliability target, backpressure/drop policy, persistence/cache plan, and API shape.

- [ ] Update `docs/lb_sys.drawio` so logging is shown as a separate LogIngest subsystem rather than InfoStorage SUB/PUB.

- [ ] Update README or scheduler docs only if they currently imply PUB/SUB logs are the long-term design.

### Step 2: Testing & Verification


- [ ] Verify `docs/lb_sys.drawio` is well-formed XML.

- [ ] Review documentation for consistency with current code and planned follow-up TPs.

### Step 3: Documentation & Delivery


- [ ] Mark logging redesign debt as planned in `taskplane-tasks/CONTEXT.md`.

- [ ] Log any design discoveries in STATUS.md.

## Documentation Requirements

**Must Update:**
- `docs/logging-redesign.md — new architecture decision and migration plan`
- `docs/lb_sys.drawio — current architecture diagram`

**Check If Affected:**
- `README.md`
- `docs/build-your-own-scheduler.md`

## Completion Criteria

- [ ] The TP's scoped logging redesign deliverable is complete
- [ ] Existing behavior outside this TP's stage is preserved or intentionally documented
- [ ] Targeted tests/build/smoke listed above pass
- [ ] Documentation and CONTEXT are updated
- [ ] Final history contains exactly one commit for this TP, with Lore trailers

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-021` and Lore trailers.

## Do NOT

- Add third-party dependencies unless explicitly justified and accepted by existing project rules
- Break ZMQ multipart frame ordering for existing messages
- Claim exactly-once log delivery; target at-least-once with idempotent ingestion unless the design explicitly changes
- Leave unbounded log memory growth
- Hide dropped logs or sequence gaps
- Mix changes from a later dependent TP into this TP

---

## Amendments (Added During Execution)
