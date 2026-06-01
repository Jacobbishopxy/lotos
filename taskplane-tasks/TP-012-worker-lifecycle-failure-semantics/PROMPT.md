# Task: TP-012 - Worker Lifecycle and Failure Semantics

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Exercises retry/failure/garbage semantics around worker task execution and status handling. It may reveal production defects, but should proceed with bounded tests and minimal fixes.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
taskplane-tasks/TP-012-worker-lifecycle-failure-semantics/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Verify and harden worker lifecycle behavior beyond the happy path: task start/finish statuses, command failure reporting, timeout/failure mapping, retry queue behavior, and garbage-bin behavior after retry exhaustion. Document or implement the smallest fixes needed to make failure semantics trustworthy.

## Dependencies

- **Task:** TP-011 (protocol/frame regression baseline should be in place first)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `docs/task-schedule-mvp.md` — current MVP runtime and smoke behavior
- `scripts/task-schedule-smoke.sh` — green happy-path smoke reference
- `lotos/src/Lotos/Zmq/Adt.hs` — task status and retry fields
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` — failed task/retry/garbage handling
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs` — queue pulling and scheduling behavior
- `lotos/src/Lotos/Zmq/LBW.hs` — worker task execution/status reporting
- `applications/TaskSchedule/src/Worker.hs` — command result to task status path
- `applications/TaskSchedule/src/Util.hs` — command result conversion
- `lotos/test/*` — current bounded regression style

## Environment

- **Workspace:** core scheduler/worker code, tests, smoke tooling if needed
- **Services required:** Prefer bounded tests; local smoke variants only with cleanup/timeouts

## File Scope

- `lotos/test/*`
- `lotos/lotos.cabal`
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs`
- `lotos/src/Lotos/Zmq/LBW.hs`
- `applications/TaskSchedule/src/Worker.hs`
- `applications/TaskSchedule/src/Util.hs`
- `scripts/task-schedule-smoke.sh` (only if adding failure-mode smoke option is justified)
- `docs/task-schedule-mvp.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-012-worker-lifecycle-failure-semantics/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-011 completed and current tests are green

### Step 1: Plan lifecycle/failure coverage

**Plan-review checkpoint** — review selected semantics and test strategy before editing.

- [ ] Identify expected behavior for success, command failure, timeout, retry decrement/requeue, and garbage after exhaustion
- [ ] Identify bounded unit/frame tests vs smoke-style integration checks
- [ ] Define which discovered issues will be fixed now vs documented as follow-up

### Step 2: Implement tests and minimal fixes

- [ ] Add bounded tests for failure/status/retry semantics where practical
- [ ] Patch minimal production defects revealed by tests
- [ ] Preserve existing happy-path smoke behavior

### Step 3: Testing & Verification

**Code review checkpoint** — review final lifecycle changes and evidence before completion.

- [ ] `cabal build all --enable-tests` passes
- [ ] `cabal test all` passes
- [ ] `scripts/task-schedule-smoke.sh` passes
- [ ] Any failure-mode smoke/manual evidence is captured or exact blocker documented

### Step 4: Documentation & Delivery

- [ ] `docs/task-schedule-mvp.md` updated if failure/retry semantics are documented there
- [ ] `taskplane-tasks/CONTEXT.md` updated with resolved/new lifecycle debt
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — resolved/new lifecycle debt

**Check If Affected:**
- `docs/task-schedule-mvp.md` — if user-visible failure/retry behavior is clarified
- `README.md` — only if verification commands change

## Completion Criteria

- [ ] Worker failure/status/retry semantics are covered by bounded tests or exact documented blockers
- [ ] Minimal discovered defects are fixed or follow-up debt is explicit
- [ ] Build, regression tests, and happy-path smoke pass

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-012` and Lore trailers.

## Do NOT

- Rewrite the scheduler architecture
- Add dependencies
- Leave background processes running after smoke/failure checks

---

## Amendments (Added During Execution)
