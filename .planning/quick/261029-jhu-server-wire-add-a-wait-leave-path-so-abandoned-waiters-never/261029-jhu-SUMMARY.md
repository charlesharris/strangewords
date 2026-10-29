---
phase: quick-261029-jhu
plan: 01
subsystem: server-matchmaking, ios-net
tags: [obs-1, wait-leave, stale-waiter, race-safety]
status: complete
requirements: [QUICK-261029-jhu]
key-files:
  created:
    - server/internal/gateway/wait_test.go
  modified:
    - server/internal/store/store.go
    - server/internal/matchmaker/matchmaker.go
    - server/internal/gateway/gateway.go
    - server/internal/gateway/bot_test.go
    - server/internal/metrics/metrics.go
    - plan.v1.md
    - ios/Strangewords/Net/Backend.swift
    - ios/Strangewords/Net/APIClient.swift
    - ios/Strangewords/Net/LocalBackend.swift
    - ios/Strangewords/App/AppModel.swift
    - ios/StrangewordsTests/FakeBackend.swift
    - ios/StrangewordsTests/AppModelTests.swift
    - ios/StrangewordsTests/LocalBackendTests.swift
decisions:
  - "StaleWaiterAfter = 10 s (about 3x the 3 s poll plus slack); strictly-greater comparison so the boundary counts as live"
  - "The waiter's token ref is the single ownership record: binds use SET XX (BindWaiter), the leave uses a WATCH compare-and-delete (DropWaitIfUnbound)"
  - "Wait-leave answers {status: left | dissolved}, 410 session_gone when there is nothing to leave"
  - "Two counters: sw_wait_left_total, sw_stale_waiters_dropped_total"
commits: 3
plan_head_before: b5ad8fd90a305b8055894b93dfde4db72ced51c9
plan_head_after: 02d0b7e54444d1d6bebcc4163940fb11172954b7
actuals:
  tasks: 3
  commits: 3
---

# Phase quick-261029-jhu Plan 01: Wait-leave path and stale-waiter liveness Summary

OBS-1 closed: `POST /v1/wait/leave` plus a 10 s poll-liveness rule at pair time, with a SET XX / WATCH ownership protocol on the waiter's token ref so a leave racing an arrival or a bot claim can never strand a partner.

## Tasks and commits

| Task | Commit | What |
| ---- | ------ | ---- |
| 1 (tracer) | a8440e8 | `POST /v1/wait/leave`, `Matchmaker.LeaveWait`, `Store.DropWaitIfUnbound`, both counters, four `TestWaitLeave*` tests |
| 2 | 10bbfb7 | `Backend.leaveWait(token:)` on APIClient, LocalBackend, FakeBackend; `AppModel.leave()` sends it when there is a token and no session id; iOS tests |
| 3 | 02d0b7e | `LastPolledAt` liveness touch, `StaleWaiterAfter`, Enter stale-skip loop, `BindWaiter` in pair/PairWithBot/migration, `UpdateWait`/`DropWait` (replacing `SaveWait`), race tests, plan.v1.md §6/§7 |

## Verification

- `go test -race -count=1 ./...`, `go vet ./...`, `gofmt -l server/` clean; gateway package also green with `-count=3` (50-iteration race tests repeated).
- `scripts/test-ios.sh`: PASS (98 passed, 0 failed, 1 skipped pre-existing); zero sleeps in `ios/StrangewordsTests`.
- `go.mod` / `go.sum` unchanged. `store.go` still has exactly 5 `"sw:` literals.
- Wire parity: `/v1/wait/leave` appears in both `gateway.go` and `APIClient.swift`.
- Nothing pushed.

## Recorded items (per plan output spec)

- **StaleWaiterAfter** is 10 s, a `[TUNABLE]` const in `server/internal/matchmaker/matchmaker.go`.
- **Intentional rename of the OBS-1 pin test:** `leaveWhileWaitingSendsNoLeaveCall` became `leaveWhileWaitingSendsLeaveWait` and its assertion is inverted.
- **TestHumanVsBotRaceSingleSession precondition change:** before the race, the test now advances `BotWindow-1ms`, polls A (asserting waiting), then advances 1 ms. Reason: the old test's waiter never polled during the 25 s jump, which is indistinguishable from an abandoned waiter under the new rule. The race under test is still human arrival versus bot claim; all original assertions are unchanged.
- **Backgrounded-waiter behavior change:** a waiter whose app is backgrounded stops polling. After 10 s an arriver may drop it, and on return its next poll gets 410, which AppModel already maps to `.dissolved(.noOneCame)`. Revisit when APNs push lands.
- **Todo resolved:** `.planning/todos/pending/2026-10-27-abandoned-waiters-dead-pair-with-next-arriver.md` is resolved by this item, for the close-out step to move.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Arriver ref is set before the waiter bind in `pair()`**
- **Found during:** Task 3 design of the leave-vs-arrival race.
- **Issue:** The plan said to bind the waiter then "SetRef the arriver as today". If a leave sees the bind and dissolves the session between those two steps, the arriver's ref would be written after `DeleteSession`, leaving a dangling `sw:tok:` ref to a deleted session for up to 90 minutes. That would break the race test's "0 tok keys" invariant.
- **Fix:** Order is SaveSession, SetRef(arriver), BindWaiter(waiter). A failed bind runs `DeleteSession`, which also erases the arriver's ref; a successful bind followed by a leave dissolves both tokens.
- **Files modified:** `server/internal/matchmaker/matchmaker.go`
- **Commit:** 02d0b7e

### Other notes

- `go-redis` `SetXX(...).Result()` returns `(false, nil)` for an XX miss, so `UpdateWait` and `BindWaiter` return that result directly.
- A `PairWithBot` that loses the bind to a leave returns `(nil, false, nil)`, so that poll answers `waiting` to a client that already left (200, as the plan specified); the next poll gets 410.
- The harness refused a Write to the primary-checkout SUMMARY path from this isolated worktree, so this file lives at the same relative path inside the worktree (uncommitted) for the orchestrator to copy.

## Known Stubs

None.

## Threat Flags

None. No new key class, no new dependency; `LastPolledAt` is never returned to clients and no token is logged.

## Self-Check: PASSED

- wait_test.go exists; commits a8440e8, 10bbfb7, 02d0b7e are ancestors of HEAD.
