---
phase: 06-two-poem-trade
plan: 01
subsystem: api
tags: [go, redis, watch-multi-exec, session-state-machine, robot-poet, privacy]

requires:
  - phase: 05-robot-poet
    provides: "UpdateSession compare-and-set, settleBot poll settling, botplayer deterministic replay, fake-clock bot rig"
provides:
  - "POST /v1/session/{id}/trade: offer and acceptance as one per-participant signal"
  - "Session.BeginNextPoem, poem-ordinal role swap in AuthorOf, TradeOpen/BotTradeDue domain predicates"
  - "View keys poemNumber, tradeOpen, youWantTrade, partnerWantsTrade (all omitempty)"
  - "Robot poet that accepts a trade after BotThink and writes poem 2 from a per-poem seeded replay"
  - "handleDismiss on the bounded compare-and-set (DEC-06-01)"
  - "sw_trades_offered_total and sw_trades_begun_total counters"
affects: [06-02-ios-client, 06-03-ios-keepsakes, ship, testflight]

actuals:
  tokens: 14300
  tasks: 3
  commits: 6

plan_head_before: d9a6606b6097c46d9f4a6d73a4466f0697795e9c
plan_head_after: 9f3b750795fb16797e46ea06d1baa16bfad5e140
commits: 6

tech-stack:
  added: []
  patterns:
    - "Bounded CAS helper (casAttempts = 3) over store.UpdateSession; apply closures reset their captured decision flags"
    - "Per-poem start offset derived from PoemCount inside AuthorOf, never by mutating StartIndex"
    - "Per-poem deterministic poet seed (PoemSeed) so a restart changes nothing"

key-files:
  created:
    - server/internal/gateway/trade_test.go
    - server/internal/sessions/trade_test.go
  modified:
    - server/internal/sessions/session.go
    - server/internal/store/store.go
    - server/internal/gateway/gateway.go
    - server/internal/gateway/privacy.html
    - server/internal/gateway/privacy_test.go
    - server/internal/metrics/metrics.go
    - server/internal/botplayer/botplayer.go
    - server/internal/botplayer/botplayer_test.go

key-decisions:
  - "Offer and accept share one endpoint and one WantsTrade flag, mirroring the symmetric Dismissed flag"
  - "Role swap derives from PoemCount (poemStart) so StartIndex keeps its encounter-level meaning and the policy is untouched"
  - "No poems[] collection: BeginNextPoem resets poem-level fields in place so finished poems never stay on the server"
  - "DEC-06-01: dismiss on an active poem 2 dissolves; an active poem 1 keeps HEAD's flag-only all-must-dismiss rule"
  - "Poem 2's seed is FNV-1a over id + '#' + poem number; poem 1 keeps Seed(id) so in-flight sessions and cmd/bot's seedFor stay in lockstep"

patterns-established:
  - "Trade state lives inside the TTL-bound session blob: zero new sw: key classes"
  - "A repeat /trade by a caller whose flag is set writes nothing, so it can neither extend RevealTTL nor re-arm the robot poet"

requirements-completed: [P6-TRADE, P6-ROLES, P6-BOT, P6-ANON, P6-COMPAT, P6-TESTS]

coverage:
  - id: D1
    description: "Two humans can trade back over HTTP: the second ask begins poem 2 in the same session with roles swapped, poem 1's cache purged, poem 2 reveals with no further trade, and dissolution leaves no session, token or cache keys"
    requirement: "P6-TRADE"
    verification:
      - kind: integration
        ref: "server/internal/gateway/trade_test.go#TestTradeTracer"
        status: pass
    human_judgment: false
  - id: D2
    description: "Roles swap for poem 2 (whoever wrote lines 1 and 3 of poem 1 writes line 2 of poem 2) without mutating StartIndex"
    requirement: "P6-ROLES"
    verification:
      - kind: unit
        ref: "server/internal/sessions/trade_test.go#TestPoemTwoSwapsRoles"
        status: pass
    human_judgment: false
  - id: D3
    description: "The robot poet accepts a trade only after BotThink, survives a restart, and writes poem 2 from a per-poem deterministic replay (both start orders)"
    requirement: "P6-BOT"
    verification:
      - kind: integration
        ref: "server/internal/gateway/trade_test.go#TestBotTradesBack"
        status: pass
      - kind: unit
        ref: "server/internal/botplayer/botplayer_test.go#TestPoemSeed"
        status: pass
      - kind: unit
        ref: "server/internal/botplayer/botplayer_test.go#TestNextLineReplaysPoemTwo"
        status: pass
    human_judgment: false
  - id: D4
    description: "Anonymity holds: no new key class (store.go keeps 5 sw: literals), poem 1's lines and cached responses are erased when poem 2 begins, and the privacy page states the trade"
    requirement: "P6-ANON"
    verification:
      - kind: integration
        ref: "server/internal/gateway/trade_test.go#TestTradeTracer"
        status: pass
      - kind: integration
        ref: "server/internal/gateway/privacy_test.go#TestPrivacyPageMatchesCode"
        status: pass
    human_judgment: false
  - id: D5
    description: "Old clients are fail-safe: a client that never calls /trade dissolves as before, the body is ignored, and declining or leaving closes the trade"
    requirement: "P6-COMPAT"
    verification:
      - kind: integration
        ref: "server/internal/gateway/trade_test.go#TestOldClientNeverTrades"
        status: pass
      - kind: integration
        ref: "server/internal/gateway/trade_test.go#TestTradeIgnoresRequestBody"
        status: pass
      - kind: integration
        ref: "server/internal/gateway/trade_test.go#TestTradeDeclinedByLettingGo"
        status: pass
    human_judgment: false
  - id: D6
    description: "Races are safe under -race: concurrent accepts begin exactly one poem 2, and a let-go racing an accept never reverts poem 2 to poem 1 nor resurrects a dissolved session"
    requirement: "P6-TESTS"
    verification:
      - kind: integration
        ref: "server/internal/gateway/trade_test.go#TestConcurrentAcceptsBeginOnePoem"
        status: pass
      - kind: integration
        ref: "server/internal/gateway/trade_test.go#TestAcceptVersusLetGoRace"
        status: pass
      - kind: integration
        ref: "server/internal/gateway/trade_test.go#TestDismissAfterPoemTwoBeganDissolves"
        status: pass
      - kind: integration
        ref: "server/internal/gateway/trade_test.go#TestDismissDuringPoemOneKeepsHeadSemantics"
        status: pass
    human_judgment: false

duration: 7min
completed: 2026-11-02
status: complete
---

# Phase 6 Plan 01: Two-Poem Trade, Server Half Summary

**POST /v1/session/{id}/trade lets two humans (or a human and the robot poet, after its think time) trade back into a role-swapped second poem in the same session, with poem 1's lines and retry cache erased at the transition and zero new Redis key classes.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-11-02T16:24:23Z
- **Completed:** 2026-11-02T16:31Z
- **Tasks:** 3 (1 tracer, 2 auto; all TDD)
- **Files modified:** 10 (2 created, 8 modified), 1217 insertions, 50 deletions

## Final Wire Contract (Plan 02 mirrors this exactly)

- **Route:** `POST /v1/session/{id}/trade`, bearer participant token.
- **Request:** no body needed; any body (empty, `{}`, non-JSON, `{"accept":false}`) is ignored (`TestTradeIgnoresRequestBody`).
- **200:** the caller's `View`. First ask: still `status: "complete"` with `youWantTrade: true`. Completing ask: `status: "active"`, `poemNumber: 2`, empty `lines`, `currentLine: 0`, no `tradeOpen`.
- **Errors:** `409 trade_closed` (not a complete tradeable reveal, a human already let go, or already poem 2), `503 busy` (lost the CAS 3 times), plus the `authSession` errors `401 no_token`, `410 session_gone`, `403 not_a_member`.
- **New View keys, all omitempty:** `poemNumber` (int, encounter ordinal, always present from 1), `tradeOpen` (bool), `youWantTrade` (bool), `partnerWantsTrade` (bool). Computed only in `ViewFor`.
- **Dismiss under the trade (DEC-06-01):** `POST /dismiss` during an active poem 2 returns `{"status":"dissolved"}`; letting go on a reveal clears the caller's offer and closes the trade for the partner.

## Accomplishments

- Domain: per-participant `WantsTrade`, `MaxPoems = 2`, `TradeOpen`, `AnyWantsTrade`/`AllWantTrade`, `HasBot`/`BotTradeDue`, `BeginNextPoem`, and a `poemStart()` offset so `AuthorOf` swaps roles per poem while `StartIndex` and the turn policy stay untouched.
- Gateway: `handleTrade` makes the both-asked decision on the WATCHed fresh read through a bounded `updateSession` helper (`casAttempts = 3`); a repeat call writes nothing; poem 1's cached responses are purged via the new `Store.DeleteIdem` (built on the existing `idemKey`).
- Robot poet (D-06): `handleTrade` arms `BotReadyAt = now + BotThink`; `settleBot` accepts through the same CAS once ready; `botplayer.PoemSeed(id, poem)` gives each poem its own deterministic poet (poem 1 unchanged).
- `handleDismiss` moved onto the CAS so a stale plain write can never revert a just-begun poem 2.
- Trade counters, a privacy page bullet ("A second poem."), effective date 2026-10-29, and 15 new/updated tests, all green under `-race`.

## Assumption-delta decision, as executed

Pluralization decision **no-change** held: no `poems[]` collection and no second set of poem fields. `BeginNextPoem` resets the poem-level fields in place, so a finished poem never stays on the server. `PoemCount` and `IdemKeys` moved from the poem-level block to the encounter-level block of `Session` with byte-identical JSON tags; the struct comment "v1 has exactly one poem" was rewritten. Blobs written before deploy decode with zero values and need no migration.

## store.go `"sw:` literal count

Before: **5**. After: **5**. `DeleteIdem` reuses `idemKey`; no new key builder.

## Task Commits

1. **Task 1 (tracer): two humans trade back end to end**
   - RED `e182d32` (test) - `TestTradeTracer`; the two metric counters were added here so the test compiles
   - GREEN `ce5dcd6` (feat) - domain trade state, `handleTrade`, CAS helper, `DeleteIdem`
2. **Task 2: the robot poet trades back**
   - RED `e30c6e9` (test) - `TestPoemSeed`, `TestNextLineReplaysPoemTwo`, `TestBotTradesBack`
   - GREEN `cdae702` (feat) - `PoemSeed`, `BotTradeDue`, widened `settleBot`
3. **Task 3: decline, races and old clients**
   - RED `c420ae3` (test) - dismiss/race/privacy tests and domain tests
   - GREEN `9f3b750` (feat) - CAS `handleDismiss`, privacy page

**Plan metadata:** recorded in the following `docs(06-01)` commits (SUMMARY, then STATE/ROADMAP/REQUIREMENTS).

## TDD Gate Compliance

All three tasks have a `test(06-01)` RED commit followed by a `feat(06-01)` GREEN commit. No refactor commits were needed. `gsd_run check tdd-red-evidence` returned `RED_EVIDENCE_OK` (reason `target_test_failed`) for each RED target.

- **RED 1:** `TestTradeTracer` failed on the planned assertion that a complete poem 1 view carries `tradeOpen:true`/`poemNumber:1` (semantic assessment: the target ran and failed because /trade and the view keys did not exist, the intended reason).
- **RED 2:** `TestBotTradesBack` failed because poem 2 never began (the robot poet did not accept); `TestPoemSeed` and `TestNextLineReplaysPoemTwo` failed on assertion against a deliberately wrong `PoemSeed` stub that returned 0.
- **RED 3:** `TestDismissAfterPoemTwoBeganDissolves` failed (dismiss returned an active poem-2 view instead of dissolving), `TestAcceptVersusLetGoRace` failed with an impossible stored state (active/complete session with A dismissed and still wanting a trade), and the privacy tests failed on the missing phrase and date.
- **Characterization tests:** in RED 3 the following already passed because the Task 1 and 2 behavior covered them: `TestTradeDeclinedByLettingGo`, `TestDismissDuringPoemOneKeepsHeadSemantics` (a pin that must keep passing through the CAS rewrite), `TestTradeRepeatIsIdempotent`, `TestTradeErrors`, `TestConcurrentAcceptsBeginOnePoem`, `TestOldClientNeverTrades`, `TestTradeIgnoresRequestBody`, and the four `sessions` domain tests.

## Decisions Made

- DEC-06-01 implemented exactly as recorded in the plan: a single dismiss dissolves only when `Status == active && PoemCount > 1`; every other state keeps HEAD's all-must-dismiss rule at `RevealTTL`, plus clearing the caller's `WantsTrade`.
- Gateway trade tests decode the new wire keys into a local `tradeFields` struct straight from the response body, so the contract (key names, omitempty) is verified independently of the server's `View` type.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug in plan assertion] "zero `sw:` keys" cannot hold for human-paired sessions**
- **Found during:** Task 1 (GREEN, `TestTradeTracer` last assertion)
- **Issue:** The plan asks for `assertNoKeysWithPrefix(t, mr, "sw:")` after dissolving a two-human session. A human pairing leaves the original waiter's `sw:wait:` record in place until its own `WaitTTL` (pre-existing behavior: `pair` does not drop it, and `dissolve` does not touch it; privacy.html already states "erased after 15 minutes"). It holds no poem content and predates the trade. Bot sessions drop it at pairing, so they do reach zero `sw:` keys.
- **Fix:** Added `assertEncounterGone` in `trade_test.go`: no session, token-ref or idem key may remain, and the only tolerated key is a `sw:wait:` record with a TTL in `(0, WaitTTL]`. Every human-rig test uses it; every bot-rig test keeps the strict `assertNoKeysWithPrefix(t, mr, "sw:")`. No production behavior changed.
- **Files modified:** `server/internal/gateway/trade_test.go`
- **Verification:** all trade tests pass under `-race`
- **Committed in:** `ce5dcd6`

**2. [Rule 3 - Blocking] RED commits needed compile scaffolding**
- **Found during:** Task 1 and Task 2 RED
- **Issue:** A test naming a symbol that does not exist is a build failure, which the RED classifier refuses as `INVALID_RED`.
- **Fix:** Task 1's RED commit also declared the two metric counters (declarations only; they are driven in GREEN). Task 2's RED commit added `botplayer.PoemSeed` as a deliberately wrong stub (`return 0`) so the tests fail on assertion rather than on compilation; GREEN replaced it.
- **Files modified:** `server/internal/metrics/metrics.go`, `server/internal/botplayer/botplayer.go`
- **Committed in:** `e182d32`, `e30c6e9`

---

**Total deviations:** 2 auto-fixed (1 Rule 1 plan-assertion correction, 1 Rule 3 TDD scaffolding)
**Impact on plan:** Both are test-harness matters; no production behavior differs from the plan.

## Issues Encountered

- The classifier refuses a RED record outside the project directory, so records were built in the scratchpad and copied into a temporary `.planning/tmp-red/` for validation, then removed (never committed).
- `.planning/STATE.md` carried an uncommitted modification from before this plan; it is included in the STATE update commit.

## Known Stubs

None.

## Threat Flags

None. The only new surface is the planned `POST /v1/session/{id}/trade` route, covered by T-06-01 through T-06-08 in the plan's threat model; `authSession` binds the bearer token to the path id before any write.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The wire contract above is stable for Plan 02 (`Backend.tradeBack`, `SessionView` tolerant decode, `LocalBackend`/`FakeBackend` parity, Reveal affordance).
- Not performed (deferred, automated-only milestone): live Fly deploy and any manual device check of the trade. `cmd/bot` is deliberately unchanged; it dismisses at the reveal, which is D-02's decline path.

## Self-Check: PASSED

All created and modified files exist; commits `e182d32`, `ce5dcd6`, `e30c6e9`, `cdae702`, `c420ae3`, `9f3b750` are ancestors of HEAD; `go test ./... -count=1`, `go test -race` on the gateway, sessions and botplayer packages, `go vet ./...` and `gofmt -l .` are clean; `store.go` still has exactly 5 `"sw:` literals.

---
*Phase: 06-two-poem-trade*
*Completed: 2026-11-02*
