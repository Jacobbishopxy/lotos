# Task: TP-049 - CI verification profile

**Created:** 2026-06-04
**Size:** M

## Review Level: 1 (Plan Only)

**Assessment:** This is mostly build tooling and documentation around existing commands. It should not change runtime code, but it shapes contributor verification behavior.
**Score:** 3/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-049-ci-verification-profile/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Create a lightweight CI-friendly verification profile that compiles all tests, runs terminating regression suites, and builds docs without accidentally launching long-running demo/server workflows. Contributors should have a single documented command for routine checks plus targeted commands for smoke and protocol validation.

## Dependencies

- **Task:** TP-048 (protocol fixture tests complete)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `Makefile` — existing build/test/docs targets
- `AGENTS.md` — project build guidance
- `README.md` — contributor commands
- `docs/book/lotos/src/verification.md` — verification guide
- `lotos/lotos.cabal` and `applications/TaskSchedule/TaskSchedule.cabal` — registered tests/exes

## Environment

- **Workspace:** repository root
- **Services required:** None for CI profile; smoke remains explicit opt-in

## File Scope

- `Makefile`
- `README.md`
- `AGENTS.md`
- `docs/book/lotos/src/verification.md`
- `.github/workflows/*`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied

### Step 1: Define the CI-safe command set

- [ ] Inventory registered tests and demos to confirm which commands terminate safely
- [ ] Define Makefile targets for CI build, targeted regression tests, docs build, and optional smoke
- [ ] Avoid defaulting to `cabal test all` if it would be slower or less controlled than targeted suites
- [ ] Run syntax/target listing checks: `make -n` for new targets where useful

**Artifacts:**
- `Makefile` (modified)

### Step 2: Implement CI-friendly targets and optional workflow

- [ ] Add or refine Makefile targets such as `ci-build`, `ci-test`, `ci-docs`, and `ci-check` using existing Cabal/mdBook commands
- [ ] If a `.github/workflows` directory exists or is appropriate for this repo, add a minimal workflow that uses those targets; otherwise document why no workflow was added
- [ ] Keep smoke scripts explicit opt-in rather than part of the default CI target unless bounded enough for CI
- [ ] Run the new CI target(s): `make ci-check` or the final equivalent

**Artifacts:**
- `Makefile` (modified)
- `.github/workflows/*` (new/modified if added)

### Step 3: Document contributor verification

- [ ] Update README with routine CI/local verification commands
- [ ] Update mdBook verification chapter with CI, targeted, and smoke profiles
- [ ] Update AGENTS.md only if standing project guidance should change

**Artifacts:**
- `README.md` (modified)
- `docs/book/lotos/src/verification.md` (modified)
- `AGENTS.md` (modified if needed)

### Step 4: Testing & Verification

- [ ] Run final CI profile: `make ci-check` or equivalent
- [ ] Run docs gate: `make book-build`
- [ ] Run at least one targeted protocol/scheduler suite if not included in CI profile
- [ ] Fix all failures

### Step 5: Documentation & Delivery

- [ ] "Must Update" docs modified
- [ ] "Check If Affected" docs reviewed
- [ ] Discoveries logged in STATUS.md and context if future work remains

## Documentation Requirements

**Must Update:**
- `README.md` — local/CI verification command summary
- `docs/book/lotos/src/verification.md` — CI-safe verification profile

**Check If Affected:**
- `AGENTS.md` — update only if canonical agent verification guidance changes
- `taskplane-tasks/CONTEXT.md` — log discovered verification gaps

## Completion Criteria

- [ ] A single CI-safe verification command exists and is documented
- [ ] The profile compiles all tests and runs terminating suites/docs without long-running demos
- [ ] New targets pass locally

## Git Commit Convention

Commits happen at **step boundaries** and MUST include `TP-049`.

## Do NOT

- Make long-running demo/server tests part of the default CI target
- Add external CI dependencies without need
- Replace targeted smoke scripts with unbounded waits

---

## Amendments (Added During Execution)
