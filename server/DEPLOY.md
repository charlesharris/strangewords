# Deploying the Strangewords backend

The backend is a single stateless Go binary (`cmd/server`) backed by Redis. It
deploys to [Fly.io](https://fly.io) from the `server/` directory. All app config
lives in [`fly.toml`](./fly.toml); the image is built from [`Dockerfile`](./Dockerfile).

The iOS app talks to a stable custom hostname (`https://api.strangerwords.us`),
so the backend can be re-pointed via DNS without an App Store update.

> **On the name.** The public domain is **`strangerwords.us`** (with the "r",
> matching the app's display name "Stranger Words"). The backend lives on the
> `api.` subdomain; the apex `strangerwords.us` is reserved for a future landing
> page. The Fly app is `strangerwords` (hence `strangerwords.fly.dev`). The Go
> module/identifiers keep the no-"r" spelling on purpose — they're internal,
> never user-visible, and renaming them is churn. The **iOS bundle id is
> `com.strangerwords.us`** (with the "r"), matching the registered App ID so
> App Attest can bind to `2M6QRD8T3A.com.strangerwords.us`.

## Why Fly.io

The choice was pragmatic, not dogmatic — `plan.v1.md` left the host `[TUNABLE]`
(Fly.io / Render / small VM), and Fly fits this app's shape:

- **Shape match.** One stateless Go binary + ephemeral Redis is Fly's sweet
  spot: a Dockerfile becomes a machine, with managed Redis (`fly redis`) on the
  same private network. No Postgres needed — nothing is persisted by design.
- **Warm but cheap.** `min_machines_running = 1` keeps one `shared-cpu-1x`/256mb
  machine warm so the iOS polling loop never hits a cold start mid-poem.
- **Region pinning** (`sjc`) puts it near early users; more regions is config.
- **DNS-repointable hostname + free TLS**, so the backend can move without an App
  Store update — the property the `api.strangerwords.us` indirection relies on.
- **Private networking** is already used for pprof (`SW_DEBUG_ADDR` via `fly proxy`).

Reconsider if Upstash Redis reliability bites (a blip only drops in-flight
poems, which the design tolerates) or multi-region / own-VM control is wanted.
The server is plain Docker + `SW_*` env config, so switching hosts is an
afternoon — the host-specific footprint is just `fly.toml`, this file, and the
CI workflow.

## Configuration

The server reads these env vars (see `internal/config/config.go`):

| Var                 | Default            | Notes                                          |
| ------------------- | ------------------ | ---------------------------------------------- |
| `SW_ADDR`           | `:8080`            | HTTP listen address                            |
| `SW_REDIS_ADDR`     | `127.0.0.1:6379`   | Redis `host:port`, **or** a full `redis://` / `rediss://` URL (the form Fly prints — it's parsed) |
| `SW_REDIS_PASSWORD` | _(empty)_          | Redis auth password (ignored if the URL already carries one) |
| `SW_REDIS_TLS`      | _(unset)_          | Set to any value to dial Redis via TLS (or just use a `rediss://` URL) |
| `SW_RATE_RPS`       | `30`               | Per-IP sustained request rate; `0` disables it |
| `SW_RATE_BURST`     | `60`               | Per-IP burst depth (token-bucket size)         |

Redis holds only ephemeral, TTL-bounded state — a restart drops in-progress
poems, which is acceptable. No persistence or durability is required.

### Hardening

The HTTP surface defends itself with a few always-on guards (no config needed):

- **Request body cap** — bodies over 16 KiB are rejected before they're read,
  so a single large POST can't exhaust memory.
- **Server timeouts** — read (10s), write (15s), and idle (60s) timeouts, plus a
  5s header timeout, reap slow or stuck connections.
- **Panic recovery** — a handler panic becomes a logged 500 (and bumps
  `sw_panics_recovered_total`) instead of dropping the connection.
- **Per-IP rate limiting** — a token bucket (`SW_RATE_RPS`/`SW_RATE_BURST`) keyed
  on the client IP. Behind Fly the real IP comes from the `Fly-Client-IP` header.
  `/healthz` and `/metrics` are exempt. Limits are loose because mobile carriers
  (CGNAT) can share one IP across many real users; rejections increment
  `sw_rate_limited_total`. Set `SW_RATE_RPS=0` to disable.

### Safety / moderation

Two product-level safety rails sit on top of the infra hardening (Phase 5):

- **Content filter.** Submitted lines are screened against a small blocklist of
  unambiguous slurs (`internal/sessions/banned_terms.txt`, matched as whole
  tokens after a light leet-fold, so innocent words aren't caught). A hit is a
  `422 content_rejected` and bumps `sw_content_rejected_total`. The list is a
  deliberately minimal floor — the brief errs toward allowing creative
  expression — and should be swapped for a maintained source before wide release.
- **Abuse reports.** `POST /v1/session/{id}/report` lets any member capture a
  live session's poem + metadata (no tokens — anonymity holds) to the moderation
  **sink**, the one durable exception to the app's ephemerality. v1 uses
  `moderation.LogSink` (structured logs, retained by Fly / forwardable to a
  drain); swap in a Postgres/object-store `Sink` for review tooling without
  touching callers. Reporting works while the session is live (active or in its
  reveal window); a post-dissolution grace window and the in-app report action +
  first-run EULA gate are the remaining Phase 5 (iOS) pieces.

## One-time bootstrap (run once, from your laptop)

Creates the app, Redis, secrets, and custom domain. These persist on Fly.

```bash
brew install flyctl
fly auth login
cd server

# 1. Create the app. Names are GLOBALLY unique — if "strangerwords" is taken,
#    pick another and update `app =` in fly.toml to match.
fly apps create strangerwords

# 2. Create Redis in the SAME region as fly.toml (primary_region = "sjc").
#    Copy the connection string it prints:
#    redis://default:PASSWORD@fly-xxxx.upstash.io:6379
fly redis create

# 3. Store the Redis endpoint as app secrets (NOT in git / CI). Easiest and
#    least error-prone: paste the WHOLE redis:// URL — the server parses it.
fly secrets set SW_REDIS_ADDR='redis://default:PASSWORD@fly-xxxx.upstash.io:6379'
#    Or split it yourself (note: SW_REDIS_ADDR is host:port ONLY — no redis://
#    prefix, no password — else the dialer errors "too many colons in address"):
#    fly secrets set SW_REDIS_ADDR=fly-xxxx.upstash.io:6379 SW_REDIS_PASSWORD=PASSWORD

# 4. First deploy + sanity check.
fly deploy
fly logs                                       # expect "listening" + redis ping ok
curl https://strangerwords.fly.dev/healthz      # expect 200

# 5. Custom domain + TLS cert.
fly certs add api.strangerwords.us
fly certs show api.strangerwords.us            # prints the exact DNS records to add
#    -> add those records at your DNS registrar (typically a CNAME
#       api -> strangerwords.fly.dev, plus AAAA/A if listed).
fly certs check api.strangerwords.us           # wait until it validates
curl https://api.strangerwords.us/healthz      # expect 200
```

After `api.strangerwords.us/healthz` returns 200, the iOS base URL
(`ios/Strangewords/Net/APIClient.swift`) points here.

## Continuous deployment (push-to-deploy)

`.github/workflows/fly-deploy.yml` deploys on every push to `main` that touches
`server/**`. The build runs on Fly's remote builder, so CI only needs a token.

```bash
# Create a long-lived deploy token (copy the WHOLE output, incl. "FlyV1 " prefix).
fly tokens create deploy -x 999999h
```

Add it as a GitHub Actions repo secret named `FLY_API_TOKEN`
(Settings → Secrets and variables → Actions). After that, pushes to `main`
deploy automatically. Manual `fly deploy` from your laptop still works and does
the same thing.

## Routine operations

```bash
fly deploy            # manual deploy (from server/)
fly logs             # tail logs
fly status           # machine + health state
fly secrets list     # show configured secrets (values hidden)
fly redis status     # Redis health
```

## Observability

The server exposes Prometheus metrics at `GET /metrics` (same port as the API):

| Metric                              | Type      | What it tells you                                  |
| ----------------------------------- | --------- | -------------------------------------------------- |
| `sw_http_requests_total`            | counter   | Rate + errors, by `route` template / `method` / `code` |
| `sw_http_request_duration_seconds`  | histogram | Request latency (p50/p99) per route                |
| `sw_http_requests_in_flight`        | gauge     | Concurrency right now                              |
| `sw_redis_command_duration_seconds` | histogram | Per-command Redis latency (the usual bottleneck)   |
| `sw_redis_command_errors_total`     | counter   | Real Redis errors (cache misses excluded)          |
| `sw_rate_limited_total`             | counter   | Requests rejected by the per-IP limiter            |
| `sw_panics_recovered_total`         | counter   | Handler panics caught by the recovery middleware   |
| `sw_content_rejected_total`         | counter   | Lines rejected by the abuse content filter         |
| `sw_reports_total`                  | counter   | Abuse reports captured to the moderation sink      |
| `sw_entered/matched/waiting/...`    | counters  | Business funnel                                    |

Routes are templates (`POST /v1/session/{id}/line`), never concrete ids, so
label cardinality stays flat under any traffic. Point a Prometheus/Grafana
Cloud agent at `/metrics`, or spot-check with `curl .../metrics`.

**Profiling (pprof).** Off by default. To profile a live machine, set the debug
address and reach it over Fly's private network — it is never publicly routed:

```bash
fly secrets set SW_DEBUG_ADDR=:6060
fly proxy 6060:6060                                   # in one terminal
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30   # CPU
go tool pprof http://localhost:6060/debug/pprof/heap                 # allocations
curl http://localhost:6060/debug/pprof/goroutine?debug=1 | head      # goroutine dump
```

**Runtime limits.** `GOMEMLIMIT=220MiB` (in `fly.toml`) keeps the heap under the
256 MB VM cap so GC reclaims before the OOM-killer fires; `automaxprocs` aligns
`GOMAXPROCS` to Fly's fractional vCPU at startup (logged on boot).
