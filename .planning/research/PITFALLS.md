# Domain Pitfalls

**Domain:** Retrofitting automated tests onto an existing XcodeGen SwiftUI (iOS 17+) + Go/Redis app ("Stranger Words")
**Researched:** 2026-10-08
**Method:** Read the codebase (AppModel, LocalBackend, TokenStore, APIClient, PoemNaming, Syllables, bot, run/live scripts, project.yml) and ran a throwaway spike in the scratchpad. The spike added a `bundle.unit-test` target to a copy of `project.yml` and ran `xcodebuild test` on Xcode 16.4 against the iPhone 16 / iOS 18.6 simulator. Items tagged **[SPIKE]** were reproduced there (HIGH confidence). Items tagged **[CODE]** come from reading this repo's code (HIGH for what the code does, MEDIUM for how it will behave under test). Items tagged **[GENERAL]** are well-known XCTest/Xcode behavior from training knowledge and were not re-verified against current docs (MEDIUM).

Phase names below are suggestions for mapping, not a committed roadmap:
- **P1** Reconcile working tree, then wire the test target
- **P2** Testability seams (small, behavior-preserving refactors)
- **P3** iOS unit suites (AppModel, LocalBackend, Naming, Syllables, Models)
- **P4** Headless runner script
- **P5** Scripted e2e (Go side, robot poet)
- **P6** Fix-as-we-go and baseline capture

---

## Critical Pitfalls

Mistakes that cause rewrites, silent false-greens, or a baseline nobody can trust.

### Pitfall 1: The explicit scheme has no test action, so `xcodebuild test` refuses to run
**What goes wrong:** `project.yml` declares an explicit `schemes: Strangewords:` block with only `build` and `run`. Adding a `StrangewordsTests` target alone changes nothing for the scheme. **[SPIKE]** `xcodebuild ... -scheme Strangewords test` failed immediately with `Scheme Strangewords is not currently configured for the test action.`
**Why it happens:** XcodeGen only auto-generates schemes for targets that have no explicit scheme. An explicit scheme is used verbatim.
**Consequences:** A target that compiles in Xcode's UI but cannot run headlessly, which is the stated requirement. People then "fix" it by hand in Xcode, which is lost on the next `xcodegen generate` because `.xcodeproj` is gitignored.
**Prevention:** Add `test: { config: Debug, targets: [StrangewordsTests] }` to the scheme in `project.yml`. Also set the test environment variables there (see Pitfall 6). Never hand-edit the generated project.
**Detection:** The error above; or tests visible in Xcode that do not appear in CLI output.
**Phase:** P1.

### Pitfall 2: Hosted tests run inside the real app, in the developer's real app container
**What goes wrong:** A `bundle.unit-test` target with `@testable import Strangewords` is app-hosted. **[SPIKE]** `UIApplication.shared.connectedScenes.count == 1` and `windows.count == 1` during a test, so the full `StrangewordsApp` launches. That means `RootView` with its Canvas scenes and animations renders, and `.task { model.resume() }` runs concurrently with every test. The host uses bundle id `com.strangerwords.us`, so on a given simulator it shares its UserDefaults domain with the app you run via `run.sh` / `live_test.sh`.
**Why it happens:** `@testable import` of an app target requires an app host (or restructuring into a framework, which is out of scope).
**Consequences:**
- A `TokenStore.token` left over from a manual `./run.sh --solo` session makes the host's `resume()` call the real `APIClient.shared`. The default base URL is `https://api.strangerwords.us`, so **tests can hit production**.
- Tests that write `TokenStore.token/sessionId` leave a "ghost session" in the simulator that the next manual `run.sh --solo` run resumes into.
- Test-written tokens persisting is also a (small) violation of the project's anonymity constraint.
- Canvas and animation CPU load in the host adds timing jitter to every wait-based assertion.
**Prevention:**
1. Short-circuit the app under test: in `StrangewordsApp`, if `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`, render an empty view and skip `resume()`. This is a few lines and removes both the UI load and the stray network call.
2. In the scheme's `test.environmentVariables`, set `SW_API_BASE` to a dead local address (for example `http://127.0.0.1:9`) so an accidental `APIClient` use fails fast rather than reaching prod.
3. Run tests on a dedicated simulator (a clone such as "SW-Test") so manual dev state and test state never share a container.
4. Never call `TokenStore.clear()` in test teardown as the only isolation, because that wipes the developer's real token (see Pitfall 5).
**Detection:** Network traffic to `api.strangerwords.us` during a test run; a manual run that resumes mid-poem; tests that pass alone and fail after a manual session.
**Phase:** P1 (host short-circuit, env vars), P4 (dedicated simulator).

### Pitfall 3: Wait-based assertions on `AppModel` (unstructured Tasks plus a hard-coded 3 s poll)
**What goes wrong:** `begin()`, `submit()`, and `resume()` fire unstructured `Task { }` blocks with no handle. `pollInterval` is `private let ... = .seconds(3)`. `LocalBackend.enter` sleeps 600 ms, and the stranger's think time is 1.6 s measured with `Date()`. **[SPIKE]** `begin()` to `.composing` took 0.62 s; the stranger's line only arrives on the next 3 s poll tick. A full arc is therefore 5 to 8 seconds of real time, and any test that sleeps a fixed amount is either slow or flaky.
**Why it happens:** The app was built for a human watching a simulator, so every delay is a real, private constant.
**Consequences:** Tests with `Task.sleep` or `Task.yield()` guesses pass locally and flake under load (the hosted app also eats CPU). Alternatively the suite is so slow nobody runs it. Asserting on intermediate phases like `.connecting` is a race.
**Prevention:**
- Add a defaulted init parameter (`pollInterval: Duration = .seconds(3)`) to `AppModel` and a defaulted `strangerThinkTime` / `enterDelay` to `LocalBackend`. Behavior is unchanged for the app; tests pass milliseconds. This is the single highest-leverage refactor (P2).
- Do not use a third-party clock library (the project forbids third-party iOS deps). If you want a clock seam, hand-roll a tiny protocol, but defaulted durations are usually enough.
- Write one async helper, `await waitUntil(timeout: 5) { model.phase == ... }`, that polls on the main actor and fails with the current phase in the message. Assert only on settled states.
- For ordering and race tests, use a gated fake backend (Pitfall 4) so responses are released by the test, not by wall-clock time.
- A `Task` the test cannot reach: either keep a small internal `@testable`-visible handle or rely on `waitUntil`. Do not add production-only test hooks beyond that.
**Detection:** Suite runtime over about 30 s for a handful of tests; failures that disappear on re-run; `sleep(` appearing in test code.
**Phase:** P2 (seams), P3 (helper and tests).

### Pitfall 4: Test doubles that fight actors, `Sendable`, and `@MainActor`
**What goes wrong:** `Backend` is `Sendable` and is implemented by actors (`LocalBackend`, `APIClient`). `AppModel` is `@MainActor`. Typical mistakes:
- A `final class FakeBackend` with mutable arrays: a data race, a Sendable warning today (project is `SWIFT_VERSION 5.0`), and a hard error if the project ever moves to Swift 6.
- Using `XCTestExpectation` + synchronous `wait(for:)` inside a `@MainActor` async test: this blocks the main thread, so the `Task`s that need the main actor never run and the test times out. Use `await fulfillment(of:timeout:)`. **[GENERAL]**
- `XCTAssertEqual(await fake.calls, ...)` does not compile because XCTest autoclosures are not async. Hoist into a `let` first. **[GENERAL]**
- Reading the fake's recorded calls synchronously from the test: actor state needs `await`.
- Actor reentrancy: `LocalBackend.enter` resets state, then suspends in `Task.sleep`, then returns `view()`. Two overlapping `enter()` calls interleave around that suspension. A gated fake that suspends inside an actor method on a continuation has the same property. That is intended for race tests but surprising if you did not expect it.
**Prevention:**
- Write fakes as `actor FakeBackend: Backend` with a scripted response queue, a recorded `calls` array exposed through an async accessor, and optional continuation "gates" so a test controls exactly when `getSession` / `submitLine` return.
- Mark test classes `@MainActor` and use `async` test methods; use `await fulfillment(of:)`.
- Include a fake that ignores cancellation (see Pitfall 8), since it is the realistic worst case.
**Detection:** Compiler Sendable/isolation warnings in the test target; tests that time out only when the main thread is blocked.
**Phase:** P3.

### Pitfall 5: `TokenStore` writes to process-global `UserDefaults.standard`
**What goes wrong:** `TokenStore` is a static enum over `UserDefaults.standard`. Every `AppModel` in every test shares it. `AppModel.init(backend:)` with an injected backend does **not** clear it (only the `SW_LOCAL_MOCK` branch does), `apply()` writes `sessionId`, `begin()` writes `token`, and `poll*` loops silently `return` if `TokenStore.token` is nil.
**Consequences:**
- Order-dependent tests: test A leaves a token, test B's `resume()` takes the resume path.
- A fake backend that returns `participantToken: nil` makes `submit()` a silent no-op (`guard ... let token = TokenStore.token else { return }`) and the poll loop exit without a trace, so the test just times out with no diagnostic.
- Cleaning up with `TokenStore.clear()` deletes the real developer token on a shared simulator (Pitfall 2).
- Swift Testing (`import Testing`) runs tests in parallel by default, which would turn the shared static into a data race. Stay on XCTest, or mark suites `.serialized`.
**Prevention:**
- Make the backing store injectable: `static var defaults: UserDefaults = .standard`. In `setUp`, assign `UserDefaults(suiteName: "sw.tests.\(UUID())")!`; in `tearDown`, call `removePersistentDomain(forName:)` and restore `.standard`. This isolates tests and leaves no identity behind.
- Do not use your own bundle id as the suite name (it does not behave as a separate domain).
- Do not test `TokenStore` against the Keychain. The unsigned simulator build (`CODE_SIGNING_ALLOWED=NO`) cannot use it; that is exactly why the project chose UserDefaults.
- Use XCTest, keep parallel testing off in the scheme, and have every fake return a non-nil token unless the test is specifically about the nil case.
- Add an assertion in one test that after `dissolve`/`reset`/`leave`, `token` and `sessionId` are both nil, since that is the anonymity invariant on the client.
**Detection:** Tests pass individually and fail as a class; "resumed into ghost session" on manual runs.
**Phase:** P2 (injectable store), P3 (use it everywhere).

### Pitfall 6: "Guarding drift" by testing `LocalBackend` against itself
**What goes wrong:** PROJECT.md says tests of `LocalBackend` "guard the mock/real drift risk." They do not. A test that asserts `LocalBackend` returns what `LocalBackend` returns proves the mock is stable, not that it matches the Go server. **[CODE]** Known divergences already exist: `submitLine` with the wrong turn silently returns the current view instead of throwing 409; there is no content rejection (422), no idempotency, no `gone` (410), no `session_gone`; `waiting` always reports matched; `dismiss` / `leave` are no-ops; it is single-session with fixed `sessionId = "local-poem"`.
The robot-poet e2e does not close the gap either: `cmd/bot` decodes responses into the server's own `sessions.View` type (`import "strangewords/internal/sessions"`), so a renamed JSON tag changes both ends together and still passes, while `Models.swift` silently breaks.
**Consequences:** A green baseline that says nothing about whether the iOS client can decode what the server sends. This is the most likely real-world break.
**Prevention:**
- Add a **wire-contract fixture** step: a Go test (or the e2e harness) writes real server JSON for enter-matched, enter-waiting, waiting, session active/complete, 409 not-your-turn, 410, and 422 bodies to a committed `fixtures/` directory (or the Swift tests read them from the repo path). Swift tests decode them with `SessionView`, `EnterResponse`, `WaitingResponse`, `ServerError`, and run `APIClient.mapError` against the status codes and bodies. The Go side regenerates and diffs the fixtures, so drift fails a test on whichever side moved.
- Test `APIClient` with a `URLProtocol` stub on an ephemeral session (needs a small seam: inject `URLSessionConfiguration`) rather than only through the actor.
- In the `LocalBackend` tests, say explicitly which behaviors are pinned for the mock's own sake and keep a short "known divergence from server" list in the test file or the TESTING doc, so nobody reads it as a contract.
**Detection:** All iOS tests green, yet `./live_test.sh` shows the app failing to decode after a server change.
**Phase:** P2 (URLSession seam), P3 (fixtures and decoding tests), P5 (fixture generation in the Go harness).

### Pitfall 7: The "scripted e2e" is not scripted, headless, or able to fail
**What goes wrong:** The existing tooling is built for a human at a simulator, and **[CODE]**:
- `cmd/bot` plays one side and needs a partner. Two `-once` bots can pair with each other, but the bot exits **0 even on failure**: errors are printed as "hiccup" and, with `-once`, the program returns normally. A test that only checks the exit code is a false green. It also prints emoji prose with random lines and random 1.5 to 3.3 s pauses, so output cannot be string-matched reliably.
- `live_test.sh` launches the simulator through `run.sh`, streams logs, and waits for Ctrl-C. It cannot run unattended.
- Both scripts hard-code `:8080`, kill whatever listens there (`lsof -ti tcp:8080 | xargs kill`), `pkill -f /tmp/sw-server`, write fixed `/tmp` paths, and run **`FLUSHALL` against the Redis on 6379**. In a test harness that destroys a developer's local server and data, and two concurrent runs collide.
- Redis comes from Docker (`docker compose`). `redis-server` is not installed locally, so a stopped Docker daemon fails the e2e in a confusing way.
- Readiness is a `curl /healthz` loop, but a stale process on the port can answer it (the script guards this only partially).
- macOS has no `timeout` command, so a hung bot hangs the script forever.
- A zero-keys-after-dissolution check will **fail today**: CONCERNS.md documents that `DeleteSession` never removes the `WaitEntry`, which keeps token and push token for up to 15 minutes. That is a real bug the e2e will find, and it must be triaged (Pitfall 10), not "worked around" by weakening the assertion.
**Prevention:**
- Prefer an in-process Go e2e: start the real server on an ephemeral port (`:0`) over miniredis, run two bot clients in goroutines, and assert on the final session views, a Redis key scan, and `/metrics` counters. It needs no Docker, no fixed port, and no FLUSHALL, and it reuses the `newRig` pattern already in `gateway_test.go`. If the real binary must be exercised, use a random free port, a dedicated Redis (own port or DB), and unique temp paths created with `mktemp -d`.
- Refactor the bot's play loop into a function that returns an error and the final poem, and have the e2e assert on those values instead of parsing text. Add a nonzero exit code to `cmd/bot` on failure.
- Give every wait a deadline (context timeout in Go; a background-and-kill wrapper in bash, since `timeout` is missing on macOS unless coreutils is installed). A hang must fail the run, not stall it.
- Assert the full arc: match, turns in order (A, B, A), completion with 3 lines, both dismiss/leave, session and token keys gone, and a second poll returning 410. For the keys check, scan with `SCAN sw:*` after dissolution.
- Run it with `-race` once, since the CONCERNS read-modify-write race (`touchPresence` vs `handleLine`) is only visible under concurrency.
- Keep rate limiting off in the e2e via `SW_RATE_RPS=0`, as the existing test convention says, or two polling bots will get 429s that look like flakes.
**Detection:** The e2e passes with the server's Redis stopped; passes when the bot logs "hiccup"; a developer's `make run` dies after running the tests.
**Phase:** P5.

---

## Moderate Pitfalls

### Pitfall 8: Late responses resurrect state after dissolution (the fake must be able to expose this)
**What goes wrong:** **[CODE]** `pollSession` / `pollWaiting` do `let s = try await api.getSession(...)` and then call `apply(s)` / `dissolve(...)` without re-checking `Task.isCancelled`. A response that lands after `stopPolling()` (from `leave()`, `reset()`, or a transition) still runs `apply`, which calls `TokenStore.sessionId = s.sessionId`. After `dissolve()` cleared the token, this can write the session id back and flip the UI to `.composing` / `.reveal`. Real `URLSession` calls usually throw on cancellation, which hides the bug; `LocalBackend` and ordinary fakes do not throw, so tests expose it while manual testing never does. Related: `begin()` has no double-tap guard and keeps no handle, so `reset()` during `.connecting` cannot cancel the in-flight `enter()`.
**Prevention:** Include a test with a gated fake: start polling, call `leave()`, then release the gated `getSession` response, and assert `phase == .dissolved(.ended)` and `TokenStore.sessionId == nil`. Expect it to fail, then fix with `guard !Task.isCancelled` after each `await` (or a generation counter). This is a legitimate fix-as-we-go item and also protects the anonymity invariant.
**Phase:** P3 (find), P6 (fix and record).

### Pitfall 9: Golden-value tests on `PoemNaming` that break on a toolchain update
**What goes wrong:** The seed derivation (FNV-1a) and `SeededGenerator` (SplitMix64) are code this project owns, so their outputs are stable. But `coin(from:)` also calls `shuffle(using:)` and `randomElement(using:)`, whose algorithms are stdlib implementation details and not guaranteed stable across Swift releases. A golden "this poem coins 'Silent Pond Porter'" test can fail after an Xcode update with no code change. **[CODE]/[GENERAL]**
**Prevention:**
- Pin hard goldens only on code you own: `fnv1a("...")` known vectors, and the first N outputs of `SeededGenerator` for a fixed seed.
- For `coin(from:)`, assert properties: same lines give the same result across repeated calls; case-insensitive input gives the same result (it lowercases); different poems usually give different names; empty or all-stopword poems return `nil`; the result never contains an empty name. Keep at most one or two full-string goldens, clearly labelled as toolchain-sensitive.
- The word-pool order depends on first appearance only (no `Set` iteration order is used for output), so the determinism claim is sound; add a test that runs `coin` many times in one process to catch accidental `Hasher` use.
**Phase:** P3.

### Pitfall 10: Characterization tests that enshrine known bugs, and unbounded fix-as-we-go
**What goes wrong:** The suite will touch behavior CONCERNS.md already calls buggy (wait record not erased on dissolution; `handleDismiss` resets TTL to 120 s regardless of status; abandoned waiters pair with active users; session read-modify-write race; swallowed transient errors). If tests are written to match what the code does today, bugs become "expected." If every discovery is fixed immediately, the milestone has no end and the baseline is a moving target.
**Prevention:**
- Triage rule up front: (a) cheap, local, clearly wrong: fix and add the regression test in the same commit; (b) needs design (turn timeouts, abandoned-waiter policy, App Attest, metrics exposure): record in the baseline as a known failing/expected-failure test and defer to its own milestone.
- Use `XCTExpectFailure` (iOS) or `t.Skip("known: <CONCERNS item>")` (Go) so the suite is green but the gap is visible and flips loudly when fixed.
- The baseline document must list these explicitly, otherwise "verified" silently overclaims.
**Phase:** P3, P5, P6.

### Pitfall 11: Test target configuration details in XcodeGen
**What goes wrong:**
- **[SPIKE]** With `CODE_SIGNING_ALLOWED=NO` the bare target built and ran. With signing allowed (`CODE_SIGN_IDENTITY=-`), the build failed: `Cannot code sign because the target does not have an Info.plist file`. Set `GENERATE_INFOPLIST_FILE: YES` on the test target so it works both ways. If you instead use `info:` with a path, that generated plist must also be added to `.gitignore` (the app's `Strangewords/Info.plist` already is).
- The project-level `DEVELOPMENT_TEAM` and `CODE_SIGN_STYLE: Automatic` are inherited by the test target. On a machine without that team's certificates, a signed test run fails. `run.sh` already works around this with `CODE_SIGNING_ALLOWED=NO`; the test runner must pass the same flag. A side effect: entitlements (App Attest) are not applied in these runs, so nothing here verifies them.
- **[SPIKE]** The built app contains `PlugIns/StrangewordsTests.xctest` after a test build. If tests share `-derivedDataPath ios/build` with `run.sh`, you install a test-bundle-bearing app and get stale incremental state. Use a separate derived data path for tests.
- `-destination 'platform=iOS Simulator,name=iPhone 16'` is ambiguous when several OS runtimes are installed (only 18.6 here today). Pin `OS=` or use the UDID.
- Uncommitted edits are sitting in `ios/project.yml`, and `Strangewords.entitlements` is untracked while `CODE_SIGN_ENTITLEMENTS` references it. Adding the test target on top of an unreconciled file mixes unrelated changes into the test-wiring commit and breaks fresh clones.
**Prevention:** Reconcile and commit the working tree first, as its own commit. Verify with a clean clone: `xcodegen generate`, then build and test. Keep the test target's settings minimal: `GENERATE_INFOPLIST_FILE: YES`, a dependency on the app target, and no `TEST_HOST` overrides unless needed.
**Phase:** P1.

### Pitfall 12: Snapshot-testing the Canvas-heavy themes and scenes
**What goes wrong:** Themes and scenes are Canvas/TimelineView animations driven by `Date()` (several `start = Date()` in `onAppear`) and time-of-day. Pixel snapshots depend on the Xcode version, simulator runtime, GPU, animation phase, and local time zone. The standard snapshot library is third-party, which the project forbids. `TimeOfDay.now` also reads `SW_FORCE_TOD` and `Calendar.current`, so a test that passes at 3 pm fails at 3 am, or on a CI machine in another time zone.
**Prevention:** Do not snapshot Canvas output. Test what is pure: `TimeOfDay.now(date, calendar:)` with an explicit `Calendar` that has a fixed `TimeZone` (and `SW_FORCE_TOD` unset), the hex-color helper, and the phase-to-view mapping. At most add one smoke test that renders a view with `ImageRenderer` and asserts it produces a non-empty image without crashing. State this scope in the baseline so "UI verified" is not overclaimed.
**Phase:** P3.

### Pitfall 13: The `dissolving` to `dissolved` leg is driven by a SwiftUI animation callback
**What goes wrong:** `release()` sets `.dissolving`; only the view's effect completion calls `finishDissolving()`. In unit tests the callback never fires, so a test that waits for `.dissolved` hangs, and a test that calls `finishDissolving()` directly proves the model but not the wiring.
**Prevention:** Unit-test the two halves separately (`release()` sets `.dissolving` and calls `dismiss` on the fake; `finishDissolving()` coins the keepsake and ends in `.dissolved(.completedAndGone)` with token and session cleared). Record the view-driven wiring as an explicit gap in the baseline (manual UAT is deferred per PROJECT.md). Because `release()` fires `Task { await api.dismiss }`, assert the dismiss call with `waitUntil` on the fake's recorded calls, not immediately.
**Phase:** P3.

### Pitfall 14: Simulator flakiness in headless runs
**What goes wrong:** **[SPIKE]** The very first `xcodebuild test` on a shut-down simulator failed with `Early unexpected exit, operation never finished bootstrapping ... Test crashed with signal kill before starting test execution`; the identical re-run passed. This is a cold-boot flake, not a test failure. Other observed or common issues: `run.sh` and `live_test.sh` call `open -a Simulator` and shut down other booted devices, which will kill a running test simulator; concurrent `xcodebuild` and `simctl` use of the same device; `-resultBundlePath` fails if the path already exists **[GENERAL]**; xcodebuild can print `** TEST SUCCEEDED **` for an empty or misconfigured run if nobody checks the executed count.
**Prevention:**
- Runner script order: boot the target explicitly (`xcrun simctl boot <udid>` then `xcrun simctl bootstatus <udid> -b`), then `xcodebuild test`, with one automatic retry for the specific bootstrap-crash signature only. Do not enable blanket `-retry-tests-on-failure`, which masks real flakes.
- Build once, then `test-without-building` for repeated or retried runs.
- `rm -rf` the result bundle path before each run, and parse the output for `Executed N tests` with N above a floor so a green run with zero tests fails the script.
- Never run the unit-test script concurrently with `run.sh` / `live_test.sh` on the same device; use the dedicated test simulator (Pitfall 2).
- Do not pipe into tools that are not installed (`xcpretty` and `xcbeautify` are absent here); `set -o pipefail` so a failing `xcodebuild | grep` still fails the script.
**Detection:** A failure with no assertion message that vanishes on re-run; "test passed" with 0 executed.
**Phase:** P4.

---

## Minor Pitfalls

### Pitfall 15: `Syllables` golden tests of a heuristic
**What goes wrong:** The counter is a vowel-cluster heuristic documented as "guidance only." Asserting linguistically correct counts for hard words ("fire", "poem", "queue") fails, and "fixing" the heuristic to pass expands scope.
**Prevention:** Pin the existing documented behavior (cluster counting, trailing silent "e" drop, floor of 1, empty and punctuation-only input returns 0, case-insensitivity, multi-word sums) and the bundled `LocalBackend` / bot lines (the 5-7-5 curated lines should count to their targets, which doubles as a data sanity test). Label hard-word cases as characterization.
**Phase:** P3.

### Pitfall 16: Haptics and `Date()` calls inside the model
**What goes wrong:** `Haptics.*` (UIKit feedback generators) run inside `begin()`, `submit()`, `apply()`. They are harmless no-ops on the simulator but are untestable and create a hidden dependency. `LocalBackend.getSession` uses the wall clock for the stranger's pacing.
**Prevention:** Leave haptics alone (not worth a seam). Handle pacing through the defaulted `strangerThinkTime` (Pitfall 3). Do not assert on haptic calls.
**Phase:** P2/P3.

### Pitfall 17: Coverage chasing and Go-side redundancy
**What goes wrong:** Spending the milestone on coverage numbers for views, or re-testing Go behavior that `gateway_test.go` already covers, while the real gaps stay open: iOS state machine, wire-contract decoding, concurrent `POST /line` vs polling, and `store`/`matchmaker` direct tests (CONCERNS lists these as high priority).
**Prevention:** Prioritize by risk: contract fixtures, `AppModel` transitions (including 410/409/422 branches), the late-response race, the wait-record leak, then the concurrent-write race. Do not set a coverage threshold for this milestone.
**Phase:** P3/P5.

### Pitfall 18: Go-toolchain and path drift in scripted runs
**What goes wrong:** `go.mod` says `go 1.25.0` while the Dockerfile builds on `golang:1.26`; scripts build to fixed `/tmp/sw-server` and `/tmp/sw-bot`, which can be stale binaries from an earlier build if a build step is skipped.
**Prevention:** Always build to a fresh `mktemp -d` directory in the e2e, and print `go version` into the evidence log so the baseline records the toolchain used.
**Phase:** P5/P6.

---

## Phase-Specific Warnings

| Phase | Likely Pitfall | Mitigation |
|-------|----------------|------------|
| P1 Reconcile tree, wire target | Dirty `project.yml` and untracked entitlements (11); no test action in scheme (1); hosted-app side effects (2) | Commit reconciled tree first; add `test:` to scheme; `GENERATE_INFOPLIST_FILE: YES`; XCTest-aware app body; dead `SW_API_BASE` in test env |
| P2 Testability seams | Over-refactoring production code; skipping the seams and writing sleeps (3) | Only defaulted init parameters (`pollInterval`, `strangerThinkTime`, injectable `UserDefaults`, `URLSessionConfiguration`); app behavior unchanged; verify with `./run.sh` once |
| P3 iOS unit suites | Shared `TokenStore` (5); actor/MainActor fake mistakes (4); mock-vs-itself false assurance (6); golden `PoemNaming` (9); heuristic goldens (15); Canvas snapshots (12); unreachable dissolve callback (13) | Gated actor fakes, isolated defaults suite, contract fixtures, property tests, explicit gap list |
| P4 Headless runner | Cold-boot crash flake (14); shared derived data and simulator (11, 2); zero-test green | Boot + bootstatus, targeted retry, separate derived data, executed-count floor |
| P5 Scripted e2e | Bot exits 0 on failure, fixed ports, FLUSHALL, no timeout on macOS (7); leaked wait record trips key check (7, 10) | In-process Go harness on ephemeral port, deadline on everything, assert on values not text, triage the leak as a bug |
| P6 Fix and baseline | Enshrining bugs; endless fixing (10); overclaiming "verified" (13, 12) | Triage rule, `XCTExpectFailure` / `t.Skip` with CONCERNS references, baseline lists gaps and toolchain versions |

## Sources

- Local spike (Xcode 16.4, iOS 18.6 simulator, iPhone 16) in the session scratchpad: scheme without a test action, `GENERATE_INFOPLIST_FILE` signing failure, cold-boot "signal kill" flake, hosted-app window count, begin-to-compose timing. HIGH.
- Repository reading: `ios/project.yml`, `ios/Strangewords/App/AppModel.swift`, `Net/LocalBackend.swift`, `Net/Keychain.swift` (`TokenStore`), `Net/APIClient.swift`, `Naming/PoemNaming.swift`, `Syllables/Syllables.swift`, `Design/Theme.swift`, `server/cmd/bot/main.go`, `live_test.sh`, `run_test_server_and_robot_poet_friend.sh`, `run.sh`, `server/Makefile`, `.planning/codebase/TESTING.md`, `.planning/codebase/CONCERNS.md`. HIGH for facts about the code.
- XCTest, Swift concurrency, UserDefaults suite, `xcodebuild` result-bundle and Swift Testing parallelism behavior: general knowledge, not re-verified against current Apple documentation in this session. MEDIUM; confirm against Xcode 16.4 docs before relying on exact flag names.
- No web search was run for this dimension.
