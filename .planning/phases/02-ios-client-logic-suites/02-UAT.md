---
status: testing
phase: 02-ios-client-logic-suites
source: [02-VERIFICATION.md]
started: 2026-10-15T20:55:00Z
updated: 2026-10-15T20:55:00Z
---

## Current Test

number: 1
name: Decide on the one stale-writer write the guards missed (WR-03)
expected: |
  Either (a) fix it with a red-first race test (leave, reset, begin, new submit in
  flight, then release the OLD submit and assert `submitting` stays true), or
  (b) accept it as a follow-up via an override on the Plan 02-02 truth
  "Every write after an await ... is guarded".
awaiting: user response

## Tests

### 1. Decide on the one stale-writer write the guards missed (WR-03)
expected: `defer { submitting = false }` in AppModel.submit (AppModel.swift:143) runs for a stale submit task and is not epoch-guarded. Either fix with a red-first race test, or accept via an override on the Plan 02-02 "every write after an await is guarded" truth. The verifier judged impact low (worst effect: a briefly re-enabled button; the server's turn check absorbs a duplicate).
result: [pending]

### 2. Accept or reject the backstop truth about the session epoch
expected: Reviewer confirms the design claim the plan marks `verification: backstop` (untestable by design): the epoch is a plain Int (`private var epoch = 0`), compared for equality only (`e != epoch`), bumped once per begin() (line 87), reset() (line 194), dissolve() (line 246); overflow is not tested (needs ~2^63 actions).
result: [pending]

### 3. Decide fix-now vs Phase-4 ledger for the weak tests (WR-04, WR-06)
expected: `AppModelTests.leaveWhileWaitingSendsNoLeaveCall` (asserts before the leave task could run) and `leaveTwiceIsStable` (`count <= 1` accepts 0) tightened; `staleEnterFromPreviousAttemptIsIgnoredAfterBeginAgain` and `lateResumeResponseAfterBeginIsIgnored` use a distinct stale token and assert identity between the stale and fresh resolve — or these are deferred to the Phase 4 FIX-01 ledger as a scheduling decision.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
