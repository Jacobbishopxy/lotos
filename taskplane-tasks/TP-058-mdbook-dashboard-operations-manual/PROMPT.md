# Task: TP-058 - mdBook dashboard operations manual

**Created:** 2026-06-05
**Size:** M

## Review Level: 1 (Plan Only)

**Assessment:** Documentation and Makefile startup polish for existing/new commands. It should not change runtime behavior beyond safe command aliases.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-058-mdbook-dashboard-operations-manual/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Write the final documented manual in the mdBook that explains how to run and use the visualization dashboard with the TaskSchedule runtime. The manual must describe each role (broker/server, worker, client, dashboard, mdBook/docs), the read-only endpoints each role uses or exposes, and the startup commands **via `make` targets**. Add missing Make targets if the manual needs them, but keep the dashboard read-only.

## Dependencies

- **Task:** TP-057 (dashboard live data integration)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `Makefile` — target names and defaults
- `README.md` — top-level quickstart
- `docs/book/lotos/src/SUMMARY.md` — mdBook navigation
- `docs/book/lotos/src/start-here.md` — entry page style
- `docs/book/lotos/src/operations.md` — runbook style and endpoint probes
- `applications/dashboard/*` — dashboard commands/features

## Environment

- **Workspace:** repository root
- **Services required:** None for docs build. Manual commands may describe long-running services.

## File Scope

- `docs/book/lotos/src/*`
- `README.md`
- `Makefile`
- `applications/dashboard/README.md`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied

### Step 1: Make startup commands complete

- [ ] Ensure root `make` targets exist for broker/server, worker, client submission, dashboard dev/build/preview, mdBook serve/build, and smoke checks
- [ ] Keep long-running command target names explicit and help text accurate
- [ ] Preserve override variables for config paths/ports where useful

**Artifacts:**
- `Makefile`

### Step 2: mdBook dashboard manual

- [ ] Add a new mdBook page for dashboard/manual usage
- [ ] Document roles: server/broker, worker, client, dashboard, mdBook docs
- [ ] Document startup order and commands via `make`
- [ ] Document read-only dashboard scope, API endpoints, light theme/design choice, troubleshooting, and smoke/manual verification
- [ ] Link the manual from `SUMMARY.md`, `start-here.md`, and related ops docs

**Artifacts:**
- `docs/book/lotos/src/*`

### Step 3: README/dashboard docs alignment

- [ ] Update README with the shortest dashboard startup path
- [ ] Add/refresh `applications/dashboard/README.md` with local development commands
- [ ] Cross-link mdBook manual

### Step 4: Testing & Verification

- [ ] Run `make book-build`
- [ ] Run `make dashboard-build`
- [ ] Run `make help`
- [ ] Fix all failures

### Step 5: Documentation & Delivery

- [ ] "Must Update" docs modified
- [ ] "Check If Affected" docs reviewed
- [ ] Discoveries logged in STATUS.md and `taskplane-tasks/CONTEXT.md` if future work remains

## Documentation Requirements

**Must Update:**
- `docs/book/lotos/src/SUMMARY.md` — link new manual page
- `docs/book/lotos/src/start-here.md` — add dashboard path
- `docs/book/lotos/src/operations.md` — link dashboard manual where relevant
- `README.md` — mention manual and startup commands
- `applications/dashboard/README.md` — dashboard-specific usage
- `Makefile` — make targets/help if needed

**Check If Affected:**
- `docs/book/lotos/src/runtime-failures.md` — only if troubleshooting text changes
- `taskplane-tasks/CONTEXT.md` — log follow-ups

## Completion Criteria

- [ ] mdBook contains a dashboard operations manual
- [ ] Manual describes each role and startup commands via `make`
- [ ] Dashboard remains read-only
- [ ] `make book-build`, `make dashboard-build`, and `make help` pass

## Git Commit Convention

Commits happen at step boundaries. All commits for this task MUST include `TP-058` for traceability.

## Do NOT

- Do not add release or GitHub CI work
- Do not add write/control actions to the dashboard
- Do not leave docs/book/lotos/book generated output committed
- Do not require live services for docs/dashboard build commands

---

## Amendments (Added During Execution)
