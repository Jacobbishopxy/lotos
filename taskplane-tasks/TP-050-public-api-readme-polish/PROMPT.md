# Task: TP-050 - Public API/readme polish for first users

**Created:** 2026-06-04
**Size:** M

## Review Level: 1 (Plan Only)

**Assessment:** This is documentation/API guidance polish across README and mdBook with low runtime risk. It should clarify existing APIs rather than change public Haskell surfaces unless tiny export fixes are discovered.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-050-public-api-readme-polish/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Make the project easier for first users by tightening the README, public API guidance, configuration examples, migration notes, and build-your-own scheduler flow. The docs should clearly explain the current trustworthy baseline: explicit context/EventLoop ownership, capacity/reservation scheduling, at-least-once logging ingestion, and protocol compatibility rules.

## Dependencies

- **Task:** TP-049 (CI/local verification profile complete)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `README.md` — top-level first-user guide
- `docs/build-your-own-scheduler.md` — scheduler extension guide
- `docs/book/lotos/src/public-api.md` — public API guide
- `docs/book/lotos/src/compatibility.md` — migration compatibility notes
- `docs/book/lotos/src/task-schedule.md` — demo/scheduler semantics
- `lotos/src/Lotos/Zmq.hs` — facade exports

## Environment

- **Workspace:** repository root docs and facade review
- **Services required:** None

## File Scope

- `README.md`
- `docs/build-your-own-scheduler.md`
- `docs/book/lotos/src/public-api.md`
- `docs/book/lotos/src/compatibility.md`
- `docs/book/lotos/src/task-schedule.md`
- `docs/book/lotos/src/introduction.md`
- `docs/book/lotos/src/SUMMARY.md`
- `lotos/src/Lotos/Zmq.hs`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied

### Step 1: Audit first-user flow

- [ ] Read README and public API docs as a new user and identify unclear setup/config/API paths
- [ ] Check build-your-own scheduler guide against current capacity/reservation APIs
- [ ] Check logging/migration wording for at-least-once semantics and preferred LogIngest names
- [ ] Check `Lotos.Zmq` facade exports only if docs reference missing names

**Artifacts:**
- `README.md` (modified if needed)
- `docs/book/lotos/src/public-api.md` (modified if needed)

### Step 2: Polish quickstart and API docs

- [ ] Clarify build/test/docs/smoke commands using TP-049 profile
- [ ] Clarify minimal broker/worker/client setup and config file names
- [ ] Clarify scheduler extension points, worker capacity, and reservations without exposing internal modules unnecessarily
- [ ] Clarify logging reliability as at-least-once with idempotent ingestion, not exactly-once
- [ ] Make small facade export changes only if documentation reveals a truly missing public API

**Artifacts:**
- `README.md` (modified)
- `docs/book/lotos/src/public-api.md` (modified)
- `docs/build-your-own-scheduler.md` (modified)
- `lotos/src/Lotos/Zmq.hs` (modified only if needed)

### Step 3: Align compatibility and migration notes

- [ ] Ensure legacy logging names, worker-state old-frame fallback, and protocol compatibility policy are cross-linked
- [ ] Ensure docs direct incompatible protocol changes to explicit versioning/new discriminator work
- [ ] Ensure TaskSchedule docs show capacity-aware behavior and smoke verification links

**Artifacts:**
- `docs/book/lotos/src/compatibility.md` (modified)
- `docs/book/lotos/src/task-schedule.md` (modified)
- `docs/book/lotos/src/introduction.md` (modified if needed)

### Step 4: Testing & Verification

- [ ] Run docs gate: `make book-build`
- [ ] Run CI/local docs-aware gate from TP-049: `make ci-check` or equivalent
- [ ] If Haskell exports changed, run `cabal build all --enable-tests`
- [ ] Fix all failures

### Step 5: Documentation & Delivery

- [ ] "Must Update" docs modified
- [ ] "Check If Affected" docs reviewed
- [ ] Discoveries logged in STATUS.md and context if future work remains

## Documentation Requirements

**Must Update:**
- `README.md` — first-user quickstart and verification path
- `docs/book/lotos/src/public-api.md` — current public API guidance
- `docs/build-your-own-scheduler.md` — scheduler capacity/reservation guidance if stale

**Check If Affected:**
- `docs/book/lotos/src/compatibility.md`
- `docs/book/lotos/src/task-schedule.md`
- `docs/book/lotos/src/introduction.md`
- `taskplane-tasks/CONTEXT.md`

## Completion Criteria

- [ ] First-user quickstart is coherent and current
- [ ] Public API/scheduler/logging/compatibility docs agree
- [ ] Docs build and CI/local verification profile pass

## Git Commit Convention

Commits happen at **step boundaries** and MUST include `TP-050`.

## Do NOT

- Add dependencies
- Promise exactly-once log delivery
- Expose internal modules casually as public API
- Change runtime behavior unless a tiny documented export fix is necessary

---

## Amendments (Added During Execution)
