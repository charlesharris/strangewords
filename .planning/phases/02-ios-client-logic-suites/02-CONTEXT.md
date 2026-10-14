# Phase 2: iOS Client Logic Suites - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning

<domain>
## Phase Boundary

The on-device logic — syllable counting (`Syllables`), keepsake naming (`PoemNaming`), the mock backend (`LocalBackend`), and the full `AppModel` arc — is pinned by fast, deterministic Swift Testing suites that run through the Phase 1 harness (`scripts/test-ios.sh`) with no human at a simulator. Minimal test seams (IOST-05) land as defaulted init parameters with unchanged default behavior. The known late-poll race is exposed, fixed, and regression-tested here under fix-as-we-go. Requirements: IOST-01..05. Server e2e, wire fixtures, and the one-command verify belong to Phases 3 and 4.

</domain>

<decisions>
## Implementation Decisions

### Seam shape (IOST-05)
- **D-01:** `TokenStore` converts from a static enum to a **struct instance** with `init(defaults: UserDefaults = .standard)`, passed into `AppModel` as a defaulted init parameter (`tokenStore:`). All static `TokenStore.x` call sites in `AppModel` move to the instance. Real per-test isolation; no global state. — **Reversibility:** costly — touches every TokenStore call site in AppModel; reverting re-globalizes state the suites depend on isolating.
- **D-02:** `LocalBackend` gets **zero-able delay init params**: `init(strangerThinkTime: TimeInterval = 1.6, enterDelay: Duration = .milliseconds(600))` (exact labels at planner's discretion). Tests pass 0; the 1.6s pacing *feel* itself stays untested (fits "only seams justified by a specific test"). No injected clock.
- **D-03:** `AppModel(pollInterval: Duration = .seconds(3))` keeps its `[TUNABLE]` marker. `APIClient` gains `init(base: URL = <prod/SW_API_BASE>, session: URLSession = .shared)`; `.shared` stays the default instance. The URLSession seam is groundwork only — URLProtocol stub tests remain v2 (DRFT-02), do not write them this phase.
- **D-04:** Shared-container hygiene is an **executable check**: suites use suite-named `UserDefaults` (with `removePersistentDomain` cleanup), plus one explicit guard test asserting `UserDefaults.standard` holds no `sw.*` keys — extending the existing `HostIsolationTests` pattern. Satisfies success criterion 5 by proof, not convention.

### Driving async & time (IOST-04)
- **D-05:** AppModel arc tests are driven by a **test-bundle scripted `FakeBackend`** implementing the `Backend` protocol: scripted responses/errors per call, with continuation "gates" the test releases to control exactly when a response lands. `LocalBackend` stays production-pure and gets its own direct actor-level tests (IOST-03).
- **D-06:** "No real-time sleeps" is met by passing **pollInterval ≈ .zero** in tests; poll pacing then comes entirely from the fake's gates (each poll request parks until the test releases it). No sleeper-closure seam.
- **D-07:** Actions (`begin`, `submit`, `release`, `leave`, `resume`) **track their in-flight `Task`** in an internal `@ObservationIgnored private(set) var` so tests have a deterministic `await actionTask?.value` sync point. Views unaffected; production behavior unchanged.

### Late-poll race fix (fix-as-we-go)
- **D-08:** The fix is **both layers**: `Task.isCancelled` guards between each `await` and any state mutation in `pollWaiting`/`pollSession`, **plus** a session epoch/generation counter (bumped on begin/reset/dissolve) that `apply()` checks so any stale writer — poll or action — is rejected. — **Reversibility:** reversible — localized to AppModel internals; regression tests pin the behavior either way.
- **D-09:** Regression tests cover **two stale-writer scenarios**: a gated poll response released after `leave()` (the criterion-named case: session must not come back), and a gated `submitLine` response released after `leave()` (justifies the epoch guard so it isn't untested defensive code).
- **D-10:** The race fix is sequenced **red-then-green**: the regression test is written first, its failure against unfixed code is recorded (commit message / ledger note), then the fix lands turning it green. Phase 4's FIX-01 ledger gets documented evidence, not just an assertion.

### Test content & naming (IOST-01..03)
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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prior phase & harness contract
- `.planning/phases/01-clean-tree-trustworthy-ios-harness/01-CONTEXT.md` — Phase 1 locked decisions carried forward: Swift Testing, `@Suite(.serialized)` for shared state (D-10), xcresult-only verdict (D-11), host-app isolation via `SW_LOCAL_MOCK=1` (D-12)
- `scripts/test-ios.sh` — the harness these suites run through; its exit-code + evidence-dir contract must not change
- `ios/project.yml` — source of truth for the test target (`StrangewordsTests`); any target change goes here then `xcodegen generate`

### Code under test (ground truth)
- `ios/Strangewords/App/AppModel.swift` — state machine, poll loops with the late-poll race, fire-and-forget action Tasks, `pollInterval` [TUNABLE]
- `ios/Strangewords/Net/LocalBackend.swift` — mock semantics incl. current drift (no validation, ignored idemKey, no-op leave/dismiss), `strangerThinkTime` [TUNABLE]
- `ios/Strangewords/Net/Keychain.swift` — `TokenStore` (UserDefaults-backed despite filename); the D-01 conversion target
- `ios/Strangewords/Net/APIClient.swift` — base URL + `SW_API_BASE`; D-03 seam target
- `ios/Strangewords/Net/Backend.swift` — the protocol FakeBackend must implement
- `ios/Strangewords/Syllables/Syllables.swift`, `ios/Strangewords/Naming/PoemNaming.swift` — IOST-01/02 subjects
- `ios/StrangewordsTests/SyllablesTests.swift` — Phase 1 seed to grow (its comment assigns the known misses to this phase); `HostIsolationTests.swift` — pattern D-04 extends

### Server rules LocalBackend mirrors (for D-11/D-14 citations)
- `server/internal/sessions/policy_test.go` — round-robin authorship (ABA)
- `server/internal/sessions/validate.go` + `validate_test.go` — line validation rules (`CleanLine`, `MaxLineLen`, sentinel errors)
- `server/internal/gateway/gateway_test.go` — HTTP-level turn/idempotency/teardown semantics

### Planning docs
- `.planning/codebase/TESTING.md` — test conventions (note: its "no iOS test target" claim is stale post-Phase 1)
- `.planning/codebase/CONCERNS.md` — known issues incl. mock/real drift risk
- `.planning/ROADMAP.md` Phase 2 — success criteria 1–5 and the expected late-poll-race finding

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `StrangewordsTests` target + `scripts/test-ios.sh` (Phase 1): suites drop in; no harness work needed
- `SyllablesTests.swift`: parameterized `@Test(arguments:)` style already established — extend, don't replace
- `Backend` protocol: the DI seam FakeBackend plugs into; `AppModel.init(backend:)` already accepts an injected backend

### Established Patterns
- No third-party iOS deps — no swift-clocks/test libs; hand-written fakes only
- One primary type per file; wire models mirror server JSON exactly
- `[TUNABLE]` markers must survive the seam refactors (pollInterval, strangerThinkTime)
- `AppModel` is `@MainActor @Observable`; arc tests run on the main actor

### Integration Points
- `AppModel.init` grows defaulted params (`tokenStore:`, `pollInterval:`); `StrangewordsApp`/previews/`RootView` keep compiling unchanged because every new param is defaulted
- `AppModel.init`'s `SW_LOCAL_MOCK` branch calls `TokenStore.clear()` statically today — moves to the injected instance (D-01)
- `apply()` is the single choke point where the epoch guard (D-08) lands; it also writes `sessionId` via TokenStore

</code_context>

<specifics>
## Specific Ideas

- The gated-fake pattern: each FakeBackend call parks on a continuation the test explicitly releases — the test owns every poll tick and every response landing, which is what makes the stale-writer tests (D-09) deterministic.
- Success criterion 1 is a behavior-preservation check: the app built with all defaults must behave exactly as before (3s poll, 1.6s think time, 600ms enter breath, prod base URL, `.standard` defaults).

</specifics>

<deferred>
## Deferred Ideas

- **URLProtocol stub tests for APIClient** — seam (session param) lands now per D-03, tests are DRFT-02 (v2)
- **Full LocalBackend/server parity contract** (shared scenario table, drift list document) — DRFT-01 (v2); this phase only fixes AppModel-visible drift per D-11
- **Fixing the Syllables heuristic misses** — deliberate non-goal (D-12); would change the in-app nudge in a verification milestone

</deferred>

---

*Phase: 2-iOS Client Logic Suites*
*Context gathered: 2026-10-14*
