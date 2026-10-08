# Technology Stack: Automated Verification Baseline

**Project:** Stranger Words (milestone: verification baseline; existing app, nothing new shipped)
**Dimension:** Stack, covering iOS unit tests, headless CLI runs, and scripted Go e2e
**Researched:** 2026-10-08
**Overall confidence:** HIGH. The core iOS recipe was prototyped end to end in a scratch copy of `ios/` on this machine (Xcode 16.4, XcodeGen 2.45.4, iPhone 16 / iOS 18.6 simulator). Nothing in the repo was modified.

## Bottom Line

Use Swift Testing (bundled with the Xcode toolchain, so still zero third-party dependencies) in one hosted `bundle.unit-test` target declared in `ios/project.yml`. Drive it with plain `xcodebuild test` plus `xcresulttool` for a machine-checkable verdict. Do the e2e in Go: a build-tagged test package that spawns the real `cmd/server` binary against an in-process miniredis, plays the existing robot poet against a scripted "human" client, and asserts the zero-keys invariant. Add no new dependencies. No Docker is needed.

## Toolchain Actually Installed (verified on this machine)

| Tool | Version found | Latest known | Decision |
|------|---------------|--------------|----------|
| Xcode | 16.4 (16F6), Swift 6.1.2 | Xcode 26.x exists (26.5 notes seen); Swift 6.4 released 2026-09 | Stay on 16.4 for this milestone. Do not upgrade mid-baseline. The recipe below is not Xcode-26-specific. |
| iOS Simulator runtime | iOS 18.6 only | n/a | Only the iOS 18.6 runtime is installed; there is no iOS 17 runtime. See Gaps. |
| XcodeGen | 2.45.4 | 2.46.0 (2026-07-16) | Keep 2.45.4. Nothing needed from 2.46. |
| Go | 1.26.0 | n/a | `go.mod` says 1.25.0, fine. `go test ./...` is green today. |
| miniredis | v2.38.0 (go.mod) | v2.39.0 (2026-09-02) | Keep. Do not bump in a verification milestone. |
| Docker | present | n/a | Needed only by the legacy `live_test.sh`. The new e2e does not need it. |
| redis-server / redis-cli | NOT installed | n/a | Do not depend on a native Redis. Use miniredis. |
| xcbeautify / xcpretty / jq | none / none / present | n/a | Use raw `xcodebuild` output plus `xcresulttool` plus `jq`. |

## Recommended Stack

### iOS Test Framework
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Swift Testing (`import Testing`) | Ships with Xcode 16.4; "Testing Library Version 124.4" reported at runtime | All unit tests: `AppModel`, `LocalBackend`, `Syllables`, `PoemNaming`, models | Built into the toolchain, so it adds no dependency and honors the no-third-party convention. `#expect` and parameterized `@Test(arguments:)` suit the table-heavy cases (syllable counts, naming determinism). Native async/await tests suit the `actor LocalBackend` and the `@MainActor @Observable AppModel`. Suites are structs and parallel by default. Verified: it runs hosted on the simulator with `SWIFT_VERSION: "5.0"` and the iOS 17.0 deployment target. | HIGH (prototyped) |
| XCTest | Ships with Xcode | Reserved for a future UI-test target only | Swift Testing does not do UI automation (XCUITest) or `measure` performance tests. Neither is in scope ("automated-only, no human driving a simulator", and no UI tests were requested). Keep XCTest out of this milestone. | HIGH |

Why not XCTest for the unit tests: the code under test is async and actor-based. XCTest forces expectations or `await fulfillment(of:)`, and gives weaker failure output. The only argument for XCTest is mixing with UI tests, which are out of scope. Swift Testing and XCTest can coexist in one target if XCUITest is added later, but UI tests need their own `bundle.ui-testing` target anyway.

### Project Wiring (XcodeGen)
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| XcodeGen `bundle.unit-test` target | 2.45.4 | Declares `StrangewordsTests` in `ios/project.yml` | The `.xcodeproj` is gitignored, so `project.yml` is the only place a test target can live. XcodeGen docs state `TEST_HOST` is set automatically for unit tests targeting an application, and `dependencies: - target: Strangewords` gives `@testable import Strangewords`. Verified working. | HIGH (prototyped) |
| XcodeGen scheme `test:` section | 2.45.4 | Makes `xcodebuild test -scheme Strangewords` run the tests, with coverage | Without a `test:` block on the explicit scheme, `xcodebuild test` has nothing to run. | HIGH (prototyped) |

Exact YAML that was verified (append under `targets:`, and add `test:` to the existing `schemes: Strangewords:` block next to `build:` and `run:`):

```yaml
targets:
  # ... existing Strangewords app target unchanged ...
  StrangewordsTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - StrangewordsTests          # new dir: ios/StrangewordsTests/
    dependencies:
      - target: Strangewords       # sets TEST_HOST/BUNDLE_LOADER; enables @testable import
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
      gatherCoverageData: true
      coverageTargets:
        - Strangewords
      targets:
        - StrangewordsTests
      # Recommended (not prototyped, MEDIUM): keep the host app off the network
      # while it boots as the test host. Ensures AppModel() defaults to LocalBackend.
      # environmentVariables:
      #   - variable: SW_LOCAL_MOCK
      #     value: "1"
    run:
      config: Debug
      # ... existing environmentVariables unchanged ...
```

Notes:
- The test target needs no `info:` block. `GENERATE_INFOPLIST_FILE: YES` was used in the prototype.
- No `DEVELOPMENT_TEAM` or signing work is needed for simulator tests. Pass `CODE_SIGNING_ALLOWED=NO` on the command line, as `run.sh` already does. The app's entitlements file coexisted fine in the prototype.
- `sources: StrangewordsTests` is relative to `ios/` (where `project.yml` lives). Create `ios/StrangewordsTests/`.

### Headless Command-Line Runs
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| `xcodebuild test` | Xcode 16.4 | Run unit tests with no GUI | The prototype run took about 13s wall-clock cold. xcodebuild boots the simulator itself, and Simulator.app is NOT needed (`run.sh`'s `open -a Simulator` is a UI-only habit; do not copy it into the test script). | HIGH (prototyped) |
| `-resultBundlePath` + `xcrun xcresulttool get test-results summary --path X.xcresult` | Xcode 16.4 | Machine-checkable verdict (`result`, `passedTests`, `failedTests`, `totalTestCount`) | The text output is not a reliable verdict (see the zero-test gotcha). Use with `jq`. `xcresulttool get test-results tests` lists test identifiers. The path must not already exist, so `rm -rf` it first. | HIGH (prototyped) |
| `xcrun xccov view --report --only-targets X.xcresult` | Xcode 16.4 | Coverage readout (prototype showed Strangewords.app 21.26% with 2 trivial tests) | Free, built in. Report only; no threshold gate this milestone. | HIGH |
| `-only-testing:'StrangewordsTests/AppModelTests/beginMovesToWaiting()'` | Xcode 16.4 | Run one test or suite | Identifier format is `Target/Suite/function()`, with parentheses and quotes. Verified. Parameterized tests list as `Suite/fn(word:n:)`. | HIGH (prototyped) |

Canonical invocation (the script for the roadmap to wrap as `ios/test.sh` or `./test_ios.sh`):

```bash
set -euo pipefail
cd ios && xcodegen generate >/dev/null            # .xcodeproj is gitignored; always regenerate
RB=build/TestResults.xcresult; rm -rf "$RB"       # xcodebuild refuses an existing bundle path
SIM="${SW_SIM_NAME:-iPhone 16}"                   # only name that exists locally; override per machine
set +e
xcodebuild test \
  -project Strangewords.xcodeproj -scheme Strangewords \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath build -resultBundlePath "$RB" \
  CODE_SIGNING_ALLOWED=NO -enableCodeCoverage YES
rc=$?
set -e
# Do NOT trust rc/"TEST SUCCEEDED" alone. Assert on the result bundle.
xcrun xcresulttool get test-results summary --path "$RB" \
  | jq -e '.result=="Passed" and .failedTests==0 and .totalTestCount>0' >/dev/null
xcrun simctl shutdown all || true                 # xcodebuild leaves the sim Booted
exit $rc
```

Reuse `ios/build` as `-derivedDataPath` (already gitignored via `ios/build/` and already used by `run.sh`). This shares build products with `run.sh`.

### Go End-to-End Verification
| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Go `testing` + `os/exec` + `net/http` (stdlib) | Go 1.26 | New package `server/e2e` (build tag `//go:build e2e`) | Matches the stdlib-first, no-assertion-library convention in `TESTING.md`. A real test gives a real pass/fail exit code, which the shell scripts cannot. | HIGH |
| miniredis `miniredis.Run()` as a TCP Redis | v2.38.0 (already in go.mod) | Redis for the spawned real server | `Run()` listens on a real TCP port, so the unmodified `cmd/server` binary can be pointed at it with `SW_REDIS_ADDR=<mr.Addr()>`. No Docker, no redis-server. It also gives `mr.Keys()` for the zero-keys-after-dissolution invariant, reusing the existing `assertNoSessionKeys` idea. Caveat: miniredis TTLs only expire via `mr.FastForward`; test TTL behavior explicitly, never by sleeping. | HIGH on mechanism; MEDIUM that every Redis command the server uses behaves identically (the gateway tests already prove the main paths) |
| Existing `cmd/bot` robot poet | in repo | The scripted second participant | It is the tool the project already built. Run it as a subprocess (`go build` to `t.TempDir()`) with `-once`, and let the Go test play the "human" over HTTP, mirroring `gateway_test.go`'s `rig.do`. | HIGH |
| `make e2e` target | n/a | `go test -tags e2e -count=1 ./e2e/...` | Keeps `go test ./...` fast and hermetic; e2e opts in. `-count=1` defeats test result caching for process-spawning tests. | HIGH |

Required small changes to existing code (so e2e can give a real verdict):
1. `server/cmd/bot/main.go`: today `-once` exits 0 even when `playOne()` errored, because it prints "(hiccup ...)" and returns. Make it exit non-zero on error and print a stable completion line (for example the poem block), so the harness can assert on exit code and output. Without this change, the bot gives no machine-readable pass/fail.
2. Port selection: `SW_ADDR=127.0.0.1:<free port>` (listen on `:0`, read the port, close, then pass it), then poll `/healthz` as `live_test.sh` does. Never hardcode `:8080` (the legacy scripts kill whatever is on 8080).
3. Capture server stdout (JSON slog) to a buffer and attach it to the test log on failure.

E2E test shape (one test, about 10 to 15s because the bot pauses 1.5 to 3.3s per turn):
- Start miniredis, build and start the server, wait for healthz.
- Spawn `bot -once -base http://127.0.0.1:PORT`.
- The test enters via `/v1/enter`, polls `/v1/waiting`, and writes its lines when `yourTurn`. Assert 5-7-5 form, round-robin turn order, the bot's lines present, and `status == "complete"`.
- Both sides dismiss. Then assert the bot exited 0, `/v1/session/{id}` returns 410, and `mr.Keys()` is empty (anonymity and teardown invariant).
- Optionally add a second test where the human calls `leave` mid-poem and the bot sees 410 and exits cleanly.

### Supporting Pieces
| Library / tool | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| `jq` | installed | Parse `xcresulttool` JSON in scripts | Always, in the iOS test script |
| `xcrun simctl shutdown all` | Xcode | Leave no booted sim after a run | End of the iOS script |
| `go test -race -count=1 ./...` | Go 1.26 | Race-checked backend run | Add to the verification script. `TESTING.md` says it is not wired in yet. |
| `go vet ./...` | Go 1.26 | Static check | Already `make vet` |
| `xcrun xccov` | Xcode | Coverage report | Informational only |

## Testability Seams the iOS Tests Will Need (small source changes, not new deps)

These are findings from reading `AppModel.swift`, `LocalBackend.swift`, and `Keychain.swift`. Tests written against the code as it stands will be slow or flaky, so the roadmap should schedule these as part of the iOS test phase (fix-as-we-go).

| Seam | Problem today | Fix | Confidence |
|------|---------------|-----|------------|
| Poll interval | `private let pollInterval: Duration = .seconds(3)` in `AppModel`. A waiting-to-matched or poll-to-your-turn test costs at least 3s each. | Add an init parameter (default `.seconds(3)`), e.g. `init(backend:pollInterval:)`. Tests pass `.milliseconds(10)`. | HIGH |
| Stranger think time | `LocalBackend.strangerThinkTime = 1.6s`, compared against `Date()`. A full-arc test costs at least 1.6s plus a poll. | Make it an init parameter (default 1.6) so tests set `0`. Keep the existing public behavior. | HIGH |
| Global token state | `TokenStore` writes `UserDefaults.standard`, shared across tests and with the host app process. Swift Testing runs suites in parallel by default. | Put every `AppModel` and `TokenStore` suite under `@Suite(.serialized)`, and call `TokenStore.clear()` at the start of each test. Do not mock `UserDefaults` with a library. | HIGH |
| Haptics | `Haptics.*` are static UIKit calls from `AppModel`. | Leave them. They are harmless on the simulator. Do not abstract them for the baseline. | MEDIUM |
| `AppModel` selection | `AppModel(backend:)` already accepts an injected `Backend`, and `Backend` is a small `Sendable` protocol. | No change needed. Hand-write a `StubBackend` struct in the tests (prototyped). | HIGH |
| Mock/real drift | `LocalBackend` re-implements server rules (5-7-5, round-robin from offset 0). | Pin its behavior in tests. For true drift detection, add a Go test that reads the real `/v1/enter` form targets and asserts them against a small shared fixture list; defer to a later milestone if scope is tight. | MEDIUM |

Test inventory the stack should support (maps to the Active requirements): `Syllables.count` (parameterized words), `PoemNaming.coin(from:)` (same lines give the same name; empty or short input returns `nil`; pin a couple of golden outputs), `LocalBackend` (turn order, `lines`, form 5-7-5, `status` complete after 3 lines, a `submitLine` out-of-turn no-op, `enter` resets), `AppModel` (threshold to connecting to waiting or composing; content-rejected shows `submitError`; `gone` leads to dissolved(.partnerLeft); release then finishDissolving sets `keepsake` and dissolved(.completedAndGone); `reset` returns to threshold), and `SessionView` Codable round-trip (decode a literal JSON from the Go wire format).

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| iOS unit framework | Swift Testing | XCTest | More ceremony for async and actor code; no benefit without UI tests. Revisit only when adding XCUITest. |
| iOS unit framework | Swift Testing | Quick/Nimble, ViewInspector, SnapshotTesting, swift-snapshot-testing | Third-party SPM dependencies violate the project's "no third-party iOS dependencies" rule. Also out of scope (no UI or snapshot verification this milestone). |
| Test host | Hosted `bundle.unit-test` with `dependencies: target` | Logic-only bundle compiling app sources into the test target | Hosted gives `@testable import` with no source duplication. Prototype confirmed it. The cost is the app booting as host (about 1 to 2s), which is acceptable. |
| Test runner | Raw `xcodebuild` + `xcresulttool` + `jq` | xcpretty / xcbeautify / fastlane scan | Extra installs and dependencies for cosmetic output. Neither is installed, and the xcresult summary is the more reliable verdict anyway. |
| Running via | `xcodebuild test` | `swift test` / SwiftPM | The app is an Xcode app target, not a package. `swift test` cannot run it. |
| E2E Redis | In-process miniredis over TCP | Docker `redis:7-alpine` (as `live_test.sh`) | Docker adds startup time, port state, and `FLUSHALL` races. miniredis is already the project's test double and gives direct key inspection. Keep Docker only for the manual live path. |
| E2E driver | Go test spawning server and bot | Extending `live_test.sh` | The shell scripts need a human to tap "begin" in the simulator and have no pass/fail exit. They stay as the manual dev loop. |
| iOS side of e2e | None this milestone (app-level e2e is deferred) | XCUITest driving the simulator against a real local server | Valuable, but heavy: a UI-test target, launch-argument plumbing, and flake risk. The Go e2e proves the wire contract and `AppModel` unit tests prove the client logic, which together cover the baseline. Candidate follow-on. |
| Backend assertions | stdlib `testing` | testify / gomock | Contradicts the stdlib-first convention in `TESTING.md`. |
| CI | None (out of scope) | GitHub Actions macOS runner | Explicitly out of scope. Note that `fly-deploy.yml` deploys with no test step. Note for the follow-on. |

## What NOT to Use

- Any SPM or CocoaPods test library (Quick, Nimble, ViewInspector, SnapshotTesting, OHHTTPStubs). Violates the zero-dependency rule, and Swift Testing plus a hand-written stub is enough.
- `open -a Simulator` or any GUI step in the test path. It is unnecessary and defeats "headless".
- A hardcoded simulator UDID. The UDIDs are per-machine. Resolve by name, or by the `resolve_udid` approach in `run.sh`, with a `SW_SIM_NAME` override.
- The text line `** TEST SUCCEEDED **` or xcodebuild's exit code as the sole verdict (see Pitfall below).
- `time.Sleep` for TTL or timing in Go e2e tests; `TESTING.md` already forbids it. Use `mr.FastForward` and polling with deadlines.
- Hitting `https://api.strangerwords.us` or the Fly app from any test. Prod verification is out of scope.

## Critical Gotchas Found While Prototyping

1. **Zero-test false green (HIGH, observed).** `xcodebuild test -only-testing:'StrangewordsTests/DoesNotExist'` printed `** TEST SUCCEEDED **` with "Executed 0 tests", and `xcresulttool` reported `result: "unknown"`, `totalTestCount: 0`. A typo, a broken target membership, or an empty target would pass silently. The wrapper script must assert `totalTestCount > 0` and `result == "Passed"`.
2. **Failing test exit code (HIGH, observed).** A failing `#expect` gives xcodebuild exit 65 and `result: "Failed"`. So non-zero is trustworthy, while zero is not.
3. **Misleading XCTest banner (HIGH, observed).** Output includes `Test Suite 'All tests' passed ... Executed 0 tests`, which is the empty XCTest harness. Swift Testing results follow after it, as `✔ Test run with N tests passed`. Do not grep the first banner.
4. **Simulator left booted (HIGH, observed).** After the run, iPhone 16 was still Booted. `simctl shutdown all` at the end of the script, or later `run.sh` runs will find a stray device.
5. **Swift Testing runs in parallel by default.** Combined with `UserDefaults.standard` in `TokenStore`, this makes cross-test interference likely. Use `.serialized` (see seams).
6. **`.xcodeproj` is gitignored.** Every test run must start with `xcodegen generate`, or a new test file will not be in the target.
7. **Swift Testing's runtime banner reports `arm64-apple-ios13.0-simulator`.** This is the testing library's own platform string, not your deployment target. The 17.0 target is respected (the prototype built with the project's settings).
8. **`resultBundlePath` must not pre-exist**, or xcodebuild fails. `rm -rf` first.

## Installation

```bash
# Nothing to install. Everything is already on the machine or in go.mod.
# Verified present: Xcode 16.4, xcodegen 2.45.4, jq, go 1.26, miniredis v2.38.0 in go.mod.
# Do NOT brew install xcbeautify/xcpretty; they are not needed.

# iOS tests (after adding the project.yml block and ios/StrangewordsTests/)
cd ios && xcodegen generate

# Go e2e
cd server && go test -tags e2e -count=1 ./e2e/...
```

## Gaps and Risks

- **No iOS 17 simulator runtime installed.** Only iOS 18.6 exists locally, so tests prove the code on iOS 18.6 built with a 17.0 deployment target, not on an iOS 17 runtime. If true iOS 17 coverage matters, install the runtime via Xcode Settings, then Platforms; this is a human or download step. Flag it in the roadmap as an accepted limit or optional task. (HIGH that only 18.6 is installed; MEDIUM that this matters here.)
- **Xcode 26.x behavior not verified locally.** The Xcode 16.4 recipe is expected to carry forward (xcodebuild, xcresulttool, and Swift Testing are stable interfaces, and release notes seen mention only additive Swift Testing features like attachments and issue severity). Treat it as MEDIUM on newer Xcode until run there. One known issue in Xcode 26.5 notes: stdout and stderr streaming can lag during parallel testing, which is cosmetic.
- **`xcresulttool` flag stability.** Apple deprecated the old `xcresulttool` subcommands in Xcode 16 (they require `--legacy`). The `get test-results summary` and `tests` subcommands used here are the supported ones. Their JSON schema is not formally published, so pin the `jq` filter to the few fields used (`result`, `failedTests`, `totalTestCount`) and re-verify on Xcode upgrade. (MEDIUM)
- **Coverage is informational.** 21% with two trivial tests shows the plumbing works. Set no threshold until the suite exists.
- **Working-tree state.** `ios/project.yml` and `run.sh` have uncommitted edits (App Attest entitlements). The prototype copied the dirty tree and worked. Reconcile before committing the test target.
- **`LocalBackend` vs real-server drift** is guarded only by mirror tests, not by a contract test. Consider a follow-on.

## Confidence Summary

| Recommendation | Confidence | Basis |
|----------------|------------|-------|
| Swift Testing in a hosted `bundle.unit-test` target | HIGH | Built and run end to end locally, including parameterized, async, and `@MainActor` tests |
| XcodeGen block and scheme `test:` section | HIGH | Run locally; matches XcodeGen ProjectSpec docs |
| `xcodebuild test` + `xcresulttool` + `jq` verdict | HIGH | Observed pass, fail (exit 65), and zero-test behavior |
| Go e2e: real server binary + miniredis TCP + bot subprocess | MEDIUM-HIGH | Mechanism standard and miniredis already used in gateway tests; not prototyped here; bot exit-code change required |
| Testability seams (poll interval, think time, `.serialized`) | HIGH | Derived directly from reading source |
| Behavior on Xcode 26.x or newer | MEDIUM | Not installed; release notes only |
| Scheme `environmentVariables: SW_LOCAL_MOCK` for the test host | MEDIUM | Documented XcodeGen feature; not run |

## Sources

- Local prototype run, 2026-10-08, in a scratch copy of `ios/` (Xcode 16.4, iOS 18.6 simulator): HIGH
- XcodeGen ProjectSpec: https://raw.githubusercontent.com/yonaskolb/XcodeGen/master/Docs/ProjectSpec.md (scheme `test`, `testTargets`, `TEST_HOST` auto-set for unit tests): HIGH
- XcodeGen releases (2.46.0, 2026-07-16), miniredis releases (v2.39.0, 2026-09-02), swift-testing releases (via `gh api`): HIGH
- Apple developer forum thread on Swift Testing minimum deployment target (iOS 13+): https://developer.apple.com/forums/thread/803950 : MEDIUM (forum, Apple engineer)
- Xcode 26.5 release notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-26_5-release-notes.md : HIGH (official, not fetched in full)
- Apple forum on `xcresulttool` format and `--legacy` deprecation: https://developer.apple.com/forums/thread/763050 : MEDIUM
- Existing repo context: `.planning/PROJECT.md`, `.planning/codebase/STACK.md`, `.planning/codebase/TESTING.md`, `ios/project.yml`, `server/cmd/bot/main.go`, `ios/Strangewords/App/AppModel.swift`, `ios/Strangewords/Net/LocalBackend.swift`: HIGH
