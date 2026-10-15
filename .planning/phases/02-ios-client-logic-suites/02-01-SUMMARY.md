---
phase: 02-ios-client-logic-suites
plan: 01
subsystem: testing
tags: [swift-testing, appmodel, test-seams, fake-backend, userdefaults, state-machine]

requires:
  - phase: 01-clean-tree-trustworthy-ios-harness
    provides: "scripts/test-ios.sh harness, hosted StrangewordsTests target, HostIsolationTests"
provides:
  - "TokenStore as an injectable struct over a UserDefaults instance (keys byte-identical)"
  - "AppModel(backend:tokenStore:pollInterval:) defaulted seams plus pollTask/actionTask sync handles"
  - "APIClient(base:session:) with pure resolveBase(environment:) and makeDefaultSession() defaults"
  - "Gated FakeBackend, makeModel factory, haikuView and Arrivals helpers (test support for plan 02-02)"
  - "21 AppModel tests covering the full arc, every submit error arm, polling edges, resume and leave"
  - "SeamDefaultsTests plus the UserDefaults.standard guard in HostIsolationTests"
affects: [02-02 stale-writer red-first tests, 02-03 LocalBackend seam, phase-04 verify ledger]

actuals:
  tokens: 12579
  tasks: 3
  commits: 4

plan_head_before: 8459fca1bb80752b5ad9af2a0a6d9d7eedbf8409
plan_head_after: 923ac11db7239b3c262fd34a09ef2897ff34a5df

tech-stack:
  added: []
  patterns:
    - "Gated test double: every Backend call parks on a continuation the test resolves; arrival order via AsyncStream"
    - "Deterministic async sync points: actionTask/pollTask handles, never the wall clock"
    - "One AppModel factory in tests (makeModel) always injecting a suite-named TokenStore"
    - "Pure default resolvers (resolveBase, makeDefaultSession) so defaults are testable without ProcessInfo"

key-files:
  created:
    - ios/StrangewordsTests/TestSupport.swift
    - ios/StrangewordsTests/FakeBackend.swift
    - ios/StrangewordsTests/AppModelTests.swift
    - ios/StrangewordsTests/SeamDefaultsTests.swift
  modified:
    - ios/Strangewords/Net/Keychain.swift
    - ios/Strangewords/App/AppModel.swift
    - ios/Strangewords/Net/APIClient.swift
    - ios/StrangewordsTests/HostIsolationTests.swift

key-decisions:
  - "D-03 session default interpreted as APIClient.shared plus the existing ephemeral 15 s session, not URLSession.shared (needs developer confirmation)"
  - "TDD task split into RED (test) and GREEN (feat) commits with inert APIClient stubs so RED fails on assertions, not compilation"
  - "FakeBackend fails any call made after drain() at once, so a cancelled poll loop can never re-park after cleanup"

patterns-established:
  - "Test Rig struct (defaults, fake, arrivals, model) built through makeModel; every test ends with finish()"
  - "Sync on the NEXT arrival after a non-terminal poll; await a pre-captured pollTask after a terminal one"

requirements-completed: [IOST-04, IOST-05]

coverage:
  - id: D1
    description: "TokenStore is an injectable struct; AppModel reads and writes identity only through its injected instance; key strings unchanged"
    requirement: IOST-05
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/SeamDefaultsTests.swift#tokenStoreKeysAreUnchanged"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/SeamDefaultsTests.swift#tokenStoreIsolatesSuites"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/SeamDefaultsTests.swift#tokenStoreDefaultsToStandard"
        status: pass
    human_judgment: false
  - id: D2
    description: "AppModel poll interval, APIClient base and APIClient session are defaulted init parameters whose defaults equal shipped behavior"
    requirement: IOST-05
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/SeamDefaultsTests.swift#appModelPollsEveryThreeSecondsByDefault"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/SeamDefaultsTests.swift#apiBaseDefaultsToProduction"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/SeamDefaultsTests.swift#apiClientUsesInjectedBase"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/SeamDefaultsTests.swift#defaultSessionIsEphemeralWithFifteenSecondTimeout"
        status: pass
    human_judgment: false
  - id: D3
    description: "AppModel full arc (threshold to dissolved with keepsake), submit errors, partner gone, no-one-came, resume, leave and begin-again are driven deterministically with no wall-clock waits"
    requirement: IOST-04
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelTests.swift#fullArcThroughRevealAndDissolve"
        status: pass
      - kind: unit
        ref: "scripts/test-ios.sh -only-testing:StrangewordsTests/AppModelTests"
        status: pass
    human_judgment: false
  - id: D4
    description: "No test leaves a participant token or session id in the shared UserDefaults.standard container"
    requirement: IOST-05
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/HostIsolationTests.swift#standardDefaultsHoldNoSessionKeys"
        status: pass
    human_judgment: false
  - id: D5
    description: "The D-03 reading (ephemeral 15 s session kept as the APIClient default rather than URLSession.shared) matches the developer's intent"
    verification: []
    human_judgment: true
    rationale: "CONTEXT D-03 wording is ambiguous between APIClient.shared and URLSession.shared; only the developer can confirm the intended reading (flagged assumption A4)."

duration: 9min
completed: 2026-10-15
status: complete
---

# Phase 2 Plan 1: AppModel Seams, Gated FakeBackend and Full-Arc Tests Summary

**Injectable TokenStore, defaulted AppModel/APIClient seams, a gated FakeBackend, and 21 deterministic AppModel tests covering the full arc, all green through `scripts/test-ios.sh` in 4.3 s of test time.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-10-15T18:09:26Z
- **Completed:** 2026-10-15T18:18:30Z
- **Tasks:** 3 (tracer, auto, tdd)
- **Files modified:** 8 (4 created, 4 modified)

## Accomplishments

- `TokenStore` is now a struct over an injected `UserDefaults`; `AppModel` reads and writes identity only through its instance, and the key strings are byte-identical, so installed builds keep resuming. `StrangewordsApp`'s `AppModel()` is untouched.
- `AppModel` gained `tokenStore:` and `pollInterval:` defaulted seams (`defaultPollInterval` keeps its `[TUNABLE]` marker) and observation-ignored `pollTask` / `actionTask` handles, so tests await exact sync points instead of the clock.
- A gated `FakeBackend` parks every `enter`/`waiting`/`getSession`/`submitLine` until the test releases it, records `leave`/`dismiss` without parking, and hands calls over in arrival order. With `pollInterval: .zero` the gates are the only pacing.
- 21 AppModel tests pin threshold, connecting, waiting, composing, reveal, dissolving and dissolved, plus content rejected, gone, stale-turn refetch, transport error, partner gone, no-one-came, transient poll error, resume paths, leave/reset/release idempotency and begin-again.
- `APIClient(base:session:)` landed with pure default resolvers; the default session stays the ephemeral 15 s one. `SeamDefaultsTests` proves every seam default equals shipped behavior, and `HostIsolationTests.standardDefaultsHoldNoSessionKeys` guards the shared defaults container.

## Task Commits

1. **Task 1: Tracer, injected TokenStore + gated FakeBackend + `beginMatchedLandsInComposing`** - `fe1c316` (feat)
2. **Task 2: Full AppModel arc and error arms (20 more tests)** - `3d75ad1` (test)
3. **Task 3 RED: failing defaults-preservation tests with inert APIClient stubs** - `9c85ec0` (test)
4. **Task 3 GREEN: APIClient base/session seam with unchanged defaults** - `923ac11` (feat)

**Plan metadata:** committed separately (docs: complete plan).

## TDD Gate Compliance

Task 3 carried `tdd="true"`; both gates are present.

- **RED:** `9c85ec0`. Run: `scripts/test-ios.sh -only-testing:StrangewordsTests/SeamDefaultsTests` gave `FAIL {"result":"Failed","passedTests":4,"failedTests":3,"totalTestCount":7}`. `gsd_run check tdd-red-evidence` returned `RED_EVIDENCE_OK` (format `swift-testing`, reason `target_test_failed`) for `apiBaseDefaultsToProduction`, `apiClientUsesInjectedBase` and `defaultSessionIsEphemeralWithFifteenSecondTimeout`. Evidence records are in `build/verify/red-02-01-t3/` (gitignored).
- **Semantic assessment:** each target executed and failed on its planned assertion, not on setup, import or compile faults. `resolveBase` returned `about:blank` against the production URL, the injected base read back `http://127.0.0.1:9` instead of `http://x:1`, and the session timeout was 60 s instead of 15 s. The four tests that passed on arrival (`appModelPollsEveryThreeSecondsByDefault`, `tokenStoreKeysAreUnchanged`, `tokenStoreDefaultsToStandard`, `tokenStoreIsolatesSuites`) characterize seams that already landed in Task 1, so they are not RED targets.
- **GREEN:** `923ac11`. All of `SeamDefaultsTests` passes and the full suite is green.
- **REFACTOR:** none needed.

The RED commit carries inert stubs (`resolveBase` returning `about:blank`, a `makeDefaultSession` with the default 60 s timeout, and an empty `init`) so the tests fail on assertions rather than compile errors. `APIClient.shared` kept its original stored-property initializers in that commit, so shipped behavior and the ephemeral-session posture never changed at any SHA. The GREEN commit replaced every stub.

## Files Created/Modified

- `ios/Strangewords/Net/Keychain.swift` - `TokenStore` struct over an injected `UserDefaults`; `tokenKey`/`sessionKey` internal; `nonmutating set`.
- `ios/Strangewords/App/AppModel.swift` - `defaultPollInterval`, `pollInterval`, `tokenStore` seams; `pollTask`/`actionTask` handles; all five fire-and-forget tasks stored in `actionTask`; no stale-writer protection added (plan 02-02 owns it red-first).
- `ios/Strangewords/Net/APIClient.swift` - `init(base:session:)`, `resolveBase(environment:)`, `makeDefaultSession()`; `base` now internal.
- `ios/StrangewordsTests/TestSupport.swift` - `makeIsolatedDefaults`, `makeModel` (the only AppModel factory), `haikuView`, `Arrivals`, `finish`.
- `ios/StrangewordsTests/FakeBackend.swift` - gated `actor FakeBackend: Backend` with single-use `Pending`, `recordedCalls()` and `drain()`.
- `ios/StrangewordsTests/AppModelTests.swift` - 21 tests, `@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))`.
- `ios/StrangewordsTests/SeamDefaultsTests.swift` - seven defaults-preservation tests.
- `ios/StrangewordsTests/HostIsolationTests.swift` - adds `standardDefaultsHoldNoSessionKeys`; both existing tests untouched.

## Decisions Made

- **D-03 session-default interpretation (needs developer confirmation, assumption A4).** CONTEXT D-03 writes the session default as `.shared` and says ".shared stays the default instance". This plan reads that as `APIClient.shared` (the actor singleton), and keeps the existing ephemeral, 15 s `URLSession` as the default session. A process-wide `URLSession.shared` default would change the request timeout from 15 s to 60 s and add persistent cookies and caching, which contradicts IOST-05's unchanged-behavior clause and the anonymity posture. It is reversible by changing one default argument. `defaultSessionIsEphemeralWithFifteenSecondTimeout` pins the chosen reading.
- **Full-suite test time:** the newest full-run xcresult summary (`build/verify/20261015-131652/ios-summary-1.json`) gives `finishTime - startTime` = **4.34 s** (33 passed, 1 skipped, 34 total; the skip is the pre-existing `HarnessCanary`). The gate was under 30 s.
- **TDD split into two commits.** The plan prescribed a single `feat(02-01)` commit for Task 3, but the task is `tdd="true"`, so it was split into a RED `test` and a GREEN `feat` commit as the TDD reference requires.
- **`FakeBackend.drain()` also fails later calls at once.** Without this, a cancelled poll loop that resumes after cleanup could park a fresh call that nothing ever resolves.

## Observations carried forward

- **OBS-1 (not changed):** a waiter who leaves before a match is never reported to the server. `AppModel.leave()` only calls `api.leave` when a session id is stored, and a waiter has only a token. The server has no wait-leave endpoint, so this is not fixable client-side in this phase. `leaveWhileWaitingSendsNoLeaveCall` pins today's behavior with a comment. Carry it to Phase 4's ledger as a documented observation.
- **No fix-as-we-go AppModel defects surfaced.** No test exposed a real AppModel bug, so there is no new regression test. The one known defect (a late write after `leave()`) is deliberately left for plan 02-02.
- **Mutation spot-check:** changing the `pollSession` gone-arm from `.partnerLeft` to `.ended` made exactly one `AppModelTests` test fail (20 passed, 1 failed). The change was reverted and not committed, which confirms the suite is not vacuous.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `Arrivals` cannot be main-actor isolated**
- **Found during:** Task 1
- **Issue:** advancing `AsyncStream.AsyncIterator` is a mutating async call, which Swift rejects on actor-isolated storage (`cannot call mutating async function 'next()' on actor-isolated property 'iterator'`).
- **Fix:** made `Arrivals` a plain `final class ... @unchecked Sendable` with a doc comment explaining why. Only one test task awaits it at a time.
- **Files modified:** `ios/StrangewordsTests/TestSupport.swift`
- **Verification:** `AppModelTests` and the full suite pass.
- **Committed in:** `fe1c316`

**2. [Rule 3 - Blocking] Test-side isolation fixes**
- **Found during:** Tasks 2 and 3
- **Issue:** the nested `Rig` struct does not inherit `@MainActor` from the suite (compile errors calling `makeModel`), and reading the actor property `APIClient.base` across modules needs `await`.
- **Fix:** annotated `Rig` with `@MainActor`; made `apiClientUsesInjectedBase` `async` and read `await client.base`.
- **Files modified:** `ios/StrangewordsTests/AppModelTests.swift`, `ios/StrangewordsTests/SeamDefaultsTests.swift`
- **Verification:** compile errors cleared; suites green.
- **Committed in:** `3d75ad1`, `9c85ec0`

**3. [Rule 2 - Missing Critical] `FakeBackend` rejects calls after `drain()`**
- **Found during:** Task 1 (design review of Pitfall 7)
- **Issue:** with `pollInterval: .zero`, a cancelled poll loop can resume after cleanup and park a new call nothing resolves, leaking a task that holds the model.
- **Fix:** `drain()` sets a flag; later calls throw `CancellationError` immediately.
- **Files modified:** `ios/StrangewordsTests/FakeBackend.swift`
- **Committed in:** `fe1c316`

**4. [Process] Task 3 committed as RED then GREEN instead of one `feat` commit**
- **Reason:** `tdd="true"` plus the TDD reference's commit-scope contract. See "TDD Gate Compliance". The final state matches the plan's acceptance criteria.

---

**Total deviations:** 3 auto-fixed (2 blocking, 1 missing-critical) and 1 process adjustment.
**Impact on plan:** all test-side. Production behavior is byte-for-byte unchanged apart from the planned seams; no scope creep.

## Issues Encountered

None beyond the compile-time isolation fixes above.

## Authentication Gates

None.

## Known Stubs

None. The inert RED stubs in `APIClient.swift` existed only in commit `9c85ec0` and were replaced in `923ac11`.

## Threat Flags

None. No new network surface, auth path or trust-boundary schema. The plan's mitigations hold: T-2-01 via `makeModel`, the factory grep gate and the `standardDefaultsHoldNoSessionKeys` guard; T-2-02 via the pinned ephemeral 15 s session; T-2-03 via `SeamDefaultsTests` and an untouched `StrangewordsApp.swift`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 02-02 can write its stale-writer tests red-first on this FakeBackend, `pollTask`/`actionTask` handles and `TestSupport`. `AppModel.swift` has exactly two `isCancelled` lines (the pre-existing poll-loop conditions), so a genuine red run is still possible.
- Plans run sequentially because `scripts/test-ios.sh` has no lock against concurrent simulator runs.
- Developer to confirm the D-03 reading (ephemeral 15 s session as the `APIClient` default).

## Self-Check: PASSED

- Created and modified files all present on disk (8 of 8).
- Task commits `fe1c316`, `3d75ad1`, `9c85ec0`, `923ac11` are ancestors of HEAD; `check evaluation-scope --plan 02-01 --commits-only` resolves all four.
- Acceptance criteria for all three tasks re-run and passing; the factory gate, the no-sleep grep and the `UserDefaults.standard` write grep print nothing.
- Final `scripts/test-ios.sh` verdict: `PASS` (33 passed, 0 failed, 1 skipped, 34 total).

---
*Phase: 02-ios-client-logic-suites*
*Completed: 2026-10-15*
