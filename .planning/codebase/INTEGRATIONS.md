---
last_mapped_commit: 4196ce5e0ccea3955e6a70452d0cded834a85ad4
last_mapped_at: 2026-10-08
---
# External Integrations

**Analysis Date:** 2026-10-08

## APIs & External Services

**Apple (planned, not yet implemented):**
- APNs (Apple Push Notification service) - re-engagement pushes (`match-ready`, `your-turn`). Only an interface exists: `server/internal/push/push.go` defines `Notifier`, and `push.Noop` is wired in `server/cmd/server/main.go`. Blocked on an Apple Developer account and APNs key (`docs/STATUS.md`, Phase 2). No APNs client, key handling, or HTTP/2 transport exists yet.
- App Attest (DeviceCheck) - device attestation for the iOS client.
  - Client side: entitlement `com.apple.developer.devicecheck.appattest-environment` in `ios/Strangewords/Strangewords.entitlements`, environment set per build config in `ios/project.yml` (`development` for Debug, `production` for Release).
  - Server side: config field `SW_APP_ATTEST_APPID` is loaded into `Config.AppAttestAppID` in `server/internal/config/config.go`, but no code in `server/internal/gateway/` or elsewhere reads it. No attestation or assertion validation is implemented yet.
  - App ID expected: `2M6QRD8T3A.com.strangerwords.us`.

**No other third-party SaaS, LLM, analytics, or payment APIs were detected.** Searches of `server/` and `ios/Strangewords/` for common provider SDKs returned nothing. The iOS app has no third-party Swift packages.

## Data Storage

**Databases:**
- Redis 7 - the only datastore. All state is ephemeral and TTL-bounded (sessions, matchmaking queue, reveal window, rate-limit state).
  - Client: `github.com/redis/go-redis/v9` in `server/internal/store/store.go`; constructed in `server/cmd/server/main.go` (`redisOptions`).
  - Connection: `SW_REDIS_ADDR` (either `host:port` or `redis://` / `rediss://` URL), `SW_REDIS_PASSWORD`, `SW_REDIS_TLS`.
  - Key layout: sessions stored as JSON blobs at `sw:sess:{id}` (`server/internal/store/store.go`, per `docs/STATUS.md`); matchmaking uses atomic `LPOP`.
  - Local: `server/docker-compose.yml` runs `redis:7-alpine` with persistence disabled (`--save "" --appendonly no`) on port 6379.
  - Tests: `github.com/alicebob/miniredis/v2` replaces Redis in unit tests.
- No SQL, document, or object database. Moderation reports are logged, not persisted (see below).

**File Storage:**
- Local filesystem only. The banned-term list is read from `server/internal/sessions/banned_terms.txt` (embedded or loaded at build time; see `server/internal/sessions/content.go`).
- iOS fonts are bundled in the app (`ios/Strangewords/Resources/Fonts`).

**Caching:**
- None beyond Redis session state. No CDN configuration in the repo.

## Authentication & Identity

**Client identity (server-issued anonymous bearer token):**
- `POST /v1/enter` issues a token; subsequent requests send `Authorization: Bearer <token>`.
- Server parses the header in `bearer()` in `server/internal/gateway/gateway.go` and resolves it to a session and participant index in `authSession()`.
- The token is stored on the device in `UserDefaults` via `ios/Strangewords/Net/Keychain.swift` (a `TokenStore`, deliberately not Keychain; see `docs/STATUS.md`).
- No user accounts, OAuth, or third-party identity provider.

**Client attestation:**
- Planned via App Attest as described above; not enforced.

## Monitoring & Observability

**Metrics:**
- Prometheus, exposed at `GET /metrics` (`server/internal/metrics/metrics.go`, route in `server/internal/gateway/gateway.go`). Includes RED HTTP metrics, Redis command timing, and counters such as `sw_rate_limited_total`, `sw_content_rejected_total`, `sw_panics_recovered_total`.
- Scraping target and remote-write destination are not configured in the repo.

**Profiling:**
- `net/http/pprof` on `SW_DEBUG_ADDR` (disabled by default). Intended to be reached only via `fly proxy 6060:6060`; not in `[http_service]` in `server/fly.toml`.

**Error Tracking:**
- None (no Sentry or similar detected).

**Logs:**
- Structured JSON to stdout via `log/slog` (`server/cmd/server/main.go`). Fly collects stdout.
- Abuse reports are written to logs by `moderation.LogSink` (`server/internal/moderation/moderation.go`). Durable storage (Postgres) is planned but not built.
- Redis credentials are deliberately excluded from logs; only the host:port is logged (`server/cmd/server/main.go`).

## CI/CD & Deployment

**Hosting:**
- Fly.io, app `strangerwords`, region `sjc`, one `shared-cpu-1x` 256 MB machine kept warm (`server/fly.toml`).
- Public hostname `strangerwords.fly.dev`; planned custom host `api.strangerwords.us` (DNS and certificate step pending, `docs/STATUS.md`).
- Deploy runbook: `server/DEPLOY.md`.

**CI Pipeline:**
- GitHub Actions, workflow `.github/workflows/fly-deploy.yml` ("Fly Deploy").
  - Triggers: push to `main` touching `server/**` or the workflow file.
  - Steps: `actions/checkout@v4`, `superfly/flyctl-actions/setup-flyctl@master`, then `flyctl deploy --remote-only` in `./server`.
  - Concurrency group `deploy-group` prevents parallel deploys.
- No test or lint step runs in CI; `go test ./...` is not part of the workflow.
- iOS builds are not in CI.

## Environment Configuration

**Required env vars in production (Fly secrets):**
- `SW_REDIS_ADDR` - Redis endpoint (URL form recommended)
- `SW_REDIS_PASSWORD` - if the endpoint does not embed it
- `SW_REDIS_TLS` - if using plain `host:port` with TLS
- `SW_APP_ATTEST_APPID` - intended for App Attest (currently unused by code)

**Required in CI:**
- `FLY_API_TOKEN` - GitHub Actions secret used by `flyctl deploy`

**Optional tuning (set in `server/fly.toml` or as secrets):**
- `SW_RATE_RPS`, `SW_RATE_BURST`, `SW_DEBUG_ADDR`, `GOMEMLIMIT`

**Secrets location:**
- Production server secrets: Fly.io secret store (`fly secrets set`)
- CI deploy token: GitHub repository secret `FLY_API_TOKEN`
- Apple signing: Xcode automatic signing with team `2M6QRD8T3A`. APNs keys and `.p8` / `.p12` files are gitignored and must not be committed (`.gitignore`).
- Local dev values: `.env*` files are gitignored; none were read for this analysis.

## Webhooks & Callbacks

**Incoming:**
- None. The public HTTP API is client-facing only; there are no webhook receivers.
- Public routes (`server/internal/gateway/gateway.go`):
  - `GET /healthz` - Fly health check
  - `GET /metrics` - Prometheus scrape
  - `POST /v1/enter` - join matchmaking
  - `GET /v1/waiting` - poll for match
  - `GET /v1/session/{id}` - poll session state
  - `POST /v1/session/{id}/line` - submit a line
  - `POST /v1/session/{id}/leave` - leave
  - `POST /v1/session/{id}/dismiss` - dismiss after reveal
  - `POST /v1/session/{id}/report` - report abuse

**Outgoing:**
- None at runtime. The server makes no outbound HTTP calls (APNs is the only planned one).
- Clients call the backend. The iOS app's base URL is `https://api.strangerwords.us` in `ios/Strangewords/Net/APIClient.swift`, with a mock alternative `ios/Strangewords/Net/LocalBackend.swift` selected by `SW_LOCAL_MOCK`.
- The robot test client `server/cmd/bot/main.go` calls the backend at `-base` (default `http://127.0.0.1:8080`).

---

*Integration audit: 2026-10-08*
