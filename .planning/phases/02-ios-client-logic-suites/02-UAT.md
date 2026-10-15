---
status: diagnosed
phase: 02-ios-client-logic-suites
source: [02-VERIFICATION.md]
started: 2026-10-15T20:55:00Z
updated: 2026-10-15T19:01:47.541Z
---

## Current Test

[testing complete]

## Tests

### 1. Decide on the one stale-writer write the guards missed (WR-03)
expected: `defer { submitting = false }` in AppModel.submit (AppModel.swift:143) runs for a stale submit task and is not epoch-guarded. Either fix with a red-first race test, or accept via an override on the Plan 02-02 "every write after an await is guarded" truth. The verifier judged impact low (worst effect: a briefly re-enabled button; the server's turn check absorbs a duplicate).
result: issue
reported: "fix it with the red-first race test"
severity: minor

### 2. Accept or reject the backstop truth about the session epoch
expected: Reviewer confirms the design claim the plan marks `verification: backstop` (untestable by design): the epoch is a plain Int (`private var epoch = 0`), compared for equality only (`e != epoch`), bumped once per begin() (line 87), reset() (line 194), dissolve() (line 246); overflow is not tested (needs ~2^63 actions).
result: pass

### 3. Decide fix-now vs Phase-4 ledger for the weak tests (WR-04, WR-06)
expected: `AppModelTests.leaveWhileWaitingSendsNoLeaveCall` (asserts before the leave task could run) and `leaveTwiceIsStable` (`count <= 1` accepts 0) tightened; `staleEnterFromPreviousAttemptIsIgnoredAfterBeginAgain` and `lateResumeResponseAfterBeginIsIgnored` use a distinct stale token and assert identity between the stale and fresh resolve — or these are deferred to the Phase 4 FIX-01 ledger as a scheduling decision.
result: issue
reported: "fix the weak tests now"
severity: minor

## Summary

total: 3
passed: 1
issues: 2
pending: 0
skipped: 0
blocked: 0

## Gaps

- gap_id: G-02-1
  truth: "No stale submit task can write AppModel state after leave/reset/begin — `defer { submitting = false }` in AppModel.submit (AppModel.swift:143) must be epoch-guarded, proven by a red-first race test (leave, reset, begin, new submit in flight, release the OLD submit, assert `submitting` stays true)"
  status: failed
  reason: "User reported: fix it with the red-first race test"
  severity: minor
  test: 1
  root_cause: "AppModel.submit (ios/Strangewords/App/AppModel.swift:134) captures `let e = epoch` at line 139 and guards its post-await `apply`/`refresh` calls, but the `defer { submitting = false }` at line 143 runs unconditionally when the stale task unwinds — it is the one write after an await not gated by the `isStale` check (AppModel.swift:301), so a stale submit task can flip `submitting` back to false after leave/reset/begin moved the epoch on"
  artifacts:
    - path: "ios/Strangewords/App/AppModel.swift"
      issue: "defer { submitting = false } at line 143 not epoch-guarded; executes for stale submit tasks"
  missing:
    - "Epoch-guard the defer (e.g. `defer { if e == epoch { submitting = false } }` or equivalent guard inside the task body)"
    - "Red-first race test in AppModelRaceTests: start a submit, leave/reset/begin so a new submit is in flight, release the OLD submit's response, assert `submitting` stays true"
  debug_session: ".planning/phases/02-ios-client-logic-suites/02-VERIFICATION.md"  # root cause established by phase verifier (WR-03); confirmed against live code, no debug agent needed

- gap_id: G-02-3
  truth: "The weak tests are tightened: `leaveWhileWaitingSendsNoLeaveCall` waits for the leave task to have had a chance to run before asserting; `leaveTwiceIsStable` asserts exactly one leave call (not `count <= 1`, which accepts 0); `staleEnterFromPreviousAttemptIsIgnoredAfterBeginAgain` and `lateResumeResponseAfterBeginIsIgnored` use a distinct stale token and assert identity between the stale and fresh resolve"
  status: failed
  reason: "User reported: fix the weak tests now"
  severity: minor
  test: 3
  root_cause: "Four tests assert too weakly to fail on the regression they exist to catch (verifier findings WR-04, WR-06): `leaveWhileWaitingSendsNoLeaveCall` (AppModelTests.swift:471) asserts before the spawned leave task could have run; `leaveTwiceIsStable` (AppModelTests.swift:486) asserts `count <= 1`, which passes when zero leave calls happen; `staleEnterFromPreviousAttemptIsIgnoredAfterBeginAgain` (AppModelRaceTests.swift:124) and `lateResumeResponseAfterBeginIsIgnored` (AppModelRaceTests.swift:151) reuse the same token for stale and fresh responses, so they cannot distinguish which resolve the model actually applied"
  artifacts:
    - path: "ios/StrangewordsTests/AppModelTests.swift"
      issue: "leaveWhileWaitingSendsNoLeaveCall asserts before the leave task runs; leaveTwiceIsStable accepts 0 calls via count <= 1"
    - path: "ios/StrangewordsTests/AppModelRaceTests.swift"
      issue: "stale-response tests use identical tokens for stale and fresh resolves, so identity of the applied response is unverified"
  missing:
    - "leaveWhileWaitingSendsNoLeaveCall: drain/await the spawned leave task before asserting no leave call was made"
    - "leaveTwiceIsStable: assert exactly one leave call (== 1), not count <= 1"
    - "staleEnterFromPreviousAttemptIsIgnoredAfterBeginAgain and lateResumeResponseAfterBeginIsIgnored: give the stale response a distinct token and assert the model holds the fresh token, proving the stale resolve was discarded"
  debug_session: ".planning/phases/02-ios-client-logic-suites/02-VERIFICATION.md"  # root cause established by phase verifier (WR-04, WR-06); confirmed against live code, no debug agent needed
