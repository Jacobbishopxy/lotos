# Task: TP-032 - Introduce explicit ZMQ context in LotosApp

**Created:** 2026-06-03
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** This changes the application environment and service runners across the library but should preserve socket behavior. It introduces an architectural foundation without changing protocol frames.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-032-introduce-zmqx-monad-context/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Move lotos from hidden global ZMQ context usage toward explicit monadic context ownership by extending the application environment and runner surface. This prepares all later socket and EventLoop migrations while preserving current runtime behavior.

## Dependencies

- **Task:** TP-031 (current EventLoop baseline and broker/worker evaluation decisions integrated)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — confirm current `Zmqx.Monad` API details.
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — confirm current EventLoop ownership and mailbox APIs when this task touches EventLoop.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** Library/app runner layer; no services required for unit/build verification.

## File Scope

- `lotos/src/Lotos/Logger.hs`
- `lotos/src/Lotos/Zmq/Util.hs`
- `lotos/src/Lotos/Zmq.hs`
- `applications/TaskSchedule/app/*`
- `lotos/test/*`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Map current runner/context usage

- [ ] Plan-review checkpoint — inventory every `runZmqContextIO`, `runZmqContextWithThreadIO`, `Zmqx.run`, and direct socket-open call site.
- [ ] Decide the public runner shape (`runZmqApp`/compatibility wrappers) and how to preserve existing app entry points during migration.
- [ ] Identify any tests or demos that depend on nested/global `Zmqx.run` behavior.

### Step 2: Add explicit context to the app environment

- [ ] Introduce a `LotosEnv` (or equivalent) that carries `LoggerEnv` plus `Zmqx.Context` while preserving logger helpers.
- [ ] Implement `MonadZmqx LotosApp` using the explicit context.
- [ ] Update `forkApp` so forked app actions retain the same logger and ZMQ context safely.

### Step 3: Adapt runners without changing socket behavior

- [ ] Add explicit-context app runners using `Zmqx.Monad.runZmqx` or `Zmqx.withContext` plus `runZmqxT` as appropriate.
- [ ] Keep compatibility wrappers for current executable/test call sites if needed.
- [ ] Update TaskSchedule executable wrappers and test helpers to use the new runner surface.

### Step 4: Testing & Verification

- [ ] Code review checkpoint — verify context lifetime, forked action behavior, and compatibility surface.
- [ ] Run `cabal build lotos`.
- [ ] Run representative frame tests: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames`.
- [ ] Run `cabal build all --enable-tests`.

### Step 5: Documentation & Delivery

- [ ] Update `taskplane-tasks/CONTEXT.md` with the monad-context migration status and any compatibility notes.
- [ ] Record any remaining global-context call sites in STATUS.md.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — record the explicit-context migration status and remaining migration sequence.

**Check If Affected:**
- `README.md` — update only if public runner names change.

## Completion Criteria

- [ ] All steps complete
- [ ] All tests passing with evidence recorded in STATUS.md
- [ ] Protocol frame ordering preserved or explicitly covered by regression tests
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Commits happen at **step boundaries** (not after every checkbox). The final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-032: Introduce explicit ZMQ context in LotosApp`

## Do NOT

- Expand scope into unrelated feature work; log follow-ups in `taskplane-tasks/CONTEXT.md`
- Claim exactly-once logging delivery
- Change ZMQ multipart frame ordering without explicit regression coverage
- Couple worker logging backpressure to task/status backend traffic
- Commit a final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
