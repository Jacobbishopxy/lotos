# Task: TP-015 - Implement Retry Delay Semantics

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Makes an existing public task field (`taskRetryInterval`) operational in scheduler failure handling. This touches retry queue timing semantics and requires bounded tests to avoid regressions.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
taskplane-tasks/TP-015-implement-retry-delay-semantics/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Implement meaningful retry delay semantics for `taskRetryInterval`. Failed tasks with remaining retries should not become immediately eligible when `taskRetryInterval > 0`; they should become schedulable only after the delay elapses. Preserve immediate retry behavior when the interval is `0` or less, add bounded regression coverage, and update docs.

## Dependencies

- **None**

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `AGENTS.md` — project guidance, protocol invariants, one-TP-one-commit rule
- `taskplane-tasks/CONTEXT.md` — current retry-delay debt
- `docs/task-schedule-mvp.md` — current task JSON/retry docs
- `README.md` — public verification and protocol notes
- `lotos/src/Lotos/Zmq/Adt.hs` — `Task`, retry fields, task status types
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` — failure handling and retry/garbage disposition
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs` — task queue pulling and scheduling eligibility
- `lotos/test/ZmqWorkerFrames.hs` — current retry/failure frame coverage
- `applications/TaskSchedule/test/WorkerLifecycle.hs` — lifecycle/failure tests

## Environment

- **Workspace:** core scheduler/failure handling, tests, docs
- **Services required:** Prefer bounded tests; smoke script for final safety check

## File Scope

- `lotos/src/Lotos/Zmq/Adt.hs`
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs`
- `lotos/test/*`
- `lotos/lotos.cabal` (only if adding a test suite)
- `applications/TaskSchedule/test/*` (only if lifecycle tests are extended)
- `docs/task-schedule-mvp.md`
- `README.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-015-implement-retry-delay-semantics/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Current retry behavior and tests are understood

### Step 1: Design retry-delay model

**Plan-review checkpoint** — review the timing model before implementation.

- [ ] Define eligibility semantics for `taskRetryInterval <= 0`, positive intervals, retry decrement, and garbage after exhaustion
- [ ] Choose where delayed retry metadata lives without breaking JSON/ZMQ task frame compatibility
- [ ] Define bounded tests that do not rely on long sleeps

### Step 2: Implement retry delay behavior

- [ ] Failed tasks with remaining retries are delayed until eligible
- [ ] Immediate retry remains for zero/negative intervals
- [ ] Retry exhaustion still moves to garbage correctly
- [ ] Any helper/API exposure is minimal and documented for TP-016 follow-up if needed

### Step 3: Testing & Verification

**Code review checkpoint** — review final retry changes and evidence before completion.

- [ ] `cabal build all --enable-tests` passes
- [ ] `cabal test all` passes
- [ ] `scripts/task-schedule-smoke.sh` passes
- [ ] Bounded tests prove delayed and immediate retry behavior

### Step 4: Documentation & Delivery

- [ ] `docs/task-schedule-mvp.md` documents final retry interval semantics
- [ ] `README.md` protocol notes updated if needed
- [ ] `taskplane-tasks/CONTEXT.md` marks retry-delay debt resolved or records exact follow-up
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `docs/task-schedule-mvp.md` — retry interval semantics
- `taskplane-tasks/CONTEXT.md` — retry debt status

**Check If Affected:**
- `README.md` — protocol notes if public behavior changed

## Completion Criteria

- [ ] `taskRetryInterval` has tested behavior
- [ ] Immediate retry compatibility is preserved
- [ ] Build, regression tests, and smoke pass

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-015` and Lore trailers.

## Do NOT

- Change `ToZmq`/`FromZmq` frame ordering incompatibly
- Add dependencies
- Use long sleep-based tests when a bounded clock/eligibility helper can prove behavior

---

## Amendments (Added During Execution)
