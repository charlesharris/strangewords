---
last_mapped_commit: 4196ce5e0ccea3955e6a70452d0cded834a85ad4
last_mapped_at: 2026-10-08
---
# Codebase Concerns

**Analysis Date:** 2026-10-08

## Tech Debt

**Session and wait records are not fully erased on dissolution:**
- Issue: `Store.DeleteSession` removes the session key, participant token refs, and idempotency keys, but never touches the `WaitEntry` record. When a waiter is matched, `matchmaker.pair` calls `SaveWait` with the waiter's `Token` and `PushToken` still in place, and that record persists for up to `WaitTTL` (15 min). The `Participant` struct is documented as "erased when the session dissolves," which this does not satisfy for the wait record.
- Files: `server/internal/store/store.go` (`DeleteSession`, `SaveWait`), `server/internal/matchmaker/matchmaker.go` (`pair`), `server/internal/gateway/gateway.go` (`dissolve`)
- Impact: The anonymity model in `brief.v4.md` and `plan.v1.md` §6 says infrastructural identifiers are erased on dissolution. Here a participant token and push token survive Redis for up to 15 minutes after the poem ends. The poem lines are not in the wait record, so the content exposure is limited to identifiers.
- Fix approach: On pairing, delete the wait key (or store only a tombstone with no token/pushToken) instead of re-saving the full entry. Add a regression test in `gateway_test.go` that checks `sw:wait:*` keys are gone after `dissolve`.

**Dismiss resets the session TTL to the reveal window regardless of status:**
- Issue: `handleDismiss` calls `SaveSessionTTL(..., store.RevealTTL)` (120 s) on every non-final dismiss. The handler does not check `sess.Status`, so a dismiss on an active poem shortens its lifetime from 90 min to 120 s. The inline comment ("preserve the reveal countdown rather than extending it") does not match what the code does, since it always sets a fresh 120 s.
- Files: `server/internal/gateway/gateway.go` (`handleDismiss`)
- Impact: A participant who dismisses during an active poem can cause the session to expire two minutes later, and the partner gets `session_gone` mid-poem. Dismiss is only called from the reveal screen in the iOS client (`ios/Strangewords/App/AppModel.swift:140`), so this is latent unless a client sends it early.
- Fix approach: Reject dismiss unless `sess.Status == sessions.StatusComplete` (return 409), or only apply the reveal TTL when the status is complete and otherwise keep the existing TTL.

**Keychain file name does not match its contents:**
- Issue: `ios/Strangewords/Net/Keychain.swift` defines `TokenStore`, which uses `UserDefaults`, not the Keychain. The file header explains the choice, but the name will mislead anyone looking for credential storage.
- Files: `ios/Strangewords/Net/Keychain.swift`
- Impact: Readers may assume the participant token is hardware-backed. The decision is documented in the file, but the file name contradicts it.
- Fix approach: Rename the file to `TokenStore.swift` (and update `ios/project.yml` if needed, though XcodeGen picks it up from the folder).

**Stale and drifting documentation:**
- Issue: `docs/STATUS.md` is dated 2026-06-26 and still lists `api.strangerwords.us` cert/DNS as remaining, while `server/DEPLOY.md` and `ios/Strangewords/Net/APIClient.swift` already assume it. `server/DEPLOY.md` says the Go module keeps the "no-r" spelling on purpose, but the repo also has `brief.final.md`, `brief.v4.md`, and `plan.v1.md` with different names ("Haiku for Strangers" in `server/cmd/server/main.go`'s package comment vs. "Stranger Words" in the app).
- Files: `docs/STATUS.md`, `server/DEPLOY.md`, `server/cmd/server/main.go` (package comment), `ios/project.yml` (`CFBundleDisplayName`)
- Impact: New contributors get conflicting names and stale status.
- Fix approach: Refresh STATUS.md after the custom-domain step, and align the `main.go` package comment with the product name.

**Uncommitted and untracked build inputs:**
- Issue: `ios/Strangewords/Strangewords.entitlements` is untracked (`??` in git status), but `ios/project.yml` already sets `CODE_SIGN_ENTITLEMENTS` to it. Other changes to `ios/project.yml`, `run.sh`, `server/DEPLOY.md`, `server/internal/config/config.go`, and `docs/STATUS.md` are also uncommitted.
- Files: `ios/Strangewords/Strangewords.entitlements`, `ios/project.yml`, `server/internal/config/config.go`
- Impact: A fresh clone of `main` cannot produce a signed build, because the entitlements file is missing. The uncommitted `config.go` change (`SW_APP_ATTEST_APPID`) is not present in the deployed history.
- Fix approach: Commit the entitlements file and the pending changes together, and verify with a clean clone and `xcodegen generate` followed by a build.

## Known Bugs

**Read-modify-write races on the session blob:**
- Symptoms: Concurrent requests can overwrite each other's changes to a session. Polling (`GET /v1/session/{id}`, `GET /v1/waiting`) calls `touchPresence`, which saves the whole session it loaded moments earlier. If a `POST .../line` lands between the load and the save, the stale write can roll back `Lines`, `CurrentLine`, or `Status`.
- Files: `server/internal/gateway/gateway.go` (`touchPresence`, `handleLine`, `handleGetSession`, `handleWaiting`), `server/internal/store/store.go` (`SaveSession`, `SaveSessionTTL`)
- Trigger: Both participants' clients poll every 3 s (`ios/Strangewords/App/AppModel.swift`, `pollInterval`) while one submits a line. The window is small but nonzero, and it grows under load or on a slow Redis round-trip. The gateway tests cover sequential behavior only.
- Workaround: None. The iOS client's idempotency key (`idemKey`) only protects exact replays of the same line.
- Fix approach: Use Redis `WATCH`/`MULTI` (or a Lua script) for session updates, or update only the presence field with `HSET` on a hash, so polling never rewrites lines or status.

**Abandoned waiters pair with active users and stall the first turn:**
- Symptoms: A user who closes the app while waiting stays in the queue until the 15-minute wait TTL. The next arrival is paired with that ghost. The ghost never writes, so the arriver is blocked until the 90-minute session TTL expires, unless the arriver leaves.
- Files: `server/internal/matchmaker/matchmaker.go` (`Enter`, `PopWaiter`), `server/internal/store/store.go` (`PopWaiter`, `WaitTTL`), `server/internal/gateway/gateway.go` (`handleWaiting` presence is not checked before matching)
- Trigger: Enter the queue, then force-quit or background the app. Presence is recorded (`LastSeen`) but is not used for matchmaking or turn skipping.
- Workaround: The arriver can tap "step back out" (`WaitingView.swift`) or leave the session. Neither is automatic.
- Fix approach: At pop time, skip waiters whose `EnqueuedAt` is older than a presence threshold (e.g. `cfg.PresenceWindow` plus slack), and add a turn timeout that lets the active partner end a stalled poem.

## Security Considerations

**App Attest is configured but not enforced:**
- Risk: Anyone with network access can call `POST /v1/enter` and the rest of the API without proving they run the real app. The only anti-abuse controls are per-IP rate limits and a slur filter.
- Files: `server/internal/config/config.go` (`AppAttestAppID`, `SW_APP_ATTEST_APPID`), `ios/project.yml` (`APP_ATTEST_ENVIRONMENT`), `ios/Strangewords/Strangewords.entitlements`, `server/DEPLOY.md`
- Current mitigation: `AppAttestAppID` is loaded but never read. No attestation or assertion code exists in `server/` or `ios/`. The entitlement is declared, so the app can request App Attest, but nothing calls it.
- Recommendations: Either implement the attestation validator and an assertion header on the `enter` and `line` routes, or remove the config field and the entitlement and document the gap. The config comment currently implies enforcement exists.

**Rate limiter trusts `Fly-Client-IP` on any request:**
- Risk: `clientIP` uses the `Fly-Client-IP` header whenever it is present. Fly's edge sets this header, so it is trustworthy on the public route. Any path that reaches the process without passing through Fly (e.g. a future internal listener, or a second service attached to the same machine) could forge it and bypass per-IP limits.
- Files: `server/internal/gateway/middleware.go` (`clientIP`, `middleware`)
- Current mitigation: The service is exposed only through `http_service` in `server/fly.toml`. The debug listener is not routed publicly.
- Recommendations: Document the trust boundary in `server/DEPLOY.md`. If the service is ever exposed another way, only honor `Fly-Client-IP` when the peer is a Fly proxy address.

**Metrics endpoint is publicly routed and unauthenticated:**
- Risk: `GET /metrics` is registered on the public mux and exempt from rate limiting. It exposes request counts, Redis timing, and business counters (matches, poems completed, reports, rejected content).
- Files: `server/internal/gateway/gateway.go` (`Routes`), `server/internal/gateway/middleware.go` (`middleware` exemptions), `server/internal/metrics/metrics.go`
- Current mitigation: Nothing beyond obscurity of the path.
- Recommendations: Serve `/metrics` on the debug listener (`SW_DEBUG_ADDR`) instead of the public router, or require a bearer token for it.

**Content moderation is a seed list, and report evidence goes to shared logs:**
- Risk: `server/internal/sessions/banned_terms.txt` has 20 lines (the file-level comment calls it a seed list). `content.go` documents that splitting a term with interior symbols bypasses it. Moderation reports (`server/internal/moderation/moderation.go`, `LogSink`) write full poem lines and a user-supplied reason at WARN into the Fly log stream, which is retained and may be forwarded to a drain.
- Files: `server/internal/sessions/banned_terms.txt`, `server/internal/sessions/content.go`, `server/internal/moderation/moderation.go`
- Current mitigation: Reports omit participant and push tokens. Lines are length-capped by the 16 KiB body limit and per-line validation.
- Recommendations: Source a maintained blocklist before a wider release, and define a retention policy and access controls for log drains before the first TestFlight build.

**Client identifiers are stored in UserDefaults:**
- Risk: The participant bearer token lives in `UserDefaults` (`ios/Strangewords/Net/Keychain.swift`, `TokenStore`). It is readable from unencrypted device backups and by any code with sandbox access. The file header acknowledges this and calls the token short-lived.
- Files: `ios/Strangewords/Net/Keychain.swift`
- Current mitigation: Tokens are scoped to a single engagement and erased on dissolution (`TokenStore.clear`).
- Recommendations: Move to the Keychain for signed builds, now that the entitlements file exists.

**ATS exception ships in every configuration:**
- Risk: `NSAllowsLocalNetworking: true` is set in the base Info.plist properties in `ios/project.yml`, and the comment calls it "Dev-only," but it applies to Release builds too.
- Files: `ios/project.yml`
- Current mitigation: The exception only permits local-network connections, not arbitrary plain HTTP.
- Recommendations: Move the ATS key into a Debug-only config or remove it once local development uses HTTPS.

## Performance Bottlenecks

**Whole-session JSON on every poll and write:**
- Problem: Each `GET` (3 s poll per client) and each `POST` reads and rewrites the entire session JSON, including all lines and idempotency keys.
- Files: `server/internal/store/store.go` (`GetSession`, `SaveSession`), `server/internal/gateway/gateway.go` (`touchPresence`)
- Cause: The session is one Redis string. `touchPresence` writes it on every active-state poll just to update `LastSeen`.
- Improvement path: Keep presence in a separate key or hash field with its own short TTL, and write the session only on turn changes. Current volume is small (a poem is three lines), so this is a scaling concern rather than a present one.

**Per-process rate limiter state:**
- Problem: Token buckets live in process memory. With `auto_stop_machines = "stop"` and `min_machines_running = 1` in `server/fly.toml`, scaling to more machines multiplies the effective per-IP budget, and the buckets reset on restart.
- Files: `server/internal/gateway/middleware.go`, `server/fly.toml`
- Cause: No shared store for limiter state.
- Improvement path: Acceptable for one machine. If the service scales out, move limiter counters to Redis (`INCR` with an expiry window).

## Fragile Areas

**Turn logic and session view coupling:**
- Files: `server/internal/sessions/session.go`, `server/internal/sessions/policy.go`, `server/internal/gateway/gateway.go` (`handleLine`)
- Why fragile: `CurrentAuthor` is derived from `CurrentLine`, `StartIndex`, and the participant count on every call. `handleLine` checks `req.Line`, then `idx`, then appends and mutates `CurrentLine`, while `touchPresence` can rewrite the same blob concurrently (see Known Bugs).
- Safe modification: Change turn rules only in `TurnPolicy` with tests in `server/internal/sessions/policy_test.go`. Run `TestTurnOrderViolations` and `TestMatchRaceSingleSession` after any change.
- Test coverage: Policy and validation have unit tests. There is no concurrency test for simultaneous `POST /line` plus polling.

**Idempotency key tracking:**
- Files: `server/internal/gateway/gateway.go` (`handleLine`, `IdemKeys`), `server/internal/store/store.go` (`IdemGet`, `IdemSet`, `DeleteSession`)
- Why fragile: `IdemSet` writes the cached response before the session records the key in `IdemKeys`. A failed session save after `IdemSet` leaves an idempotency entry that teardown will not find, so it is not erased and only expires after `IdemTTL` (10 min). The key list grows on every submitted line and is stored in the session blob.
- Safe modification: Record the key in the same write as the line, or derive the idempotency key name from the session and line so teardown can delete it without the list.
- Test coverage: `TestIdempotentResubmit` covers replay, not partial failure.

**iOS app state machine:**
- Files: `ios/Strangewords/App/AppModel.swift` (polling tasks, `stopPolling`, `leave`, `dismiss`), `ios/Strangewords/App/RootView.swift`
- Why fragile: Polling is driven by a single `pollTask` that is cancelled and replaced on each transition. Transient errors are swallowed ("keep polling"), so a server that stops responding leaves the UI in its last state with no error surfaced.
- Safe modification: Change transitions in `AppModel` only, and verify with `SW_LOCAL_MOCK=1` (`LocalBackend`) and with `./live_test.sh`.
- Test coverage: No iOS test target exists in `ios/project.yml`.

## Scaling Limits

**Single Redis and single machine:**
- Current capacity: One `shared-cpu-1x` / 256 MB machine (`server/fly.toml`), one Redis instance, `GOMEMLIMIT` set to 220 MiB.
- Limit: All queue state, sessions, and rate-limit counters are in one process plus one Redis. Redis is started with `--save "" --appendonly no` in `server/docker-compose.yml`, so restarts drop all in-flight poems by design (`server/DEPLOY.md`).
- Scaling path: Add a Redis replica only if availability matters more than ephemerality. Move the rate limiter to Redis before running more than one machine (see Performance Bottlenecks).

## Dependencies at Risk

**Go toolchain version split:**
- Risk: `server/go.mod` declares `go 1.25.0`, while `server/Dockerfile` builds from `golang:1.26-alpine`. Both are current, but they can drift on the next upgrade.
- Impact: CI and local builds may diverge if one is bumped and not the other.
- Migration plan: Pin both to the same minor version and document it in `server/Makefile` or `server/DEPLOY.md`.

## Missing Critical Features

**Push notifications (APNs):**
- Problem: `push.Noop` is wired in `server/cmd/server/main.go`. The app polls every 3 s instead.
- Blocks: Async play (leaving the app and getting a "your turn" nudge). Blocked on an Apple developer account and APNs key, per `docs/STATUS.md`.

**In-app report flow and EULA gate:**
- Problem: `POST /v1/session/{id}/report` exists on the server and has a test (`server/internal/gateway/report_test.go`), but no iOS code calls it (no `report(` call site in `ios/Strangewords`). `docs/STATUS.md` lists the EULA gate as remaining.
- Blocks: User-facing abuse reporting, which the moderation design assumes for App Store review.

**Turn timeout and skip:**
- Problem: A participant who never takes their turn can hold the other participant until the session TTL expires.
- Blocks: Reliable completion of poems when a partner goes silent. Related to the abandoned-waiter bug above.

## Test Coverage Gaps

**Store and matchmaker lack direct tests:**
- What's not tested: `server/internal/store/store.go` (TTL behavior, `PopWaiter` stale-id skipping, `DeleteSession` key set) and `server/internal/matchmaker/matchmaker.go` have no `_test.go` files. Coverage comes only indirectly through `gateway_test.go` and `main_test.go`, which use miniredis.
- Files: `server/internal/store/store.go`, `server/internal/matchmaker/matchmaker.go`
- Risk: The leak of wait records after dissolution and the stale-id skip logic would not be caught.
- Priority: High

**Concurrent session writes:**
- What's not tested: Simultaneous `POST /line` and `GET /session` against the same session, which is where the read-modify-write race lives.
- Files: `server/internal/gateway/gateway_test.go`
- Risk: Lost line or status updates that only appear under real polling load.
- Priority: High

**Metrics, moderation, push, config, and bot:**
- What's not tested: `server/internal/metrics/metrics.go`, `server/internal/moderation/moderation.go`, `server/internal/push/push.go`, `server/internal/config/config.go`, and `server/cmd/bot/main.go` have no tests.
- Files: as listed
- Risk: Config parsing regressions (e.g. `SW_REDIS_ADDR` URL handling in `main.go`) and moderation capture failures would go unnoticed.
- Priority: Medium

**iOS client:**
- What's not tested: No unit or UI test target exists. The state machine in `ios/Strangewords/App/AppModel.swift` and the `APIClient` error mapping in `ios/Strangewords/Net/APIClient.swift` are verified only manually or with `live_test.sh`.
- Files: `ios/project.yml`, `ios/Strangewords/App/AppModel.swift`, `ios/Strangewords/Net/APIClient.swift`
- Risk: Regressions in turn handling and error-to-state mapping (e.g. the 410 and 409 branches).
- Priority: Medium

---

*Concerns audit: 2026-10-08*
