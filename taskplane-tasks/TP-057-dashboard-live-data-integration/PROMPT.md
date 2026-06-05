# Task: TP-057 - Dashboard live data integration

**Created:** 2026-06-05
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Wires a new frontend to existing read-only HTTP endpoints and dev proxy behavior. It touches frontend runtime behavior and Makefile/docs but not backend protocol or writes.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-057-dashboard-live-data-integration/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Connect the dashboard created by TP-056 to the existing TaskSchedule read-only HTTP API. The dashboard should poll `/SimpleServer/info`, `/worker_stats`, `/worker_tasks`, `/tasks`, and `/logs/stats` through a configurable API base or Vite dev proxy, render live data when available, and fall back to useful sample/offline state when the server is not running. Preserve the light Linear-inspired style.

## Dependencies

- **Task:** TP-056 (dashboard app foundation)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `applications/dashboard/*` — dashboard foundation from TP-056
- `docs/book/lotos/src/operations.md` — endpoint definitions and jq probes
- `docs/book/lotos/src/runtime-failures.md` — diagnostic field semantics
- `scripts/task-schedule-smoke.sh` — current endpoint evidence names
- `scripts/task-schedule-multi-worker-smoke.sh` — capacity/reservation evidence names

## Environment

- **Workspace:** repository root
- **Services required:** Optional local TaskSchedule server for manual testing; app must still build without services.

## File Scope

- `applications/dashboard/*`
- `Makefile`
- `README.md`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied

### Step 1: API client and data model

- [ ] Add typed API/data modules for `/info`, `/worker_stats`, `/worker_tasks`, `/tasks`, and `/logs/stats`
- [ ] Add configurable API base/dev proxy behavior appropriate for Vite
- [ ] Preserve offline/sample data fallback for build and no-server local preview

**Artifacts:**
- `applications/dashboard/*`

### Step 2: Live dashboard rendering

- [ ] Render heartbeat age, stale state, reservations, queue overload status, worker capacity, task queues, and LogIngest stats from live data
- [ ] Add loading/error/offline indicators that are clear but non-disruptive
- [ ] Keep layout responsive and light themed

**Artifacts:**
- `applications/dashboard/*`

### Step 3: Makefile/README integration

- [ ] Add or refine Make targets for dashboard development against default `http://127.0.0.1:8081`
- [ ] Document the expected backend service prerequisites and fallback mode
- [ ] Keep `make help` aligned

### Step 4: Testing & Verification

- [ ] Run `make dashboard-build`
- [ ] Run `make help`
- [ ] If practical, run a smoke helper then manually confirm the dashboard can fetch via configured API base or dev proxy
- [ ] Fix all failures

### Step 5: Documentation & Delivery

- [ ] "Must Update" docs modified
- [ ] "Check If Affected" docs reviewed
- [ ] Discoveries logged in STATUS.md and `taskplane-tasks/CONTEXT.md` if future work remains

## Documentation Requirements

**Must Update:**
- `README.md` — dashboard live data usage
- `Makefile` — targets/env names if changed

**Check If Affected:**
- `docs/book/lotos/src/operations.md` — update only if endpoint usage guidance changes
- `taskplane-tasks/CONTEXT.md` — log follow-ups

## Completion Criteria

- [ ] Dashboard builds and can operate with offline sample data
- [ ] Dashboard fetches read-only TaskSchedule API data when available
- [ ] No write/control actions added
- [ ] Make targets and README explain local usage

## Git Commit Convention

Commits happen at step boundaries. All commits for this task MUST include `TP-057` for traceability.

## Do NOT

- Do not add write/control buttons or mutate broker state
- Do not change ZMQ protocol frames
- Do not require a live server for `make dashboard-build`
- Do not switch away from the user-requested light theme

---

## Amendments (Added During Execution)
