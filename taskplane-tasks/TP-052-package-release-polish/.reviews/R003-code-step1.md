## Code Review: Step 1: Assess current state and design

### Verdict: REVISE

### Summary
The Cabal upper-bound additions are mechanically aligned with the current dependency plan, and package-local `cabal check` plus `make book-build` pass. Project quality-check commands are not configured in `.pi/taskplane-config.json` and there is no `package.json`, so no declared typecheck/lint/format command was available to run. However, the release-readiness docs currently omit a material package-metadata gap: the GHC 9.14.1 plan depends on the workspace `allow-newer` override, while published `.cabal` metadata alone does not resolve.

### Issues Found
1. **[docs/book/lotos/src/release.md:7] [important]** — The release policy says the bounds are based on a verified GHC 9.14.1 plan, while lines 11-15 describe `allow-newer: all` as only a workspace/development override and the known-gap list does not mention that this override is currently required for the tested plan. A strict dry-run using the same packages/source repo but without `allow-newer` fails: `Error: [Cabal-7107] Could not resolve dependencies ... rejecting: servant-server-0.20.3.0 (conflict: ... servant-server => base>=4.16.4.0 && <4.22)` under GHC 9.14.1. Fix by documenting this as a non-release/public-metadata gap (and in `taskplane-tasks/CONTEXT.md` if it remains future work), or by changing the release profile/bounds to a dependency/GHC plan that resolves without the workspace override.

### Pattern Violations
- None found.

### Test Gaps
- No test gap for runtime behavior; this step is package metadata/docs only. The missing verification is a strict package-metadata solver check that respects published bounds and omits workspace `allow-newer`.

### Suggestions
- Keep the current package-local `cabal check` command wording; it matches this cabal-install behavior and both package checks passed during review.
