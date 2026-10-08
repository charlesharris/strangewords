# Feature Research

**Domain:** Automated verification baseline for a mobile client-server app (SwiftUI iOS 17+ client with a mock backend, plus a Go/Redis backend that already has a solid test suite)
**Researched:** 2026-10-08
**Confidence:** HIGH on what to include and exclude. This is driven by the project's own constraints (PROJECT.md, TESTING.md) and well-established testing practice. MEDIUM on exact tool mechanics (XcodeGen test-target syntax, `xcodebuild test` flags). The roadmap phase should verify those against the installed Xcode 16.4 / iOS 18.6 simulators.

Here "features" means verification capabilities the milestone delivers, not app features. The "user" is the developer (and later CI) who needs a repeatable answer to "is the core experience still working?"

Local facts that shape the scope:
- Xcode 16.4 is installed, with iOS 18.6 simulators (iPhone 16 and others), so headless `xcodebuild test` is available.
- `ios/project.yml` has a single `Strangewords` application target. There is no test target and no `.xcodeproj` in git.
- The robot poet (`server/cmd/bot`) is a log-only loop. It has no assertions, swallows errors ("hiccup, trying again"), and needs a counterpart. `-once` plays one poem. `run_test_server_and_robot_poet_friend.sh` needs Docker for Redis.
- Go tests cover the lifecycle thoroughly via miniredis. The gap is entirely on the iOS side, plus the lack of a scripted real-server run with a pass/fail result.

## Feature Landscape

### Table Stakes (a baseline isn't credible without these)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **T1. Reconcile working tree + green "existing checks" run** (`go test ./...`, `go vet`, `go build`, XcodeGen generate + `xcodebuild build`) | A baseline is meaningless on a dirty or unbuildable tree. This is the first gate and the "does it even compile" smoke test. | LOW | Six files are uncommitted (project.yml, run.sh, config.go, etc.). Decide commit or revert first. Add `go test -race ./...` as a one-off run, since the matchmaking race test is worth running under the detector. |
| **T2. iOS unit-test target in `project.yml`** (bundle `unit-test`, `TEST_HOST`/`@testable import Strangewords`, added to the scheme's `test:` action) | Prerequisite for every other iOS test. Without it nothing else exists. | MEDIUM | Main risk is signing/entitlements: the app has `CODE_SIGN_ENTITLEMENTS` (App Attest) and `DEVELOPMENT_TEAM`. For simulator test runs, `CODE_SIGNING_ALLOWED=NO` or the simulator's ad-hoc signing normally works. The run action's env vars (`SW_LOCAL_MOCK`, `SW_DEV`) do NOT apply to the test action, so tests must not depend on them. |
| **T3. Headless CLI test execution** (one script or Make target: `xcodegen` → `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 16'`, non-zero exit on failure) | "Automated-only" is a hard milestone constraint. If tests need Xcode's GUI they don't count. | LOW-MEDIUM | Pin an explicit simulator destination. Capture the `.xcresult` bundle (`-resultBundlePath`) as verification evidence. Pipe through `xcpretty` only if already present, since there are no third-party dependencies. Plain `xcodebuild` output is acceptable. |
| **T4. `AppModel` state-machine tests** (every phase transition in threshold → waiting → compose → reveal → dissolve → dissolved, including the polling-driven ones) | `AppModel` is the heart of the client, and the milestone names it explicitly. A state machine is the highest-value unit-test target. | MEDIUM-HIGH | Drive `AppModel` against `LocalBackend` or a scripted fake `Backend` (the protocol seam already exists). Cover: happy path, waiting→matched, turn handoff, submit error and retry, partner-gone and early dissolve, "begin again" returning to threshold. The hard part is the 3s polling timer. Tests need an injectable interval/clock, or an `await` on state changes with a bounded timeout. Do not use `sleep(3)`. If `AppModel` hard-wires its timer, a small seam refactor is justified (fix-as-we-go). |
| **T5. `LocalBackend` semantics tests** (enter → queue/pair, turn order round-robin 5-7-5, line validation/rejections, idempotent resubmit, reveal only after completion, teardown) | `LocalBackend` is a hand-copied reimplementation of server rules. These tests are what stops the mock from silently drifting. | MEDIUM | Assertions should mirror the Go behaviours that already have tests: A-B-A authorship, empty/too-long/banned line rejection, idempotency, post-dissolution state. Cases are pure and fast. |
| **T6. `Syllables` heuristic tests** (table-driven: known words, edge cases, empty input, punctuation, numerals) | Pure deterministic logic, the cheapest and most reliable tests available. Named in the milestone. | LOW | Table-driven word→count and line→count cases. Include the 5/7/5 thresholds the compose UI relies on. Because it is a heuristic, pin current behaviour including known-wrong words as documented "characterization" cases, and do not assert linguistic truth. |
| **T7. `PoemNaming` determinism tests** (same poem → same name; different poems → different names in the typical case; FNV-1a seed and SplitMix64 stability pinned with golden values; empty or whitespace input is safe) | Determinism is the property that makes the keepsake name reproducible. Golden values catch accidental changes to the hash, the word lists, or their order, any of which would silently rename every poem. | LOW | Include 3-5 golden poem→name pairs. Comment that changing word-list order is a deliberate breaking change. |
| **T8. Scripted end-to-end run on the real server with a pass/fail exit code** (start server with Redis, run two participants through match → 3 turns → reveal → dissolve, assert the final state, tear down) | The Go integration tests use `httptest`. This proves the real binary, real config, and real Redis wire path behave the same, and it is the "repeatable e2e" required by the milestone. | MEDIUM | The existing bot is not enough on its own: it needs a counterpart and it has no assertions. Minimum viable shape is a second client (a second `bot` instance, or a small `cmd/e2e` / `-assert` mode) that plays the human side and exits non-zero on any unexpected state. Must run unattended with a timeout so it cannot hang. |
| **T9. E2E asserts the dissolution/anonymity invariant on the live path** (after dissolve, both tokens return the "gone" response and the Redis keyspace is empty or only holds allowed keys) | Zero-keys-after-dissolution is a core product promise. Go unit tests prove it against miniredis. The e2e run proves it against real Redis. | LOW-MEDIUM | Needs a way to inspect keys (`redis-cli DBSIZE`/`KEYS` on the e2e Redis, or a test-only health detail). Use an isolated Redis (own port or DB) so the check is not polluted. |
| **T10. Fix-as-we-go loop with evidence** (any failing check is fixed in this milestone or explicitly logged as a deferred known issue, with a re-run proving green) | Required by the milestone. Findings with no resolution record make the baseline untrustworthy. | VARIES | Process, not code. Each fix gets a regression test where one is feasible. |
| **T11. One-command "verify everything" entry point** (e.g. `./verify.sh` or `make verify`: Go test + vet + build, iOS build + test, e2e) with a summary and a non-zero exit on any failure | A baseline people can't re-run in one step decays after the next change. The milestone's value is that "future milestones verify against this baseline". | LOW (once T1-T9 exist) | Must run from a clean checkout. Can be skipped selectively with flags (e.g. `--no-e2e` when Docker is down). |
| **T12. Recorded baseline evidence** (tool versions, commands, pass counts, date/commit, in `.planning/` or `docs/`) | Required by the milestone's last active item. It turns "tests pass on my machine" into a dated fact against a commit. | LOW | Capture Xcode/Go versions, test counts per suite, and the commit hash. Also record anything intentionally unverified. |

### Differentiators (valuable beyond the baseline; include only if cheap)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **D1. Mock/real parity contract test** (one shared scenario script, e.g. a JSON list of steps and expected states, run against both `LocalBackend` in Swift and the real Go server via the e2e client) | Directly attacks the top codebase risk: a duplicated server in Swift that drifts. Proves the mock is a faithful stand-in, not merely self-consistent. | MEDIUM-HIGH | Cheaper variant: a documented table of behaviours, each referenced by both a Swift test and a Go test with the same name. The full shared-fixture variant is the stronger one. Recommended as the single "stretch" item. |
| **D2. Wire-format (Codable) round-trip tests against real server JSON** (check in sample responses captured from the Go server, decode them in Swift `APIClient`/`Models`) | The iOS `Models.swift` and the Go response structs are independently maintained. A fixture decode test catches field renames and optionality mismatches without a running server. | LOW-MEDIUM | Captures from the e2e run or hand-written from the Go test structs (`enterResp`, `waitingResp`). Delivers most of D1's value at low cost. |
| **D3. `APIClient` tests with a `URLProtocol` stub** (request shape, bearer header, status→error mapping, timeout/offline handling) | Tests the one iOS layer that talks to the real server, with no network. | MEDIUM | Only worthwhile if `APIClient` is injectable with a `URLSessionConfiguration`. Cheap if it already is. If it needs a refactor, defer. |
| **D4. Coverage reporting** (`-enableCodeCoverage YES` + `xcrun xccov`, `go test -cover`) | Shows where the baseline is thin. Useful as information, not as a gate. | LOW | Report only. Do not set thresholds this milestone. |
| **D5. Go race-detector run in the verify script** (`go test -race ./...`) | The matchmaking race is a real risk area. One extra flag. | LOW | Needs cgo/toolchain support. Make it non-fatal if unavailable. |
| **D6. Backend-level Go e2e as a `go test` (build tag `e2e`)** rather than only a shell script | Gives Go-native, debuggable e2e with real assertions and no shell parsing. | MEDIUM | Alternative to extending `bot`. Could use miniredis, which removes the Docker dependency, but then it proves less about real Redis. Pick one primary e2e path in the roadmap. |
| **D7. Flake guard** (run the iOS suite N times once to confirm no timing-dependent failures) | Polling-driven state tests are the likely flake source. A one-off 5x run is cheap insurance for a "trusted" baseline. | LOW | One-time validation, not a permanent feature. |
| **D8. Test-helper layer** (scripted `Backend` fake with call recording, `AppModel` factory, fixture builders) | Keeps T4 and T5 readable and makes future milestones (push, safety) cheap to test. | LOW-MEDIUM | Build it as part of T4, not as separate work. |
| **D9. Persistent-state hygiene test** (assert `Keychain`/`UserDefaults` hold only the token and settings, and are cleared on dissolution) | Backs the anonymity constraint on the client side. The server side is already covered. | MEDIUM | `Keychain.swift` touches real Keychain APIs, so it may need a test seam. Include only if a seam already exists. |

### Anti-Features (deliberately NOT built this milestone)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **XCUITest / UI automation suite** (tapping through the screens) | "Real e2e on the simulator" feels like the true proof. | Slow, flaky, simulator-dependent, and needs accessibility identifiers added across the views. The milestone's value is repeatable logic proof, and the UI is a thin layer over `AppModel`. | Test `AppModel` state transitions (T4) and the server arc via the e2e client (T8). Add UI automation in a later milestone only if the views grow real logic. |
| **Snapshot / visual regression tests** (themes, pixel scenes, dissolutions) | There are three themes and time-of-day palettes. | Needs a snapshot library (violates the no-third-party-iOS-deps convention) or hand-rolled image diffing. Pixel and animation output is brittle across OS and simulator versions. Visual quality is also subjective, and the manual feel pass is explicitly out of scope. | None. Compile coverage (T1) is enough for the Design layer. |
| **CI pipeline** (GitHub Actions running tests, test gate before Fly deploy) | The Go deploy workflow has no test step, which is a real gap. | Explicitly out of scope in PROJECT.md. The baseline must first run locally. macOS runners and simulator caching are their own project. | Make T11 a single script so wiring CI later is a one-liner. Record "add CI" as the follow-on milestone. |
| **Device farm / multi-OS-version matrix** | Broader compatibility confidence. | The app is iOS 17+, pre-TestFlight, with no known device-specific logic. Cost far exceeds the value. | One pinned simulator destination. |
| **Prod / Fly.io verification and load/soak tests** | The backend is live. | Out of scope by decision (local/automated only). Load tests also risk tripping rate limiting and production state. | Existing metrics and rate limiting. Revisit at the TestFlight milestone. |
| **Coverage thresholds / gates** | "Make sure it stays tested." | Arbitrary numbers produce gaming and noise at baseline time, and the UI layer will drag the total down. | Report coverage (D4) without enforcing. |
| **Third-party test libs** (Quick/Nimble, ViewInspector, SnapshotTesting, Mockolo/Cuebiq-style mock generators) | Nicer syntax and generated mocks. | Breaks the no-third-party-iOS-dependency convention and adds SPM resolution to a headless run. | XCTest (or Swift Testing, if Xcode 16.4 and the existing conventions allow) with hand-written fakes. |
| **Push, safety/report-UI, App Attest, TestFlight verification** | Adjacent in the roadmap. | Blocked on the Apple Developer account or deferred to later milestones. | Keep the entitlements file building; do not test attestation. |
| **Rewriting or expanding Go tests for already-covered ground** | The Go packages `store`/`matchmaker` have no own test files. | The gateway integration tests already cover them indirectly, and the Go suite is described as well tested. Re-covering it dilutes the milestone. | Add Go tests only if a fix-as-we-go bug is found there. |
| **Fuzz / property-based testing of `Syllables` or `PoemNaming`** | Edge-case discovery. | Disproportionate for a heuristic with a known-imperfect spec. Golden and table tests give the signal. | Table-driven characterization cases (T6, T7). |
| **Refactoring app code for testability beyond the minimum seams** | Cleaner tests. | Scope creep in an existing, working app. | Only add the smallest seams (injectable clock/interval, backend protocol use), justified by a specific test. |

## Feature Dependencies

```
T1 clean tree + existing checks green
    └──required by──> everything (don't build on a broken base)

T2 test target in project.yml
    └──requires──> T1 (iOS build must work)
    └──required by──> T3, T4, T5, T6, T7, D2, D3, D9

T3 headless xcodebuild test
    └──requires──> T2
    └──required by──> T11, T12

T8 scripted e2e (server + two participants, assertions)
    └──requires──> T1 (server builds, Redis available)
    └──required by──> T9, T11, D1(real-server half), D2(fixture capture)

T9 anonymity assert on live path
    └──requires──> T8

T4 AppModel tests
    └──requires──> T2
    └──enhanced by──> D8 helper layer (built together)
    └──depends on──> LocalBackend behaving correctly (so T5 should land first or alongside)

T5 LocalBackend tests
    └──requires──> T2

T6 Syllables tests, T7 PoemNaming tests
    └──require──> T2 only (independent; ideal first iOS tests to prove the pipeline)

D1 parity contract
    └──requires──> T5 and T8
D2 wire-format fixtures
    └──requires──> T2; cheapest if fixtures are captured via T8

T10 fix-as-we-go
    └──runs alongside──> all of the above (failures from T4/T5/T8 feed it)

T11 verify entry point
    └──requires──> T3 and T8 (and T1's commands)

T12 baseline evidence
    └──requires──> T11 (final step, after all fixes)

Conflicts:
D6 (Go e2e with miniredis) ──overlaps──> T8 (shell+real Redis): pick ONE primary e2e path
UI/snapshot suites ──conflict with──> the automated-only, no-third-party constraints
```

### Dependency Notes

- **T2 gates all iOS tests.** Land it first with one trivial test (T6 or T7) to prove the whole chain: XcodeGen, build, simulator boot, `xcodebuild test`, exit code. Debugging the harness is the largest unknown (signing, simulator, `TEST_HOST`), so it should not be mixed with testing `AppModel`.
- **T5 before T4.** `AppModel` tests that run against `LocalBackend` inherit its bugs. Establish that the mock is right first, or use a scripted fake for the `AppModel` tests so they are independent.
- **T8 is independent of the iOS track.** It can run in parallel with T2 through T7, which suits wave-based execution.
- **T11 and T12 close the milestone.** They depend on everything else being green.
- **D1 and D2 are the best use of spare capacity.** They share fixtures with T8, and they address the mock-drift risk that makes `LocalBackend` a liability.

## MVP Definition

### Launch With (this milestone)

- [ ] T1 reconciled tree and existing checks green. This is the gate.
- [ ] T2 + T3 test target and headless run, proved with T6/T7 first (cheapest, pure).
- [ ] T6, T7 `Syllables` and `PoemNaming` tests (golden and table).
- [ ] T5 `LocalBackend` semantics tests.
- [ ] T4 `AppModel` state-machine tests (with injectable timing, with minimal seam changes).
- [ ] T8 + T9 scripted real-server e2e with assertions and an anonymity check.
- [ ] T10 fixes, each with a regression test where feasible.
- [ ] T11 + T12 single verify command and recorded evidence.

### Add If Cheap (same milestone, stretch)

- [ ] D2 wire-format fixture decode tests (low cost, high drift-catching value).
- [ ] D1 parity contract, at least the lightweight form (same-named scenarios in both suites).
- [ ] D4 coverage report and D5 `-race` run, which are each one flag.
- [ ] D7 one-off flake check on the iOS suite.

### Future Consideration (later milestones)

- [ ] CI pipeline (test gate before Fly deploy). This is the biggest hole the codebase map flags, and it is deliberately deferred.
- [ ] D3 `APIClient` URLProtocol tests, if it needs a refactor now.
- [ ] D9 client persistence hygiene tests, which pair naturally with the safety-rails milestone.
- [ ] UI automation, once the push and safety flows add real view logic.
- [ ] Prod smoke checks, at the TestFlight milestone.

## Feature Prioritization Matrix

| Feature | Value | Cost | Priority |
|---------|-------|------|----------|
| T1 clean tree + existing checks | HIGH | LOW | P1 |
| T2 test target in project.yml | HIGH | MEDIUM | P1 |
| T3 headless CLI test run | HIGH | LOW-MEDIUM | P1 |
| T6 Syllables tests | MEDIUM | LOW | P1 |
| T7 PoemNaming tests | MEDIUM | LOW | P1 |
| T5 LocalBackend tests | HIGH | MEDIUM | P1 |
| T4 AppModel tests | HIGH | MEDIUM-HIGH | P1 |
| T8 scripted real-server e2e | HIGH | MEDIUM | P1 |
| T9 live anonymity assertion | HIGH | LOW-MEDIUM | P1 |
| T10 fix-as-we-go | HIGH | VARIES | P1 |
| T11 verify entry point | HIGH | LOW | P1 |
| T12 baseline evidence | MEDIUM | LOW | P1 |
| D2 wire-format fixtures | MEDIUM-HIGH | LOW-MEDIUM | P2 |
| D1 parity contract | HIGH | MEDIUM-HIGH | P2 |
| D4 coverage report | LOW-MEDIUM | LOW | P2 |
| D5 race run | MEDIUM | LOW | P2 |
| D7 flake check | MEDIUM | LOW | P2 |
| D8 test helper layer | MEDIUM | LOW-MEDIUM | P2 (built with T4) |
| D3 APIClient stub tests | MEDIUM | MEDIUM | P3 |
| D6 Go e2e build tag | LOW-MEDIUM | MEDIUM | P3 (alternative to T8) |
| D9 persistence hygiene | MEDIUM | MEDIUM | P3 |

**Priority key:** P1 = must have for a credible baseline. P2 = add if cheap. P3 = defer.

## Comparable Efforts (what mature baselines typically include)

| Capability | Typical practice for mobile client-server apps | Our approach |
|------------|-----------------------------------------------|--------------|
| Client logic unit tests | View-model/state-machine tests against a fake backend. The test pyramid's wide base. | T4-T7, with `LocalBackend` doubling as the fake. |
| Server tests | Handler and integration tests with in-memory dependencies. | Already done (miniredis). No new work. |
| API contract | Shared schema or recorded fixtures (OpenAPI, Pact, recorded JSON). | D2 fixtures, D1 shared scenarios. No Pact or OpenAPI tooling, which is overkill for one team and one client. |
| E2E | A thin number of full-stack scenarios against a real server, often via a headless client. UI E2E is kept minimal because it is flaky. | T8/T9, using a headless Go client instead of UI automation. |
| UI tests | A few XCUITest smoke flows. | Deliberately excluded (anti-feature). |
| CI | Runs unit and e2e on every PR. | Deferred. T11 makes it trivial later. |
| Coverage | Reported, with sometimes a soft threshold. | Reported only (D4). |

## Sources

- `/Users/charris/src/strangewords/.planning/PROJECT.md` for milestone scope, constraints, and out-of-scope decisions (HIGH).
- `/Users/charris/src/strangewords/.planning/codebase/TESTING.md` for existing test inventory, Go patterns, and the CI gap (HIGH).
- Local inspection: `ios/project.yml` (single app target, run-action-only env vars, entitlements), `server/cmd/bot/main.go` (log-only, loops forever, `-once`, no assertions), `run_test_server_and_robot_poet_friend.sh` (Docker Redis), Xcode 16.4 with iOS 18.6 simulators (HIGH).
- General mobile test-pyramid and contract-testing practice, plus XcodeGen/`xcodebuild test` mechanics, from established knowledge. No external web sources were fetched for this file (MEDIUM). Verify test-target syntax against the XcodeGen docs during phase planning.
