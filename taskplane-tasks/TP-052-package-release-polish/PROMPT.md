    # Task: TP-052 - Package/release polish

    **Created:** 2026-06-04
    **Size:** M

    ## Review Level: 2 (Plan and Code)

    **Assessment:** This task is release-readiness work with bounded implementation scope and explicit verification. It may touch package metadata, runtime scheduling/observability, or docs/tests depending on the packet.
    **Score:** Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 2

    ## Canonical Task Folder

    ```
    /home/xiey/Code/lotos/taskplane-tasks/TP-052-package-release-polish/
    ├── PROMPT.md   ← This file (immutable above --- divider)
    ├── STATUS.md   ← Execution state (worker updates this)
    ├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
    └── .DONE       ← Created when complete
    ```

    ## Mission

    Prepare package metadata for first release readiness by adding a clear dependency upper-bound/PVP policy, reducing `cabal check` noise where appropriate, and documenting release notes without changing runtime behavior.

    ## Dependencies

    - **Task:** TP-051 must be complete

    ## Context to Read First

    **Tier 2 (area context):**
    - `taskplane-tasks/CONTEXT.md`

    **Tier 3 (load only if needed):**
    - `README.md` — top-level user guidance
    - `Makefile` — current verification targets
    - `docs/book/lotos/src/verification.md` — verification profile
    - `docs/book/lotos/src/runtime-failures.md` — operator recovery guidance if present
    - `docs/book/lotos/src/protocol-compatibility.md` — protocol compatibility policy if protocol-adjacent
    - `lotos/src/Lotos/Zmq/Adt.hs` — protocol payloads if protocol-adjacent

    ## Environment

    - **Workspace:** repository root
    - **Services required:** None unless the task explicitly chooses to run smoke scripts

    ## File Scope

    - `lotos/lotos.cabal`
- `applications/TaskSchedule/TaskSchedule.cabal`
- `cabal.project`
- `README.md`
- `docs/book/lotos/src/verification.md`
- `docs/book/lotos/src/compatibility.md`
- `docs/book/lotos/src/public-api.md`
- `docs/book/lotos/src/release.md`
- `docs/book/lotos/src/SUMMARY.md`
- `taskplane-tasks/CONTEXT.md`

    ## Steps

    ### Step 0: Preflight

    - [ ] Required files and paths exist
    - [ ] Dependencies satisfied

    ### Step 1: Assess current state and design

    - [ ] Run `cabal check lotos` and `cabal check TaskSchedule` to capture current warnings
- [ ] Decide and document a conservative PVP/upper-bound policy for this pre-release workspace
- [ ] Add or adjust Cabal upper bounds only when they are supportable by current tested dependency versions
- [ ] Add release-readiness notes and known non-release gaps

    **Artifacts:**
    - Files from the File Scope above (modified/new as needed)

    ### Step 2: Implement focused changes

    - [ ] Make the smallest implementation/doc/test changes that satisfy the mission
    - [ ] Preserve current public behavior unless the task explicitly calls for a behavior change
    - [ ] Add or update targeted regression coverage where runtime or package behavior changes
    - [ ] Run targeted tests before moving to full verification

    **Artifacts:**
    - Files from the File Scope above (modified/new as needed)

    ### Step 3: Documentation alignment

    - [ ] Update Must Update docs
    - [ ] Review Check If Affected docs
    - [ ] Log any discovered future work in `taskplane-tasks/CONTEXT.md`

    ### Step 4: Testing & Verification

    - [ ] Run `cabal check lotos` and `cabal check TaskSchedule`
- [ ] Run `make ci-check`
- [ ] Run `make book-build`
    - [ ] Fix all failures

    ### Step 5: Documentation & Delivery

    - [ ] "Must Update" docs modified
    - [ ] "Check If Affected" docs reviewed
    - [ ] Discoveries logged in STATUS.md and taskplane context if future work remains

    ## Documentation Requirements

    **Must Update:**
    - `README.md` — update if affected
- `docs/book/lotos/src/verification.md` — update if affected
- `docs/book/lotos/src/compatibility.md` — update if affected
- `docs/book/lotos/src/public-api.md` — update if affected
- `docs/book/lotos/src/release.md` — update if affected
- `docs/book/lotos/src/SUMMARY.md` — update if affected

    **Check If Affected:**
    - `taskplane-tasks/CONTEXT.md` — log discoveries or close debt items
    - `README.md` — update if top-level user commands or release guidance changes
    - `docs/book/lotos/src/SUMMARY.md` — update if new mdBook pages are added

    ## Completion Criteria

    - [ ] Mission satisfied with scoped changes
    - [ ] Required targeted tests pass
    - [ ] `make ci-check` and/or documented equivalent passes when applicable
    - [ ] `make book-build` passes when docs changed
    - [ ] No new dependencies added

    ## Git Commit Convention

    Commits happen at **step boundaries**. All commits for this task MUST include `TP-052` for traceability.

    ## Do NOT

    - Do not add dependencies
- Do not pin overly narrow upper bounds without evidence
- Do not change runtime behavior merely to silence package warnings
    - Skip verification
    - Leave generated `docs/book/lotos/book/` committed

    ---

    ## Amendments (Added During Execution)
