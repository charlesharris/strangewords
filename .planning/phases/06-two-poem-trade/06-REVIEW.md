---
phase: 06-two-poem-trade
reviewed: 2026-11-02T00:00:00Z
depth: standard
files_reviewed: 19
files_reviewed_list:
  - server/internal/gateway/gateway.go
  - server/internal/sessions/session.go
  - server/internal/store/store.go
  - server/internal/botplayer/botplayer.go
  - server/internal/metrics/metrics.go
  - server/internal/gateway/privacy.html
  - ios/Strangewords/App/AppModel.swift
  - ios/Strangewords/Net/Models.swift
  - ios/Strangewords/Net/Backend.swift
  - ios/Strangewords/Net/APIClient.swift
  - ios/Strangewords/Net/LocalBackend.swift
  - ios/Strangewords/Features/Reveal/RevealView.swift
  - ios/Strangewords/Features/Reveal/TradeBack.swift
  - ios/Strangewords/Features/Dissolved/DissolvedView.swift
  - ios/Strangewords/Naming/PoemNaming.swift
  - server/internal/gateway/trade_test.go
  - server/internal/sessions/trade_test.go
  - ios/StrangewordsTests/AppModelTradeTests.swift
  - ios/StrangewordsTests/TradeBackTests.swift
findings:
  critical: 1
  warning: 4
  info: 5
  total: 10
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-11-02
**Depth:** standard
**Files Reviewed:** 19
**Status:** issues_found

## Summary

The server half is sound. I checked the following and found no defect:
- The WATCH/MULTI/EXEC discipline in `handleTrade`, `handleDismiss` and `settleBot`.
- The per-poem role swap in `poemStart`.
- The legacy-blob handling (`PoemCount` 0).
- The DEC-06-01 dismiss rule.
- The anonymity invariants. `store.go` still has exactly 5 `"sw:` literals, and `go vet`, `gofmt` and the Go tests are clean.

The defects are on the iOS client. The trade-back button has no in-flight guard, and `closeTrade` stops polling without checking the phase. A double tap on an accept can therefore strand the user in poem 2 with no poll running. Smaller items follow: view-ordering regressions, silently swallowed trade errors, a reveal-window extension that conflicts with the privacy page, and a few info items.

Decisions D-01 to D-06 are not flagged. The carried advisory WR-02 (`touchPresence` blind save) is not re-reported.

## Critical Issues

### CR-01: Double-tapping "trade back" can kill poem 2's poll and strand the user

**File:** `ios/Strangewords/App/AppModel.swift:209-225` and `:347-355`, with `ios/Strangewords/Features/Reveal/RevealView.swift:50-58`

**Issue:** `tradeBack()` guards on `phase == .reveal(s)` with `!s.youWantTrade`. That phase only changes when the response lands. Nothing disables the button or tracks an in-flight trade, and `Haptics.soft(); model.tradeBack()` fires on every tap.

A second tap before the first response therefore sends a second `POST /trade`. This is the normal case on the accept path, where the partner has already offered:

1. Tap 1 reaches the server, which begins poem 2 and returns `active`.
2. Tap 2 reaches the server on a session that is no longer complete. `TradeOpen()` is false, so it returns `409 trade_closed`. This maps to `APIError.wrongTurn`.
3. Response 1 runs `apply()`. This lands on `.composing(poem 2)` and, when the stranger opens poem 2, starts `pollSession`.
4. Response 2 runs `closeTrade(asked: true)`. It does nothing in the phase (the phase is not `.reveal`), but it unconditionally calls `stopPolling()`. That cancels the poem-2 `pollSession`.

The epoch is unchanged, so `isStale` does not protect this. The user then sits on "their turn" forever, because only `apply()` restarts a poll and nothing will call it. The only exit is "leave". Roles swap, so about half of accepters open poem 2 as the non-author. The same unconditional `stopPolling()` also hits a late `.gone` caught in `tradeBack()`.

**Fix:**
```swift
// 1. Only touch polling when the reveal is actually on screen.
private func closeTrade(asked: Bool) {
    guard case .reveal(let s) = phase else { return }
    var closed = s
    closed.tradeOpen = false
    if asked { closed.youWantTrade = true }
    phase = .reveal(closed)
    stopPolling()
}

// 2. Single-flight the call, and disable the button while it runs.
@ObservationIgnored private var tradeInFlight = false   // expose a read-only `tradingBack` for the view

func tradeBack() {
    guard !tradeInFlight, case .reveal(let s) = phase, s.tradeOpen, !s.youWantTrade,
          let token = tokenStore.token else { return }
    tradeInFlight = true
    let e = epoch
    actionTask = Task {
        defer { tradeInFlight = false }
        // ... unchanged body ...
    }
}
```
Add a test that double-calls `tradeBack()`. The first response must be `poemTwo(yourTurn: false)` and the second `fail(.wrongTurn)`. Then assert that `model.pollTask != nil` and the phase is still `.composing(two)`.

## Warnings

### WR-01: `apply()` has no poem-ordinal or status monotonicity guard, so a late response can regress poem 2 to poem 1's reveal

**File:** `ios/Strangewords/App/AppModel.swift:305-339`

**Issue:** `tradeBack()` responses and `pollReveal` / `refresh` results are all applied with the same epoch. If a first-ask `complete` view with `youWantTrade` from `tradeBack()` arrives after a poll view that already shows poem 2 `active`, `apply()` sets `phase = .reveal(poem 1)`. This undoes poem 2 and starts a new `pollReveal`. Poem 2 and its keepsake coining are then lost, and the poll sees `active`, so poem 1's keepsake is coined again. The coin site is guarded by `outgoingReveal`, so this can double-append. This needs out-of-order responses, but the phase introduced two independent writers (the action task and the reveal poll) on one phase without ordering.

**Fix:** In `apply`, ignore a view that goes backwards:
```swift
if let cur = currentSessionView, s.sessionId == cur.sessionId, s.poemNumber < cur.poemNumber { return }
```
Also ignore `complete` after `active` of the same ordinal.

### WR-02: A reveal offer resets `RevealTTL`, so a finished poem can outlive the two-minute window the privacy page promises

**File:** `server/internal/gateway/gateway.go:506` (also `:441`), `server/internal/gateway/privacy.html:74`

**Issue:** The comment says "the offer ages out with the reveal". But `return store.RevealTTL, true` runs `SET ... EX 120s`, which restarts the countdown from the moment of the offer. A single offer at 119s keeps poem 1 (and the other participant's view) alive for up to about 239s. The privacy page still says "A finished poem is shown during a two-minute reveal window and then erased". The `handleDismiss` CAS rewrite inherits the same reset (it was already the case at HEAD, where the comment "Preserve the reveal countdown" was already false). Phase 6 adds a second path and a user-facing claim that the code does not honour.

**Fix:** Either preserve the remaining TTL (read it with `PTTL` inside the transaction, or store `CompletedAt + RevealTTL` and compute `min(RevealTTL, remaining)`), or amend the privacy copy to "at least two minutes, a little longer if someone offers to trade back".

### WR-03: `tradeBack()` swallows every non-409/410 failure with no feedback

**File:** `ios/Strangewords/App/AppModel.swift:221-223`

**Issue:** `503 busy` (the server's CAS-exhausted answer), `404` (an older server), `.http(5xx)` and `.transport` all land in an empty `catch`. The button just does nothing and the user gets no signal. For `503 busy` a retry is the right behaviour, but nothing says so. For an old-server `404` the user can tap forever. `tradeOpen` should never be true from an old server, but the server's `trade_closed` and `busy` are different conditions and are treated alike.

**Fix:** Set a quiet transient caption (reuse `submitError` or add `tradeError`) such as "couldn't reach the quiet room, try again". Map the `503` to a limited auto-retry, or at least clear any in-flight flag, so the button is usable again.

### WR-04: The Effective date on the privacy page is earlier than the change it describes

**File:** `server/internal/gateway/privacy.html:59`, `server/internal/gateway/privacy_test.go:53`

**Issue:** The "second poem" disclosure was added on 2026-11-02 but the page now reads "Effective October 29, 2026" (that is the CONTEXT capture date). The pinned test enshrines the wrong date. A policy that claims a practice has been in force since before it was written is inaccurate. It is also the same instrument that must stay true to the code (the privacy test is named `TestPrivacyPageMatchesCode`).

**Fix:** Set the date to the actual deployment or effective date in both the HTML and the test. Update it again at ship if it slips.

## Info

### IN-01: `settleBot` trade branch has an unreachable fallthrough return

**File:** `server/internal/gateway/gateway.go:665-673`

**Issue:** The bot's `WantsTrade` is set, and `BotTradeDue()` guarantees a human has asked. With two participants `AllWantTrade()` is therefore always true, so `return store.RevealTTL, true` at line 673 is dead for the current model and would silently reset TTL if a third participant ever existed.

**Fix:** Keep it only with a comment saying it is the N>2 case, or remove it and return `0, false`.

### IN-02: Mock marks `maxPoems` as `[TUNABLE]` while the server says it is "a product rule, not a tunable"

**File:** `ios/Strangewords/Net/LocalBackend.swift:66-67`, `server/internal/sessions/session.go:31`

**Issue:** The two sides disagree, and the project convention reserves the `[TUNABLE]` marker for values expected to be tuned.

**Fix:** Drop the marker from the mock and mirror the server comment.

### IN-03: Poem 1's keepsake is unrecoverable if the app is resumed during or after the trade

**File:** `ios/Strangewords/App/AppModel.swift:136-159`, `:316-324`

**Issue:** Keepsakes are in memory only (by design). Poem 1's name is coined only when `apply` sees poem 2 start from an on-screen poem-1 reveal. A cold launch or process kill after the trade resumes into poem 2 with `keepsakes == []`, and poem 1's lines are gone on the server (BeginNextPoem), so D-04's "one per completed poem" silently becomes one. This follows from the design choices, so a doc note is enough.

**Fix:** Document the limitation near the coin site and in `docs/STATUS.md`.

### IN-04: Reports cannot reach poem 1 after the trade and carry no poem ordinal

**File:** `server/internal/gateway/gateway.go:558-566`

**Issue:** `BeginNextPoem` erases poem 1's lines. A participant who sees abusive content in poem 1 and then trades (or whose partner trades) can no longer report it. The moderation `Report` also records neither the poem number nor which poem `Lines` belongs to, so a reviewer cannot tell poem 1 from poem 2 context.

**Fix:** Add `Poem: sess.PoemCount` to `moderation.Report`. Consider allowing a report on the reveal view before the trade, which already works, and say in the UI/design notes that the report window closes at the trade.

### IN-05: Over-long comment line in `botplayer.NextLine`

**File:** `server/internal/botplayer/botplayer.go:46-48`

**Issue:** The doc comment was edited in place and the third line runs to about 110 characters, which is out of keeping with the file.

**Fix:** Reflow the comment.

---

_Reviewed: 2026-11-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

---

## Disposition Ledger (2026-11-02)

| Finding | Severity | Disposition | Evidence |
|---------|----------|-------------|----------|
| CR-01 | Critical | **fixed** — single-flight `tradeBack()` + `closeTrade` scoped to `.reveal` | commit `8671b71`; tests `secondTradeBackWhileInFlightSendsNoSecondRequest`, `lateTradeFailureAfterPoemTwoBeganKeepsThePollRunning` |
| WR-01 | Warning | **fixed** — stale trade response dropped once the reveal progressed | commit `e44e380`; test `staleTradeResponseAfterPoemTwoBeganIsIgnored` |
| WR-02 | Warning | **deferred** — TTL refresh on reveal saves is arguably intentional (an offer must keep the reveal alive for the answer); copy/behavior drift tracked | `.planning/todos/pending/2026-11-02-reveal-ttl-reset-vs-privacy-wording.md` |
| WR-03 | Warning | **deferred** — silent trade-tap failures need new user-facing copy (voice-rule tests); overlaps 06-UI-REVIEW fix 3 | `.planning/todos/pending/2026-11-02-trade-tap-and-poll-silent-failures.md` |
| WR-04 | Warning | **fixed** — effective date moved to 2026-11-02 on page and pinned test | commit `b0b56b9` |
| IN-01 | Info | **accepted** — unreachable fallthrough in `settleBot` with two participants; harmless defensive return | no action |
| IN-02 | Info | **accepted** — mock `maxPoems` `[TUNABLE]` wording vs server comment; cosmetic | no action |
| IN-03 | Info | **accepted** — keepsakes are in-memory by design (anonymity model: nothing persists); a relaunch mid-trade losing poem 1's name is consistent with the ephemerality contract | no action |
| IN-04 | Info | **accepted** — reporting carries no poem number and poem 1 becomes unreportable once purged at the trade; purge is the stronger privacy promise (T-06-04) | no action |
| IN-05 | Info | **accepted** — over-long comment line in botplayer.go; cosmetic | no action |

Post-fix verification: iOS suite 177 passed / 0 failed / 1 skipped (evidence `build/verify/p6-fix`); Go suite, vet, gofmt clean; structural gates hold (5 `"sw:`, 2 `"sw.`, no sleeps, goldens untouched).
