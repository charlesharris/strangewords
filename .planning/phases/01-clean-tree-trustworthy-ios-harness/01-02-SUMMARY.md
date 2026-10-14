---
phase: 01-clean-tree-trustworthy-ios-harness
plan: "02"
subsystem: testing
tags: [swift-testing, xcodegen, xcodebuild, xcresulttool, simulator]
requires:
  - phase: 01-clean-tree-trustworthy-ios-harness (plan 01-01)
    provides: committed project.yml with App Attest prep and explicit scheme
provides:
  - Hosted StrangewordsTests unit-test target (com.strangerwords.us.tests) generated from ios/project.yml, with a scheme test action carrying explicit isolation env
  - scripts/test-ios.sh, a headless runner whose verdict comes only from the xcresult summary (exit 0/1/2)
  - scripts/test-ios-selfcheck.sh, a re-runnable proof that the verdict cannot lie (6 cases)
  - Seed Syllables characterization suite, a permanent HostIsolationTests guard, and an env-gated failing canary
  - Gitignored /build/ for verification evidence and test derived data
affects: [phase-02, phase-03, phase-04]
actuals:
  tokens: 4160
  tasks: 2
  commits: 2
plan_head_before: 8cc58a1c5badbe5d951c206411a9d3506a33b784
plan_head_after: 287c4cf1044d14e3241ac3c92cb68d2e4117b1fc
tech-stack:
  added: []
  patterns:
    - "Verdict from xcresulttool summary via jq positive match, never from xcodebuild banner or exit code"
    - "Explicit scheme test env so the test action does not inherit the Run action env"
    - "Env-gated canary test (TEST_RUNNER_ prefix) for re-provable failing verdicts"
key-files:
  created:
    - scripts/test-ios.sh
    - scripts/test-ios-selfcheck.sh
    - ios/StrangewordsTests/SyllablesTests.swift
    - ios/StrangewordsTests/HostIsolationTests.swift
    - ios/StrangewordsTests/HarnessCanary.swift
  modified:
    - ios/project.yml
    - .gitignore
key-decisions:
  - "Shut down the pinned simulator unconditionally at the end of every run (D-07), not only when the script booted it"
  - "Include SW_API_BASE=http://127.0.0.1:9 in the test env as defense in depth (research Open Question 1)"
  - "Shipped the permanent env-gated canary (research option b); the temporary-canary fallback was not needed"
requirements-completed: [HARN-02, HARN-03]
coverage:
  - id: D1
    description: "Hosted StrangewordsTests target and scheme test action survive xcodegen generate, with explicit test env"
    requirement: "HARN-02"
    verification:
      - kind: other
        ref: "xcodebuild -list lists StrangewordsTests; generated scheme TestAction has shouldUseLaunchSchemeArgsEnv = NO and SW_LOCAL_MOCK; pbxproj has com.strangerwords.us.tests; unsigned app build exit 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "scripts/test-ios.sh exits 0 with a test-ios: PASS line taken from the result-bundle summary"
    requirement: "HARN-03"
    verification:
      - kind: other
        ref: "scripts/test-ios.sh -> exit 0, PASS 4 passed / 1 skipped / 5 total with the canary skipped; pinned simulator not booted afterwards"
        status: pass
    human_judgment: false
  - id: D3
    description: "Runner exits 1 on a failing test (not retried), on zero tests despite xcodebuild's green banner, and on a missing result bundle; exits 2 on a missing simulator"
    requirement: "HARN-03"
    verification:
      - kind: other
        ref: "scripts/test-ios-selfcheck.sh -> selfcheck: PASS 6/6 (pass, isolation, zero, canary, nobundle, nosim)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Host app runs in mock mode with a dead API base and no inherited Run env during tests"
    requirement: "HARN-03"
    verification:
      - kind: unit
        ref: "HostIsolationTests (2 tests) pass under the scheme env; self-check case isolation exit 0"
        status: pass
    human_judgment: false
  - id: D5
    description: "Cold-boot bootstrap-crash retry fires exactly once and only for zero tests plus 'Early unexpected exit'"
    requirement: "HARN-03"
    verification:
      - kind: other
        ref: "Code path present in scripts/test-ios.sh; the signature cannot be produced on demand (research A1). The no-retry-on-real-failure case is proven by self-check case canary (no ios-tests-2.xcresult)"
        status: pass
    human_judgment: true
duration: 4min
completed: 2026-10-14
status: complete
---

# Phase 1 Plan 02: Trustworthy Headless iOS Test Harness Summary

**A hosted XcodeGen StrangewordsTests target and `scripts/test-ios.sh` whose pass/fail verdict comes only from the xcresulttool summary, with a committed 6-case self-check that proves zero-test, failing-test, and no-bundle runs cannot go green.**

## Performance
- **Duration:** 4 min
- **Started:** 2026-10-14T17:48:46Z
- **Completed:** 2026-10-14T17:53:00Z
- **Tasks:** 2
- **Files modified:** 7 (5 created, 2 modified)

## Accomplishments
- `ios/project.yml` now generates a `StrangewordsTests` `bundle.unit-test` target (bundle id `com.strangerwords.us.tests`; the app keeps `com.strangerwords.us`) and a `Strangewords` scheme test action with its own `SW_LOCAL_MOCK=1` and `SW_API_BASE=http://127.0.0.1:9` env, so the generated scheme has `shouldUseLaunchSchemeArgsEnv = "NO"`.
- `scripts/test-ios.sh` regenerates the project, boots the pinned iPhone 16 by exact name, runs `xcodebuild test` unsigned into `build/derived/ios-test`, and decides only from `jq -e '.result=="Passed" and .failedTests==0 and .passedTests>0 and .totalTestCount>0'`. Evidence lands in gitignored `build/verify/<timestamp>/`.
- `scripts/test-ios-selfcheck.sh` proves all six verdicts in one command: pass (including a pre-booted simulator being shut down), isolation guard, zero tests under xcodebuild's `** TEST SUCCEEDED **` banner, the failing canary (exit 1, no retry), a missing result bundle (summary exactly `{}`), and a missing simulator (exit 2).
- Test suites: 3-case `Syllables` seed (`fire`->1, empty->0, `A frog jumps into the pond`->7, kept parameterized so Phase 2 appends rows), `HostIsolationTests` (mock mode, dead API base, no `SW_DEV`), and the env-gated `HarnessCanary`.

## Task Commits
1. **Task 1 (tracer): hosted target, isolated test action, runner, seed suite** - `bcb84d6` (feat)
2. **Task 2: host-isolation guard, canary, self-check** - `287c4cf` (feat)

**Plan metadata:** recorded in the final docs commit.

## Files Created/Modified
- `ios/project.yml` - StrangewordsTests target and scheme `test:` block with explicit env (additions only, no removed lines)
- `.gitignore` - `/build/`
- `scripts/test-ios.sh` - headless runner, mode 100755
- `scripts/test-ios-selfcheck.sh` - six-case verdict proof, mode 100755
- `ios/StrangewordsTests/SyllablesTests.swift`, `HostIsolationTests.swift`, `HarnessCanary.swift` - Swift Testing suites

## Decisions Made
- D-07 applied literally: the EXIT trap shuts down the pinned UDID even when it was already booted. This ends a `run.sh` session on the same iPhone 16 (accepted threat T-01-09, documented in the script header). The research prototype's `BOOTED_BY_US` guard was dropped.
- `SW_API_BASE` dead-port line included in the test env. Assumption A6 holds: the default run passes with it present.
- **Canary form shipped:** the permanent env-gated `HarnessCanary.swift` (research option b). Assumptions A2 (a skipped canary does not break PASS: result Passed with `skippedTests` 1) and A4 (`TEST_RUNNER_` forwarding enables it) were both confirmed, so fallback (a) was not used.
- Assumption A3 confirmed: an invalid xcodebuild option produces no result bundle, the summary is exactly `{}`, and the runner exits 1.

## Deviations from Plan

None - plan executed exactly as written. No fix-as-we-go changes to `scripts/test-ios.sh` were needed after Task 1.

## Issues Encountered
- Parameterized Swift Testing functions count once per function in the summary, so the default run reports 5 total (2 Syllables functions, 2 isolation, 1 skipped canary). The verdict logic only needs counts greater than zero, so this has no effect.

## Authentication Gates
None.

## User Setup Required
None - no external service configuration required.

## Not verified (carry to Phase 4)
- App Attest entitlements are not applied in test runs, because signing is off (`CODE_SIGNING_ALLOWED=NO`, D-08).
- Only the iOS 18.6 simulator runtime is installed, so the iOS 17.0 deployment target is not exercised.
- The cold-boot "Early unexpected exit" retry signature cannot be produced on demand (research A1). Only the code path and the no-retry-on-real-failure case are proven. Behavior on newer Xcode is unverified (A5); re-run `scripts/test-ios-selfcheck.sh` after any upgrade.
- Two harness runs at once, or a run alongside `run.sh` on the same simulator, are not guarded by a lock (EDGE-HARN-03); the script header documents it.

## Next Phase Readiness
Phase 2 can grow `SyllablesTests` and add suites against a trusted runner; tests that touch `TokenStore` or `UserDefaults` need their own isolation seam (IOST-05) and `@Suite(.serialized)`. Phase 4's verify.sh can compose `scripts/test-ios.sh` through its exit code and `SW_VERIFY_OUT`.

## Known Stubs
None.

## Self-Check: PASSED

Created files present on disk (both scripts, three test files); commits `bcb84d6` and `287c4cf` are ancestors of HEAD; all task acceptance criteria and plan-level verification re-run green: `scripts/test-ios.sh` exit 0 with PASS, `scripts/test-ios-selfcheck.sh` ended `selfcheck: PASS 6/6`, unsigned `xcodebuild build` exit 0, HARN-01 ordering edge held (both 01-01 commits are ancestors of the target commit; its project.yml diff removes no lines), and `git status --porcelain` outside `.planning/` is empty.

---
*Phase: 01-clean-tree-trustworthy-ios-harness*
*Completed: 2026-10-14*
