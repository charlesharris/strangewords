# Project Status — pick up here

> **Snapshot:** 2026-06-17
> **Branch:** `main`
> **One-liner:** Anonymous, ephemeral iOS app for writing a 3-line poem with a stranger, then letting it go.

Read order for a newcomer: this file → `brief.v4.md` (intent) → `plan.v1.md` (architecture + phases) → `README.md` (how to run).

---

## Where we are

The **core experience works end to end**: a person enters, gets matched, takes turns writing a haiku (5-7-5 soft guidance), sees it revealed, and watches it dissolve — verified live against a robot partner on the simulator. The backend is complete and tested; the iOS app's core loop works; the day/night design is in (two passes).

**Not yet built:** push notifications (the async/durable-connection headline), the full "feel" pass (real dissolution animation, haptics, true fonts), safety/moderation, and shipping to TestFlight.

### What you can do today
```sh
./run.sh                  # app only, ONE sim, no backend — an on-device
                          # stranger auto-replies + dev time-of-day toggle on
                          # (the everyday dev/feel loop)
./live_test.sh            # Redis + backend + robot poet + app on one simulator
                          # tap "begin" in the sim → matched with the robot
./live_test.sh --night    # force a theme: --morning | --afternoon | --night
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
| 4 — Pacing / motion / a11y / copy | 🟡 partial | Reduce-Motion-aware scene, **bundled fonts (Fraunces + Inter)**, **softened syllable nudge**, **swappable dissolution (pixel + soft petals)**, **per-state dusk deepening**, **haptics**, basic VoiceOver labels, initial copy. **Missing:** reveal/compose micro-animations, Dynamic Type audit, smooth theme transitions, final copy |
| 5 — Safety rails | ⛔ not started | rate limiting, abusive-content filter, reporting + moderation store, EULA |
| 6 — Observability + deploy → TestFlight | ⛔ not started | basic `/metrics` counters exist; deploy + TestFlight need the Apple account |
| Design pass 1 — time-of-day theming | ✅ done | palette from local hour |
| Design pass 2 — richer scene | ✅ done | ridges, celestial body, stars/clouds, cherry branch (the "painterly" vector scene) |
| Design pass 3 — pixel-art scene | ✅ done | procedural pixel-art day/night: Bayer-dithered sky, pixel sun, **richer moon (glow + shading + craters)**, twinkling stars, drifting clouds, stepped hills, **pixel cherry branch** (the Nature theme) |
| Design pass 4 — themes | ✅ done | `SceneTheme` bundles palette + scene + dissolution. Ships **Nature**, **Sci-Fi** (ringed planet, lit-window skyline, derez), **Fantasy** (twin moons, castle, rising motes). Dev chip cycles themes |

---

## Repo map

```
brief.final.md   v3 brief (web app) — archived
brief.v4.md      current brief — iOS, durable/async connections, anonymity
plan.v1.md       build plan: architecture, API contract, Redis model, phases
docs/STATUS.md   this file
docs/haiku-*.png design boards (morning / afternoon / night)

server/          Go backend (one deployable)
  cmd/server     main
  cmd/bot        the robot poet (automated test participant)
  internal/
    sessions     pure domain: Form, TurnPolicy (round-robin), Session, validation
    store        Redis layer (atomic LPOP match, TTLs, teardown)
    matchmaker   pop-and-pair / enqueue
    gateway      HTTP handlers, auth, coordination
    push         APNs notifier interface (Noop for now)
    config, metrics

ios/             SwiftUI app (iOS 17+), generated from project.yml via XcodeGen
  Strangewords/
    App          StrangewordsApp, AppModel (state machine), RootView
    Net          APIClient (actor), Models (Codable), TokenStore
    Features     Threshold / Waiting / Compose / Reveal / Dissolved
    Design       Theme (palette + TimeOfDay), SceneBackground (procedural scene)
    Syllables    on-device vowel-cluster hint

run.sh                                  build + launch app on simulator(s)
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
- **Themes bundle the whole visual identity.** `Design/SceneTheme.swift` defines the `SceneTheme` protocol — a palette per time of day, a procedural `background`, and a `dissolution` — plus a `Themes` registry and a `\.sceneTheme` environment value. Three ship today (`Design/Themes/`): **Nature** (cherry-blossom scene + falling petals — the original), **Sci-Fi** (ringed planet over a lit-window city skyline + a "derez" of rising flickering fragments), **Fantasy** (twin moons + a castle silhouette + drifting motes + rising twinkling motes). Add a theme by conforming the protocol and listing it in `Themes.all`; swapping changes scene, colors, and dissolution together. Shared pixel primitives live in `Design/Pixel.swift` (dithered sky, disc/ring, ridges, stars, hash, `Color.mix`).
- **Dissolution is per-theme.** `Design/Dissolution.swift` defines `DissolutionEffect`; `RevealView` plays `theme.dissolution` when you tap "let it go", and transitions only once the effect signals done. Conformers: `PixelPetalDissolution` (nature), `SciFiDissolution`, `FantasyDissolution`, plus `PetalDissolution`/`FadeDissolution` (alternates). All Reduce-Motion-aware.
- **Swapping themes / time of day in dev.** Two stacked dev chips (top-trailing, shown when `Dev.showControls`) cycle the time of day and the theme. For screenshots/scripts, `SW_FORCE_THEME=nature|sci-fi|fantasy` and `SW_FORCE_TOD=...` force them; `SW_DEV_DISSOLVE=1` loops the active theme's dissolution. The retained vector scene (`Design/SceneBackground.swift`) is currently unused — a future theme could adopt it.
- **Per-state dusk deepening.** `SceneDepthOverlay` (in `RootView.swift`) is a dusk that gathers at the edges/ground as the arc progresses (composing 0.22 → reveal 0.70 → dissolved 1.0), modulated via `.opacity` so it animates with the phase change. Center stays clear so the poem stays legible; tone follows the time of day.
- **Haptics.** `App/Haptics.swift` centralizes a small tactile vocabulary; triggers live in `AppModel.apply` (which reads the outgoing phase to detect real transitions) plus the begin/offer/let-go taps, so both real and mock backends fire them. Silent on the simulator — feel them on device.
- **Dev affordances.** `App/Dev.swift` gates dev-only UI on `SW_LOCAL_MOCK=1` (`./run.sh --mock`) or `SW_DEV=1`. Currently: a top-trailing chip that cycles the time-of-day backdrop for previewing the three scenes without waiting on the clock.
- **Dev override:** `SW_FORCE_TOD=morning|afternoon|night` forces the theme (used by the `--morning/--afternoon/--night` script flags).
- **Tests live with the code:** `go test ./...` (uses miniredis, no services needed). Covers turn policy incl. N>2, validation, full poem, turn-order errors, idempotency, leave/teardown, the match race, and the zero-keys-after-dissolution anonymity invariant.

---

## Dependencies that block progress

- **Apple Developer account ($99/yr) + APNs auth key (.p8, Key ID, Team ID).** Needed for Phase 2 (push) and Phase 6 (TestFlight). Worth starting early — it's the long pole for getting real humans testing.

---

## Recommended next steps (any order)

1. ~~Bundle Larken + Inter~~ — **done** (Fraunces + Inter; see decisions above).
2. ~~Falling-petals dissolution~~ — **done** (`PetalDissolution`, swappable; see decisions above).
3. ~~Dynamic pixel-art day/night backgrounds~~ — **done** (`PixelScene`, swappable).
4. ~~Pixel-art polish~~ — **done**: richer night moon, pixel cherry branch, per-state dusk deepening, pixel dissolution variant, haptics, plus a dev time-of-day toggle. (See decisions above.)
5. **Remaining feel work** — reveal/compose micro-animations, Dynamic Type audit, smooth theme transitions across an hour boundary, final copy pass.
6. **Phase 2 push** — unlocks the actual async/durable-connection experience (needs Apple account).
7. **Phase 5 safety + Phase 6 TestFlight** — required before real strangers can use it.

Open richer-scene ideas: water/reflection at the bottom, a torii/bridge silhouette, seasonal blossom density, smooth theme transitions across an hour boundary.

---

## Git state

On branch `main` (the earlier `build/backend-core` work landed here); no remote
configured. Commits so far (newest first): feel pass — bundled fonts + mock
mode → STATUS snapshot → richer scene → theme flags → time-of-day theming →
live_test → robot poet → run.sh → iOS core loop → backend core + plan/briefs.
Plus fixes: token storage, script hardening, stray-simulator shutdown.
