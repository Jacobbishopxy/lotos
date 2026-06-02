## Code Review: Step 2: Implement protocol/config and tests

### Verdict: REVISE

### Summary
The new protocol/config surface largely matches the Step 2 plan, keeps legacy `WorkerLogging` frames intact, and the targeted protocol test plus touched TaskSchedule executables build successfully. No declared static typecheck/lint/format commands were configured in `.pi/taskplane-config.json` and there is no `package.json` fallback, so those quality checks were skipped. One protocol parsing bug needs fixing before approval because malformed sequence-number frames can be accepted as valid `Word64` values.

### Issues Found
1. **[lotos/src/Lotos/Zmq/Adt.hs:687] [important]** — `word64FromBS` parses directly with `reads :: Word64`, and GHC's `Read Word64` wraps invalid numeric input (`"-1"` becomes `18446744073709551615`, overflow can become `0`) instead of rejecting it. That means malformed `LogEvent` sequence/drop fields, `LogBatch.firstSeq`, and `LogAck.acceptedThrough` frames can silently corrupt sequence/gap metadata. Fix by parsing as a non-negative unbounded integer (or otherwise checking only digits), rejecting values above `maxBound :: Word64`, then converting with `fromInteger`; add regression cases for negative and overflow sequence frames.

### Pattern Violations
- None.

### Test Gaps
- The current tests round-trip `LogBatch`/`LogAck`, but do not pin their exact multipart frame lists; a future simultaneous encoder/decoder reorder would still pass. Add literal frame-order assertions for these public wire formats when touching the parser tests.

### Suggestions
- For partial nested broker/worker `logIngest` JSON objects, consider defaulting an omitted `logIngestAddr` from the parent `loggingAddr` / `loadBalancerLoggingAddr` rather than the standalone `5558` fallback, so early adopters can override one knob without silently changing the endpoint.

### Verification Run
- `cabal test lotos:test:test-zmq-log-protocol-config` — PASS
- `cabal build TaskSchedule:exe:ts-server TaskSchedule:exe:ts-worker` — PASS
- `git diff --check 565dc86..HEAD` — PASS
