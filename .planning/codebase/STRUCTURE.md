---
last_mapped_commit: 4196ce5e0ccea3955e6a70452d0cded834a85ad4
last_mapped_at: 2026-10-08
---
# Codebase Structure

**Analysis Date:** 2026-10-08

## Directory Layout

```
strangewords/                         # repo root (git, branch main)
├── .github/workflows/                # CI: fly-deploy.yml (push to main → flyctl deploy)
├── docs/                             # STATUS.md (start here), README screenshots, design boards
├── ios/                              # SwiftUI app (XcodeGen; project.yml is source of truth)
│   ├── project.yml                   # XcodeGen spec: targets, UIAppFonts, bundle id, ATS
│   └── Strangewords/                 # app sources (folder = Xcode target "Strangewords")
│       ├── App/                      # entry point, AppModel state machine, RootView, dev/haptics
│       ├── Net/                      # Backend protocol, APIClient, LocalBackend, Models, TokenStore
│       ├── Features/                 # one folder per phase screen
│       │   ├── Threshold/            # entry screen + SplashLines
│       │   ├── Waiting/              # waiting-for-a-stranger screen
│       │   ├── Compose/              # line-writing screen
│       │   ├── Reveal/               # completed poem screen
│       │   └── Dissolved/            # ending screen (keepsake name)
│       ├── Design/                   # theme, pixel primitives, scenes, dissolutions, buttons
│       │   └── Themes/               # NatureTheme, SciFiTheme, FantasyTheme
│       ├── Syllables/                # on-device vowel-cluster syllable hint
│       ├── Naming/                   # on-device keepsake-name coiner (PoemNaming)
│       ├── Resources/Fonts/          # Fraunces*.ttf, Inter.ttf, OFL-*.txt licenses
│       └── Assets.xcassets/          # AppIcon.appiconset
├── server/                           # Go backend (module "strangewords")
│   ├── cmd/
│   │   ├── server/                   # main.go (deployable), main_test.go
│   │   └── bot/                      # main.go (robot poet test client)
│   ├── internal/                     # all non-exported packages
│   │   ├── config/                   # config.go: env-driven Config
│   │   ├── gateway/                  # HTTP handlers, middleware, and their tests
│   │   ├── matchmaker/               # enqueue / pair
│   │   ├── metrics/                  # Prometheus collectors
│   │   ├── moderation/               # report Sink + LogSink
│   │   ├── push/                     # APNs Notifier interface + Noop
│   │   ├── sessions/                 # pure domain: session, form, policy, validation, screener
│   │   └── store/                    # Redis persistence + TTLs
│   ├── Dockerfile                    # static binary on alpine, non-root
│   ├── fly.toml                      # Fly app "strangewords", region sjc, /healthz check
│   ├── docker-compose.yml            # local Redis (and Postgres in Phase 5)
│   ├── Makefile                      # run, test, and local dev targets
│   ├── DEPLOY.md                     # authoritative deploy runbook
│   ├── go.mod / go.sum
│   └── .dockerignore
├── brief.v4.md                       # current product brief (intent)
├── brief.final.md                    # archived v3 brief (web app)
├── plan.v1.md                        # architecture, API contract, Redis model, phases
├── README.md                         # how to run the backend and iOS app
├── run.sh                            # build + launch iOS sim (default: mock mode, one sim)
├── live_test.sh                      # backend + robot poet + app on one simulator
└── run_test_server_and_robot_poet_friend.sh  # backend + robot only
```

## Directory Purposes

**`server/internal/sessions/`:**
- Purpose: pure domain logic with no I/O.
- Contains: `session.go` (`Session`, `Participant`, `Status`, `ViewFor`), `form.go` (`Form`, `LookupForm`, `haiku` registry entry), `policy.go` (`TurnPolicy`, `roundRobin`, `LookupPolicy`), `validate.go` (`CleanLine`), `content.go` (`Screener`, `fold`, `parseTermList`), `banned_terms.txt` (embedded word list).
- Key files: `server/internal/sessions/session.go`, `server/internal/sessions/form.go`, `server/internal/sessions/policy.go`.
- Tests: `*_test.go` beside each file.

**`server/internal/store/`:**
- Purpose: all Redis reads and writes, key naming, and TTL policy.
- Contains: `store.go` only. Key constants and builders, token and ID generators (`NewToken`, `NewID`), `Enqueue`, `PopWaiter`, session save/get/delete, and idempotency cache.
- Key files: `server/internal/store/store.go`.
- Tests: none in this package. The Redis behavior is exercised through `gateway` tests against miniredis.

**`server/internal/gateway/`:**
- Purpose: HTTP surface.
- Contains: `gateway.go` (routes and handlers), `middleware.go` (body limit, panic recovery, rate limiter, client IP), and tests `gateway_test.go`, `middleware_test.go`, `report_test.go`.
- Key files: `server/internal/gateway/gateway.go` (`Routes()` lists every endpoint).

**`server/internal/matchmaker/`:**
- Purpose: pairing strategy.
- Contains: `matchmaker.go` (`Enter`, `enqueue`, `pair`). No tests in this package. Coverage comes from the gateway match-race tests.

**`server/internal/moderation/`, `server/internal/push/`, `server/internal/metrics/`, `server/internal/config/`:**
- Purpose: side-effect seams and cross-cutting concerns. Each is a small single file.
- Key files: `moderation.go` (`Sink`, `Report`, `LogSink`), `push.go` (`Notifier`, `Noop`, `Kind`), `metrics.go` (counters such as `sw_entered_total`, `sw_matched_total`, plus RED metrics), `config.go` (`Load`, `SW_*` env vars).

**`server/cmd/server/`:**
- Purpose: the one deployable server binary.
- Contains: `main.go` (composition root and `redisOptions`), `main_test.go`.

**`server/cmd/bot/`:**
- Purpose: a robot poet that talks to the public API. Used for end-to-end testing with `live_test.sh`.
- Contains: `main.go` only.

**`ios/Strangewords/App/`:**
- Purpose: app shell and the phase state machine.
- Contains: `StrangewordsApp.swift` (`@main`), `AppModel.swift` (`Phase`, `Reason`, transitions, polling), `RootView.swift` (phase switch, `DissolutionPreviewView`, `SceneDepthOverlay`), `Haptics.swift`, `Dev.swift` (dev-only flags).
- Key files: `ios/Strangewords/App/AppModel.swift`, `ios/Strangewords/App/RootView.swift`.

**`ios/Strangewords/Net/`:**
- Purpose: everything that crosses the network or persists the token.
- Contains: `Backend.swift` (protocol), `APIClient.swift` (production), `LocalBackend.swift` (mock), `Models.swift` (Codable types), `Keychain.swift` (`TokenStore`, which is UserDefaults-backed).
- Key files: `ios/Strangewords/Net/Backend.swift`, `ios/Strangewords/Net/APIClient.swift`.

**`ios/Strangewords/Features/`:**
- Purpose: one screen per `AppModel.Phase`.
- Contains: `Threshold/ThresholdView.swift` + `SplashLines.swift`, `Waiting/WaitingView.swift`, `Compose/ComposeView.swift`, `Reveal/RevealView.swift`, `Dissolved/DissolvedView.swift`.

**`ios/Strangewords/Design/`:**
- Purpose: visual system shared by all features.
- Contains: `Theme.swift` (type scale, `Palette`, `TimeOfDay`), `Pixel.swift` (dither, disc, ridges, stars, `Color.mix`), `PixelScene.swift` (nature scene), `SceneBackground.swift` (unused vector scene), `SceneTheme.swift` (protocol and `Themes.all`), `Dissolution.swift` (effects), `RitualButton.swift`.
- Subfolder `Themes/`: one file per theme, each conforming to `SceneTheme`.

**`ios/Strangewords/Syllables/` and `ios/Strangewords/Naming/`:**
- Purpose: pure on-device functions with no network calls.
- Key files: `Syllables/Syllables.swift`, `Naming/PoemNaming.swift`.

**`docs/`:**
- Purpose: project status and visual references.
- Contains: `STATUS.md` (current snapshot and phase table), `screen-*.png` (README screenshots), `haiku-*.png` (design boards).

## Key File Locations

**Entry Points:**
- `server/cmd/server/main.go`: backend `main`.
- `server/cmd/bot/main.go`: robot poet `main`.
- `ios/Strangewords/App/StrangewordsApp.swift`: iOS `@main`.

**Configuration:**
- `server/internal/config/config.go`: Go env config (`SW_ADDR`, `SW_DEBUG_ADDR`, `SW_REDIS_ADDR`, `SW_REDIS_PASSWORD`, `SW_REDIS_TLS`, and others).
- `server/fly.toml`: Fly.io app definition.
- `server/docker-compose.yml`: local Redis.
- `ios/project.yml`: XcodeGen project (bundle id `app.strangewords`, deployment target iOS 17.0, `UIAppFonts`).
- `ios/Strangewords/Strangewords.entitlements`: App Attest entitlement (referenced by `CODE_SIGN_ENTITLEMENTS`).
- `.github/workflows/fly-deploy.yml`: CI deploy.

**Core Logic:**
- `server/internal/sessions/session.go`: session model and per-participant view.
- `server/internal/store/store.go`: Redis layer.
- `server/internal/matchmaker/matchmaker.go`: pairing.
- `server/internal/gateway/gateway.go`: request handling.
- `ios/Strangewords/App/AppModel.swift`: client state machine.

**Testing:**
- `server/**/*_test.go`: Go unit and integration tests. Run with `go test ./...` from `server/`. They use miniredis and need no external services.
- No iOS test target is present in `ios/project.yml`.

## Naming Conventions

**Go files:**
- Lowercase single words, one concept per file: `session.go`, `policy.go`, `middleware.go`.
- Tests: `<name>_test.go` in the same package.
- Packages: lowercase single word under `internal/`.

**Go identifiers:**
- Exported types `PascalCase`: `Session`, `Matchmaker`, `LogSink`.
- Unexported helpers `camelCase`: `queueKey`, `waitKey`, `handleLine`, `writeErr`.
- Redis keys use the `sw:` prefix with a noun and ID: `sw:queue:{bucket}`, `sw:wait:{id}`, `sw:tok:{token}`, `sw:sess:{id}`, `sw:idem:{sid}:{key}`.
- Handler methods are `handle<Verb><Noun>` on `*Server`: `handleEnter`, `handleLine`, `handleReport`.

**Swift files:**
- One primary type per file, named after it: `AppModel.swift`, `APIClient.swift`, `RitualButton.swift`.
- View files end in `View.swift`: `ComposeView.swift`, `RevealView.swift`.
- Theme files end in `Theme.swift` under `Design/Themes/`: `SciFiTheme.swift`.

**Swift identifiers:**
- Types `PascalCase`, members `camelCase`. Phase cases are lowercase enum cases: `.composing(SessionView)`, `.dissolved(Reason)`.
- Environment keys `\.sceneTheme`. Button style `.ritual`.

**Directories:**
- Server: lowercase single words under `internal/` and `cmd/`.
- iOS: `PascalCase` folders matching the Swift feature or concept (`Features/Compose`, `Design/Themes`).

**Repo-level docs:** UPPERCASE for doc names that are key (`README.md`, `STATUS.md`), and `<name>.v<N>.md` for versioned briefs and plans (`brief.v4.md`, `plan.v1.md`).

## Where to Add New Code

**New poem form (for example tanka or free verse):**
- Primary code: add an entry to the registry in `server/internal/sessions/form.go`.
- Client: consume `FormView` from `ios/Strangewords/Net/Models.swift`. Do not hardcode line counts in `Features/Compose/`.
- Tests: `server/internal/sessions/validate_test.go` or a new `form_test.go` beside `form.go`.

**New turn policy:**
- Primary code: implement `TurnPolicy` in `server/internal/sessions/policy.go` and register it in `LookupPolicy`.
- Tests: `server/internal/sessions/policy_test.go`.

**New HTTP endpoint:**
- Route: add a `mux.HandleFunc("METHOD /v1/...")` line in `Routes()` in `server/internal/gateway/gateway.go`.
- Handler: a `handle<Verb><Noun>` method on `*Server` in `gateway.go`.
- Storage: add a method to `server/internal/store/store.go` and do not call `rdb` directly.
- Tests: add a case to `server/internal/gateway/gateway_test.go`.

**New Redis key:**
- Add a key builder beside `queueKey`/`waitKey`/`sessKey` in `server/internal/store/store.go` with a TTL constant, so the teardown path covers it.

**New push type or APNs client:**
- Implement `push.Notifier` in a new file under `server/internal/push/` (for example `apns.go`). Replace `push.Noop{Log: log}` in `server/cmd/server/main.go`.

**Durable moderation store (Phase 5):**
- Implement `moderation.Sink` in `server/internal/moderation/`. Replace `moderation.LogSink` in `main.go`.

**New Feature screen:**
- Implementation: `ios/Strangewords/Features/<Name>/<Name>View.swift`. Add a `Phase` case in `AppModel.swift` and a branch in `RootView.swift`.

**New Theme:**
- Implementation: `ios/Strangewords/Design/Themes/<Name>Theme.swift` conforming to `SceneTheme`, then listed in `Themes.all` in `ios/Strangewords/Design/SceneTheme.swift`.
- Dissolution: add a conformer to `ios/Strangewords/Design/Dissolution.swift` if the theme needs a new effect.

**New shared UI primitive:**
- `ios/Strangewords/Design/Pixel.swift` for pixel drawing, `Design/RitualButton.swift` for button styles, `Design/Theme.swift` for type and palette tokens.

**Utilities:**
- Server shared helpers: `server/internal/sessions/validate.go` for input cleanup. There is no general `util` package, so add to the most specific existing package.
- iOS pure logic: a new folder under `ios/Strangewords/` beside `Syllables/` and `Naming/`.

**Mock behavior for a new endpoint:**
- Add the matching method to `ios/Strangewords/Net/LocalBackend.swift` so `./run.sh --mock` keeps working.

## Special Directories

**`ios/Strangewords/Resources/Fonts/`:**
- Purpose: bundled fonts (Fraunces, Inter) and their OFL license text.
- Generated: No (committed binaries). Regeneration notes live in `docs/STATUS.md`.
- Committed: Yes.

**`ios/Strangewords/Assets.xcassets/`:**
- Purpose: app icon and asset catalog.
- Generated: No.
- Committed: Yes.

**`ios/Strangewords.xcodeproj/` and `ios/Strangewords/Info.plist`:**
- Purpose: Xcode project and generated Info.plist.
- Generated: Yes, by `xcodegen generate` from `ios/project.yml`.
- Committed: No (gitignored).

**`ios/build/`, `ios/**/DerivedData/`, `ios/**/xcuserdata/`:**
- Purpose: build output and per-user Xcode state.
- Generated: Yes.
- Committed: No (gitignored).

**`server/bin/`:**
- Purpose: compiled binaries from `make`.
- Generated: Yes.
- Committed: No (gitignored).

**`.planning/`:**
- Purpose: GSD planning artifacts. `.planning/codebase/` holds these mapping documents.
- Generated: Yes, by `/gsd-map-codebase`.
- Committed: Per project workflow.

---

*Structure analysis: 2026-10-08*
