---
phase: 05-opt-in-robot-poet-collaboration
reviewed: 2026-10-27T00:00:00Z
depth: standard
files_reviewed: 28
files_reviewed_list:
  - ios/Strangewords/App/AppModel.swift
  - ios/Strangewords/App/SettingsStore.swift
  - ios/Strangewords/Features/Compose/ComposeView.swift
  - ios/Strangewords/Features/Compose/PartnerPresence.swift
  - ios/Strangewords/Features/Reveal/RevealView.swift
  - ios/Strangewords/Features/Settings/SettingsView.swift
  - ios/Strangewords/Features/Threshold/ThresholdView.swift
  - ios/Strangewords/Features/Waiting/WaitingView.swift
  - ios/Strangewords/Net/APIClient.swift
  - ios/Strangewords/Net/Backend.swift
  - ios/Strangewords/Net/LocalBackend.swift
  - ios/Strangewords/Net/Models.swift
  - ios/StrangewordsTests/AppModelTests.swift
  - ios/StrangewordsTests/FakeBackend.swift
  - ios/StrangewordsTests/LocalBackendTests.swift
  - ios/StrangewordsTests/PartnerPresenceTests.swift
  - ios/StrangewordsTests/SeamDefaultsTests.swift
  - ios/StrangewordsTests/SessionViewTests.swift
  - ios/StrangewordsTests/TestSupport.swift
  - server/internal/botplayer/botplayer.go
  - server/internal/botplayer/botplayer_test.go
  - server/internal/config/config.go
  - server/internal/gateway/bot_test.go
  - server/internal/gateway/gateway.go
  - server/internal/matchmaker/matchmaker.go
  - server/internal/metrics/metrics.go
  - server/internal/sessions/session.go
  - server/internal/store/store.go
findings:
  critical: 0
  warning: 2
  info: 6
  total: 8
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-10-27
**Depth:** standard
**Files Reviewed:** 28
**Status:** issues_found

## Summary

The phase is well built overall. The opt-in is strict and fail-closed on both
sides. The `LREM`/`LPOP` claim is a real mutual-exclusion point. `settleBot`
persists through WATCH/MULTI/EXEC and returns the latest stored state on
conflict. The `partnerIsBot` disclosure is computed only in `ViewFor`, and the
tolerant decode is correct. `go vet`, `gofmt -l` and `go test -race` over
`gateway` and `botplayer` are clean, and `sessions` tests pass.

The remaining problems are on the edges of the new concurrency design:

1. The bot claim is not atomic with what follows it, so a Redis error strands the waiter.
2. Pre-existing blind `SaveSession` writers still run on the same keys the new WATCH contract protects, so the contract in the `settleBot` doc comment is only partly true.

No security vulnerabilities were found. There are no secrets or injection paths.
Auth is unchanged, and the empty-token case is covered in IN-01.

## Warnings

### WR-01: Bot claim is not atomic with session creation; a Redis error after `ClaimWaiter` strands the waiter

**File:** `server/internal/matchmaker/matchmaker.go:111-147` (with `server/internal/gateway/gateway.go:173-177`)
**Issue:** `PairWithBot` first removes the waiter from the queue with `LREM`, then does `SaveSession`, `SetRef` and `DelWait`, each of which can fail.

- If any step after the claim fails, for example a transient Redis error on `SaveSession`, the handler returns 500. The waiter is already out of the queue.
- The waiter's token ref still points at the wait entry, and `MatchedSessionID` is empty.
- Every later poll re-enters `PairWithBot`. `ClaimWaiter` now returns `n == 0`, so the poll falls through to `{"state":"waiting"}`.
- The user keeps polling until `WaitTTL` (15 min) expires. No human can ever pair with them, because they are no longer in the queue. The bot cannot pair with them either, because the claim is lost.
- This is a silent dead-end in exactly the failure mode (Redis blip) the project treats as normal (`redis_down`).
- If `SetRef` fails after `SaveSession` succeeded, an orphan session also stays in Redis for `SessionTTL`.

**Fix:** Make the post-claim steps recoverable. Either re-enqueue the id and clean up the orphan on failure, or record the claim so a later poll can finish the pairing instead of falling through to "waiting".

```go
claimed, err := m.st.ClaimWaiter(ctx, waiter.Bucket, waiter.ID)
...
fail := func(err error) (*sessions.Session, bool, error) {
    // best-effort rollback so the waiter is not lost
    _ = m.st.DeleteSession(ctx, sess)                 // drop any half-written session
    _ = m.st.RequeueWaiter(ctx, waiter.Bucket, waiter.ID) // LPUSH to keep its place
    return nil, false, err
}
if err := m.st.SaveSession(ctx, sess); err != nil { return fail(err) }
```

Alternatively, pass the claim's `wfe` forward and set `waiter.MatchedSessionID = sess.ID` via `SaveWait` before `SetRef`. Then the existing "matched" branch in `handleWaiting` completes the pairing on the next poll even if the response was lost.

### WR-02: Blind read-modify-write savers bypass the WATCH contract; a stale poll can clobber a line or resurrect a dissolved session

**File:** `server/internal/gateway/gateway.go:203,220,496-504` (`touchPresence`), `gateway.go:306-311` (`handleLine` idempotency re-save), `gateway.go:346` (`handleDismiss`)
**Issue:** The `settleBot` doc comment (gateway.go:434-441) promises that a human line written after a stale poll's load survives, and that "a dissolved session is never resurrected". That holds only inside `settleBot`. Right after it, the same handlers call `touchPresence`, which does an unconditional `SaveSession` of the session object loaded earlier in the request.

- **Resurrection.** Suppose a poll loads the session on the bot's turn when the bot is not yet due, so `settleBot` declines and returns the stale object. A concurrent `leave` or `dismiss` then runs `DeleteSession`. The poll's `touchPresence` then does a plain `SET sw:sess:{id}` with the whole poem and a fresh 90-minute `SessionTTL`. The tokens are already gone, so the poem is unreachable but persisted for up to 90 minutes. That violates the ephemerality guarantee and the "dissolution erases" contract that Phase 5 explicitly tests.
- **Clobber.** `handleLine` with an `IdemKey` re-saves the session after the first save (gateway.go:306-311). The first save has just armed `BotReadyAt`. With `SW_BOT_THINK_MS` small or 0, a concurrent poll's `settleBot` can write the bot line in between. The re-save then overwrites the session and drops the bot line, while the bot's `metrics.LinesSubmitted` was already counted.
- The window is small, but the client polls every 3 s and `AppModel.leave()` does not wait for in-flight requests.

**Fix:** Route presence and idempotency tracking through the same optimistic path, or make them non-destructive. For example, give `touchPresence` an `UpdateSession` that only sets `LastSeen` and never recreates a missing key:

```go
func (s *Server) touchPresence(ctx context.Context, id string, idx int) {
    _, _ = s.st.UpdateSession(ctx, id, func(f *sessions.Session) (time.Duration, bool) {
        if f.Status != sessions.StatusActive || idx < 0 || idx >= len(f.Participants) {
            return 0, false
        }
        f.Participants[idx].LastSeen = s.now().UnixMilli()
        return store.SessionTTL, true
    })
}
```

`ErrNotFound` and `ErrConflict` are then correctly ignored. Fold the `IdemKeys` append into the first `SaveSession` in `handleLine` (append the key before the first save) so the second write disappears.

## Info

### IN-01: `IndexForToken("")` matches the bot participant

**File:** `server/internal/sessions/session.go:82-89` (also `server/internal/store/store.go:267-270`)
**Issue:** The bot is stored with `Token: ""`. `IndexForToken("")` therefore returns the bot's index. This is not currently exploitable, because `bearer()` can yield `""` but `GetRef("")` finds nothing and returns 410 first. It is a latent identity-confusion hazard that depends on an unrelated guard. Separately, `DeleteSession` appends `tokKey("")` (`sw:tok:`) for the bot and issues a pointless `DEL`.
**Fix:** Guard empty tokens.

```go
func (s *Session) IndexForToken(token string) int {
    if token == "" { return -1 }
    ...
}
```

In `DeleteSession`, skip participants where `p.Token == ""`.

### IN-02: Bot activity is indistinguishable in reports and metrics

**File:** `server/internal/gateway/gateway.go:376-385`, `server/internal/metrics/metrics.go:29-30`
**Issue:** `moderation.Report` carries no marker that the partner was the robot poet. `Participants` is just 2, and the bot's lines look human. A reviewer triaging an abuse report cannot tell that the offending line came from the poet, which is the more actionable finding. `LinesSubmitted` and `PoemsCompleted` also count bot-authored lines and bot-finished poems with no label, so the pre-phase dashboards silently change meaning.
**Fix:** Add `PartnerIsBot bool` to `moderation.Report` (derive it from `sess.ViewFor(...)` or a loop over `Participants`). Consider a separate `sw_bot_lines_total` counter.

### IN-03: Replay determinism is coupled to the `poet` package version

**File:** `server/internal/botplayer/botplayer.go:27-45`
**Issue:** The package doc and `NextLine` doc say a restart mid-poem "changes nothing". That holds across restarts of the same binary. The project deploys on every push to `main` (`fly-deploy.yml`), and replay re-runs the poet over the current word banks and templates. A deploy that edits `poet` banks or templates mid-poem makes the replayed RNG and `used/mine` state diverge from what produced the stored bot lines. The result is still a valid line, so nothing breaks, but the "stateless replay" claim and the determinism tests only cover same-binary behaviour.
**Fix:** Narrow the claim in the comment ("same build"), or store a poet version/seed alongside the session if byte-stable continuation across deploys matters.

### IN-04: `fallbackLine` is five syllables regardless of the target

**File:** `server/internal/botplayer/botplayer.go:14-17,41-44`
**Issue:** The fallback "still water at dusk" is returned for any line that fails `CleanLine`, including the 7-syllable middle line. The comment says it matches the first and last lines only. It is a safe degradation, but the form target is silently violated and nothing is logged or counted when the fallback fires. If the screener starts rejecting poet output (for example after a banned-term update), the problem is invisible.
**Fix:** Log at `Warn` or increment a counter when the fallback is used. Optionally pick a 7-syllable fallback (`the river remembers rain`, already in the poet) when `target(...) == 7`.

### IN-05: Config accepts non-finite or out-of-range values for the bot tunables

**File:** `server/internal/config/config.go:52-53,64-71`
**Issue:** `envFloat` uses `strconv.ParseFloat`, which accepts `NaN`, `Inf`, and values like `1e30`. `time.Duration(f * float64(time.Second))` is implementation-defined for those, and may wrap negative. For `SW_BOT_WAIT_SECONDS` a wrapped value can silently disable the robot poet or make the window arbitrary. For `SW_BOT_THINK_MS` a negative value makes the bot always due. This is operator-supplied config, so the risk is low, but the code documents `<= 0` as an ops kill switch.
**Fix:** Reject non-finite or overly large values in `envFloat`, or clamp the converted duration (for example a max of 1 h).

### IN-06: Minor test and mock fidelity gaps

**File:** `ios/Strangewords/Net/LocalBackend.swift:114-123`, `server/internal/gateway/bot_test.go:66-97`, `ios/StrangewordsTests/AppModelTests.swift`
**Issue:**
- `LocalBackend.waiting()` after `leave()`/`dismiss()` returns `state: "matched"` with a `dissolved` view instead of throwing `APIError.gone` as `getSession` does. `AppModel` still ends in `.dissolved(.ended)`, but this is an unflagged drift from the server's 410. The class header lists the other drifts but not this one.
- `newBotRig` never closes its `redis.Client` (`restart` does). This is a small leak across the 50-iteration race test and the 64-iteration poem test.
- There is no AppModel test for the path that matters most for this phase: `begin()` with `allowBot: true`, then waiting, then a poll returning a `partnerIsBot` session. `optInTravelsAndPersists` only covers an immediate match. There is also no test pinning that `begin()` captures the opt-in at call time (`allow`) and does not re-read it.
- There is no Go test for the `PairWithBot` failure paths described in WR-01.
**Fix:** Throw `APIError.gone` in `LocalBackend.waiting` when `status == "dissolved"`, or add a DRIFT note. Add `t.Cleanup(func() { _ = rdb.Close() })` in `newBotRig`. Add the waiting-to-bot AppModel test. Add a store-failure test around `PairWithBot` once WR-01 is fixed.

---

_Reviewed: 2026-10-27_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
