# Task: TP-051 - Runtime failure runbook

**Created:** 2026-06-04
**Size:** M

## Review Level: 1 (Plan Only)

**Assessment:** This is operator documentation backed by existing observability and smoke commands. It has low runtime risk but spans several docs and should be reviewed for correctness.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-051-runtime-failure-runbook/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Write an operator-focused runtime failure runbook for stuck workers, LogIngest backlog, broker overload, stale heartbeats, reservation behavior, smoke failures, and safe recovery. The runbook should turn the new observability signals into concrete diagnosis and remediation steps without overstating delivery guarantees.

## Dependencies

- **Task:** TP-050 (public docs and verification profile are current)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `docs/book/lotos/src/operations.md` — current operations chapter
- `docs/book/lotos/src/observations.md` — runtime observability notes
- `docs/book/lotos/src/verification.md` — smoke/CI verification commands
- `docs/logging-redesign.md` — logging reliability design
- `docs/task-schedule-mvp.md` — demo operations notes
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs` — info/log stats surfaces if docs need exact names

## Environment

- **Workspace:** docs and runbooks
- **Services required:** None; use existing smoke commands only if needed to validate examples

## File Scope

- `docs/book/lotos/src/operations.md`
- `docs/book/lotos/src/observations.md`
- `docs/book/lotos/src/verification.md`
- `docs/book/lotos/src/SUMMARY.md`
- `docs/book/lotos/src/runtime-failures.md`
- `docs/logging-redesign.md`
- `docs/task-schedule-mvp.md`
- `README.md`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied

### Step 1: Define failure taxonomy and evidence sources

- [ ] List operator-visible symptoms for stuck workers, no task progress, broker overload, LogIngest backlog, stale heartbeats, reservation underutilization, and smoke failures
- [ ] Map each symptom to available evidence: `/info`, `runtimeQueueStats`, `/logs/stats`, worker stats, smoke output, logs, and task status
- [ ] Identify any missing signal as future work rather than inventing undocumented behavior

**Artifacts:**
- `docs/book/lotos/src/runtime-failures.md` (new)

### Step 2: Write safe recovery procedures

- [ ] Add diagnosis/remediation steps for stuck workers and stale heartbeats
- [ ] Add LogIngest backlog guidance with at-least-once/idempotent ingestion wording
- [ ] Add broker overload and handoff queue growth guidance without recommending lossy protocol queues
- [ ] Add capacity reservation behavior guidance, including conservative retention/underutilization risk
- [ ] Add smoke failure triage steps and where artifacts are written

**Artifacts:**
- `docs/book/lotos/src/runtime-failures.md` (new)
- `docs/book/lotos/src/operations.md` (modified)

### Step 3: Cross-link docs and README

- [ ] Link the runtime failure runbook from mdBook summary and operations/observations/verification chapters
- [ ] Update README only if top-level operations guidance should point at the runbook
- [ ] Update older markdown docs if they contain stale failure/recovery guidance

**Artifacts:**
- `docs/book/lotos/src/SUMMARY.md` (modified)
- `docs/book/lotos/src/operations.md` (modified)
- `docs/book/lotos/src/observations.md` (modified)
- `docs/book/lotos/src/verification.md` (modified)
- `README.md` (modified if needed)

### Step 4: Testing & Verification

- [ ] Run docs gate: `make book-build`
- [ ] Run CI/local docs-aware gate from TP-049: `make ci-check` or equivalent
- [ ] Optionally run a smoke script if examples changed materially
- [ ] Fix all failures

### Step 5: Documentation & Delivery

- [ ] "Must Update" docs modified
- [ ] "Check If Affected" docs reviewed
- [ ] Discoveries logged in STATUS.md and context if future work remains

## Documentation Requirements

**Must Update:**
- `docs/book/lotos/src/runtime-failures.md` — new operator failure runbook
- `docs/book/lotos/src/SUMMARY.md` — include the new runbook
- `docs/book/lotos/src/operations.md` — link and summarize recovery flow

**Check If Affected:**
- `docs/book/lotos/src/observations.md`
- `docs/book/lotos/src/verification.md`
- `docs/logging-redesign.md`
- `docs/task-schedule-mvp.md`
- `README.md`
- `taskplane-tasks/CONTEXT.md`

## Completion Criteria

- [ ] Runtime failure runbook covers diagnosis, evidence, and recovery for the named failure classes
- [ ] Docs do not claim exactly-once logging or lossy protocol queues
- [ ] `make book-build` and CI/local verification profile pass

## Git Commit Convention

Commits happen at **step boundaries** and MUST include `TP-051`.

## Do NOT

- Claim exactly-once delivery
- Recommend dropping task/status protocol frames as a recovery strategy
- Invent observability endpoints that do not exist
- Add dependencies

---

## Amendments (Added During Execution)
