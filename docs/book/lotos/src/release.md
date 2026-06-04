# Release Readiness

This workspace is preparing a first `0.1.0.0` release of the `lotos` library and the TaskSchedule demo package. The current release-polish policy is conservative: improve package metadata and documentation without changing runtime behavior, protocol frames, scheduler semantics, or demo defaults.

## Dependency bounds policy

`lotos/lotos.cabal` and `applications/TaskSchedule/TaskSchedule.cabal` carry upper bounds on public-library dependencies reported by `cabal check`. Bounds are chosen at the next PVP major-version boundary above the dependency versions selected by the verified `cabal build all --enable-tests --dry-run` plan for GHC 9.14.1. For example, the current plan selected `aeson-2.3.0.0`, `servant-0.20.3.0`, `text-2.1.3`, and `zmqx-0.1.1.1`, so the package metadata uses ceilings such as `<2.4`, `<0.21`, `<2.2`, and `<0.2` respectively.

The bounds are intentionally not lower-bound claims. Aside from the existing `base >=4 && <5` constraint, this pre-release has not audited the oldest dependency versions that can build and pass the regression suite. Do not add lower bounds or narrower upper bounds without evidence from a build/test matrix.

Workspace-only settings are not release policy:

- `cabal.project` pins `zmqx` through a `source-repository-package` entry for local development.
- `allow-newer: all` and setup constraints are solver/development overrides for this checkout.
- The current GHC 9.14.1 dependency plan relies on that `allow-newer` override: a strict solver run without it rejects `servant-server-0.20.3.0` because its published `base <4.22` bound does not include GHC 9.14.1's `base-4.22.0.0`.
- Published package metadata should be read from the package `.cabal` files, not from those workspace overrides, and public release packaging still needs a strict metadata plan that resolves without `allow-newer` or a documented compiler/dependency profile that does.

## Package metadata checks

Run package-local `cabal check` commands before release packaging:

```bash
(cd lotos && cabal check)
(cd applications/TaskSchedule && cabal check)
```

With the current bounds these commands report no package warnings. Some cabal-install versions reject `cabal check <path>` with `Cabal-7055`, so the package-local form is the portable command used by this repository.

## Release verification profile

The routine release-readiness gate remains:

```bash
make ci-check
make book-build
```

`make ci-check` compiles every package, test suite, and demo executable with tests enabled, runs the bounded regression target list, and builds this mdBook. Runtime smoke helpers remain opt-in and should be run when release notes or runtime examples change materially.

## Known non-release gaps

These items are documented so the first package release does not imply unsupported guarantees:

- `zmqx` is currently consumed from a pinned git source repository. A public package release should either publish/consume a released `zmqx` artifact or document the source access requirement clearly for downstream users.
- Strict published-metadata solving without the workspace `allow-newer` override does not currently resolve on GHC 9.14.1 because upstream `servant-server` metadata excludes `base-4.22`. Before a public release, either use a compiler/dependency profile that resolves strictly or wait for/update to metadata that supports GHC 9.14.1 without `allow-newer`.
- Oldest-supported dependency versions have not been audited; current bounds only state the next breaking-version ceiling above the verified dependency plan.
- The repository documents a local `make ci-check` gate but does not include a hosted CI workflow.
- Runtime observability gaps called out in the [Runtime Failure Runbook](runtime-failures.md) remain future operational hardening work and are not changed by package metadata polish.
