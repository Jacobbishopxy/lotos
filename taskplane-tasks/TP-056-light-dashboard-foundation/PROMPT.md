# Task: TP-056 - Light dashboard foundation

**Created:** 2026-06-05
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Adds a new frontend app and Makefile entry points with limited backend impact. Design/system novelty is moderate, no auth/data writes, and changes are reversible.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-056-light-dashboard-foundation/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Create the frontend dashboard foundation for visualizing Lotos/TaskSchedule runtime state. The app must use a **light theme** inspired by the Linear DESIGN.md style: precise typography, near-white canvas, quiet gray hierarchy, hairline borders, restrained cards, and a single lavender-blue primary accent. It should be a Vite + TypeScript app under `applications/dashboard/` with static/sample data only in this task, plus root `make` commands for installing/building/developing the dashboard.

## Dependencies

- **Task:** TP-055 (runtime diagnostics must be complete and pushed)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `README.md` — current quickstart and Makefile guidance
- `Makefile` — existing target style
- `docs/book/lotos/src/start-here.md` — docs navigation pattern
- `docs/book/lotos/src/operations.md` — runtime endpoint terminology
- `examples/minimal-scheduler/README.md` — example package docs style

## Environment

- **Workspace:** repository root
- **Services required:** None. Static dashboard preview/build only.

## File Scope

- `applications/dashboard/*`
- `Makefile`
- `README.md`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied

### Step 1: Design and app skeleton

- [ ] Create `applications/dashboard/` as a Vite + TypeScript app with package metadata and TypeScript config
- [ ] Add `DESIGN.md` or equivalent design notes capturing the light Linear-inspired tokens and dashboard patterns
- [ ] Implement a static dashboard shell: header, endpoint/status strip, worker cards, queue/reservation cards, and logs/status panels using sample data

**Artifacts:**
- `applications/dashboard/*`

### Step 2: Makefile and README wiring

- [ ] Add root `make` targets for dashboard install/build/dev/preview using npm prefix commands
- [ ] Keep `make help` aligned with the new targets
- [ ] Update README with the dashboard location, light theme direction, and build/dev commands

**Artifacts:**
- `Makefile`
- `README.md`

### Step 3: Testing & Verification

- [ ] Run `npm --prefix applications/dashboard install` or equivalent package-lock creation command
- [ ] Run `make dashboard-build`
- [ ] Run `make help`
- [ ] Fix all failures

### Step 4: Documentation & Delivery

- [ ] "Must Update" docs modified
- [ ] "Check If Affected" docs reviewed
- [ ] Discoveries logged in STATUS.md and `taskplane-tasks/CONTEXT.md` if future work remains

## Documentation Requirements

**Must Update:**
- `README.md` — mention dashboard and commands
- `Makefile` — add targets/help

**Check If Affected:**
- `taskplane-tasks/CONTEXT.md` — log follow-up if needed

## Completion Criteria

- [ ] Dashboard app builds successfully
- [ ] Light Linear-inspired visual foundation exists
- [ ] Root Makefile exposes dashboard startup/build commands
- [ ] No backend behavior changed

## Git Commit Convention

Commits happen at step boundaries. All commits for this task MUST include `TP-056` for traceability.

## Do NOT

- Do not add auth, writes, or task-control actions
- Do not change the Haskell info API in this task
- Do not make the dashboard depend on a live server to build
- Do not use a dark/neon-first theme; user explicitly prefers a light theme

---

## Amendments (Added During Execution)
