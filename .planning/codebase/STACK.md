---
last_mapped_commit: 4196ce5e0ccea3955e6a70452d0cded834a85ad4
last_mapped_at: 2026-10-08
---
# Technology Stack

**Analysis Date:** 2026-10-08

## Languages

**Primary:**
- Go 1.25 (module `strangewords`, `server/go.mod`) - backend server, bot client, and tests under `server/cmd/` and `server/internal/`
- Swift 5 (`SWIFT_VERSION: "5.0"` in `ios/project.yml`) - iOS app under `ios/Strangewords/`

**Secondary:**
- YAML - XcodeGen project spec (`ios/project.yml`), GitHub Actions workflow (`.github/workflows/fly-deploy.yml`), Docker Compose (`server/docker-compose.yml`), Fly config (`server/fly.toml`)
- Bash - dev/test scripts `run.sh`, `live_test.sh`, `run_test_server_and_robot_poet_friend.sh` at repo root
- Plain text - banned-term list `server/internal/sessions/banned_terms.txt`

## Runtime

**Server:**
- Go runtime. Dockerfile builds with `golang:1.26-alpine` (`server/Dockerfile`); `go.mod` declares `go 1.25.0`
- Static binary (`CGO_ENABLED=0`, `-trimpath -ldflags="-s -w"`) run in `alpine:3.20` as non-root user `app` (uid 10001)
- Runtime memory tuned via `GOMEMLIMIT = "220MiB"` in `server/fly.toml`; `go.uber.org/automaxprocs` aligns GOMAXPROCS to the cgroup CPU quota

**iOS:**
- iOS 17.0 minimum deployment target (`ios/project.yml`), iPhone and iPad (`TARGETED_DEVICE_FAMILY: "1,2"`), though orientation is portrait-only in `Info.plist` settings
- Bundle identifier `com.strangerwords.us`, team `2M6QRD8T3A`, display name "Stranger Words", marketing version 0.1.0 (build 1)

**Package Managers:**
- Go modules - `server/go.mod`, lockfile `server/go.sum` present
- Swift Package Manager - not used; the iOS app has no third-party dependencies (per `docs/STATUS.md`)
- XcodeGen - generates `ios/Strangewords.xcodeproj` from `ios/project.yml`; the generated project and `Info.plist` are gitignored

## Frameworks

**Server (Go):**
- Standard library `net/http` with Go 1.22+ method-pattern routing (`mux.HandleFunc("POST /v1/enter", ...)` in `server/internal/gateway/gateway.go`)
- `log/slog` JSON handler for structured logging (`server/cmd/server/main.go`)
- `net/http/pprof` - debug profiling, exposed only on `SW_DEBUG_ADDR` (not public)

**iOS (Swift):**
- SwiftUI - all UI (`ios/Strangewords/App/`, `ios/Strangewords/Features/`)
- Canvas-based procedural pixel-art scenes and effects (`ios/Strangewords/Design/Pixel.swift`, `PixelScene.swift`, `Dissolution.swift`)
- UIKit-level APIs: `UserDefaults` (token storage, `Net/Keychain.swift`), haptics (`App/Haptics.swift`)

**Testing:**
- Go `testing` package - unit tests in `server/internal/*/*_test.go` and `server/cmd/server/main_test.go`
- `github.com/alicebob/miniredis/v2` v2.38.0 - in-process Redis fake used by tests (no external Redis needed)
- `github.com/prometheus/client_golang/prometheus/testutil` - metrics assertions in tests
- No iOS test target is declared in `ios/project.yml`

**Build/Dev:**
- Docker and Docker Compose - local Redis (`server/docker-compose.yml`: `redis:7-alpine`, no persistence)
- Make - `server/Makefile` targets: `run`, `test`, `vet`, `build`, `tidy`, `redis`, `redis-stop`
- XcodeGen (`brew install xcodegen`) and `xcodebuild` / `xcrun simctl` - iOS build and simulator launch via `run.sh`
- Flyctl - deployment CLI (`server/DEPLOY.md`)

## Key Dependencies

**Critical (Go, from `server/go.mod`):**
- `github.com/redis/go-redis/v9` v9.20.1 - Redis client; all session, matchmaking, and TTL state (`server/internal/store/store.go`)
- `github.com/prometheus/client_golang` v1.23.2 - `/metrics` endpoint, RED HTTP metrics, Redis command timing, business counters (`server/internal/metrics/metrics.go`)
- `go.uber.org/automaxprocs` v1.6.0 - blank-imported in `server/cmd/server/main.go`
- `golang.org/x/text` v0.38.0 - Unicode normalization (`unicode/norm`) for line validation (`server/internal/sessions/`)

**Test-only (Go):**
- `github.com/alicebob/miniredis/v2` v2.38.0

**Indirect (Go):** `prometheus/common`, `prometheus/procfs`, `prometheus/client_model`, `google.golang.org/protobuf`, `yuin/gopher-lua`, `go.uber.org/atomic`, `golang.org/x/sys` - pulled transitively; not imported directly.

**Critical (iOS):**
- Bundled fonts (no SPM packages): Fraunces (display serif, `Fraunces.ttf`, `Fraunces-SemiBold.ttf`, `Fraunces-Italic.ttf`) and Inter (`Inter.ttf`), registered via `UIAppFonts` in `ios/project.yml`; OFL licenses in `ios/Strangewords/Resources/Fonts`
- Build-time font instancing used `fonttools` via a script noted in `docs/STATUS.md` (not part of the repo build)

**Infrastructure:**
- Redis 7 (local via Docker Compose; production Redis endpoint supplied as a Fly secret, Upstash-style URL per `server/DEPLOY.md`)
- `ca-certificates` in the runtime image (Alpine package) for outbound TLS

## Configuration

**Server environment variables** (parsed in `server/internal/config/config.go`):
- `SW_ADDR` - listen address, default `:8080`
- `SW_DEBUG_ADDR` - pprof listen address, default empty (disabled)
- `SW_REDIS_ADDR` - `host:port` or `redis://` / `rediss://` URL, default `127.0.0.1:6379`
- `SW_REDIS_PASSWORD` - Redis password, default empty
- `SW_REDIS_TLS` - any non-empty value enables TLS to Redis
- `SW_RATE_RPS` / `SW_RATE_BURST` - per-IP token bucket, defaults `30` / `60`; `0` disables
- `SW_APP_ATTEST_APPID` - Apple App ID for App Attest, default empty (see Concerns note below)
- `GOMEMLIMIT` - set in `server/fly.toml` `[env]`, not read by app code

Production secrets are set with `fly secrets set` (not stored in the repo); `.env*` and `fly.secrets` are gitignored (`.gitignore`).

**iOS configuration:**
- `ios/project.yml` is the source of truth; `Info.plist` is generated
- Build setting `APP_ATTEST_ENVIRONMENT`: `development` for Debug, `production` for Release
- Entitlements file `ios/Strangewords/Strangewords.entitlements` sets `com.apple.developer.devicecheck.appattest-environment` from that build setting
- `NSAppTransportSecurity.NSAllowsLocalNetworking: true` (dev-only plain HTTP to local backend)
- Dev-only environment flags read at launch: `SW_LOCAL_MOCK`, `SW_DEV`, `SW_FORCE_THEME`, `SW_FORCE_TOD`, `SW_DEV_DISSOLVE` (`ios/Strangewords/App/Dev.swift`)
- Backend base URL hardcoded in `ios/Strangewords/Net/APIClient.swift` as `https://api.strangerwords.us`

**Build:**
- `server/Dockerfile` - multi-stage build
- `server/fly.toml` - Fly app `strangerwords`, region `sjc`, `shared-cpu-1x` / 256 MB VM, `min_machines_running = 1`, health check `GET /healthz`
- `server/.dockerignore` (referenced in `docs/STATUS.md`)
- `ios/project.yml` - XcodeGen spec, iOS 17.0 target
- `.github/workflows/fly-deploy.yml` - push-to-deploy on `main` for `server/**` changes

## Platform Requirements

**Development:**
- Go 1.25+ toolchain (Docker build uses 1.26)
- Docker (for local Redis via `make redis`), or any reachable Redis 7 instance
- macOS with Xcode, `xcodegen` (Homebrew), and an iOS 17+ simulator for the app
- Optional: `flyctl` for manual deploys

**Production:**
- Fly.io, app `strangerwords`, primary region `sjc`, public at `https://strangerwords.fly.dev` (`docs/STATUS.md`); intended custom host `api.strangerwords.us` (cert/DNS step still pending per `docs/STATUS.md`)
- Managed Redis reached via `SW_REDIS_ADDR` secret
- Deploy trigger: GitHub Actions `fly-deploy.yml` using `FLY_API_TOKEN` secret, running `flyctl deploy --remote-only` from `server/`

---

*Stack analysis: 2026-10-08*
