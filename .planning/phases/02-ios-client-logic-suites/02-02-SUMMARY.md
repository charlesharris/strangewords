---
phase: 02-ios-client-logic-suites
plan: 02
subsystem: testing
tags: [swift-testing, appmodel, concurrency, race, epoch, fix-as-we-go, red-green]

requires:
  - phase: 02-ios-client-logic-suites
    provides: "Plan 02-01: gated FakeBackend, makeModel/Arrivals/finish helpers, AppModel pollTask/actionTask handles, injected TokenStore"
provides:
  - "AppModel session epoch plus isStale(_:) guard: no response captured under an older generation can mutate phase, draft, submitError, keepsake or either identity key"
  - "apply(_:epoch:) rejects a stale epoch before the session-id write"
  - "Seven deterministic stale-writer regression tests (AppModelRaceTests), each committed red first with the failing harness verdict in the commit body"
  - "Red/green evidence for Phase 4 FIX-01 (two findings, four SHAs)"
affects: [phase-04 verify ledger FIX-01, 02-03, 02-04]

actuals:
  tokens: 2500
  tasks: 2
  commits: 4

plan_head_before: 6a6444511d6ffb2a0b4cd1fff16cc7013f4e01fb
plan_head_after: cdcd6e93eaaed5cb7f62e769da6b57f611bfd2da

tech-stack:
  added: []
  patterns:
    - "Session epoch (plain Int, equality only) bumped in begin/reset/dissolve; every post-await writer captures it and checks isStale(e)"
    - "Capture the stale task handle BEFORE the triggering leave()/begin(), then await it: no wall-clock waits"
    - "Red-first fix-as-we-go: test commit with the failing verdict line in its body, then a separate fix commit"

key-files:
  created:
    - ios/StrangewordsTests/AppModelRaceTests.swift
  modified:
    - ios/Strangewords/App/AppModel.swift

key-decisions:
  - "Two guard layers per D-08: Task.isCancelled for cancelled poll tasks, epoch equality for action tasks that leave() never cancels"
  - "Guard placed at every write site AND as apply()'s first statement, so a stale view never reaches the session-id write"
  - "defer { submitting = false } kept: a stale submit still clears the in-flight flag (accepted assumption A5)"

patterns-established:
  - "AppModelRaceTests reuses AppModelTests.Rig through a private typealias, so the only AppModel factory stays makeModel"

requirements-completed: [IOST-04]

coverage:
  - id: D1
    description: "Leaving mid-poll: a poll response (matched, refresh, or gone) released after leave() leaves the model at .dissolved(.ended) with no token or session id on the device"
    requirement: IOST-04
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelRaceTests.swift#latePollResponseAfterLeaveDoesNotResurrect"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelRaceTests.swift#latePollRefreshAfterLeaveDoesNotResurrect"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelRaceTests.swift#lateGoneAfterLeaveKeepsEndedReason"
        status: pass
    human_judgment: false
  - id: D2
    description: "Action-task writers (submit, enter, resume) cannot resurrect a left session or overwrite a newer attempt, and a stale enter from a previous attempt is ignored while the current one applies"
    requirement: IOST-04
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelRaceTests.swift#lateSubmitResponseAfterLeaveDoesNotResurrect"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelRaceTests.swift#lateEnterResponseAfterLeaveDoesNotResurrect"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelRaceTests.swift#staleEnterFromPreviousAttemptIsIgnoredAfterBeginAgain"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelRaceTests.swift#lateResumeResponseAfterBeginIsIgnored"
        status: pass
    human_judgment: false
  - id: D3
    description: "The full iOS suite passes in seconds, with no wall-clock waits and every AppModel built with an isolated tokenStore"
    requirement: IOST-04
    verification:
      - kind: other
        ref: "scripts/test-ios.sh (40 passed, 0 failed, 1 skipped; finishTime-startTime 4.11 s)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The epoch is an equality-only Int bumped once per begin/reset/dissolve; overflow (about 2^63 user actions) is not tested"
    verification: []
    human_judgment: true
    rationale: "Backstop truth from the plan (EDGE-IOST-04-precision): confirmable only by reading the source; no test asserts it."

duration: 4min
completed: 2026-10-15
status: complete
---

# Phase 2 Plan 2: Stale-Writer Race Fix (Epoch + isCancelled) Summary

**Late-poll race reproduced red then fixed under D-08 with a session epoch plus `Task.isCancelled` guards at every post-await AppModel write, pinned by seven deterministic regression tests.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-10-15T18:20:34Z
- **Completed:** 2026-10-15T18:24:22Z
- **Tasks:** 2 (tracer, auto), both TDD
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments

- Reproduced ROADMAP success criterion 4 deterministically: a waiting-poll "matched" response released after `leave()` put the model back in `.composing` and re-wrote the session id. Same for a session-poll refresh and for a `gone` poll that overwrote `.ended` with `.noOneCame`.
- Found the race is wider than the poll loops (RESEARCH Pitfall 2): `begin`, `resume` and `submit` run in action tasks that `leave()` never cancels, so late enter, resume and submit responses resurrected state too. All four now ignored.
- `AppModel` carries a private `epoch` (bumped first in `begin()`, `reset()`, `dissolve(_:)`) and `isStale(_:)` (`Task.isCancelled || e != epoch`). Every write after an await in `begin`, `resume`, `submit`, `refresh`, `pollWaiting` and `pollSession` is guarded, including the catch arms. `apply(_:epoch:)` checks it as its first statement, before `tokenStore.sessionId` is written.
- Full suite: 40 passed, 0 failed, 1 skipped (pre-existing `HarnessCanary`); test time 4.11 s from the xcresult summary; no wall-clock waits in tests; production construction `AppModel()` unchanged.

## Task Commits

1. **Task 1 RED:** `c1075ec` (test) - three late-poll tests, all failing on their assertions
2. **Task 1 GREEN:** `d2edd92` (fix) - epoch, `isStale`, guards on the poll loops
3. **Task 2 RED:** `f9fb1d3` (test) - four action-writer tests, failing; Task 1's three still green
4. **Task 2 GREEN:** `cdcd6e9` (fix) - `apply(_:epoch:)` and guards on every action write site

**Plan metadata:** committed separately (docs: complete plan).

**Bisect note:** `c1075ec` and `f9fb1d3` are intentionally red (D-10). Skip them with `git bisect skip c1075ec f9fb1d3`.

## Fix-as-we-go ledger entries (Phase 4 FIX-01)

**Finding 1: late poll response after leave() resurrects the session and re-persists identity**
- Red SHA: `c1075ec`
- Red verdict: `test-ios: FAIL {"result":"Failed","passedTests":0,"failedTests":3,"totalTestCount":3} (xcodebuild rc=65)` (evidence `build/verify/20261015-132055`, gitignored)
- Red assertion: `model.phase == .dissolved(.ended)` observed `.composing(s1)`; `identityIsClear` observed false; `.noOneCame` instead of `.ended`
- Fix SHA: `d2edd92`
- Regression tests: `latePollResponseAfterLeaveDoesNotResurrect`, `latePollRefreshAfterLeaveDoesNotResurrect`, `lateGoneAfterLeaveKeepsEndedReason`

**Finding 2: action tasks (begin/resume/submit/refresh) write state after leave() or begin-again**
- Red SHA: `f9fb1d3`
- Red verdict: `test-ios: FAIL {"result":"Failed","passedTests":3,"failedTests":4,"totalTestCount":7} (xcodebuild rc=65)` (evidence `build/verify/20261015-132241`, gitignored)
- Red assertion: phase `.composing(s1/old)` instead of `.dissolved(.ended)` / `.connecting`; `identityIsClear` false after a late submit and a late enter
- Fix SHA: `cdcd6e9`
- Regression tests: `lateSubmitResponseAfterLeaveDoesNotResurrect`, `lateEnterResponseAfterLeaveDoesNotResurrect`, `staleEnterFromPreviousAttemptIsIgnoredAfterBeginAgain`, `lateResumeResponseAfterBeginIsIgnored`

Impact of both findings before the fix: a response that arrived after the user left could re-persist the participant token or session id on the device, so the next cold launch would try to resume a session the user ended (anonymity model: identity must not outlive the encounter).

## TDD Gate Compliance

Both tasks carry `tdd="true"`; RED and GREEN gates are present for each (`test(02-02)` precedes `fix(02-02)` in both pairs). The plan prescribes `fix` rather than `feat` for the green commits, since they repair existing behavior.

- **RED evidence (semantic assessment):** in both runs every target test executed and failed on its planned assertion (phase and identity expectations), not on compile, setup or fixture faults. Task 1: 3 of 3 targets failed. Task 2: 4 of 4 new targets failed while Task 1's 3 stayed green. Evidence is the harness verdict plus the `Expectation failed` lines in each red commit body. `gsd_run check tdd-red-evidence` was not run: the plan's own evidence contract is the verdict-line-in-commit-body, which its acceptance criteria verify. The classifier's swift-testing adapter was not exercised here.
- **GREEN:** `d2edd92` (3/3 race tests plus 21/21 `AppModelTests`), `cdcd6e9` (7/7 race tests, then the full suite 40 passed).
- **REFACTOR:** none needed.

## Files Created/Modified

- `ios/StrangewordsTests/AppModelRaceTests.swift` - seven stale-writer tests; `@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))`; reuses `AppModelTests.Rig`.
- `ios/Strangewords/App/AppModel.swift` - `epoch`, `isStale(_:)`, `apply(_:epoch:)`, `handleEnter(_:epoch:)`, `refresh(id:token:epoch:)`, and guards at every post-await write site.

## Decisions Made

- Both D-08 layers kept: `Task.isCancelled` alone is not enough because `leave()` never cancels `actionTask`; the epoch alone would not stop a cancelled poll that has already read the epoch. `isStale` combines them.
- The guard sits at each write site and again as `apply`'s first statement, so a stale view cannot reach the session-id write even from a future call site that forgets its own guard.
- `defer { submitting = false }` unchanged (assumption A5, accepted): a stale submit clears the in-flight flag; only the compose button reads it.
- The epoch is compared for equality only and bumped once per begin/reset/dissolve; overflow is not tested (backstop truth, D4 above).

## Deviations from Plan

None - plan executed exactly as written. The only choice beyond the text was reusing `AppModelTests.Rig` through a private typealias rather than duplicating it, which keeps `makeModel` the single AppModel factory.

## Issues Encountered

None. Both red runs failed on assertions at the first attempt; neither passed vacuously.

## Authentication Gates

None.

## Known Stubs

None.

## Threat Flags

None. No new network surface, auth path or schema. T-2-05 is mitigated (epoch plus `isStale` after every await, seven regression tests asserting phase and the suite-defaults identity keys). T-2-06 is mitigated (red commits touch only the test file, predate the guard, and carry the failing verdict and expectation lines; the ledger above lists the SHAs).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The expected "late-poll race" finding from STATE.md is fixed with recorded red evidence for Phase 4 FIX-01.
- `AppModel` still has untouched production construction, so plans 02-03 and 02-04 can proceed independently. Plans stay sequential because `scripts/test-ios.sh` has no lock against concurrent simulator runs.
- Carried forward from 02-01: developer to confirm the D-03 reading (ephemeral 15 s session as the `APIClient` default), and OBS-1 (a waiter who leaves is never reported to the server).

## Self-Check: PASSED

- `ios/StrangewordsTests/AppModelRaceTests.swift` and `ios/Strangewords/App/AppModel.swift` present on disk.
- Commits `c1075ec`, `d2edd92`, `f9fb1d3`, `cdcd6e9` are ancestors of HEAD, in red, green, red, green order; both red commits touch only the race test file and carry a `test-ios: FAIL` line; neither red tree contains the guard (`isStale` and `apply(_:epoch:)` absent at those SHAs).
- All task acceptance criteria re-run and passing: `epoch += 1` count 3; `isStale(e)` counts in `pollWaiting`/`pollSession` 2/2, in `begin`/`resume`/`submit` 2/4/4; the guard is `apply`'s first statement; `defer { submitting = false }` count 1; wall-clock grep and factory gate print nothing; `StrangewordsApp.swift` unchanged; `git status` clean outside `.planning`.
- Final full `scripts/test-ios.sh`: PASS (40 passed, 0 failed, 1 skipped, 41 total), 4.11 s.

---
*Phase: 02-ios-client-logic-suites*
*Completed: 2026-10-15*
