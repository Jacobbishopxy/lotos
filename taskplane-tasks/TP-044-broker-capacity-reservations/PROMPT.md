# Task: TP-044 - Add broker-side capacity reservations between heartbeats

**Created:** 2026-06-04
**Size:** L

## Review Level: 3 (Full)

**Assessment:** Changes scheduling/admission behavior across broker and TaskSchedule tests. It must preserve scheduler extension contracts while preventing over-assignment between heartbeat snapshots.
**Score:** 7/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 3

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-044-broker-capacity-reservations/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Add broker-side reservation accounting so capacity-aware scheduling does not over-assign workers between heartbeat updates, while preserving existing LoadBalancerAlgo extension semantics.

## Dependencies

- **Task:** TP-043 (queue/overload observability available for runtime diagnosis)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `/home/xiey/Code/arcadia-lob/Makefile.toml` — reference style for mdBook build/serve/help command design.
- `Makefile` — existing project command surface.
- `docs/logging-redesign.md` — logging architecture and compatibility context.
- `docs/task-schedule-mvp.md` — TaskSchedule runtime/smoke context.
- `docs/build-your-own-scheduler.md` — scheduler API/adopter context.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** None unless smoke verification steps explicitly start TaskSchedule services.

## File Scope

- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs`
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/src/Lotos/Zmq/Adt.hs`
- `applications/TaskSchedule/src/Server.hs`
- `applications/TaskSchedule/test/Scheduler.hs`
- `lotos/test/*`
- `docs/book/lotos/src/*`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Design reservation model

- [ ] Plan-review checkpoint — decide whether reservations live in worker task map, a new broker map, or adjusted worker snapshots passed to `LoadBalancerAlgo`.
- [ ] Define how reservations are created on dispatch and released on worker status/task-status/stale recovery.
- [ ] Preserve public scheduler API unless a clearly documented extension is required.

### Step 2: Implement reservation accounting

- [ ] Track same-pass and between-heartbeat reservations per worker.
- [ ] Prevent repeated scheduler passes from assigning beyond reported capacity while status has not caught up.
- [ ] Release reservations when task status reports processing/succeed/fail or when stale-worker recovery reclaims tasks.

### Step 3: Add tests

- [ ] Add fixed-clock or deterministic scheduler/TaskProcessor tests for repeated scheduling before heartbeat update.
- [ ] Test reservation release on success/failure/stale recovery.
- [ ] Verify multi-worker capacity fairness remains stable.

### Step 4: Testing & Verification

- [ ] Test-review checkpoint — review over-assignment and release coverage.
- [ ] Run TaskSchedule scheduler tests, worker frame tests, liveness/retry tests.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run single/multi-worker smoke.

### Step 5: Documentation & Delivery

- [ ] Update mdBook architecture/TaskSchedule chapters with heartbeat-vs-reservation behavior.
- [ ] Update known risks in `taskplane-tasks/CONTEXT.md`.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `docs/book/lotos/src/architecture.md` — describe reservation accounting.
- `docs/book/lotos/src/task-schedule.md` — describe capacity semantics.

**Check If Affected:**
- `docs/task-schedule-mvp.md` — update if demo behavior materially changes.

## Completion Criteria

- [ ] All steps complete
- [ ] Tests/build/smoke evidence recorded in STATUS.md
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-044: Add broker-side capacity reservations between heartbeats`

## Do NOT

- Change ZMQ multipart frame ordering without explicit tests and documented compatibility reasoning
- Convert no-drop task/status queues into dropping queues unless the prompt explicitly allows it
- Claim exactly-once logging delivery
- Add non-Cabal build dependencies unless the task explicitly scopes them as optional docs tooling
- Leave final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
