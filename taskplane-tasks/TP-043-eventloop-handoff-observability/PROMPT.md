# Task: TP-043 - Add overload observability for EventLoop handoff queues

**Created:** 2026-06-04
**Size:** L

## Review Level: 3 (Full)

**Assessment:** Touches worker/broker runtime queues and observability. It should avoid changing no-drop semantics while adding measurable queue-depth/high-water indicators.
**Score:** 6/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 2

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-043-eventloop-handoff-observability/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Add observability for intentionally unbounded task/status EventLoop handoff queues so overload risk is visible without silently dropping protocol-critical work.

## Dependencies

- **Task:** TP-042 (mdBook docs are available for architecture/operations updates)

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

- `lotos/src/Lotos/Zmq/Internal/WorkerRuntime.hs`
- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs`
- `lotos/test/*`
- `docs/book/lotos/src/*`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Inventory unbounded handoff queues

- [ ] Plan-review checkpoint — list worker backend, task-status, SocketLayer frontend/backend/TaskProcessor queues, and any existing bounded LogIngest queue metrics.
- [ ] Choose observable fields: current depth where cheap, high-water marks, and warning thresholds.
- [ ] Define where metrics are exposed: logs, `/info`, `/logs/stats`, or a small broker runtime stats endpoint.

### Step 2: Implement non-dropping metrics

- [ ] Add queue-depth/high-water tracking around enqueue/drain operations without converting protocol-critical queues to dropping/bounded queues.
- [ ] Emit bounded warning logs when high-water thresholds are crossed.
- [ ] Expose enough stats for smoke/manual diagnosis without making info snapshots too heavy.

### Step 3: Add regression coverage

- [ ] Test that enqueue/drain updates high-water metrics.
- [ ] Test that metrics do not change protocol frame ordering or scheduling semantics.
- [ ] Keep existing LogIngest rejected/drop accounting distinct from no-drop task/status metrics.

### Step 4: Testing & Verification

- [ ] Test-review checkpoint — review observability coverage and no-drop invariants.
- [ ] Run worker frame/wake tests and broker SocketLayer frame tests.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run single/multi-worker smoke if info/log stats changed.

### Step 5: Documentation & Delivery

- [ ] Update mdBook operations/architecture pages with overload metrics and their meaning.
- [ ] Update `taskplane-tasks/CONTEXT.md` with remaining overload/backpressure risks.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `docs/book/lotos/src/operations.md` — describe overload indicators and thresholds.
- `taskplane-tasks/CONTEXT.md` — record observability status.

**Check If Affected:**
- `README.md` — mention only if a new endpoint/command is public.

## Completion Criteria

- [ ] All steps complete
- [ ] Tests/build/smoke evidence recorded in STATUS.md
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-043: Add overload observability for EventLoop handoff queues`

## Do NOT

- Change ZMQ multipart frame ordering without explicit tests and documented compatibility reasoning
- Convert no-drop task/status queues into dropping queues unless the prompt explicitly allows it
- Claim exactly-once logging delivery
- Add non-Cabal build dependencies unless the task explicitly scopes them as optional docs tooling
- Leave final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
