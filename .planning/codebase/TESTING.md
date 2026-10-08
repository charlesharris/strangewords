---
last_mapped_commit: 4196ce5e0ccea3955e6a70452d0cded834a85ad4
last_mapped_at: 2026-10-08
---
<!-- refreshed: 2026-10-08 -->

# Testing Patterns

**Analysis Date:** 2026-10-08

## Test Framework

**Backend (Go):**
- Standard library `testing` package. No third-party assertion library.
- Redis is faked in tests with `github.com/alicebob/miniredis/v2` (in-process server) plus `github.com/redis/go-redis/v9` as the client. See `server/go.mod`.
- Config: none beyond `go.mod`. No `go test` flags are set in `server/Makefile`.

**iOS (Swift):**
- No test target exists. There is no `*Tests` directory under `ios/` and no `XCTestCase` anywhere in `ios/Strangewords`. `ios/project.yml` defines only the `Strangewords` application target.
- Verification is manual, through the on-device `LocalBackend` stand-in (`ios/Strangewords/Net/LocalBackend.swift`) and the simulator run script `run.sh`.

**Run Commands:**

```bash
cd server && make test                  # go test ./...
cd server && go test ./internal/sessions/... -run TestCleanLine -v   # one package / pattern
cd server && go test -race ./...        # race detector (not wired into Makefile; use manually)
cd server && make vet                   # go vet ./...
cd server && make build                 # go build ./...
./run.sh                                # build and launch the iOS app in the simulator (see run.sh)
./live_test.sh                          # end-to-end smoke run against a live backend (see script)
```

No watch mode, no coverage target, and no coverage command are configured.

## Test File Organization

**Location:** Co-located. Each `_test.go` file sits in the same directory as the code under test, and uses the same `package` name (white-box testing). Example: `server/internal/sessions/validate_test.go` is `package sessions`.

**Exception:** `server/internal/gateway/gateway_test.go` and `server/internal/gateway/middleware_test.go` use the same package, but the HTTP tests drive the server through `httptest.NewServer(srv.Routes())`, not by calling handlers directly.

**Naming:**
- File: `<source>_test.go`.
- Functions: `Test<Subject><Behavior>`, e.g. `TestCleanLineRejectsEmpty`, `TestRoundRobinHaikuIsABA`, `TestDefaultScreenerLoaded`.

**Current inventory (Go):**

| File | Covers |
|------|--------|
| `server/cmd/server/main_test.go` | Redis options construction (`TestRedisOptions`) |
| `server/internal/sessions/validate_test.go` | `CleanLine` normalization, length, control chars, zero-width stripping |
| `server/internal/sessions/content_test.go` | Content screener matching and default screener load |
| `server/internal/sessions/policy_test.go` | Round-robin authorship (haiku A-B-A pattern, start offsets) |
| `server/internal/gateway/gateway_test.go` | Full HTTP flow: enter, wait, session, lines, reveal |
| `server/internal/gateway/middleware_test.go` | Body limit, panic recovery, rate limiter |
| `server/internal/gateway/report_test.go` | Report capture endpoint |

There are 27 test functions across 7 files. Packages `store`, `matchmaker`, `push`, `moderation`, `metrics`, and `config` have no test files of their own; they are exercised indirectly through `gateway_test.go`.

## Test Structure

**Suite Organization:** Flat top-level `func TestX(t *testing.T)` functions. No `t.Run` table subtests in the simplest files; use a `for` loop over inputs when checking several values with the same expectation:

```go
func TestCleanLineRejectsEmpty(t *testing.T) {
	for _, in := range []string{"", "   ", "\t\n", "​​"} {
		if _, err := CleanLine(in); err != ErrEmptyLine {
			t.Fatalf("CleanLine(%q): got %v want ErrEmptyLine", in, err)
		}
	}
}
```

Use `t.Helper()` in helpers (`newRig` and `do` in `gateway_test.go` both call it). `t.Parallel()` is not used in the current suite; do not add it to tests that share a miniredis instance.

**Assertion style:** Plain `if got != want { t.Fatalf("... got %v want %v", ...) }`. Use `t.Fatalf` for setup and precondition failures, and `t.Errorf` only when several independent checks in one test should all report. Message format is `"<what>: got X want Y"`.

**Setup/teardown:**
- Register cleanup with `t.Cleanup(...)`, not `defer`, so helpers can own their resources:

```go
mr, err := miniredis.Run()
if err != nil {
	t.Fatalf("miniredis: %v", err)
}
t.Cleanup(mr.Close)
```

- Build the full server with `newRig(t)` in `server/internal/gateway/gateway_test.go`. It returns a `*rig` holding the `httptest.Server`, the `miniredis` instance, and a client. Reuse it for any new HTTP-level test.

**Response shapes:** Test-local structs mirror the wire JSON (`enterResp`, `waitingResp` in `gateway_test.go`). Decode into these, not into the production types, when asserting over the wire.

## Mocking

**Framework:** None. Doubles are hand-written or use production no-op implementations.

**Patterns:**
- Replace external dependencies with the in-process fake, not a mock library. Redis is `miniredis.Run()`.
- Logging is silenced by building a discard logger: `slog.New(slog.NewTextHandler(io.Discard, nil))`.
- Notifications use the production no-op: `push.Noop{Log: log}` and `moderation.LogSink{Log: log}` (both in `server/internal/push` and `server/internal/moderation`). Prefer these over writing a new fake.
- Time is injected through a `now func() time.Time` field (`rateLimiter.now` in `server/internal/gateway/middleware.go`). Set it in tests to control bucket refill; do not sleep.

**What to Mock:**
- External systems (Redis, APNs push, moderation sink) at the constructor boundary.
- Clocks, via injected `now` functions.

**What NOT to Mock:**
- The domain layer (`sessions`): test it directly with pure function calls.
- Redis behavior: use miniredis so TTL and key semantics match production.
- Handlers: exercise them through `httptest` and `Routes()` so middleware order is covered.

## Fixtures and Factories

**Test Data:** Inline literals in each test. Input lists are declared in the loop header (see `TestCleanLineRejectsEmpty`). Long inputs are generated with `strings.Repeat`:

```go
long := strings.Repeat("a", MaxLineLen+1)
```

Boundary tests check both sides: `MaxLineLen+1` must fail with `ErrLineTooLong`, and `MaxLineLen` must pass (`validate_test.go`).

**Location:** No separate `testdata/` or fixtures directory is present. Keep literals in the test file.

## Coverage

**Requirements:** None enforced. No coverage threshold appears in the Makefile, CI workflow (`.github/workflows/fly-deploy.yml`, which only deploys and does not run tests), or Dockerfile.

**View Coverage:**

```bash
cd server && go test -cover ./...
cd server && go test -coverprofile=cover.out ./... && go tool cover -html=cover.out
```

**Gap note:** CI does not run tests before deploy. `fly-deploy.yml` triggers on push to `main` for `server/**` and runs `flyctl deploy` with no test or vet step. Run `make test vet` locally before pushing.

## Test Types

**Unit Tests (Go):** Pure logic in `sessions` (validation, content screening, authorship policy) and `gateway` middleware (body limit, rate limiter, panic recovery). Assert on return values directly.

**Integration Tests (Go):** `gateway_test.go` and `report_test.go` run the real router, handlers, store, and matchmaker against miniredis over HTTP. These are the main safety net for the session lifecycle.

**Scripted end-to-end:** `live_test.sh` and `run_test_server_and_robot_poet_friend.sh` at the repo root drive a running server with a scripted "robot poet" partner. They are shell scripts, not `go test` targets. `live_test.sh` brings up Redis and the backend itself, launches the iOS simulator through `run.sh --solo`, and tears everything down on Ctrl-C.

**iOS:** No automated tests. Validate UI and state changes by running the simulator (`./run.sh`), which uses `LocalBackend` for the full poem arc with no server. `SW_API_BASE` points the client at a local server for two-device checks.

**E2E Tests:** Not using a framework. The shell scripts above are the closest equivalent.

## Common Patterns

**Asserting error sentinels:** Compare with `!=` for sentinels returned directly, and use `errors.Is` when the error may be wrapped:

```go
if _, err := CleanLine(in); err != ErrEmptyLine {
	t.Fatalf("CleanLine(%q): got %v want ErrEmptyLine", in, err)
}
```

**HTTP tests:** Use the `rig.do` helper, then decode the JSON body into a local response struct:

```go
status, body := r.do(t, http.MethodPost, "/v1/enter", "", map[string]any{...})
var resp enterResp
if err := json.Unmarshal(body, &resp); err != nil {
	t.Fatalf("decode: %v body=%s", err, body)
}
```

**Concurrency tests:** `gateway_test.go` imports `sync`. `sync` is imported for `sync.WaitGroup`-driven concurrent requests against the same rig when testing matchmaking races. Keep these deterministic by asserting on the set of outcomes, not their order.

**Time-dependent tests:** Inject `now` (see the rate limiter pattern above). Do not use `time.Sleep` in new tests.

**Rate-limit tests:** Set `SW_RATE_RPS=0` to disable limiting in the test environment (`config.go` treats 0 as off). Leave limits enabled when the test is specifically about limiting.

## Adding New Tests

1. Put `<source>_test.go` beside the file under test, in the same package.
2. Use `t.Helper()` in any helper and `t.Cleanup` for teardown.
3. For HTTP behavior, extend `gateway_test.go` through `newRig(t)` rather than building a new server.
4. Run `cd server && make test vet` before committing.
5. For iOS changes, there is no test target to add to; verify in the simulator via `./run.sh` and note the manual steps in the PR description. Adding an XCTest target would require a new entry under `targets:` in `ios/project.yml`.

---

*Testing analysis: 2026-10-08*
