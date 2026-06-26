# Deploying the Strangewords backend

The backend is a single stateless Go binary (`cmd/server`) backed by Redis. It
deploys to [Fly.io](https://fly.io) from the `server/` directory. All app config
lives in [`fly.toml`](./fly.toml); the image is built from [`Dockerfile`](./Dockerfile).

The iOS app talks to a stable custom hostname (`https://api.strangewords.app`),
so the backend can be re-pointed via DNS without an App Store update.

## Configuration

The server reads three env vars (see `internal/config/config.go`):

| Var                 | Default            | Notes                                  |
| ------------------- | ------------------ | -------------------------------------- |
| `SW_ADDR`           | `:8080`            | HTTP listen address                    |
| `SW_REDIS_ADDR`     | `127.0.0.1:6379`   | Redis `host:port`                      |
| `SW_REDIS_PASSWORD` | _(empty)_          | Redis auth password                    |
| `SW_REDIS_TLS`      | _(unset)_          | Set to any value to dial Redis via TLS |

Redis holds only ephemeral, TTL-bounded state — a restart drops in-progress
poems, which is acceptable. No persistence or durability is required.

## One-time bootstrap (run once, from your laptop)

Creates the app, Redis, secrets, and custom domain. These persist on Fly.

```bash
brew install flyctl
fly auth login
cd server

# 1. Create the app. Names are GLOBALLY unique — if "strangewords" is taken,
#    pick another and update `app =` in fly.toml to match.
fly apps create strangewords

# 2. Create Redis in the SAME region as fly.toml (primary_region = "sjc").
#    Copy the connection string it prints:
#    redis://default:PASSWORD@fly-xxxx.upstash.io:6379
fly redis create

# 3. Store the Redis endpoint as app secrets (NOT in git / CI).
#    Leave SW_REDIS_TLS unset — Fly's private Redis is plaintext.
fly secrets set SW_REDIS_ADDR=fly-xxxx.upstash.io:6379 SW_REDIS_PASSWORD=PASSWORD

# 4. First deploy + sanity check.
fly deploy
fly logs                                       # expect "listening" + redis ping ok
curl https://strangewords.fly.dev/healthz      # expect 200

# 5. Custom domain + TLS cert.
fly certs add api.strangewords.app
fly certs show api.strangewords.app            # prints the exact DNS records to add
#    -> add those records at your DNS registrar (typically a CNAME
#       api -> strangewords.fly.dev, plus AAAA/A if listed).
fly certs check api.strangewords.app           # wait until it validates
curl https://api.strangewords.app/healthz      # expect 200
```

After `api.strangewords.app/healthz` returns 200, the iOS base URL
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
