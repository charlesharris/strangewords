# Phase 1: Clean Tree & Trustworthy iOS Harness - Research

**Researched:** 2026-10-08
**Domain:** XcodeGen-managed SwiftUI app, headless `xcodebuild test` with Swift Testing, result-bundle verdicts, git reconciliation
**Confidence:** HIGH (every load-bearing claim below was reproduced on this machine this session; see the probe log)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Keep ALL six dirty/untracked files — they are one coherent chunk of deliberate App Attest / device-signing prep: `ios/project.yml` (bundle ID → `com.strangerwords.us`, `DEVELOPMENT_TEAM: 2M6QRD8T3A`, `CODE_SIGN_ENTITLEMENTS`, per-config `APP_ATTEST_ENVIRONMENT`, Xcode Run scheme with `SW_LOCAL_MOCK=1`/`SW_DEV=1`), `ios/Strangewords/Strangewords.entitlements` (untracked, App Attest environment), `run.sh` (bundle ID), `server/internal/config/config.go` (`AppAttestAppID` scaffold, env `SW_APP_ATTEST_APPID`, empty disables), `docs/STATUS.md` and `server/DEPLOY.md` (doc updates describing the above). Nothing is reverted. — **Reversibility:** costly — the bundle ID must match the registered App ID (`2M6QRD8T3A.com.strangerwords.us`); reverting it breaks App Attest binding and contradicts the docs that already describe it.
- **D-02:** Commit split by concern, not one lump: (a) iOS signing/scheme changes + the doc updates that describe them, (b) server `AppAttestAppID` config scaffold. Keeps history legible and per-concern revertable.
- **D-03:** Headless runner lives in a NEW top-level `scripts/` directory: `scripts/test-ios.sh`. `run.sh` stays untouched (it is the feel loop, not the test loop). Phase 4's `verify.sh` will live beside it and compose it.
- **D-04:** Phase 1 scripts the iOS runner ONLY. HARN-01's Go checks (`go test ./...`, `go vet ./...`, `go build ./...`) run as bare commands this phase; aggregation into one command is Phase 4's job (HARN-04).
- **D-05:** Test evidence (`.xcresult` bundle + parsed summary) lands in gitignored top-level `build/verify/<timestamp>/` — the same location Phase 4's verify.sh will collate all stage evidence into. Add the gitignore entry if missing.
- **D-06:** Pin the simulator by NAME only: `iPhone 16` (OS version unpinned — uses the installed runtime, currently iOS 18.6). Rationale: pinning OS breaks on every Xcode runtime update.
- **D-07:** The runner manages the simulator lifecycle: `simctl bootstatus` (boot if needed) before testing, `simctl shutdown` after. Guards the cold-boot "Early unexpected exit" flake; retry only that failure signature once.
- **D-08:** Force `CODE_SIGNING_ALLOWED=NO` on `xcodebuild test` invocations. Simulator tests need no signing; runs stay machine-independent (no team membership required) and avoid the silent-keychain-failure bug class. The now-set `DEVELOPMENT_TEAM` stays in `project.yml` for device builds — it just must not be a prerequisite for the test harness.
- **D-09:** The trivial test that proves the harness is a REAL seed: 2–3 genuine `Syllables` characterization cases. It is kept and grows into Phase 2's suite — nothing thrown away.
- **D-10:** Swift Testing (not XCTest); `@Suite(.serialized)` for suites touching shared state (e.g. `UserDefaults`).
- **D-11:** Verdict comes from the result bundle via `xcresulttool` (+ `jq`), never from xcodebuild's banner or exit code alone: non-zero exit on test failure AND on zero-tests-executed (`totalTestCount > 0` and `result == "Passed"` required).
- **D-12:** The test host app must run isolated: scheme test action sets `SW_LOCAL_MOCK=1` so no test can reach production through a leftover token. Probe `TEST_RUNNER_` env forwarding / scheme test-env mechanics with a one-line check before relying on them (roadmap research flag).

### Claude's Discretion

- Test target naming and its bundle ID (expected `com.strangerwords.*` per the new `bundleIdPrefix`; confirm what XcodeGen generates, roadmap mentions `com.strangerwords.us.tests`).
- Exact `scripts/test-ios.sh` flag surface (e.g. `-only-testing` passthrough), retry mechanics, and summary format.
- Whether `GENERATE_INFOPLIST_FILE: YES` or an explicit plist is used for the test target (PITFALLS notes it's needed when signing is allowed).

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope. (Known future work — actual App Attest validation server-side, CI — already lives in v2 requirements / later milestones.)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HARN-01 | Working tree reconciled (six files committed deliberately) and all existing checks pass: `go test ./...`, `go vet`, `go build`, `xcodegen generate` + `xcodebuild build` | Go checks and both signed/unsigned `xcodebuild build` pass on the dirty tree today (probe P1, P2). Commit grouping and ordering in "Architecture Patterns / Pattern 1". |
| HARN-02 | Hosted `bundle.unit-test` target in `ios/project.yml` with scheme `test:` action, survives `xcodegen generate` | Verified YAML (Code Examples A). Generated test bundle ID is `com.strangerwords.us.tests` (probe P3). |
| HARN-03 | Headless CLI test run with trustworthy verdict; non-zero on failure AND zero executed tests | Verdict recipe and a working prototype runner that exits 0/1/1 for pass/zero/fail (Code Examples B, probe P6-P8). |
</phase_requirements>

## Summary

Everything this phase needs was reproduced locally, and the two items the roadmap flagged are now resolved. **(1) Env isolation works, and it is necessary.** With `environmentVariables: SW_LOCAL_MOCK=1` on the scheme's `test:` action, the host app (`AppModel.init`) sees `SW_LOCAL_MOCK=1`, selects `LocalBackend`, and `TokenStore.clear()` wipes a leftover token before `resume()` runs. With no env anywhere, the host takes the `APIClient.shared` branch and `resume()` runs against a leftover token (the real-network path). `TEST_RUNNER_`-prefixed env on the xcodebuild command line also reaches the host, so it is a valid second layer. **(2) The test bundle ID XcodeGen generates is exactly `com.strangerwords.us.tests`** when set explicitly, and the app keeps `com.strangerwords.us` — the dirty-tree bundle ID change does not interfere.

The false-green is real and is caught by the result bundle: a mistyped `-only-testing` filter makes xcodebuild print `** TEST SUCCEEDED **` with exit 0, while `xcresulttool get test-results summary` reports `result: "unknown"`, `totalTestCount: 0`. A real failing `#expect` gives exit 65 and `result: "Failed"`. A compile error gives exit 65 with `totalTestCount: 0`. A prototype `test-ios.sh` built from these facts returned exit 0 / 1 / 1 for pass / zero-tests / failing-test and left no simulator booted.

One non-obvious trap: adding a scheme `test:` block **without** its own `environmentVariables` makes XcodeGen emit `shouldUseLaunchSchemeArgsEnv = "YES"`, so tests silently inherit the Run action's `SW_LOCAL_MOCK=1`/`SW_DEV=1`. Isolation then holds by accident and breaks if anyone edits the Run env. Set the test env explicitly, and add a permanent guard test that asserts it.

**Primary recommendation:** Three plans in order: (1) reconcile the tree in two concern-split commits and prove the existing checks green; (2) add `StrangewordsTests` + scheme `test:` (with explicit `SW_LOCAL_MOCK=1`) + seed `Syllables` tests + `.gitignore`; (3) write `scripts/test-ios.sh` using the prototype in Code Examples B, then prove the three verdicts (pass, zero tests, failing test) before committing. Finish with `git status` clean.

## Architectural Responsibility Map

This is a tooling phase, not a multi-tier feature. Ownership is by toolchain layer.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Project/target/scheme definition | `ios/project.yml` (XcodeGen) | — | `.xcodeproj` is gitignored; hand edits in Xcode are lost on regenerate |
| Test host isolation (mock backend) | Scheme `test:` env | `TEST_RUNNER_*` env at CLI | Env must be present in the host process before `AppModel.init` |
| Test execution | `xcodebuild test` | Simulator (CoreSimulator) | Only way to run an app-hosted bundle headlessly |
| Pass/fail verdict | `xcresulttool` + `jq` in `scripts/test-ios.sh` | — | xcodebuild banner/exit code can be green with 0 tests |
| Simulator lifecycle | `scripts/test-ios.sh` (`simctl`) | — | Guards cold-boot flake; avoids leaving devices booted |
| Evidence retention | `build/verify/<ts>/` (gitignored) | — | Same location Phase 4 collates |
| Go checks | bare `go test/vet/build` in `server/` | — | D-04: no aggregation this phase |

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Xcode / `xcodebuild` | 16.4 (16F6) [VERIFIED: `xcodebuild -version` this session] | Build and run tests headlessly | Only supported runner for app-hosted tests |
| Swift Testing (`import Testing`) | Ships with Xcode 16.4 | Unit tests (D-10) | No third-party dependency; ran hosted with `SWIFT_VERSION: "5.0"` and iOS 17.0 deployment target [VERIFIED: probe P3] |
| XcodeGen | 2.45.4 [VERIFIED: `xcodegen --version`] | Generates project incl. test target and scheme | `project.yml` is the source of truth (CLAUDE.md) |
| `xcrun xcresulttool` | version 23714, format 3.53 [VERIFIED: `xcresulttool --version`] | `get test-results summary` for the verdict | Result bundle is the authoritative record |
| `jq` | `/usr/bin/jq` present [VERIFIED: `which jq`] | Parse summary JSON and `simctl -j` | Already installed; no new dependency |
| Go | 1.26.0 [VERIFIED: `go version`] | Existing server checks | `go.mod` says 1.25.0; fine |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `xcrun simctl` (`list -j`, `bootstatus -b`, `shutdown`) | Resolve UDID by exact name, boot-and-wait, cleanup | In `scripts/test-ios.sh` |
| `xcodebuild test-without-building` | Fast re-run after a build | Optional for the retry path; not required |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Swift Testing | XCTest | Locked out by D-10 |
| `-destination "platform=iOS Simulator,name=iPhone 16"` | `-destination "id=<UDID>"` | Prefer `id=` resolved from the exact name: the same UDID is then used for boot/shutdown, and name-match ambiguity (16 / 16 Plus / 16 Pro / 16e exist here) disappears. Still "pinned by name" per D-06. |
| xcpretty/xcbeautify | raw xcodebuild log | Not installed, not needed; log is written to a file in the evidence dir |

**Installation:** nothing to install. [VERIFIED: all tools present this session]

**Package legitimacy:** this phase installs no external packages (no SPM, no npm, no pip, no cargo). The `gsd-tools package-legitimacy` check does not apply.

## Package Legitimacy Audit

No external packages are installed in this phase. The no-third-party-iOS-dependencies invariant is preserved: Swift Testing is part of the Xcode toolchain.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| — | — | — | — | — | — | N/A |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
developer
   |  scripts/test-ios.sh [-only-testing:...]
   v
[preflight: xcodegen/xcodebuild/jq present] --missing--> exit 2
   |
   v
xcodegen generate  (ios/project.yml --> ios/Strangewords.xcodeproj, gitignored)
   |
   v
simctl list -j  --exact name "iPhone 16"--> UDID  --none--> exit 2
   |
   v
simctl bootstatus -b  (boot if needed; remember if WE booted it)
   |
   v
xcodebuild test  -destination id=UDID  CODE_SIGNING_ALLOWED=NO
   |   -derivedDataPath build/derived/ios-test
   |   -resultBundlePath build/verify/<ts>/ios-tests-N.xcresult
   |        |
   |        +--> host app launches with scheme TEST env (SW_LOCAL_MOCK=1)
   |               AppModel.init -> LocalBackend, TokenStore.clear()
   |               Swift Testing bundle injected, tests run
   v
xcresulttool get test-results summary --> ios-summary-N.json
   |
   +-- totalTestCount==0 AND log has "Early unexpected exit"? --> retry ONCE
   v
jq -e '.result=="Passed" and .failedTests==0 and .passedTests>0 and .totalTestCount>0'
   |                                   |
 exit 0 (PASS line)              exit 1 (FAIL line)    [trap: shutdown sim if we booted it]
```

### Recommended Project Structure
```
scripts/
└── test-ios.sh                 # new (D-03); Phase 4 verify.sh will live beside it
ios/
├── project.yml                 # + StrangewordsTests target, + scheme test:
├── Strangewords/               # unchanged app sources
└── StrangewordsTests/          # new
    ├── SyllablesTests.swift    # seed (D-09), grows in Phase 2
    └── HostIsolationTests.swift# guard: asserts SW_LOCAL_MOCK == "1" in the host
build/                          # gitignored (D-05): verify/<ts>/ and derived/ios-test/
```

### Pattern 1: Reconciliation commit sequence (HARN-01)
**What:** Two concern-split commits (D-02), then everything else this phase adds is committed in its own commits so `git status` is clean at phase end.
**Grouping (recommended; `ios/Strangewords/Strangewords.entitlements` MUST ride with `project.yml` because `CODE_SIGN_ENTITLEMENTS` references it, so a commit with one and not the other breaks fresh clones):**
1. `ios/project.yml` + `ios/Strangewords/Strangewords.entitlements` + `run.sh` + `docs/STATUS.md` + `server/DEPLOY.md` — iOS signing / bundle-ID / scheme prep and the docs that describe it. (`DEPLOY.md` and `STATUS.md` hunks are only about the bundle ID and App Attest binding [VERIFIED: `git diff` this session].)
2. `server/internal/config/config.go` — `AppAttestAppID` scaffold.
Stage by explicit path, never `git add -A` (the tree also holds `.planning/` files). Commit trailer per the session attribution reminder: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
**Check after each commit:** `git status --short` shows only what is expected; after commit 2 it is empty. Do the Go checks and an unsigned+signed `xcodebuild build` BEFORE committing so any red is attributable (they are green today).

### Pattern 2: Explicit scheme test env (HARN-02, D-12)
**What:** `test:` block with its own `environmentVariables` so `shouldUseLaunchSchemeArgsEnv` is `NO` and the Run action's `SW_DEV=1` does not leak.
**Why:** see Pitfall 1. YAML in Code Examples A (list-of-`variable`/`value` form; the existing `run:` block uses map form, both are valid XcodeGen).

### Pattern 3: Verdict from the result bundle (HARN-03, D-11)
**What:** The script's exit code is derived only from `ios-summary-N.json`. The xcodebuild exit code is recorded in the output line for diagnosis but never decides the verdict. Missing/unreadable bundle yields `{}` and therefore FAIL (jq comparisons against null are false).
**Additionally require `passedTests>0`** so an all-skipped run (`result` may still say Passed) cannot go green. [ASSUMED: all-skipped yields result "Passed"; the extra guard is free either way.]

### Anti-Patterns to Avoid
- **Grepping `** TEST SUCCEEDED **` or `Executed N tests`.** Reproduced: both print on a zero-test run; the `Executed 0 tests` line is the empty XCTest harness and appears even on passing Swift Testing runs [VERIFIED: probe P7].
- **Hand-editing the generated scheme/project in Xcode.** Lost on the next `xcodegen generate`.
- **Sharing `-derivedDataPath ios/build` with `run.sh`.** The test build embeds `PlugIns/StrangewordsTests.xctest` in the app; use `build/derived/ios-test` (PITFALLS #11, [CITED: .planning/research/PITFALLS.md]).
- **`simctl shutdown all`** (STACK.md's sketch). It kills a dev's `run.sh` simulators; shut down only the UDID, and only if the script booted it.
- **`open -a Simulator`.** Not needed headless (run.sh habit; do not copy).
- **Blanket `-retry-tests-on-failure`.** Masks real flakes (D-07 says retry only the bootstrap signature).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Counting executed tests | Parsing xcodebuild text | `xcresulttool get test-results summary` fields `result`, `passedTests`, `failedTests`, `totalTestCount` | Text is misleading (zero-test green) |
| Failure details for the evidence record | Regex on logs | `testFailures[]` in the same summary (`failureText`, `testIdentifierString`) [VERIFIED: probe P7] | Structured already |
| Finding the simulator | `grep` on `simctl list` text (run.sh style) | `simctl list devices available -j \| jq` with exact-name `select` [VERIFIED: returned the iPhone 16 UDID] | Exact match; no prefix collisions |
| Waiting for boot | `sleep N` | `simctl bootstatus <udid> -b` | Boots if needed and blocks until ready |
| Test target wiring | Manual pbxproj / Xcode UI | XcodeGen `bundle.unit-test` + `dependencies: - target:` | `TEST_HOST`/`BUNDLE_LOADER` set automatically; `@testable import` works |
| Isolation of host app | Editing `StrangewordsApp` to detect XCTest | Scheme test env `SW_LOCAL_MOCK=1` | Zero production-code change; the app already honors this env |

**Key insight:** every piece of "trust" in this harness comes from structured artifacts (`xcresult` JSON, `simctl -j`), not from human-readable output.

## Runtime State Inventory

Not a rename phase, but the bundle ID change (`com.strangewords.app` → `com.strangerwords.us`) is already in the working tree, so the question "what still carries the old name" is answered for completeness.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | App container `UserDefaults` is per bundle ID. The test host and `run.sh` now share the `com.strangerwords.us` container on a given simulator; a Phase-2 test that writes `TokenStore.token` persists after the run (reproduced: a token written by a test was still in `Library/Preferences/com.strangerwords.us.plist` on the next run [VERIFIED: probe P4/P5]). The old `com.strangewords.app` container is orphaned on any simulator that ran an older build. | None for Phase 1 (seed tests do not touch `TokenStore`). Record for Phase 2: tests must save/restore or clear what they write. |
| Live service config | None — the bundle ID is not registered in any service this phase touches (Apple App ID registration is already done per D-01). | None |
| OS-registered state | None — no launchd/Task Scheduler entries reference the bundle ID. | None |
| Secrets/env vars | `SW_APP_ATTEST_APPID` (server, empty by default) and `APP_ATTEST_ENVIRONMENT` (build setting). Team ID `2M6QRD8T3A` is an identifier, not a secret. [VERIFIED: config.go diff, project.yml:49-54] | None |
| Build artifacts | `ios/Strangewords.xcodeproj` and `ios/Strangewords/Info.plist` are gitignored and regenerated; `ios/build/` holds a pre-rename app build with the old bundle ID if one exists. | Always `xcodegen generate` first (script does). Optional: `rm -rf ios/build` once. |

## Common Pitfalls

### Pitfall 1: Test action silently inherits the Run action's env
**What goes wrong:** A `test:` block with no `environmentVariables` generates `shouldUseLaunchSchemeArgsEnv = "YES"`; tests then run with `SW_LOCAL_MOCK=1` and `SW_DEV=1` from the Run action. Isolation works by accident [VERIFIED: probe P5, scheme line 30 `shouldUseLaunchSchemeArgsEnv = "YES"` when test env absent; `"NO"` when present].
**Why it happens:** XcodeGen's default for the Test action's "use Run action arguments and environment".
**How to avoid:** Explicit `test.environmentVariables` (Code Examples A) plus the guard test `HostIsolationTests` asserting `ProcessInfo.processInfo.environment["SW_LOCAL_MOCK"] == "1"`.
**Warning signs:** guard test fails; `AppModel.init` taking the `APIClient.shared` branch.

### Pitfall 2: Zero-test false green
**What goes wrong:** Mistyped `-only-testing:StrangewordsTests/Nope` → `** TEST SUCCEEDED **`, exit 0, summary `result: "unknown"`, `totalTestCount: 0` [VERIFIED: probe P7].
**How to avoid:** verdict requires `totalTestCount>0` and `result=="Passed"` (Code Examples B).

### Pitfall 3: Compile error also yields an "unknown" summary
**What goes wrong:** Build failure gives exit 65, `result: "unknown"`, 0 tests [VERIFIED: probe P7]. Not a false green, but a naive "result != Failed" check would pass it.
**How to avoid:** Positive-match `Passed`, never negative-match `Failed`.

### Pitfall 4: `-resultBundlePath` must not pre-exist
**What goes wrong:** xcodebuild refuses an existing path. **How to avoid:** `rm -rf` the exact path first; use a per-attempt filename (`ios-tests-1`, `-2`) so a retry does not collide and the first attempt's evidence is kept. [CITED: .planning/research/STACK.md gotcha 8; the script was run with fresh paths so the collision itself was not re-triggered]

### Pitfall 5: Cold-boot flake
**What goes wrong:** First run on a shut-down simulator can die with `Early unexpected exit, operation never finished bootstrapping ... signal kill before starting test execution`; identical re-run passes [CITED: .planning/research/PITFALLS.md #14, observed in the earlier spike; not reproduced this session — in six cold boots this session it never occurred].
**How to avoid:** `bootstatus -b` before testing; retry once ONLY if `totalTestCount==0` AND the log contains `Early unexpected exit`. A real test failure is never retried.

### Pitfall 6: Signing prerequisites leaking into tests
**What goes wrong:** project-level `DEVELOPMENT_TEAM`/`CODE_SIGN_STYLE: Automatic` are inherited by the test target. **How to avoid:** `CODE_SIGNING_ALLOWED=NO` (D-08) and `GENERATE_INFOPLIST_FILE: YES` on the test target. Note the consequence: with signing off, entitlements (App Attest) are not applied, so nothing in this harness verifies them — put it on Phase 4's not-verified list. A signed simulator build also passes on this machine (one valid "Apple Development" identity present), so HARN-01's `xcodebuild build` is green either way [VERIFIED: probe P2].

### Pitfall 7: Tests that write the shared container (forward-looking for Phase 2)
**What goes wrong:** the host and tests share one `UserDefaults.standard`; a token written in one test remains for the next run and for the dev's `run.sh` on that simulator. **How to avoid:** Phase 2 concern (IOST-05); do not add token-writing tests in Phase 1. Note also that running the harness wipes the dev's `iPhone 16` token (host `AppModel.init` calls `TokenStore.clear()` in mock mode) — document in the script header.

### Pitfall 8: `simctl spawn defaults write` is NOT a valid way to plant a test token
**What goes wrong:** it writes a device-level plist; the app can read it but `removeObject` cannot clear it, so it looks like `TokenStore.clear()` is broken [VERIFIED: probe P4, token stayed `GHOSTTOKEN`]. **How to avoid:** if a plan wants a ghost-token proof, plant via a test run or the container plist (`simctl get_app_container <udid> <bundle> data` with the sim shut down).

## Code Examples

### A. `ios/project.yml` additions (all of this was generated and run in the probe)

```yaml
# Source: probe P3, XcodeGen 2.45.4, Xcode 16.4 [VERIFIED: ran `xcodegen generate` + `xcodebuild test`]
targets:
  StrangewordsTests:            # add as a sibling of `Strangewords:` under targets:
    type: bundle.unit-test
    platform: iOS
    sources:
      - StrangewordsTests
    dependencies:
      - target: Strangewords    # sets TEST_HOST/BUNDLE_LOADER; enables @testable import
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.strangerwords.us.tests

schemes:
  Strangewords:
    build:
      targets:
        Strangewords: all
    test:
      config: Debug
      targets:
        - StrangewordsTests
      environmentVariables:     # explicit => shouldUseLaunchSchemeArgsEnv = NO
        - variable: SW_LOCAL_MOCK
          value: "1"
        - variable: SW_API_BASE # defense in depth; APIClient reads it at init (APIClient.swift:26-27)
          value: "http://127.0.0.1:9"
    run:
      config: Debug
      environmentVariables:
        SW_LOCAL_MOCK: "1"
        SW_DEV: "1"
```
Existing file context, quoted verbatim: the current `schemes:` block is `build:` (`Strangewords: all`) then `run:` (`config: Debug`, `environmentVariables`, `SW_LOCAL_MOCK: "1"`, `SW_DEV: "1"`) [VERIFIED: ios/project.yml:60-69]. The app target already sets `PRODUCT_BUNDLE_IDENTIFIER: com.strangerwords.us` [VERIFIED: ios/project.yml:43]. `SW_API_BASE` was not itself exercised in the probe (only `SW_LOCAL_MOCK` was); it is optional, low risk, and is read via `ProcessInfo.processInfo.environment["SW_API_BASE"]` [VERIFIED: ios/Strangewords/Net/APIClient.swift:26]. Mock-branch behaviour quoted from `AppModel.swift:55-60`: `else if ProcessInfo.processInfo.environment["SW_LOCAL_MOCK"] == "1" {` … `self.api = LocalBackend()` … `TokenStore.clear()` [VERIFIED].

### Seed tests (D-09). Expected values computed by compiling the real `Syllables.swift` this session, not guessed

```swift
// ios/StrangewordsTests/SyllablesTests.swift
import Testing
@testable import Strangewords

struct SyllablesTests {
    // [VERIFIED: values printed by compiling ios/Strangewords/Syllables/Syllables.swift]
    @Test(arguments: [
        ("hello", 2), ("the", 1), ("silent", 2), ("fire", 1),   // trailing-e drop; floor at 1
        ("river", 2), ("autumn", 2), ("", 0), ("123", 0),       // empty / non-letters
    ])
    func word(_ text: String, _ expected: Int) { #expect(Syllables.count(text) == expected) }

    @Test(arguments: [
        ("An old silent pond", 5),
        ("A frog jumps into the pond", 7),
        ("Splash! Silence again.", 5),
    ])
    func haikuLine(_ text: String, _ expected: Int) { #expect(Syllables.count(text) == expected) }
}
```
Characterized-as-is imperfections (record, do not "fix" in Phase 1): `"poem"` → 1 (vowel cluster "oe"), `"quiet"` → 1, `"rhythm"` → 1. These are heuristic limits (PITFALLS #15); only pin them in Phase 2 with a comment, if at all.

```swift
// ios/StrangewordsTests/HostIsolationTests.swift  — guards D-12 permanently
import Testing
import Foundation

struct HostIsolationTests {
    @Test func hostRunsInLocalMockMode() {
        #expect(ProcessInfo.processInfo.environment["SW_LOCAL_MOCK"] == "1")
    }
}
```
(`@Suite(.serialized)` is not required here — no shared state. Add it to any suite that touches `TokenStore`/`UserDefaults`, per D-10.)

### B. `scripts/test-ios.sh` — prototype, run this session
Behaviour verified in probe P8 (output captured): `-only-testing` of a passing suite → `PASS ... exit 0`; nonexistent suite → `FAIL {"result":"unknown",...,"totalTestCount":0} (xcodebuild rc=0)` exit 1; failing test → `FAIL {"result":"Failed",...} (xcodebuild rc=65)` exit 1; no simulator left booted afterwards (the script booted it, so it shut it down). The retry path and the "sim was already booted" path were not exercised.

```bash
#!/usr/bin/env bash
# scripts/test-ios.sh — headless iOS unit tests with a result-bundle verdict.
# Usage: scripts/test-ios.sh [extra xcodebuild args, e.g. -only-testing:StrangewordsTests/SyllablesTests]
# Side effect: the host app runs in mock mode and clears the participant token in the
# com.strangerwords.us container of the test simulator (dev tokens on that sim are wiped).
set -uo pipefail

ROOT="${SW_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
IOS="$ROOT/ios"
SIM_NAME="${SW_SIM_NAME:-iPhone 16}"
OUT="${SW_VERIFY_OUT:-$ROOT/build/verify/$(date +%Y%m%d-%H%M%S)}"   # Phase 4 can set SW_VERIFY_OUT
DERIVED="$ROOT/build/derived/ios-test"
mkdir -p "$OUT"

for t in xcodegen xcodebuild jq xcrun; do
  command -v "$t" >/dev/null || { echo "test-ios: missing tool: $t" >&2; exit 2; }
done
( cd "$IOS" && xcodegen generate >/dev/null ) || { echo "test-ios: xcodegen failed" >&2; exit 2; }

UDID="$(xcrun simctl list devices available -j \
  | jq -r --arg n "$SIM_NAME" '[.devices[][] | select(.name==$n)][0].udid // empty')"
[ -n "$UDID" ] || { echo "test-ios: no available simulator named '$SIM_NAME'" >&2; exit 2; }

BOOTED_BY_US=0
xcrun simctl list devices booted | grep -q "$UDID" || BOOTED_BY_US=1
cleanup() { [ "$BOOTED_BY_US" = 1 ] && xcrun simctl shutdown "$UDID" >/dev/null 2>&1; true; }
trap cleanup EXIT
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

run_once() {  # $1 = attempt number; remaining args pass through to xcodebuild
  RB="$OUT/ios-tests-$1.xcresult"; LOG="$OUT/xcodebuild-$1.log"; SUMMARY="$OUT/ios-summary-$1.json"
  rm -rf "$RB"
  ( cd "$IOS" && xcodebuild test \
      -project Strangewords.xcodeproj -scheme Strangewords \
      -destination "id=$UDID" -derivedDataPath "$DERIVED" \
      -resultBundlePath "$RB" CODE_SIGNING_ALLOWED=NO "${@:2}" ) >"$LOG" 2>&1
  XC_RC=$?
  if [ -d "$RB" ] && xcrun xcresulttool get test-results summary --path "$RB" >"$SUMMARY" 2>/dev/null; then :; else echo '{}' >"$SUMMARY"; fi
}

run_once 1 "$@"
if [ "$(jq -r '.totalTestCount // 0' "$SUMMARY")" = 0 ] && grep -q "Early unexpected exit" "$LOG"; then
  echo "test-ios: cold-boot flake signature seen; retrying once" >&2
  run_once 2 "$@"
fi

if jq -e '.result=="Passed" and .failedTests==0 and .passedTests>0 and .totalTestCount>0' "$SUMMARY" >/dev/null 2>&1; then
  echo "test-ios: PASS $(jq -c '{passedTests,failedTests,skippedTests,totalTestCount}' "$SUMMARY") (xcodebuild rc=$XC_RC) evidence: $OUT"
  exit 0
fi
echo "test-ios: FAIL $(jq -c '{result,passedTests,failedTests,totalTestCount}' "$SUMMARY") (xcodebuild rc=$XC_RC) evidence: $OUT" >&2
exit 1
```
Planner notes on the script: `chmod +x`; the `$ROOT`/`SW_ROOT` override exists only so the probe could point at a scratch tree — keep or drop. `"${@:2}"` inside `run_once` forwards the original args because they are passed as `run_once 1 "$@"`. Do not use `set -e` (the script must keep going after a failing xcodebuild).

### C. Proving the three verdicts without committing a failing test
Run from repo root after the target exists:
```bash
scripts/test-ios.sh; echo "exit=$?"                                        # expect PASS, exit 0
scripts/test-ios.sh -only-testing:StrangewordsTests/DoesNotExist; echo "exit=$?"   # expect FAIL, exit 1 (zero tests)
```
For the failing-test proof, either (a) temporarily add `struct Canary { @Test func f() { #expect(1 == 2) } }` under `ios/StrangewordsTests/`, run, expect exit 1 and `"result":"Failed"`, then delete it before committing, or (b) recommended: commit a permanent env-gated canary so the proof is re-runnable by Phase 4:
```swift
struct HarnessCanary {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SW_HARNESS_CANARY_FAIL"] == "1"))
    func failsOnPurpose() { #expect(Bool(false), "harness canary") }
}
// TEST_RUNNER_SW_HARNESS_CANARY_FAIL=1 scripts/test-ios.sh   -> must exit 1
```
`TEST_RUNNER_` forwarding into the host/test process was verified with `SW_LOCAL_MOCK` (probe P6 variant D), but the `.enabled(if:)` + canary combination itself was NOT run; treat (b) as needing a one-time check. Also prove the missing-bundle path: temporarily break the scheme (e.g. run against a project without `test:`) or pass a bad `-scheme`; the script must exit 1 with `{}` summary. [ASSUMED: the missing-bundle branch behaves as designed; `{}` + `jq -e` was reasoned, not run end to end.]

### D. `.gitignore` additions
`git check-ignore` returned nothing for `build/x`, `ios/StrangewordsTests/a.swift`, `scripts/test-ios.sh` [VERIFIED: this session], i.e. `build/` is currently NOT ignored (only `ios/build/` is). Add:
```
# Verification evidence + test derived data (scripts/test-ios.sh, Phase 4 verify.sh)
/build/
```

### E. Existing checks (HARN-01 observables)
```bash
cd server && go test ./... && go vet ./... && go build ./...        # all green today (probe P1)
cd ios && xcodegen generate && xcodebuild -project Strangewords.xcodeproj -scheme Strangewords \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath <fresh dir> -quiet build   # green signed AND with CODE_SIGNING_ALLOWED=NO (probe P2)
git status --short                                                  # must print nothing
```
Use a throwaway `-derivedDataPath` (e.g. `build/derived/ios-build`) rather than `ios/build` so the build does not disturb the `run.sh` feel loop. A clean-clone check (`git clone . $TMP && cd $TMP/ios && xcodegen generate && xcodebuild ...`) is the strongest proof the entitlements-with-project.yml grouping is right.

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Parse xcodebuild text / `xcpretty` | `xcresulttool get test-results summary` (JSON) | Old `xcresulttool` subcommands need `--legacy` since Xcode 16; the `test-results` subcommands used here are the supported ones [CITED: .planning/research/STACK.md, Apple forums thread 763050]. Schema is not formally published: pin `jq` to `result`, `passedTests`, `failedTests`, `totalTestCount`, re-verify on Xcode upgrade. |
| XCTest | Swift Testing | `-only-testing` takes `Target/Suite[/test()]`; suite-level worked [VERIFIED: probe P7] |

**Deprecated/outdated:** `xcodebuild`'s "Executed N tests" banner for Swift Testing runs (always 0 from the XCTest harness).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The cold-boot flake text is `Early unexpected exit` and a retry fixes it (from the earlier spike, not reproduced this session) | Pitfall 5, script | Retry never fires; the flake shows as a FAIL and the developer re-runs manually. Safe failure direction. |
| A2 | An all-skipped run could report `result: "Passed"` | Pattern 3 | None; the `passedTests>0` guard is harmless either way. |
| A3 | Missing result bundle path yields `{}` and exits 1 as designed | Code Examples C | A scheme with no test action might behave differently; run the proof before committing. |
| A4 | Env-gated canary via `.enabled(if:)` + `TEST_RUNNER_` works as described | Code Examples C(b) | Fall back to option (a) temporary failing test. |
| A5 | Behavior on Xcode 26.x matches 16.4 | Standard Stack | The machine has 16.4 only; re-verify on upgrade. |
| A6 | Adding `SW_API_BASE=http://127.0.0.1:9` to the test env has no side effect on hosted tests | Code Examples A | Remove the line; `SW_LOCAL_MOCK` alone is the verified mechanism. |

## Open Questions (RESOLVED)

All three were resolved at planning time. The adopted answer is recorded inline under each one.

1. **Does the developer want the `SW_API_BASE` dead-address env line?**
   - Known: `SW_LOCAL_MOCK=1` alone is verified and sufficient for `AppModel`; the dead base only protects code paths that construct `APIClient` directly (none in Phase 1).
   - Recommendation: include it (one line, defense in depth, PITFALLS #2); drop if the planner prefers strictly verified config.
   - **RESOLVED: include it.** Plan 01-02 Task 1 (step B) adds `SW_API_BASE=http://127.0.0.1:9` to the scheme's test-action env, next to `SW_LOCAL_MOCK=1`. `HostIsolationTests.hostRunsInLocalMockMode()` (01-02 Task 2) asserts both values. A6 counts as proven when the default run passes with the line present. Fallback, kept from A6: if it ever causes a side effect, remove the line, because `SW_LOCAL_MOCK` alone is the verified mechanism.
2. **Shutdown policy when the simulator was already booted.**
   - Known: D-07 says shutdown after; the prototype shuts down only if the script booted it, to avoid killing a `run.sh` session on the same device.
   - Recommendation: keep the "only if we booted it" rule and state it in the script header; it satisfies D-07's intent (no stray booted sim after a headless run).
   - **RESOLVED: shut down unconditionally, per locked decision D-07. The recommendation above is NOT adopted.** CONTEXT D-07 reads "`simctl shutdown` after", with no only-if-we-booted-it qualifier, and locked decisions are not re-litigated at planning time. `scripts/test-ios.sh` (01-02 Task 1, step D) installs an EXIT trap that shuts down the pinned UDID, and only that UDID, even if it was already booted. Two consequences:
     - Ending a `run.sh` session on the same iPhone 16 is an accepted cost (threat T-01-09). The script header documents it.
     - Self-check case 1 (01-02 Task 2) pre-boots the simulator and proves it is shut down afterwards.

     The prototype's `BOOTED_BY_US` guard in Code Examples B is therefore dropped when the prototype is lifted.
3. **iOS 17 runtime not installed** (`iOS 18.6` only [VERIFIED: `simctl list runtimes`]). Accepted gap per CONTEXT; Phase 4 not-verified list.
   - **RESOLVED: accepted gap, and no runtime is installed in Phase 1.** Tests run on the installed iOS 18.6 runtime with the simulator pinned by name only (D-06). The 17.0 deployment target goes untested, and the gap is recorded in two places:
     - the "Not verified (carry to Phase 4)" list in the 01-02 SUMMARY (01-02 Task 1, step E)
     - Phase 4's not-verified list (the ROADMAP Phase 4 notes name the iOS 17.x runtime)

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode / xcodebuild | HARN-01..03 | yes | 16.4 (16F6) | — |
| XcodeGen | HARN-01..03 | yes | 2.45.4 | — |
| iOS Simulator `iPhone 16` | HARN-03 | yes | iOS 18.6 runtime (only runtime) | `SW_SIM_NAME` override |
| `jq` | HARN-03 verdict | yes | `/usr/bin/jq` | — (required; script exits 2 if missing) |
| Go | HARN-01 | yes | 1.26.0 | — |
| Apple Development signing identity | optional signed build | yes (1 valid) | — | `CODE_SIGNING_ALLOWED=NO` (what tests use) |
| Docker / redis-server | not needed this phase | — | — | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** iOS 17.x runtime (not installed; accepted gap).

*Validation Architecture section omitted: `workflow.nyquist_validation` is `false` in `.planning/config.json` [VERIFIED: config.json:24]. The phase's own observable checks are listed in Code Examples C and E.*

## Security Domain

`security_enforcement` is enabled, ASVS level 1. This phase ships no network-facing or user-data code; the relevant controls are about not weakening the anonymity model and about script hygiene.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | indirect | Host runs in mock mode so no real bearer token is replayed; `TokenStore.clear()` runs in the mock branch (verified) |
| V4 Access Control | no | — |
| V5 Input Validation | partial | `scripts/test-ios.sh` quotes all expansions; user args pass only to `xcodebuild` as separate words |
| V6 Cryptography | no | App Attest entitlements are committed but not exercised (signing off for tests) |
| V14 Configuration | yes | No secrets in the six files: team ID and App ID are identifiers; `.gitignore` already blocks `*.p8`, `*.p12`, `.env*` |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Test run reaches production API with a leftover bearer token | Information disclosure | Scheme test env `SW_LOCAL_MOCK=1` (verified) + guard test + optional dead `SW_API_BASE` |
| Test-written token/poem persists on the simulator | Information disclosure (anonymity) | No `TokenStore` writes in Phase 1 tests; Phase 2 must clear/restore |
| Evidence bundles committed accidentally | Information disclosure | `/build/` gitignored (D-05) |
| Shell script clobbering other simulators | Denial of service (dev loop) | Shut down only the UDID this script booted; never `shutdown all` |

## Sources

### Primary (HIGH confidence — reproduced this session)
- Probe log (scratchpad copy of `ios/`, Xcode 16.4, iPhone 16 / iOS 18.6, XcodeGen 2.45.4):
  - P1: `go test ./... && go vet ./... && go build ./...` green in `server/` (gofmt -l lists pre-existing files `gateway_test.go`, `session.go`, `validate.go`, `store.go`; not part of this phase, not caused by the dirty tree — `config.go` is gofmt-clean)
  - P2: `xcodegen generate` + `xcodebuild build` green with `CODE_SIGNING_ALLOWED=NO` and with default signing
  - P3: generated `PRODUCT_BUNDLE_IDENTIFIER` values: app `com.strangerwords.us`, test `com.strangerwords.us.tests`
  - P4/P5: ghost-token behavior; scheme test env reaches host; `AppModel.init` clears token in mock mode
  - P6: negative control (no env: `mock=nil`, token survives, `resume()` runs on it) and `TEST_RUNNER_SW_LOCAL_MOCK=1` forwarding (`mock=1`, token cleared)
  - P7: pass / zero-test / failing-test / compile-error verdicts from `xcresulttool` (`totalTestCount`, `result`, `testFailures`)
  - P8: prototype `test-ios.sh` exits 0 / 1 / 1; simulator not left booted
- `ios/project.yml:38-69`, `ios/Strangewords/App/AppModel.swift:50-63`, `ios/Strangewords/Net/APIClient.swift:22-31` (read this session)
- `git diff` of the six files; `git check-ignore` output

### Secondary (MEDIUM confidence)
- `.planning/research/STACK.md`, `.planning/research/PITFALLS.md` (earlier prototype/spike in the same environment; items not re-run are tagged `[CITED]`/`[ASSUMED]` above)

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools present and exercised.
- Architecture: HIGH — the exact flow was run end to end in a scratch copy.
- Pitfalls: HIGH for 1-4, 6, 8 (reproduced); MEDIUM for 5 (cold-boot flake not reproduced this session) and 7 (forward-looking).

**Research date:** 2026-10-08
**Valid until:** 2026-11-07 for the recipe, or until Xcode/XcodeGen is upgraded (re-verify the `xcresulttool` JSON fields).
