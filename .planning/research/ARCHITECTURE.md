# Architecture Research

**Domain:** Automated test and verification infrastructure for an existing SwiftUI (iOS 17+) + Go/Redis app, with an XcodeGen-generated project and a robot-poet API client
**Researched:** 2026-10-08
**Confidence:** HIGH on the integration shape and the seams (read directly from `ios/project.yml`, `AppModel.swift`, `LocalBackend.swift`, `APIClient.swift`, `cmd/bot/main.go`, `gateway.go`, and the shell scripts). MEDIUM on a few Xcode and `xcodebuild` mechanics, listed under "Verify when building".

This document does not re-describe the app. See `.planning/codebase/ARCHITECTURE.md` for that. It describes the *verification layer* that sits around the app and how each piece plugs into what exists.

## Standard Architecture

### System Overview

A system like this is normally verified in four concentric rings. The inner rings are fast and hermetic. The outer ring is slow and uses real processes. Each ring writes evidence into one run directory, and one runner orchestrates all of them.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  scripts/verify/verify.sh   (headless runner: stages, exit code, evidence) │
│  Writes build/verify/<ts>/  ──►  summarised into .planning/ VERIFICATION   │
├──────────────┬───────────────────────────┬───────────────────────────────┤
│ Stage 1: Go  │ Stage 2: iOS (simulator)  │ Stage 3: E2E (real processes)  │
│              │                           │                                │
│ go vet       │ xcodegen generate         │  throwaway Redis (docker, free │
│ go build     │ xcodebuild test           │    port)                       │
│ go test      │   (hosted unit bundle)    │  real server binary            │
│  -race -json │ ┌──────────────────────┐  │  bot A  ◄─ HTTP ─►  bot B      │
│  (miniredis) │ │ StrangewordsTests    │  │  assert: 3 lines, complete,    │
│              │ │  Syllables           │  │    both dismissed, 410 after,  │
│              │ │  PoemNaming          │  │    zero sw:* keys, metrics     │
│              │ │  Models decoding     │  │                                │
│              │ │  LocalBackend        │  │  optional Stage 3b: iOS live   │
│              │ │  AppModel + fake     │  │  tests (APIClient ↔ real       │
│              │ │  Live (opt-in) ──────┼──┼─► server, test acts as both    │
│              │ └──────────────────────┘  │  participants)                 │
├──────────────┴───────────────────────────┴───────────────────────────────┤
│  Existing, unchanged: server/**/_test.go (miniredis), ios app target,      │
│  server/cmd/bot, root run.sh / live_test.sh / run_test_server_and_robot_   │
│  poet_friend.sh (interactive dev tools, NOT part of verification)          │
└──────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation | Status |
|-----------|----------------|------------------------|--------|
| Go test suite | Domain, gateway, middleware, full HTTP lifecycle against miniredis | `go test ./...` | Exists. Wrapped, not changed. |
| `StrangewordsTests` (new iOS target) | Unit-tests on-device logic and the state machine, in-process, no network | XcodeGen `bundle.unit-test` target **hosted** by the app (`@testable import Strangewords`) | New |
| Test seams in app code | Make `AppModel`, `LocalBackend`, `APIClient`, and `TokenStore` testable without sleeping 3 seconds per poll | Defaulted init parameters; production behaviour unchanged | New, small |
| Fake `Backend` (test support) | Scripted, instant `Backend` for driving `AppModel` through every phase and error branch | A test-only `actor` conforming to `Backend` | New |
| iOS live tests (opt-in) | Prove `APIClient` and `Models.swift` decode what the real Go server emits | XCTest that calls `XCTSkip` unless `SW_E2E_BASE` is set | New |
| Hardened robot poet (`cmd/bot`) | Be a deterministic, assertable API client, not just a chatty demo | Add exit codes, a `-json` result line, and a `-fast` pacing flag | Modify existing |
| E2E orchestrator | Bring up isolated Redis + server + 2 bots, assert the full arc, tear down | Bash with `trap` cleanup plus a Go-built server and bot | New |
| Headless runner (`verify.sh`) | Run all stages in order, never need a human, return non-zero on any failure, collect evidence | Bash dispatcher over per-stage scripts | New |
| Evidence store | Make each run's proof inspectable and summarisable | One directory per run: logs, `.xcresult`, JSON, snapshots | New |

## Recommended Project Structure

```
ios/
├── project.yml                      # + StrangewordsTests target, + scheme test action
├── Strangewords/                    # app (gets small seam changes only)
└── StrangewordsTests/               # NEW, path-sourced by XcodeGen
    ├── Support/
    │   ├── ScriptedBackend.swift    # fake Backend: queue of responses/errors, instant
    │   └── TestEnv.swift            # TokenStore reset, shared helpers
    ├── SyllablesTests.swift
    ├── PoemNamingTests.swift        # determinism + golden names
    ├── ModelsDecodingTests.swift    # JSON fixtures → SessionView / EnterResponse / ServerError
    ├── LocalBackendTests.swift      # 5-7-5, turn order, completion, restart on enter
    ├── AppModelTests.swift          # phase machine against ScriptedBackend
    └── Live/
        └── APIClientLiveTests.swift # skips unless SW_E2E_BASE is set

server/
├── cmd/bot/main.go                  # + exit codes, -json, -fast (small diff)
└── ...                              # existing tests untouched

scripts/verify/                      # NEW; existing root scripts stay as they are
├── verify.sh                        # entry point: ./scripts/verify/verify.sh [--stage go|ios|e2e|all]
├── lib.sh                           # free-port picker, redis container, trap cleanup, evidence dir
├── stage_go.sh
├── stage_ios.sh
└── stage_e2e.sh

build/verify/<timestamp>/            # gitignored raw evidence (ios/build/ is already ignored; add this)
└── go.json  go-race.txt  ios.xcresult  ios-summary.json  e2e-bot-a.json
    e2e-bot-b.json  e2e-redis-keys.txt  e2e-metrics.txt  server.log  result.json

.planning/                           # committed distillation of one blessed run
└── (phase dir)/VERIFICATION.md      # requirement → evidence path/line table
```

### Structure Rationale

- **`ios/StrangewordsTests/` as a sibling of the app folder:** XcodeGen sources it by path, `.xcodeproj` stays regenerated and gitignored, and test code can never be compiled into the app target.
- **`scripts/verify/` rather than the repo root:** the three root scripts are interactive dev tools. They `lsof | kill` whatever holds `:8080`, run `FLUSHALL`, write fixed `/tmp/sw-*` paths, open the Simulator GUI, and never exit on their own. Verification needs the opposite properties: isolated, non-destructive, exits with a status. Keeping them in a separate directory makes the contrast explicit and keeps the dev loop untouched.
- **Raw evidence in `build/verify/`, summary committed in `.planning/`:** raw logs and `.xcresult` bundles are large and churny. The committed `VERIFICATION.md` records what was run, when, at which commit, and the pass counts, which is what the baseline needs.

## Architectural Patterns

### Pattern 1: Hosted unit-test bundle for an app target

**What:** XcodeGen `type: bundle.unit-test` with a dependency on the app target. XcodeGen then sets `TEST_HOST` and `BUNDLE_LOADER` so `@testable import Strangewords` works against the app module.
**When to use:** The code under test lives in the app target (it does: `AppModel`, `LocalBackend`, `Syllables`, `PoemNaming` are all in `Strangewords`). This is the lowest-friction option and needs no source moves.
**Trade-offs:** The app itself launches in the simulator for every test run, so launch-time side effects are real (see Pitfalls below). The alternative, extracting a `Core` framework or local Swift package, gives faster pure-logic tests but moves files and changes the build graph. That is a refactor, not part of establishing a baseline. Defer it.

**Example (`project.yml`):**
```yaml
targets:
  StrangewordsTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - StrangewordsTests
    dependencies:
      - target: Strangewords
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.strangerwords.us.tests
schemes:
  Strangewords:
    build:
      targets:
        Strangewords: all
    run:
      config: Debug
      environmentVariables: { SW_LOCAL_MOCK: "1", SW_DEV: "1" }   # existing
    test:                         # NEW. An explicit scheme gets no test action unless you add one.
      config: Debug
      targets:
        - StrangewordsTests
      environmentVariables:
        SW_LOCAL_MOCK: "1"        # host app must never reach production at launch
```

### Pattern 2: Defaulted-parameter seams, not protocol rewrites

**What:** The architecture already has the one seam that matters (`Backend`, with `AppModel.init(backend:)` already accepting injection). The remaining blockers are hard-coded timings and singletons. Fix each with a defaulted init parameter so production call sites do not change.
**When to use:** Anywhere a test would otherwise sleep, hit a singleton, or touch global state.
**Trade-offs:** Tiny, reviewable production diffs, but they are production changes, so they are made in the same phase as the first suite that needs them and covered by that suite.

Seams needed, found by reading the code:

| Location | Blocker | Seam |
|----------|---------|------|
| `AppModel.pollInterval` | `private let = .seconds(3)`; every polling test would wait 3 s per tick | `init(backend:, pollInterval: Duration = .seconds(3))` |
| `LocalBackend.strangerThinkTime` (1.6 s) and the 600 ms sleep in `enter` | Hard-coded, so each LocalBackend arc test takes seconds | `init(strangerThinkTime:, enterDelay:)` with current values as defaults |
| `APIClient.base` | `private let`, read once from `SW_API_BASE`; `APIClient.shared` is a singleton | `init(base: URL = <current default>)` so a live test can target a random-port server without env games |
| `TokenStore` | Static wrapper over `UserDefaults.standard`; process-global, shared with the host app | Cheapest: `TokenStore.clear()` in test `setUp`/`tearDown`. Heavier option (injectable `UserDefaults` suite) only if tests collide. |
| `AppModel.begin()` and similar | They spawn unstructured `Task { }` and return immediately, so tests cannot `await` them | Await by polling `model.phase` with a bounded helper (`waitUntil { model.phase == … }`), not by sleeping a fixed time. Do not restructure `AppModel` for this. |

### Pattern 3: Hermetic, self-cleaning E2E orchestration

**What:** One script owns the lifetime of every process it starts: a throwaway Redis container on a free port, a server on a free port, two bots. A single `trap cleanup EXIT INT TERM` kills them all. Nothing is shared with the developer's running stack.
**When to use:** Any real-process test that must be rerunnable and safe on a dev machine that may already have `:8080` and `:6379` in use.
**Trade-offs:** Slightly more script than reusing the existing ones, but it removes the destructive behaviours (kill on `:8080`, `FLUSHALL` on whatever Redis is on `:6379`) and the fixed-path collisions.

**Example (`lib.sh` shape):**
```bash
free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }

start_redis() {            # sets REDIS_CID, REDIS_PORT
  REDIS_PORT=$(free_port)
  REDIS_CID=$(docker run -d --rm -p "127.0.0.1:${REDIS_PORT}:6379" redis:7-alpine \
              redis-server --save "" --appendonly no)
}
cleanup() { trap - EXIT INT TERM
  [ -n "${BOT_PIDS:-}" ] && kill $BOT_PIDS 2>/dev/null
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null
  [ -n "${REDIS_CID:-}" ] && docker stop "$REDIS_CID" >/dev/null 2>&1
}
trap cleanup EXIT INT TERM
```

`docker run --rm` on a fresh container means no `FLUSHALL` is needed, so there is nothing to race against. The existing `redis-cli PING` readiness loop is worth keeping, and `/healthz` polling for the server.

### Pattern 4: The test acts as the partner (iOS live tests)

**What:** `APIClient`'s methods take the token as a parameter, so a live test can be *both* participants: call `enter` twice with two `APIClient` calls, get two tokens, and alternate `submitLine` per `TurnPolicy`. No bot process is needed for the iOS-to-server contract check.
**When to use:** To prove the Swift `Codable` models decode the real Go `View`, and that error mapping (`410` → `.gone`, `409` → `.notYourTurn`/`.wrongTurn`, `422` → `.contentRejected`) matches real responses.
**Trade-offs:** Not a UI test; it does not drive SwiftUI. That is deliberate: UI automation is the slowest and flakiest layer and the milestone's value is in state-machine and contract correctness. Opt-in by env (`SW_E2E_BASE`), so a plain `xcodebuild test` stays hermetic and offline.

### Pattern 5: Backend conformance on the shared subset only

**What:** `LocalBackend` is a hand-written copy of server semantics. Pin it with tests, but only on the behaviour both sides really share. Compare against the real server in the live tests, not by forcing identical behaviour.
**Known divergences found while reading the code** (these are drift items to record, not necessarily bugs):

| Behaviour | Real server | `LocalBackend` |
|-----------|-------------|----------------|
| First `enter` | `state: "waiting"` until a partner arrives | Always `matched` instantly |
| Out-of-turn or wrong line number | 409 (`not_your_turn`, `wrong_turn`) | Silently returns the current view, no error |
| Banned terms | 422 from `Screener` | No screening |
| `dismiss` / `leave` | Both participants must dismiss to dissolve; later calls get 410 | No-ops |
| Token | 32-byte random | The literal `"local"` |

**Shared invariants worth asserting on both:** haiku targets `[5,7,5]`; `you == 0` gets lines 0 and 2; `status` reaches `complete` after exactly `targets.count` lines; `lines.count == targets.count` at completion; `SessionView` round-trips through `JSONEncoder`/`JSONDecoder`.

## Data Flow

### Verification run (evidence production)

```
verify.sh  ──creates──►  build/verify/<ts>/   (EVIDENCE_DIR exported to every stage)
   │
   ├─ stage_go.sh ──► go vet ; go build ./... ; go test -race -json ./...
   │                      └──► go.json , go-race.txt          (exit code + pass/fail counts)
   │
   ├─ stage_ios.sh ─► xcodegen generate
   │                  xcodebuild test -scheme Strangewords
   │                    -destination 'platform=iOS Simulator,name=iPhone 16'
   │                    -derivedDataPath ios/build  -resultBundlePath <ts>/ios.xcresult
   │                    CODE_SIGNING_ALLOWED=NO
   │                      └──► ios.xcresult
   │                  xcrun xcresulttool get test-results summary --path ios.xcresult
   │                      └──► ios-summary.json               (counts, failures)
   │
   ├─ stage_e2e.sh ─► start_redis ─► build server+bot to a temp dir ─► start server (free port)
   │                  start bot A, bot B (-once -json -fast) against it
   │                      └──► e2e-bot-a.json , e2e-bot-b.json (each: matched, lines, outcome)
   │                  assert A.lines == B.lines, 3 lines, status complete
   │                  GET /v1/session/{id} with a bot token ─► expect 410
   │                  redis-cli --scan 'sw:*' ─► expect empty
   │                      └──► e2e-redis-keys.txt
   │                  curl /metrics ─► sw dissolved counter incremented
   │                      └──► e2e-metrics.txt , server.log
   │
   └─ collate ──► result.json  { commit, dirty?, stages:{go,ios,e2e}:{pass,counts}, timestamps }
                      │
                      ▼
          human/agent copies the headline into .planning/.../VERIFICATION.md
          (requirement → stage → evidence file → result)
```

Direction is strictly one way: stages write evidence, nothing reads evidence except the final collation and the person writing `VERIFICATION.md`. A stage failing does not stop later stages by default (so one run reports all failures), but the runner's exit code is the OR of all of them. A `--fail-fast` flag is optional.

### Test target versus app target

```
StrangewordsTests (bundle)  ──@testable import──►  Strangewords (app module)
        │                                                  │
        │ injects                                          │ owns
        ▼                                                  ▼
 ScriptedBackend / LocalBackend / APIClient(base:)     AppModel, TokenStore (UserDefaults.standard)
        │                                                  ▲
        └──────────── never the reverse: the app target has no knowledge of tests
```

Dependency direction is one way: tests import the app. The only app-side changes are the defaulted-parameter seams above.

### E2E harness versus server and robot

```
verify.sh ──spawns──► redis (docker, free port)
          ──spawns──► server  (SW_REDIS_ADDR=127.0.0.1:<rport>, SW_ADDR=127.0.0.1:<sport>, SW_RATE_RPS=0)
          ──spawns──► bot A ──HTTP──► server ◄──HTTP── bot B      (server matches them, 5-7-5 round robin)
          ──reads───► bots' JSON stdout (client's view)
          ──reads───► redis-cli / curl /metrics (server-side truth)
```

The harness never links Go packages from the server. It treats the server as a black box over HTTP, Redis, and `/metrics`. That is what makes this a different check from `gateway_test.go`, which runs the router in-process on miniredis. E2E adds what in-process tests cannot see: `main.go` wiring, `redisOptions`, real Redis TTL and `LPOP` semantics, `http.Server` timeouts, the real binary starting at all.

### Key Data Flows

1. **Two bots to a complete poem:** A enters (waiting), B enters (matched, atomic `LPOP`); A polls `/v1/waiting` and gets the session; participant 0 writes lines 0 and 2, participant 1 writes line 1; the 3rd submit flips status to `complete`. Each bot then dismisses; **the session only dissolves when both have dismissed** (`handleDismiss`), so the second dismiss returns `dissolved` and the first leaves the session in reveal. This is why the bot must not treat "partner already gone" as failure on its last step.
2. **Dissolution proof:** after both dismiss, the harness asserts three independent things: `GET /v1/session/{id}` returns 410, `redis-cli --scan 'sw:*'` is empty, and the `dissolved` counter in `/metrics` went up by 1. Three views of the same fact make a false pass unlikely.
3. **iOS state machine proof:** `AppModel` + `ScriptedBackend` walks `threshold → connecting → waiting → composing → reveal → dissolving → dissolved(.completedAndGone)`, plus the error branches (`.gone` → `partnerLeft`, `.contentRejected` sets `submitError`, `.notYourTurn` refetches, wait `.gone` → `noOneCame`), asserting `TokenStore` is cleared at every terminal phase and `keepsake` is set only on completion.

## Build Order (dependencies)

Two independent tracks can run in parallel after step 1. The runner is the join point.

```
 0. Reconcile working tree (uncommitted project.yml, run.sh, config.go, entitlements)
        │
 1. Baseline existing checks: go test/vet/build, xcodegen + xcodebuild build
        │   (finds drift BEFORE any new infrastructure; fix-as-we-go happens here)
        ├────────────────────────────┬───────────────────────────────
 iOS track                       Server/E2E track
 2. Test target skeleton         5. Harden bot (exit codes, -json, -fast)
    (project.yml + 1 trivial        │
     test, runs headlessly)      6. E2E orchestrator (lib.sh + stage_e2e.sh)
        │                           │   needs 5; needs Docker
 3. Seams (pollInterval,            │
    LocalBackend timings,           │
    APIClient base, TokenStore)     │
        │                           │
 4. Suites, easiest first:          │
    Syllables, PoemNaming,          │
    Models decoding →               │
    LocalBackend → AppModel         │
        │                           │
 7. iOS live tests ◄────────────────┘  needs 2, 3, and the server bring-up from 6
        │
 8. verify.sh + evidence collation  (needs 1, 4, 6, 7 working individually)
        │
 9. Blessed run recorded as the baseline: VERIFICATION.md + requirement traceability
```

**Ordering rationale:**

- **Step 1 first.** The cheapest information is whether what exists already passes. Any drift found there changes what is worth testing, and a fix made later would otherwise contaminate the new suites' first run.
- **Step 2 before any suite, with only one trivial test.** The riskiest unknown is the Xcode plumbing (XcodeGen test target, scheme test action, hosted launch, headless `xcodebuild test`, simulator availability). De-risk it with a single `XCTAssertTrue(true)` before writing real tests. The project's scheme is explicit, so it will not get a test action unless one is added.
- **Seams (3) before `AppModel`/`LocalBackend` suites (4).** Without them each polling test costs seconds and the suite will be slow and flaky.
- **Pure suites before stateful ones.** `Syllables`, `PoemNaming`, and `Models` decoding have no dependencies, produce passing tests quickly, and validate the target works. `PoemNaming` is deterministic by construction, so record golden outputs (a fixed poem produces a fixed name) rather than asserting vague properties.
- **Bot hardening (5) is on the critical path of E2E and independent of iOS.** It can be done in parallel with steps 2 to 4.
- **iOS live tests (7) last among the test code.** They need the test target, the `APIClient(base:)` seam, and a way to start a server, which step 6 provides. They are the highest-cost, so they come after the cheap layers already give a signal.
- **`verify.sh` (8) only after each stage runs standalone.** Wire the stages together last, once each has a stable command and a known-good result. Building the runner first just hides which layer is broken.

## Anti-Patterns

### Anti-Pattern 1: Reusing `live_test.sh` / `run_test_server_and_robot_poet_friend.sh` as the verification harness

**What people do:** Add flags to the existing interactive scripts so they "also" run headless.
**Why it's wrong:** They are built for a human at a keyboard. They kill any listener on `:8080`, `FLUSHALL` the Redis on `:6379`, write fixed `/tmp/sw-*` files, open the Simulator window, wait forever on `tail -f`, and the bot only exits 0 on every path. Mixing the two modes breaks the dev loop and still produces an unreliable verifier.
**Do this instead:** A separate `scripts/verify/` set with isolated ports and a throwaway Redis. Leave the dev scripts alone.

### Anti-Pattern 2: Asserting by grepping the bot's emoji output

**What people do:** `./bot ... | grep "the poem is complete"`.
**Why it's wrong:** It is a demo printout, so it changes whenever someone tweaks the text, and it cannot distinguish "completed" from "printed and then failed to dismiss". Today `-once` returns exit 0 even when `playOne` errored (the error is printed, then `if *once { return }`).
**Do this instead:** Give the bot a real contract: nonzero exit on any error or incomplete poem, plus one machine-readable `-json` line (session id, lines, final status, dismissed). The human-friendly output stays as the default.

### Anti-Pattern 3: UI automation (XCUITest) as the first iOS test layer

**What people do:** Start from end-to-end UI tests because they feel closest to "does the app work".
**Why it's wrong:** Slowest, flakiest, and needs accessibility identifiers the views do not have. The 3-second poll, animations, and dissolution effects make timing fragile. It would consume the milestone without testing logic any better than the state-machine tests do.
**Do this instead:** Unit-test `AppModel` against a fake `Backend` (phase is the full UI contract: "views are pure functions of `AppModel.phase`"), plus the live `APIClient` contract tests. UI tests are a follow-on if ever needed.

### Anti-Pattern 4: Real sleeps and unbounded waits in tests

**What people do:** `try await Task.sleep(for: .seconds(4))` to let polling happen.
**Why it's wrong:** Slow and flaky; the existing Go suite already forbids `time.Sleep` in new tests for the same reason.
**Do this instead:** Shrink the interval via the seam, and use a bounded `waitUntil` that polls a condition with a timeout and fails with a clear message.

### Anti-Pattern 5: Letting tests persist anything that outlives the encounter

**What people do:** Leave a token in `UserDefaults.standard`, or write poem text into a fixture committed to the repo or into evidence.
**Why it's wrong:** The project's constraint is that nothing identity-bearing or content-bearing survives the encounter. Test residue in `UserDefaults` is also a *functional* hazard, not just a principle (see Pitfalls).
**Do this instead:** Clear `TokenStore` in `setUp`/`tearDown`. Use clearly synthetic lines in tests. Evidence files may contain bot-written poem lines (from the curated bot lists), which is fine since they are not user content.

## Integration Points

### External Services and Tools

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| XcodeGen 2.45.4 (installed) | `ios/project.yml` is the single source of truth; add the test target and a scheme `test:` block there | `xcodegen generate` is already in `run.sh`; `.xcodeproj` stays gitignored |
| Xcode 16.4 / iOS 18.6 simulator (installed) | `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 16'` | Same device name `run.sh` resolves; `CODE_SIGNING_ALLOWED=NO` as `run.sh` does |
| `xcrun xcresulttool get test-results summary` (present in this Xcode) | Convert the `.xcresult` into JSON evidence | No `xcbeautify`/`xcpretty` installed; do not depend on them, plain `xcodebuild` output is fine in a log file |
| Docker 29 (installed) | Throwaway `redis:7-alpine` on a free port | No local `redis-server` binary exists, so Docker is the only real Redis. If Docker must be avoided later, a small Go entrypoint embedding `miniredis` (already a dependency) is the fallback, at the cost of not testing real Redis. |
| Go 1.26 | `go test -race -json ./...`, `go build -o <tmp>` for server and bot | `-race` is documented as "not wired into Makefile"; the runner should add it |
| `.github/workflows/fly-deploy.yml` | Unchanged | CI is out of scope; design the stages as standalone commands so a later workflow can call them |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `StrangewordsTests` to app target | `@testable import Strangewords` | One-way. Needs `ENABLE_TESTABILITY` which Debug has by default. |
| Test code to `Backend` | Inject `ScriptedBackend` / `LocalBackend(thinkTime: 0)` / `APIClient(base:)` | The existing protocol seam is the only abstraction needed |
| iOS live tests to server | HTTP to `SW_E2E_BASE` | Passed through `xcodebuild` as `TEST_RUNNER_SW_E2E_BASE=...` (xcodebuild forwards `TEST_RUNNER_`-prefixed variables to the test process, prefix stripped). The simulator shares the host network, and the app's plist already allows local networking (`NSAllowsLocalNetworking`). |
| `verify.sh` to stage scripts | Env vars (`EVIDENCE_DIR`, `COMMIT`) in; exit code + files out | Stages are independently runnable, which is what makes failures attributable |
| E2E harness to server | HTTP + Redis + `/metrics` only | Black box. Server is started with `SW_RATE_RPS=0` so the two bots are not rate limited; leave limiting on in a separate negative check only if wanted. |
| Bot to harness | Exit code + `-json` line | Contract introduced in step 5 |

## Pitfalls specific to this integration

These shape phase structure and are flagged here so they are not rediscovered mid-build.

1. **Hosted tests launch the real app, which can reach production.** `StrangewordsApp` creates `AppModel()` and runs `resume()` on appear; with no `SW_LOCAL_MOCK` it uses `APIClient.shared`, whose default base is `https://api.strangerwords.us`. If a previous test left a token in `UserDefaults.standard`, the host app's launch-time `resume()` would call production. Mitigate twice: set `SW_LOCAL_MOCK=1` in the scheme's test environment (the existing `run:` env does not apply to the test action), and clear `TokenStore` in test setup.
2. **An explicit `schemes:` block means no automatic test action.** The existing `Strangewords` scheme in `project.yml` is hand-declared, so the new target must be added to its `test:` section. Symptom if forgotten: `xcodebuild test` reports no tests or "scheme is not configured for the test action".
3. **Uncommitted `project.yml`.** The working tree changes bundle ID (`com.strangewords.app` to `com.strangerwords.us`), team ID, entitlements, and scheme env. The test target's bundle ID and `TEST_HOST` derive from these. Reconcile and commit before adding the target, or the first red build will be ambiguous.
4. **`SWIFT_VERSION: "5.0"` in project.yml.** Fine and keeps strict concurrency off, but `@MainActor` test classes and actor-based fakes should still be written correctly so a later Swift 6 migration does not break them.
5. **Concurrency semantics of `AppModel`.** `@MainActor` means test classes calling it must be `@MainActor` (or hop with `await MainActor.run`). Fire-and-forget `Task {}` inside `begin()`/`submit()` needs the `waitUntil` helper.
6. **E2E timing.** The bot pauses 1.5 to 3.3 s per line and polls every 1.5 s; a full two-bot poem takes roughly 8 to 15 s of wall time. Either accept that, or add the `-fast` flag. A hard overall timeout in the runner (kill and fail) is required so a hung match never blocks a run.
7. **Dissolution needs both dismisses.** A bot that errors on `410` after its partner dissolved the session will report a false failure. Treat 410 on the final dismiss as success only when the other bot has already dismissed (the runner can verify with the Redis check).

## Verify when building (MEDIUM-confidence items)

- XcodeGen's exact keys for a hosted test target and the scheme `test:` environment variables (confirm against the XcodeGen 2.45 ProjectSpec docs when writing `project.yml`).
- That `TEST_RUNNER_`-prefixed environment variables reach the test process on this Xcode version (a one-line probe test settles it).
- `GENERATE_INFOPLIST_FILE` for the unit-test bundle (needed because the app uses a custom `Info.plist` and the test bundle has none).
- Simulator readiness for headless runs: `xcodebuild test` boots the destination itself, but a first run on a cold simulator can exceed naive timeouts.

## Growth Considerations

Not a scaling question here; this is about what changes when CI arrives.

| Stage | Adjustment |
|-------|------------|
| Local only (this milestone) | `verify.sh` is the single entry point; Docker for Redis |
| Adding CI later | Stages become separate jobs. Go stage and E2E fit `ubuntu-latest` (Redis as a service container, no Docker-in-script). The iOS stage needs a `macos-*` runner with Xcode 16 and XcodeGen. Because stages are standalone scripts keyed by env vars (`EVIDENCE_DIR`, `SW_REDIS_ADDR`), the workflow is thin. Note `fly-deploy.yml` currently deploys without running tests; gating deploy on the Go stage is the natural first CI step. |
| More suites | Add an `xctestplan` to split fast unit tests from opt-in live tests, instead of env-based skips. Not needed yet. |

## Sources

- `/Users/charris/src/strangewords/ios/project.yml` (explicit scheme, single app target, working-tree edits) read directly. HIGH.
- `/Users/charris/src/strangewords/ios/Strangewords/App/AppModel.swift`, `Net/Backend.swift`, `Net/LocalBackend.swift`, `Net/APIClient.swift`, `Net/Keychain.swift`, `Net/Models.swift` read directly (seam analysis). HIGH.
- `/Users/charris/src/strangewords/server/cmd/bot/main.go`, `internal/gateway/gateway.go` (`handleDismiss`, `dissolve`), `server/Makefile`, `server/docker-compose.yml` read directly. HIGH.
- `/Users/charris/src/strangewords/run.sh`, `live_test.sh`, `run_test_server_and_robot_poet_friend.sh` read directly (reasons not to reuse). HIGH.
- Local toolchain probes: Xcode 16.4, iOS 18.6 runtime, XcodeGen 2.45.4, Docker 29.2.1, Go 1.26.0, `xcresulttool get test-results` present; no `redis-server`, `xcbeautify`, or `xcpretty`. HIGH.
- XcodeGen hosted unit-test target conventions and `TEST_RUNNER_` env forwarding: from established practice, not re-fetched this session. MEDIUM; see "Verify when building".
- `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/TESTING.md`, `.planning/PROJECT.md`. HIGH (project-internal).

---
*Architecture research for: automated test and verification infrastructure on an existing SwiftUI + Go/Redis app*
*Researched: 2026-10-08*
