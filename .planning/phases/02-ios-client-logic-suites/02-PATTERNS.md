# Phase 2: iOS Client Logic Suites - Pattern Map

**Mapped:** 2026-10-14
**Files analyzed:** 17 (9 new test files, 4 modified app files, 1 extended test, 1 extended test, 2 doc/no-op)
**Analogs found:** 15 / 17 (all analogs verified git-tracked)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `ios/Strangewords/Net/Keychain.swift` (mod: enum to struct) | utility/store | CRUD (UserDefaults) | itself (current enum, lines 12-31) | self |
| `ios/Strangewords/App/AppModel.swift` (mod: seams, task handles, epoch guards) | state machine | event-driven / request-response | itself (lines 46-64, 69-259) | self |
| `ios/Strangewords/Net/LocalBackend.swift` (mod: init delays, validation, teardown) | service (actor) | request-response | itself; validation from `server/internal/sessions/validate.go` | self + Go port |
| `ios/Strangewords/Net/APIClient.swift` (mod: init base/session, static defaults) | service (actor) | request-response | itself (lines 15-36) | self |
| `ios/StrangewordsTests/SyllablesTests.swift` (extend) | test | transform | itself (parameterized `@Test(arguments:)`) | exact |
| `ios/StrangewordsTests/SessionViewTests.swift` (new) | test | transform | `SyllablesTests.swift` | exact |
| `ios/StrangewordsTests/PoemNamingTests.swift` (new) | test | transform | `SyllablesTests.swift` | exact |
| `ios/StrangewordsTests/HostIsolationTests.swift` (extend) | test | config guard | itself | exact |
| `ios/StrangewordsTests/LocalBackendTests.swift` (new) | test | request-response | `SyllablesTests.swift` for table style; Go `validate_test.go`, `policy_test.go`, `gateway_test.go` for cases | role-match |
| `ios/StrangewordsTests/FakeBackend.swift` (new) | test double | event-driven (gated) | `Backend` protocol in `Net/Backend.swift`; `LocalBackend` actor shape | role-match |
| `ios/StrangewordsTests/TestSupport.swift` (new) | test util | factory | none in repo; RESEARCH Hygiene helper | no analog |
| `ios/StrangewordsTests/AppModelTests.swift` (new) | test | event-driven | `HostIsolationTests.swift` struct style; RESEARCH Pattern 5 | partial |
| `ios/StrangewordsTests/AppModelRaceTests.swift` (new) | test | event-driven | same, RESEARCH Pattern 5 | partial |
| `ios/project.yml` | config | none | no change needed (target globs `StrangewordsTests`) | n/a |

## Pattern Assignments

### `ios/Strangewords/Net/Keychain.swift` (D-01: enum to struct)

Current shape to convert (lines 12-31): `enum TokenStore` with `private static let tokenKey = "sw.participantToken"`, `sessionKey = "sw.sessionId"`, static `token`/`sessionId` get/set on `UserDefaults.standard`, and `static func clear()`. Keep key strings byte-identical and keep the header doc comment (lines 3-11).

Target (RESEARCH Pattern 1): `struct TokenStore { let defaults: UserDefaults; init(defaults: UserDefaults = .standard) }`, instance `var token`/`sessionId` with `nonmutating set`, instance `func clear()`.

Call sites to move to the instance (all in AppModel.swift, only consumer; `StrangewordsApp.swift:5` calls `AppModel()` with no args and stays unchanged): lines 60, 76, 87, 90, 99, 109, 139, 155, 188, 213, 224, 241.

### `ios/Strangewords/App/AppModel.swift` (D-01, D-03, D-06, D-07, D-08)

**Seam block to replace** (lines 46-64):
```swift
private let api: any Backend
private var pollTask: Task<Void, Never>?
private let pollInterval: Duration = .seconds(3) // [TUNABLE] plan.v1.md §10

init(backend: (any Backend)? = nil) {
    if let backend { self.api = backend }
    else if ProcessInfo.processInfo.environment["SW_LOCAL_MOCK"] == "1" {
        self.api = LocalBackend()
        TokenStore.clear()
    } else { self.api = APIClient.shared }
}
```
Becomes `init(backend:, tokenStore: TokenStore = TokenStore(), pollInterval: Duration = AppModel.defaultPollInterval)`, `pollTask`/`actionTask` as `@ObservationIgnored private(set) var`, `[TUNABLE]` comment retained on the default. The `SW_LOCAL_MOCK` branch calls `tokenStore.clear()`.

**Fire-and-forget Tasks to capture as `actionTask = Task { ... }`:** `begin` (line 73), `resume` (88), `submit` (115), `release` (140), `leave` (156).

**Post-`await` write sites needing `guard !Task.isCancelled, e == epoch` (capture `let e = epoch` first):**
- `begin` lines 75-81; `resume` lines 91-102 (incl. both catch arms); `submit` lines 118-131 (success, contentRejected, gone, notYourTurn, generic; keep `defer { submitting = false }`); `refresh` line 208.
- `pollWaiting` lines 226-229 and `pollSession` lines 243-249. Note `pollSession` line 247 `self.phase = .composing(s)` bypasses `apply()`, so only the call-site guard covers it.
- `apply()` line 188 writes `TokenStore.sessionId` first; guard BEFORE calling `apply`, not inside after.
- Bump `epoch` in `begin()`, `reset()`, `dissolve()` (lines 69, 162, 211).

Poll loop shape to preserve (lines 221-233):
```swift
pollTask = Task { [weak self] in
    while !Task.isCancelled {
        try? await Task.sleep(for: self?.pollInterval ?? .seconds(3))
        guard let self, let token = TokenStore.token else { return }
        do { ... } catch APIError.gone { self.dissolve(.noOneCame); return } catch { /* transient */ }
    }
}
```
Pitfall: `leave()` only sends `api.leave` when `sessionId` is non-nil (line 155).

### `ios/Strangewords/Net/LocalBackend.swift` (D-02, D-11)

**Delay seams** (replace line 17 `private let strangerThinkTime: TimeInterval = 1.6` and line 61 `try? await Task.sleep(for: .milliseconds(600))`): add `init(strangerThinkTime: TimeInterval = LocalBackend.defaultStrangerThinkTime, enterDelay: Duration = LocalBackend.defaultEnterDelay)`; keep `[TUNABLE]` doc comment. Skip the sleep when `enterDelay == .zero` is unnecessary (`Task.sleep(.zero)` is fine).

**Validation fix** (line 79-84 `submitLine` currently appends `text.trimmingCharacters(...)` with no checks):
```swift
guard yourTurn, line == currentLine else { return view() }   // keep; pin as drift note
lines.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
```
Insert `cleanLine` after the turn guard; on failure `throw APIError.contentRejected("line is empty" | "line exceeds maximum length" | "line contains disallowed characters")`. Port is in RESEARCH "LocalBackend vs server" (uses `unicodeScalars.count`, NFC, zero-width strip). Mark max length `[TUNABLE]` and cite `server/internal/sessions/validate.go`. Error enum precedent: `APIError.contentRejected(String)` at `APIClient.swift:8`.

**Teardown (Open Question 1):** `leave`/`dismiss` (lines 86-87) are `{}` today; recommended minimal teardown sets `status = "dissolved"`, clears `lines`, later `getSession`/`submitLine` throw `APIError.gone`, `enter` revives (it already resets state at lines 57-60).

### `ios/Strangewords/Net/APIClient.swift` (D-03)

Lines 25-36 hold `private let base: URL = {...}()` (reads `SW_API_BASE`, falls back to `https://api.strangerwords.us`) and `private let session` (ephemeral, `timeoutIntervalForRequest = 15`). Convert to `init(base: URL = APIClient.resolveBase(environment: ProcessInfo.processInfo.environment), session: URLSession = APIClient.makeDefaultSession())`. Keep `static let shared = APIClient()` (line 16). DEVIATION from D-03 text: default session must stay the ephemeral 15s session, not `URLSession.shared` (RESEARCH Pitfall 1); flag in the plan. No URLProtocol tests this phase.

### `ios/StrangewordsTests/SyllablesTests.swift` (extend, IOST-01)

**Analog:** itself, lines 1-24. Imports and style to copy:
```swift
import Testing
@testable import Strangewords

struct SyllablesTests {
    @Test(arguments: [("fire", 1), ("", 0)])
    func word(_ text: String, _ expected: Int) { #expect(Syllables.count(text) == expected) }

    @Test(arguments: [("A frog jumps into the pond", 7)])
    func haikuLine(_ text: String, _ expected: Int) { ... }
}
```
Add rows per RESEARCH table; add a separate `@Test(arguments:)` for known misses (poem/quiet/rhythm = 1, etc.) with comments as heuristic limits. Update header comment (lines 4-6) which currently says Phase 2 owns the misses.

### `SessionViewTests.swift` and `PoemNamingTests.swift` (new)

Copy the SyllablesTests struct + `@Test(arguments:)` layout. `SessionView.currentTarget` is at `Net/Models.swift:19-23` (construct `SessionView(sessionId:you:participantCount:status:form:currentLine:currentAuthor:yourTurn:lines:)` memberwise; `FormView(id:targets:)`). `PoemNaming.coin(from: [String]) -> CoinedName?` (`Naming/PoemNaming.swift:22`) returns `CoinedName` (Equatable, fields `lead`, `name`, `kind`). Goldens: capture on the simulator per RESEARCH procedure, not host values.

### `HostIsolationTests.swift` (extend, D-04)

**Analog:** itself (lines 14-24): plain `struct`, `@Test func`, `ProcessInfo.processInfo.environment` assertions. Add:
```swift
@Test func standardDefaultsHoldNoSessionKeys() {
    #expect(UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("sw.") }.isEmpty)
}
```
Note the test env sets `SW_LOCAL_MOCK=1` and `SW_API_BASE=http://127.0.0.1:9`, so tests of `APIClient` defaults must use the pure `resolveBase(environment:)`.

### `FakeBackend.swift`, `TestSupport.swift` (new)

**Analog for protocol conformance:** `Net/Backend.swift` lines 10-17 (`protocol Backend: Sendable`, six methods: `enter(pushToken:)`, `waiting(token:)`, `getSession(id:token:)`, `submitLine(id:token:line:text:idemKey:)`, `leave(id:token:) async`, `dismiss(id:token:) async`). Actor form mirrors `actor LocalBackend: Backend`. Use RESEARCH Pattern 3 (AsyncStream of parked `Pending`), with `leave`/`dismiss` recording and returning immediately, `drain()`, single-use resolve. `TestSupport.swift`: `makeIsolatedDefaults()` (RESEARCH Hygiene helper) and a `makeModel()` factory, the only way tests construct `AppModel`.

### `LocalBackendTests.swift`, `AppModelTests.swift`, `AppModelRaceTests.swift` (new)

Style: `struct`/`@Suite(.serialized)` with `@Test`, `@testable import Strangewords`, `@MainActor` for AppModel suites, `.timeLimit(.minutes(1))` on gated tests. Race skeleton: RESEARCH Pattern 5 (capture `model.pollTask` before `leave()`). Each LocalBackend test carries a doc comment like `/// Mirrors TestRoundRobinHaikuIsABA (server/internal/sessions/policy_test.go)` (D-14). Go counterparts and lines are tabulated in RESEARCH "LocalBackend vs server" (gateway_test.go:155/209/238/266, policy_test.go:5, validate_test.go:8/18/26/37/43).

Go test shape to mirror for validation cases (`validate_test.go:8-25`): accept `"  an old   silent\tpond  "` -> `"an old silent pond"`; reject `""`, `"   "`, `"\t\n"`, zero-width-only as empty.

## Shared Patterns

### Test-file conventions
**Source:** `ios/StrangewordsTests/*.swift`. Swift Testing only (`import Testing`, `@testable import Strangewords`), plain `struct` suites, `@Test`/`@Test(arguments:)`, `#expect`, doc comment at the top citing the design/phase decision. No XCTest, no third-party libs, no `Task.sleep`/`Thread.sleep` in tests.

### Isolation
Every `AppModel` in tests gets `tokenStore: TokenStore(defaults: <suite UserDefaults>)` and `pollInterval: .zero`; cleanup via `removePersistentDomain`. Hosted tests run with `SW_LOCAL_MOCK=1` (HostIsolationTests lines 15-19).

### Error mapping
**Source:** `APIClient.swift:4-11` `APIError`; AppModel catch arms (`submit` lines 122-130) switch on these cases. LocalBackend validation must throw `APIError.contentRejected(<server message>)`.

### Tunables
Keep `[TUNABLE]` markers on `pollInterval` default, `strangerThinkTime` default, the enter delay, and the new max line length.

### Project wiring
`scripts/test-ios.sh` runs `xcodegen generate`; new files under `ios/StrangewordsTests/` are picked up automatically. Red/green runs: `scripts/test-ios.sh -only-testing:StrangewordsTests/AppModelRaceTests`.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `ios/StrangewordsTests/TestSupport.swift` | test util | factory | No shared test helpers exist yet; use RESEARCH helper |
| `ios/StrangewordsTests/FakeBackend.swift` | test double | gated event-driven | No fakes exist; only the `Backend` protocol and `LocalBackend` shape |
| `AppModelTests.swift` / `AppModelRaceTests.swift` | test | async state machine | No async/main-actor tests exist; use RESEARCH Patterns 3-5 (prototype-verified) |

## Metadata

**Analog search scope:** `ios/Strangewords/{App,Net,Naming,Syllables}`, `ios/StrangewordsTests`, Go `server/internal/sessions` tests (cited via RESEARCH).
**Files scanned:** ~12 (all verified tracked via `git ls-files`).
**Pattern extraction date:** 2026-10-14
