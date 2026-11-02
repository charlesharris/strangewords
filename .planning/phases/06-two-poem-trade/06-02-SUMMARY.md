---
phase: 06-two-poem-trade
plan: 02
subsystem: ios-client
tags: [swift, swiftui, swift-testing, observation, polling, mock-backend, privacy]

requires:
  - phase: 06-two-poem-trade
    provides: "Plan 01 wire contract: POST /v1/session/{id}/trade, the four omitempty View keys, 409 trade_closed and 503 busy"
provides:
  - "SessionView tolerant decode of poemNumber, tradeOpen, youWantTrade, partnerWantsTrade (old server decodes as poem 1, all false)"
  - "Backend.tradeBack(id:token:) in the protocol, APIClient, LocalBackend and FakeBackend"
  - "LocalBackend mock trade arc: stranger offers after its think time, roles swap into poem 2, robot poet accepts but never offers"
  - "AppModel.tradeBack(), a reveal poll that runs only while the server says tradeOpen, closeTrade, and a release() that ends the generation"
affects: [06-03-ios-keepsakes-and-reveal-ui, ship, testflight]

actuals:
  tokens: 10986
  tasks: 3
  commits: 6

plan_head_before: 88924696454a696afcbd82b05c7b51081cd4dde4
plan_head_after: 2e3bd8d61f5953f8da3876413f242a8c2c070506
commits: 6

tech-stack:
  added: []
  patterns:
    - "Trade state is server-derived only: the client never infers tradeOpen; absent keys decode as closed"
    - "A trade transition stays inside the current epoch (same session, same token); release() now bumps the epoch"
    - "Mock mirrors the server arc with one pacing knob (strangerThinkTime); no new TUNABLE"

key-files:
  created:
    - ios/StrangewordsTests/AppModelTradeTests.swift
  modified:
    - ios/Strangewords/Net/Models.swift
    - ios/Strangewords/Net/Backend.swift
    - ios/Strangewords/Net/APIClient.swift
    - ios/Strangewords/Net/LocalBackend.swift
    - ios/Strangewords/App/AppModel.swift
    - ios/StrangewordsTests/FakeBackend.swift
    - ios/StrangewordsTests/TestSupport.swift
    - ios/StrangewordsTests/LocalBackendTests.swift
    - ios/StrangewordsTests/SessionViewTests.swift
    - ios/StrangewordsTests/AppModelRaceTests.swift

key-decisions:
  - "tradeBack returns the updated SessionView and throws, like submitLine; the server's 409 trade_closed maps to the existing APIError.wrongTurn, so no new error case"
  - "A 410 at the reveal closes the trade but keeps the poem on screen; let it go still plays the dissolution as today"
  - "release() bumps the epoch and stops polling, so no late reveal writer can pull the model back from dissolving"
  - "The mock human stranger always offers at poem 1's reveal after its think time (recorded as DRIFT)"

patterns-established:
  - "Negative AppModel assertions compare actionTask to its prior value instead of reading recordedCalls, so they cannot race a call still on its way"
  - "RED for a multi-arrival AppModel test needs a naive scaffold: a bare no-op stub makes every test park on a missing arrival until the 60 s time limit"

requirements-completed: [P6-TRADE, P6-ROLES, P6-COMPAT, P6-PARITY, P6-TESTS]

coverage:
  - id: D1
    description: "SessionView decodes the four trade fields when present and defaults them (poem 1, all false) when absent, so an old server never shows a trade"
    requirement: "P6-COMPAT"
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/SessionViewTests.swift#decodesTradeFieldsWhenPresent"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/SessionViewTests.swift#tradeFieldsDefaultWhenAbsent"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/SessionViewTests.swift#memberwiseDefaultsTradeFields"
        status: pass
    human_judgment: false
  - id: D2
    description: "Backend.tradeBack is a protocol requirement implemented by APIClient (POST /v1/session/{id}/trade), LocalBackend and FakeBackend with no defaulted variant"
    requirement: "P6-PARITY"
    verification:
      - kind: other
        ref: "grep gate: tradeBack signature present in Backend, APIClient, LocalBackend, FakeBackend; the app target compiles"
        status: pass
    human_judgment: false
  - id: D3
    description: "Mock mode walks the full arc: offer after think time, tradeBack begins poem 2 with roles swapped and 5-syllable stranger lines, poem 2's reveal is closed, a closed trade throws wrongTurn, the robot poet accepts but never offers"
    requirement: "P6-ROLES"
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/LocalBackendTests.swift#tradeBackSwapsRolesIntoPoemTwo"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/LocalBackendTests.swift#robotPoetAcceptsButNeverOffers"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/LocalBackendTests.swift#yourOfferIsAcceptedOnTheNextPoll"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/LocalBackendTests.swift#tradeBackOutsideAnOpenTradeIsRejected"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/LocalBackendTests.swift#repeatTradeBackIsIdempotent"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/LocalBackendTests.swift#enterAfterATradeStartsFreshAtPoemOne"
        status: pass
    human_judgment: false
  - id: D4
    description: "AppModel trades back only from an open, unasked reveal; follows the partner's answer by polling only while the server says tradeOpen; a declined, closed or lapsed trade leaves the poem on the reveal"
    requirement: "P6-TRADE"
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelTradeTests.swift (9 tests, suite passes)"
        status: pass
    human_judgment: false
  - id: D5
    description: "A reveal poll or tradeBack response landing after release() cannot pull the model back from dissolving; both guards proven load-bearing by mutation"
    requirement: "P6-TESTS"
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelRaceTests.swift#revealPollLandingAfterReleaseIsIgnored"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelRaceTests.swift#tradeResponseLandingAfterReleaseIsIgnored"
        status: pass
    human_judgment: false
  - id: D6
    description: "Mock mode (./run.sh --mock) walks the trade arc with a feel the user would approve; the Reveal affordance that renders it is Plan 03"
    verification: []
    human_judgment: true
    rationale: "Pacing and feel of the mock trade on a simulator is not asserted by any test; the milestone is automated-only, so the manual check is recorded for UAT, not performed"

duration: 63min
completed: 2026-11-02
status: complete
---

# Phase 6 Plan 02: Two-Poem Trade, iOS Client Contract Summary

**SessionView decodes Plan 01's trade fields tolerantly, Backend.tradeBack is mirrored in APIClient, LocalBackend and FakeBackend, the mock walks the whole offer, role-swapped poem 2 and closed reveal, and AppModel trades back from an open reveal while release() makes late reveal writers stale.**

## Performance

- **Duration:** 63 min
- **Started:** 2026-11-02T16:32:00Z
- **Completed:** 2026-11-02T17:36:00Z
- **Tasks:** 3 (1 tracer, 2 auto; all TDD)
- **Files modified:** 11 (1 created, 10 modified), 711 insertions and 13 deletions across the six task commits

## Test Evidence

- **Baseline** (precondition, before any edit): `passedTests` **142**, 0 failed, 1 skipped (the harness canary), at `build/verify/p6-02-base`.
- **Final** full suite: `passedTests` **162**, 0 failed, 1 skipped, at `build/verify/p6-02-final`. That is baseline + 20: 6 LocalBackendTests, 3 SessionViewTests, 9 AppModelTradeTests, 2 AppModelRaceTests. The plan's `final >= base + 20` gate passes.
- All 23 pre-existing LocalBackendTests, every pre-existing AppModelTests, StepAwayTests and AppModelRaceTests tests, and `HostIsolationTests` pass unmodified. `releaseOutsideRevealDoesNothing` still passes: the epoch bump sits after `release()`'s guard.
- Grep gates: `"sw.` literal count in `ios/Strangewords` is 2 (unchanged, no new persisted key); no wall-clock waits in the test tree; no `AppModel(` outside TestSupport without an injected `TokenStore`; `DRIFT` lines in LocalBackend went from 5 to 7.

## Task Commits

1. **Task 1 (tracer): a trade back walks the mock end to end**
   - RED `c4045d8` (test): six LocalBackendTests; models, protocol, APIClient and FakeBackend landed here as compile scaffolding, with `LocalBackend.tradeBack` a stub that throws wrongTurn
   - GREEN `cc4430d` (feat): the full mock arc, roles swapped, `maxPoems`, short-line rotation, DRIFT notes
2. **Task 2: AppModel trades back**
   - RED `02c8b21` (test): `haikuView` trade parameters, 3 decode tests, 9 AppModelTradeTests, naive AppModel scaffold
   - GREEN `e4f5dd7` (feat): guarded `tradeBack()`, `pollReveal`, `closeTrade`, apply starts the poll only when `tradeOpen`
3. **Task 3: red first, then green on release()**
   - RED `2f56fa9` (test): `test(06-02): red - late reveal poll and trade response must not undo a let-go`
   - FIX `2e3bd8d` (fix): `release()` bumps the epoch and calls `stopPolling()`; epoch doc comment updated

**Plan metadata:** recorded in the following `docs(06-02)` commit (SUMMARY, STATE, ROADMAP, REQUIREMENTS).

## TDD Gate Compliance

Every task has a `test(06-02)` RED commit before its `feat`/`fix` commit. No refactor commits. `gsd_run check tdd-red-evidence` returned `RED_EVIDENCE_OK` (`target_test_failed`) for all three RED targets.

- **RED 1** (target `tradeBackSwapsRolesIntoPoemTwo()`): all six new tests failed, 23 pre-existing passed. Semantic assessment: the target ran and failed on the planned assertions (`complete.tradeOpen` false, `offered.partnerWantsTrade` false) and on the scaffold stub's `wrongTurn`, which is the intended reason.
- **RED 2** (target `goneDuringRevealClosesTheTradeButKeepsThePoem()`): with the naive scaffold, `goneDuringReveal...`, `closedTradeShowsItPassed` and `tradeBackOnlyFromAnOpenUnaskedReveal` failed on their assertions. The tracer, old-server, partner-offer, offer-then-poll, declined and transient tests passed against the scaffold (characterization, since the scaffold already handled their happy paths). The 3 SessionView decode tests also passed at RED because Task 1 had already landed the model fields.
- **RED 3** (target `tradeResponseLandingAfterReleaseIsIgnored()`): both new tests failed against Task 2's AppModel; the 7 pre-existing race tests passed.

### Mutation proof (Task 3, neither committed)

| Mutation | Failing test | Failure |
|----------|--------------|---------|
| Remove `epoch += 1` from `release()` | `tradeResponseLandingAfterReleaseIsIgnored` only | `model.phase == .dissolving(reveal)` |
| Remove `stopPolling()` from `release()` | `revealPollLandingAfterReleaseIsIgnored` only | `model.pollTask == nil` |

Both were restored (`git checkout -- AppModel.swift`); `git status` was clean afterwards. Evidence: `build/verify/p6-02-mutA`, `build/verify/p6-02-mutB`.

## DRIFT lines added to LocalBackend

- (amended) `DRIFT: the mock starts with your turn, where the server picks StartIndex at random, so the robot poet may write first there. Poem 2 starts with the stranger, as on the server after a trade (the start seat moves one later).`
- (new) `DRIFT: the mock human stranger always offers to trade back after its think time at poem 1's reveal, so one simulator can design the accept state; a real stranger may never offer.`
- (new) `DRIFT: the mock reuses strangerThinkTime for the stranger's offer and acceptance, where the server's robot poet uses BotThink and humans answer when they answer.`

## Decisions Made

- `tradeBack` throws and returns the updated view (like `submitLine`) so the UI can tell "offered" from "poem 2 began". The 409 `trade_closed` reuses `APIError.wrongTurn`.
- The reveal poll starts only from `apply`'s `complete` branch when the view's own `tradeOpen` is true. An old server's reveal never polls or trades (`oldServerRevealNeverPollsOrTrades`).
- A trade transition does not bump the epoch (same session, same token). `release()` now does, which is what makes every in-flight reveal writer stale.
- No new timer, TUNABLE or persisted key: the mock reuses `strangerThinkTime`, and identity stays the two `sw.` TokenStore keys.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] RED commits needed compile scaffolding**
- **Found during:** Task 1 RED and Task 2 RED
- **Issue:** A test naming `tradeBack` on `LocalBackend` or `AppModel` before it exists is a build failure, which the RED classifier refuses as `INVALID_RED`. For Task 2 a bare no-op `AppModel.tradeBack()` made every test park on an arrival that never came; each ran to the 60 s time limit and restarted the host (a first RED attempt of this shape was killed after about 10 minutes and discarded).
- **Fix:** Task 1's RED commit carried the protocol, models, APIClient and FakeBackend plus a stub `LocalBackend.tradeBack` that throws `wrongTurn`. Task 2's RED commit carried a naive `tradeBack()` and a one-shot `pollReveal`, which GREEN replaced with the guarded implementation. No scaffold remains in HEAD.
- **Files modified:** `LocalBackend.swift`, `AppModel.swift`
- **Committed in:** `c4045d8`, `02c8b21` (replaced in `cc4430d`, `e4f5dd7`)

**2. [Rule 1 - Bug in own test] Negative assertion could race**
- **Found during:** Task 2 RED
- **Issue:** `tradeBackOnlyFromAnOpenUnaskedReveal` first checked `recordedCalls()` right after `model.tradeBack()`. A call still on its way would not be recorded yet, so the test passed vacuously against a naive scaffold.
- **Fix:** The test also asserts `model.actionTask` is unchanged, which is deterministic: a guarded `tradeBack()` creates no task.
- **Files modified:** `ios/StrangewordsTests/AppModelTradeTests.swift`
- **Committed in:** `02c8b21`

---

**Total deviations:** 2 auto-fixed (1 Rule 3 TDD scaffolding, 1 Rule 1 test robustness)
**Impact on plan:** Both are test-harness matters. Production behavior matches the plan.

## Issues Encountered

- `scripts/test-ios.sh` runs of a few seconds sometimes took several minutes of wall time (simulator boot and teardown), so two foreground calls hit the tool timeout and were finished in the background; results were unaffected.
- The RED classifier's swift-testing adapter rejects a report containing a parameterized test (`rejectsEmpty(input:)`) as incomplete. RED 1 evidence was therefore re-run with only the six new tests selected.

## Known Stubs

None. No placeholder text or empty data sources were introduced; the scaffolds above were removed by their GREEN commits.

## Threat Flags

None. The one new network surface, `POST /v1/session/{id}/trade` from `APIClient`, is the planned Plan 01 route covered by that plan's threat model (T-06-01 to T-06-08); this plan's T-06-10 to T-06-12 are mitigated as recorded above, T-06-13 accepted.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 03 can render the Reveal affordance against `AppModel.tradeBack()`, `phase == .reveal(s)` with `s.tradeOpen`, `s.youWantTrade` and `s.partnerWantsTrade`, and the per-poem keepsakes (D-04, D-05). Poem 2's reveal arrives with `tradeOpen` false; `./run.sh --mock` exercises the whole arc on one simulator.
- Not performed (automated-only milestone): a manual feel check of the mock trade on a simulator, recorded as the one `human_judgment` deliverable (D6).

## Self-Check: PASSED

All 11 files exist; commits `c4045d8`, `cc4430d`, `02c8b21`, `e4f5dd7`, `2f56fa9`, `2e3bd8d` are ancestors of HEAD; the full suite is green at 162 passed (baseline 142 + 20); the grep gates pass; the working tree is clean of tracked changes.

---
*Phase: 06-two-poem-trade*
*Completed: 2026-11-02*
