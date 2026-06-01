# Task: TP-008 - Complete Client ACK Path

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Completes the broker acceptance response expected by `ts-client`. It touches client/server protocol behavior but should be a narrow ACK path change.
**Score:** 4/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-008-complete-client-ack-path/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Make the broker send the expected client ACK after accepting/enqueuing a task so `ts-client` can exit successfully after broker acceptance. TP-003 bounded client waits, and TP-005 documented that the server frontend currently enqueues but does not complete the `ClientAck` response path.

## Dependencies

- **Task:** TP-007 (worker registration should be fixed first so smoke can progress far enough to distinguish ACK behavior)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `docs/task-schedule-mvp.md` — ACK semantics and current blocker notes
- `lotos/src/Lotos/Zmq/Adt.hs` — `Ack`, `RouterFrontendOut`, and frontend frame contracts
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` — frontend task receive/enqueue path
- `lotos/src/Lotos/Zmq/LBC.hs` — `sendTaskRequest` client wait path
- `applications/TaskSchedule/app/TaskScheduleClient.hs` — current CLI behavior

## Environment

- **Workspace:** core client/frontend ZMQ path
- **Services required:** Local server/client smoke for runtime ACK verification

## File Scope

- `lotos/src/Lotos/Zmq/Adt.hs`
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/src/Lotos/Zmq/LBC.hs`
- `applications/TaskSchedule/app/TaskScheduleClient.hs` (only if output/error handling needs adjustment)
- `docs/task-schedule-mvp.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-008-complete-client-ack-path/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-007 completion criteria are satisfied or remaining status is understood

### Step 1: Plan ACK semantics and frame shape

**Plan-review checkpoint** — review response frame shape before editing protocol code.

- [ ] Confirm frontend Router/Req multipart expectations for sending `Ack`
- [ ] Confirm ACK means accepted/enqueued, not worker completion
- [ ] Identify minimal server/client changes and any tests

### Step 2: Implement ACK response path

- [ ] Broker sends `ClientAck`/`Ack` after successful enqueue
- [ ] Client receives and reports ACK without hanging under default config
- [ ] Failure path remains clear for parse/enqueue errors where applicable

### Step 3: Testing & Verification

**Code review checkpoint** — review final ACK changes and evidence before completion.

- [ ] Build passes: `cabal build all`
- [ ] Tests compile: `cabal build all --enable-tests`
- [ ] Targeted regression passes: `cabal test lotos:test:test-conc-executor`
- [ ] Runtime check proves `ts-client` exits `0` on broker ACK, or exact remaining blocker is documented

### Step 4: Documentation & Delivery

- [ ] MVP docs updated with final ACK status
- [ ] Context debt for client ACK marked fixed or refined
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `docs/task-schedule-mvp.md` — ACK path status
- `taskplane-tasks/CONTEXT.md` — mark/refine ACK debt

**Check If Affected:**
- `README.md` — only if command behavior changes

## Completion Criteria

- [ ] `ts-client` receives broker ACK and exits successfully for a valid task while server is running
- [ ] ACK semantics remain documented as broker acceptance, not worker completion
- [ ] Build and targeted tests pass

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-008` and Lore trailers.

## Do NOT

- Conflate ACK with task completion
- Change worker task status semantics unless required and documented
- Leave client waits unbounded

---

## Amendments (Added During Execution)
