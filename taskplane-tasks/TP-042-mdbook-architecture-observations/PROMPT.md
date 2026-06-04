# Task: TP-042 - Add mdBook architecture and API runbook with Makefile serve command

**Created:** 2026-06-04
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Adds documentation structure and Makefile commands, touching public project docs but not runtime code. Plan/code review protects command usability and doc accuracy.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-042-mdbook-architecture-observations/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Create a lightweight mdBook for lotos observations, API guidance, architecture, runtime operations, protocol compatibility, and verification notes, plus Makefile commands to build/serve it using the Arcadia LOB Makefile.toml docs command style as reference.

## Dependencies

- **External:** Current `main` with TP-032 through TP-041 and capacity-aware scheduling integrated

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `/home/xiey/Code/arcadia-lob/Makefile.toml` — reference style for mdBook build/serve/help command design.
- `Makefile` — existing project command surface.
- `docs/logging-redesign.md` — logging architecture and compatibility context.
- `docs/task-schedule-mvp.md` — TaskSchedule runtime/smoke context.
- `docs/build-your-own-scheduler.md` — scheduler API/adopter context.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** None unless smoke verification steps explicitly start TaskSchedule services.

## File Scope

- `Makefile`
- `docs/book/lotos/book.toml`
- `docs/book/lotos/src/*`
- `README.md`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Design book layout and Makefile surface

- [ ] Plan-review checkpoint — inspect `~/Code/arcadia-lob/Makefile.toml` and current `Makefile`, then choose target names, host/port variables, and book path.
- [ ] Define mdBook chapters for observations, public API, ZMQ/EventLoop architecture, TaskSchedule demo, operations, compatibility, and verification.
- [ ] Decide how README should point users to the book without duplicating all content.

### Step 2: Create mdBook and commands

- [ ] Add `docs/book/lotos/book.toml` and `src/SUMMARY.md`.
- [ ] Create chapter files with current observations from the recent monad/EventLoop/capacity work.
- [ ] Add `make book-build` and `make book-serve` (plus docs aliases if useful) using configurable `MDBOOK_HOST`, `MDBOOK_PORT`, and `MDBOOK_DIR`.

### Step 3: Testing & Verification

- [ ] Code review checkpoint — verify Makefile targets and book paths are accurate.
- [ ] Run `make book-build` if `mdbook` is installed; otherwise record the missing-tool result and run static file checks.
- [ ] Run `make book-serve` under a bounded smoke if practical, or validate command construction without leaving a server running.

### Step 4: Documentation & Delivery

- [ ] Update README with the mdBook command.
- [ ] Update `taskplane-tasks/CONTEXT.md` with mdBook availability.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `README.md` — document the mdBook serve/build commands.
- `taskplane-tasks/CONTEXT.md` — record the docs follow-up status.

**Check If Affected:**
- `docs/task-schedule-mvp.md` — link only if the book supersedes duplicated operational notes.

## Completion Criteria

- [ ] All steps complete
- [ ] Tests/build/smoke evidence recorded in STATUS.md
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-042: Add mdBook architecture and API runbook with Makefile serve command`

## Do NOT

- Change ZMQ multipart frame ordering without explicit tests and documented compatibility reasoning
- Convert no-drop task/status queues into dropping queues unless the prompt explicitly allows it
- Claim exactly-once logging delivery
- Add non-Cabal build dependencies unless the task explicitly scopes them as optional docs tooling
- Leave final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
