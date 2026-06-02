# Task: TP-026 - LogIngest Durability and Retention Hardening

**Created:** 2026-06-02
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Hardens a newly introduced runtime subsystem by adding restart recovery, retention enforcement, and socket-level pressure controls. It touches broker LogIngest, config/tests/docs, but stays within the reliable logging subsystem.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-026-logingest-durability-retention-hardening/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Make reliable worker logging trustworthy across broker restarts and sustained log volume. LogIngest already accepts ACKed batches and exposes `/logs/*`; this TP should add bounded restart recovery from the JSONL journal, enforce retention/compaction behavior, apply configured socket HWM where supported, and cover those behaviors with targeted tests.

## Dependencies

- **Task:** TP-025 (reliable logging transport and smoke/docs cleanup must be complete)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `AGENTS.md` — project rules, Cabal verification, and 1 TP = 1 final commit expectation
- `docs/logging-redesign.md` — current reliable logging architecture and known remaining risks
- `docs/task-schedule-mvp.md` — current smoke/log evidence path
- `lotos/src/Lotos/Zmq/LBS/LogIngest.hs` — broker log ingest, journal, cache, stats, and query implementation
- `lotos/src/Lotos/Zmq/Config.hs` — `LogIngestConfig` retention/HWM knobs
- `lotos/src/Lotos/Zmq/LBW/LogTransport.hs` — worker batching/ACK/drop behavior for compatibility checks
- `lotos/test/ZmqLogIngest.hs` — existing bounded LogIngest tests
- `lotos/test/ZmqLogProtocolConfig.hs` — protocol/config compatibility tests
- `lotos/test/ZmqWorkerLogTransport.hs` — worker-side reliable log transport tests

## Environment

- **Workspace:** lotos core library and logging docs
- **Services required:** None for unit tests; smoke scripts only if runtime changes reach TaskSchedule wiring

## File Scope

- `lotos/src/Lotos/Zmq/LBS/LogIngest.hs`
- `lotos/src/Lotos/Zmq/Config.hs`
- `lotos/src/Lotos/Zmq/LBS.hs` (only if LogIngest startup/state initialization changes)
- `lotos/src/Lotos/Zmq/LBW/LogTransport.hs` (only if HWM or ACK semantics require worker compatibility changes)
- `lotos/test/ZmqLogIngest.hs`
- `lotos/test/ZmqLogProtocolConfig.hs` (only if config parsing/defaults change)
- `lotos/test/ZmqWorkerLogTransport.hs` (only if worker compatibility changes)
- `lotos/lotos.cabal` (only if adding/renaming tests)
- `docs/logging-redesign.md`
- `docs/task-schedule-mvp.md` (only if user-facing reliability semantics change)
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-026-logingest-durability-retention-hardening/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-025 reliable logging state and smoke evidence understood
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Define durability/retention contract

**Plan-review checkpoint** — review restart, retention, and HWM semantics before implementation.

- [ ] Define what LogIngest must recover from the JSONL journal on broker startup: recent caches, accepted-through per worker, duplicates, gaps, and stats as appropriate
- [ ] Define retention/compaction behavior for `logIngestRetentionBytes`: what is retained, what can be discarded, and how operators see truncation/drop effects
- [ ] Define how to apply `logIngestSocketHWM` to the ROUTER and worker DEALER sockets where the current Zmqx API supports it; document any API limitation instead of pretending it is enforced
- [ ] Identify targeted tests that prove restart recovery, retention bounds, malformed journal handling, and HWM/config compatibility

### Step 2: Implement restart recovery and retention enforcement

- [ ] Add LogIngest initialization/reload path that rebuilds bounded read caches and accepted-through state from valid journal entries
- [ ] Handle malformed/partial JSONL journal lines safely with visible counters or warnings, without crashing normal startup
- [ ] Enforce retention/compaction/rotation using `logIngestRetentionBytes` while preserving bounded recent query usefulness
- [ ] Apply configured socket HWM for LogIngest ROUTER and worker logging DEALER if supported by Zmqx; otherwise document the unsupported part and add a config/test guard
- [ ] Preserve at-least-once/idempotent semantics and existing `/logs/*` query API shape

### Step 3: Testing & Verification

**Code review checkpoint** — review implementation and evidence before completion.

- [ ] Add or extend bounded LogIngest tests for restart recovery from journal
- [ ] Add or extend tests for retention/compaction behavior and malformed journal lines
- [ ] Add or extend tests for HWM/config parsing/defaults if changed
- [ ] Run `cabal test lotos:test:test-zmq-log-ingest lotos:test:test-zmq-log-protocol-config lotos:test:test-zmq-worker-log-transport`
- [ ] Run `cabal build all --enable-tests`

### Step 4: Documentation & Delivery

- [ ] Update `docs/logging-redesign.md` with the final restart/retention/HWM behavior and remaining caveats
- [ ] Update `taskplane-tasks/CONTEXT.md` to set `Next Task ID` to `TP-027`, mark resolved logging-hardening debt, and record any remaining follow-up
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `docs/logging-redesign.md` — restart recovery, retention/compaction, HWM behavior, and caveats
- `taskplane-tasks/CONTEXT.md` — set `Next Task ID` to `TP-027` and close/refine reliable logging hardening debt

**Check If Affected:**
- `docs/task-schedule-mvp.md`
- `README.md`

## Completion Criteria

- [ ] LogIngest can rebuild usable state from its journal after restart
- [ ] Retention/compaction behavior is bounded and tested
- [ ] Socket-level HWM is applied or explicitly documented as unsupported by the current Zmqx surface
- [ ] Targeted logging tests and build pass
- [ ] Final history contains exactly one commit for TP-026, with Lore trailers

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-026` and Lore trailers.

## Do NOT

- Add new third-party dependencies without explicit justification and project approval
- Change ZMQ multipart frame ordering for existing log/task/status messages
- Claim exactly-once log delivery
- Let journal recovery or retention make log memory usage unbounded
- Fold log traffic back into task/status backend traffic
- Expand into worker capacity-aware scheduling or package release polish

---

## Amendments (Added During Execution)
