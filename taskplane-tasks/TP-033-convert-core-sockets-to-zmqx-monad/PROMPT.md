# Task: TP-033 - Convert core socket operations to Zmqx.Monad

**Created:** 2026-06-03
**Size:** L

## Review Level: 3 (Full)

**Assessment:** This touches all core broker, worker, client, and test socket operations. Protocol behavior must remain identical, so both plan/code/test review are warranted.
**Score:** 6/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 2

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-033-convert-core-sockets-to-zmqx-monad/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Convert direct global-context socket opens and common send/receive/poll operations to the `Zmqx.Monad` surface so lotos consistently uses explicit context ownership while preserving existing ZMQ protocol shapes.

## Dependencies

- **Task:** TP-032 (explicit `LotosApp` ZMQ context and `MonadZmqx` instance)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — confirm current `Zmqx.Monad` API details.
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — confirm current EventLoop ownership and mailbox APIs when this task touches EventLoop.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** Core lotos ZMQ modules and tests; no live services required until smoke verification.

## File Scope

- `lotos/src/Lotos/Zmq/LBC.hs`
- `lotos/src/Lotos/Zmq/LBS/*.hs`
- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/src/Lotos/Zmq/LBW/LogTransport.hs`
- `lotos/test/*`
- `applications/TaskSchedule/app/*`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Convert low-risk socket creation sites

- [ ] Plan-review checkpoint — group socket sites by module and decide conversion order to keep build failures local.
- [ ] Convert `LBC` client REQ open/connect/send/receive to `Zmqx.Monad` wrappers where available.
- [ ] Convert straightforward test helper socket opens to the monadic surface.

### Step 2: Convert broker and worker service sockets

- [ ] Convert `LBS.LogIngest`, `LBS.TaskProcessor`, `LBS.SocketLayer`, and `LBW` direct opens/connects/binds to `Zmqx.Monad.open` and monadic helpers where applicable.
- [ ] Preserve existing `zmqUnwrap`/error handling semantics or introduce a minimal monadic wrapper with equivalent behavior.
- [ ] Keep direct protocol handler code behavior-equivalent; do not introduce EventLoop migration in this TP.

### Step 3: Convert send/receive/poll call sites consistently

- [ ] Replace direct `Zmqx.sends`, `Zmqx.receives`, `Zmqx.poll`, and `Zmqx.pollFor` with `Zmqx.Monad` operations where the API supports them.
- [ ] Leave any EventLoop command calls unchanged until TP-034.
- [ ] Verify no remaining direct global socket operations exist except deliberately documented exceptions.

### Step 4: Testing & Verification

- [ ] Test-review checkpoint — verify frame ordering coverage is sufficient before finalizing.
- [ ] Run frame/protocol tests: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-log-protocol-config`.
- [ ] Run worker/log/lifecycle tests touched by conversion.
- [ ] Run `cabal build all --enable-tests`.

### Step 5: Documentation & Delivery

- [ ] Update `taskplane-tasks/CONTEXT.md` with the direct-socket-to-monad conversion status.
- [ ] List intentional remaining direct `Zmqx.*` calls in STATUS.md with rationale.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — record conversion status and remaining direct-call exceptions.

**Check If Affected:**
- `README.md` — update only if public runner examples changed.

## Completion Criteria

- [ ] All steps complete
- [ ] All tests passing with evidence recorded in STATUS.md
- [ ] Protocol frame ordering preserved or explicitly covered by regression tests
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Commits happen at **step boundaries** (not after every checkbox). The final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-033: Convert core socket operations to Zmqx.Monad`

## Do NOT

- Expand scope into unrelated feature work; log follow-ups in `taskplane-tasks/CONTEXT.md`
- Claim exactly-once logging delivery
- Change ZMQ multipart frame ordering without explicit regression coverage
- Couple worker logging backpressure to task/status backend traffic
- Commit a final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
