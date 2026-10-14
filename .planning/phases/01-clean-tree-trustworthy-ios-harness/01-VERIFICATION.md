---
phase: 01-clean-tree-trustworthy-ios-harness
verified: 2026-10-14T18:30:00Z
status: passed
score: 8/9 must-haves verified
covered_files:
  - ".gitignore"
  - ".planning/phases/01-clean-tree-trustworthy-ios-harness/01-01-PLAN.md"
  - ".planning/phases/01-clean-tree-trustworthy-ios-harness/01-01-SUMMARY.md"
  - ".planning/phases/01-clean-tree-trustworthy-ios-harness/01-02-PLAN.md"
  - ".planning/phases/01-clean-tree-trustworthy-ios-harness/01-02-SUMMARY.md"
  - "ios/Strangewords/Strangewords.entitlements"
  - "ios/StrangewordsTests/HarnessCanary.swift"
  - "ios/StrangewordsTests/HostIsolationTests.swift"
  - "ios/StrangewordsTests/SyllablesTests.swift"
  - "ios/project.yml"
  - "run.sh"
  - "scripts/test-ios-selfcheck.sh"
  - "scripts/test-ios.sh"
  - "server/internal/config/config.go"
covered_digest: "v3:sha256:9d11cfdf868e7d665b91eff4beae58d209e5bffc73b0e95a4557fd83bab8b1cd"
behavior_unverified: 1
overrides_applied: 1
overrides:
  - must_have: "A cold-boot bootstrap crash triggers exactly one retry into attempt-2 evidence paths"
    reason: "Signature cannot be produced on demand; carried to Phase 4 per plan 01-02"
    accepted_by: "Charles Harris"
    accepted_at: "2026-10-14T18:02:49Z"
behavior_unverified_items:
  - truth: "A cold-boot bootstrap crash (zero tests plus 'Early unexpected exit') triggers exactly one retry into attempt-2 evidence paths (verification: backstop)"
    test: "Reproduce or stub the 'Early unexpected exit' signature once (for example a PATH-stubbed xcodebuild) and run scripts/test-ios.sh"
    expected: "ios-tests-2.xcresult and ios-summary-2.json exist, exactly one retry occurs, and the verdict comes from attempt 2"
    why_human: "The signature cannot be produced on demand (research A1). Only the code path and the no-retry-on-real-failure case are evidenced, so presence and wiring cannot prove the retry behavior."
human_verification:
  - test: "Accept or exercise the cold-boot retry path (backstop truth)"
    expected: "Either record an override accepting that this is carried to Phase 4 as the plan states, or stub the signature and confirm one retry"
    why_human: "Non-inferable truth; no passing test exercises it. The plan and the orchestrator both flag it as a deliberate Phase 4 carry-over, so this is not a goal gap, but it needs an explicit human acceptance."
gaps: []
deferred:
  - truth: "App Attest entitlements are applied in a test run; iOS 17.0 deployment target is exercised; concurrent harness runs are locked"
    addressed_in: "Phase 4"
    evidence: "Carried to the Phase 4 not-verified list in 01-02-SUMMARY.md (D-08 unsigned runs; only the iOS 18.6 runtime installed; EDGE-HARN-03 documented in the script header)"
---

# Phase 1: Clean Tree & Trustworthy iOS Harness Verification Report

**Phase Goal:** The developer starts from a deliberate, reconciled tree where every existing check passes, and can run an iOS test suite headlessly with a pass/fail verdict that cannot report a false green
**Verified:** 2026-10-14T18:30:00Z
**Status:** human_needed
**Re-verification:** No, initial verification

## Goal Achievement

The goal is achieved in the codebase. All five ROADMAP success criteria are verified. The one item left open is the plan's own `verification: backstop` truth (cold-boot retry), which is non-inferable and routes to human acceptance. It is not a gap.

### Observable Truths

| #   | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| SC1 | Each of the six dirty files was deliberately committed or reverted, and `git status` is clean | ✓ VERIFIED | Commit `436f09e` holds exactly docs/STATUS.md, Strangewords.entitlements, project.yml, run.sh and server/DEPLOY.md. Commit `9e137f7` holds only server/internal/config/config.go. `git status --porcelain` shows only `.planning/config.json`, `.planning/milestone.lock` and `.planning/state.json`. These are outside the criterion's scope (paths outside `.planning/`). `ios/Strangewords/Strangewords.entitlements` is tracked in `git ls-files`. |
| SC2 | `go test`, `go vet` and `go build` pass in `server/`; `xcodegen generate` plus `xcodebuild build` succeed | ✓ VERIFIED | Re-ran at HEAD: `go build ./...` and `go vet ./...` exit 0, `go test ./...` ok (cmd/server, gateway, sessions), `gofmt -l server/` empty. `xcodegen generate` re-ran cleanly. The xcodebuild build is exercised by every `xcodebuild test` run in the recorded evidence, and there are no ios/scripts/server changes since `287c4cf`. The plan summary also records a fresh-clone unsigned build at `436f09e`, which I did not re-run. |
| SC3 | After a fresh `xcodegen generate`, the scheme has a test action and a hosted unit-test target, and a trivial test runs headlessly and passes | ✓ VERIFIED | `project.yml` declares `StrangewordsTests` as `type: bundle.unit-test` with a dependency on the app. The regenerated scheme has a `TestableReference` for `StrangewordsTests`, and pbxproj contains `com.strangerwords.us.tests` (2 hits). Recorded run `build/verify/20261014-125345`: `PASS {"passedTests":4,"failedTests":0,"skippedTests":1,"totalTestCount":5}`, `result: Passed`, simulator iPhone 16 / iOS 18.6. |
| SC4 | The CLI test command exits non-zero on a test failure AND on zero executed tests; the verdict comes from the result bundle, not the banner | ✓ VERIFIED | `scripts/test-ios.sh` decides only via `jq -e '.result=="Passed" and .failedTests==0 and .passedTests>0 and .totalTestCount>0'` on the xcresulttool summary. The missing-bundle fallback `{}` cannot match. Self-check evidence: `zero` shows `FAIL {"result":"unknown","passedTests":0,"totalTestCount":0} (xcodebuild rc=0)`, and its log contains `** TEST SUCCEEDED **` (banner count 1), so the override is non-vacuous. `canary` shows `FAIL ... failedTests:1 (rc=65)` with no `ios-tests-2.xcresult`. `nobundle` shows `FAIL` with a null summary. `nosim` prints "no available simulator named" (exit 2). |
| SC5 | While tests run, the host app launches in local-mock mode, so no test can reach production through a leftover token | ✓ VERIFIED | The scheme test action sets its own env (`SW_LOCAL_MOCK=1`, `SW_API_BASE=http://127.0.0.1:9`) with `shouldUseLaunchSchemeArgsEnv = "NO"`. The Run action's `SW_DEV` is absent from the test env. `AppModel.init` selects `LocalBackend` and calls `TokenStore.clear()` when `SW_LOCAL_MOCK == "1"`. `HostIsolationTests` (2 tests) asserts the env, and the `isolation` self-check case passed (2/2). See IN-02: the guard checks the env, not the selected backend directly. |
| P1 | Plan 01-01: exactly two concern-split commits, plus a separate whitespace-only gofmt commit; same-commit project.yml and entitlements | ✓ VERIFIED | Commit subjects and file lists match the plan exactly. `57ba34e` holds the four drifted server files, and the review independently confirmed it is whitespace-only. Both reconcile commits are ancestors of `bcb84d6`. |
| P2 | Plan 01-02: the project.yml diff adds the test target and removes no lines | ✓ VERIFIED | `git diff --numstat bcb84d6^ bcb84d6 -- ios/project.yml` gives `29 0`. |
| P3 | Evidence lands in gitignored `build/verify/<timestamp>/`, test derived data is isolated, and the pinned simulator is shut down after a run (even if pre-booted) | ✓ VERIFIED | `/build/` is in `.gitignore`. `DERIVED=build/derived/ios-test`, not `run.sh`'s directory. The EXIT trap shuts down the pinned UDID. `xcrun simctl list devices booted` is currently empty. The self-check `pass` case asserts shutdown after a pre-booted run. |
| P4 | A cold-boot bootstrap crash triggers exactly one retry into attempt-2 paths (`verification: backstop`) | ? UNCERTAIN (PRESENT_BEHAVIOR_UNVERIFIED) | The code path exists (`scripts/test-ios.sh` lines 100-103: `totalTestCount == 0` plus `grep "Early unexpected exit"` calls `run_once 2`). No test exercises the retry branch (review IN-01). The negative half, no retry on a real failure, is proven by the `canary` case. Routed to human acceptance. |

**Score:** 8/9 truths verified (1 present, behavior-unverified). The ROADMAP SC1-SC5 and the plan truths P1-P3 are counted; P4 is the sole open item.

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | App Attest entitlements are not applied in unsigned test runs | Phase 4 | 01-02-SUMMARY "Not verified (carry to Phase 4)" |
| 2 | The iOS 17.0 deployment target is exercised only on an 18.6 runtime | Phase 4 | Same list; no iOS 17.x runtime is installed |
| 3 | No concurrent-run lock between two harness runs, or between a harness run and `run.sh` | Phase 4 | Documented in the `scripts/test-ios.sh` header (EDGE-HARN-03) |

These were designated carry-overs and are not counted as gaps.

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `ios/project.yml` | `StrangewordsTests` bundle.unit-test target and a scheme test action with explicit env | ✓ VERIFIED | Present, substantive, additions only, and survives `xcodegen generate`. |
| `ios/Strangewords/Strangewords.entitlements` | Tracked entitlements referenced by project.yml | ✓ VERIFIED | Tracked, and committed in the same commit as project.yml. |
| `ios/StrangewordsTests/SyllablesTests.swift` | 3 seed cases | ✓ VERIFIED | `fire` -> 1, empty -> 0, `A frog jumps into the pond` -> 7, with `@testable import Strangewords`. |
| `ios/StrangewordsTests/HostIsolationTests.swift` | Mock-mode and no-Run-env guard | ✓ VERIFIED | 2 tests asserting `SW_LOCAL_MOCK`, `SW_API_BASE` and a nil `SW_DEV`. |
| `ios/StrangewordsTests/HarnessCanary.swift` | Env-gated failing test | ✓ VERIFIED | Skipped by default (1 skipped in the PASS run) and failing when `SW_HARNESS_CANARY_FAIL=1`. |
| `scripts/test-ios.sh` | Headless runner, exits 0/1/2 | ✓ VERIFIED | Mode 755; contains `xcresulttool get test-results summary` and the jq positive match. |
| `scripts/test-ios-selfcheck.sh` | Six-case proof | ✓ VERIFIED | Mode 755. Evidence for all six cases is in `build/verify/20261014-125059-selfcheck/`. |
| `.gitignore` | `/build/` rule | ✓ VERIFIED | Line 30. |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| `scripts/test-ios.sh` | `ios/project.yml` | `xcodegen generate`, then `xcodebuild test -scheme Strangewords` | WIRED | Both commands are in the script, and the scheme is defined in project.yml. |
| `scripts/test-ios.sh` | `ios-summary-N.json` | xcresulttool piped into jq verdict | WIRED | Exact pattern present. |
| `project.yml` scheme `test.environmentVariables` | `AppModel.swift` | `SW_LOCAL_MOCK` selects `LocalBackend` and clears the token | WIRED | Generated scheme carries the env, and `AppModel.init` reads it. |
| `HostIsolationTests` | `project.yml` | Asserts `127.0.0.1:9` | WIRED | Value matches. |
| `test-ios-selfcheck.sh` | `test-ios.sh` | One invocation per case with `SW_VERIFY_OUT` | WIRED | Per-case directories exist. |

### Data-Flow Trace (Level 4)

Not applicable. The phase delivers tooling and tests that render no dynamic data.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Go checks | `cd server && go build ./... && go vet ./... && go test ./...` | exit 0, all packages ok | ✓ PASS |
| gofmt | `gofmt -l server/` | empty | ✓ PASS |
| Project regeneration | `cd ios && xcodegen generate` | project written, test target and scheme env present | ✓ PASS |
| iOS suite verdict | Recorded: orchestrator's `scripts/test-ios.sh` run at HEAD (`build/verify/20261014-125345/ios-verdict.txt`) | `PASS` 4 passed / 0 failed / 1 skipped / 5 total | ✓ PASS (recorded, not re-run) |
| False-green resistance | Recorded: self-check evidence directories | zero, canary, nobundle and nosim all non-green; pass and isolation green | ✓ PASS (recorded, not re-run) |

### Probe Execution

SKIPPED. No `probe-*.sh` is declared or present. `scripts/test-ios-selfcheck.sh` is the phase's proof script, and I used its recorded evidence rather than re-running it (a multi-minute simulator run).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| HARN-01 | 01-01 | Tree reconciled and all existing checks pass | ✓ SATISFIED | SC1 and SC2 |
| HARN-02 | 01-02 | Hosted unit-test target with a scheme test action that survives `xcodegen generate` | ✓ SATISFIED | SC3 |
| HARN-03 | 01-02 | Headless CLI run with a trustworthy verdict; non-zero on failure; zero tests counts as failure | ✓ SATISFIED | SC4 and SC5 (the retry-path backstop is noted as P4) |

REQUIREMENTS.md maps HARN-01..03 to Phase 1, and all three appear in plan frontmatter (01-01: HARN-01; 01-02: HARN-02, HARN-03). HARN-04 and HARN-05 are mapped to Phase 4. There are no orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (scripts, tests) | - | No TBD/FIXME/XXX markers; no stubs | ℹ️ Info | Clean. |
| `scripts/test-ios.sh` | 45-60, 109 | WR-01: stale `ios-verdict.txt` and attempt-2 files survive when `SW_VERIFY_OUT` is reused. Exit-2 paths write no verdict file. | ⚠️ Warning | Does not break the exit-code contract, since the summary is regenerated each run. It matters if Phase 4 reads the file instead of the exit code. |
| `scripts/test-ios.sh` | 67 | WR-02: a simulator boot failure is swallowed and reported as exit 1 instead of 2 | ⚠️ Warning | The result is still non-green, so no false green. It only misclassifies the failure. |
| `scripts/test-ios.sh` | 58-60 | WR-03: simulator selection is not deterministic across runtimes, and the evidence does not record the UDID or Xcode version | ⚠️ Warning | A reproducibility concern for the baseline; not a verdict-integrity issue. |
| `server/internal/config/config.go` | 20-43 | WR-04: `AppAttestAppID` defaults to empty and is not in DEPLOY.md | ⚠️ Warning | Scaffold only; nothing reads it yet. Belongs to the push/safety milestone. |
| `scripts/test-ios.sh` | 80-86 | IN-05: pass-through args can override `-destination` or `-resultBundlePath` | ℹ️ Info | Caller footgun, not a default-path defect. |

The review dispositions are all `open`; none are blockers.

### Human Verification Required

#### 1. Cold-boot retry path (backstop truth)

**Test:** Stub the "Early unexpected exit" signature once (for example a PATH-stubbed `xcodebuild`), or record an override accepting the carry-over to Phase 4.
**Expected:** Exactly one retry into `ios-tests-2.xcresult` and `ios-summary-2.json`, with the verdict taken from attempt 2. A real test failure is never retried (already proven by the `canary` case).
**Why human:** This is a non-inferable `verification: backstop` truth. The signature cannot be produced on demand, and no test exercises the retry branch. The plan marks it as a deliberate Phase 4 carry-over, so it is not a goal gap. It needs an explicit human acceptance.

To accept it as intentional, add this to the VERIFICATION.md frontmatter:

```yaml
overrides:
  - must_have: "A cold-boot bootstrap crash triggers exactly one retry into attempt-2 evidence paths"
    reason: "Signature cannot be produced on demand; carried to Phase 4 per plan 01-02"
    accepted_by: "{name}"
    accepted_at: "{ISO timestamp}"
```

### Gaps Summary

There are no gaps. The tree is reconciled in the exact commit structure the plan specified. Go build, vet, test and gofmt are green at HEAD. The hosted test target, scheme test action and isolation env survive regeneration. The runner's verdict is a positive jq match on the result-bundle summary, and committed self-check evidence shows zero-test, failing-test and no-bundle runs all exit non-zero, including one run where xcodebuild printed its success banner. The only open item is the unexercisable cold-boot retry, which routes to human acceptance. The four review warnings are advisory hardening for the Phase 4 consumer.

---

_Verified: 2026-10-14T18:30:00Z_
_Verifier: Claude (gsd-verifier)_
