# Phase 1: Clean Tree & Trustworthy iOS Harness - Pattern Map

**Mapped:** 2026-10-08
**Files analyzed:** 7 new/modified (plus 6 commit-only files)
**Analogs found:** 4 / 7 (3 have no in-repo analog; use RESEARCH.md recipes)

All analogs below were verified as git-tracked (`git ls-files`). `ios/Strangewords/Strangewords.entitlements` is untracked until committed (commit it WITH `ios/project.yml`).

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `ios/project.yml` (add `StrangewordsTests` target and scheme `test:`) | config | build-time | `ios/project.yml` (existing `Strangewords` target and `schemes:`) | exact (same file) |
| `ios/StrangewordsTests/SyllablesTests.swift` | test | transform | none in iOS; subject is `ios/Strangewords/Syllables/Syllables.swift`; Go table-test style in `server/internal/sessions/validate_test.go` | partial |
| `ios/StrangewordsTests/HostIsolationTests.swift` (plus optional `HarnessCanary`) | test | env guard | none | no analog |
| `scripts/test-ios.sh` | utility (script) | batch / request-response to simctl and xcodebuild | `run.sh` | role-match |
| `.gitignore` | config | n/a | `.gitignore` lines for `ios/build/` | exact |
| Commit-only: `ios/project.yml`, `ios/Strangewords/Strangewords.entitlements`, `run.sh`, `docs/STATUS.md`, `server/DEPLOY.md`, `server/internal/config/config.go` | reconcile | n/a | none | n/a |

## Pattern Assignments

### `ios/project.yml` (config)

**Analog:** itself. Add the test target as a sibling of `Strangewords:` under `targets:` (after line 54) and extend `schemes:` (lines 60-69).

**Existing scheme block to extend** (lines 60-69). Note `run:` uses MAP form for env:
```yaml
schemes:
  Strangewords:
    build:
      targets:
        Strangewords: all
    run:
      config: Debug
      environmentVariables:
        SW_LOCAL_MOCK: "1"
        SW_DEV: "1"
```
**Add** (from RESEARCH Code Examples A; verified in probes). The `test:` env MUST be explicit, otherwise XcodeGen emits `shouldUseLaunchSchemeArgsEnv = "YES"` and tests inherit Run env by accident:
```yaml
  StrangewordsTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - StrangewordsTests
    dependencies:
      - target: Strangewords
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.strangerwords.us.tests
# ...in schemes.Strangewords, after build:
    test:
      config: Debug
      targets:
        - StrangewordsTests
      environmentVariables:
        - variable: SW_LOCAL_MOCK
          value: "1"
        - variable: SW_API_BASE
          value: "http://127.0.0.1:9"   # optional defense in depth
```
Conventions: 2-space YAML, explanatory `#` comments stating WHY (see lines 25-27, 45-48, 55-59). Add a comment that the test env is explicit on purpose. Source of truth is this file; never hand-edit the `.xcodeproj`. Regenerate with `cd ios && xcodegen generate`.

---

### `ios/StrangewordsTests/SyllablesTests.swift` (test, transform)

**Subject:** `ios/Strangewords/Syllables/Syllables.swift`, API `enum Syllables { static func count(_ text: String) -> Int }` (line 6-7).

**Pattern** (Swift Testing, D-10; expected values were computed from the real implementation, see RESEARCH):
```swift
import Testing
@testable import Strangewords

struct SyllablesTests {
    @Test(arguments: [
        ("hello", 2), ("the", 1), ("silent", 2), ("fire", 1),
        ("river", 2), ("autumn", 2), ("", 0), ("123", 0),
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
Do NOT pin known heuristic misses ("poem", "quiet", "rhythm") in Phase 1. Style: 4-space indent, no semicolons (project Swift convention). Table-driven style parallels Go tests in `server/internal/sessions/validate_test.go`. Add `@Suite(.serialized)` only for suites touching `TokenStore`/`UserDefaults`.

---

### `ios/StrangewordsTests/HostIsolationTests.swift` (test, env guard)

**Analog:** none. Use the RESEARCH recipe. It guards D-12 permanently:
```swift
import Testing
import Foundation

struct HostIsolationTests {
    @Test func hostRunsInLocalMockMode() {
        #expect(ProcessInfo.processInfo.environment["SW_LOCAL_MOCK"] == "1")
    }
}
```
Mechanism it protects: `ios/Strangewords/App/AppModel.swift:55-60` picks `LocalBackend()` and calls `TokenStore.clear()` when `SW_LOCAL_MOCK == "1"`.

Optional canary (RESEARCH C(b), needs a one-time check, assumption A4) for re-runnable failing-verdict proof:
```swift
struct HarnessCanary {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SW_HARNESS_CANARY_FAIL"] == "1"))
    func failsOnPurpose() { #expect(Bool(false), "harness canary") }
}
// TEST_RUNNER_SW_HARNESS_CANARY_FAIL=1 scripts/test-ios.sh  -> must exit 1
```

---

### `scripts/test-ios.sh` (utility, batch)

**Analog:** `/Users/charris/src/strangewords/run.sh`. The full verified prototype is in RESEARCH Code Examples B; lift it verbatim, then align with run.sh conventions below. Do not reuse run.sh logic that conflicts with the harness.

**Copy from run.sh:**

Header comment block plus strict shell and ROOT resolution (lines 1-22):
```bash
#!/usr/bin/env bash
# (usage doc comment block)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
IOS="$ROOT/ios"
```
Adapt: `ROOT="$(cd "$(dirname "$0")/.." && pwd)"` because the script lives in `scripts/`. DEVIATION: use `set -uo pipefail` WITHOUT `-e` (must continue past failing xcodebuild).

Tool preflight (lines 50-51), then project generation (line 54):
```bash
command -v xcodegen >/dev/null || { echo "xcodegen not found — brew install xcodegen"; exit 1; }
( cd "$IOS" && xcodegen generate >/dev/null )
```
Adapt: exit code 2 for missing tools and add `jq` and `xcrun`.

Boot wait (line 107): `xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true`

xcodebuild invocation shape (lines 57-60), keep `CODE_SIGNING_ALLOWED=NO`:
```bash
xcodebuild -project "$PROJ" -scheme Strangewords \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$IOS/build" \
  CODE_SIGNING_ALLOWED=NO -quiet build
```
Adapt: `xcodebuild test`, `-destination "id=$UDID"`, `-derivedDataPath "$ROOT/build/derived/ios-test"` (NOT `ios/build`, which run.sh owns), plus `-resultBundlePath`.

**Do NOT copy from run.sh:**
- `resolve_udid` text grep (lines 74-78); use `simctl list devices available -j | jq` with exact-name `select` (avoids iPhone 16 / Plus / Pro / e collisions).
- Shutting down all other booted sims (lines 91-96) and `simctl shutdown all`; shut down only the UDID the script booted.
- `open -a Simulator` (line 98).
- Emoji/`▸` banner style is optional; the verdict line format is `test-ios: PASS|FAIL {json} (xcodebuild rc=N) evidence: DIR`.

**Verdict core** (the contract Phase 4 composes; exit code plus `$OUT` evidence dir):
```bash
if jq -e '.result=="Passed" and .failedTests==0 and .passedTests>0 and .totalTestCount>0' "$SUMMARY" >/dev/null 2>&1; then
  ...; exit 0
fi
...; exit 1
```
Exit codes: 0 pass, 1 test verdict fail, 2 environment/preflight. Evidence goes to `${SW_VERIFY_OUT:-$ROOT/build/verify/<timestamp>}`. Retry once only when `totalTestCount == 0` AND log contains `Early unexpected exit`; use per-attempt result-bundle names and `rm -rf` the path first. Header must document that the host wipes the dev token on the test simulator. `chmod +x`.

---

### `.gitignore` (config)

**Analog:** its own Xcode block:
```
# Xcode / iOS
ios/**/xcuserdata/
ios/build/
```
Add (currently `build/` is NOT ignored):
```
# Verification evidence + test derived data (scripts/test-ios.sh, Phase 4 verify.sh)
/build/
```

---

### Reconciliation commits (HARN-01, D-01/D-02)

No code analog. Order (stage by explicit path, never `git add -A`):
1. `ios/project.yml` + `ios/Strangewords/Strangewords.entitlements` + `run.sh` + `docs/STATUS.md` + `server/DEPLOY.md` (entitlements must ride with project.yml since `CODE_SIGN_ENTITLEMENTS` references it).
2. `server/internal/config/config.go`.
3. Later commits for tests, scheme `test:`, script, and `.gitignore`.
Run `cd server && go test ./... && go vet ./... && go build ./...` and an `xcodebuild build` (throwaway `-derivedDataPath build/derived/ios-build`) BEFORE committing. Final check: `git status --short` prints nothing. Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Shared Patterns

### XcodeGen is the source of truth
**Source:** `ios/project.yml`. **Apply to:** every iOS target or scheme change. Run `xcodegen generate` first in any script; `.xcodeproj` and `Info.plist` are gitignored.

### Mock-mode isolation
**Source:** `ios/Strangewords/App/AppModel.swift:55-60` plus scheme env. **Apply to:** all test runs. `SW_LOCAL_MOCK=1` must come from the explicit scheme `test:` env (optionally also `TEST_RUNNER_SW_LOCAL_MOCK=1` on the CLI).

### Signing off for tests
**Source:** `run.sh:60` (`CODE_SIGNING_ALLOWED=NO`). **Apply to:** every `xcodebuild test`. Consequence: App Attest entitlements are not exercised; add to Phase 4's not-verified list, along with the iOS 17 runtime gap (only 18.6 installed).

### Anonymity
**Apply to:** all tests. No `TokenStore` writes in Phase 1; Phase 2 tests must clear/restore what they write (shared `UserDefaults` container `com.strangerwords.us`).

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `ios/StrangewordsTests/*` | test | transform / env guard | No iOS test target or Swift Testing code exists yet; use RESEARCH Code Examples A |
| `scripts/` directory | utility | batch | New directory; only `run.sh` is a loose analog (root-level scripts: `run.sh`, `live_test.sh`, `run_test_server_and_robot_poet_friend.sh`) |
| Result-bundle verdict logic | utility | transform | No existing `xcresulttool`/`jq` usage; use RESEARCH Code Examples B |

## Metadata

**Analog search scope:** repo root scripts, `ios/project.yml`, `ios/Strangewords/Syllables`, `.gitignore`, Go `_test.go` inventory
**Files scanned:** about 10
**Pattern extraction date:** 2026-10-08
