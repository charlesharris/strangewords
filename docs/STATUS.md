# Project Status — pick up here

> **Snapshot:** 2026-06-17
> **Branch:** `main`
> **One-liner:** Anonymous, ephemeral iOS app for writing a 3-line poem with a stranger, then letting it go.

Read order for a newcomer: this file → `brief.v4.md` (intent) → `plan.v1.md` (architecture + phases) → `README.md` (how to run).

---

## Where we are

The **core experience works end to end**: a person enters, gets matched, takes turns writing a haiku (5-7-5 soft guidance), sees it revealed, and watches it dissolve — verified live against a robot partner on the simulator. The backend is complete and tested; the iOS app's core loop works.

The **feel pass is substantially done**: bundled fonts (Fraunces + Inter), a procedural pixel-art scene, a full-screen dissolution, per-state dusk deepening, haptics, a shared button style, and a randomized splash. The look is now a **theme system** — three themes ship (**Nature**, **Sci-Fi**, **Fantasy**), each bundling its own palette-per-time-of-day, scene, and dissolution; the time of day and theme are both swappable from dev chips. The app's user-facing name is **"Stranger Words"** (the repo/target stay `strangewords`).

**In progress:** Fly.io deployment scaffolding exists (Dockerfile, `fly.toml`, Redis TLS/password support) but hasn't been deployed yet — see "Deployment" below.

**Not yet built:** push notifications (the async/durable-connection headline — blocked on an Apple account), safety/moderation, Dynamic Type audit, final copy, and shipping to TestFlight.

### What you can do today
```sh
./run.sh                  # app only, ONE sim, no backend — an on-device stranger
                          # auto-replies + dev chips (time-of-day & theme) on
                          # (the everyday dev/feel loop)
./live_test.sh            # Redis + backend + robot poet + app on one simulator
./live_test.sh --night    # force a theme: --morning | --afternoon | --night

# Dev env overrides (any sim launch): force the look for screenshots/testing
#   SW_FORCE_THEME=nature|sci-fi|fantasy   SW_FORCE_TOD=morning|afternoon|night
#   SW_DEV_DISSOLVE=1   → boot into a looping dissolution of the active theme
```
See `README.md` for the full set of run/test options.

---

## Phase status (see plan.v1.md §11 for detail)

| Phase | State | Notes |
|-------|-------|-------|
| 0 — Scaffolding | ✅ done | monorepo, Go module, docker-compose, Makefile, XcodeGen project |
| 1 — Backend coordination core | ✅ done, tested | full poem + clean dissolution + zero-keys invariant verified |
| 2 — APNs push | ⛔ not started | **blocked: needs Apple Developer account + APNs key.** `push.Noop` is wired in its place |
| 3 — iOS core loop | ✅ working | live-verified via robot; the *async-by-push* half waits on Phase 2 |
| 4 — Pacing / motion / a11y / copy | 🟡 mostly | Reduce-Motion-aware scenes, **bundled fonts (Fraunces + Inter)**, **softened syllable nudge**, **per-theme dissolution (full-screen)**, **per-state dusk deepening**, **haptics**, **shared button style**, **randomized splash**, basic VoiceOver labels. **Missing:** Dynamic Type audit, smooth theme transitions across an hour boundary, final copy pass |
| 5 — Safety rails | ⛔ not started | rate limiting, abusive-content filter, reporting + moderation store, EULA |
| 6 — Observability + deploy → TestFlight | 🟡 started | basic `/metrics` counters exist; **Fly.io deploy scaffolding added (Dockerfile, `fly.toml`, Redis TLS) — not yet deployed**; TestFlight still needs the Apple account |
| Design pass 1 — time-of-day theming | ✅ done | palette from local hour |
| Design pass 2 — richer scene | ✅ done | ridges, celestial body, stars/clouds, cherry branch (the "painterly" vector scene) |
| Design pass 3 — pixel-art scene | ✅ done | procedural pixel-art day/night: Bayer-dithered sky, pixel sun, **richer moon (glow + shading + craters)**, twinkling stars, drifting clouds, stepped hills, **pixel cherry branch** (the Nature theme) |
| Design pass 4 — themes | ✅ done | `SceneTheme` bundles palette + scene + dissolution. Ships **Nature**, **Sci-Fi** (ringed planet, varied lit-window skyline with peaked/slanted/domed tops, full-screen derez), **Fantasy** (twin moons, castle, magical-flames burn-up). Dev chip cycles themes |

---

## Repo map

```
brief.final.md   v3 brief (web app) — archived
brief.v4.md      current brief — iOS, durable/async connections, anonymity
plan.v1.md       build plan: architecture, API contract, Redis model, phases
docs/STATUS.md   this file
docs/haiku-*.png design boards (morning / afternoon / night)
docs/screen-*.png README screenshots (one per time of day)

server/          Go backend (one deployable)
  cmd/server     main (reads SW_ADDR, SW_REDIS_ADDR/PASSWORD/TLS)
  cmd/bot        the robot poet (automated test participant)
  internal/
    sessions     pure domain: Form, TurnPolicy (round-robin), Session, validation
    store        Redis layer (atomic LPOP match, TTLs, teardown)
    matchmaker   pop-and-pair / enqueue
    gateway      HTTP handlers, auth, coordination
    push         APNs notifier interface (Noop for now)
    config, metrics
  Dockerfile, fly.toml, .dockerignore   Fly.io deploy (in progress)

ios/             SwiftUI app (iOS 17+), generated from project.yml via XcodeGen
  Strangewords/
    App          StrangewordsApp, AppModel (state machine incl. .dissolving),
                 RootView (theme + tod + dev chips), Dev, Haptics
    Net          Backend protocol, APIClient (actor), LocalBackend (mock),
                 Models (Codable), TokenStore
    Features     Threshold (+ SplashLines) / Waiting / Compose / Reveal / Dissolved
    Design       Theme (typography + Palette + TimeOfDay), Pixel (shared
                 primitives), SceneTheme (+ Themes registry), Themes/ (Nature,
                 SciFi, Fantasy), PixelScene (nature), SceneBackground (unused
                 vector scene), Dissolution (effects), RitualButton
    Resources/Fonts  Fraunces*, Inter, OFL licenses
    Syllables    on-device vowel-cluster hint

run.sh                                  build + launch; DEFAULT = 1 sim, mock, dev chips on
live_test.sh                            one command: backend + robot + app
run_test_server_and_robot_poet_friend.sh  backend + robot only
```

---

## Key implementation decisions & deviations from the plan

These are choices made during the build that a future session should know:

- **Token storage: UserDefaults, not Keychain.** Keychain writes fail silently on unsigned simulator builds (no entitlement), which caused a "matched but frozen" bug. The token is an ephemeral infra bearer credential, so UserDefaults is fine. `ios/.../Net/TokenStore` is the single place to change if signed builds ever want hardware-backed storage. (Resolved a real bug — see git log.)
- **Matchmaking is atomic via `LPOP`** (not the Lua script the plan mentioned). Single `LPOP` is atomic and keeps the test suite runnable against in-process **miniredis** with no external Redis.
- **Sessions stored as a JSON blob** at `sw:sess:{id}` (not hash fields). Equivalent for our always-whole-object access; simpler.
- **Reveal-window cap (120s) is implemented as a shortened Redis TTL** on completion — self-expires even if clients vanish, no sweeper needed.
- **iOS:** iOS 17+, **no third-party dependencies**, `SWIFT_VERSION = 5.0`. The `.xcodeproj` and generated `Info.plist` are **gitignored** — regenerate with `xcodegen generate` (or just run `./run.sh`).
- **Fonts:** the boards specify **Larken (display serif) + Inter (body)**. Larken is commercial, so **Fraunces** — a free, OFL, high-contrast display serif in the same spirit — stands in as the display voice; **Inter** is the body sans. Both are bundled in `ios/Strangewords/Resources/Fonts` (+ their `OFL-*.txt`) and registered via `UIAppFonts`. Fraunces was **partially instanced** (pinned `wght`/`SOFT`/`WONK`, `opsz` left free so CoreText optically sizes it). All type routes through `Design/Theme.swift` — swapping to licensed Larken later means dropping the files in and changing the family name in one place. Regenerate fonts with `/tmp/build_fonts.py` (uses `fonttools`; see git history of this work).
- **Mock backend:** `ios/.../Net/Backend.swift` is the network seam; `LocalBackend` is a full on-device fake (instant match + a simulated stranger that auto-writes its lines). Selected by `SW_LOCAL_MOCK=1` / `./run.sh --mock` in `AppModel.init`. Lets you exercise the whole arc on one simulator with no server — the fast loop for feel work.
- **Themes bundle the whole visual identity.** `Design/SceneTheme.swift` defines the `SceneTheme` protocol — a palette per time of day, a procedural `background`, and a `dissolution` — plus a `Themes` registry and a `\.sceneTheme` environment value. Three ship today (`Design/Themes/`): **Nature** (cherry-blossom scene + falling petals — the original), **Sci-Fi** (ringed planet over a lit-window city skyline + a full-screen "derez" pixel-dissolve that wipes the text), **Fantasy** (twin moons + a castle silhouette + drifting motes + a magical-flames dissolution that burns the poem away upward). Add a theme by conforming the protocol and listing it in `Themes.all`; swapping changes scene, colors, and dissolution together. Shared pixel primitives live in `Design/Pixel.swift` (dithered sky, disc/ring, ridges, stars, hash, `Color.mix`).
- **Dissolution is per-theme and full-screen.** `Design/Dissolution.swift` defines `DissolutionEffect`. Tapping "let it go" → `AppModel.release()` → a `.dissolving` phase that `RootView` renders **full-screen, outside the padded content** (so it covers the whole scene — buildings and all), then `finishDissolving()` → `.dissolved`. Conformers: `PixelPetalDissolution` (nature: flip-flutter petals), `SciFiDissolution` (full-screen derez wipe), `FantasyDissolution` (flames sweeping up, poem burns bottom-line-first), plus `PetalDissolution`/`FadeDissolution` (alternates). All Reduce-Motion-aware. Each effect pads only its own text so the Canvas stays full-bleed.
- **Per-state dusk deepening.** `SceneDepthOverlay` (in `RootView.swift`) is a dusk that gathers at the edges/ground as the arc progresses (composing 0.22 → reveal 0.70 → dissolving 0.85 → dissolved 1.0), modulated via `.opacity` so it animates with the phase change. Center stays clear so the poem stays legible; tone follows the time of day.
- **Buttons** use a shared `RitualButtonStyle` (`Design/RitualButton.swift`, `.buttonStyle(.ritual)`): a capsule filled with `onAccent` (light on day palettes, dark at night — the opposite of the `ink` label) so it stays legible over any scene, with disabled dimming + press feedback handled by the style.
- **Splash.** Title is **"Stranger Words"**; the tagline is a random pick from `Features/Threshold/SplashLines.swift` (~10 lines), re-rolled each time the threshold appears.
- **App name.** User-facing name is "Stranger Words" (`CFBundleDisplayName`, README). Technical identifiers stay `strangewords`/`Strangewords` (Go module, Xcode target/scheme/folder, `com.strangewords.app`) — renaming them is needless churn and they're never user-visible.
- **Haptics.** `App/Haptics.swift` centralizes a small tactile vocabulary; triggers live in `AppModel.apply` (reads the outgoing phase to detect real transitions) plus the begin/offer/let-go taps, so both real and mock backends fire them. Silent on the simulator — feel them on device.
- **Dev affordances.** `App/Dev.swift` gates dev-only UI: `Dev.showControls` (`SW_LOCAL_MOCK=1` via `./run.sh --mock`, or `SW_DEV=1` — set on every `run.sh` launch) shows two top-trailing chips that cycle **time of day** and **theme**. `Dev.previewDissolution` (`SW_DEV_DISSOLVE=1`) boots into a looping dissolution of the active theme. Env forcers for screenshots/scripts: `SW_FORCE_TOD`, `SW_FORCE_THEME`. The retained vector scene (`Design/SceneBackground.swift`) is currently unused — a future theme could adopt it.
- **`run.sh` defaults to ONE simulator in mock mode** (on-device stranger, no backend) with dev chips on — the everyday loop. `--solo` = one sim against a real backend (used by `live_test.sh` + robot poet); `--two` = two sims (be both strangers). It shuts down *every* other booted simulator so a stray (e.g. an iPhone 16 Plus) can't launch alongside.
- **Tests live with the code:** `go test ./...` (uses miniredis, no services needed). Covers turn policy incl. N>2, validation, full poem, turn-order errors, idempotency, leave/teardown, the match race, and the zero-keys-after-dissolution anonymity invariant.

---

## Dependencies that block progress

- **Apple Developer account ($99/yr) + APNs auth key (.p8, Key ID, Team ID).** Needed for Phase 2 (push) and Phase 6 (TestFlight). Worth starting early — it's the long pole for getting real humans testing.

---

## Deployment (in progress)

Backend deploy to **Fly.io** is scaffolded but **not yet deployed**. Files: `server/Dockerfile` (static binary on alpine, non-root), `server/fly.toml` (app `strangewords`, region `sjc`, one warm machine, `/healthz` check), `server/.dockerignore`. The server reads `SW_ADDR`, `SW_REDIS_ADDR`, `SW_REDIS_PASSWORD`, `SW_REDIS_TLS` (TLS for `rediss://` endpoints).

Runbook to finish (not yet run):
1. `cd server && fly launch --no-deploy` (or `fly apps create strangewords`).
2. Provision Redis (e.g. Upstash) in the same region; note the host/port/password and whether it needs TLS.
3. `fly secrets set SW_REDIS_ADDR=… SW_REDIS_PASSWORD=… SW_REDIS_TLS=1`.
4. `fly deploy`; verify `curl https://<app>.fly.dev/healthz`.
5. Point the iOS app's base URL at the deployed host (currently `http://127.0.0.1:8080` in `ios/.../Net/APIClient.swift`; the dev-only ATS exception in `project.yml` allows local HTTP — production should be HTTPS).

> Note: the Fly.io files landed bundled into the skyline commit `36582c7` (an accidental `git add -A`); content is correct and tests pass, history left as-is.

---

## Recommended next steps (any order)

Feel pass largely done — fonts, themes (Nature/Sci-Fi/Fantasy), full-screen dissolutions, dusk deepening, haptics, button style, randomized splash. What's left:

1. **Finish the Fly.io deploy** (see Deployment above) — gets a real backend online; doesn't need an Apple account.
2. **Remaining feel work** — Dynamic Type audit, smooth theme transitions across an hour boundary, final copy pass.
3. **Phase 2 push** — the actual async/durable-connection experience (needs Apple account).
4. **Phase 5 safety + Phase 6 TestFlight** — required before real strangers can use it.

Open ideas: a 4th theme from the unused vector scene; per-theme time-of-day tuning (sci-fi day skyline, fantasy day moons); water/reflection; smooth theme transitions across an hour boundary.

---

## Git state

On branch `main`, pushed to `origin` (`github.com:charlesharris/strangewords`).
Recent arc (newest first): sci-fi skyline variety + bundled Fly.io deploy files →
full-screen dissolution + varied skyline → reworked sci-fi/fantasy dissolutions →
theme system (Nature/Sci-Fi/Fantasy) → button style + mock-resume fix → splash
rename + randomized lines → run.sh single-sim/mock defaults → pixel-art polish
(moon, branch, dusk, haptics, dev toggle) → pixel scene → fonts + mock mode →
backend core + plan/briefs.
