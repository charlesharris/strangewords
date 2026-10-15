---
phase: 02-ios-client-logic-suites
reviewed: 2026-10-15T00:00:00Z
depth: standard
files_reviewed: 14
files_reviewed_list:
  - ios/Strangewords/App/AppModel.swift
  - ios/Strangewords/Net/APIClient.swift
  - ios/Strangewords/Net/Keychain.swift
  - ios/Strangewords/Net/LocalBackend.swift
  - ios/StrangewordsTests/AppModelRaceTests.swift
  - ios/StrangewordsTests/AppModelTests.swift
  - ios/StrangewordsTests/FakeBackend.swift
  - ios/StrangewordsTests/HostIsolationTests.swift
  - ios/StrangewordsTests/LocalBackendTests.swift
  - ios/StrangewordsTests/PoemNamingTests.swift
  - ios/StrangewordsTests/SeamDefaultsTests.swift
  - ios/StrangewordsTests/SessionViewTests.swift
  - ios/StrangewordsTests/SyllablesTests.swift
  - ios/StrangewordsTests/TestSupport.swift
findings:
  critical: 0
  warning: 8
  info: 5
  total: 13
status: issues_found
---

# Phase 2: Code Review Report

**Reviewed:** 2026-10-15
**Depth:** standard
**Files Reviewed:** 14
**Status:** issues_found

## Summary

The epoch guards close the headline late-poll resurrection window. Stale writers are rejected before they reach `tokenStore` or `phase` in the paths the race tests exercise. The LocalBackend `cleanLine` port matches `sessions.CleanLine` in order, messages and the scalar-versus-rune count. I compared it with `server/internal/sessions/validate.go` and with the 422 mapping in `gateway.go:230-235`, which uses `err.Error()` as the message. `unicode.IsSpace`/`IsControl` and Swift's `isWhitespace`/`.control` cover the same sets. I found no BLOCKER defects. There are real gaps:

- **Stale state:** `begin()` leaves stale identity and a stale error message behind.
- **Epoch guards:** the `submitting` flag is not covered by them.
- **Test strength:** several tests are vacuous or weaker than they claim, and test cleanup is skipped on failure.
- **Drift:** nothing mechanically ties the Swift port to the Go source.

## Warnings

### WR-01: Enter-failure message is never shown at the threshold and leaks into ComposeView on retry

**File:** `ios/Strangewords/App/AppModel.swift:99-101` (also `:86-92`)
**Issue:** On enter failure `begin()` writes "Couldn't reach the quiet room. Try again." into `submitError` and returns to `.threshold`. The only reader of `submitError` in the app is `ComposeView.swift:55`. The message is therefore invisible where the error happened. `begin()` does not clear `submitError`, so after a failed attempt and a successful retry, the compose screen opens already showing the stale "couldn't reach" text. `reset()` clears it, but the failure-to-retry path never goes through `reset()`. `AppModelTests.enterFailureReturnsToThreshold` (`:314-327`) pins the write but not the display or the clearing.
**Fix:** Clear `submitError = nil` at the top of `begin()`. Give the enter failure its own property (for example `enterError`) that `ThresholdView` renders. Add a test: fail the first enter, run a second `begin()`, then assert `submitError == nil` once composing.

### WR-02: `begin()` does not clear a leftover sessionId, so a waiting engagement can persist the wrong session

**File:** `ios/Strangewords/App/AppModel.swift:86-104`, interacting with `:107-130`
**Issue:** If `resume()` hits a transient error on cold launch, its generic catch (`:125-128`) sets `.threshold` but leaves both `token` and `sessionId` in the store. The user then taps begin, and `enter` returns `state: "waiting"`:
- `tokenStore.token` is overwritten with the new token.
- `tokenStore.sessionId` still holds the OLD session id.

Consequences:
- A relaunch while still waiting calls `getSession(old)`, gets 410 and runs `tokenStore.clear()`. That throws away the valid waiting token.
- `leave()` sends `leave` for the old session id.

`lateResumeResponseAfterBeginIsIgnored` seeds exactly this state (`sessionId: "old"`) but never asserts what happens to it when the enter is a waiting one.
**Fix:** In `begin()`, set `tokenStore.sessionId = nil` (or call `tokenStore.clear()`) before awaiting `enter`, and add a test that seeds identity, begins into `waiting`, and asserts `sessionKey == nil`.

### WR-03: `submitting` reset in `defer` is not epoch-guarded

**File:** `ios/Strangewords/App/AppModel.swift:143`
**Issue:** `defer { submitting = false }` runs for stale submit tasks too. Sequence: submit in flight, then `leave()`, `reset()`, `begin()`, a fresh composing session, and a second `submit()` (`submitting = true`). The old task now completes and flips `submitting` to false while the new submit is in flight. `ComposeView.swift:96` enables the button on `!model.submitting`, so a double submit becomes possible. This is the same class of bug the epoch work targets, in a field the guards did not cover.
**Fix:**
```swift
actionTask = Task {
    defer { if !isStale(e) { submitting = false } }
    ...
}
```
Also reset `submitting = false` in `reset()`/`dissolve()` when bumping the epoch. Add a race test for it.

### WR-04: Two tests assert before the action they check could have run (vacuous)

**File:** `ios/StrangewordsTests/AppModelTests.swift:471-484` and `:486-501`
**Issue:**
- `leaveWhileWaitingSendsNoLeaveCall` calls `model.leave()` and immediately reads `recordedCalls()` without awaiting `actionTask`. Any `leave` Task is enqueued on the main actor and runs after the test suspends. The recorded-calls read is already queued on the fake actor and runs first, so `!contains(.leave)` passes even if `AppModel` started sending leave. The test cannot fail for the regression it exists to catch.
- `leaveTwiceIsStable` asserts `count <= 1`. Given the code, the count is exactly 1, so `<= 1` also accepts 0 and would hide a regression that drops the leave call.

**Fix:** In the first test, `await model.actionTask?.value` after `leave()` and before reading the calls. In the second, assert `== 1`.

### WR-05: Test cleanup is skipped on any early exit, leaving on-disk UserDefaults suites

**File:** `ios/StrangewordsTests/TestSupport.swift:58-63`, `ios/StrangewordsTests/AppModelTests.swift` (every test), `ios/StrangewordsTests/LocalBackendTests.swift:143-159`
**Issue:** Each test ends with `await finish(...)`/`cleanup()`, but any `try await rig.arrivals.next()` that throws or any `try #require` failure exits the test before cleanup. Consequences:
- The `sw.tests.<UUID>` plist, containing the fake token and session id, persists in the simulator's Preferences. This is small, but the project constraint is that tests must not persist identity beyond the encounter.
- The parked `CheckedContinuation` is never resumed.
- The model and its poll task stay alive.

A failing test also sits until the 1-minute limit.
**Fix:** Make the cleanup run unconditionally. For example, give `Rig` a `func run(_ body:)` that wraps the body in `defer`, or a `deinit`-style teardown. In single-use tests, put `defer { cleanup() }` right after `makeIsolatedDefaults()`. `drain()` is async, so use a task or restructure so it is awaited on all paths.

### WR-06: Race tests cannot detect a stale token write, and some skip the identity assertion

**File:** `ios/StrangewordsTests/AppModelRaceTests.swift:124-147`, `:151-174`
**Issue:** The D-08 requirement is that a stale writer must not re-persist the token or session id. In `staleEnterFromPreviousAttemptIsIgnoredAfterBeginAgain` and `lateResumeResponseAfterBeginIsIgnored`:
- Both enters use the token `"tok"`, so a stale `tokenStore.token = t` write is indistinguishable from the fresh one.
- No identity assertion runs between the stale resolve and the fresh resolve; the final `sessionKey == "new"` only checks the end state.
- If the token-write line in `begin()` moved above the `isStale` guard, these tests would still pass. Only the `.connecting` phase check would catch a phase leak.

**Fix:** Use a distinct token for the stale response (`"stale-tok"`). After `await staleFirst?.value`, assert `rig.defaults.string(forKey: TokenStore.tokenKey) == nil` and `sessionKey == nil` (or the seeded "old" in the resume case).

### WR-07: LocalBackend `cleanLine` can drift from the Go source without any test failing

**File:** `ios/Strangewords/Net/LocalBackend.swift:119-167`, `ios/StrangewordsTests/LocalBackendTests.swift:55-160`
**Issue:** The parity is by hand-copying. `maxLineLength`, the three message strings and the zero-width set are duplicated constants. The suite checks the Swift side against literals the author wrote, and the "Mirrors TestX" comments are not machine-checked. Nothing fails if `MaxLineLen`, the zero-width set or a message changes in `validate.go`. The cases most likely to expose a divergence between `unicode.IsSpace`/`TrimSpace` and Swift's `isWhitespace`/`trimmingCharacters` are untested: NBSP U+00A0, U+3000, U+2028/2029, NEL U+0085 and DEL U+007F. NEL and DEL are rejected as control characters in Go, so the Swift side must agree.
**Fix:** Move the cases into a shared fixture (for example `server/internal/sessions/testdata/cleanline.json` with `input`, `want` and `err`). Have both `validate_test.go` and `LocalBackendTests` iterate it. At minimum, add the whitespace and control cases above to the Swift suite. Keep the DRFT-01 note for the screener.

### WR-08: `refresh` swallows every error, including `.gone`, after a 409

**File:** `ios/Strangewords/App/AppModel.swift:241-243`, caller `:156-158`
**Issue:** After `notYourTurn`/`wrongTurn`, `refresh` uses `try? await api.getSession`. The consequences:
- If the session is gone (410) the model stays in `.composing` with a dead session and starts no poll.
- On a transient failure the model also stays stale with no poll.
- The user only learns the session ended by submitting again.

This breaks the CLAUDE.md rule that `try?` is only for failures that are safe to ignore. `submitStaleTurnRefetches` covers only the success path.
**Fix:** Do the fetch with `do/catch`. Map `.gone` to `dissolve(.partnerLeft)` behind the stale check. On other errors, set `submitError` or start `pollSession(id:)`. Add tests for refresh-gone and refresh-transient.

## Info

### IN-01: Polling loops make one more backend call after cancellation

**File:** `ios/Strangewords/App/AppModel.swift:259-262`, `:279-282`
**Issue:** `try? await Task.sleep(...)` swallows the cancellation error. A task cancelled during the sleep proceeds to `guard let token`, then issues one more request before `while !Task.isCancelled` ends the loop. In production the token is usually cleared by then, and URLSession fails fast for a cancelled task. `FakeBackend` is deliberately cancellation-blind, so the call still happens and appears in `recordedCalls`.
**Fix:** Add `if Task.isCancelled { return }` after the sleep, or use `try await` inside the `do` block.

### IN-02: Leaving while connecting or waiting leaves a server-side ghost; the tests pin it

**File:** `ios/Strangewords/App/AppModel.swift:185-190`, `ios/StrangewordsTests/AppModelTests.swift:468-484`, `AppModelRaceTests.swift:104-120`
**Issue:** With no `sessionId`, `leave()` tells the server nothing. The server has no cancel-wait endpoint (`gateway.go:52-60`). A waiter's token stays queued until `WaitTTL` and can be matched to the next entrant, who then writes to a ghost. For `lateEnterResponseAfterLeave`, the client discards a token the server already issued. The test names OBS-1 and defers it, which is fine. It should be tracked as a server-contract item so it does not stay pinned forever.
**Fix:** Record it in the Phase 4 ledger and add a `DELETE /v1/waiting` (or equivalent) with a matching `Backend` method plus `LocalBackend` implementation.

### IN-03: LocalBackend paces with wall-clock `Date()`

**File:** `ios/Strangewords/Net/LocalBackend.swift:89-90`, `:184`
**Issue:** `Date().timeIntervalSince(since) >= strangerThinkTime` is affected by system clock adjustments (NTP step, manual change). With `strangerThinkTime: 0` in tests, a backwards step makes the stranger line not arrive and could make `roundRobinIsABA` flaky. This is a tiny window, but the phase's rule is no wall-clock dependence.
**Fix:** Use `ContinuousClock.now` instants, or inject a clock.

### IN-04: Hosted-env and golden tests are tied to environment details

**File:** `ios/StrangewordsTests/HostIsolationTests.swift:21-23`, `ios/StrangewordsTests/PoemNamingTests.swift:7-13`
**Issue:**
- `hostRunsInLocalMockMode` hardcodes `http://127.0.0.1:9` and depends on the scheme in `project.yml`. Changing the scheme or running with a different test plan fails it with no hint of the source.
- The PoemNaming goldens depend on stdlib `shuffle(using:)`/`randomElement(using:)` behavior, which Apple does not guarantee across releases. This is documented, but the suite will go red on a runtime upgrade with no code change.

**Fix:** Point the failure message at `project.yml`'s test scheme. Add a canary golden that exercises only the FNV-1a/SplitMix64 outputs (not the stdlib shuffle) so a real regression and stdlib drift can be told apart.

### IN-05: Smaller items

**File:** `ios/Strangewords/Net/APIClient.swift:71,78`, `ios/Strangewords/Net/Keychain.swift:16-41`
**Issue:**
- `"/v1/session/\(id)"` interpolates the server-supplied session id unencoded into the path. It is server-trusted today, but an id containing `/` or `?` would silently re-route the request. Percent-encode it, or use `URLComponents`.
- `TokenStore` lives in `Keychain.swift` and is backed by `UserDefaults`, so the bearer token is included in device backups. The file comment states the trade-off. The filename still misleads, and `CLAUDE.md` already notes it.
- `resolveBase` accepts any `URL(string:)`-parseable `SW_API_BASE` (for example a scheme-less `localhost:8080` parses with `localhost` as the scheme). A dev typo then fails silently at request time.

**Fix:** Percent-encode the id with `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`. Validate that the override has an `http(s)` scheme and a host, otherwise fall back to the default.

---

_Reviewed: 2026-10-15_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
