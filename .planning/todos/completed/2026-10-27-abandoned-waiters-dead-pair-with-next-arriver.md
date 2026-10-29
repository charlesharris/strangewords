---
created: 2026-10-27T23:56:07.547Z
title: Abandoned waiters linger in the queue and dead-pair with the next arriver (OBS-1)
area: api
severity: blocker
files:
  - server/internal/matchmaker/matchmaker.go (pair() pops queue head without liveness check)
  - server/internal/store/store.go (WaitEntry, WaitTTL 15m)
  - server/internal/gateway/gateway.go:167 (handleWaiting — natural place to track last-poll liveness)
  - ios/Strangewords/App/AppModel.swift:200 (leave() only calls the server when a session id exists)
---

## Problem

OBS-1 (pinned in Phase 2: "a waiter who leaves before a match is never reported to the
server") bit twice in the first 20 minutes of real production use (2026-10-27):

1. A deploy-verification `enter` left a ghost waiter in the queue; the first real user paired
   with it and sat forever at "the stranger is with the poem now".
2. The user entered, backed out of the waiting room ("step back out" never reaches the
   server), re-entered, and was instantly paired with their OWN stale waiter — same dead
   session, self-inflicted via normal UI use.

Any abandoned waiter persists up to WaitTTL (15 minutes) and dead-pairs with the next
arriver. Combined with the missing Compose escape (sibling todo), this traps users for up to
90 minutes. This is the top pre-App-Store fix, ranked above code-review warnings WR-01/WR-02.

## Solution

Two complementary halves (either alone helps; both is right):

1. **Wait-leave endpoint:** e.g. `POST /v1/wait/leave` (bearer = participant token) that
   LREMs the caller's queue entry and deletes the wait entry + token ref. Call it from
   `AppModel.leave()` when there is a waitId but no session id (the exact case leave()
   currently skips). LocalBackend mirrors it (parity rule).
2. **Liveness at pair time:** record last-polled-at on the WaitEntry during handleWaiting;
   in matchmaker.pair(), skip (and clean up) queue entries whose owner has not polled within
   ~3× the 3s poll interval. Covers crashes/offline, not just polite leaves. Keep the
   LPOP-loop atomic per entry; add race tests alongside TestHumanVsBotRaceSingleSession.

Note the interaction with the bot path: a skipped stale waiter must also not block an
opted-in arriver's own bot window.
