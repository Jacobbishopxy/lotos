# Task: TP-013 - Info and Logging Pipeline Cleanup

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Clarifies or completes the worker logging/info-storage path. It spans worker PUB logging, server info storage, docs, and possibly config, but should be bounded to removing ambiguity.
**Score:** 4/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-013-info-logging-pipeline-cleanup/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Resolve ambiguity around worker logging and info storage. The MVP currently treats worker log collection as optional/reserved while info storage exposes `workerLoggingsMap`. This task should either wire the logging path end-to-end under the documented `5557` endpoint or deliberately simplify/document the unsupported path so users are not misled.

## Dependencies

- **Task:** TP-011 (protocol/frame regression baseline should be in place first)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `docs/task-schedule-mvp.md` — current optional logging semantics
- `README.md` — demo/info API docs
- `lotos/src/Lotos/Zmq/Config.hs` — config fields and inproc addresses
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs` — info storage subscriber and API behavior
- `lotos/src/Lotos/Zmq/LBW.hs` — worker PUB logging path
- `lotos/src/Lotos/Zmq/Adt.hs` — `WorkerLogging` frame shape
- `applications/TaskSchedule/config/*.json` — sample runtime configs
- `scripts/task-schedule-smoke.sh` — evidence capture and endpoint snapshots

## Environment

- **Workspace:** info storage/logging/config/docs
- **Services required:** Local smoke if wiring logging end-to-end

## File Scope

- `lotos/src/Lotos/Zmq/Config.hs`
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs`
- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/src/Lotos/Zmq/Adt.hs`
- `applications/TaskSchedule/config/*`
- `scripts/task-schedule-smoke.sh`
- `docs/task-schedule-mvp.md`
- `README.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-013-info-logging-pipeline-cleanup/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-011 completed and current smoke is green

### Step 1: Decide logging product stance

**Plan-review checkpoint** — review whether to wire logging or explicitly de-scope/simplify before editing.

- [ ] Trace current worker logging publish and info storage subscribe paths
- [ ] Decide whether end-to-end worker log collection is in scope for this repo now
- [ ] Define acceptance criteria for either wired logs or clearly documented unsupported logging

### Step 2: Implement cleanup

- [ ] If wiring logs: align config/socket addresses and info storage subscription, then capture logs in `/info.workerLoggingsMap`
- [ ] If simplifying: remove/rename misleading config/docs and clearly describe current local log-file behavior
- [ ] Add bounded tests or smoke assertions if practical

### Step 3: Testing & Verification

**Code review checkpoint** — review final logging stance and evidence before completion.

- [ ] `cabal build all --enable-tests` passes
- [ ] `cabal test all` passes
- [ ] `scripts/task-schedule-smoke.sh` passes
- [ ] Logging behavior is verified according to the selected stance

### Step 4: Documentation & Delivery

- [ ] README and MVP docs accurately describe info/logging behavior
- [ ] Context debt updated with resolved/new logging debt
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `docs/task-schedule-mvp.md` — final logging/info API stance
- `README.md` — info/logging docs if changed
- `taskplane-tasks/CONTEXT.md` — logging debt status

**Check If Affected:**
- `applications/TaskSchedule/config/*` — sample config consistency

## Completion Criteria

- [ ] Worker logging/info storage behavior is no longer ambiguous
- [ ] Docs and sample configs match actual behavior
- [ ] Build, regression tests, and smoke pass

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-013` and Lore trailers.

## Do NOT

- Add dependencies
- Break the green MVP smoke path
- Leave logging docs promising behavior that is not verified

---

## Amendments (Added During Execution)
