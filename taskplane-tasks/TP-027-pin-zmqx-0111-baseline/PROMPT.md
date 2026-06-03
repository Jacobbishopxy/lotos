# Task: TP-027 - Pin zmqx v0.1.1.1 and Establish EventLoop Baseline

**Created:** 2026-06-03
**Size:** S

## Review Level: 1 (Plan Only)

**Assessment:** Updates the external zmqx source-repository pin and records the compatibility/performance baseline before deeper event-loop changes. Scope is mostly config/docs plus verification, so risk is limited but still affects all ZMQ users.
**Score:** 3/8 — Blast radius: 2, Pattern novelty: 0, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-027-pin-zmqx-0111-baseline/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Pin the workspace to `zmqx` tag `v0.1.1.1`, verify the current codebase remains green, and document the follow-up EventLoop/worker responsiveness roadmap so later TPs optimize the right hot paths without conflating dependency upgrade risk with runtime refactors.

## Dependencies

- **None**

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `AGENTS.md` — project rules, Cabal verification, and 1 TP = 1 commit expectation
- `cabal.project` — current `zmqx` source-repository pin
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/README.md` — zmqx v0.1.1.x API guidance after dependency materialization
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — EventLoop API details if migrating socket ownership
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — monad-style context API details if relevant
- `lotos/src/Lotos/Zmq/LBW.hs` — worker backend/task execution loop
- `lotos/src/Lotos/Zmq/LBW/LogTransport.hs` — reliable worker log transport
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` — broker socket loop
- `lotos/src/Lotos/Zmq/LBS/LogIngest.hs` — broker reliable log ingestion

## Environment

- **Workspace:** lotos core library, TaskSchedule demo, and docs as scoped below
- **Services required:** None for unit tests; smoke scripts for final verification where listed

## File Scope

- `cabal.project`
- `taskplane-tasks/CONTEXT.md`
- `docs/logging-redesign.md (only if EventLoop/logging caveats need updating)`
- `README.md (only if the dependency pin or verification notes are user-facing)`
- `taskplane-tasks/TP-027-pin-zmqx-0111-baseline/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Pin and baseline

- [ ] Confirm `git@github.com:Jacobbishopxy/zmqx.git` latest intended tag is `v0.1.1.1` and `cabal.project` points to it.
- [ ] Run and record `cabal build all --enable-tests` and `cabal test all` evidence.
- [ ] Identify whether the new zmqx release requires immediate code changes; if not, explicitly record that deeper changes belong to TP-028+.

### Step 2: Documentation & Delivery

- [ ] Plan-review checkpoint — review the dependency baseline and staged follow-up plan before completion.
- [ ] Update `taskplane-tasks/CONTEXT.md` with `Next Task ID: TP-032` if this TP series remains TP-027 through TP-031.
- [ ] Keep exactly one final TP-027 commit with Lore trailers.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md — next task counter and roadmap status`
- `cabal.project — zmqx pin`

**Check If Affected:**
- `README.md`
- `docs/logging-redesign.md`

## Completion Criteria

- [ ] This TP's scoped zmqx/EventLoop/performance deliverable is complete
- [ ] Existing ZMQ multipart frame ordering is preserved
- [ ] Targeted tests/build/smoke listed above pass or gaps are documented honestly
- [ ] Documentation and CONTEXT are updated
- [ ] Final history contains exactly one commit for TP-027, with Lore trailers

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-027` and Lore trailers.

## Do NOT

- Add third-party dependencies unless explicitly justified and accepted by existing project rules
- Change existing task/status/log frame ordering
- Claim performance wins without a test, smoke result, benchmark, or clearly bounded rationale
- Mix changes from later dependent TPs into this TP
- Leave runtime hot loops with unconditional stdout logging

---

## Amendments (Added During Execution)
