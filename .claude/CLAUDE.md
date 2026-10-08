<!-- GSD:project-start source:PROJECT.md -->

## Project

**Stranger Words**

An anonymous, ephemeral iOS app ("Stranger Words") for writing a 3-line poem with a stranger, then letting it go. A SwiftUI client (iOS 17+) drives a phase state machine against a Go backend (live on Fly.io, Redis-backed, all state TTL-bounded); no accounts, no history — the only durable keepsake is a whimsical name the poem coins for itself on-device.

The current milestone is not a new feature: it is **verifying the current state under GSD** — exercising everything automated, closing the iOS automated-test gap, fixing what breaks, and capturing the result as a validated baseline that future milestones (push, safety, TestFlight) build on.

**Core Value:** A trustworthy, automated proof that the core experience works — so every future change can be verified against a known-good baseline instead of memory and manual poking.

### Constraints

- **Tech stack**: Go stdlib-first backend, SwiftUI iOS 17+, no third-party iOS dependencies — established project convention
- **Tooling**: `.xcodeproj` is gitignored; `ios/project.yml` (XcodeGen) is the source of truth — test targets must be added there
- **Anonymity model**: tests must not introduce anything that persists identity or poem content beyond the encounter
- **Automated-only**: this milestone's verification must run without a human driving a simulator; manual UAT is explicitly deferred

<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->

## Technology Stack

## Languages

- Go 1.25 (module `strangewords`, `server/go.mod`) - backend server, bot client, and tests under `server/cmd/` and `server/internal/`
- Swift 5 (`SWIFT_VERSION: "5.0"` in `ios/project.yml`) - iOS app under `ios/Strangewords/`
- YAML - XcodeGen project spec (`ios/project.yml`), GitHub Actions workflow (`.github/workflows/fly-deploy.yml`), Docker Compose (`server/docker-compose.yml`), Fly config (`server/fly.toml`)
- Bash - dev/test scripts `run.sh`, `live_test.sh`, `run_test_server_and_robot_poet_friend.sh` at repo root
- Plain text - banned-term list `server/internal/sessions/banned_terms.txt`

## Runtime

- Go runtime. Dockerfile builds with `golang:1.26-alpine` (`server/Dockerfile`); `go.mod` declares `go 1.25.0`
- Static binary (`CGO_ENABLED=0`, `-trimpath -ldflags="-s -w"`) run in `alpine:3.20` as non-root user `app` (uid 10001)
- Runtime memory tuned via `GOMEMLIMIT = "220MiB"` in `server/fly.toml`; `go.uber.org/automaxprocs` aligns GOMAXPROCS to the cgroup CPU quota
- iOS 17.0 minimum deployment target (`ios/project.yml`), iPhone and iPad (`TARGETED_DEVICE_FAMILY: "1,2"`), though orientation is portrait-only in `Info.plist` settings
- Bundle identifier `com.strangerwords.us`, team `2M6QRD8T3A`, display name "Stranger Words", marketing version 0.1.0 (build 1)
- Go modules - `server/go.mod`, lockfile `server/go.sum` present
- Swift Package Manager - not used; the iOS app has no third-party dependencies (per `docs/STATUS.md`)
- XcodeGen - generates `ios/Strangewords.xcodeproj` from `ios/project.yml`; the generated project and `Info.plist` are gitignored

## Frameworks

- Standard library `net/http` with Go 1.22+ method-pattern routing (`mux.HandleFunc("POST /v1/enter", ...)` in `server/internal/gateway/gateway.go`)
- `log/slog` JSON handler for structured logging (`server/cmd/server/main.go`)
- `net/http/pprof` - debug profiling, exposed only on `SW_DEBUG_ADDR` (not public)
- SwiftUI - all UI (`ios/Strangewords/App/`, `ios/Strangewords/Features/`)
- Canvas-based procedural pixel-art scenes and effects (`ios/Strangewords/Design/Pixel.swift`, `PixelScene.swift`, `Dissolution.swift`)
- UIKit-level APIs: `UserDefaults` (token storage, `Net/Keychain.swift`), haptics (`App/Haptics.swift`)
- Go `testing` package - unit tests in `server/internal/*/*_test.go` and `server/cmd/server/main_test.go`
- `github.com/alicebob/miniredis/v2` v2.38.0 - in-process Redis fake used by tests (no external Redis needed)
- `github.com/prometheus/client_golang/prometheus/testutil` - metrics assertions in tests
- No iOS test target is declared in `ios/project.yml`
- Docker and Docker Compose - local Redis (`server/docker-compose.yml`: `redis:7-alpine`, no persistence)
- Make - `server/Makefile` targets: `run`, `test`, `vet`, `build`, `tidy`, `redis`, `redis-stop`
- XcodeGen (`brew install xcodegen`) and `xcodebuild` / `xcrun simctl` - iOS build and simulator launch via `run.sh`
- Flyctl - deployment CLI (`server/DEPLOY.md`)

## Key Dependencies

- `github.com/redis/go-redis/v9` v9.20.1 - Redis client; all session, matchmaking, and TTL state (`server/internal/store/store.go`)
- `github.com/prometheus/client_golang` v1.23.2 - `/metrics` endpoint, RED HTTP metrics, Redis command timing, business counters (`server/internal/metrics/metrics.go`)
- `go.uber.org/automaxprocs` v1.6.0 - blank-imported in `server/cmd/server/main.go`
- `golang.org/x/text` v0.38.0 - Unicode normalization (`unicode/norm`) for line validation (`server/internal/sessions/`)
- `github.com/alicebob/miniredis/v2` v2.38.0
- Bundled fonts (no SPM packages): Fraunces (display serif, `Fraunces.ttf`, `Fraunces-SemiBold.ttf`, `Fraunces-Italic.ttf`) and Inter (`Inter.ttf`), registered via `UIAppFonts` in `ios/project.yml`; OFL licenses in `ios/Strangewords/Resources/Fonts`
- Build-time font instancing used `fonttools` via a script noted in `docs/STATUS.md` (not part of the repo build)
- Redis 7 (local via Docker Compose; production Redis endpoint supplied as a Fly secret, Upstash-style URL per `server/DEPLOY.md`)
- `ca-certificates` in the runtime image (Alpine package) for outbound TLS

## Configuration

- `SW_ADDR` - listen address, default `:8080`
- `SW_DEBUG_ADDR` - pprof listen address, default empty (disabled)
- `SW_REDIS_ADDR` - `host:port` or `redis://` / `rediss://` URL, default `127.0.0.1:6379`
- `SW_REDIS_PASSWORD` - Redis password, default empty
- `SW_REDIS_TLS` - any non-empty value enables TLS to Redis
- `SW_RATE_RPS` / `SW_RATE_BURST` - per-IP token bucket, defaults `30` / `60`; `0` disables
- `SW_APP_ATTEST_APPID` - Apple App ID for App Attest, default empty (see Concerns note below)
- `GOMEMLIMIT` - set in `server/fly.toml` `[env]`, not read by app code
- `ios/project.yml` is the source of truth; `Info.plist` is generated
- Build setting `APP_ATTEST_ENVIRONMENT`: `development` for Debug, `production` for Release
- Entitlements file `ios/Strangewords/Strangewords.entitlements` sets `com.apple.developer.devicecheck.appattest-environment` from that build setting
- `NSAppTransportSecurity.NSAllowsLocalNetworking: true` (dev-only plain HTTP to local backend)
- Dev-only environment flags read at launch: `SW_LOCAL_MOCK`, `SW_DEV`, `SW_FORCE_THEME`, `SW_FORCE_TOD`, `SW_DEV_DISSOLVE` (`ios/Strangewords/App/Dev.swift`)
- Backend base URL hardcoded in `ios/Strangewords/Net/APIClient.swift` as `https://api.strangerwords.us`
- `server/Dockerfile` - multi-stage build
- `server/fly.toml` - Fly app `strangerwords`, region `sjc`, `shared-cpu-1x` / 256 MB VM, `min_machines_running = 1`, health check `GET /healthz`
- `server/.dockerignore` (referenced in `docs/STATUS.md`)
- `ios/project.yml` - XcodeGen spec, iOS 17.0 target
- `.github/workflows/fly-deploy.yml` - push-to-deploy on `main` for `server/**` changes

## Platform Requirements

- Go 1.25+ toolchain (Docker build uses 1.26)
- Docker (for local Redis via `make redis`), or any reachable Redis 7 instance
- macOS with Xcode, `xcodegen` (Homebrew), and an iOS 17+ simulator for the app
- Optional: `flyctl` for manual deploys
- Fly.io, app `strangerwords`, primary region `sjc`, public at `https://strangerwords.fly.dev` (`docs/STATUS.md`); intended custom host `api.strangerwords.us` (cert/DNS step still pending per `docs/STATUS.md`)
- Managed Redis reached via `SW_REDIS_ADDR` secret
- Deploy trigger: GitHub Actions `fly-deploy.yml` using `FLY_API_TOKEN` secret, running `flyctl deploy --remote-only` from `server/`

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

## Scope of the Repo

- **Backend (Go 1.25):** `server/` (module name `strangewords`, see `server/go.mod`). Conventions below under Go.
- **iOS client (Swift, SwiftUI, iOS 17+):** `ios/Strangewords/`, generated by XcodeGen from `ios/project.yml`. Conventions below under Swift.
- **Docs and scripts:** `docs/`, `README.md`, `run.sh`, `live_test.sh`, `run_test_server_and_robot_poet_friend.sh` (bash).

## Naming Patterns

- Lowercase single-word file names: `middleware.go`, `validate.go`, `policy.go`, `store.go`, `matchmaker.go` (`server/internal/<pkg>/<name>.go`).
- Tests are `<name>_test.go` next to the code they cover, e.g. `server/internal/sessions/validate_test.go`.
- Packages are short lowercase nouns: `sessions`, `gateway`, `store`, `matchmaker`, `moderation`, `push`, `metrics`, `config`.
- Exported: PascalCase (`CleanLine`, `MaxLineLen`, `ErrEmptyLine`, `ErrNotFound`).
- Unexported: camelCase (`limitBody`, `recoverPanic`, `newRateLimiter`, `maxBodyBytes`).
- Sentinel errors are package vars named `Err<Condition>` with `errors.New`: `ErrEmptyLine`, `ErrLineTooLong`, `ErrBadChars` in `server/internal/sessions/validate.go`; `ErrNotFound` in `server/internal/store/store.go`.
- Constructors are `New(...)` or `newX(...)` (`store.New`, `matchmaker.New`, `gateway.New`, `newRateLimiter`).
- Tunables carry a `[TUNABLE]` marker in their doc comment (`MaxLineLen` in `validate.go`, TTL constants in `store.go`, `strangerThinkTime` in `ios/Strangewords/Net/LocalBackend.swift`). Keep this marker on any new constant that is expected to be tuned.
- Design-doc references are cited in comments (`plan.v1.md §5/§6`, `brief.v4.md §9`). Preserve these citations when editing the corresponding logic.
- One primary type per file, named after the type: `APIClient.swift` (`actor APIClient`), `AppModel.swift` (`final class AppModel`), `LocalBackend.swift` (`actor LocalBackend`).
- Directories group by responsibility: `App/`, `Net/`, `Design/`, `Design/Themes/`, `Features/<Feature>/`, `Syllables/`, `Naming/`.
- Types are PascalCase; members are camelCase. Nested enums hold state (`AppModel.Phase`, `AppModel.Reason`, `APIError`).
- Wire-model fields mirror the server JSON keys exactly (camelCase), e.g. `SessionView.sessionId`, `currentLine`, `participantCount` in `ios/Strangewords/Net/Models.swift`.
- Backend: `SW_` prefix, SCREAMING_SNAKE_CASE (`SW_ADDR`, `SW_REDIS_ADDR`, `SW_RATE_RPS`). Read through the `env(key, def)` and `envFloat(key, def)` helpers in `server/internal/config/config.go`. Add new settings there with a default, never by calling `os.Getenv` in a feature package.
- iOS: `SW_API_BASE` is read from `ProcessInfo.processInfo.environment` in `APIClient`. Build-time values are set per config in `ios/project.yml` (e.g. `APP_ATTEST_ENVIRONMENT`).

## Code Style

- Standard `gofmt` output. Run `gofmt -l server/` before committing. Some files in `server/internal/sessions/validate.go` and `server/internal/store/store.go` have hand-aligned `var` and `const` blocks that gofmt will realign; accept gofmt's output.
- Makefile targets: `make vet` (`go vet ./...`), `make build`, `make test`, `make tidy` (see `server/Makefile`).
- Four-space indentation, no trailing semicolons, `// MARK: - Section` headers for extension groupings (`ios/Strangewords/Design/Theme.swift`).
- Doc comments use `///` on types and non-obvious members. Line comments use `//`.
- Prefer `struct` for value models (`SessionView`, `FormView`) and `actor` for mutable network/backend state (`APIClient`, `LocalBackend`). Use `@MainActor @Observable final class` for UI state (`AppModel`).

## Import Organization

## Error Handling

- Wrap with `fmt.Errorf` when adding context, and compare with `errors.Is` (never `==`), e.g. `errors.Is(err, store.ErrNotFound)` in `server/internal/gateway/gateway.go` and `server/internal/matchmaker/matchmaker.go`.
- Map domain errors to HTTP responses in handlers via `writeErr(w, status, code, message)` in `server/internal/gateway/gateway.go`. The `code` is a stable snake_case token the client switches on: `redis_down`, `no_token`, `session_gone`, `internal`.
- Unexpected failures are logged with `s.log.Error("internal error", "err", err)` and return a generic message to the client. Never leak `err.Error()` to HTTP responses.
- Panics are converted to 500 responses by the outermost middleware `recoverPanic` in `server/internal/gateway/middleware.go`.
- Non-fatal side-effect failures (push, dissolve, report capture) are logged at `Warn` or `Error` and do not fail the request (`server/internal/gateway/gateway.go`, around lines 349-431).
- Network failures are normalized to the `APIError` enum in `ios/Strangewords/Net/APIClient.swift` (`gone`, `notYourTurn`, `wrongTurn`, `contentRejected(String)`, `http(Int)`, `transport`). UI code switches on these cases; it never inspects raw `URLError`.
- Calls are `async throws`. Best-effort operations use `try?` (about 27 occurrences across `ios/Strangewords`). Use `try?` only when the failure is safe to ignore; otherwise propagate and map to `APIError`.

## Logging

## Comments

- Explain *why* and reference the design doc section when a rule comes from it (`// Dev-only: allow plain HTTP...` in `ios/project.yml`; `// Normalize to NFC first so length and character checks are stable.` in `server/internal/sessions/validate.go`).
- Mark tunables with `[TUNABLE]`.
- Mark security-sensitive config inline (`// e.g. ":6060" — reach via fly proxy, never expose publicly` in `server/internal/config/config.go`).

## Function Design

- Handlers are methods on `*Server` with the signature `func (s *Server) handleX(w http.ResponseWriter, r *http.Request)`.
- Middleware is `func(next http.Handler) http.Handler`, composed in `Routes()`.
- Dependencies (store, matchmaker, notifier, moderation sink, logger, config) are passed in the constructor, not read from globals. Time is injected as `now func() time.Time` for tests (`server/internal/gateway/middleware.go`).
- Policies are behind an interface with a lookup, e.g. `LookupPolicy("round-robin")` in `server/internal/sessions/policy.go`.
- Feature views are pure functions of `AppModel.phase`. Do not add new state to a view when it belongs on `AppModel`.
- Protocols abstract the backend: `Backend` is implemented by both `APIClient` (production) and `LocalBackend` (on-device stand-in). New backend calls must be added to the protocol and both implementations.

## Module Design

## Where Conventions Are Not Yet Uniform

- Keep new sentinel errors in the same file as the function that returns them, matching `server/internal/sessions/validate.go`.
- The Swift `Design/` folder mixes theme data (`Themes/*.swift`) with rendering helpers (`PixelScene.swift`). New theme data goes in `Design/Themes/`; new drawing code goes beside `PixelScene.swift`.

<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

## System Overview

```text

```

## Pattern Overview

- **Anonymity by construction:** no accounts. Identity is a single 32-byte random `participantToken` (bearer) issued on `enter`; no identifier a partner could recognize is ever issued (`plan.v1.md` §4, `server/internal/store/store.go` `NewToken`).
- **Ephemeral state:** every operational key has a TTL; dissolution deletes session data and tokens. The only planned durable store is the Phase 5 moderation store; today reports go to structured logs (`server/internal/moderation/moderation.go` `LogSink`).
- **Data-driven poem shape:** poem structure is a `Form` registry value (`server/internal/sessions/form.go`, `haiku` = targets `[5,7,5]`) and authorship is a separate pluggable `TurnPolicy` (`server/internal/sessions/policy.go`, `round-robin`). Neither is hardcoded in the runtime.
- **Polling, not sockets:** HTTP request/response only; the client polls `GET /v1/waiting` or `GET /v1/session/{id}` every 3 seconds (`ios/Strangewords/App/AppModel.swift` `pollInterval`). Push is stubbed behind `push.Notifier`.
- **Theme as a bundle:** the visual identity is a `SceneTheme` protocol that bundles palette, scene background, and dissolution effect (`ios/Strangewords/Design/SceneTheme.swift`).
- **Dependency-injected seams with dev/mock implementations:** `push.Noop`, `moderation.LogSink`, `LocalBackend`, and `Dev` flags are all selected at composition time.

## Layers

### Server (Go, module `strangewords`)

- Location: `server/internal/sessions/`
- Contains: `Session`, `Participant`, `Status` (`active` / `complete` / `dissolved`), `Form`, `TurnPolicy`, `CleanLine` / validation, `Screener` (banned-term matching in `content.go`, list in `banned_terms.txt`).
- Depends on: standard library only (`time`, `strings`, `unicode`).
- Used by: `store`, `matchmaker`, `gateway`.
- Note: `Session.ViewFor(token)` in `session.go` produces the per-participant view returned to clients, so redaction rules live in the domain.
- Location: `server/internal/store/store.go`
- Contains: `Store` wrapping `*redis.Client`; key builders (`queueKey`, `waitKey`, `tokKey`, `sessKey`, `idemKey`); TTL constants (`SessionTTL` 90m, `RevealTTL` 120s, `WaitTTL` 15m, `IdemTTL` 10m); atomic `PopWaiter` via `LPOP`; idempotency cache `IdemGet`/`IdemSet`; `DeleteSession` for teardown.
- Depends on: `sessions` (serializes `Session` as a JSON blob at `sw:sess:{id}`), `go-redis/v9`.
- Used by: `matchmaker`, `gateway`.
- Location: `server/internal/matchmaker/matchmaker.go`
- Contains: `Matchmaker.Enter` → `enqueue` (no partner waiting) or `pair` (pop a waiter, build a `Session`, save refs for both tokens). Returns a `Result` describing matched vs. waiting.
- Depends on: `store`, `sessions`.
- Used by: `gateway` (`handleEnter`).
- Location: `server/internal/gateway/gateway.go`, `server/internal/gateway/middleware.go`
- Contains: `Server` struct built by `New(st, mm, notifier, mod, log, cfg)`; `Routes()` registers Go 1.22 method+path patterns; handlers; `authSession` (bearer → session + participant index); `dissolve`; `maybePush`; `writeJSON` / `writeErr`. Middleware: `limitBody` (16 KiB cap), `recoverPanic` (→ 500), `rateLimiter` (token bucket keyed by `Fly-Client-IP` via `clientIP`, with `runJanitor` idle sweep).
- Depends on: `store`, `matchmaker`, `sessions`, `push`, `moderation`, `metrics`, `config`.
- Used by: `cmd/server/main.go`.
- `server/internal/push/push.go`: `Notifier` interface, `Noop` implementation. APNs client not yet written.
- `server/internal/moderation/moderation.go`: `Sink` interface, `LogSink` implementation. Report captures omit participant and push tokens.
- `server/internal/metrics/metrics.go`: Prometheus RED HTTP metrics, Redis command timing, business counters; exposed at `GET /metrics`.
- Location: `server/cmd/server/main.go`
- Responsibilities: parse Redis config (`redisOptions` accepts `host:port` or `redis://` / `rediss://` URL), ping Redis, wire `store` → `matchmaker` → `gateway`, configure `http.Server` timeouts, start rate-limiter maintenance, optional pprof debug server on `SW_DEBUG_ADDR`, graceful shutdown on SIGINT/SIGTERM.

### Client (iOS, SwiftUI)

- Location: `ios/Strangewords/App/`
- Contains: `StrangewordsApp.swift` (entry), `AppModel.swift` (state machine), `RootView.swift` (theme + time-of-day environment, phase switch, dev chips, `SceneDepthOverlay`), `Haptics.swift`, `Dev.swift`.
- Depends on: `Net/` (via `Backend`), `Design/`, `Features/`.
- Location: `ios/Strangewords/Net/`
- Contains: `Backend.swift` (protocol: `enter`, `waiting`, `getSession`, `submitLine`, `leave`, `dismiss`), `APIClient.swift` (`actor`, production HTTPS client; base defaults to `https://api.strangerwords.us`, overridable with `SW_API_BASE`), `LocalBackend.swift` (`actor`, on-device fake stranger), `Models.swift` (Codable `SessionView`, `FormView`, `EnterResponse`, `WaitingResponse`, `ServerError`), `Keychain.swift` (`TokenStore`, backed by UserDefaults despite the filename).
- Location: `ios/Strangewords/Features/{Threshold,Waiting,Compose,Reveal,Dissolved}/`
- Contains: one SwiftUI view per phase. `SplashLines.swift` holds the randomized tagline. Views are pure functions of `AppModel.phase`.
- Location: `ios/Strangewords/Design/`
- Contains: `Theme.swift` (typography, `Palette`, `TimeOfDay`), `Pixel.swift` and `PixelScene.swift` (shared pixel primitives and scene), `SceneTheme.swift` (protocol + `Themes` registry + `\.sceneTheme` environment key), `Themes/{NatureTheme,SciFiTheme,FantasyTheme}.swift`, `Dissolution.swift` (`DissolutionEffect` implementations), `RitualButton.swift` (`.buttonStyle(.ritual)`), `SceneBackground.swift` (retained vector scene, currently unused).
- `ios/Strangewords/Syllables/Syllables.swift`: vowel-cluster syllable hint, a soft nudge only.
- `ios/Strangewords/Naming/PoemNaming.swift`: deterministic keepsake-name coiner (SplitMix64 seeded by FNV-1a of the poem text). Nothing is sent to the server.

## Data Flow

### Primary Request Path: entering and matching

### Turn loop: writing a line

### Polling and state sync

### Dissolution and teardown

- Server: all poem state lives in the Redis JSON blob at `sw:sess:{id}`. Redis TTLs bound lifetimes so abandoned state self-expires with no sweeper.
- Client: `AppModel` is the single source of truth (`@Observable`, `@MainActor`). `draft`, `submitError`, `submitting`, and `keepsake` are held there too.

## Key Abstractions

- Purpose: the encounter (pair of anonymous participants) plus its current poem.
- Server: `server/internal/sessions/session.go`. Encounter-level fields (`ID`, `Participants`, `StartIndex`, `Bucket`) are separated from poem-level fields (`Status`, `FormID`, `PolicyID`, `Lines`, `CurrentLine`), so a future "continue with this person" can start a new poem inside the same encounter.
- Client: `ios/Strangewords/Net/Models.swift`.
- Purpose: the text shape of a poem (line count and per-line syllable targets, where `nil` means no nudge).
- Examples: `server/internal/sessions/form.go` (`LookupForm`, registry with `haiku`).
- Pattern: registry lookup by ID. New forms are registry entries.
- Purpose: decides which participant writes line N.
- Examples: `server/internal/sessions/policy.go` (`roundRobin.Author`, `LookupPolicy`).
- Pattern: strategy interface selected by `PolicyID` and stored on the session.
- Purpose: layered coordination. `Store` owns Redis keys, `Matchmaker` owns pairing rules, and `Server` owns HTTP concerns.
- Examples: `server/internal/store/store.go`, `server/internal/matchmaker/matchmaker.go`, `server/internal/gateway/gateway.go`.
- Purpose: network seam. `AppModel` depends only on the protocol, so the same state machine runs against `APIClient` or `LocalBackend`.
- Examples: `ios/Strangewords/Net/Backend.swift`.
- Pattern: protocol injection in `AppModel.init(backend:)`.
- Purpose: a theme bundles palette per time of day, a procedural background, and a dissolution effect.
- Examples: `ios/Strangewords/Design/Themes/NatureTheme.swift`, `SciFiTheme.swift`, `FantasyTheme.swift`, registered in `Themes.all` in `ios/Strangewords/Design/SceneTheme.swift`.
- Pattern: protocol with registry plus SwiftUI environment injection.
- Purpose: side-effect seams for push and moderation.
- Examples: `server/internal/push/push.go` (`Noop`), `server/internal/moderation/moderation.go` (`LogSink`).
- Pattern: interface with a no-op or log implementation today, and a real implementation planned.

## Entry Points

- Location: `server/cmd/server/main.go` (`func main`)
- Triggers: container start on Fly.io (`server/fly.toml`, `server/Dockerfile`), or `make run` in `server/Makefile` (local Redis via `server/docker-compose.yml`).
- Responsibilities: wire the composition root, serve the API on `SW_ADDR` (default `:8080`), and expose `/healthz` and `/metrics`.
- Location: `server/cmd/bot/main.go`
- Triggers: `run_test_server_and_robot_poet_friend.sh`, `live_test.sh`.
- Responsibilities: an automated participant that enters, waits, and writes lines through the public API.
- Location: `ios/Strangewords/App/StrangewordsApp.swift`
- Triggers: launch from Xcode or `./run.sh` (XcodeGen project generated from `ios/project.yml`).
- Responsibilities: create `AppModel` (real, mock, or dev backend via `SW_LOCAL_MOCK`), render `RootView`.
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

### Writing operational state outside `store`

### Putting redaction or participant logic in handlers

### Persisting identity on the device beyond the engagement

## Error Handling

- Server: `writeErr(w, status, code, msg)` in `server/internal/gateway/gateway.go` emits `{code, message}`. `s.fail(w, err)` maps `store.ErrNotFound` and domain errors to statuses. `recoverPanic` in `middleware.go` converts panics to 500.
- Client: `APIError` in `ios/Strangewords/Net/APIClient.swift`. `AppModel` sets `submitError` on failure (e.g. "Couldn't reach the quiet room") rather than crashing. `ServerError.Body` decodes the server `code`/`message`.

## Cross-Cutting Concerns

<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-fast` for a trivial task inline, with no subagents and no PLAN.md
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
