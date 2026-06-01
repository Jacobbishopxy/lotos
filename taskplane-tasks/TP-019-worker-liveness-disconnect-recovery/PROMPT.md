# Task: TP-019 - Worker Liveness and Disconnect Recovery

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Adds broker-side recovery semantics for stale/dead workers and in-flight tasks. It touches scheduler state transitions and retry/failure handling, so it needs bounded tests and careful smoke preservation.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
taskplane-tasks/TP-019-worker-liveness-disconnect-recovery/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Implement worker liveness/disconnect recovery so tasks assigned to stale/dead workers do not remain stuck indefinitely. The broker should detect stale worker status, remove stale workers from scheduling consideration, and requeue or dispose of in-flight tasks assigned to stale workers according to existing retry/garbage semantics.

## Dependencies

- **None**

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `AGENTS.md` — project rules, protocol invariants, one-TP-one-commit rule
- `README.md` — current runtime, smoke, and protocol notes
- `docs/task-schedule-mvp.md` — current TaskSchedule runtime contract and smoke evidence
- `docs/build-your-own-scheduler.md` — adopter-facing behavior expectations
- `lotos/src/Lotos/Zmq/Adt.hs` — `AliveSensor` TODO, task/status types, worker maps
- `lotos/src/Lotos/Zmq/Config.hs` — broker/task processor/info storage config types
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` — worker status/task maps, failure/retry handling
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs` — scheduling loop and worker status usage
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs` — worker status observability
- `lotos/src/Lotos/Zmq/Internal/Retry.hs` — retry disposition helpers
- `lotos/test/ZmqWorkerFrames.hs` — bounded broker/frame tests
- `scripts/task-schedule-smoke.sh` and `scripts/task-schedule-multi-worker-smoke.sh` — smoke gates to preserve

## Environment

- **Workspace:** broker liveness/retry logic, tests, docs
- **Services required:** Prefer bounded tests; run existing smoke scripts for final safety

## File Scope

- `lotos/src/Lotos/Zmq/Adt.hs`
- `lotos/src/Lotos/Zmq/Config.hs`
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs`
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs`
- `lotos/src/Lotos/Zmq/Internal/Retry.hs`
- `lotos/test/*`
- `lotos/lotos.cabal` (only if adding a test suite)
- `README.md`
- `docs/task-schedule-mvp.md`
- `docs/build-your-own-scheduler.md` (only if user-facing behavior changes)
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-019-worker-liveness-disconnect-recovery/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Current liveness-related TODOs and worker/task state maps are understood

### Step 1: Design liveness and recovery semantics

**Plan-review checkpoint** — review the recovery model before implementation.

- [ ] Define how the broker determines worker staleness without long sleeps in tests
- [ ] Define how stale worker statuses are removed from scheduling consideration
- [ ] Define how in-flight tasks assigned to stale workers are requeued, delayed, retried, or sent to garbage
- [ ] Define bounded tests and smoke/manual evidence

### Step 2: Implement recovery logic

- [ ] Add broker-side stale worker detection/recovery helper(s)
- [ ] Remove stale workers from worker status/task maps at the correct point in the loop
- [ ] Requeue/dispose in-flight tasks using existing retry-delay/garbage semantics
- [ ] Preserve healthy worker scheduling and current smoke behavior

### Step 3: Testing & Verification

**Code review checkpoint** — review recovery code and evidence before completion.

- [ ] `cabal build all --enable-tests` passes
- [ ] `cabal test all` passes
- [ ] `scripts/task-schedule-smoke.sh` passes
- [ ] `scripts/task-schedule-multi-worker-smoke.sh` passes
- [ ] Bounded tests prove stale worker task recovery without long sleeps

### Step 4: Documentation & Delivery

- [ ] README/docs document worker liveness behavior if user-facing
- [ ] `taskplane-tasks/CONTEXT.md` updated with resolved/new liveness debt
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — resolved/new liveness debt

**Check If Affected:**
- `README.md` — protocol/runtime invariants if liveness is public behavior
- `docs/task-schedule-mvp.md` — smoke/runtime notes if behavior is observable
- `docs/build-your-own-scheduler.md` — adopter notes if configs/semantics change

## Completion Criteria

- [ ] Stale/dead worker tasks are not stuck indefinitely
- [ ] In-flight stale-worker tasks follow retry/garbage semantics
- [ ] Healthy single-worker and multi-worker smokes still pass
- [ ] Build and bounded regression tests pass

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-019` and Lore trailers.

## Do NOT

- Add dependencies
- Use long sleep-based tests when fixed-clock helpers can prove behavior
- Break multipart frame ordering
- Hide recovery failures by weakening smoke assertions

---

## Amendments (Added During Execution)
