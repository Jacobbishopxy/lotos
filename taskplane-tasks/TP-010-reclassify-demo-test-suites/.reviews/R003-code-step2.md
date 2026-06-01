## Code Review: Step 2: Apply test metadata/code/docs changes

### Verdict: REVISE

### Summary
The Cabal reclassification is mostly sound: `cabal build all --enable-tests` and `timeout 120s cabal test all` both passed, and `cabal test all` now runs only the three bounded regression suites. No declared typecheck/lint/format-check commands were configured in `.pi/taskplane-config.json`, and there is no `package.json`, so static quality checks were skipped. One documented demo command is not actually useful from the repository root, which violates the task requirement to preserve a documented way to run the demos.

### Issues Found
1. **[lotos/test/ConcExecutor2.hs:46] [important]** — The README documents `cabal run lotos:exe:demo-conc-executor2` from the repo-level verification section, but running that command from the repository root makes every helper-script command fail with `bash: ../scripts/rand.sh: No such file or directory` / `bash: ../scripts/fail.sh: No such file or directory`. Fix by either making the demo use repo-root-relative paths (`scripts/...`, `.tmp/...`) for the documented command, or documenting/running it from the `lotos/` working directory and verifying the helper scripts are found. Consider failing fast if required helper scripts are missing so the demo cannot silently print only path errors.

### Pattern Violations
- `hie.yaml:24` still maps `lotos/test` to removed Cabal components such as `lotos:test:test-logger`, `lotos:test:test-event-trigger`, `lotos:test:test-conc-executor2`, and `lotos:test:test-zmq-xt`; `cabal build lotos:test:test-logger` now reports `Unknown target`. Update the HLS cradle to active components (`lotos:exe:demo-*` for demos and the remaining `lotos:test:*` regression suites), preferably with file-specific paths.

### Test Gaps
- No additional blocking gaps beyond the failing documented demo command above. Review-time checks run: `cabal build all --enable-tests` passed, `timeout 120s cabal test all` passed, and `timeout 30s cabal run lotos:exe:demo-conc-executor2` exposed the helper-path failure.

### Suggestions
- After fixing the demo path, record the intentional demo command status in Step 3 along with the already passing build/regression commands.
