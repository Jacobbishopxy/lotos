# Task: TP-018 - Package and Examples Polish

**Created:** 2026-06-01
**Size:** M

## Review Level: 1 (Plan Only)

**Assessment:** Final adoption polish after behavior and smoke coverage are stable. Mostly docs/examples/package metadata with low production risk.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-018-package-examples-polish/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Polish the repo for a new adopter: package metadata, example guidance, quickstart flow, config samples, and “build your own scheduler” documentation. This should be a final adoption/readiness pass after retry semantics, API boundaries, and multi-worker smoke are settled.

## Dependencies

- **Task:** TP-015 (retry semantics documented)
- **Task:** TP-016 (public API boundary settled)
- **Task:** TP-017 (multi-worker smoke status known)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `README.md` — main project docs
- `docs/task-schedule-mvp.md` — demo runtime contract
- `lotos/lotos.cabal` — package metadata
- `applications/TaskSchedule/TaskSchedule.cabal` — app metadata/examples
- `applications/TaskSchedule/config/*.json` — sample configs
- `applications/TaskSchedule/src/Adt.hs`
- `applications/TaskSchedule/src/Server.hs`
- `applications/TaskSchedule/src/Worker.hs`
- `scripts/*smoke*.sh`

## Environment

- **Workspace:** docs/examples/package metadata
- **Services required:** None except smoke verification if docs mention it

## File Scope

- `README.md`
- `docs/*`
- `lotos/lotos.cabal`
- `applications/TaskSchedule/TaskSchedule.cabal`
- `applications/TaskSchedule/config/*`
- `applications/TaskSchedule/src/*` (comments/examples only unless small compile fix needed)
- `scripts/*`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-018-package-examples-polish/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-015, TP-016, and TP-017 completion status understood

### Step 1: Plan adoption polish

**Plan-review checkpoint** — review docs/examples outline before editing.

- [ ] Identify confusing or stale docs after TP-015 through TP-017
- [ ] Decide whether to add a dedicated quickstart/build-your-own guide or keep README-focused docs
- [ ] Identify package metadata fields or sample configs that need polish

### Step 2: Apply docs/examples/package polish

- [ ] Update README quickstart and library usage flow
- [ ] Update or add concise guide/examples for building a scheduler/worker/client using `lotos`
- [ ] Ensure sample configs and smoke commands are discoverable and accurate
- [ ] Polish package metadata only where it is clearly helpful

### Step 3: Testing & Verification

- [ ] `cabal build all --enable-tests` passes
- [ ] `cabal test all` passes
- [ ] Smoke commands referenced by docs are either run or explicitly identified as optional/manual
- [ ] Links/paths/commands in docs are checked

### Step 4: Documentation & Delivery

- [ ] Context debt updated with any remaining adoption/docs follow-up
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `README.md` — quickstart/adoption polish

**Check If Affected:**
- `docs/task-schedule-mvp.md` — if runtime/smoke docs moved or changed
- `lotos/lotos.cabal` and `applications/TaskSchedule/TaskSchedule.cabal` — metadata only if useful
- `taskplane-tasks/CONTEXT.md` — remaining docs/adoption debt

## Completion Criteria

- [ ] New adopters can run the demo and identify extension points from docs
- [ ] Docs reflect final retry, API, logging, and multi-worker smoke status
- [ ] Build and regression tests pass

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-018` and Lore trailers.

## Do NOT

- Refactor production code for doc aesthetics
- Add dependencies
- Duplicate large examples across multiple docs

---

## Amendments (Added During Execution)
