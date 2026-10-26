---
last_mapped_commit: 4196ce5e0ccea3955e6a70452d0cded834a85ad4
last_mapped_at: 2026-10-08
---
<!-- refreshed: 2026-10-08 -->

# Architecture

**Analysis Date:** 2026-10-08

## System Overview

```text
┌──────────────────────────────────────────────────────────────────────┐
│                 iOS app — SwiftUI, iOS 17+ (`ios/Strangewords`)       │
│  App/AppModel (@MainActor @Observable phase machine) → RootView       │
│  Features/{Threshold,Waiting,Compose,Reveal,Dissolved}  Design/*      │
├──────────────────────────────┬───────────────────────────────────────┤
│  Net/Backend (protocol seam) │  Syllables/  Naming/  (on-device only) │
│  ├─ Net/APIClient  (actor)   │                                        │
│  └─ Net/LocalBackend (actor, │                                        │
│     mock stranger; dev only) │                                        │
└──────────────┬───────────────┴───────────────────────────────────────┘
               │ HTTPS JSON, polling every 3s; Bearer participantToken
               ▼
┌──────────────────────────────────────────────────────────────────────┐
│        Go service — `server/cmd/server/main.go` (single deployable)   │
│  internal/gateway   HTTP routes, handlers, auth, rate limit, panic     │
│  internal/matchmaker  enqueue / pop-and-pair                           │
│  internal/sessions  pure domain: Form, TurnPolicy, Session, validation │
│  internal/store     Redis persistence, TTLs, token refs, idempotency   │
│  internal/push      Notifier interface (Noop today)                    │
│  internal/moderation Sink interface (LogSink today)                    │
│  internal/metrics   Prometheus counters / histograms                   │
│  internal/config    env-driven config                                  │
└──────────────┬───────────────────────────────────────────────────────┘
               ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Redis (ephemeral, all keys TTL-bounded)  `sw:queue:*` `sw:wait:*`     │
│  `sw:tok:*` `sw:sess:*` `sw:idem:*`          (no durable store yet)   │
└──────────────────────────────────────────────────────────────────────┘
```

`server/cmd/bot/main.go` is a second binary: a robot poet that acts as an automated client of the same HTTP API for end-to-end testing (`live_test.sh`, `run_test_server_and_robot_poet_friend.sh`).

## Pattern Overview

**Overall:** Two-tier client/server. A single Go service exposes a JSON-over-HTTPS API backed by Redis; a native SwiftUI client drives a finite state machine from that API. The server keeps a layered "pure domain + thin infrastructure + HTTP gateway" split; the client is a state-machine-driven, view-as-function-of-state app with a swappable network seam.

**Key Characteristics:**
- **Anonymity by construction:** no accounts. Identity is a single 32-byte random `participantToken` (bearer) issued on `enter`; no identifier a partner could recognize is ever issued (`plan.v1.md` §4, `server/internal/store/store.go` `NewToken`).
- **Ephemeral state:** every operational key has a TTL; dissolution deletes session data and tokens. The only planned durable store is the Phase 5 moderation store; today reports go to structured logs (`server/internal/moderation/moderation.go` `LogSink`).
- **Data-driven poem shape:** poem structure is a `Form` registry value (`server/internal/sessions/form.go`, `haiku` = targets `[5,7,5]`) and authorship is a separate pluggable `TurnPolicy` (`server/internal/sessions/policy.go`, `round-robin`). Neither is hardcoded in the runtime.
- **Polling, not sockets:** HTTP request/response only; the client polls `GET /v1/waiting` or `GET /v1/session/{id}` every 3 seconds (`ios/Strangewords/App/AppModel.swift` `pollInterval`). Push is stubbed behind `push.Notifier`.
- **Theme as a bundle:** the visual identity is a `SceneTheme` protocol that bundles palette, scene background, and dissolution effect (`ios/Strangewords/Design/SceneTheme.swift`).
- **Dependency-injected seams with dev/mock implementations:** `push.Noop`, `moderation.LogSink`, `LocalBackend`, and `Dev` flags are all selected at composition time.

## Layers

### Server (Go, module `strangewords`)

**Domain (pure):**
- Location: `server/internal/sessions/`
- Contains: `Session`, `Participant`, `Status` (`active` / `complete` / `dissolved`), `Form`, `TurnPolicy`, `CleanLine` / validation, `Screener` (banned-term matching in `content.go`, list in `banned_terms.txt`).
- Depends on: standard library only (`time`, `strings`, `unicode`).
- Used by: `store`, `matchmaker`, `gateway`.
- Note: `Session.ViewFor(token)` in `session.go` produces the per-participant view returned to clients, so redaction rules live in the domain.

**Persistence:**
- Location: `server/internal/store/store.go`
- Contains: `Store` wrapping `*redis.Client`; key builders (`queueKey`, `waitKey`, `tokKey`, `sessKey`, `idemKey`); TTL constants (`SessionTTL` 90m, `RevealTTL` 120s, `WaitTTL` 15m, `IdemTTL` 10m); atomic `PopWaiter` via `LPOP`; idempotency cache `IdemGet`/`IdemSet`; `DeleteSession` for teardown.
- Depends on: `sessions` (serializes `Session` as a JSON blob at `sw:sess:{id}`), `go-redis/v9`.
- Used by: `matchmaker`, `gateway`.

**Coordination:**
- Location: `server/internal/matchmaker/matchmaker.go`
- Contains: `Matchmaker.Enter` → `enqueue` (no partner waiting) or `pair` (pop a waiter, build a `Session`, save refs for both tokens). Returns a `Result` describing matched vs. waiting.
- Depends on: `store`, `sessions`.
- Used by: `gateway` (`handleEnter`).

**HTTP gateway:**
- Location: `server/internal/gateway/gateway.go`, `server/internal/gateway/middleware.go`
- Contains: `Server` struct built by `New(st, mm, notifier, mod, log, cfg)`; `Routes()` registers Go 1.22 method+path patterns; handlers; `authSession` (bearer → session + participant index); `dissolve`; `maybePush`; `writeJSON` / `writeErr`. Middleware: `limitBody` (16 KiB cap), `recoverPanic` (→ 500), `rateLimiter` (token bucket keyed by `Fly-Client-IP` via `clientIP`, with `runJanitor` idle sweep).
- Depends on: `store`, `matchmaker`, `sessions`, `push`, `moderation`, `metrics`, `config`.
- Used by: `cmd/server/main.go`.

**Side-effect seams:**
- `server/internal/push/push.go`: `Notifier` interface, `Noop` implementation. APNs client not yet written.
- `server/internal/moderation/moderation.go`: `Sink` interface, `LogSink` implementation. Report captures omit participant and push tokens.
- `server/internal/metrics/metrics.go`: Prometheus RED HTTP metrics, Redis command timing, business counters; exposed at `GET /metrics`.

**Composition root:**
- Location: `server/cmd/server/main.go`
- Responsibilities: parse Redis config (`redisOptions` accepts `host:port` or `redis://` / `rediss://` URL), ping Redis, wire `store` → `matchmaker` → `gateway`, configure `http.Server` timeouts, start rate-limiter maintenance, optional pprof debug server on `SW_DEBUG_ADDR`, graceful shutdown on SIGINT/SIGTERM.

### Client (iOS, SwiftUI)

**App shell and state machine:**
- Location: `ios/Strangewords/App/`
- Contains: `StrangewordsApp.swift` (entry), `AppModel.swift` (state machine), `RootView.swift` (theme + time-of-day environment, phase switch, dev chips, `SceneDepthOverlay`), `Haptics.swift`, `Dev.swift`.
- Depends on: `Net/` (via `Backend`), `Design/`, `Features/`.

**Network:**
- Location: `ios/Strangewords/Net/`
- Contains: `Backend.swift` (protocol: `enter`, `waiting`, `getSession`, `submitLine`, `leave`, `dismiss`), `APIClient.swift` (`actor`, production HTTPS client; base defaults to `https://api.strangewords.app`, overridable with `SW_API_BASE`), `LocalBackend.swift` (`actor`, on-device fake stranger), `Models.swift` (Codable `SessionView`, `FormView`, `EnterResponse`, `WaitingResponse`, `ServerError`), `Keychain.swift` (`TokenStore`, backed by UserDefaults despite the filename).

**Feature views:**
- Location: `ios/Strangewords/Features/{Threshold,Waiting,Compose,Reveal,Dissolved}/`
- Contains: one SwiftUI view per phase. `SplashLines.swift` holds the randomized tagline. Views are pure functions of `AppModel.phase`.

**Design system:**
- Location: `ios/Strangewords/Design/`
- Contains: `Theme.swift` (typography, `Palette`, `TimeOfDay`), `Pixel.swift` and `PixelScene.swift` (shared pixel primitives and scene), `SceneTheme.swift` (protocol + `Themes` registry + `\.sceneTheme` environment key), `Themes/{NatureTheme,SciFiTheme,FantasyTheme}.swift`, `Dissolution.swift` (`DissolutionEffect` implementations), `RitualButton.swift` (`.buttonStyle(.ritual)`), `SceneBackground.swift` (retained vector scene, currently unused).

**On-device logic:**
- `ios/Strangewords/Syllables/Syllables.swift`: vowel-cluster syllable hint, a soft nudge only.
- `ios/Strangewords/Naming/PoemNaming.swift`: deterministic keepsake-name coiner (SplitMix64 seeded by FNV-1a of the poem text). Nothing is sent to the server.

## Data Flow

### Primary Request Path: entering and matching

1. The threshold screen calls `AppModel.begin()` (`ios/Strangewords/App/AppModel.swift`), which calls `api.enter(pushToken: nil)`.
2. `APIClient` sends `POST /v1/enter`. The gateway's `handleEnter` (`server/internal/gateway/gateway.go`) calls `Matchmaker.Enter`.
3. `matchmaker.enqueue` writes a `WaitEntry` with `store.Enqueue` and returns `waiting`, or `matchmaker.pair` pops a waiter with `store.PopWaiter` (atomic `LPOP`) and creates a `sessions.Session`.
4. The response carries `participantToken`. `TokenStore.token` persists it. `handleEnter` routes the app to `.waiting` or `.composing`.

### Turn loop: writing a line

1. `ComposeView` edits `AppModel.draft`. Submitting calls `AppModel.submit` → `api.submitLine(id:token:line:text:idemKey:)`.
2. `POST /v1/session/{id}/line` runs `handleLine` (`server/internal/gateway/gateway.go`). Order of operations:
   - `authSession` resolves the bearer token to the session and participant index via `store.GetRef`, then `store.GetSession`.
   - The `Idempotency-Key` in the body is checked against `store.IdemGet`. A replay returns the cached response verbatim.
   - `sessions.CleanLine` and `Screener.Rejects` validate the text (422 on banned terms).
   - The domain enforces turn order through `TurnPolicy.Author`.
   - On completion, `Status` becomes `complete` and `RevealTTL` (120s) is applied with `store.SaveSessionTTL`.
3. The response is `Session.ViewFor(token)`, which the client decodes into `SessionView`.

### Polling and state sync

1. `AppModel` runs `pollTask` every 3 seconds, calling `getSession` (or `waiting` while in the queue).
2. Each response is mapped onto a `Phase` case: `.waiting`, `.composing`, `.reveal`, `.dissolving`, or `.dissolved(Reason)`.
3. `RootView` switches on `phase`. Haptics fire on real transitions, detected in `AppModel.apply` by reading the outgoing phase.

### Dissolution and teardown

1. The user taps "let it go", and `AppModel.release()` moves to `.dissolving`. `RootView` plays the full-screen `DissolutionEffect` for the active theme.
2. `AppModel.finishDissolving()` coins a keepsake name from the poem text while the lines are still in memory (`PoemNaming`), then moves to `.dissolved(.completedAndGone)`.
3. Server side, `gateway.dissolve` (`server/internal/gateway/gateway.go`) calls `store.DeleteSession` and increments the dissolved metric. The zero-keys-after-dissolution invariant is covered by tests.

**State Management:**
- Server: all poem state lives in the Redis JSON blob at `sw:sess:{id}`. Redis TTLs bound lifetimes so abandoned state self-expires with no sweeper.
- Client: `AppModel` is the single source of truth (`@Observable`, `@MainActor`). `draft`, `submitError`, `submitting`, and `keepsake` are held there too.

## Key Abstractions

**`Session` (server) and `SessionView` (client):**
- Purpose: the encounter (pair of anonymous participants) plus its current poem.
- Server: `server/internal/sessions/session.go`. Encounter-level fields (`ID`, `Participants`, `StartIndex`, `Bucket`) are separated from poem-level fields (`Status`, `FormID`, `PolicyID`, `Lines`, `CurrentLine`), so a future "continue with this person" can start a new poem inside the same encounter.
- Client: `ios/Strangewords/Net/Models.swift`.

**`Form`:**
- Purpose: the text shape of a poem (line count and per-line syllable targets, where `nil` means no nudge).
- Examples: `server/internal/sessions/form.go` (`LookupForm`, registry with `haiku`).
- Pattern: registry lookup by ID. New forms are registry entries.

**`TurnPolicy`:**
- Purpose: decides which participant writes line N.
- Examples: `server/internal/sessions/policy.go` (`roundRobin.Author`, `LookupPolicy`).
- Pattern: strategy interface selected by `PolicyID` and stored on the session.

**`Store` / `Matchmaker` / `Server`:**
- Purpose: layered coordination. `Store` owns Redis keys, `Matchmaker` owns pairing rules, and `Server` owns HTTP concerns.
- Examples: `server/internal/store/store.go`, `server/internal/matchmaker/matchmaker.go`, `server/internal/gateway/gateway.go`.

**`Backend` (client):**
- Purpose: network seam. `AppModel` depends only on the protocol, so the same state machine runs against `APIClient` or `LocalBackend`.
- Examples: `ios/Strangewords/Net/Backend.swift`.
- Pattern: protocol injection in `AppModel.init(backend:)`.

**`SceneTheme`:**
- Purpose: a theme bundles palette per time of day, a procedural background, and a dissolution effect.
- Examples: `ios/Strangewords/Design/Themes/NatureTheme.swift`, `SciFiTheme.swift`, `FantasyTheme.swift`, registered in `Themes.all` in `ios/Strangewords/Design/SceneTheme.swift`.
- Pattern: protocol with registry plus SwiftUI environment injection.

**`Notifier` / `Sink`:**
- Purpose: side-effect seams for push and moderation.
- Examples: `server/internal/push/push.go` (`Noop`), `server/internal/moderation/moderation.go` (`LogSink`).
- Pattern: interface with a no-op or log implementation today, and a real implementation planned.

## Entry Points

**Backend server:**
- Location: `server/cmd/server/main.go` (`func main`)
- Triggers: container start on Fly.io (`server/fly.toml`, `server/Dockerfile`), or `make run` in `server/Makefile` (local Redis via `server/docker-compose.yml`).
- Responsibilities: wire the composition root, serve the API on `SW_ADDR` (default `:8080`), and expose `/healthz` and `/metrics`.

**Robot poet / bot client:**
- Location: `server/cmd/bot/main.go`
- Triggers: `run_test_server_and_robot_poet_friend.sh`, `live_test.sh`.
- Responsibilities: an automated participant that enters, waits, and writes lines through the public API.

**iOS app:**
- Location: `ios/Strangewords/App/StrangewordsApp.swift`
- Triggers: launch from Xcode or `./run.sh` (XcodeGen project generated from `ios/project.yml`).
- Responsibilities: create `AppModel` (real, mock, or dev backend via `SW_LOCAL_MOCK`), render `RootView`.

**CI deploy:**
- Location: `.github/workflows/fly-deploy.yml`
- Triggers: push to `main`, runs `flyctl deploy --remote-only`.

## Architectural Constraints

- **Threading:** The Go server is goroutine-per-request under `net/http`. Atomicity relies on Redis operations (`LPOP` for matchmaking, `SETs` with TTL). The iOS app runs the state machine on the main actor (`AppModel` is `@MainActor`). Network clients are actors (`APIClient`, `LocalBackend`).
- **Global state:** `TokenStore` is backed by `UserDefaults.standard`, so the participant token is process-global. `metrics` registers Prometheus collectors at package init via `promauto`. `net/http/pprof` registers on `http.DefaultServeMux` via a blank import in `server/cmd/server/main.go`, so the debug mux is global.
- **Circular imports:** None detected. The intended direction is `gateway` → `matchmaker` → `store` → `sessions`, with `sessions` importing nothing internal.
- **Storage mismatch to watch:** `plan.v1.md` §3 lists `docs/api.md`, but no such file is tracked. The API contract lives in `plan.v1.md` §7 and in the handler code.
- **Mock and real paths must stay in sync:** `LocalBackend` duplicates server semantics (turn order, dissolution) in Swift. Changes to the contract must be mirrored there.
- **Build artifacts:** The `.xcodeproj` and generated `Info.plist` are gitignored, so `ios/project.yml` is the source of truth for the Xcode target.

## Anti-Patterns

### Hard-coding poem structure in handlers or views

**What happens:** Line counts and syllable targets are read from `Form` values in the domain. Any literal `3` or `[5,7,5]` in a handler or SwiftUI view would bypass that.
**Why it's wrong:** It breaks the planned additive path to tanka, couplets, and free verse (`plan.v1.md` §5 and §13).
**Do this instead:** Read the shape through `Session.form()` / `LookupForm` in `server/internal/sessions/`, and read `FormView` in the client.

### Writing operational state outside `store`

**What happens:** Redis keys are built only in `server/internal/store/store.go`. Any `rdb.` call in `gateway` or `matchmaker` would fork key naming and TTL policy.
**Why it's wrong:** The dissolution invariant ("zero keys after dissolution") depends on every key going through the store's teardown path.
**Do this instead:** Add a `Store` method with its TTL, then have callers use that method.

### Putting redaction or participant logic in handlers

**What happens:** Per-participant views are built by `Session.ViewFor(token)` in `server/internal/sessions/session.go`.
**Why it's wrong:** Handlers that assemble JSON by hand can leak the partner's push token or raw participant list.
**Do this instead:** Return `ViewFor` output, and add fields to `View` rather than to the response struct.

### Persisting identity on the device beyond the engagement

**What happens:** `TokenStore` in `ios/Strangewords/Net/Keychain.swift` is cleared at mock launch and deleted on dissolution.
**Why it's wrong:** A token that outlives the encounter is a stable identifier and breaks the anonymity model.
**Do this instead:** Clear through `TokenStore` at every terminal phase.

## Error Handling

**Strategy:** Typed domain errors mapped to HTTP status and a stable `code` string at the gateway boundary; client-side errors surfaced as a single user-facing message.

**Patterns:**
- Server: `writeErr(w, status, code, msg)` in `server/internal/gateway/gateway.go` emits `{code, message}`. `s.fail(w, err)` maps `store.ErrNotFound` and domain errors to statuses. `recoverPanic` in `middleware.go` converts panics to 500.
- Client: `APIError` in `ios/Strangewords/Net/APIClient.swift`. `AppModel` sets `submitError` on failure (e.g. "Couldn't reach the quiet room") rather than crashing. `ServerError.Body` decodes the server `code`/`message`.

## Cross-Cutting Concerns

**Logging:** Server uses `log/slog` with a JSON handler on stdout (`cmd/server/main.go`), passed into the gateway. Logs never include the Redis password (the address is logged, not the options). Client has no logging framework; haptics and dev chips are the only out-of-band feedback.

**Validation:** Server-side is authoritative: `sessions/validate.go` for length and whitespace, `sessions/content.go` for the banned-term screener, and a 16 KiB body cap in `middleware.go`. Client-side `Syllables` is a hint, not a gate.

**Authentication:** A bearer `participantToken` on every session route. `authSession` checks the token against the session's participant list and rejects mismatches. Per-IP rate limiting in `middleware.go` uses `Fly-Client-IP`. App Attest is referenced in `ios/project.yml` for future use, but it is not enforced server-side yet.

**Observability:** Prometheus at `/metrics` (`server/internal/metrics/metrics.go`), `/healthz`, and pprof on a private `SW_DEBUG_ADDR` that must not be added to the public `fly.toml` service.

---

*Architecture analysis: 2026-10-08*
