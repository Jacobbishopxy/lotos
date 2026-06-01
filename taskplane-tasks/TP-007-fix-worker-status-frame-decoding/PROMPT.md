# Task: TP-007 - Fix Worker Status Frame Decoding

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Fixes a protocol/runtime blocker in the ZMQ worker status path. It touches core multipart decoding/handling and must preserve frame ordering semantics.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
taskplane-tasks/TP-007-fix-worker-status-frame-decoding/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Fix the worker status registration path so `ts-worker` status reports are decoded by the broker and appear under `/SimpleServer/worker_stats`. TP-005 found that the server reaches HTTP readiness but repeatedly rejects backend worker status frames with `ZmqParsing "Text decode error: Cannot decode byte '\\xe4'"`, leaving worker stats empty and blocking scheduling.

## Dependencies

- **None**

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `docs/task-schedule-mvp.md` — current smoke evidence and blocker description
- `scripts/task-schedule-smoke.sh` — readiness checks and evidence capture
- `lotos/src/Lotos/Zmq/Adt.hs` — multipart protocol types and `ToZmq`/`FromZmq` instances
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` — backend receive/decode handling
- `lotos/src/Lotos/Zmq/LBW.hs` — worker status send path
- `applications/TaskSchedule/src/Adt.hs` — `WorkerState` ZMQ encoding/decoding

## Environment

- **Workspace:** core `lotos` ZMQ modules and TaskSchedule smoke path
- **Services required:** Local server/worker via smoke script for runtime verification

## File Scope

- `lotos/src/Lotos/Zmq/Adt.hs`
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/src/Lotos/Zmq/LBW.hs`
- `applications/TaskSchedule/src/Adt.hs` (only if concrete `WorkerState` encoding is faulty)
- `docs/task-schedule-mvp.md` (update blocker status)
- `taskplane-tasks/CONTEXT.md` (mark resolved or refine remaining debt)
- `taskplane-tasks/TP-007-fix-worker-status-frame-decoding/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Confirm current smoke or logs show worker status decode failure

### Step 1: Diagnose frame shape mismatch

**Plan-review checkpoint** — review the discovered frame shape and planned fix before editing protocol code.

- [ ] Trace worker status frames from `LBW` send path to `SocketLayer` receive path
- [ ] Compare actual multipart frames with `RouterBackendIn` / `WorkerReportStatus` decoders
- [ ] Identify the minimal fix that preserves existing task/status message ordering

### Step 2: Implement decode/handling fix

- [ ] Patch only the affected frame construction/decoding/handler code
- [ ] Preserve all documented `ToZmq`/`FromZmq` frame ordering invariants
- [ ] Add or update targeted regression coverage if practical without long-running sockets

### Step 3: Testing & Verification

**Code review checkpoint** — review protocol changes and evidence before completion.

- [ ] Build passes: `cabal build all`
- [ ] Tests compile: `cabal build all --enable-tests`
- [ ] Targeted regression passes: `cabal test lotos:test:test-conc-executor`
- [ ] Runtime check proves `/SimpleServer/worker_stats` contains `simpleWorker_1`, or documents exact remaining blocker

### Step 4: Documentation & Delivery

- [ ] `docs/task-schedule-mvp.md` updated with worker registration status
- [ ] `taskplane-tasks/CONTEXT.md` updated to mark or refine worker status debt
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `docs/task-schedule-mvp.md` — update current worker registration blocker/status
- `taskplane-tasks/CONTEXT.md` — mark fixed or refine follow-up debt

**Check If Affected:**
- `README.md` — only if run instructions change

## Completion Criteria

- [ ] Worker status frames decode without UTF-8 frame errors
- [ ] `/SimpleServer/worker_stats` shows `simpleWorker_1` under default TaskSchedule config
- [ ] Build and targeted tests pass

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-007` and Lore trailers.

## Do NOT

- Change unrelated protocol frame ordering
- Hide runtime failures; record exact blockers
- Run long-hanging demos without timeouts/cleanup

---

## Amendments (Added During Execution)
