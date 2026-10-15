---
phase: 02-ios-client-logic-suites
verified: 2026-10-15T20:50:00Z
status: human_needed
score: 6/8 must-haves verified
covered_files:
  - ".planning/phases/02-ios-client-logic-suites/02-01-PLAN.md"
  - ".planning/phases/02-ios-client-logic-suites/02-01-SUMMARY.md"
  - ".planning/phases/02-ios-client-logic-suites/02-02-PLAN.md"
  - ".planning/phases/02-ios-client-logic-suites/02-02-SUMMARY.md"
  - ".planning/phases/02-ios-client-logic-suites/02-03-PLAN.md"
  - ".planning/phases/02-ios-client-logic-suites/02-03-SUMMARY.md"
  - ".planning/phases/02-ios-client-logic-suites/02-04-PLAN.md"
  - ".planning/phases/02-ios-client-logic-suites/02-04-SUMMARY.md"
  - "ios/Strangewords/App/AppModel.swift"
  - "ios/Strangewords/Net/APIClient.swift"
  - "ios/Strangewords/Net/Keychain.swift"
  - "ios/Strangewords/Net/LocalBackend.swift"
  - "ios/StrangewordsTests/AppModelRaceTests.swift"
  - "ios/StrangewordsTests/AppModelTests.swift"
  - "ios/StrangewordsTests/FakeBackend.swift"
  - "ios/StrangewordsTests/HostIsolationTests.swift"
  - "ios/StrangewordsTests/LocalBackendTests.swift"
  - "ios/StrangewordsTests/PoemNamingTests.swift"
  - "ios/StrangewordsTests/SeamDefaultsTests.swift"
  - "ios/StrangewordsTests/SessionViewTests.swift"
  - "ios/StrangewordsTests/SyllablesTests.swift"
  - "ios/StrangewordsTests/TestSupport.swift"
covered_digest: "v3:sha256:16e56e8c869f876156745b142d4bf767a177d649e62e9b6ce2b3d23006bbc77c"
behavior_unverified: 1
overrides_applied: 0
behavior_unverified_items:
  - truth: "Plan 02-02: every write after an await in begin, resume, submit, refresh, pollWaiting and pollSession is guarded by Task.isCancelled plus the epoch (D-08, both layers)"
    test: "Start begin(), resume() and submit(), then leave() (or begin-again) while the request is in flight, and fail the parked request with transport / gone / contentRejected / notYourTurn instead of resolving it successfully"
    expected: "Phase, draft, submitError, keepsake and both identity keys stay exactly as leave() left them; `submitting` also stays correct for any newer submit"
    why_human: "The guards are present on every catch arm (read in AppModel.swift:98-102, 122-128, 150-162, 241-243), but AppModelRaceTests only drives the success arms (poll matched / refresh / gone, submit success, enter success, resume success). No test exercises a stale FAILURE arm or a stale refresh, so presence of the guard is the only evidence."
coincidental_reliance_items:
  - truth: "Roadmap SC5: no test leaves a token behind in the app's shared UserDefaults container"
    reason: incidental-ordering
    harden: "HostIsolationTests.standardDefaultsHoldNoSessionKeys only sees a leak if it runs AFTER the leaking test; Swift Testing runs suites in parallel and in no fixed order, and nothing enforces that order. The real mechanism is that makeModel is the only AppModel factory in tests (verified by grep), which is why the truth holds. Consider making the guard order-independent (for example assert after each suite) or documenting that makeModel, not the guard, is the enforcement."
human_verification:
  - test: "Decide on the one stale-writer write the guards missed: `defer { submitting = false }` in AppModel.submit (AppModel.swift:143) runs for a stale submit task and is not epoch-guarded (review WR-03)"
    expected: "Either (a) fix it with a red-first race test (leave, reset, begin, new submit in flight, then release the OLD submit and assert `submitting` stays true), or (b) accept it as a follow-up via an override on the Plan 02-02 truth 'Every write after an await ... is guarded'"
    why_human: "The literal plan truth 'every write after an await is guarded' is false for exactly this one UI flag. The truth's own edge clause (phase, draft, submitError, keepsake, identity keys never mutated) does hold, the sequence needs a request that outlives leave + reset + begin + match + a second submit, and the worst effect is a briefly re-enabled button (the server's turn check absorbs a duplicate). Whether that is a gap or an accepted residual is a product call, not a grep result."
  - test: "Accept or reject the non-inferable Plan 02-02 truth marked `verification: backstop`: 'the epoch is a plain Int compared for equality only, never ordered, bumped once per begin/reset/dissolve; overflow is not tested'"
    expected: "Reviewer confirms the design claim (observed in code: `private var epoch = 0`, only `e != epoch` comparisons, increments only in begin() at line 87, reset() at 194, dissolve() at 246)"
    why_human: "The plan marks this truth as backstop (no test can exist by design, overflow needs about 2^63 actions). The verifier abstains on backstop truths absent a wired held-out test, so it routes to a human even though the code reads correctly."
  - test: "Decide whether to strengthen two tests that cannot fail for the regression they name, and two race tests that cannot see a stale token write (review WR-04, WR-06)"
    expected: "AppModelTests.leaveWhileWaitingSendsNoLeaveCall (reads recordedCalls without awaiting actionTask, lines 471-484) and leaveTwiceIsStable (`count <= 1` accepts 0, line 496) tightened; staleEnterFromPreviousAttemptIsIgnoredAfterBeginAgain and lateResumeResponseAfterBeginIsIgnored (AppModelRaceTests.swift:124-174) use a distinct stale token and assert identity between the stale and fresh resolve"
    why_human: "These do not break the roadmap contract (the leave-mid-poll tests do assert identityIsClear and are proven red-then-green), but they weaken the 'catch regressions' half of the phase goal at the margin. Fix now vs defer to the Phase 4 ledger is a scheduling decision."
---

# Phase 2: iOS Client Logic Suites Verification Report

**Phase Goal:** The on-device logic (syllable counting, keepsake naming, the mock backend, and the full AppModel arc) is pinned by fast, deterministic unit tests that catch regressions without a human at a simulator
**Verified:** 2026-10-15T20:50:00Z
**Status:** human_needed
**Re-verification:** No, initial verification

## Verdict in one paragraph

The phase goal is achieved. All five ROADMAP success criteria and all five requirements (IOST-01 to IOST-05) are backed by code and by a green suite that I re-ran myself, not by SUMMARY claims. I found no failed must-have and no blocker. Status is `human_needed` rather than `passed` because three items need a human call: one plan-level truth that is literally false by one unguarded write (`submitting`), one truth the plan itself marks as untestable (`backstop`), and a set of known test-strength weaknesses from the code review. None of them contradict a roadmap success criterion.

## Goal Achievement

### Observable Truths

| #   | Truth | Status | Evidence |
| --- | ----- | ------ | -------- |
| 1 | SC1: poll interval, mock delays, API base and TokenStore container are injectable as defaulted init parameters; the app built with defaults behaves as before | ✓ VERIFIED | `AppModel.init(backend:tokenStore:pollInterval:)` (AppModel.swift:65), `LocalBackend.init(strangerThinkTime:enterDelay:)` (LocalBackend.swift:45), `APIClient.init(base:session:)` (APIClient.swift:24), `TokenStore.init(defaults: = .standard)` (Keychain.swift:22). `git diff 8459fca HEAD` shows `StrangewordsApp.swift` untouched (the only production `AppModel()` site). Pre-phase code had `.seconds(3)`, `1.6`, `.milliseconds(600)`, ephemeral session with 15 s timeout, `SW_API_BASE` override; post-phase defaults are identical (`defaultPollInterval = .seconds(3)`, `defaultStrangerThinkTime = 1.6`, `defaultEnterDelay = .milliseconds(600)`, `makeDefaultSession()` still `.ephemeral` + 15 s). `SeamDefaultsTests` and `LocalBackendTests.defaultsMatchShippedPacing` pin each default. |
| 2 | SC2: Syllables table tests and PoemNaming goldens pass, and changing the heuristic, hash or PRNG makes a named test fail | ✓ VERIFIED | `SyllablesTests` (word / knownMiss / haikuLine tables), `PoemNamingTests.golden` (6 poems), `SessionViewTests` (5/7/5). Mutation evidence is on disk and I read it: `build/verify/02-04-mut-fnv`, `02-04-mut-splitmix` both `Failed` on `golden(_:)`; `02-04-mut-vowels` `Failed` on `word(_:_:)`. `git diff 8459fca HEAD -- ios/Strangewords/Syllables ios/Strangewords/Naming` is empty (no behavior changed to pass a test). |
| 3 | SC3: LocalBackend tests pass for pairing, round-robin, validation/rejection, idempotent resubmit and teardown, each mirroring a named server rule | ✓ VERIFIED | `LocalBackendTests` (18 tests) each cite a Go test by name and file. I compared `LocalBackend.cleanLine` to the rules in `server/internal/sessions/validate.go` (NFC, control reject except tab/CR/LF, zero-width strip, whitespace collapse, trim, empty, 100-scalar cap) and they match. Red-first history is in git (`9a95223` red 9 failed, `1b6e655` green; `8e51c35` red 2 failed, `5bfe873` green). Idempotent resubmit and wrong-turn are pinned as documented DRIFT (mock returns the current view where the server replays or answers 409), a deliberate D-11 decision, not a silent pass. |
| 4 | SC4: AppModel tests drive the full arc plus submit errors, partner-gone, begin-again and leaving mid-poll, where a late poll response does not bring the session back | ✓ VERIFIED | `fullArcThroughRevealAndDissolve` asserts every phase and the exact backend call sequence `[.enter,.submitLine,.getSession,.getSession,.submitLine,.dismiss]`; `submit*` error tests, `partnerGoneWhileWaitingForTheirLine`, `waitEndsWithNoOneCame`, `beginAgainStartsAFreshAttempt`, resume paths. `latePollResponseAfterLeaveDoesNotResurrect` captures `pollTask` before `leave()`, releases a gated "matched" afterwards and asserts `.dissolved(.ended)` plus both identity keys absent. Behavioral proof: `c1075ec` committed it red (3 failed, resurrected `.composing`), `d2edd92` green. Same for the action layer (`f9fb1d3` red 4 failed, `cdcd6e9` green). The guard is real in code: `isStale` (AppModel.swift:300) checked after every awaited call in both poll loops and before the session-id write in `apply`. |
| 5 | SC5: the whole suite finishes in seconds with no real-time sleeps, and no test leaves a token in the shared UserDefaults container | ✓ VERIFIED (coincidental-reliance) | My fresh run: `test-ios: PASS {"passedTests":67,"failedTests":0,"skippedTests":1,"totalTestCount":68}`, evidence `build/verify/20261015-134619`; orchestrator's run `20261015-133924` shows the same line and a 4.8 s test duration. `grep` for `sleep`, `Date()`, `ContinuousClock` in `ios/StrangewordsTests` finds nothing. Only `makeModel` and one deliberate `SeamDefaultsTests` call construct `AppModel`, both with a suite-named `TokenStore`. `HostIsolationTests` also passes alone (`-only-testing`, run `20261015-134729`, 3/3). The single skip is the intentional `HarnessCanary`. Caveat recorded in `coincidental_reliance_items`: the standard-defaults guard is order-dependent. |
| 6 | Plan 02-02: every write after an await in begin, resume, submit, refresh, pollWaiting and pollSession is guarded by `Task.isCancelled` plus the epoch; the epoch bumps in begin/reset/dissolve; `apply` rejects a stale epoch before the session-id write | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Present and wired: `apply` guard is its first statement (line 216), epoch bumps at 87/194/246, every catch arm in begin/resume/submit/pollWaiting/pollSession has `guard !isStale(e)`. Two limits. (1) Only success-arm races are exercised by tests; stale failure arms and stale `refresh` are not. (2) The literal "every write" is false for `defer { submitting = false }` (line 143), see Human Verification item 1. Not FAILED because the truth's own edge clause (phase, draft, submitError, keepsake, identity never mutated by a stale writer) holds for every path the tests drive and by reading for the rest. |
| 7 | Plan 02-02 (backstop): epoch is a plain Int compared for equality only, bumped once per begin/reset/dissolve; overflow not tested | ? UNCERTAIN (insufficient_spec) | Code reading agrees (`private var epoch = 0`; only `e != epoch`; three increments). The plan classes this as `verification: backstop`, so no test can exist by design and I abstain. Routed to Human Verification item 2. |
| 8 | Plan 02-03: in mock mode an AppModel submitting a zero-width-only line shows submitError "line is empty" and stays composing | ✓ VERIFIED | `mockModeSurfacesServerRejectionMessage` drives `AppModel` over a real `LocalBackend(strangerThinkTime: 0, enterDelay: .zero)` and asserts the message and `.composing`. Red in `9a95223`, green in `1b6e655`. |

**Score:** 6/8 truths verified (1 present, behavior-unverified; 1 backstop abstained)

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `ios/Strangewords/Net/Keychain.swift` | injectable `TokenStore` struct, keys byte-identical | ✓ VERIFIED | `init(defaults: UserDefaults = .standard)`, keys `sw.participantToken` / `sw.sessionId` (pinned by `tokenStoreKeysAreUnchanged`) |
| `ios/Strangewords/App/AppModel.swift` | defaulted seams, `actionTask`/`pollTask` handles, epoch guard | ✓ VERIFIED | `@ObservationIgnored private(set) var actionTask`, `isStale`, `apply(_:epoch:)` all present and used |
| `ios/Strangewords/Net/APIClient.swift` | `init(base:session:)`, pure `resolveBase(environment:)` | ✓ VERIFIED | present, ephemeral 15 s default retained |
| `ios/Strangewords/Net/LocalBackend.swift` | zero-able delays, `cleanLine` port, teardown | ✓ VERIFIED | `static func cleanLine(`, `dissolve()` erases lines |
| `ios/StrangewordsTests/TestSupport.swift` | `makeModel`, `makeIsolatedDefaults`, `haikuView`, `finish` | ✓ VERIFIED | `makeModel` always injects suite store and `.zero` poll |
| `ios/StrangewordsTests/FakeBackend.swift` | gated `actor FakeBackend: Backend` | ✓ VERIFIED | parks enter/waiting/getSession/submitLine; records leave/dismiss |
| `ios/StrangewordsTests/AppModelTests.swift` | full-arc suite | ✓ VERIFIED | 21 tests, contains `beginMatchedLandsInComposing` |
| `ios/StrangewordsTests/AppModelRaceTests.swift` | stale-writer tests | ✓ VERIFIED | 7 tests, contains `latePollResponseAfterLeaveDoesNotResurrect` |
| `ios/StrangewordsTests/SeamDefaultsTests.swift`, `HostIsolationTests.swift` | defaults proof, standard-defaults guard | ✓ VERIFIED | present, pass in full and isolated runs |
| `ios/StrangewordsTests/LocalBackendTests.swift`, `PoemNamingTests.swift`, `SyllablesTests.swift`, `SessionViewTests.swift` | per plans 03 and 04 | ✓ VERIFIED | all present and substantive (see truths 2 and 3) |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| AppModel | TokenStore | injected `tokenStore` instance | WIRED | every identity read/write goes through `tokenStore.` (no static access remains) |
| `makeModel` | AppModel | `pollInterval: .zero` + suite `TokenStore` | WIRED | TestSupport.swift:20 |
| FakeBackend | Backend protocol | `actor FakeBackend: Backend` | WIRED | compiles and drives all AppModel tests |
| StrangewordsApp | AppModel | `AppModel()` with all seams defaulted | WIRED | file unchanged since phase start |
| AppModel (mock branch) | LocalBackend | `LocalBackend()` defaulted | WIRED | AppModel.swift:73 |
| `apply` | `tokenStore.sessionId` | epoch check before the write | WIRED | AppModel.swift:216 before 222 |
| LocalBackend.submitLine | `cleanLine` | rejects as `APIError.contentRejected` | WIRED | LocalBackend.swift:100 |

### Data-Flow Trace (Level 4)

Not applicable: this phase adds tests and injection seams, no new rendered dynamic data. The one user-visible data path, mock-mode `submitError`, was traced from `LocalBackend.cleanLine` through `AppModel.submit`'s `contentRejected` arm to `submitError` and is exercised by truth 8.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Whole iOS suite, fresh run | `./scripts/test-ios.sh` | `PASS passed 67, failed 0, skipped 1, total 68` (`build/verify/20261015-134619`) | ✓ PASS |
| Host isolation guard alone | `./scripts/test-ios.sh -only-testing:StrangewordsTests/HostIsolationTests` | `PASS 3/3` (`build/verify/20261015-134729`) | ✓ PASS |
| Hash / PRNG / heuristic mutation each fail a named test | read `build/verify/02-04-mut-*/ios-summary-1.json` | `Failed` on `golden(_:)` x2 and `word(_:_:)` | ✓ PASS |
| Red-then-green history for each fix | `git show` bodies of `c1075ec`, `d2edd92`, `f9fb1d3`, `cdcd6e9`, `9a95223`, `1b6e655`, `8e51c35`, `5bfe873` | Red commits carry `test-ios: FAIL` lines with the failing expectation; fix commits carry `PASS` | ✓ PASS |
| Go side untouched | `git diff --stat 8459fca HEAD -- server` | empty | ✓ PASS (Go suites out of this phase's scope; orchestrator reported them green) |

### Probe Execution

Step 7c: SKIPPED. No PLAN declares a `probe-*.sh`, and there is no `scripts/*/tests/probe-*.sh`.

### Requirements Coverage

Plan frontmatter IDs: 02-01 `[IOST-04, IOST-05]`, 02-02 `[IOST-04]`, 02-03 `[IOST-03, IOST-05]`, 02-04 `[IOST-01, IOST-02]`. Union is IOST-01 to IOST-05, matching REQUIREMENTS.md's Phase 2 rows exactly. No orphaned requirement.

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| IOST-01 | 02-04 | Syllables table-driven characterization incl. 5/7/5 | ✓ SATISFIED | `SyllablesTests`, `SessionViewTests`, vowel-set mutation fails `word(_:_:)` |
| IOST-02 | 02-04 | PoemNaming goldens, hash/PRNG stability | ✓ SATISFIED | `PoemNamingTests.golden` x6, FNV and SplitMix mutations fail it |
| IOST-03 | 02-03 | LocalBackend semantics mirror server rules | ✓ SATISFIED | `LocalBackendTests`, with resubmit and wrong-turn as documented DRIFT |
| IOST-04 | 02-01, 02-02 | AppModel full arc, errors, partner-gone, begin-again, no real-time sleeps | ✓ SATISFIED | `AppModelTests`, `AppModelRaceTests`; no sleep or clock calls in the test target |
| IOST-05 | 02-01, 02-03 | Defaulted seams (poll interval, mock delays, API base, TokenStore defaults) with unchanged behavior | ✓ SATISFIED | all four seams present; defaults diffed against pre-phase code and pinned by tests |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (all phase files) | - | `TBD` / `FIXME` / `XXX` / `TODO` / `HACK` / placeholder | none | grep found none |
| `ios/Strangewords/App/AppModel.swift` | 143 | `defer { submitting = false }` not epoch-guarded | ⚠️ Warning | see Human Verification 1 (review WR-03) |
| `ios/Strangewords/App/AppModel.swift` | 241-243 | `refresh` uses `try?`, swallowing `.gone` after a 409 | ⚠️ Warning | pre-existing behavior, review WR-08, not a phase must-have |
| `ios/Strangewords/App/AppModel.swift` | 86-104 | `begin()` does not clear stale `submitError` or `sessionId` | ⚠️ Warning | pre-existing behavior, review WR-01/WR-02, not a phase must-have |
| `ios/StrangewordsTests/AppModelTests.swift` | 471-501 | two tests that cannot fail for their stated regression | ⚠️ Warning | Human Verification 3 (review WR-04) |
| `ios/StrangewordsTests/AppModelRaceTests.swift` | 124-174 | stale-token write indistinguishable from fresh | ⚠️ Warning | Human Verification 3 (review WR-06) |

The 02-REVIEW findings (0 critical, 8 warning, 5 info, all `open` in `02-REVIEW-DISPOSITION.md`) are consistent with what I found by reading the code. WR-01, WR-02 and WR-08 describe latent bugs in production AppModel behavior that predate this phase; they are outside the Phase 2 goal (a test baseline) and belong in the Phase 4 FIX-01 ledger. Nothing in the review contradicts a roadmap success criterion.

### Human Verification Required

#### 1. The one unguarded post-await write (`submitting`)

**Test:** Decide fix-now or accept. To fix: add a race test (submit in flight, `leave()`, `reset()`, `begin()` to a fresh composing session, second `submit()`, then release the OLD submit and assert `submitting` is still true), written red first per D-10, then guard the `defer`.
**Expected:** `submitting` stays true until the newer submit completes.
**Why human:** Plan 02-02 asserts every post-await write is guarded; this one is not. It is low severity (needs a request outliving leave, reset, begin, match and a second submit; the server's turn check absorbs a duplicate) so the call is yours. If you accept it, add to this file's frontmatter:

```yaml
overrides:
  - must_have: "Every write after an await in begin, resume, submit, refresh, pollWaiting, and pollSession is guarded by Task.isCancelled plus the epoch"
    reason: "submitting reset in submit's defer is unguarded (review WR-03); tracked for the Phase 4 FIX-01 ledger, low severity"
    accepted_by: "{name}"
    accepted_at: "{ISO timestamp}"
```

#### 2. Backstop truth about the epoch counter

**Test:** Read AppModel.swift lines 59, 87, 194, 246, 300 and confirm the epoch is a plain `Int`, only compared with `!=`, and bumped once in each of begin/reset/dissolve.
**Expected:** Matches the plan's description.
**Why human:** Marked `verification: backstop` in the plan; the verifier does not self-certify non-inferable truths.

#### 3. Test-strength weaknesses at the margin

**Test:** Decide whether to tighten `leaveWhileWaitingSendsNoLeaveCall` (await `actionTask` before reading calls), `leaveTwiceIsStable` (`== 1`), and the two begin-again race tests (distinct stale token, identity assertion between stale and fresh resolve), or defer to Phase 4.
**Expected:** Each test can fail for the regression it names.
**Why human:** These do not break any roadmap criterion, but they are the part of "catches regressions" that is weakest today.

### Gaps Summary

No gaps. Nothing is missing, stubbed or unwired, and no must-have FAILED. The roadmap contract (SC1 to SC5) and all five requirement IDs are met by code I read and a suite I ran. Status is `human_needed` solely because of the three decisions above, which the verification rules do not let me absorb into `passed`. Carry-overs for the Phase 4 ledger: WR-01, WR-02, WR-08 (production AppModel behavior), IN-02 (server has no cancel-wait endpoint, so a waiter who backs out leaves a ghost), and the PoemNaming toolchain-drift caveat (goldens captured on iOS 18.6 only).

---

_Verified: 2026-10-15T20:50:00Z_
_Verifier: Claude (gsd-verifier)_
