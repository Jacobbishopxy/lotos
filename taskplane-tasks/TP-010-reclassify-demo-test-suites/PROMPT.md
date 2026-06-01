# Task: TP-010 - Reclassify Demo Test Suites

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Adjusts Cabal test metadata and documentation so CI-safe tests are distinct from demos. It touches test/package structure but should not change library behavior.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
taskplane-tasks/TP-010-reclassify-demo-test-suites/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Separate or clearly gate Cabal suites that behave as demos/long-running servers so developers can safely use default regression commands. TP-006 documented the current risk; this task should make the project metadata/docs enforce the safe posture instead of relying only on warnings.

## Dependencies

- **Task:** TP-009 (final smoke status should inform test/run docs)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `README.md` — current verification guidance
- `docs/task-schedule-mvp.md` — smoke command/status
- `lotos/lotos.cabal` — current test suite definitions
- `lotos/test/ConcExecutor.hs`
- `lotos/test/ConcExecutor2.hs`
- `lotos/test/EventTrigger.hs`
- `lotos/test/Logger.hs`
- `lotos/test/SimpleServant.hs`
- `lotos/test/ZmqXT.hs`

## Environment

- **Workspace:** Cabal test metadata, test files, docs
- **Services required:** None unless smoke is re-run for docs

## File Scope

- `lotos/lotos.cabal`
- `lotos/test/*`
- `README.md`
- `docs/task-schedule-mvp.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-010-reclassify-demo-test-suites/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-009 completion status is understood

### Step 1: Plan test classification

**Plan-review checkpoint** — review proposed Cabal/test metadata changes before editing.

- [ ] Classify each suite as regression, bounded demo, long-running demo, or server demo
- [ ] Decide whether to rename, move to benchmark/example executable, gate with env vars, or docs-only for each suite
- [ ] Preserve a quick default regression command and a full compile command

### Step 2: Apply test metadata/code/docs changes

- [ ] Update Cabal metadata/test code to avoid CI-hostile default behavior where practical
- [ ] Keep genuinely terminating regression tests easy to run
- [ ] Update README and MVP docs with final commands
- [ ] Update context debt list to mark the demo-suite debt resolved or refine remaining work

### Step 3: Testing & Verification

**Code review checkpoint** — review final test posture before completion.

- [ ] `cabal build all --enable-tests` passes
- [ ] Safe regression command passes
- [ ] Any gated/renamed demo command is documented and either tested with timeout or explicitly not run

### Step 4: Documentation & Delivery

- [ ] README verification section is clear and current
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `README.md` — final safe verification commands
- `taskplane-tasks/CONTEXT.md` — mark/refine test-suite debt

**Check If Affected:**
- `docs/task-schedule-mvp.md` — smoke command/status if touched

## Completion Criteria

- [ ] Default recommended verification cannot hang unexpectedly
- [ ] Long-running/demo behavior is separated, gated, or explicitly documented with safe commands
- [ ] Build/test verification passes

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-010` and Lore trailers.

## Do NOT

- Delete useful demos without preserving a documented way to run them
- Make `cabal test all` a recommendation unless it is genuinely safe
- Hide known long-running behavior

---

## Amendments (Added During Execution)
