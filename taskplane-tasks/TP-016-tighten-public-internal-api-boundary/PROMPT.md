# Task: TP-016 - Tighten Public/Internal API Boundary

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Audits the public `Lotos.Zmq` facade and moves test-only/internal helpers out of public exports. This is API-surface work with moderate compatibility risk and should be conservative.
**Score:** 4/8 — Blast radius: 2, Pattern novelty: 0, Security: 0, Reversibility: 2

## Canonical Task Folder

```
taskplane-tasks/TP-016-tighten-public-internal-api-boundary/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Tighten the boundary between public library API and internal/test-only helpers after retry semantics are settled. In particular, address the debt that `failedTaskDisposition` is exported through `Lotos.Zmq` primarily for tests. Keep legitimate extension points public, move internals behind narrower modules or test imports, and update docs/tests accordingly.

## Dependencies

- **Task:** TP-015 (retry semantics must be implemented first so helper/API needs are known)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `README.md` — public API docs and library usage guidance
- `docs/task-schedule-mvp.md` — public behavior docs
- `lotos/src/Lotos/Zmq.hs` — public facade exports
- `lotos/src/Lotos/Zmq/Adt.hs` — protocol/task/status types
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` — retry/failure helpers
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs`
- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/lotos.cabal` — exposed vs other modules and test visibility
- `lotos/test/*` — tests importing internals

## Environment

- **Workspace:** public facade, internal modules, Cabal metadata, tests/docs
- **Services required:** None; smoke for final safety check

## File Scope

- `lotos/src/Lotos/Zmq.hs`
- `lotos/src/Lotos/Zmq/Adt.hs`
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs`
- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/lotos.cabal`
- `lotos/test/*`
- `README.md`
- `docs/task-schedule-mvp.md` (only if public API docs change)
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-016-tighten-public-internal-api-boundary/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-015 completion status and helper/API changes understood

### Step 1: Audit public exports

**Plan-review checkpoint** — review proposed API boundary changes before editing exports.

- [ ] List public exports in `Lotos.Zmq` and classify as extension point, protocol type, config, utility, or internal/test-only
- [ ] Decide how tests should access internals without widening the public facade
- [ ] Identify docs that need updates if exports move

### Step 2: Apply boundary cleanup

- [ ] Remove or relocate test-only/internal helpers from `Lotos.Zmq` public exports where safe
- [ ] Update tests to import narrower/internal modules or use public behavior
- [ ] Preserve documented public extension points: `LoadBalancerAlgo`, `TaskAcceptor`, `StatusReporter`, config/readers, client/server/worker entry points, protocol types needed by users

### Step 3: Testing & Verification

**Code review checkpoint** — review API-surface changes before completion.

- [ ] `cabal build all --enable-tests` passes
- [ ] `cabal test all` passes
- [ ] `scripts/task-schedule-smoke.sh` passes
- [ ] Public docs still match exported API

### Step 4: Documentation & Delivery

- [ ] README updated if public API guidance changed
- [ ] Context debt for public/internal boundary marked resolved or refined
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — mark/refine public API helper debt

**Check If Affected:**
- `README.md` — public API docs
- `docs/task-schedule-mvp.md` — only if behavior docs change

## Completion Criteria

- [ ] Public `Lotos.Zmq` exports no longer include avoidable test-only helpers
- [ ] Tests still cover internals safely
- [ ] Build, regression tests, and smoke pass

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-016` and Lore trailers.

## Do NOT

- Break intended library extension points
- Rename modules gratuitously
- Add dependencies

---

## Amendments (Added During Execution)
