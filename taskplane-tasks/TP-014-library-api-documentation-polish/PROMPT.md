# Task: TP-014 - Library API Documentation Polish

**Created:** 2026-06-01
**Size:** M

## Review Level: 1 (Plan Only)

**Assessment:** Improves user-facing docs and examples for the now-working library/demo API. Mostly documentation/Haddocks; lower code risk unless examples reveal small compile issues.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-014-library-api-documentation-polish/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Make `lotos` understandable as a reusable library, not only as the TaskSchedule demo. Add or improve documentation/Haddocks/examples for `LoadBalancerAlgo`, `TaskAcceptor`, `StatusReporter`, task/config types, protocol invariants, and safe verification commands.

## Dependencies

- **Task:** TP-011 (protocol coverage baseline)
- **Task:** TP-012 (failure/lifecycle semantics clarified)
- **Task:** TP-013 (info/logging stance clarified)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `README.md` — main project documentation
- `docs/task-schedule-mvp.md` — demo contract and smoke status
- `lotos/src/Lotos/Zmq.hs` — public facade exports
- `lotos/src/Lotos/Zmq/Adt.hs` — task/protocol types
- `lotos/src/Lotos/Zmq/Config.hs` — config types/readers
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs` — `LoadBalancerAlgo`
- `lotos/src/Lotos/Zmq/LBW.hs` — `TaskAcceptor` and `StatusReporter`
- `applications/TaskSchedule/src/Server.hs` — concrete scheduler example
- `applications/TaskSchedule/src/Worker.hs` — concrete worker example

## Environment

- **Workspace:** docs and public API comments
- **Services required:** None

## File Scope

- `README.md`
- `docs/*`
- `lotos/src/Lotos/Zmq.hs`
- `lotos/src/Lotos/Zmq/Adt.hs`
- `lotos/src/Lotos/Zmq/Config.hs`
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs`
- `lotos/src/Lotos/Zmq/LBW.hs`
- `applications/TaskSchedule/src/Server.hs`
- `applications/TaskSchedule/src/Worker.hs`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-014-library-api-documentation-polish/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-011, TP-012, and TP-013 completion status understood

### Step 1: Plan docs/API polish

**Plan-review checkpoint** — review docs outline before editing many files.

- [ ] Identify missing public API explanations and examples
- [ ] Decide where docs belong: README vs Haddocks vs `docs/` reference
- [ ] Define verification for documentation/code examples

### Step 2: Apply documentation polish

- [ ] Add concise Haddocks for main extension points and config/task types
- [ ] Improve README/docs with minimal library usage example or pointers to TaskSchedule
- [ ] Document protocol invariants and verification commands without duplicating stale details

### Step 3: Testing & Verification

- [ ] `cabal build all --enable-tests` passes
- [ ] `cabal test all` passes
- [ ] Documentation links/commands are checked for accuracy

### Step 4: Documentation & Delivery

- [ ] Context debt updated with any remaining docs/API follow-up
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `README.md` — library usage/docs polish
- Relevant Haddocks in public API modules

**Check If Affected:**
- `docs/task-schedule-mvp.md` — if demo details are referenced
- `taskplane-tasks/CONTEXT.md` — docs debt status

## Completion Criteria

- [ ] A new developer can identify extension points and run the demo from docs
- [ ] Public API docs explain the key typeclasses/config/task invariants
- [ ] Build and regression tests pass

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-014` and Lore trailers.

## Do NOT

- Refactor production behavior just for documentation aesthetics
- Add dependencies
- Duplicate large stale examples across multiple docs

---

## Amendments (Added During Execution)
