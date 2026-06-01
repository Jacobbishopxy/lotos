# Task: TP-011 - Protocol Frame Regression Coverage

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Adds regression coverage around the ZMQ multipart protocol contracts that recently changed. It touches tests and possibly small test-only exports/helpers, but should not alter production behavior unless a defect is discovered.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
taskplane-tasks/TP-011-protocol-frame-regression-coverage/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Broaden bounded regression coverage for Lotos ZMQ multipart frame contracts so future changes cannot silently break client/frontend, worker/backend, task status, retry/failure, and ACK frame ordering. This task should lock down the protocol fixes from TP-007 and TP-008 without broad refactoring.

## Dependencies

- **None**

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `AGENTS.md` — protocol and verification rules
- `docs/task-schedule-mvp.md` — current smoke/ACK/status behavior
- `lotos/src/Lotos/Zmq/Adt.hs` — protocol types and `ToZmq`/`FromZmq` instances
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` — ROUTER frontend/backend frame handling
- `lotos/src/Lotos/Zmq/LBW.hs` — DEALER worker frame handling
- `lotos/src/Lotos/Zmq/LBC.hs` — REQ client frame handling
- `lotos/test/ZmqWorkerFrames.hs` — existing worker frame regression test
- `lotos/test/ZmqClientAckFrames.hs` — existing client ACK frame regression test
- `lotos/lotos.cabal` — test suite declarations

## Environment

- **Workspace:** `lotos/src`, `lotos/test`, Cabal metadata
- **Services required:** None; tests should be bounded and assertion-based

## File Scope

- `lotos/test/*`
- `lotos/lotos.cabal`
- `lotos/src/Lotos/Zmq/Adt.hs` (only for testable helpers if justified)
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` (only if a coverage-driven bug is found)
- `lotos/src/Lotos/Zmq/LBW.hs` (only if a coverage-driven bug is found)
- `lotos/src/Lotos/Zmq/LBC.hs` (only if a coverage-driven bug is found)
- `README.md` (only if test commands change)
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-011-protocol-frame-regression-coverage/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Current protocol regression tests and Cabal test suites identified

### Step 1: Plan frame coverage matrix

**Plan-review checkpoint** — review the coverage matrix before writing tests.

- [ ] List each protocol direction and frame shape to protect: client request, client ACK, worker status, worker task status, scheduled worker task, retry/failure frames if applicable
- [ ] Map each shape to existing coverage or a new bounded test case
- [ ] Identify whether production code needs small testable helper extraction; prefer tests over refactor

### Step 2: Implement bounded regression tests

- [ ] Add/extend assertion-based tests for missing frame contracts
- [ ] Keep tests deterministic and non-long-running
- [ ] Register new test suites or extend existing ones in `lotos/lotos.cabal`

### Step 3: Testing & Verification

**Code review checkpoint** — review final tests and any protocol-code changes before completion.

- [ ] `cabal build all --enable-tests` passes
- [ ] `cabal test all` passes
- [ ] Existing smoke script still passes or exact unrelated blocker is documented: `scripts/task-schedule-smoke.sh`

### Step 4: Documentation & Delivery

- [ ] README updated only if verification commands changed
- [ ] Any discovered protocol debt appended to `taskplane-tasks/CONTEXT.md`
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — append newly discovered protocol debt only

**Check If Affected:**
- `README.md` — if test command names/coverage descriptions change

## Completion Criteria

- [ ] Key multipart frame contracts have bounded regression coverage
- [ ] `cabal test all` remains safe and passes
- [ ] Smoke script remains green or any blocker is exact and documented

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-011` and Lore trailers.

## Do NOT

- Change protocol frame ordering unless a test proves a current defect
- Reintroduce long-running/no-assertion suites as Cabal tests
- Add dependencies

---

## Amendments (Added During Execution)
