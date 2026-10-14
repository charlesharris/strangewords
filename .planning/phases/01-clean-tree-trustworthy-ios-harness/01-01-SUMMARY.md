---
phase: 01-clean-tree-trustworthy-ios-harness
plan: "01"
subsystem: infra
tags: [git, reconcile, xcodegen, xcodebuild, go, gofmt, app-attest]
requires: []
provides:
  - Reconciled working tree: the six milestone-start dirty files are committed, none reverted
  - iOS App Attest signing prep (bundle id, team, entitlements, scheme) committed as one self-contained commit
  - Server Config.AppAttestAppID scaffold committed
  - gofmt -l server/ empty at HEAD
  - Known-good baseline: go test/vet/build and xcodegen + xcodebuild build green on HEAD and on a fresh clone of the iOS commit
affects: [01-02, phase-02, phase-03, phase-04]
actuals:
  tokens: 2864
  tasks: 3
  commits: 3
plan_head_before: 429e201d3e9ff823214ef99ca80e6d51f00f8cfa
plan_head_after: 57ba34ebcca8a84516a0b1a5b532b73501ffb9c1
tech-stack:
  added: []
  patterns:
    - "Concern-split reconciliation commits, then a separate whitespace-only formatting commit"
    - "Fresh-clone build proof for any commit that adds a file referenced from project.yml"
key-files:
  created:
    - ios/Strangewords/Strangewords.entitlements
  modified:
    - ios/project.yml
    - run.sh
    - docs/STATUS.md
    - server/DEPLOY.md
    - server/internal/config/config.go
    - server/internal/gateway/gateway_test.go
    - server/internal/sessions/session.go
    - server/internal/sessions/validate.go
    - server/internal/store/store.go
key-decisions:
  - "D-01/D-02: keep all six dirty files; commit as (a) iOS signing prep + docs and (b) server config scaffold"
  - "D-13: gofmt -w the four already-drifted server files in a separate whitespace-only commit (git diff -w empty); gofmt output accepted per CLAUDE.md"
requirements-completed: [HARN-01]
coverage:
  - id: D1
    description: "Six dirty files committed deliberately in two concern-split commits, nothing reverted"
    requirement: "HARN-01"
    verification:
      - kind: other
        ref: "git show --name-only on 436f09e and 9e137f7 matches the expected 5-path and 1-path lists; git diff --quiet HEAD on the five iOS/doc paths exited 0 right after the commit"
        status: pass
    human_judgment: false
  - id: D2
    description: "Fresh clone of the iOS commit runs xcodegen generate and an unsigned xcodebuild build"
    requirement: "HARN-01"
    verification:
      - kind: other
        ref: "git clone + checkout 436f09e; (cd ios && xcodegen generate); xcodebuild -scheme Strangewords -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build -> exit 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "Go checks green and gofmt clean at final HEAD"
    requirement: "HARN-01"
    verification:
      - kind: unit
        ref: "cd server && go test ./... && go vet ./... && go build ./... -> exit 0; gofmt -l server/ -> empty"
        status: pass
    human_judgment: false
  - id: D4
    description: "Formatting commit is whitespace-only and holds exactly the four drifted files"
    requirement: "HARN-01"
    verification:
      - kind: other
        ref: "git diff -w --quiet 57ba34e^ 57ba34e -> exit 0; git show --name-only lists the four expected paths"
        status: pass
    human_judgment: false
duration: 9min
completed: 2026-10-14
status: complete
---

# Phase 1 Plan 01: Clean Tree Reconcile Summary

**Six dirty App Attest/signing files committed in two concern-split commits plus a whitespace-only gofmt commit, leaving go test/vet/build, gofmt, and xcodegen + xcodebuild all green on HEAD and on a fresh clone of the iOS commit.**

## Performance
- **Duration:** 9 min (includes a pause at the default-branch commit guard)
- **Started:** 2026-10-14T17:35:08Z
- **Completed:** 2026-10-14T17:43:41Z
- **Tasks:** 3
- **Files modified:** 10 (1 created, 9 modified)

## Accomplishments
- The App Attest binding (bundle id `com.strangerwords.us`, team `2M6QRD8T3A`, `CODE_SIGN_ENTITLEMENTS`, per-config `APP_ATTEST_ENVIRONMENT`, `Strangewords` scheme) is committed together with its entitlements file, so a fresh clone builds.
- `Config.AppAttestAppID` (env `SW_APP_ATTEST_APPID`, empty default) committed alone.
- `gofmt -l server/` went from four files to empty without changing any token, assertion, or skip.
- No check was skipped, deleted, or narrowed; no `_test.go`, `go.mod`, or `go.sum` change except the whitespace-only reformat of `gateway_test.go`.

## Dirty-tree Baseline (before any commit)
- `go test ./...` exit 0, `go vet ./...` exit 0, `go build ./...` exit 0
- `xcodegen generate` ok; unsigned `xcodebuild build` exit 0; signed `xcodebuild build` exit 0
- `plutil -lint ios/Strangewords/Strangewords.entitlements`: OK
- `gofmt -l server/` listed exactly: `server/internal/gateway/gateway_test.go`, `server/internal/sessions/session.go`, `server/internal/sessions/validate.go`, `server/internal/store/store.go` (Task 3 reformatted these)

## Environment findings
- **Signed build:** the signed `xcodebuild build` (generic iOS Simulator destination, DEVELOPMENT_TEAM `2M6QRD8T3A` with `CODE_SIGN_ENTITLEMENTS`) exited 0 on this machine. No code-signing, provisioning, or keychain error occurred, so there is nothing to carry to Phase 4 from the signed build. The unsigned build (`CODE_SIGNING_ALLOWED=NO`) also exited 0; unsigned builds do not exercise the entitlements.
- **Default-branch guard:** the pre-commit assertion initially refused to commit on `main` because `git.allow_default_branch_commits` was unset. The execution halted before any commit. The orchestrator then set `git.allow_default_branch_commits: true` in `.planning/config.json`; I confirmed it with `config-get` and confirmed the guard returned `false` before committing.
- No iOS 17.x simulator runtime is installed (only 18.6); carried forward from research to Phase 4's not-verified list.

## Task Commits
1. **Task 1: iOS App Attest signing prep + docs** - `436f09e` (chore)
2. **Task 2: server AppAttestAppID config scaffold** - `9e137f7` (chore)
3. **Task 3: accept gofmt output on hand-aligned server blocks** - `57ba34e` (style)

**Plan metadata:** recorded in the final docs commit (docs: complete plan).

## Files Created/Modified
- `ios/project.yml` - bundle id, team, entitlements, APP_ATTEST_ENVIRONMENT per config, explicit Strangewords scheme
- `ios/Strangewords/Strangewords.entitlements` - App Attest environment entitlement (new, tracked)
- `run.sh` - BUNDLE set to `com.strangerwords.us`
- `docs/STATUS.md`, `server/DEPLOY.md` - bundle-id and App Attest binding notes
- `server/internal/config/config.go` - `AppAttestAppID` scaffold
- `gateway_test.go`, `session.go`, `validate.go`, `store.go` - gofmt realignment only

## Decisions Made
- D-13: the four drifted server files were reformatted with gofmt in their own commit after both reconciliation commits, rather than deferred to Phase 4. Proven whitespace-only.
- The whitespace-only proof was scoped to the four paths (`git diff -w --quiet -- <paths>`) because `.planning/` files are legitimately dirty during execution.

## Deviations from Plan

**1. [Rule 3 - Blocking issue] Whitespace check scoped to the four paths**
- **Found during:** Task 3
- **Issue:** The plan's unscoped `git diff -w --quiet` exited non-zero, because `.planning/STATE.md` and `.planning/config.json` are modified.
- **Fix:** Re-ran scoped to the four server paths (exit 0). The commit-level proof `git diff -w --quiet 57ba34e^ 57ba34e` was run unscoped and exited 0.
- **Files modified:** none
- **Commit:** n/a

**Total deviations:** 1 auto-fixed (1 blocking). **Impact:** none on outputs.

## Issues Encountered
- A transient halt at the default-branch commit guard (see Environment findings), resolved by an explicit config setting before any commit was made.

## Authentication Gates
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
Plan 01-02 can add the test target on a reconciled tree. The reconciliation commits are looked up by subject: `chore(01-01): commit iOS App Attest signing prep and the docs that describe it` and `chore(01-01): commit server AppAttestAppID config scaffold`.

## Known Stubs
None.

## Self-Check: PASSED

Entitlements file present; commits 436f09e, 9e137f7, 57ba34e are ancestors of HEAD; all task acceptance criteria and plan-level verification re-run green on the final HEAD (`git status --porcelain` outside `.planning/` empty).

---
*Phase: 01-clean-tree-trustworthy-ios-harness*
*Completed: 2026-10-14*
