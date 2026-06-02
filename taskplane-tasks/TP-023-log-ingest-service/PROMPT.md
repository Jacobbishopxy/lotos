# Task: TP-023 - Log Ingest Service and Query API

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Adds a new broker-side service and HTTP API surface. It is a new internal component but can initially run alongside the existing InfoStorage logging path.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-023-log-ingest-service/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Implement the broker-side LogIngest service skeleton using ROUTER/DEALER semantics, batched ACK after ingestion, bounded recent caches, append-only JSONL persistence, and log query endpoints. Keep integration conservative so existing TaskSchedule smoke paths can continue passing while the worker switch is staged separately.

## Dependencies

- **Task:** TP-022 (must complete before this dependent logging redesign stage)

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

- `lotos/src/Lotos/Zmq/LBS/LogIngest.hs`
- `lotos/src/Lotos/Zmq/LBS.hs`
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs`
- `lotos/src/Lotos/Zmq/Config.hs`
- `lotos/src/Lotos/Zmq/Adt.hs`
- `lotos/test/*`
- `lotos/lotos.cabal`
- `docs/logging-redesign.md`
- `taskplane-tasks/TP-023-log-ingest-service/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Design ingestion/storage boundary


- [ ] Plan-review checkpoint — decide LogIngest module API, cache indexes, JSONL file layout, and HTTP route integration.

- [ ] Keep InfoStorage scheduler snapshots lightweight; do not embed full logs in `/info` as the final direction.

- [ ] Define duplicate/sequence-gap/drop accounting behavior.

### Step 2: Implement LogIngest service and tests


- [ ] Add a LogIngest module with bounded per-worker/per-task recent caches and append-only JSONL writer.

- [ ] Add ROUTER receive + LogBatch decode + persist/cache + LogAck send flow.

- [ ] Add `/logs/...` query endpoints or a dedicated log API server route, with task/worker/recent/stats lookups.

- [ ] Add bounded unit tests for cache eviction, duplicate handling, sequence-gap detection, and JSON encoding/API shape.

### Step 3: Testing & Verification


- [ ] Code review checkpoint — review concurrency/resource handling and API shape.

- [ ] Run targeted LogIngest tests.

- [ ] Run `cabal build all --enable-tests` and relevant bounded regression tests.

### Step 4: Documentation & Delivery


- [ ] Update docs with endpoint names, persistence layout, and limitations.

- [ ] Record any worker-side follow-up in STATUS.md/CONTEXT.

## Documentation Requirements

**Must Update:**
- `docs/logging-redesign.md — endpoint/storage details`
- `taskplane-tasks/CONTEXT.md — follow-up status`

**Check If Affected:**
- `README.md`
- `docs/task-schedule-mvp.md`

## Completion Criteria

- [ ] The TP's scoped logging redesign deliverable is complete
- [ ] Existing behavior outside this TP's stage is preserved or intentionally documented
- [ ] Targeted tests/build/smoke listed above pass
- [ ] Documentation and CONTEXT are updated
- [ ] Final history contains exactly one commit for this TP, with Lore trailers

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-023` and Lore trailers.

## Do NOT

- Add third-party dependencies unless explicitly justified and accepted by existing project rules
- Break ZMQ multipart frame ordering for existing messages
- Claim exactly-once log delivery; target at-least-once with idempotent ingestion unless the design explicitly changes
- Leave unbounded log memory growth
- Hide dropped logs or sequence gaps
- Mix changes from a later dependent TP into this TP

---

## Amendments (Added During Execution)
