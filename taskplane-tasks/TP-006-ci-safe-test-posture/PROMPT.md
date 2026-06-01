# Task: TP-006 - CI-Safe Test Posture

**Created:** 2026-05-31
**Size:** S

## Review Level: 1 (Plan Only)

**Assessment:** Separates/document safe regression commands from demo-style suites. Mostly cabal metadata and docs, with moderate risk if test suites are renamed or disabled incorrectly.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-006-ci-safe-test-posture/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Make the project's test posture explicit and CI-safe after the TaskSchedule MVP work. Developers should know which commands are safe for quick regression, which suites are demos/long-running, and what command proves the MVP without hanging.

## Dependencies

- **Task:** TP-005 (end-to-end smoke path informs final verification docs)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `README.md` — current test guidance
- `docs/task-schedule-mvp.md` — smoke verification guidance
- `lotos/lotos.cabal` — test suite definitions
- `lotos/test/*.hs` — identify terminating vs demo tests
- `scripts/task-schedule-smoke.sh` — smoke verification command if created

## Environment

- **Workspace:** tests/docs/build metadata
- **Services required:** None unless re-running smoke verification

## File Scope

- `README.md`
- `docs/task-schedule-mvp.md`
- `lotos/lotos.cabal` (only if metadata changes are necessary)
- `scripts/*` (only if smoke/test wrappers are necessary)
- `taskplane-tasks/CONTEXT.md` (append discoveries only)

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-005 completion criteria are satisfied

### Step 1: Define safe test posture

**Plan-review checkpoint** — review proposed test classification before metadata/doc changes.

- [ ] Classify each current test suite as regression, demo, long-running, or smoke
- [ ] Decide whether docs-only is enough or cabal metadata/scripts should change
- [ ] Define recommended commands for quick, full-build, and MVP smoke verification

### Step 2: Apply docs/metadata updates

- [ ] README test section updated with safe commands
- [ ] MVP contract references final smoke verification command
- [ ] Cabal metadata adjusted only if necessary and low-risk

### Step 3: Testing & Verification

- [ ] Build passes: `cabal build all --enable-tests`
- [ ] Safe regression command passes: `cabal test lotos:test:test-conc-executor`
- [ ] Smoke command/runbook status is documented from TP-005

### Step 4: Documentation & Delivery

- [ ] Discoveries logged in STATUS.md
- [ ] Any remaining long-running/demo test debt appended to `taskplane-tasks/CONTEXT.md`

## Documentation Requirements

**Must Update:**
- `README.md` — final safe test commands

**Check If Affected:**
- `docs/task-schedule-mvp.md` — final smoke command/status
- `taskplane-tasks/CONTEXT.md` — future test debt if discovered

## Completion Criteria

- [ ] Developers have clear safe verification commands
- [ ] CI-hostile commands are identified and not recommended as default
- [ ] Build/test verification passes for safe commands

## Git Commit Convention

Commits happen at step boundaries. All commits for this task MUST include the task ID for traceability.

## Do NOT

- Delete demo tests unless explicitly justified and reviewed
- Hide known long-running behavior
- Run commands expected to hang without a timeout/cleanup plan

---

## Amendments (Added During Execution)
