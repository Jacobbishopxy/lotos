# TP-052: Package/release polish — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-04
**Review Level:** 2
**Review Counter:** 10
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied

---

### Step 1: Assess current state and design
**Status:** ✅ Complete

- [x] Add concise Step 1 plan artifact covering baseline warning capture, PVP criteria, documentation targets, scope guard, and non-release gap logging
- [x] Run `cabal check lotos` and `cabal check TaskSchedule` to capture current warnings
- [x] Decide and document a conservative PVP/upper-bound policy for this pre-release workspace
- [x] Add or adjust Cabal upper bounds only when they are supportable by current tested dependency versions
- [x] Add release-readiness notes and known non-release gaps
- [x] Document that the tested GHC 9.14.1 dependency plan currently requires the workspace `allow-newer` override and log that strict published-metadata solving remains future work

**Step 1 plan (R001 response):**
- Capture current packaging warnings by running `cabal check lotos` and `cabal check TaskSchedule`; record the warning classes in STATUS notes, then use them to choose only package/docs metadata changes.
- Document a conservative pre-release policy in release/compatibility/public API docs: follow PVP-style lower bounds already encoded by Cabal, add upper bounds only when the workspace has evidence from current tested versions or Cabal metadata, and avoid narrow pins without support evidence.
- Treat the absent `docs/book/lotos/src/release.md` as a candidate release-readiness page; if created, add it to `docs/book/lotos/src/SUMMARY.md` and cross-link affected existing docs/README only where release guidance changes.
- Preserve runtime behavior and protocol frame shapes; do not edit Haskell runtime code merely to silence `cabal check` warnings.
- Log non-release gaps in `taskplane-tasks/CONTEXT.md` when they are future work, and mirror important task-local discoveries in STATUS notes.

---

### Step 2: Implement focused changes
**Status:** ✅ Complete

- [x] Confirm the package/docs changes are the smallest scoped implementation for the mission
- [x] Preserve current public/runtime behavior; no runtime source changes made merely to silence package warnings
- [x] Confirm no targeted regression coverage is needed because changes are Cabal metadata and docs only
- [x] Run targeted package/docs checks before moving to full verification

**Step 2 plan:**
- Review the current diff against the Step 1 baseline and keep only Cabal metadata plus release/readiness documentation edits required by the mission.
- Verify no runtime Haskell modules, protocol frame definitions, or demo behavior files changed.
- Treat Cabal metadata/docs changes as not needing new runtime regression tests; use package-local `cabal check` and `make book-build` as targeted checks before the full verification step.

---

### Step 3: Documentation alignment
**Status:** ✅ Complete

- [x] Must-update docs (`README.md`, verification, compatibility, public API, release, SUMMARY) modified or confirmed unaffected
- [x] Check-if-affected docs (`taskplane-tasks/CONTEXT.md`, README, SUMMARY) reviewed
- [x] Follow-up gaps logged in `taskplane-tasks/CONTEXT.md` when found

**Step 3 plan:**
- Inspect the documentation diff to ensure every Must Update doc has either a relevant edit or an explicit unaffected decision.
- Verify `SUMMARY.md` includes the new release page and README links point to the mdBook release guidance.
- Confirm future package-release gaps from the release page are mirrored in `taskplane-tasks/CONTEXT.md`.

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Run package-local `cabal check` for `lotos` and TaskSchedule
- [x] `make ci-check` passes
- [x] `make book-build` passes
- [x] All failures fixed and generated mdBook output removed from the worktree

**Step 4 plan:**
- Run the package-local `cabal check` commands first to prove Cabal metadata is warning-free.
- Run the full project gate `make ci-check`, then run `make book-build` explicitly because documentation changed and the prompt requires it.
- If mdBook generates `docs/book/lotos/book/`, remove that generated output before committing or handoff.

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] "Must Update" docs modified
- [x] "Check If Affected" docs reviewed
- [x] Discoveries logged

---

## Discoveries

| Date | Discovery | Follow-up |
|------|-----------|-----------|
| 2026-06-04 | First-release upper bounds are warning-free for public library dependencies, but oldest-supported dependency versions were not audited. | Logged in `taskplane-tasks/CONTEXT.md` as lower-bound/oldest-dependency support future work. |
| 2026-06-04 | The current GHC 9.14.1 dependency plan relies on workspace `allow-newer` because `servant-server-0.20.3.0` metadata excludes `base-4.22`. | Logged in `taskplane-tasks/CONTEXT.md` as strict package solver profile future work. |
| 2026-06-04 | Public release packaging still depends on the git-pinned `zmqx` source repository unless a released artifact or explicit source-access guidance is provided. | Logged in `taskplane-tasks/CONTEXT.md` as public `zmqx` release/source guidance future work. |

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | plan | Step 1 | REVISE | `.reviews/R001-plan-step1.md` |
| R002 | plan | Step 1 | APPROVE | `.reviews/R002-plan-step1.md` |
| R003 | code | Step 1 | REVISE | `.reviews/R003-code-step1.md` |
| R004 | code | Step 1 | APPROVE | `.reviews/R004-code-step1.md` |
| R005 | plan | Step 2 | APPROVE | `.reviews/R005-plan-step2.md` |
| R006 | code | Step 2 | APPROVE | `.reviews/R006-code-step2.md` |
| R007 | plan | Step 3 | APPROVE | `.reviews/R007-plan-step3.md` |
| R008 | code | Step 3 | APPROVE | `.reviews/R008-code-step3.md` |
| R009 | plan | Step 4 | APPROVE | `.reviews/R009-plan-step4.md` |
| R010 | code | Step 4 | APPROVE | `.reviews/R010-code-step4.md` |

---

## Notes

| 2026-06-04 14:51 | Task started | Runtime V2 lane-runner execution |
| 2026-06-04 14:51 | Step 0 started | Preflight |
| 2026-06-04 | Preflight | Verified task/status/context and scoped source/doc paths; `docs/book/lotos/src/release.md` is absent and will be created if the design keeps a release page. TP-051 status is complete. |
| 2026-06-04 | Step 1 started | Assess current state and design |
| 2026-06-04 | Review R001 | plan Step 1: REVISE; added required plan-artifact revision item. Suggestion noted: keep plan outcome-level and concise. |
| 2026-06-04 14:54 | Review R001 | plan Step 1: REVISE |
| 2026-06-04 14:56 | Review R002 | plan Step 1: APPROVE |
| 2026-06-04 | Review R002 suggestion | Distinguish package metadata bounds from workspace-only `cabal.project` settings such as `allow-newer` and the `zmqx` source pin. |
| 2026-06-04 | Cabal check baseline | `cabal check <path>` is unsupported by this Cabal (`Cabal-7055`), so ran package-local equivalents. `lotos`: only `missing-upper-bounds` for 23 library deps. `TaskSchedule`: only `missing-upper-bounds` for ts-client/server/worker libs (`aeson`, `bytestring`, `lotos`, `process`, `text` as applicable). |
| 2026-06-04 | PVP/upper-bound policy decision | For first release readiness, add package metadata upper bounds only for dependencies reported by `cabal check` in public libraries, using the next PVP major-version boundary above the `cabal build all --enable-tests --dry-run` plan (`aeson-2.3`, `servant-0.20`, `zmqx-0.1.1.1`, etc.). Do not add unsupported lower-bound claims, do not constrain test/demo-only deps unless `cabal check` requires it, and document that `cabal.project` `allow-newer`/git source pins are workspace development overrides rather than published package policy. |
| 2026-06-04 | Cabal bounds applied | Added upper bounds to `lotos` and TaskSchedule public library dependencies only, using next PVP major-version ceilings above the dry-run dependency plan. Package-local `cabal check` now reports no warnings for both packages. |
| 2026-06-04 | Release notes/gaps | Created mdBook Release Readiness notes, linked them from SUMMARY/README/compatibility/public API/verification docs, and logged future release gaps for lower-bound audits and the git-pinned `zmqx` dependency in `taskplane-tasks/CONTEXT.md`. |
| 2026-06-04 15:08 | Review R003 | code Step 1: REVISE |
| 2026-06-04 | Review R003 suggestion | Keep package-local `cabal check` command wording; it matches this cabal-install behavior and passed in review. |
| 2026-06-04 | R003 fix | Release docs, README, compatibility notes, and taskplane context now state that the current GHC 9.14.1 plan relies on workspace `allow-newer` due upstream `servant-server`/`base-4.22` metadata; strict published-metadata solving remains future work. `make book-build` passed after the doc edits. |
| 2026-06-04 15:12 | Review R004 | code Step 1: APPROVE |
| 2026-06-04 | Step 2 started | Implement focused changes |
| 2026-06-04 | Step 2 scope check | Diff is limited to Cabal metadata, release/readiness docs, README links, and taskplane context/status/review files; no runtime behavior implementation files are in scope. |
| 2026-06-04 | Runtime behavior preservation check | `git diff --name-only` against the Step 1 baseline shows no `lotos/src`, TaskSchedule `src`/`app`, config, or script changes. |
| 2026-06-04 | Targeted coverage decision | No runtime regression test added because the diff is Cabal dependency metadata and documentation only; package-local `cabal check` and mdBook build are the targeted checks. |
| 2026-06-04 | Step 2 targeted checks | `(cd lotos && cabal check)`, `(cd applications/TaskSchedule && cabal check)`, and `make book-build` all passed; removed generated `docs/book/lotos/book/` output after the docs build. |
| 2026-06-04 15:14 | Review R005 | plan Step 2: APPROVE |
| 2026-06-04 15:17 | Review R006 | code Step 2: APPROVE |
| 2026-06-04 | Step 3 started | Documentation alignment |
| 2026-06-04 | Must-update docs check | `README.md`, `verification.md`, `compatibility.md`, `public-api.md`, new `release.md`, and `SUMMARY.md` all have release-readiness relevant edits/links. |
| 2026-06-04 | Check-if-affected docs check | `taskplane-tasks/CONTEXT.md`, `README.md`, and `SUMMARY.md` were reviewed/updated for release guidance links and follow-up debt. |
| 2026-06-04 | Follow-up gaps logged | Context now records lower-bound/oldest-dependency audit, public `zmqx` release/source guidance, and strict solver profile without `allow-newer` as future work. |
| 2026-06-04 15:19 | Review R007 | plan Step 3: APPROVE |
| 2026-06-04 15:22 | Review R008 | code Step 3: APPROVE |
| 2026-06-04 | Step 4 started | Testing & Verification |
| 2026-06-04 | Step 4 cabal check | `(cd lotos && cabal check)` and `(cd applications/TaskSchedule && cabal check)` passed with no errors or warnings. |
| 2026-06-04 | Step 4 ci-check | `make ci-check` passed: built all components/tests/demos, ran the explicit bounded regression target list, and built the mdBook. |
| 2026-06-04 | Step 4 book-build | Explicit `make book-build` passed after `make ci-check`. |
| 2026-06-04 | Step 4 cleanup | No verification failures remained; removed generated `docs/book/lotos/book/` output and confirmed it is not tracked. |
| 2026-06-04 15:24 | Review R009 | plan Step 4: APPROVE |
| 2026-06-04 15:29 | Review R010 | code Step 4: APPROVE |
| 2026-06-04 | Step 5 started | Documentation & Delivery |
| 2026-06-04 | Delivery must-update docs | Verified final diff includes all Must Update docs: README, verification, compatibility, public API, release, and SUMMARY. |
| 2026-06-04 | Delivery check-if-affected docs | Reviewed/updated `taskplane-tasks/CONTEXT.md`, README, and SUMMARY; SUMMARY links the new Release Readiness page. |
| 2026-06-04 | Delivery discoveries | STATUS Discoveries and taskplane context now record lower-bound audit, strict solver without `allow-newer`, and public `zmqx` release/source guidance future work. |

| 2026-06-04 15:33 | Worker iter 1 | done in 2513s, tools: 178 |
| 2026-06-04 15:33 | Task complete | .DONE created |