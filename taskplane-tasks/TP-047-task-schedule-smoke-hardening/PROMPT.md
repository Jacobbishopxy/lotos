# Task: TP-047 - End-to-end TaskSchedule smoke hardening

**Created:** 2026-06-04
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** This touches smoke scripts, demo config expectations, and operational docs across broker/worker/client runtime behavior. It adapts existing smoke patterns without changing core protocol semantics.
**Score:** 4/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-047-task-schedule-smoke-hardening/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Harden the TaskSchedule end-to-end smoke scripts so the recent EventLoop, LogIngest, capacity, reservation, and compatibility work is proven by deterministic operator-friendly checks. The smoke path should validate dispatch, configured worker capacity, reservation-safe scheduling, worker log ingestion, broker `/info` runtime queue stats, and `/logs/stats` without coupling log traffic to task/status traffic.

## Dependencies

- **Task:** TP-046 (protocol compatibility/versioning policy is complete)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `scripts/task-schedule-smoke.sh` — single-worker smoke baseline
- `scripts/task-schedule-multi-worker-smoke.sh` — multi-worker smoke baseline
- `docs/book/lotos/src/operations.md` — operator-facing runbook
- `docs/book/lotos/src/verification.md` — verification command docs
- `docs/book/lotos/src/task-schedule.md` — TaskSchedule behavior docs

## Environment

- **Workspace:** repository root
- **Services required:** Smoke scripts start/stop local broker, worker, and client processes themselves

## File Scope

- `scripts/task-schedule-smoke.sh`
- `scripts/task-schedule-multi-worker-smoke.sh`
- `docs/book/lotos/src/operations.md`
- `docs/book/lotos/src/verification.md`
- `docs/book/lotos/src/task-schedule.md`
- `README.md`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied

### Step 1: Characterize current smoke assertions

- [ ] Run or dry-read both smoke scripts to list current proof points and flake-prone waits
- [ ] Identify checks missing for capacity, reservations, `/info.runtimeQueueStats`, and `/logs/stats`
- [ ] Preserve existing fresh-marker and per-worker execution evidence semantics
- [ ] Run targeted shell syntax checks: `bash -n scripts/task-schedule-smoke.sh scripts/task-schedule-multi-worker-smoke.sh`

**Artifacts:**
- `scripts/task-schedule-smoke.sh` (modified if needed)
- `scripts/task-schedule-multi-worker-smoke.sh` (modified if needed)

### Step 2: Harden deterministic runtime evidence

- [ ] Add bounded retry helpers or reuse existing ones for HTTP and log-stat checks without introducing sleeps that hide failures
- [ ] Validate broker `/info` includes runtime queue stats without requiring nonzero backlog
- [ ] Validate `/logs/stats` remains LogIngest accounting and does not replace runtime queue stats
- [ ] Validate multi-worker capacity/reservation behavior using existing checked-in configs or generated configs
- [ ] Run targeted smoke: `scripts/task-schedule-smoke.sh`
- [ ] Run targeted smoke: `scripts/task-schedule-multi-worker-smoke.sh`

**Artifacts:**
- `scripts/task-schedule-smoke.sh` (modified)
- `scripts/task-schedule-multi-worker-smoke.sh` (modified)

### Step 3: Document smoke gates for operators

- [ ] Update verification docs with the strengthened smoke proof points
- [ ] Update operations docs with where to inspect `/info.runtimeQueueStats` and `/logs/stats`
- [ ] Update README only if the top-level quick verification list changes

**Artifacts:**
- `docs/book/lotos/src/verification.md` (modified)
- `docs/book/lotos/src/operations.md` (modified)
- `README.md` (modified if needed)

### Step 4: Testing & Verification

- [ ] Run FULL build gate: `cabal build all --enable-tests`
- [ ] Run smoke gate: `scripts/task-schedule-smoke.sh`
- [ ] Run smoke gate: `scripts/task-schedule-multi-worker-smoke.sh`
- [ ] Run docs gate: `make book-build`
- [ ] Fix all failures

### Step 5: Documentation & Delivery

- [ ] "Must Update" docs modified
- [ ] "Check If Affected" docs reviewed
- [ ] Discoveries logged in STATUS.md and taskplane context if future work remains

## Documentation Requirements

**Must Update:**
- `docs/book/lotos/src/verification.md` — strengthened smoke gate and expected evidence
- `docs/book/lotos/src/operations.md` — runtime queue/log-stat observability pointers

**Check If Affected:**
- `README.md` — update if top-level verification commands change
- `docs/book/lotos/src/task-schedule.md` — update if smoke behavior documents TaskSchedule semantics
- `taskplane-tasks/CONTEXT.md` — log discoveries or follow-up debt

## Completion Criteria

- [ ] Both smoke scripts are deterministic and fail with useful diagnostics
- [ ] Smoke verifies task dispatch, capacity/reservations, LogIngest stats, and runtime queue stats
- [ ] `cabal build all --enable-tests`, both smoke scripts, and `make book-build` pass

## Git Commit Convention

Commits happen at **step boundaries** (not after every checkbox). All commits for this task MUST include the task ID for traceability.

## Do NOT

- Claim exactly-once logging delivery
- Couple worker logging traffic/backpressure to task/status backend traffic
- Reorder ZMQ multipart frames
- Add dependencies
- Skip smoke verification

---

## Amendments (Added During Execution)
