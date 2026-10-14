# Phase 2: iOS Client Logic Suites - Research

**Researched:** 2026-10-14
**Domain:** Swift Testing unit suites for a hosted iOS test bundle (SwiftUI app, `@MainActor @Observable` state machine, actor-based backends), minimal DI seams, and a concurrency (stale-writer) race fix
**Confidence:** HIGH (the central risk, the late-poll race and the gated-fake test pattern, was reproduced red and green in a scratch copy of the repo on this machine; the repo itself was not modified)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Seam shape (IOST-05)**
- **D-01:** `TokenStore` converts from a static enum to a **struct instance** with `init(defaults: UserDefaults = .standard)`, passed into `AppModel` as a defaulted init parameter (`tokenStore:`). All static `TokenStore.x` call sites in `AppModel` move to the instance. Real per-test isolation; no global state. — **Reversibility:** costly — touches every TokenStore call site in AppModel; reverting re-globalizes state the suites depend on isolating.
- **D-02:** `LocalBackend` gets **zero-able delay init params**: `init(strangerThinkTime: TimeInterval = 1.6, enterDelay: Duration = .milliseconds(600))` (exact labels at planner's discretion). Tests pass 0; the 1.6s pacing *feel* itself stays untested (fits "only seams justified by a specific test"). No injected clock.
- **D-03:** `AppModel(pollInterval: Duration = .seconds(3))` keeps its `[TUNABLE]` marker. `APIClient` gains `init(base: URL = <prod/SW_API_BASE>, session: URLSession = .shared)`; `.shared` stays the default instance. The URLSession seam is groundwork only — URLProtocol stub tests remain v2 (DRFT-02), do not write them this phase.
- **D-04:** Shared-container hygiene is an **executable check**: suites use suite-named `UserDefaults` (with `removePersistentDomain` cleanup), plus one explicit guard test asserting `UserDefaults.standard` holds no `sw.*` keys — extending the existing `HostIsolationTests` pattern. Satisfies success criterion 5 by proof, not convention.

**Driving async & time (IOST-04)**
- **D-05:** AppModel arc tests are driven by a **test-bundle scripted `FakeBackend`** implementing the `Backend` protocol: scripted responses/errors per call, with continuation "gates" the test releases to control exactly when a response lands. `LocalBackend` stays production-pure and gets its own direct actor-level tests (IOST-03).
- **D-06:** "No real-time sleeps" is met by passing **pollInterval ≈ .zero** in tests; poll pacing then comes entirely from the fake's gates (each poll request parks until the test releases it). No sleeper-closure seam.
- **D-07:** Actions (`begin`, `submit`, `release`, `leave`, `resume`) **track their in-flight `Task`** in an internal `@ObservationIgnored private(set) var` so tests have a deterministic `await actionTask?.value` sync point. Views unaffected; production behavior unchanged.

**Late-poll race fix (fix-as-we-go)**
- **D-08:** The fix is **both layers**: `Task.isCancelled` guards between each `await` and any state mutation in `pollWaiting`/`pollSession`, **plus** a session epoch/generation counter (bumped on begin/reset/dissolve) that `apply()` checks so any stale writer — poll or action — is rejected. — **Reversibility:** reversible — localized to AppModel internals; regression tests pin the behavior either way.
- **D-09:** Regression tests cover **two stale-writer scenarios**: a gated poll response released after `leave()` (the criterion-named case: session must not come back), and a gated `submitLine` response released after `leave()` (justifies the epoch guard so it isn't untested defensive code).
- **D-10:** The race fix is sequenced **red-then-green**: the regression test is written first, its failure against unfixed code is recorded (commit message / ledger note), then the fix lands turning it green. Phase 4's FIX-01 ledger gets documented evidence, not just an assertion.

**Test content & naming (IOST-01..03)**
- **D-11:** LocalBackend-vs-server drift policy: **fix AppModel-visible drift** under fix-as-we-go — e.g., LocalBackend currently has no line validation/rejection at all, so the submit-error UX is unexercisable in mock mode; bring that up to server semantics. Divergence that is cosmetically equivalent from AppModel's view (silently returning a stale view where the server 409s — AppModel refetches either way) is pinned as-is with a drift note in the test. Full parity is DRFT-01 (v2); do not pull the rest forward.
- **D-12:** The `Syllables` table (IOST-01) **pins the known misses** ("poem", "quiet", "rhythm") at their current, wrong counts as characterization, commented as known heuristic limits — plus correct words, lines, edge cases, and the 5/7/5 thresholds. The heuristic itself is not changed (it's a soft nudge by design, brief.v4.md §9).
- **D-13:** `PoemNaming` goldens (IOST-02) are **captured from current code**: run `coin()` over ~6–10 varied poems (typical haiku, unicode/emoji lines, empty/whitespace line, very long line, repeated identical lines), sanity-check the names, commit the input→name pairs. Pins FNV-1a + SplitMix64 + word lists; any hash/PRNG/vocabulary change fails a named test.
- **D-14:** Each `LocalBackend` test carries a **doc comment citing its Go counterpart** — e.g., `/// Mirrors TestRoundRobinHaikuIsABA (server/internal/sessions/policy_test.go)` — matching the project's existing design-doc citation convention and staying greppable from either side. No shared scenario-name table this phase.

### Claude's Discretion
- Exact parameter labels/spelling for the new seams, and where the epoch counter lives inside `AppModel`.
- FakeBackend's gating API design (continuations vs AsyncStream vs checked actors) — whatever is least flaky under `@Suite(.serialized)`.
- Which suites need `.serialized` (anything sharing a `UserDefaults` suite or main-actor state) vs can run parallel.
- Suite/file organization in `ios/StrangewordsTests/` (per-type files following the one-primary-type-per-file convention is the natural default).
- How many Syllables table rows and which edge cases beyond the named misses and 5/7/5 thresholds.
- The exact set of LocalBackend validation rules deemed "AppModel-visible" under D-11 (line rejection is confirmed in; judge the rest case by case against what AppModel can observe).

### Deferred Ideas (OUT OF SCOPE)
- **URLProtocol stub tests for APIClient** — seam (session param) lands now per D-03, tests are DRFT-02 (v2)
- **Full LocalBackend/server parity contract** (shared scenario table, drift list document) — DRFT-01 (v2); this phase only fixes AppModel-visible drift per D-11
- **Fixing the Syllables heuristic misses** — deliberate non-goal (D-12); would change the in-app nudge in a verification milestone
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| IOST-01 | `Syllables` heuristic covered by table-driven characterization tests (words, lines, edge cases, 5/7/5 thresholds) | Section "Syllables table" below: measured counts for ~30 inputs, including the three named misses (all return 1) and extra misses found (table, create, café, don't). 5/7/5 target logic lives in `SessionView.currentTarget` (Models.swift), which is pure and testable; the hint text in `ComposeView` is a private View method and is NOT unit-testable without a refactor (out of scope). |
| IOST-02 | `PoemNaming` determinism pinned with golden poem→name values | Section "PoemNaming goldens": candidate golden pairs measured with the repo's own source; stdlib `shuffle(using:)`/`randomElement(using:)` are documented as not stable across Swift releases, so goldens must be captured on the pinned simulator runtime, and are toolchain/runtime-sensitive. |
| IOST-03 | `LocalBackend` tests mirror server rules: pairing, round-robin, validation/rejection, idempotent resubmit, teardown | Section "LocalBackend vs server": rule-by-rule mapping with verified Go test names/line numbers, the present drift (no validation, ignored idemKey, no-op leave/dismiss), and a compiled+run Swift port of `CleanLine`. |
| IOST-04 | `AppModel` covered across the full arc with no real-time sleeps | Sections "Gated FakeBackend", "Late-poll race": an AsyncStream-of-pending-calls fake plus `pollTask`/`actionTask` handles gives deterministic sync points; 4 stale-writer tests ran red (unfixed) and green (fixed) in 0.017s total. |
| IOST-05 | Seams as defaulted init parameters with unchanged app behavior | Sections "Seams", Pitfall 1: D-03's literal `session: URLSession = .shared` would CHANGE behavior (current session is an ephemeral 15s-timeout config); defaults-preservation can be tested via pure/static defaults. |
</phase_requirements>

## Summary

Phase 2 is pure Swift Testing work in the existing hosted `StrangewordsTests` bundle plus a small set of app-side seams. Nothing needs new tooling: `ios/project.yml` already globs the `StrangewordsTests` directory, so new test files are picked up by the `xcodegen generate` that `scripts/test-ios.sh` runs on every invocation. The whole toolchain exists on this machine (Xcode 16.4, Swift 6.1.2 compiler in Swift 5 language mode, iPhone 16 simulator on iOS 18.6, xcodegen, jq). No third-party packages are involved.

The riskiest part (the gated-fake / stale-writer design) was de-risked by building it in a scratch copy of the repo (`/private/tmp/.../scratchpad/proto`): `TokenStore` as an injectable struct, `pollInterval`/`tokenStore` init params, `@ObservationIgnored private(set)` `pollTask`/`actionTask` handles, and an AsyncStream-based `FakeBackend` whose every call parks until the test resolves it. Four stale-writer tests (late `waiting` poll after `leave`, late `getSession` poll refresh after `leave`, late `submitLine` after `leave`, late `enter` after `leave`) all **fail on the unfixed AppModel** (session resurrected, `sw.sessionId` re-persisted to the suite's defaults) and **pass after the epoch + `Task.isCancelled` guards**; the four tests ran in 0.017s of test time with no sleeps and no leaked-continuation warnings.

Three findings change the plan relative to CONTEXT.md and must be handled by the planner: (1) D-03's `session: URLSession = .shared` default would silently change production behavior and anonymity properties (the real client uses an ephemeral config with a 15s timeout) — keep the existing ephemeral session as the default; (2) the race is wider than "poll loops": `pollSession` assigns `self.phase = .composing(s)` directly (bypasses `apply()`), and `begin`/`resume`/`submit`/`refresh` all write state after an `await` — so an epoch check *inside* `apply()` alone is insufficient; (3) `.serialized` does not serialize across suites, so the D-04 `UserDefaults.standard` guard test is order-dependent unless every AppModel in tests is built through one factory that always injects a suite-named `TokenStore`.

**Primary recommendation:** Land seams first (TokenStore struct, init params, task handles, LocalBackend/APIClient defaults, defaults-preservation tests), build the AsyncStream-gated `FakeBackend`, write the stale-writer tests red and record the run, then add epoch + `isCancelled` guards at every post-`await` write site to go green. Keep the ephemeral `URLSession` as `APIClient`'s default.

## Architectural Responsibility Map

This phase has no browser/CDN/API tiering in the usual sense; the relevant tiers are the iOS client's own layers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Phase state machine + stale-writer protection | iOS `AppModel` (`@MainActor`) | — | Single source of truth for UI state; all post-`await` writes happen here, so the fix lives here. |
| Token/session persistence seam | iOS `Net/Keychain.swift` (`TokenStore`) | `AppModel` (consumer) | Single place that touches `UserDefaults`; conversion to instance keeps isolation per test. |
| Mock stranger semantics | iOS `LocalBackend` actor | Go server rules (reference) | Must mirror `sessions.CleanLine`, round-robin policy, turn errors; Go is the source of truth. |
| Network seam | iOS `Backend` protocol | `APIClient` (prod), `LocalBackend` (mock), test `FakeBackend` | `AppModel` depends only on the protocol; the test fake plugs in with no production change. |
| Syllable nudge / keepsake naming | iOS pure functions (`Syllables`, `PoemNaming`) | — | On-device, deterministic, no I/O; characterization/golden tests only. |
| Test orchestration | `scripts/test-ios.sh` (Phase 1) | `xcodebuild`, `xcresulttool` | Verdict only from xcresult summary; this phase does not change it. |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Testing (`import Testing`) | ships with Xcode 16.4 / Swift 6.1.2 toolchain | `@Test`, `@Suite`, `#expect`, `.serialized`, `.timeLimit`, `Issue.record` | Locked by Phase 1 (D-10); already used by `SyllablesTests`, `HostIsolationTests`, `HarnessCanary`. [VERIFIED: ran 4 prototype tests this session via xcodebuild on Xcode 16.4] |
| Foundation `UserDefaults(suiteName:)` | iOS 17 SDK | Per-test isolated defaults container | Real isolation without globals; `removePersistentDomain(forName:)` cleanup worked in the prototype. [VERIFIED: prototype run] |
| Swift concurrency (`AsyncStream`, `CheckedContinuation`, `actor`) | Swift 5 language mode, Xcode 16.4 | Gated `FakeBackend` | No third-party test libs allowed (CLAUDE.md); compiled and ran in the prototype. [VERIFIED: prototype run] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `xcodebuild test -only-testing:StrangewordsTests/<Suite>` | Xcode 16.4 | Run one suite (red/green evidence for D-10) | Passed through `scripts/test-ios.sh "$@"`; confirmed in prototype with two `-only-testing` flags. |
| `xcrun xcresulttool get test-results summary` | Xcode 16.4 | Verdict JSON (`result`, `passedTests`, `failedTests`, `totalTestCount`) | Already how the harness decides; use the same for recording the red run. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| AsyncStream-of-pending-calls fake | Per-method `Gate` latch actor (open-before-wait safe) | Latch needs a second signal for "call has arrived"; the stream gives arrival ordering and the request payload for free. Either is deterministic; the stream is simpler to read in tests. |
| `Task` handles (`pollTask`, `actionTask`) as sync points | A bounded `Task.yield()` loop / `withObservationTracking` waiter | Yield loops are the flaky option D-07 exists to avoid. Handles are exact. |
| Epoch counter + `isCancelled` (D-08) | `isCancelled` only | `isCancelled` alone fixes the poll loops (leave cancels `pollTask`) but NOT action tasks (`begin`, `submit`, `resume`, `refresh` are never cancelled). Prototype confirmed these need the epoch. |

**Installation:** none. No packages are added. [VERIFIED: ios/project.yml has no `packages:`; CLAUDE.md "no third-party iOS dependencies"]

**Version verification:** Tooling versions measured this session: `xcodebuild -version` → "Xcode 16.4 / Build version 16F6"; `swift --version` → "Apple Swift version 6.1.2"; simulator runtimes → only "iOS 18.6 (18.6 - 22G86)"; `xcodegen` at `/opt/homebrew/bin/xcodegen`; `jq` at `/usr/bin/jq`. [VERIFIED: shell output this session]

## Package Legitimacy Audit

No external packages are installed in this phase (Apple frameworks and the Swift Testing library bundled with Xcode only). The legitimacy gate (`gsd-tools query package-legitimacy check`) was therefore not run.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| (none) | — | — | — | — | — | — |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
                       scripts/test-ios.sh  (xcodegen -> xcodebuild test -> xcresult verdict)
                                      |
                       StrangewordsTests (hosted in the app process, SW_LOCAL_MOCK=1)
                                      |
   +------------------+---------------+------------------+------------------------+
   |                  |                                  |                        |
 SyllablesTests   PoemNamingTests                 LocalBackendTests          AppModelTests (+ race)
 (pure fn)        (pure fn, goldens)              (actor, delays=0)          @MainActor
                                                        |                        |
                                                  LocalBackend            AppModel(backend: FakeBackend,
                                                  init(strangerThinkTime:0,         tokenStore: TokenStore(suite UserDefaults),
                                                       enterDelay:.zero)            pollInterval: .zero)
                                                                                        |
        test thread (MainActor)                                                         |
   1. model.begin()  --------------------------------------> actionTask = Task { await api.enter }
   2. pending = await fake.arrivals.next()  <--- FakeBackend parks call on CheckedContinuation,
                                                  yields Pending{kind,line,text} into AsyncStream
   3. pending.resolve(value | error)  ------------------> continuation resumes; Task continues
   4. await model.actionTask?.value / await staleTask?.value   (deterministic sync point)
   5. #expect(model.phase == ..., defaults.string(forKey: "sw.sessionId") == nil)

   Poll loop (production code, interval .zero in tests):
     while !cancelled { sleep(interval) ; await api.waiting/getSession  <-- parks in fake
                        guard !Task.isCancelled, epoch == captured     <-- NEW (D-08)
                        apply / phase write }
```

### Recommended Project Structure
```
ios/StrangewordsTests/
├── HarnessCanary.swift          # existing (Phase 1)
├── HostIsolationTests.swift     # existing; extend with the UserDefaults.standard guard (D-04)
├── SyllablesTests.swift         # existing; grow the tables (IOST-01), update its header comment
├── SessionViewTests.swift       # currentTarget 5/7/5 + nil cases (pure; part of IOST-01)
├── PoemNamingTests.swift        # goldens + determinism (IOST-02)
├── LocalBackendTests.swift      # IOST-03, every test cites its Go counterpart (D-14)
├── FakeBackend.swift            # test-only gated Backend (one primary type per file)
├── AppModelTests.swift          # full arc + errors + partner gone + begin-again (IOST-04)
├── AppModelRaceTests.swift      # stale-writer regression tests (D-09), written red first (D-10)
└── TestSupport.swift            # makeIsolatedDefaults(), makeModel(): the ONLY way tests build an AppModel
ios/Strangewords/ (changed: Net/Keychain.swift, App/AppModel.swift, Net/LocalBackend.swift, Net/APIClient.swift)
```
No `project.yml` change is needed (target already has `sources: - StrangewordsTests`). [VERIFIED: ios/project.yml lines for `StrangewordsTests` read this session]

### Pattern 1: TokenStore as an injectable struct (D-01)
**What:** Same keys, instance-held `UserDefaults`. Keep the key strings byte-identical so installed apps keep resuming. Use `nonmutating set` so a `let` struct can write.
**Example:** (compiled and run in the prototype)
```swift
// ios/Strangewords/Net/Keychain.swift
struct TokenStore {
    static let tokenKey = "sw.participantToken"
    static let sessionKey = "sw.sessionId"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var token: String? {
        get { defaults.string(forKey: Self.tokenKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.tokenKey) }
    }
    var sessionId: String? {
        get { defaults.string(forKey: Self.sessionKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.sessionKey) }
    }
    func clear() {
        defaults.removeObject(forKey: Self.tokenKey)
        defaults.removeObject(forKey: Self.sessionKey)
    }
}
```

### Pattern 2: AppModel seams + task handles (D-01, D-03, D-06, D-07)
```swift
// ios/Strangewords/App/AppModel.swift (excerpt; compiled in the prototype)
private let tokenStore: TokenStore
@ObservationIgnored private(set) var pollTask: Task<Void, Never>?
@ObservationIgnored private(set) var actionTask: Task<Void, Never>?
private let pollInterval: Duration // [TUNABLE] default .seconds(3) plan.v1.md §10

init(backend: (any Backend)? = nil,
     tokenStore: TokenStore = TokenStore(),
     pollInterval: Duration = .seconds(3)) { ... }
```
Notes: `@ObservationIgnored` on the `private(set) var` Task handles compiled fine inside the `@Observable` class. Every `Task { ... }` in `begin`, `resume`, `submit`, `release`, `leave` becomes `actionTask = Task { ... }`. `Task {}` created inside a `@MainActor` method inherits main-actor isolation, so `await model.actionTask?.value` from a `@MainActor` test is correct. To make the success-criterion-1 "unchanged defaults" claim testable, expose the defaults as internal statics (e.g. `AppModel.defaultPollInterval`, `LocalBackend.defaultStrangerThinkTime`/`defaultEnterDelay`, `APIClient.defaultBase`) and keep the `[TUNABLE]` marker on each. Make `pollInterval` internal (`let`) rather than `private` so a test can assert it.

### Pattern 3: AsyncStream-gated FakeBackend (D-05, D-06)
**What:** Every `Backend` call is recorded, then suspended on a `CheckedContinuation`; the call (kind, line, text) is yielded to an `AsyncStream` the test consumes. The test resolves each pending call exactly once. Because the `Pending` is only yielded after the continuation is stored, resolve-before-park is impossible; because `AsyncStream` buffers, arrive-before-test-awaits is also safe.
**Example:** (compiled and run in the prototype)
```swift
actor FakeBackend: Backend {
    enum Kind: Equatable { case enter, waiting, getSession, submitLine, leave, dismiss }
    final class Pending: @unchecked Sendable {
        let kind: Kind; let line: Int?; let text: String?
        fileprivate let cont: CheckedContinuation<Any, Error>
        init(kind: Kind, line: Int?, text: String?, cont: CheckedContinuation<Any, Error>) {
            self.kind = kind; self.line = line; self.text = text; self.cont = cont }
        func resolve(_ value: Any) { cont.resume(returning: value) }
        func fail(_ error: Error) { cont.resume(throwing: error) }
    }
    nonisolated let arrivals: AsyncStream<Pending>
    private let sink: AsyncStream<Pending>.Continuation
    init() { var c: AsyncStream<Pending>.Continuation!; arrivals = AsyncStream { c = $0 }; sink = c }
    private func park(_ kind: Kind, line: Int? = nil, text: String? = nil) async throws -> Any {
        try await withCheckedThrowingContinuation { cont in sink.yield(Pending(kind: kind, line: line, text: text, cont: cont)) }
    }
    func waiting(token: String) async throws -> WaitingResponse { try await park(.waiting) as! WaitingResponse }
    // enter / getSession / submitLine likewise
}
```
Required refinements for the real fake (not in the prototype):
- `leave` and `dismiss` are fire-and-forget (`Task { await api.leave }` tracked by `actionTask`). In the prototype they parked, which hangs `await model.actionTask?.value` unless the test resolves them. Default them to **record-and-return-immediately** (append to a `calls` log the test can assert), and park only when a test opts in.
- Add a `drain()` (resume all still-pending calls with `CancellationError` or a benign value) called from test cleanup so no poll task stays suspended holding the model after the test ends.
- Make `resolve`/`fail` assert single-use (double resume of a `CheckedContinuation` traps).
- A poll that gets a transient scripted error loops again immediately at `pollInterval = .zero`, calls the fake, and parks again. That is safe **only because the fake parks every poll call**. A fake that returns immediately for `waiting`/`getSession` would hot-loop the main actor (see Pitfall 3).
- Consider `withTaskCancellationHandler` around the continuation so a test cancelled by `.timeLimit` unblocks. [ASSUMED: Swift Testing's timeout cannot preempt a task parked in a non-cancellation-aware continuation; unverified]

### Pattern 4: Stale-writer guard (D-08, verified red -> green)
Capture `let e = epoch` when an action or poll task starts; after **every** `await` and before any mutation: `guard !Task.isCancelled, e == epoch else { return }`. Bump `epoch` in `begin()`, `reset()`, `dissolve()`.
- Await sites that need the guard (complete list from reading AppModel.swift this session): `begin` (`api.enter`, and the catch arm), `resume` (`getSession`, `waiting`, both catch arms), `submit` (`submitLine` success + `contentRejected`, `gone`, `notYourTurn/wrongTurn`, generic catch), `refresh` (`getSession` then `apply`), `pollWaiting` (`waiting` + `catch gone`), `pollSession` (`getSession` + `catch gone`).
- **`pollSession`'s `self.phase = .composing(s)` ("refresh lines while we wait") writes `phase` directly and never goes through `apply()`.** An epoch check inside `apply()` does NOT cover it; only the post-`await` guard does. The prototype test `latePollSessionRefreshAfterLeave` exists specifically for this.
- `apply()` writes `tokenStore.sessionId` before it does anything else; a stale `apply` re-persists the session id to disk after `leave()`. Guard before calling `apply` (or pass the captured epoch into `apply`), never after.
- `isCancelled` alone is enough for the two poll loops (because `leave` -> `dissolve` -> `stopPolling` cancels `pollTask`); the epoch is what protects `begin`/`submit`/`resume`/`refresh`, whose tasks are never cancelled.
- Either design satisfies D-08: call-site guards (what the prototype did, ~10 sites) or a single `private func isStale(_ e: Int) -> Bool { Task.isCancelled || e != epoch }` helper used at each site. A literal "check inside `apply()`" needs `apply(_:epoch:)` plus the call-site guards for the direct `phase` write.

### Pattern 5: Race test skeleton (red first, D-09/D-10)
```swift
@Test func latePollResponseAfterLeaveDoesNotResurrect() async throws {
    let (defaults, cleanup) = makeIsolatedDefaults(); defer { cleanup() }
    let fake = FakeBackend(); var it = fake.arrivals.makeAsyncIterator()
    let model = AppModel(backend: fake, tokenStore: TokenStore(defaults: defaults), pollInterval: .zero)
    model.begin()
    let enter = await it.next()!
    enter.resolve(EnterResponse(participantToken: "tok", state: "waiting", session: nil, waitId: "w"))
    await model.actionTask?.value
    #expect(model.phase == .waiting)
    let poll = await it.next()!          // poll is now parked inside fake.waiting
    let stale = model.pollTask           // capture BEFORE leave(); stopPolling() nils model.pollTask
    model.leave()
    poll.resolve(WaitingResponse(state: "matched", session: matchedView))
    await stale?.value                   // the stale poll has now run to completion; assertion is non-vacuous
    #expect(model.phase == .dissolved(.ended))
    #expect(defaults.string(forKey: "sw.sessionId") == nil)
}
```
Recorded red evidence from the prototype (unfixed AppModel, same test): `Expectation failed: (model.phase → .composing(... sessionId: "s1" ...)) == (.dissolved(.ended) ...)` and `(defaults.string(forKey: "sw.sessionId") → "s1") == nil`; xcresult summary `{"result":"Failed","passedTests":0,"failedTests":1,"totalTestCount":1}`. Green after the fix: `{"result":"Passed","passedTests":4,"failedTests":0,"totalTestCount":4}`, total test time 0.017s. [VERIFIED: xcodebuild runs this session, scratch copy]

### Anti-Patterns to Avoid
- **Capturing `model.pollTask` after `leave()`:** `stopPolling()` sets it to nil, so the test would await nothing and the assertion would pass vacuously. Capture before `leave()`.
- **Building `AppModel(backend:)` in a test without `tokenStore:`:** `begin()` then writes to `UserDefaults.standard` (see Pitfall 4).
- **Sleeping to "let the poll happen":** forbidden by success criterion 5; use the arrivals stream and task handles.
- **Fake that answers polls immediately at `pollInterval: .zero`:** busy-loops (Pitfall 3).
- **Changing `Syllables`, the key strings, or `[TUNABLE]` defaults while adding seams:** all behavior must be byte-for-byte as before (criterion 1).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Deterministic async sync points | A sleeper/clock seam, `Task.yield()` spin-waits | `actionTask`/`pollTask` handles + `AsyncStream` of pending calls | Exact; zero wall-clock; D-06/D-07 already lock this. |
| Test isolation of persisted state | A global `TokenStore` reset in `setUp` | `UserDefaults(suiteName: "sw.tests.<UUID>")` + `removePersistentDomain` | No shared state, parallel-safe. |
| Test framework/mocking | Any third-party mocking/clock lib | Hand-written `FakeBackend` | CLAUDE.md: no third-party iOS dependencies. |
| Line validation in LocalBackend | A new ad-hoc rule set | A direct port of `sessions.CleanLine` (compiled and verified below) | Behavior must match server; ported rule-for-rule against the five Go `validate_test.go` cases. |
| NFC normalization | Manual composition | `String.precomposedStringWithCanonicalMapping` [ASSUMED: standard Foundation NFC API; the prototype port used it and passed the combining-accent case] | Matches Go's `norm.NFC`. |
| Hash/PRNG for naming | Replacing FNV-1a/SplitMix64 or stdlib shuffle | Keep as-is; pin with goldens | Out of scope; changing it changes users' keepsake names. |

**Key insight:** every sync problem in this phase is solved by making the test the owner of "when does this response land" (gates) and "has that task finished" (handles). There is no timing to tune.

## Runtime State Inventory

This is not a rename/migration phase (the `TokenStore` enum-to-struct change does not rename any stored string), so the full 5-category inventory is not required. The one runtime-state fact the planner must preserve: the `UserDefaults` keys `"sw.participantToken"` and `"sw.sessionId"` (read from `ios/Strangewords/Net/Keychain.swift` this session, `tokenKey`/`sessionKey`) must remain byte-identical, otherwise an installed build would orphan an in-progress token. Tests create their own suite-named domains (`sw.tests.<UUID>`); those plists live in the simulator app container and are removed by `removePersistentDomain`. If a test process crashes before cleanup, UUID names mean leftovers are harmless clutter rather than collisions.

## Common Pitfalls

### Pitfall 1: D-03's `session: URLSession = .shared` changes production behavior
**What goes wrong:** The current `APIClient` builds `URLSessionConfiguration.ephemeral` with `timeoutIntervalForRequest = 15` (APIClient.swift lines 32-36). `URLSession.shared` has a 60s default request timeout, a shared cookie store and URL cache. Switching the default silently violates success criterion 1 ("behaves as before") and weakens the anonymity posture (ephemeral = no persistent cookies/cache).
**Why it happens:** CONTEXT.md D-03 writes `session: URLSession = .shared` and ".shared stays the default instance"; the second phrase most plausibly refers to `APIClient.shared` (the actor singleton), not `URLSession.shared`.
**How to avoid:** `init(base: URL = APIClient.defaultBase, session: URLSession = APIClient.makeDefaultSession())` where `makeDefaultSession()` returns the existing ephemeral/15s session; `static let shared = APIClient()` keeps using defaults. Flag the deviation in the plan so the user can confirm the intent. Also make the base-resolution a pure function (`APIClient.resolveBase(environment:)`) so "prod base URL unchanged" is testable without reading the test process's `SW_API_BASE=http://127.0.0.1:9`.
**Warning signs:** a plan task that literally writes `= .shared` for the session parameter.

### Pitfall 2: The race is wider than the poll loops
**What goes wrong:** Fixing only `pollWaiting`/`pollSession` (as the roadmap note suggests) leaves `begin`, `resume`, `submit`, and `refresh` able to resurrect the session or re-persist a token after `leave()`. Reproduced: late `enter` after `leave` writes `sw.participantToken` and moves to `.composing`; late `submitLine` after `leave` re-persists `sw.sessionId` and moves to `.composing`.
**Why it happens:** Those are non-cancelled `Task {}`s created by actions; `leave()` cancels only `pollTask`.
**How to avoid:** Pattern 4. Keep all four extra tests (D-09 requires two; the other two cost ~10 lines each and exercise the other write sites).
**Warning signs:** a fix diff that touches only the two poll functions.

### Pitfall 3: Hot-looping poll at `pollInterval: .zero`
**What goes wrong:** With a zero interval, a poll loop whose backend call returns or throws immediately spins forever on the main actor, starving the test.
**Why it happens:** the loop has no pacing other than `Task.sleep`; measured: 1000 `Task.sleep(for: .zero)` calls take ~2 ms [VERIFIED: scratch swiftc run, macOS host], i.e. it does not pace.
**How to avoid:** the fake parks every `waiting`/`getSession` call (default behavior); a "transient error" test resolves exactly one pending poll with an error and then lets the next poll park. Never script an unbounded stream of immediate errors.

### Pitfall 4: The `UserDefaults.standard` guard is order-dependent
**What goes wrong:** D-04's guard asserts `.standard` has no `sw.*` keys, but Swift Testing runs tests and suites in parallel and `.serialized` does not order a suite relative to unrelated suites. If any other test builds `AppModel` without a suite-named `TokenStore` and calls `begin()`, the guard passes or fails depending on scheduling.
**Why it happens:** `.serialized` "doesn't affect the execution of a test relative to its peers or to unrelated tests" [CITED: developer.apple.com/documentation/testing/parallelization].
**How to avoid:** (1) all test AppModels come from one `makeModel()` factory in `TestSupport.swift` that always injects a suite-named store; (2) the guard test is the backstop, not the mechanism; (3) add a plan verification grep: every `AppModel(` in `ios/StrangewordsTests` must be inside the factory or pass `tokenStore:`. The host app itself leaves `.standard` clean: `StrangewordsApp` makes `AppModel()` and `.task { model.resume() }`, and in `SW_LOCAL_MOCK=1` mode `init` calls `tokenStore.clear()` on `.standard` (AppModel.swift lines 52-64 as read).
**Warning signs:** guard test flakes when run with `-only-testing` vs full suite.

### Pitfall 5: PoemNaming goldens depend on the stdlib, not just the repo
**What goes wrong:** `coin()` uses `pool.shuffle(using:)`, `randomElement(using:)`, `Int.random(in:using:)`, `Bool.random(using:)`. Apple documents that the shuffle algorithm may change in a future Swift version, so the same seeded generator can produce a different order on a different toolchain. The Swift stdlib on an iOS simulator is the runtime's, so goldens captured on iOS 18.6 may differ on an iOS 17.x runtime. [CITED: developer.apple.com/documentation/swift/array/shuffle(using:)]
**How to avoid:** capture goldens on the harness's pinned simulator (iPhone 16 / iOS 18.6) via a failing-then-read run (below), not from a macOS script; record the runtime in a comment; note in the plan that a golden failure after an Xcode/iOS update is possibly toolchain drift rather than a code regression (add it to Phase 4's not-verified list, which already notes only iOS 18.6 is installed). Do NOT "fix" by rewriting `coin()` to its own Fisher-Yates in this phase (behavior change); mention as a future option.
**Cross-check performed:** the macOS-host stdlib produced the candidate values listed below; they must still be re-captured in the simulator because host and simulator stdlibs may differ.

### Pitfall 6: Fire-and-forget actions hang `await actionTask?.value`
`leave()` and `release()` spawn `Task { await api.leave/dismiss }`. If the fake parks those calls, awaiting `actionTask` hangs forever. Default them to immediate-return in the fake (Pattern 3). Also, `leave()` only sends `api.leave` when `tokenStore.sessionId` is non-nil, so leaving while still waiting (no session yet) sends nothing; tests for "leaving mid-poll while waiting" must not expect a `.leave` call. (Observed behavior, noted as a mock/real fidelity observation, not changed here.)

### Pitfall 7: Leaked or double-resumed continuations
Unresolved `CheckedContinuation`s at test end leave tasks suspended; resolving twice traps. No leaked-continuation warnings appeared in the prototype runs because every pending call was resolved; the real fake needs `drain()` in cleanup and single-use assertions.

### Pitfall 8: Swift `String.count` vs Go `[]rune` in the LocalBackend length rule
Go caps at `len([]rune(s)) > MaxLineLen` (100 Unicode code points). Swift `String.count` counts grapheme clusters; 40 ZWJ family emojis is 40 graphemes but 200 scalars. Use `s.unicodeScalars.count`. [VERIFIED: scratch port run: 40 repeats of the ZWJ family emoji (U+1F469 U+200D U+1F469 U+200D U+1F467) -> `.tooLong`]

### Pitfall 9: Test timing and hung tests
Build dominates wall-clock (prototype: ~34s cold derived data, ~16s incremental, tests themselves 0.017s). Criterion 5's "seconds" applies to test execution; cite xcresult durations, not total script time. A test that awaits a gate nobody opens hangs: add `.timeLimit(.minutes(1))` to gated suites (the minimum granularity is one minute; applies per test) [CITED: developer.apple.com/documentation/testing/trait/timelimit(_:)], plus a grep guard that no `Task.sleep`/`Thread.sleep`/`usleep` appears under `ios/StrangewordsTests`.

## Code Examples

### Syllables table (IOST-01): measured current outputs
All values below were produced by compiling the repo's `Syllables.swift` unmodified in a scratch dir (pure logic, platform-independent). [VERIFIED: swiftc run this session]

| Input | Current count | True syllables | Note for the test comment |
|-------|--------------|----------------|---------------------------|
| `poem` | 1 | 2 | known miss (D-12): `oe` is one vowel cluster |
| `quiet` | 1 | 2 | known miss: `uie` one cluster |
| `rhythm` | 1 | 2 | known miss: only `y` |
| `table` | 1 | 2 | extra miss: trailing-`e` drop after `-le` |
| `create` | 1 | 2 | extra miss: `ea` cluster then silent-e drop |
| `café` | 1 | 2 | extra miss: `é` not in `aeiouy` |
| `don't` | 2 | 1 | extra miss: apostrophe splits into `don`,`t`; `t` floors at 1 |
| `fire` / `the` / `pond` / `jumps` / `hour` / `hmm` / `e` / `Y` | 1 | — | existing + floor behaviour |
| `into` / `silence` / `again` / `autumn` / `lanterns` | 2 | 2 | correct |
| `beautiful` | 3 | 3 | correct |
| `""`, `"123"`, `"😀"` | 0 | — | no letters -> 0 |
| `An old silent pond` | 5 | 5 | haiku line 1 |
| `A frog jumps into the pond` | 7 | 7 | existing row; haiku line 2 |
| `Splash! Silence again.` | 5 | 5 | haiku line 3 |
| `a frog leaps into the pond` / `the autumn wind scatters them` | 7 / 7 | — | LocalBackend stranger lines hit 7 |

The 5/7/5 "thresholds" for the nudge are `SessionView.currentTarget` (Models.swift lines 19-23: returns `form.targets[currentLine]`, `nil` when `currentLine` is out of range or the entry is null). Test: line 0/1/2 -> 5/7/5; line 3 and -1 -> nil; a `FormView` with a `nil` entry -> nil. The user-visible hint text (`hintText(count:target:)`) is a `private` View method in `ComposeView.swift` (lines 87-93) and is not unit-testable without a refactor; leave it out of scope per "testability refactors beyond minimal seams" (REQUIREMENTS Out of Scope).

### PoemNaming goldens (IOST-02): candidate values (macOS host stdlib; RE-CAPTURE ON THE SIMULATOR)
Measured with the repo's `PoemNaming.swift` compiled unmodified on the macOS host. [VERIFIED: swiftc run this session; host-only]

| Poem (lines) | name | kind | lead |
|--------------|------|------|------|
| `["an old silent pond","a frog jumps into the pond","splash silence again"]` | `Old Splash` | `an aged cheese` | `One strange word stayed behind:` |
| same poem, Title Case | identical to above (seed uses `.lowercased()`, words are title-cased) | | |
| `["🌸🌸🌸","  ","✨✨"]` | `nil` (no letters) | | |
| `["","   ",""]` | `nil` | | |
| `["moon","moon","moon"]` | `Moon No. 5` | `a perfume` | `The poem dissolved. This is what it named:` |
| `["moon"]` | `The Moon` | `a sailboat` | `Gone — but not before it became` |
| `[String(repeating: "lantern ", count: 40)]` | `Lantern` | `a nail polish` | `The poem dissolved. This is what it named:` |
| `["café naïve résumé","über straße","日本語 の 詩"]` | `Straße Café` | `a garden rose` | `Gone — but not before it became` |
| `["lanterns drift down the dark stream","snow settles on the still pine","frost"]` | `Lanterns Drift` | `a racehorse` | `It's gone now — but it left a name behind.` |

Capture procedure (no `print` needed, works under the harness): write each golden with a placeholder expected value, run `scripts/test-ios.sh -only-testing:StrangewordsTests/PoemNamingTests`, read the actual values from the `Expectation failed` text in the xcodebuild log, sanity-check the names, paste them in, re-run green. Also include: `coin()` twice equals itself (cheap same-process determinism), and the case-insensitivity pair above. Do not assert "different poems give different names" (not guaranteed).

Mutation check for criterion 2 ("changing heuristic, hash, or PRNG makes a named test fail"): as a verification step (not committed), temporarily change (a) `vowels` in `Syllables`, (b) the FNV offset basis `0xcbf29ce484222325`, (c) a SplitMix64 constant, run the suites, confirm a named test fails each time, then revert. Record the three outcomes in the SUMMARY.

### LocalBackend vs server: rule mapping for IOST-03 / D-14
Go counterparts (names and line numbers read from the files this session):

| Rule | Go counterpart (cite in the Swift doc comment) | LocalBackend today | Action under D-11 |
|------|-----------------------------------------------|--------------------|-------------------|
| Pairing: second entrant is matched with a session; `you`=0 first | `TestFullPoemHappyPath` (gateway_test.go:155), `match` helper | `enter` returns `state: "matched"`, token `"local"`, `waitId: nil`; `waiting` always matched | Pin as-is. |
| Round-robin ABA | `TestRoundRobinHaikuIsABA` (policy_test.go:5) | `currentAuthor = currentLine % 2`, you = 0 | Pin: you, stranger, you; `yourTurn` flips accordingly. |
| Wrong person / wrong line index -> 409 | `TestTurnOrderViolations` (gateway_test.go:209) | `guard yourTurn, line == currentLine else { return view() }` silently returns the current view | Pin as-is with drift note (AppModel refetches either way). |
| Empty / whitespace-only line -> 422 `content_rejected`, message `"line is empty"` | `TestCleanLineRejectsEmpty` (validate_test.go:18), `TestTurnOrderViolations` | appends trimmed text, even empty | FIX: throw `APIError.contentRejected("line is empty")`. |
| >100 runes -> `"line exceeds maximum length"` | `TestCleanLineRejectsTooLong` (validate_test.go:26) | none | FIX (use `unicodeScalars.count`; 100 passes, 101 rejects). |
| Control chars -> `"line contains disallowed characters"` (tab/CR/LF are whitespace, not rejects) | `TestCleanLineRejectsControl` (validate_test.go:37) | none | FIX. |
| Whitespace collapse + trim; zero-width stripped; NFC | `TestCleanLineAccepts` (:8), `TestCleanLineStripsZeroWidth` (:43) | only `trimmingCharacters` | FIX: the accepted text is what lands in `lines` and what `PoemNaming` hashes. |
| Banned-term screener -> `ErrContentRejected` (`"content not allowed"`) | `TestCleanLineScreens` (content_test.go:47) | none | Out of scope: list is server-side; document as drift note (DRFT-01). |
| Idempotent resubmit returns original response verbatim | `TestIdempotentResubmit` (gateway_test.go:238) | `idemKey` ignored; a replay of the same line index is rejected by the turn guard and returns the *current* view; no duplicate line is appended | Pin "no duplicate line" as-is; "verbatim" is NOT mirrored. `AppModel.submit()` generates a fresh UUID per call, so it never replays a key: not AppModel-visible, hence pin per D-11. |
| Leave dissolves; partner gets 410 | `TestLeaveDissolves` (gateway_test.go:266) | `leave`/`dismiss` are no-ops | See Open Question 1: a no-op makes a "teardown" test vacuous. |
| Dismiss by all -> dissolved -> 410, zero keys | `TestFullPoemHappyPath` (gateway_test.go:155) | no-op | same |

Server message strings are the Go sentinel errors verbatim (`ErrEmptyLine = errors.New("line is empty")`, `ErrLineTooLong = errors.New("line exceeds maximum length")`, `ErrBadChars = errors.New("line contains disallowed characters")`, `MaxLineLen = 100`) [VERIFIED: server/internal/sessions/validate.go lines 11-18 read this session], and `handleLine` writes `writeErr(w, http.StatusUnprocessableEntity, "content_rejected", err.Error())` [VERIFIED: gateway.go line 235]. `APIClient.mapError` turns 422 into `.contentRejected(message)`, and `AppModel.submit` sets `submitError = m`, so the mock should throw `APIError.contentRejected("<same string>")`.

Port of `CleanLine` (compiled and run in a scratch dir against the five Go `validate_test.go` expectations plus `\v`, combining accent, 100/101 boundary, and the grapheme-vs-scalar case; all matched):
```swift
func cleanLine(_ raw: String, maxLen: Int = 100) -> Result<String, LineRejection> {
    let nfc = raw.precomposedStringWithCanonicalMapping
    for u in nfc.unicodeScalars {
        if u == "\n" || u == "\r" || u == "\t" { continue }
        if u.properties.generalCategory == .control { return .failure(.badChars) }  // includes \v \f U+0085, like Go's unicode.IsControl
    }
    let zeroWidth: Set<UInt32> = [0x200B, 0x200C, 0x200D, 0xFEFF, 0x2060]
    var out = String.UnicodeScalarView(); var prevSpace = false
    for u in nfc.unicodeScalars where !zeroWidth.contains(u.value) {
        if u.properties.isWhitespace { if !prevSpace { out.append(" ") }; prevSpace = true }
        else { out.append(u); prevSpace = false }
    }
    let s = String(out).trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return .failure(.empty) }
    if s.unicodeScalars.count > maxLen { return .failure(.tooLong) }
    return .success(s)
}
```
Keep the `[TUNABLE]` comment on the max length and cite `server/internal/sessions/validate.go` in the doc comment (project convention). Note the Go order: control-char check runs on the NFC string *before* zero-width stripping; the port preserves that.

Test knobs for LocalBackend (all deterministic, no sleeps): construct with `strangerThinkTime: 0, enterDelay: .zero` so the stranger's line appears on the first `getSession` (`Date().timeIntervalSince(since) >= 0` is always true); construct with a huge think time (e.g. 3600) to prove "stranger holds the poem until the think time passes" without waiting. The stranger-line rotation index (`strangerPick`) persists across `enter`, so assert on text only for the first stranger line or avoid asserting which of the four lines appears.

### Defaults-preservation tests (criterion 1)
```swift
@Test func defaultsMatchShippedBehavior() {
    #expect(AppModel.defaultPollInterval == .seconds(3))
    #expect(LocalBackend.defaultStrangerThinkTime == 1.6)
    #expect(LocalBackend.defaultEnterDelay == .milliseconds(600))
    #expect(APIClient.resolveBase(environment: [:]).absoluteString == "https://api.strangerwords.us")
    #expect(APIClient.resolveBase(environment: ["SW_API_BASE": "http://x:1"]).absoluteString == "http://x:1")
    #expect(TokenStore().defaults === UserDefaults.standard)
}
```
(A separate test can assert `APIClient.makeDefaultSession().configuration.timeoutIntervalForRequest == 15`.) These are the minimal "seam justified by a test" exposures.

### Hygiene helper and guard (D-04)
```swift
func makeIsolatedDefaults() -> (UserDefaults, cleanup: () -> Void) {
    let suite = "sw.tests.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: suite)!
    return (d, { d.removePersistentDomain(forName: suite) })
}
// HostIsolationTests addition
@Test func standardDefaultsHoldNoSessionKeys() {
    #expect(UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("sw.") }.isEmpty)
}
```

### Running red and green (D-10)
```bash
# red (unfixed): expected exit 1, record the verdict line in the commit message / ledger
scripts/test-ios.sh -only-testing:StrangewordsTests/AppModelRaceTests
# green: same command, expected exit 0; then the full suite
scripts/test-ios.sh
```
`-only-testing:StrangewordsTests/<SuiteStruct>` selected exactly the intended Swift Testing suites in the prototype. The harness's own verdict rule (`passedTests>0`, `totalTestCount>0`) still applies, so a mistyped filter fails rather than passing empty.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| XCTest + expectations/`sleep` | Swift Testing (`@Test`, `#expect`, traits) | Xcode 16 / Swift 6.0 (availability "Xcode 16.0.0 -") [CITED: developer.apple.com/documentation/testing/timelimittrait] | Already adopted in Phase 1; async tests are native. |
| `.serialized` as global serialization | Per-suite/per-function only; does not serialize relative to unrelated suites | Current docs; a Swift Forums pitch proposes changing it, not confirmed shipped [CITED: forums.swift.org pitch-make-serialized-trait-public-api] | Do not rely on `.serialized` for cross-suite ordering. |
| Static `enum` singletons for persistence | Injected value types with defaulted parameters | n/a | D-01. |

**Deprecated/outdated:** `.planning/codebase/TESTING.md` still says "No test target exists" (stale since Phase 1, per CONTEXT canonical_refs); do not copy its claims.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Swift Testing's `.timeLimit` cannot preempt a task parked in a non-cancellation-aware `CheckedContinuation`, so gates should also honour cancellation | Pattern 3 | Low: the extra `withTaskCancellationHandler` is harmless; without it a hung gate could stall the run past the limit. |
| A2 | `precomposedStringWithCanonicalMapping` is Foundation's NFC (matches Go `norm.NFC`) | Don't Hand-Roll / LocalBackend | Low: the combining-accent probe returned the composed form, but exotic normalization edge cases were not compared against Go. |
| A3 | Candidate PoemNaming golden values from the macOS host stdlib may differ from the iOS 18.6 simulator stdlib | PoemNaming goldens | Medium if skipped: committing host-captured values could fail on the first simulator run; mitigated by the mandatory in-simulator capture procedure. |
| A4 | CONTEXT D-03's `.shared` refers to the `APIClient.shared` instance, not `URLSession.shared` | Pitfall 1 | High if the user truly wants `URLSession.shared`: would change timeout/cookie/cache behavior; planner should confirm. The research position is "keep the ephemeral default". |
| A5 | Pinning the late-`submit` result via `defer { submitting = false }` (flag cleared even when stale) is acceptable UX | Pattern 4 | Low: `submitting` is only read by the compose button. |

## Open Questions

1. **Should LocalBackend `leave`/`dismiss` gain real teardown behavior?**
   - What we know: they are no-ops today; IOST-03 names "teardown" and every server counterpart (`TestLeaveDissolves`, `TestFullPoemHappyPath`) asserts post-teardown 410/zero keys. AppModel never calls the backend after `leave`/`release` (verified by reading AppModel), so adding teardown is not AppModel-visible.
   - What's unclear: whether the user counts this under D-11's "AppModel-visible" boundary.
   - Recommendation: minimal teardown — `leave`/`dismiss` set `status = "dissolved"` and clear `lines`; subsequent `getSession`/`submitLine` throw `APIError.gone`; `enter` revives with a fresh poem. This makes the teardown test non-vacuous, mirrors the anonymity rule (poem content erased), and is safe because nothing polls after leave/dismiss. Fallback if the planner prefers strict D-11: test only "enter starts a fresh poem" and record the no-op leave as a documented drift note.

2. **Epoch check shape:** call-site guards (prototype) vs `apply(_:epoch:)` plus call-site guards. Both satisfy D-08; the prototype proves the former. Planner's discretion per CONTEXT.

3. **One commit or two for red-then-green?** Recommendation: test commit (red, with the recorded verdict line in the message) then fix commit (green). The red commit leaves the suite red at that SHA; if that is unacceptable for bisect-cleanliness, commit test+fix together and put the red run's `ios-verdict.txt` line in the SUMMARY/ledger instead.

4. **Extra stale-writer scenarios beyond D-09's two.** The prototype shows four scenarios are all real. Recommended to keep all four; the cost is small and it guards the other write sites.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode / xcodebuild | all iOS tests | ✓ | 16.4 (16F6) | — |
| Swift toolchain | compile | ✓ | 6.1.2 (project uses Swift 5 language mode) | — |
| iOS Simulator runtime | hosted tests | ✓ | iOS 18.6 only (no 17.x; carried to Phase 4 not-verified list) | none needed this phase |
| iPhone 16 simulator device | harness pin (`SW_SIM_NAME` default) | ✓ (used by prototype runs) | iOS 18.6 | `SW_SIM_NAME` override |
| xcodegen | project generation | ✓ | `/opt/homebrew/bin/xcodegen` | — |
| jq | harness verdict | ✓ | `/usr/bin/jq` | — |
| Network / third-party packages | — | not required | — | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none. (The harness shuts the pinned simulator down at the end of a run; do not run it concurrently with `run.sh` on the same simulator — documented in the script header.)

## Security Domain

`security_enforcement` is enabled (absent/true in `.planning/config.json`, ASVS level 1). This phase adds no network surface, but it touches the anonymity-critical persistence path and the mock's input validation.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Bearer token is anonymous and unchanged |
| V3 Session Management | yes | The stale-writer fix is itself a session-lifecycle fix: after `leave()`/dissolve, no late response may re-persist `sw.participantToken` / `sw.sessionId` or resurrect the session (tests assert both phase and the `UserDefaults` keys) |
| V4 Access Control | no | — |
| V5 Input Validation | yes | LocalBackend port of `CleanLine` (reject empty/over-length/control; collapse whitespace; strip zero-width; NFC) so the mock exercises the same validation contract |
| V6 Cryptography | no | FNV-1a/SplitMix64 are non-cryptographic naming seeds, not security controls; do not change |
| V8 Data Protection | yes | Tests must leave nothing behind: suite-named defaults removed with `removePersistentDomain`; `UserDefaults.standard` guard; ephemeral `URLSession` retained as the `APIClient` default (Pitfall 1) |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Late network response re-persists identity (token/session id) after the user left | Information disclosure / Tampering | Epoch + `Task.isCancelled` guards before any state or `TokenStore` write; regression tests assert the defaults keys are nil |
| Default `URLSession.shared` introduces persistent cookies/cache | Information disclosure | Keep `URLSessionConfiguration.ephemeral` as `APIClient`'s default session |
| Test pollution of the app's shared `UserDefaults` | Information disclosure | Suite-named `UserDefaults` via one factory + `.standard` guard test |
| Poem content retained in the mock after dismissal | Information disclosure | Minimal teardown (Open Question 1) clears `lines` |

## Sources

### Primary (HIGH confidence)
- Repository source read this session: `ios/Strangewords/App/AppModel.swift`, `Net/LocalBackend.swift`, `Net/Keychain.swift`, `Net/APIClient.swift`, `Net/Backend.swift`, `Net/Models.swift`, `Naming/PoemNaming.swift`, `Syllables/Syllables.swift`, `Features/Compose/ComposeView.swift`, `ios/StrangewordsTests/*.swift`, `ios/project.yml`, `scripts/test-ios.sh`, `server/internal/sessions/validate.go`, `policy_test.go`, `validate_test.go`, `content_test.go`, `server/internal/gateway/gateway.go` (lines 186-312), `gateway_test.go`.
- Prototype runs on this machine (scratch copy under the session scratchpad; repo untouched): xcodebuild test results for red (unfixed) and green (fixed) race tests; swiftc runs for Syllables, PoemNaming, `Task.sleep(.zero)` cost, and the `CleanLine` port.
- [Swift Testing: Running tests serially or in parallel](https://developer.apple.com/documentation/testing/parallelization.md)
- [Swift Testing: timeLimit(_:)](https://developer.apple.com/documentation/testing/trait/timelimit(_:).md)
- [Swift Testing: TimeLimitTrait](https://developer.apple.com/documentation/testing/timelimittrait.md)

### Secondary (MEDIUM confidence)
- [Apple docs: Array.shuffle(using:)](https://developer.apple.com/documentation/swift/array/shuffle(using:).md) (shuffle algorithm may change across Swift versions; reported via web search summary, not re-fetched)
- [Swift Forums: pitch to make .serialized public / cross-suite behaviour](https://forums.swift.org/t/pitch-make-serialized-trait-public-api/73147)

### Tertiary (LOW confidence)
- none beyond items tagged `[ASSUMED]` in the Assumptions Log.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Swift Testing already works in the harness; prototype ran on the pinned toolchain.
- Architecture (gated fake, handles, epoch): HIGH — red and green reproduced for four scenarios.
- Pitfalls: HIGH for 1-4, 6-8 (read from source or reproduced); MEDIUM for Pitfall 5 (documented stdlib caveat; simulator-vs-host divergence not measured) and the timeout-vs-continuation interaction (A1).
- LocalBackend rule mapping: HIGH — Go files read; Swift port matched all cases run.

**Not researched (deliberately):** Validation Architecture section omitted because `workflow.nyquist_validation` is `false` in `.planning/config.json`. Plan sequencing suggestion for the planner: Wave 1 (parallel, disjoint files) = [seams: Keychain/AppModel params+handles/LocalBackend init/APIClient init + defaults-preservation tests] and [Syllables + SessionView + PoemNaming suites]; Wave 2 = [LocalBackend drift fixes + tests] and [FakeBackend + AppModel arc tests + red race tests]; Wave 3 = [epoch/isCancelled fix to green + `.standard` guard + mutation checks + no-sleep grep]. AppModel.swift is edited in Wave 1 and Wave 3, so those must stay sequential.

**Research date:** 2026-10-14
**Valid until:** 2026-11-13 (stable toolchain; re-check if Xcode or the simulator runtime is updated, since PoemNaming goldens are stdlib-sensitive)
