---
phase: 05-opt-in-robot-poet-collaboration
plan: 01
subsystem: api
tags: [go, redis, matchmaking, robot-poet, optimistic-locking, miniredis, opt-in, disclosure]

requires:
  - phase: 03-server-e2e-wire-contract
    provides: gateway/store/matchmaker layers and the miniredis test rig
provides:
  - "POST /v1/enter allowBot opt-in (fail-closed decode) carried on the TTL-bound wait entry"
  - "Atomic LREM waiter claim (Store.ClaimWaiter) and Matchmaker.PairWithBot after SW_BOT_WAIT_SECONDS (default 25)"
  - "partnerIsBot disclosure computed only in Session.ViewFor, on every view of a bot session"
  - "server/internal/botplayer: stateless deterministic poet replay, CleanLine-checked with a fixed fallback"
  - "Store.UpdateSession WATCH/MULTI/EXEC compare-and-set (ErrConflict) and poll-driven Server.settleBot"
  - "sw_bot_paired_total metric and SW_BOT_WAIT_SECONDS / SW_BOT_THINK_MS config"
affects: [05-02 iOS opt-in wire/model, 05-03 settings and disclosure UI, ship, privacy]

actuals:
  tokens: 9000
  tasks: 3
  commits: 5

tech-stack:
  added: []
  patterns:
    - "Poll-driven bot: no worker, no second queue, no lock, no new Redis key"
    - "Optimistic WATCH/MULTI/EXEC compare-and-set for writers whose decision depends on the state they read"
    - "Stateless deterministic replay of a session-seeded poet instead of in-process bot state"
    - "Fake-clock bot rig (fakeClock + botRig) so time windows are crossed by Advance, never by sleeping"

key-files:
  created:
    - server/internal/botplayer/botplayer.go
    - server/internal/botplayer/botplayer_test.go
    - server/internal/gateway/bot_test.go
  modified:
    - server/internal/config/config.go
    - server/internal/sessions/session.go
    - server/internal/store/store.go
    - server/internal/matchmaker/matchmaker.go
    - server/internal/metrics/metrics.go
    - server/internal/gateway/gateway.go

key-decisions:
  - "Bot is a flagged, tokenless, pre-dismissed participant and never a queue member, so one human dismiss dissolves the session and no arrival can pop it"
  - "Bot lines are produced lazily on the human's polls by replaying a poet seeded by the session id (restart-safe, no in-process state)"
  - "settleBot persists only through UpdateSession (WATCH/MULTI/EXEC), re-deciding on a fresh read; a lost race returns the latest stored state and a later poll retries"
  - "Think time is armed in handleLine (BotReadyAt = now + BotThink) so a stale settle cannot slip a bot line in right after the human's"

patterns-established:
  - "Disclosure choke point: partnerIsBot is derived in ViewFor from Participant.Bot, never read from a request"
  - "Kill switch convention: SW_BOT_WAIT_SECONDS <= 0 disables the feature, same as SW_RATE_RPS=0"

requirements-completed: [P5-OPTIN, P5-FALLBACK, P5-DISCLOSE, P5-ANON, P5-TESTS]

coverage:
  - id: D1
    description: "Opted-in waiter is paired with the robot poet when its own poll lands at or after BotWindow; one ms earlier still waits; partnerIsBot true on waiting-matched and session views"
    requirement: P5-FALLBACK
    verification:
      - kind: integration
        ref: "server/internal/gateway/bot_test.go#TestBotFallbackTracer"
        status: pass
    human_judgment: false
  - id: D2
    description: "Strict opt-in: no body, {}, false, \"true\" string, 1, and a plain arrival after a bot pairing never reach the robot poet; kill switch disables it"
    requirement: P5-OPTIN
    verification:
      - kind: integration
        ref: "server/internal/gateway/bot_test.go#TestBotNeverPairsWithoutOptIn"
        status: pass
      - kind: integration
        ref: "server/internal/gateway/bot_test.go#TestBotFallbackDisabledByKillSwitch"
        status: pass
    human_judgment: false
  - id: D3
    description: "Human first: overlapping opted-in humans pair together; a human-vs-bot race at the window boundary always yields exactly one session whose views agree"
    requirement: P5-FALLBACK
    verification:
      - kind: integration
        ref: "server/internal/gateway/bot_test.go#TestOverlappingOptedInHumansPairTogether"
        status: pass
      - kind: integration
        ref: "server/internal/gateway/bot_test.go#TestHumanVsBotRaceSingleSession"
        status: pass
    human_judgment: false
  - id: D4
    description: "A whole haiku with the robot poet in both start orders: think time honored, one line per settle after a long gap, restart-safe, clean and on target, and zero sw: keys after one dismiss"
    requirement: P5-ANON
    verification:
      - kind: integration
        ref: "server/internal/gateway/bot_test.go#TestBotPoemCompletesAndLeavesNoKeys"
        status: pass
      - kind: unit
        ref: "server/internal/botplayer/botplayer_test.go#TestNextLineReplaysDeterministically"
        status: pass
      - kind: unit
        ref: "server/internal/botplayer/botplayer_test.go#TestNextLineIsCleanAndOnTarget"
        status: pass
    human_judgment: false
  - id: D5
    description: "A bot settle never persists over newer state: a stale load writes nothing and a write inside the read-to-save window aborts with ErrConflict"
    requirement: P5-TESTS
    verification:
      - kind: integration
        ref: "server/internal/gateway/bot_test.go#TestStaleSettleDoesNotOverwriteHumanLine"
        status: pass
    human_judgment: false
  - id: D6
    description: "A backgrounded human sees the bot's line within one think time plus one poll interval of returning (bot lines only advance on the human's polls)"
    verification: []
    human_judgment: true
    rationale: "Backstop truth in the plan: real-device pacing and push-out-of-scope behavior are not asserted by an automated test"

duration: 14 min
completed: 2026-10-27
status: complete
plan_head_before: 3e133411c4252a790f4b28fbe7da3f867029cc8d
plan_head_after: d36474ccd758b1a2eb7a0a2ca05e6aeeecd49773
commits: 5
---

# Phase 5 Plan 1: Server Robot Poet Summary

**Opt-in robot poet on the Go server: an allowBot waiter is claimed out of the queue with an atomic LREM after a 25 s window and paired with a tokenless bot that writes poet-replayed lines on the human's polls, discloses itself via partnerIsBot on every view, and leaves zero Redis keys.**

## Performance

- **Duration:** 14 min
- **Started:** 2026-10-27T22:13:23Z
- **Completed:** 2026-10-27T22:27:01Z
- **Tasks:** 3
- **Files modified:** 9 (3 created, 6 modified)

## Accomplishments

- Tracer (Task 1): one path end to end over HTTP and Redis. `POST /v1/enter {"allowBot":true}` stores the opt-in on the TTL-bound wait entry; the waiter's own `GET /v1/waiting` at or after `BotWindow` claims itself with `LREM`, builds a session with a pre-dismissed `Bot` participant, deletes its wait entry, and answers matched with `"partnerIsBot":true`. A poll 1 ms earlier still answers waiting; `sw_bot_paired_total` +1, `sw_matched_total` +0.
- Lines (Task 2): new pure `botplayer` package replays a poet seeded by an FNV-1a hash of the session id and discards earlier bot lines, so the next line is identical across restarts. `settleBot` runs on `GET /v1/session/{id}` and the matched tail of `GET /v1/waiting`, writes at most one line per call, and persists only through `Store.UpdateSession` (WATCH/MULTI/EXEC, `ErrConflict` on abort). Think time is armed in `handleLine`; `maybePush` skips bots.
- Invariants (Task 3): 6 fail-closed opt-in subtests, kill switch, overlapping opted-in humans pairing together, and a 50-iteration human-vs-bot race at the window boundary under `-race`, all green and stable over 20 repeated runs.

## Task Commits

1. **Task 1: Tracer, opted-in enter to bot-paired session with partnerIsBot** - `ad540fc` (test, RED), `55730fa` (feat, GREEN)
2. **Task 2: Robot poet writes its lines, settleBot, stale-settle safety** - `9632366` (test, RED), `002f6b2` (feat, GREEN)
3. **Task 3: Consent and race invariant proofs** - `d36474c` (test)

**Plan metadata:** committed separately (docs: complete plan)

## Files Created/Modified

- `server/internal/botplayer/botplayer.go` - `Seed`, `NextLine`, `fallbackLine`; pure (stdlib hash/fnv, poet, sessions only)
- `server/internal/botplayer/botplayer_test.go` - the four botplayer tests (replay determinism over 500 ids, clean and on-target over 200 ids in both start orders)
- `server/internal/gateway/bot_test.go` - `fakeClock`, `botRig`, `restart`, `doRaw`, and all gateway bot tests
- `server/internal/config/config.go` - `BotWindow` (SW_BOT_WAIT_SECONDS, 25) and `BotThink` (SW_BOT_THINK_MS, 2500), both `[TUNABLE]`
- `server/internal/sessions/session.go` - `Participant.Bot`, `Session.BotReadyAt`, `View.PartnerIsBot` (computed in `ViewFor`), `AuthorOf`, `BotTurn`
- `server/internal/store/store.go` - `WaitEntry.AllowBot`, `ClaimWaiter`, `ErrConflict`, `UpdateSession`; still exactly 5 `"sw:` key literals
- `server/internal/matchmaker/matchmaker.go` - `Enter(..., allowBot, now)`, `PairWithBot`
- `server/internal/metrics/metrics.go` - `BotPaired` (`sw_bot_paired_total`)
- `server/internal/gateway/gateway.go` - `allowBot` decode, window fallback in `handleWaiting`, `settleBot`, think-time arming, push skip for bots

## TDD Gate Compliance

RED evidence (`gsd_run check tdd-red-evidence`, `RED_EVIDENCE_OK`, reason `target_test_failed`) was recorded for every target before GREEN:

- **RED 1** (`ad540fc`): `TestBotFallbackTracer` failed on the planned assertion ("at the window expected matched, got {"state":"waiting"}"). Semantic assessment: the target executed and failed on the intended behavior, not on a compile or fixture fault.
- **RED 2** (`9632366`): the four botplayer tests failed against zero-value stubs on their planned assertions (Seed collision, empty line vs replayed line, empty not CleanLine-identical); `TestBotPoemCompletesAndLeavesNoKeys` failed with "expected exactly one new line after the gap"; both `TestStaleSettleDoesNotOverwriteHumanLine` subtests failed (no settle happened; stub `UpdateSession` could not return `ErrConflict`).
- GREEN commits `55730fa` and `002f6b2` follow; no refactor commit was needed.

Both RED commits carry compile scaffolding that is not behavior (config fields, metric, `View.PartnerIsBot` field; botplayer/`UpdateSession`/`settleBot` zero-value stubs), because a build failure is INVALID_RED.

## Decisions Made

- Followed the plan's mechanism (RESEARCH option c'): poll-driven, no worker/queue/lock/key.
- Stale-settle test forces `StartIndex` through the store (`dueBot`) so both start orders are covered deterministically instead of depending on `rand.IntN(2)`.
- Left `touchPresence` and `handleLine` unconditional saves as they are (pre-existing CONCERNS.md read-modify-write hazard, out of scope per plan).

## Deviations from Plan

None - plan executed exactly as written. (Two implementation slips of my own were caught by the plan's tests and fixed before the GREEN commit: a mis-indented search pattern that initially skipped the think-time arming in `handleLine`, found by `TestBotPoemCompletesAndLeavesNoKeys` and the stale-load subtest; and gofmt realignment of two struct blocks. Neither reached a commit.)

**Total deviations:** 0 auto-fixed. **Impact on plan:** none.

## Issues Encountered

None. `TestStaleSettleDoesNotOverwriteHumanLine` start order 1 relies on the think-time arming (not only the fresh-read re-check) to keep the stale settle from writing the bot's next line; that matches the plan's `k+2` assertion.

## Known Stubs

None. (The RED-phase stubs were replaced in the GREEN commits.)

## Threat Flags

None - all new surface (bot claim on `GET /v1/waiting`, `allowBot` on `POST /v1/enter`) is covered by T-05-01 through T-05-15 in the plan's threat model.

## User Setup Required

None - no external service configuration required. Optional ops env vars: `SW_BOT_WAIT_SECONDS` (default 25, `<=0` disables), `SW_BOT_THINK_MS` (default 2500).

## Next Phase Readiness

- Ready for 05-02 (iOS wire/model: send `allowBot`, tolerant decode of `partnerIsBot`, `LocalBackend` mirror) and 05-03 (settings sheet and disclosure chip).
- Wire contract to mirror: request `allowBot` (bool, absent = false); view `partnerIsBot` (omitted when false).
- Deferred by plan: privacy.html on-device line, `moderation.Report.BotPartner`.

---
*Phase: 05-opt-in-robot-poet-collaboration*
*Completed: 2026-10-27*

## Self-Check: PASSED

- Created files exist: botplayer.go, botplayer_test.go, bot_test.go (FOUND)
- Commits are ancestors of HEAD: ad540fc, 55730fa, 9632366, 002f6b2, d36474c (FOUND)
- `go test ./... -count=1`, `go vet ./...`, `gofmt -l .` clean; gateway and botplayer pass under `-race`
