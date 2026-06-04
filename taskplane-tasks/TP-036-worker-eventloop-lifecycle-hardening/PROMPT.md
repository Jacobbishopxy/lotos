# Task: TP-036 - Harden worker EventLoop lifecycle and failure behavior

**Created:** 2026-06-03
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** This focuses on failure semantics after worker EventLoop migration. It is cross-cutting inside the worker runtime but should not alter public protocol frames.
**Score:** 5/8 — Blast radius: 1, Pattern novelty: 2, Security: 0, Reversibility: 2

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-036-worker-eventloop-lifecycle-hardening/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Harden worker EventLoop shutdown, stopped-loop, broker disconnect, and `ETERM` behavior so backend and logging EventLoops fail predictably without corrupting task execution state.

## Dependencies

- **Task:** TP-035 (worker backend EventLoop migration)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — confirm current `Zmqx.Monad` API details.
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — confirm current EventLoop ownership and mailbox APIs when this task touches EventLoop.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** Worker runtime and tests; no production services required.

## File Scope

- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/src/Lotos/Zmq/LBW/LogTransport.hs`
- `lotos/src/Lotos/Zmq/Internal/WorkerRuntime.hs`
- `lotos/test/*Worker*.hs`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Inventory worker EventLoop failure modes

- [ ] Plan-review checkpoint — enumerate stopped-loop, callback exception, mailbox full, broker disconnect, and context termination paths.
- [ ] Decide which failures are logged/retried, which terminate loops, and which are safe no-ops.
- [ ] Map failure modes to tests.

### Step 2: Implement lifecycle guards

- [ ] Add bounded handling for stopped-loop and `ETERM` errors in backend/log EventLoop command paths.
- [ ] Ensure worker task execution can finish or report failure predictably when transport loops stop.
- [ ] Avoid coupling logging failures to task/status backend progress.

### Step 3: Add regression coverage

- [ ] Add tests or harnesses for backend EventLoop stopped-loop behavior and logging EventLoop stopped-loop behavior.
- [ ] Verify mailbox-full/drop accounting remains visible for logs and does not apply to task/status semantics unless explicitly designed.
- [ ] Confirm forked app actions do not outlive context teardown in tests.

### Step 4: Testing & Verification

- [ ] Code review checkpoint — review lifecycle and failure semantics.
- [ ] Run worker frame/wake/log transport tests.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run smoke scripts if runtime loops changed materially.

### Step 5: Documentation & Delivery

- [ ] Update `taskplane-tasks/CONTEXT.md` with worker EventLoop lifecycle guarantees and gaps.
- [ ] Record any remaining lifecycle debt in STATUS.md.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — record worker EventLoop lifecycle guarantees/gaps.

**Check If Affected:**
- `docs/logging-redesign.md` — update if log failure semantics change.

## Completion Criteria

- [ ] All steps complete
- [ ] All tests passing with evidence recorded in STATUS.md
- [ ] Protocol frame ordering preserved or explicitly covered by regression tests
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Commits happen at **step boundaries** (not after every checkbox). The final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-036: Harden worker EventLoop lifecycle and failure behavior`

## Do NOT

- Expand scope into unrelated feature work; log follow-ups in `taskplane-tasks/CONTEXT.md`
- Claim exactly-once logging delivery
- Change ZMQ multipart frame ordering without explicit regression coverage
- Couple worker logging backpressure to task/status backend traffic
- Commit a final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
