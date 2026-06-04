# TP-045: Deprecate legacy logging names with compatibility path — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-04
**Review Level:** 3
**Review Counter:** 9
**Iteration:** 1
**Size:** L

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Plan compatibility surface
**Status:** ✅ Complete

- [x] Plan-review checkpoint — inventory legacy names: `infoStorage.loggingAddr`, `infoStorage.loggingsBufferSize`, `loadBalancerLoggingAddr`, `taPubTaskLogging`, and related docs/config defaults.
- [x] Decide new names and whether old record fields remain, get deprecated comments, or move to compatibility-only JSON parsing.
- [x] Define migration examples for old and new broker/worker JSON.
- [x] R001: Record concrete compatibility matrix covering inventory, replacement names, Haskell API strategy, JSON aliases, conflict precedence, and docs/tests coverage.

---

### Step 2: Implement compatibility cleanup
**Status:** ✅ Complete

- [x] Add new clearer names/default derivation where feasible without breaking existing configs.
- [x] Keep old JSON keys accepted and tested; emit docs/comments explaining compatibility behavior.
- [x] Rename internal comments/usages that no longer reflect runtime LogIngest behavior.

---

### Step 3: Add tests
**Status:** ✅ Complete

- [x] Add config parse tests for old and new logging keys.
- [x] Verify TaskSchedule checked-in configs still parse.
- [x] Verify reliable logging smoke paths remain unchanged.

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review public API compatibility and docs.
- [x] Run log protocol/config tests, LogIngest tests, worker log transport tests.
- [x] Run `cabal build all --enable-tests`.
- [x] Run single-worker smoke.

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `docs/logging-redesign.md` and mdBook API/operations pages with the migration path.
- [x] Mark legacy logging-name debt resolved in `taskplane-tasks/CONTEXT.md`.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | plan | 1 | REVISE | `.reviews/R001-plan-step1.md` |
| R002 | plan | 1 | APPROVE | inline |
| R003 | code | 1 | APPROVE | inline |
| R004 | plan | 2 | APPROVE | `.reviews/R004-plan-step2.md` |
| R005 | code | 2 | APPROVE | inline |
| R006 | plan | 3 | APPROVE | `.reviews/R006-plan-step3.md` |
| R007 | code | 3 | APPROVE | inline |
| R008 | plan | 4 | APPROVE | `.reviews/R008-plan-step4.md` |
| R009 | code | 4 | APPROVE | `.reviews/R009-code-step4.md` |

---

## Notes / Discoveries

- Preflight: required source/docs/config paths exist. Documentation requirement names `docs/book/lotos/src/api.md`, but this worktree has `docs/book/lotos/src/public-api.md`; treat `public-api.md` as the mdBook API page.
- Preflight: cabal-install 3.16.1.0 and GHC 9.14.1 are available; TP-044 status is complete.
- Preflight: branch `task/xiey-lane-1-20260604T102444` at `5fe45eb`; only STATUS.md changed so far. Project rule requires squashing TP-045 to exactly one final commit.
- Step 2: added broker `infoStorage.logIngestDefaultAddr` / `logIngestDefaultBufferSize` aliases, worker top-level `logIngestDefaultAddr` compatibility parsing, optional legacy worker logging key handling, and context-sensitive partial LogIngest defaults. Targeted `cabal test lotos:test:test-zmq-log-protocol-config` passed (6 cases) after the parser change.
- Step 2: old `loggingAddr`, `loggingsBufferSize`, and `loadBalancerLoggingAddr` JSON remains accepted by existing config tests; source comments now document that old Haskell fields/callbacks are compatibility/default-derivation surfaces while LogIngest owns runtime logging.
- Step 2: replaced stale PUB/SUB publish/topic comments around `WorkerLogging`, `pubTaskLogging`, LogIngest journal ownership, and worker routing/logging id wording.
- Step 3: extended `test-zmq-log-protocol-config` to cover old-only, new-only, and mixed logging/default-derivation JSON for broker and worker configs; targeted run passed 9 cases.
- Step 3: the same test now reads `applications/TaskSchedule/config/{broker,worker,client}.json` through exported config readers and asserts the checked-in endpoints still parse/aligned.
- Step 3: reliable logging regression suites passed: `test-zmq-log-ingest` (14 cases; expected routing-id mismatch error log from negative test) and `test-zmq-worker-log-transport` (7 cases).
- Step 4: public API compatibility review found Haskell record fields/callbacks remain exported; JSON adds preferred aliases and optional legacy worker key while retaining old keys; docs still need Step 5 migration updates. Step 2/3 reviewer code reviews approved.
- Step 4: `cabal test lotos:test:test-zmq-log-protocol-config lotos:test:test-zmq-log-ingest lotos:test:test-zmq-worker-log-transport` passed (9 + 14 + 7 cases); expected routing-id mismatch error log appears in the LogIngest negative test.
- Step 4: `cabal build all --enable-tests` passed, including lotos tests/demos and TaskSchedule libs/executables/tests compilation.
- Step 4: `scripts/task-schedule-smoke.sh` passed for run `.tmp/task-schedule-smoke/task-schedule-smoke-20260604T061241Z-330652`; client ACK, fresh marker, `/logs/worker/simpleWorker_1`, and clean `/logs/stats` evidence recorded.
- Step 4: code review approved; test-review tool call is unavailable because the runtime schema only accepts `plan` or `code` review types.
- Step 5: updated `docs/logging-redesign.md`, mdBook `public-api.md`, `operations.md`, `compatibility.md`, TaskSchedule mdBook pages, `docs/task-schedule-mvp.md`, `docs/build-your-own-scheduler.md`, and README with old/new logging-name migration guidance. Re-ran `cabal test lotos:test:test-zmq-log-protocol-config` (9 cases) after docs/config updates.
- Step 5: marked the legacy logging compatibility fields/callbacks debt resolved in `taskplane-tasks/CONTEXT.md` with the TP-045 compatibility-path summary.
- Step 5: squashed temporary checkpoint commits into one final TP commit with Lore trailers and final STATUS completion; `git rev-list --count 5fe45eb..HEAD` reports 1.
- R001 suggestion: maintain a table mapping old name -> new name -> compatibility behavior -> docs/tests to update.

### Step 1 Compatibility Plan

Inventory table:

| Legacy/public name | Current locations | Preferred/new surface | Compatibility behavior | Docs/tests |
|---|---|---|---|---|
| `infoStorage.loggingAddr` | `InfoStorageConfig` exported record field, broker JSON/config docs, `LBS.hs` compatibility copy, config tests | `infoStorage.logIngestDefaultAddr` only when deriving a missing broker `logIngest` block; preferred runtime config is `logIngest.logIngestAddr` | Keep Haskell field exported with deprecated comment. Accept both JSON keys; if both appear, `logIngestDefaultAddr` wins for the stored compatibility/default value. If explicit `logIngest` exists, it is authoritative for runtime endpoint. | Update config parse tests, checked-in broker config/docs, compatibility docs. |
| `infoStorage.loggingsBufferSize` | `InfoStorageConfig` exported field, broker JSON/docs | `infoStorage.logIngestDefaultBufferSize` as a compatibility/default-derivation label; active retention remains `logIngest.logIngestReadCacheSize` / journal retention knobs | Keep Haskell field exported with deprecated comment. Accept both JSON keys; if both appear, `logIngestDefaultBufferSize` wins. It does not imply active `/info` log snapshots. | Add old/new/mixed broker parse tests and docs. |
| `loadBalancerLoggingAddr` | `WorkerServiceConfig` exported record field, worker JSON/config docs/tests | Prefer `workerLogging.logIngestAddr`; optional `logIngestDefaultAddr` top-level alias is only for deriving `workerLogging` when the block is omitted | Keep Haskell field exported with deprecated comment. Worker JSON accepts old key, new `logIngestDefaultAddr`, or an explicit `workerLogging` block. Explicit `workerLogging.logIngestAddr` wins runtime; absent legacy/default field is filled from the explicit workerLogging addr so record consumers keep a stable value. | Add old/new/mixed worker parse tests and update docs/config examples. |
| `taPubTaskLogging` | `TaskAcceptorAPI` exported field, facade export, README/scheduler docs | `taSendTaskLog` | Keep the old callback as a compatibility wrapper that enqueues stdout/info `LogEvent`s; improve comments/docs to say it no longer PUB/SUB publishes. New examples use `taSendTaskLog`. | Docs only plus existing WorkerLogging frame compatibility test. |
| Checked-in TaskSchedule configs | `applications/TaskSchedule/config/broker.json`, `worker.json` | Use explicit `logIngest` / `workerLogging` and new default-derivation alias names where legacy fields remain for compatibility | Update sample configs to parse through new aliases while preserving endpoint values: broker legacy default `5557`, LogIngest runtime `5558`; worker runtime `5558`. | Parse checked-in config files in tests. |

Conflict/default rules: new alias beats legacy alias inside the same object; explicit `logIngest` / `workerLogging` blocks beat any default-derivation address for runtime transport; partial explicit LogIngest blocks inherit defaults derived from the selected legacy/new default address rather than reverting to unrelated hard-coded endpoints; old-only configs keep deriving `5557 -> 5558` via `defaultReliableLogIngestAddr`.

Migration examples to document/test:

```json
// old broker JSON remains accepted
{"infoStorage":{"httpPort":8081,"loggingAddr":"tcp://127.0.0.1:5557","loggingsBufferSize":1000,"infoFetchIntervalSec":10}}

// preferred broker JSON gives LogIngest its runtime endpoint explicitly
{"infoStorage":{"httpPort":8081,"logIngestDefaultAddr":"tcp://127.0.0.1:5557","logIngestDefaultBufferSize":1000,"infoFetchIntervalSec":10},"logIngest":{"logIngestAddr":"tcp://127.0.0.1:5558"}}

// old worker JSON remains accepted
{"loadBalancerLoggingAddr":"tcp://127.0.0.1:5557"}

// preferred worker JSON relies on workerLogging for runtime logging
{"workerLogging":{"logIngestAddr":"tcp://127.0.0.1:5558"}}
```

| 2026-06-04 05:45 | Task started | Runtime V2 lane-runner execution |
| 2026-06-04 05:45 | Step 0 started | Preflight |
| 2026-06-04 05:48 | Review R001 | plan Step 1: REVISE |
| 2026-06-04 05:52 | Review R002 | plan Step 1: APPROVE |
| 2026-06-04 05:53 | Review R003 | code Step 1: APPROVE |
| 2026-06-04 05:54 | Review R004 | plan Step 2: APPROVE |
| 2026-06-04 06:02 | Review R005 | code Step 2: APPROVE |
| 2026-06-04 06:04 | Review R006 | plan Step 3: APPROVE |
| 2026-06-04 06:09 | Review R007 | code Step 3: APPROVE |
| 2026-06-04 06:10 | Review R008 | plan Step 4: APPROVE |
| 2026-06-04 06:17 | Review R009 | code Step 4: APPROVE |

| 2026-06-04 06:23 | Worker iter 1 | done in 2296s, tools: 171 |
| 2026-06-04 06:23 | Task complete | .DONE created |