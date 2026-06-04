# Task: TP-046 - Document and test protocol compatibility/versioning policy

**Created:** 2026-06-04
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Mostly documentation and regression-test hardening, with possible small helpers. It protects future changes to positional multipart frames.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-046-protocol-compatibility-versioning/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Codify how lotos handles positional ZMQ protocol evolution, including append-only payload changes like `WorkerState.taskCapacity`, old-frame decoding, and when a deliberate compatibility break is allowed.

## Dependencies

- **Task:** TP-045 (logging compatibility cleanup complete)

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

- `lotos/src/Lotos/Zmq/Adt.hs`
- `applications/TaskSchedule/src/Adt.hs`
- `lotos/test/*`
- `applications/TaskSchedule/test/*`
- `docs/book/lotos/src/*`
- `README.md`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Define compatibility policy

- [ ] Plan-review checkpoint — define append-only payload rules, old-frame fallback expectations, frame-order test requirements, and compatibility-break criteria.
- [ ] Identify all current protocol payloads with positional decoding and note which have compatibility fallbacks.
- [ ] Decide whether to add version tags now or explicitly defer them.

### Step 2: Harden tests/docs

- [ ] Add or improve tests for WorkerState old/new frame decoding and any other append-only payloads.
- [ ] Add mdBook protocol compatibility chapter with examples and do/don’t guidance.
- [ ] Update README protocol invariant summary.

### Step 3: Testing & Verification

- [ ] Code review checkpoint — review policy/test alignment.
- [ ] Run protocol/frame tests and TaskSchedule scheduler tests.
- [ ] Run `cabal build all --enable-tests`.

### Step 4: Documentation & Delivery

- [ ] Update `taskplane-tasks/CONTEXT.md` with compatibility policy status.
- [ ] Record remaining unversioned protocol risks.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `docs/book/lotos/src/protocol-compatibility.md` — protocol evolution policy.
- `README.md` — concise invariant update.
- `taskplane-tasks/CONTEXT.md` — record policy status.

**Check If Affected:**
- `docs/task-schedule-mvp.md` — update WorkerState compatibility note if needed.

## Completion Criteria

- [ ] All steps complete
- [ ] Tests/build/smoke evidence recorded in STATUS.md
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-046: Document and test protocol compatibility/versioning policy`

## Do NOT

- Change ZMQ multipart frame ordering without explicit tests and documented compatibility reasoning
- Convert no-drop task/status queues into dropping queues unless the prompt explicitly allows it
- Claim exactly-once logging delivery
- Add non-Cabal build dependencies unless the task explicitly scopes them as optional docs tooling
- Leave final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
