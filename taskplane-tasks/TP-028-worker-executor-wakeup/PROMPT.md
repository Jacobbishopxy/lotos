# Task: TP-028 - Make Worker Task Execution Wake on Enqueue

**Created:** 2026-06-03
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Improves the worker runtime hot path by replacing fixed sleep polling with a wake-on-enqueue signal and removing noisy broker poll output. It touches worker service concurrency and smoke-sensitive paths.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
taskplane-tasks/TP-028-worker-executor-wakeup/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Remove the worker executor's worst dispatch-latency path by replacing the 10-second empty-queue sleep with a signal triggered when the socket loop enqueues work. Also remove the broker socket-layer hot-loop `putStrLn` so high-volume polling does not spam stdout.

## Dependencies

- **Task:** TP-027 (zmqx v0.1.1.1 baseline complete)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `AGENTS.md` — project rules, Cabal verification, and 1 TP = 1 commit expectation
- `cabal.project` — current `zmqx` source-repository pin
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/README.md` — zmqx v0.1.1.x API guidance after dependency materialization
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — EventLoop API details if migrating socket ownership
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — monad-style context API details if relevant
- `lotos/src/Lotos/Zmq/LBW.hs` — worker backend/task execution loop
- `lotos/src/Lotos/Zmq/LBW/LogTransport.hs` — reliable worker log transport
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` — broker socket loop
- `lotos/src/Lotos/Zmq/LBS/LogIngest.hs` — broker reliable log ingestion

## Environment

- **Workspace:** lotos core library, TaskSchedule demo, and docs as scoped below
- **Services required:** None for unit tests; smoke scripts for final verification where listed

## File Scope

- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/test/*`
- `applications/TaskSchedule/test/*`
- `scripts/task-schedule-smoke.sh`
- `scripts/task-schedule-multi-worker-smoke.sh`
- `docs/task-schedule-mvp.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-028-worker-executor-wakeup/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Define wakeup contract

- [ ] Plan-review checkpoint — define the worker wakeup primitive (STM/TMVar/TQueue/EventTrigger integration) and how task arrival wakes `tasksExecLoop`.
- [ ] Define latency/correctness tests: no task should wait for the old 10-second sleep, and worker waiting/processing counts should remain accurate.
- [ ] Define how to remove or replace `putStrLn "> poll"` without losing useful diagnostics.

### Step 2: Implement wake-on-enqueue and cleanup

- [ ] Add a bounded/simple wake signal to `WorkerService` state and trigger it whenever `socketLoop` enqueues an incoming task.
- [ ] Change `tasksExecLoop` to block/wait on the wake signal instead of fixed 10-second sleeps when the task queue is empty.
- [ ] Remove broker socket-layer `putStrLn "> poll"` or convert it to structured DEBUG logging only if useful.
- [ ] Preserve task status, worker status, and reliable log transport semantics.

### Step 3: Testing & Verification

- [ ] Code review checkpoint — review concurrency changes and failure modes.
- [ ] Run targeted worker lifecycle/scheduler/logging tests affected by worker behavior.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run `scripts/task-schedule-smoke.sh`; run multi-worker smoke if changes affect burst scheduling or worker state.

### Step 4: Documentation & Delivery

- [ ] Update docs only if user-visible latency/runtime behavior changes.
- [ ] Update `taskplane-tasks/CONTEXT.md` with remaining EventLoop follow-up.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md — worker responsiveness status`

**Check If Affected:**
- `docs/task-schedule-mvp.md`
- `README.md`

## Completion Criteria

- [ ] This TP's scoped zmqx/EventLoop/performance deliverable is complete
- [ ] Existing ZMQ multipart frame ordering is preserved
- [ ] Targeted tests/build/smoke listed above pass or gaps are documented honestly
- [ ] Documentation and CONTEXT are updated
- [ ] Final history contains exactly one commit for TP-028, with Lore trailers

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-028` and Lore trailers.

## Do NOT

- Add third-party dependencies unless explicitly justified and accepted by existing project rules
- Change existing task/status/log frame ordering
- Claim performance wins without a test, smoke result, benchmark, or clearly bounded rationale
- Mix changes from later dependent TPs into this TP
- Leave runtime hot loops with unconditional stdout logging

---

## Amendments (Added During Execution)
