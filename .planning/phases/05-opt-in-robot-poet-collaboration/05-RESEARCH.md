# Phase 5: Opt-In Robot Poet Collaboration - Research

**Researched:** 2026-10-26
**Domain:** Go matchmaking/session coordination (stdlib + go-redis) and SwiftUI iOS 17 settings/disclosure, wire-contract change across both
**Confidence:** HIGH (almost entirely in-repo reconnaissance; the few `[ASSUMED]` items are listed in the Assumptions Log)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
1. **Strict opt-in, default OFF.** A user is never paired with the bot unless they enabled the setting. No dark patterns; the default experience is humans-only.
2. **Settings UI: quiet gear on the Threshold.** A small, unobtrusive settings affordance on the entry screen opening a minimal sheet containing the one toggle (persisted via the existing UserDefaults-backed TokenStore pattern or a sibling store — UserDefaults use is already declared CA92.1 in PrivacyInfo.xcprivacy). The sheet should leave room for future settings (safety/EULA later), but this phase ships only the bot toggle.
3. **Pairing rule: bot as fallback after a wait window.** Opted-in users still try for a human first. Only if no human pairs within a tunable window (~20–30s, mark `[TUNABLE]`) does the bot step in. Two opted-in humans who overlap must pair with each other, never each get a bot. The mechanism (server-side pairing vs. bot-client polling for lonely opted-in waiters) is the planner's/researcher's call — the behavior above is what's fixed.
4. **Disclosure: named presence.** The session UI quietly labels the partner as the robot poet (e.g. in the compose header where turn state shows), visible for the whole session — matching the repo's existing "robot poet friend" voice. No undisclosed bots, ever.
5. **Bot generation: the existing `server/internal/poet` package** (quick task 261026-p8l). No external AI/API calls.

### Claude's Discretion
The fallback **mechanism** (server-side pairing vs. bot-client polling), the exact wire field placement/name beyond "allowBot on POST /v1/enter", the disclosure field shape on the session view, the settings store shape, and the window value inside ~20–30s.

### Deferred Ideas (OUT OF SCOPE)
- Push notifications, safety/EULA UI, public-link beta hardening.
- Any change to the poet package's generation quality (separate concern).

**Constraints carried from the project (CONTEXT.md):**
- Wire-contract change must be mirrored in server handlers, `ios/Strangewords/Net/Models.swift`, the `Backend` protocol, `APIClient`, **and `LocalBackend`**.
- Anonymity model holds: the opt-in flag must not persist beyond the encounter's existing TTLs or become an identifier.
- Tests on both sides (Go + Swift) are required.
- Backward compatibility: shipped TestFlight build 0.1.0 sends no flag; absent flag must mean `allowBot=false`.
</user_constraints>

<phase_requirements>
## Phase Requirements

No requirement IDs are assigned (phase added post-roadmap, `ROADMAP.md` says "Requirements: TBD"). Acceptance is derived from the goal and CONTEXT.md. Suggested working labels for the planner (not in REQUIREMENTS.md; the planner may promote them):

| Label | Derived acceptance | Research Support |
|-------|--------------------|------------------|
| P5-OPTIN | `POST /v1/enter` accepts `allowBot` (bool); absent/non-bool/false means never paired with the bot | Wire contract section; decode tolerance verified |
| P5-FALLBACK | An opted-in waiter with no human after `BotWindow` is paired with the bot; two overlapping opted-in humans always pair with each other; non-opted-in never gets a bot | Mechanism section (LREM claim) |
| P5-DISCLOSE | Every session containing a bot yields `partnerIsBot: true` to the human; human-human sessions never do; iOS shows a persistent named presence for the whole session (compose + reveal) | Session view + iOS sections |
| P5-SETTINGS | Gear on Threshold opens a sheet with one toggle, default OFF, persisted on device, read at `begin()` | iOS section |
| P5-PARITY | `Backend`, `APIClient`, `LocalBackend`, `Models.swift` all carry the contract; LocalBackend simulates the fallback | iOS section |
| P5-ANON | After dissolution: zero `sw:*` keys (including the bot path); `allowBot` lives only on TTL-bounded records | Anonymity section |
| P5-TESTS | Go + Swift automated tests for all of the above (no human-driven simulator) | Test Surfaces section |
</phase_requirements>

## Summary

The fallback should be **server-side and request-driven, with no bot process at all**. Production runs exactly one Fly `[http_service]` (`server/fly.toml`); `cmd/bot` is a dev tool that is never deployed, and `auto_stop_machines = "stop"` rules out relying on long-lived goroutines. The waiting client already polls `GET /v1/waiting` every 3 s, so that poll is the natural clock: when the caller's wait entry is `AllowBot` and older than the window, the handler atomically claims the waiter out of its own queue (`LREM sw:queue:<bucket> 1 <waitId>`), builds a two-participant session whose second participant is flagged `Bot`, points the human's token at it, and deletes the wait entry. `LREM` and the arriving human's `LPOP` are both single Redis commands, so exactly one of them wins: the existing atomicity story (one atomic Redis op decides ownership) is preserved and a human/bot race cannot produce two sessions. Because the bot is never a queue member, a non-opted-in arriver can never pop it; "segregation" is structural rather than a second queue.

The bot then plays **lazily on the human's own polls**: the session stores `BotReadyAt` (a think-time deadline); `GET /v1/session/{id}` and the matched branch of `GET /v1/waiting` apply the bot's line when it is the bot's turn and the deadline has passed. The line is produced by a stateless replay of `poet.New(seed)` over the bot's earlier turns — **verified this session**: a fresh `Poet` that replays its prior turns reproduces the identical later line for 500 seeds. This is restart-safe (all state in Redis), adds no Redis keys (zero-keys-after-dissolution holds), and needs no CAS because the human cannot write while it is the bot's turn.

On iOS the work is mechanical but wide: `SessionView` gains a tolerant `partnerIsBot`, `Backend.enter` gains `allowBot`, a sibling `SettingsStore` (key **not** prefixed `sw.`, see Pitfall 5) feeds an `AppModel.allowBot` property, `ThresholdView` gets a gear + `.sheet`, `ComposeView`/`RevealView` get a persistent named-presence caption, and `LocalBackend` simulates the opted-in wait-then-bot arc. All test seams needed (`FakeBackend`, injected `UserDefaults`, zero-delay `LocalBackend`, injectable `Server.now`) already exist.

**Primary recommendation:** Implement option (c′) — server-side, poll-driven bot (claim via `LREM`, lazy lines via deterministic poet replay, `Participant.Bot` + `View.PartnerIsBot`), with `BotWindow` default 25 s in `config.go`; do not build a bot worker, a "lonely waiters" endpoint, or a second queue.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Opt-in preference storage | Browser/Client (UserDefaults on device) | — | Preference, not identity; never needs to outlive the device. Server only sees it per-enter |
| Opt-in transport (`allowBot`) | API/Backend (`handleEnter`) | — | Per-request flag, decoded leniently, stored only on the TTL-bound `WaitEntry` |
| Fallback timing decision | API/Backend (`handleWaiting`) | Database/Storage (queue claim) | Server clock owns the window; client cannot be trusted to ask for a bot |
| Atomic claim (human vs. bot race) | Database/Storage (`LREM` vs `LPOP`) | API/Backend (store method) | Redis single-command atomicity is the project's existing mutual-exclusion primitive |
| Bot line generation | API/Backend (new `botplayer` pkg over `poet`) | — | "No external AI"; privacy.html already states bot lines come from our own server |
| Bot turn pacing | API/Backend (lazy, poll-driven, `BotReadyAt`) | — | Restart-safe; no goroutine/worker topology on Fly |
| Disclosure truth (`partnerIsBot`) | API/Backend (`Session.ViewFor`) | Browser/Client (render) | Redaction/participant logic lives in the domain (CLAUDE.md anti-pattern); client only renders |
| Settings UI + disclosure UI | Browser/Client (SwiftUI) | — | Pure functions of `AppModel` state |
| Mock parity | Browser/Client (`LocalBackend`) | — | Standing convention: mock mirrors server semantics |

## Standard Stack

No new libraries. This phase uses only what is already in the repo.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Go stdlib `net/http`, `encoding/json` | Go 1.26.0 toolchain (go.mod `go 1.25.0`) | Handlers, lenient JSON decode | Project convention (stdlib-first) |
| `github.com/redis/go-redis/v9` | v9.20.1 | `LRem` for the atomic claim | Already the Redis client [VERIFIED: server/go.mod; `LRem` at go-redis@v9.20.1/list_commands.go:218] |
| `github.com/alicebob/miniredis/v2` | v2.38.0 | Test Redis; supports `LREM`, `WATCH` | [VERIFIED: miniredis@v2.38.0/cmd_list.go:33 `Register("LREM"`, cmd_transactions.go registers WATCH] |
| `strangewords/internal/poet` | in-repo | Deterministic line generation | Locked decision 5 |
| SwiftUI / Observation / Swift Testing | Xcode 27.1, iOS 17.0 target | UI + tests | Project convention; no third-party deps |

### Supporting
| Item | Purpose | When to Use |
|------|---------|-------------|
| `sessions.CleanLine` | Defence-in-depth validation of every bot line before append | Always (poet tests already assert CleanLine-identical output, `poet_test.go:13`) |
| `Server.now func() time.Time` | Injected clock for window/think tests | All fallback tests (set before `httptest.NewServer`) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| (c′) server-side poll-driven bot | (a) bot process polls a "lonely waiters" endpoint | Needs a deployed always-on worker (new Fly process group), a new authenticated endpoint that enumerates queue state, and the fallback silently dies when the worker is down |
| (c′) | (b) bot enters a separate marked queue; matchmaker pairs it with old opted-in waiters | Still needs a deployed bot process; still needs a way for the matchmaker to reach into a second queue by age; two queues must be drained/claimed consistently |
| (c′) | (c″) in-process goroutine per bot session | Lost on Fly restart/auto-stop mid-poem, leaving the human stuck; needs shutdown handling |
| Lazy replay of `poet.New(seed)` | Persist poet state in Redis | Extra key/blob to erase at teardown; unnecessary because replay is deterministic |
| `Bool?` on Swift `SessionView` | Non-optional `Bool` + custom decode in an extension | Optional leaks into every call site; the extension approach was compile-verified (see Code Examples) |

**Installation:** none. (`go.mod` / Swift package graph unchanged.)

**Version verification:** Go toolchain `go version go1.26.0 darwin/arm64`; `go test ./...` was run this session and is green on all packages [VERIFIED: command output].

## Package Legitimacy Audit

No external packages are installed or added by this phase. Package Legitimacy Gate: not applicable.

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
 iOS app                                   Go server (single Fly machine, state in Redis)
 -------                                   ------------------------------------------------
 Threshold ──(gear)──> Settings sheet
    │  allowBot (UserDefaults "pref.allowBot", read at begin())
    ▼
 POST /v1/enter {allowBot}  ───────────►  handleEnter
                                            │ decode leniently: absent/non-bool => false
                                            ▼
                                          Matchmaker.Enter(allowBot)
                                            │ PopWaiter (LPOP queue)  ── waiter found ──► pair(human, human)  [unchanged]
                                            │ none ─► enqueue WaitEntry{AllowBot}  (RPUSH + SET sw:wait:<id> TTL 15m)
                                            ▼
 GET /v1/waiting (every 3 s) ────────────► handleWaiting
                                            │ ref.Kind==wait, entry unmatched?
                                            │   AllowBot && BotWindow>0 && now-EnqueuedAt >= BotWindow ?
                                            │      yes ► Store.ClaimWaiter: LREM queue 1 <waitId>
                                            │              n==1 ► PairWithBot: save session{[human, bot(Bot=true,Dismissed=true)]},
                                            │                      SetRef(token→session), DelWait, arm BotReadyAt
                                            │              n==0 ► a human popped us; reply "waiting" (next poll = matched)
                                            ▼
                         matched view  {…, partnerIsBot:true}
 compose/reveal show persistent
 "robot poet" caption      ◄─────────────  GET /v1/session/{id} (every 3 s while bot's turn)
                                            │ settleBot: bot's turn && now >= BotReadyAt
                                            │   ► line = botplayer replay(poet.New(seed(sessionId)))  → CleanLine → append
                                            │   ► complete? status=complete, RevealTTL
 POST /v1/session/{id}/line ─────────────► handleLine: human line applied; if next author is bot → BotReadyAt = now+think
 POST …/dismiss ─────────────────────────► bot participant pre-Dismissed ⇒ human dismiss ⇒ dissolve ⇒ DeleteSession (zero keys)
```

### Recommended Project Structure
```
server/
├── internal/
│   ├── botplayer/            # NEW: Seed(sessionID), NextLine(view-ish inputs) — pure, no HTTP, no Redis
│   ├── config/config.go      # + BotWindow, BotThink  (SW_BOT_WAIT_SECONDS, SW_BOT_THINK_MS) [TUNABLE]
│   ├── sessions/session.go   # + Participant.Bot, Session.BotReadyAt, View.PartnerIsBot, helpers
│   ├── store/store.go        # + WaitEntry.AllowBot, Store.ClaimWaiter
│   ├── matchmaker/matchmaker.go  # Enter(... allowBot ...), PairWithBot
│   ├── metrics/metrics.go    # + BotPaired counter
│   └── gateway/gateway.go    # enterRequest.AllowBot, handleWaiting fallback, settleBot, handleLine arm
ios/Strangewords/
├── App/SettingsStore.swift   # NEW: struct SettingsStore { allowBot }  (sibling of TokenStore)
├── App/AppModel.swift        # + settings seam, allowBot property, begin() passes it
├── Net/{Backend,APIClient,LocalBackend,Models}.swift   # contract mirror
├── Features/Settings/SettingsView.swift   # NEW: the sheet
├── Features/Threshold/ThresholdView.swift # + gear + .sheet
└── Features/Compose/PartnerPresence.swift # NEW: caption view + pure copy function (used by Compose + Reveal)
```

### Pattern 1: Atomic claim of your own queue slot
**What:** The waiter removes *its own* id from the bucket queue with `LREM key 1 id`. Redis executes `LREM` and an arriver's `LPOP` serially; whichever runs first owns the waiter. `LREM` returning 1 means "I took myself out before anyone popped me"; 0 means a human already popped me.
**When to use:** The only place the bot path begins (`handleWaiting`, unmatched entry, opted-in, past window).
**Example:**
```go
// store.go — new. Keeps all Redis key knowledge in the store layer (CLAUDE.md anti-pattern: no state outside store).
// ClaimWaiter removes a waiting id from its bucket queue. It reports true only if this
// call took the id off the queue — i.e. nobody popped it first.
func (s *Store) ClaimWaiter(ctx context.Context, bucket, id string) (bool, error) {
	n, err := s.rdb.LRem(ctx, queueKey(bucket), 1, id).Result()
	return n == 1, err
}
```
Source: `LRem(ctx, key, count int64, value interface{}) *IntCmd` [VERIFIED: go-redis@v9.20.1/list_commands.go:218]. Atomicity of single Redis commands is standard Redis semantics [ASSUMED: redis.io docs not fetched this session; matches how `PopWaiter`'s `LPOP` is already relied on in `store.go:127-145`].

### Pattern 2: Lazy, deterministic bot turn (replay)
**What:** On each qualifying request, rebuild `poet.New(Seed(sessionID))`, replay a `Line` call for every earlier bot-authored line index (discard result, only to advance RNG/`used`/`mine` state), then produce the next line. Run it through `sessions.CleanLine`. Append and advance exactly one turn.
**Why it works:** Verified probe (transient test, removed): for seeds 1–500, a fresh poet replaying line 0 then generating line 2 over `[l0, humanLine]` equals the continuous poet's line 2. The poet uses only the seeded `rand.PCG`; its map ranges did not perturb output in the probe.
**Idempotency without CAS:** The human cannot submit while it is the bot's turn (`handleLine` returns 409 `not_your_turn`, `gateway.go:231`), so the only concurrent writer is another poll's `touchPresence` (`gateway.go:409-417`). Two racing polls both compute the identical line (deterministic) and write identical state; a stale `touchPresence` write can drop the bot line, but the next poll re-derives it. This is self-healing; do **not** add Redis locks (a lock key would violate the zero-`sw:*`-keys invariant unless explicitly deleted at teardown).
**Single step, not a loop:** apply at most one bot line per settle call (a loop could double-play if a future policy gives the bot consecutive turns).

### Pattern 3: Bot as a flagged participant, not a queue member
`sessions.Participant` gains `Bot bool \`json:"bot,omitempty"\``. The bot participant is created with `Dismissed: true` so `handleDismiss`'s "all dismissed → dissolve" (`gateway.go:301-312`) fires on the human's single dismiss. Its `PushToken` is empty; `maybePush` should early-return for `p.Bot` so no push is attempted for it.

### Anti-Patterns to Avoid
- **Bot enters the shared queue (dev `cmd/bot` behavior):** any non-opted-in arriver could `LPOP` it — that is exactly the segregation violation CONTEXT forbids. Production bot must never be a queue member.
- **Client decides to "ask for a bot":** the window and the claim are server-owned; the client's only input is the opt-in bit at `enter`.
- **Bot logic inside handlers:** put pairing in `matchmaker`, line generation in `botplayer`, turn/redaction logic in `sessions` (CLAUDE.md: "Putting redaction or participant logic in handlers" is a listed anti-pattern). Handlers only orchestrate.
- **New Redis keys for bot state** (locks, schedulers, sorted sets): every one must be erased at teardown; the design needs none.
- **`partnerIsBot` computed or accepted from the client:** always derived from `Participant.Bot` server-side.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Line generation | A second generator / templates for the bot | `server/internal/poet` via a thin `botplayer` wrapper | Locked decision 5; poet already CleanLine-safe and syllable-targeted |
| Atomic human-vs-bot claim | Distributed lock / SETNX key / Lua | `LREM` on the queue (single atomic command) | No new key to tear down; same primitive as `LPOP` matchmaking |
| Bot worker / scheduler | Goroutine ticker, cron, separate Fly process | Poll-driven lazy settle | Survives restart and `auto_stop_machines`; zero topology change |
| Time in tests | `time.Sleep` for the 25 s window | `Server.now` injection (+ `mr.FastForward` only if testing Redis TTLs) | Existing convention; `Matchmaker.Enter` already takes `now` |
| Settings persistence | Custom file/Keychain store | `UserDefaults` via a `SettingsStore` struct mirroring `TokenStore` | Locked decision 2; CA92.1 already declared in `PrivacyInfo.xcprivacy` |
| Sheet chrome | Custom modal overlay | `.sheet(isPresented:)` + `.presentationDetents` | Compile-verified at iOS 17.0 target |

**Key insight:** Every moving part this phase needs (atomic ownership, time injection, deterministic generation, TTL-bounded state, mock parity seam) already exists. The risk is not missing machinery; it is adding a *new kind* of moving part (worker, lock, second queue) that the anonymity/TTL invariants then have to cover.

## Runtime State Inventory

Not a rename/refactor phase. Omitted (greenfield feature on existing state). Compatibility note instead: sessions and wait entries already in Redis at deploy time lack the new fields; all new fields are `omitempty`/zero-default (`Bot=false`, `AllowBot=false`, `BotReadyAt=0`), so no data migration is needed [VERIFIED: `Participant`/`Session`/`WaitEntry` are plain JSON structs, session.go:17-44, store.go:47-54].

## Detailed Findings by Research Question

### Q1. The fallback mechanic — options weighed

| Criterion | (a) bot polls "lonely waiters" endpoint | (b) bot in separate marked queue | (c′) server-side, poll-driven (RECOMMENDED) |
|-----------|-----------------------------------------|----------------------------------|----------------------------------------------|
| Needs a deployed bot process? | Yes. `fly.toml` has only `[http_service]`; `cmd/bot` is a dev tool (`run_test_server_and_robot_poet_friend.sh`, `live_test.sh`) | Yes | **No** |
| Bot down ⇒ | Waiters wait forever (acceptable per brief, but feature silently dead) | same | n/a — cannot be "down" |
| New API surface | Yes: authenticated enumeration of queue state (info leak / authz surface) | Possibly | **None** |
| Human-vs-bot race | Needs a claim op anyway (bot "claims" a waiter by id ⇒ same `LREM`) | Matchmaker must pop from two queues by age | **`LREM` vs `LPOP`**, one atomic winner |
| Segregation ("bot only with opted-in") | By endpoint filter | By queue | **Structural** — bot is created from the opted-in waiter's own request |
| Zero-keys invariant | Bot is an ordinary client; fine | Extra queue key | **No new keys** (wait entry explicitly deleted on claim) |
| Matches `privacy.html` | Bot is "our software", but runs where? | same | **Yes** — page already says lines come from "software running on our own server" (privacy.html "The robot poet") |
| Restart/auto-stop safety | Worker lifecycle | Worker lifecycle | **All state in Redis** |
| Weakness | — | — | Bot lines only advance while the human polls (no background progress). Acceptable now (push is stubbed `push.Noop`); revisit when APNs lands (see Pitfall 7) |

**Recommended mechanics (decision):**
1. `enterRequest` gets `AllowBot bool \`json:"allowBot"\`` (top-level, per CONTEXT: "allowBot on POST /v1/enter"). `Matchmaker.Enter` takes it and stores it on the `WaitEntry` **only when the arriver enqueues**; if the arriver pairs with an existing waiter, the flag is irrelevant (human-human, unchanged path at `matchmaker.go:31-44`).
2. `handleWaiting`: in the `ref.Kind == store.KindWait` branch, after `GetWait` and the `MatchedSessionID == ""` check (`gateway.go:164-167`), if `wfe.AllowBot && s.cfg.BotWindow > 0 && s.now().UnixMilli()-wfe.EnqueuedAt >= BotWindow.Milliseconds()`, call `mm.PairWithBot`. On `claimed=false`, fall through to the existing "waiting" reply (do **not** error); the next poll finds the human match.
3. `PairWithBot` mirrors `pair()` (`matchmaker.go:65-98`): participant 0 = the human (waiter), participant 1 = bot (`Bot: true, Dismissed: true`), random `StartIndex`, `SetRef(token → session, idx 0, SessionTTL)`, **`DelWait(waiter.ID)`**, `BotReadyAt = now + BotThink`. Deleting the wait entry means the bot path does not reproduce the known `WaitEntry` leak (STATE.md Blockers: `Store.DeleteSession` does not remove `sw:wait:*`).
4. Increment a new `metrics.BotPaired` counter. Do not increment `metrics.Matched` (it means "paired immediately at enter", `metrics.go` help text).

**Window value:** default `25 * time.Second`, `[TUNABLE]`, via `config.Load()` (`SW_BOT_WAIT_SECONDS`, parsed with `envFloat` and converted). `<= 0` disables the bot entirely (mirrors the `SW_RATE_RPS=0` convention and gives ops a kill switch). With a 3 s client poll the bot actually lands between 25 s and 28 s [ASSUMED: derives from `AppModel.defaultPollInterval = .seconds(3)`, verified AppModel.swift:49]. Think time: `BotThink` default ~2.5 s `[TUNABLE]` (cmd/bot uses 1500 ms + up to 1800 ms jitter, `cmd/bot/main.go:25-30`); the lazy design adds up to one poll interval on top.

### Q2. Wire contract

- **Where enter is handled:** `Server.handleEnter` (`gateway.go:110-134`). The body is decoded with `_ = json.NewDecoder(r.Body).Decode(&req) // tolerate empty body`. Consequences [VERIFIED: gateway.go:96-113]:
  - Absent field ⇒ Go zero value ⇒ `false` ✓ (shipped build 0.1.0 and `{}` bodies).
  - Unknown fields are ignored by default ⇒ old servers ignore `allowBot` from new apps ✓ (deploy server first; CI deploys on `server/**` push).
  - A wrongly-typed value (e.g. `"allowBot":"true"`) makes `Decode` return an error that is discarded; `encoding/json` still populates the other fields and leaves the failed field at its zero value ⇒ `false` ✓ — fail-closed, which is the correct direction for strict opt-in. Pin with a test.
- **Idempotency:** `IdemGet/IdemSet` are used **only** by `handleLine` (`gateway.go:214-221, 270-280`); `enter` has no idempotency, so `allowBot` interacts with none of it. `enterResponse` needs no change (`participantToken, state, session, waitId`).
- **Where the flag lives server-side:** `store.WaitEntry` (json `allowBot,omitempty`) — TTL `WaitTTL` 15 min, erased by `DelWait` on the bot path, otherwise expires. It is not copied onto `Session` (the session records only the *outcome*, `Participant.Bot`). The flag is a single bit tied to a random wait id; it is not an identifier.
- **Disclosure on the view (`Session.ViewFor`, session.go:92-111):** the `View` struct has no participant-kind info today; `Participant` has `Token, PushToken, LastSeen, Dismissed`. Add `Participant.Bot` and `View.PartnerIsBot bool \`json:"partnerIsBot,omitempty"\`` computed as "any participant other than `you` has `Bot`". Rationale: speaks about *the caller's partner*, leaks nothing else (no indices of bots, no tokens), N-participant safe. (Alternative `bots []int` indices was considered and rejected as over-built for v1; planner may revisit — discretion.)
- **Decoding on iOS must tolerate absence** because `omitempty` omits `false`. Plain synthesized `Codable` throws `keyNotFound` for a defaulted `var` — **verified this session** (see Code Examples). Alternatively emit the field always (drop `omitempty`) and still use tolerant decode.
- **Moderation:** `moderation.Report` has `Participants int` only. Optional low-cost addition: `BotPartner bool` so a reported poem is attributable. Not required; flag to the planner as a nicety.

### Q3. iOS

- **Threshold composition:** `ThresholdView` is a `VStack(spacing: 40)` with `Spacer`s, title/tagline, `begin` button (`Button(action: model.begin)` + `.buttonStyle(.ritual)`), inside `RootView.content` with `.padding(.horizontal, 28)`. Dev chips overlay `.topTrailing` at the **root** (`RootView.devControls`, shown only when `Dev.showControls`, i.e. `SW_DEV=1`). A gear placed `.topTrailing` will collide with the chips in dev runs; either place it elsewhere (e.g. `.topLeading` or bottom) or inset it. Final placement is a UI-SPEC concern (config has `ui_phase: true`).
- **Sheet idiom (none exists yet):** `@State private var showSettings = false` in `ThresholdView`; gear `Button` with `.accessibilityLabel("Settings")` and a ≥44 pt hit area; `.sheet(isPresented:)` with `.presentationDetents([.medium])`, `.presentationDragIndicator(.visible)`, `.presentationBackground(...)`. All of these **type-check against `-target arm64-apple-ios17.0-simulator`** [VERIFIED: swiftc typecheck of the snippet in Code Examples, no diagnostics].
- **Environment into the sheet:** the palette/theme come from custom environment keys set in `RootView` (`.environment(\.palette, palette)`, `.environment(\.sceneTheme, theme)`, plus `@Environment(AppModel.self)`). Re-inject `\.palette` (and `.preferredColorScheme`) explicitly on the sheet content rather than trusting inheritance [ASSUMED: sheet environment inheritance incl. colour scheme not exercised in a simulator this session]. Settings view is built to leave room for later rows (a `VStack`/`Form`-free list of rows; this phase ships one).
- **Settings store:** mirror `TokenStore` (`Net/Keychain.swift`): `struct SettingsStore { let defaults: UserDefaults; init(defaults: UserDefaults = .standard); var allowBot: Bool { get/nonmutating set } }`. File it in `App/SettingsStore.swift` (the `Keychain.swift` filename is already misleading; don't extend it). Do **not** call it from `TokenStore.clear()` — the preference must survive dissolutions.
- **AppModel wiring:** add a defaulted seam `settings: SettingsStore = SettingsStore()` to `AppModel.init` (same pattern as `tokenStore`, IOST-05) and an observed property `var allowBot: Bool { didSet { settings.allowBot = allowBot } }` initialised from the store. `@Observable` + `didSet` **compiles and works** [VERIFIED: scratch swiftc probe printed `true true`]. `begin()` passes `allowBot` captured at call time (`AppModel.swift:93-96`). `resume()` needs no change (the server remembers the flag on the wait entry).
- **Backend protocol propagation (blast radius, verified by grep):** `Backend.enter(pushToken:)` is declared in `Backend.swift:11`, implemented in `APIClient.swift:56` and `LocalBackend.swift:71`, called in `AppModel.swift:96`, in `FakeBackend.swift`, and 10 call sites in `LocalBackendTests.swift`. Change the requirement to `enter(pushToken: String?, allowBot: Bool)`, update all mechanically, and record `allowBot` on `FakeBackend.Pending` so tests can assert what `AppModel` sent. Do not add a forwarding convenience overload that hides the parameter.
- **APIClient:** `body["allowBot"] = allowBot` (always send; explicit `false` is fine for old servers).
- **Models.swift mirror:** `SessionView` gets `var partnerIsBot: Bool = false` declared **last**, with a tolerant decoder in an `extension` so the synthesized memberwise init (and its default) survives — the 3 `SessionView(` construction sites in tests (`TestSupport.haikuView`, `SessionViewTests`) compile unchanged [VERIFIED: probe `V(a: 3)` compiled with the custom `init(from:)` in an extension]. The extension must list **all** coding keys, so future field additions must update it.
- **Compose / disclosure placement:** `ComposeView` has no header; its body is `VStack(spacing: 28){ Spacer; lines; Spacer; writingArea|theirTurn; Spacer }`. The existing "their turn" copy is `"the stranger is with the poem now"` / `"it's fine to put this down — you'll be told when there's a line for you"` (`ComposeView.swift` `theirTurn`). Add a small `PartnerPresence` caption at the top of the VStack (visible on **both** your-turn and their-turn, satisfying "visible for the whole session") and also in `RevealView` (still within the session). When `session.partnerIsBot`, change `theirTurn` copy to name the robot poet and drop the "you'll be told" push promise (push is not built and bot lines are poll-driven). Put the copy in a **pure function** (`PartnerPresence.caption(for:) -> String?`) so it is unit-testable without XCUITest (out of scope per REQUIREMENTS).
- **Settings sheet copy must say plainly it's software, not a person** (disclosure ethos). Default OFF; toggle label something like "Write with the robot poet"; helper text: if nobody else is here after a little while, a robot poet (software on our server, not a person) can keep you company.
- **LocalBackend parity:** currently `enter` returns an immediate `matched` (simulated stranger with scripted lines), `waiting` always `matched`. To mirror the new contract: `enter(pushToken:allowBot:)` with `allowBot == false` ⇒ unchanged behaviour (existing tests remain valid, `partnerIsBot == false`); with `allowBot == true` ⇒ return `state: "waiting"`, `waitId` non-nil, record the wait start; `waiting(token:)` returns `waiting` until `botWindow` elapses, then `matched` with `partnerIsBot == true`. Add an init seam `botWindow: TimeInterval = LocalBackend.defaultBotWindow` (`[TUNABLE]`, mirror the server's 25 s; tests pass `0` for immediate, a large value for "still waiting" — no sleeping, same style as `strangerThinkTime`/`enterDelay`). Pin known divergences (scripted lines vs poet, no human-race) as `DRIFT` comments as the Phase 2 suite does.
- **Privacy/policy touchpoints:** `PrivacyInfo.xcprivacy` already declares UserDefaults CA92.1 (no manifest change). The served policy page (`server/internal/gateway/privacy.html`) already has a "The robot poet" paragraph and an "On your device" list that says everything on device is "erased when the poem ends" — a persisted preference is a new on-device item and should be added to that list. `privacy_test.go` pins `datetime="2026-10-26"` / `"october 26, 2026"`; if the page's date is bumped, update both together. (Recommended, not blocking.)

### Q4. Test surfaces

**Go (existing patterns, all verified by reading):**
- Gateway tests are in-package (`package gateway`) black-box over `httptest.NewServer(srv.Routes())` with a `rig{ts, mr, cl}`; `newRig` builds `New(st, mm, push.Noop, moderation.LogSink, log, config.Load())`. It does **not** keep `srv`, so to inject a clock/cfg add `newRigWith(t, func(*config.Config)) (*rig, *fakeClock)` that sets `srv.now = clock.Now` **before** `httptest.NewServer` (avoid data races).
- Time injection: `Server.now func() time.Time` (`gateway.go:31,36`) feeds `Matchmaker.Enter(..., now)` and `touchPresence`. `rateLimiter.now` is also injectable (`middleware_test.go:61-63`). So window and think-time tests need **no sleeping**. Miniredis TTLs do not advance unless `mr.FastForward` is called, so the fake clock alone is enough for window logic.
- Invariant helper `assertNoSessionKeys` checks prefixes `sw:sess:`, `sw:tok:`, `sw:idem:` only (`gateway_test.go:322-329`). For this phase assert the stricter E2E-02 form too: **no key at all with prefix `sw:`** after dissolution on the bot path. (The human-human path is expected to still leave `sw:wait:*`, the known leak owned by Phase 3/4; do not assert that stricter form on the human-human path.)
- `TestMatchRaceSingleSession` (`gateway_test.go:283-320`) is the model for the new human-vs-bot race test.
- `store`, `matchmaker`, `config`, `metrics`, `push`, `moderation` have no test files (verified by `go test` output). Add `store_test.go` for `ClaimWaiter` (miniredis) and cover the matchmaker through gateway tests as today.
- `cmd/bot/main_test.go` covers `composeLine`, `target`, `seedFor`; keep those passing. If `Seed`/`NextLine` move into `internal/botplayer`, have `cmd/bot` delegate and keep its tests (or move them with the code).

**Go tests the fallback needs (all with a fake clock):**
1. Default/absent flag: advance clock 10 min ⇒ poll still `waiting`; no `sw:sess:` key. Same for `"allowBot": "true"` (string) and `false`.
2. Opted-in, `window-1s` ⇒ `waiting`; `window` ⇒ `matched`, `partnerIsBot == true`, `participantCount == 2`, wait entry deleted, `sw:queue:*` empty.
3. Two overlapping opted-in humans: A enters opted-in, B enters opted-in 5 s later ⇒ `matched` human-human; A's later poll (past window) returns that session with `partnerIsBot == false`; exactly one `sw:sess:` key.
4. Race: A is past window; fire A's `GET /v1/waiting` and B's `POST /v1/enter` concurrently, repeated ~50×; assert exactly one session exists and that A's and B's views are consistent (either A↔B human, or A↔bot with B waiting) — never two sessions, never A↔bot while B is also matched to A.
5. Full poem vs. bot: human writes when `yourTurn`, test advances clock beyond `BotReadyAt` + GETs; poem completes; every bot line passes `CleanLine` and is within the form's syllable tolerance; human dismisses once ⇒ session gone ⇒ **zero `sw:*` keys**.
6. Restart safety: build a *second* `Server` over the same miniredis between polls; the bot line still arrives and is identical (determinism).
7. `BotWindow <= 0` disables fallback for an opted-in waiter.
8. Disclosure invariant: for every session produced by `Matchmaker`/`PairWithBot`, `ViewFor(humanToken).PartnerIsBot == (partner.Bot)`; human-human never true. Unit-test in `sessions` plus end-to-end via HTTP.
9. Backward compat JSON: sessions JSON without `bot`/`botReadyAt` decode; `View` JSON omits `partnerIsBot` when false.
10. Metrics: `sw_bot_paired_total` increments on claim and not on human pairing.

**Swift (existing layout, verified):** target `StrangewordsTests` (hosted `bundle.unit-test`, Swift Testing) with `FakeBackend` (gated, records calls; `Pending` carries `id/token/line/text/idemKey` — add `allowBot`), `TestSupport` (`makeIsolatedDefaults`, `makeModel` = the only AppModel factory, `haikuView`, `finish`), `HostIsolationTests`, `SeamDefaultsTests`, `LocalBackendTests`. Headless runner: `scripts/test-ios.sh` (verdict from xcresult only; pinned simulator `iPhone 17`; exit 0 only for Passed/0 failed/>0 tests).
New Swift tests:
- `SessionView` decode: JSON without `partnerIsBot` ⇒ `false`; with `true` ⇒ `true`; memberwise default still `false`.
- `SettingsStore`: default `false`; round-trip; isolated across suites; `TokenStore.clear()` leaves it; key string pinned.
- `AppModel`: `begin()` passes `allowBot == false` by default and `true` after `model.allowBot = true`; the toggle persists through the injected store; `allowBot` survives `reset()`/`dissolve`; composing a bot session retains `partnerIsBot`.
- `LocalBackend`: `allowBot=false` ⇒ immediate match, `partnerIsBot == false`; `allowBot=true` with `botWindow: 0` ⇒ `enter` waiting then `waiting` matched with `partnerIsBot == true`; with a large window ⇒ still `waiting`.
- Pure caption function: `nil` for human partner, named robot-poet text for bot partner.
- `makeModel` extended to inject a `SettingsStore(defaults:)` over the same suite (never `.standard`).
- No UI/XCUITest for the gear/sheet (out of scope per REQUIREMENTS.md); the visual placement is covered by the deferred manual UAT / UI-SPEC.

### Q5. Pitfalls — see Common Pitfalls below.

## Common Pitfalls

### Pitfall 1: Human arrives while the bot claim is in flight
**What goes wrong:** Two sessions for one waiter (human-human and human-bot), or a waiter bound to a bot while a human also thinks it matched.
**Why it happens:** Read-then-act on the queue instead of one atomic command.
**How to avoid:** Claim with `LREM` and treat `n == 0` as "someone else owns me" — reply `waiting`, never error. Note `pair()` overwrites the waiter's token ref with a session ref *before* setting `MatchedSessionID` (`matchmaker.go:87-96`), so a poll in that window sees a session ref and proceeds down the matched path; both orders resolve correctly on the next poll.
**Warning signs:** `sw:sess:*` key count > 1 in the race test; a waiter whose `waiting` poll flips between `matched` sessions.

### Pitfall 2: Stale queue ids and duplicate claims
**What goes wrong:** `PopWaiter` already skips ids whose wait record expired (`store.go:136-139`). A stale id left in the list could be claimed.
**How to avoid:** `handleWaiting` only claims after `GetWait` succeeded for that same id; `LREM` only that id; count 1.

### Pitfall 3: The bot "going down" is a non-event only if nothing else depends on it
**What goes wrong:** If any implementation uses a worker, waiters hang.
**How to avoid:** The recommended design has no worker. Test #6 (second `Server` instance mid-poem) proves restart safety.

### Pitfall 4: Mock/real parity drift in LocalBackend
**What goes wrong:** Mock keeps matching instantly for opted-in users, so the waiting→bot arc is never exercised in `./run.sh` or in Swift tests.
**How to avoid:** Implement the opted-in wait-then-bot arc (Q3) with a zero-delay seam; keep human-simulated instant match as the `allowBot=false` default so the existing 02 suite stays valid; document unavoidable divergences as `DRIFT`.

### Pitfall 5: `HostIsolationTests.standardDefaultsHoldNoSessionKeys` and the settings key
**What goes wrong:** That guard fails if any key with prefix `sw.` exists in `UserDefaults.standard` (`HostIsolationTests.swift`, `hasPrefix("sw.")`). The test simulator and app container are shared with `run.sh`/dev sessions (test-ios.sh header: it acts on the `app.strangewords` container of the test simulator), so a persisted `sw.allowBot=true` from a dev session would make the identity guard fail spuriously.
**How to avoid:** Name the key outside the `sw.` namespace (e.g. `"pref.allowBot"`) and pin it in `SeamDefaultsTests` like the token keys. Do **not** loosen the guard (FIX-01: no silently weakened assertions). Note for the v2 DRFT-03 ("UserDefaults holds only the token…") that this key is a deliberate, documented non-identity exception.

### Pitfall 6: `FakeBackend`/protocol break
**What goes wrong:** Changing `Backend.enter` breaks `FakeBackend` conformance and 10+ test call sites at once.
**How to avoid:** Do the protocol change, `APIClient`, `LocalBackend`, `AppModel`, `FakeBackend`, and test call sites in **one plan/commit** so the tree always builds; `FakeBackend.Pending` records `allowBot`.

### Pitfall 7: Lazy bot only advances while the human polls
**What goes wrong:** If the human backgrounds the app, the bot's line is not written until they return (then it arrives after ≤ think-time + one poll). When APNs lands (`push.Noop` today), a "your turn" push for bot lines will never fire because nothing runs server-side while the app is away.
**How to avoid / scope note:** Acceptable for this phase (push is out of scope). Record it as a forward constraint; the lazy `settleBot` can later also be invoked from a server-side timer without changing the data model. Also ensure `maybePush` skips `p.Bot` participants.

### Pitfall 8: Disclosure integrity
**What goes wrong:** A human-human session ever shows the robot caption, or a bot session ever omits it (e.g., new view build path forgetting `PartnerIsBot`).
**How to avoid:** Compute only in `ViewFor` (single choke point; `handleLine`, `handleDismiss`, `handleGetSession`, `handleWaiting`, and `enter` all go through it). Test end-to-end on all five routes. The dev `cmd/bot` still enters the shared queue undisclosed — this is a dev-only tool and out of scope; note it so nobody runs it against production.

### Pitfall 9: Bot line safety
**What goes wrong:** The poet echoes human words into its lines (`echo.go`). A bot line could, in principle, fail the screener.
**How to avoid:** Pass every bot line through `sessions.CleanLine`; on error use a fixed safe fallback line (never submit unchecked text). Add a seed-sweep test with adversarial-but-accepted human lines. Poet generation quality itself is out of scope.

### Pitfall 10: Sheet / theme rendering
**What goes wrong:** Sheet content renders with the wrong palette or colour scheme.
**How to avoid:** Re-inject `\.palette`/`.preferredColorScheme` on the sheet content. Cannot be proven by the automated suite (UI automation is out of scope); flag for UI-SPEC / deferred manual UAT.

## Code Examples

### Tolerant `SessionView` decode that keeps the memberwise init
```swift
// Verified in a scratch swiftc build (Apple Swift 6.4): V(a: 1) and V(a: 3) compile; missing key => false;
// plain synthesized Codable with a defaulted var throws keyNotFound instead.
struct SessionView: Codable, Equatable {
    // ... existing lets ...
    var partnerIsBot: Bool = false      // LAST, so the memberwise init gets a default
}
extension SessionView {
    enum CodingKeys: String, CodingKey {
        case sessionId, you, participantCount, status, form, currentLine, currentAuthor, yourTurn, lines, partnerIsBot
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        // ... decode the rest ...
        partnerIsBot = try c.decodeIfPresent(Bool.self, forKey: .partnerIsBot) ?? false
    }
}
```
(Key names are the existing wire keys from `Models.swift` — `sessionId, you, participantCount, status, form, currentLine, currentAuthor, yourTurn, lines` [VERIFIED: Net/Models.swift:6-14] — plus the new `partnerIsBot`.)

### Observable setting that writes through
```swift
// Verified: @Observable + didSet compiles and runs (printed "true true").
@MainActor @Observable final class AppModel {
    var allowBot: Bool { didSet { settings.allowBot = allowBot } }
    @ObservationIgnored private let settings: SettingsStore
    init(backend: (any Backend)? = nil, tokenStore: TokenStore = TokenStore(),
         settings: SettingsStore = SettingsStore(),
         pollInterval: Duration = AppModel.defaultPollInterval) {
        self.settings = settings
        self.allowBot = settings.allowBot
        // ... existing ...
    }
}
```

### Gear + sheet (iOS 17.0 type-checks)
```swift
// swiftc -typecheck -target arm64-apple-ios17.0-simulator  => no diagnostics
.overlay(alignment: .topTrailing) {
    Button { showSettings = true } label: {
        Image(systemName: "gearshape").frame(width: 44, height: 44)
    }
    .accessibilityLabel("Settings")
}
.sheet(isPresented: $showSettings) {
    SettingsView()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
}
```

### Server: fallback inside `handleWaiting` (shape, not final code)
```go
// after GetWait(...) and the MatchedSessionID == "" check:
if wfe.AllowBot && s.cfg.BotWindow > 0 &&
	s.now().UnixMilli()-wfe.EnqueuedAt >= s.cfg.BotWindow.Milliseconds() {
	sess, claimed, err := s.mm.PairWithBot(r.Context(), wfe, formID, s.cfg.BotThink, s.now())
	if err != nil { s.fail(w, err); return }
	if claimed {
		metrics.BotPaired.Inc()
		v := sess.ViewFor(token)
		writeJSON(w, http.StatusOK, map[string]any{"state": "matched", "session": v})
		return
	}
	// lost the race to a human: fall through to "waiting"; next poll returns the human match
}
```
`formID` is `wfe.Bucket` in v1 (`handleEnter` sets `bucket := formID`, gateway.go:116) — use `sessions.LookupForm(wfe.Bucket).ID` rather than hard-coding.

### Fake-clock rig (test)
```go
type fakeClock struct{ mu sync.Mutex; t time.Time }
func (c *fakeClock) Now() time.Time          { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *fakeClock) Advance(d time.Duration) { c.mu.Lock(); c.t = c.t.Add(d); c.mu.Unlock() }
// newRigWith: build srv := New(...cfg...); srv.now = clock.Now; THEN httptest.NewServer(srv.Routes())
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Dev `cmd/bot` as an ordinary queued client | Server-side flagged bot participant, opt-in only | This phase | The only production bot path; dev bot stays a test tool |
| Poet used by a long-lived process (`poet.New` once) | Stateless per-request replay | This phase | Restart-safe; verified deterministic |

**Deprecated/outdated:** none relevant. (Existing `LocalBackend` "stranger" is a scripted human stand-in; it stays the `allowBot=false` default.)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Single Redis commands (`LREM`, `LPOP`) are mutually atomic, so exactly one wins the waiter | Pattern 1 / Q1 | High if false — but this is the same primitive `PopWaiter` already depends on; confirm against redis.io when writing the store test |
| A2 | Sheet content inherits custom `\.palette` environment and colour scheme from the presenting view | Q3, Pitfall 10 | Low — mitigated by explicit re-injection; visual defect only |
| A3 | Bot lands 25–28 s after enqueue given a 3 s poll interval | Q1 | Low — tunable |
| A4 | `BotWindow = 25 s` and `BotThink ≈ 2.5 s` are acceptable values within the user's "~20–30 s" | Q1 | Low — `[TUNABLE]`; user confirmation optional |
| A5 | `partnerIsBot` (single bool, omitempty) is the preferred disclosure shape vs. an index list | Q2 | Low — discretion item; a wire rename later is cheap pre-launch but the 0.1.0 build ignores unknown keys either way |
| A6 | Fly may run more than one machine in future; lazy design is safe because all state is in Redis | Q1 | Low — design uses no in-process state |
| A7 | Poet map iteration never perturbs output beyond what the 500-seed probe covered | Pattern 2 | Medium — a probe, not a proof; add a permanent replay-determinism test (seeds 1–500, varied human lines) so regressions in `poet` are caught |

## Open Questions

1. **Gear placement vs. dev chips.**
   - Known: dev chips occupy `.topTrailing` of the root when `SW_DEV=1`.
   - Unclear: exact position/size ("quiet").
   - Recommendation: leave to UI-SPEC (`ui_phase: true`); default to a position that doesn't collide (e.g., `.topLeading` or bottom) and keep ≥44 pt hit target.
2. **Should the served privacy page be updated in this phase?**
   - Recommendation: yes, minimally (add the persisted preference to "On your device"); bump the pinned date in `privacy_test.go` together with the page. Not blocking for the code.
3. **Should the dev `cmd/bot` be marked as a bot for disclosure?**
   - Recommendation: out of scope; document "dev only, never run against production".
4. **Roadmap lists Phase 5 as depending on Phase 4**, which is not executed. Nothing in this design depends on Phase 3/4 artifacts except the (known, tracked) `WaitEntry` leak on the *human-human* path; the bot path deletes its wait entry itself.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Go toolchain | Go build/tests | ✓ | go1.26.0 darwin/arm64 | — |
| miniredis (module) | Go tests | ✓ | v2.38.0 (in module cache) | — |
| xcodegen | project generation | ✓ | /opt/homebrew/bin/xcodegen | — |
| xcodebuild | iOS tests | ✓ | Xcode 27.1 (27A9275) | — |
| iPhone 17 simulator (pinned by `scripts/test-ios.sh`) | iOS tests | ✓ | listed available, shutdown | `SW_SIM_NAME` override |
| jq | `test-ios.sh` verdict | ✓ | /usr/bin/jq | — |
| docker / redis-cli | live scripts only | docker ✓, redis-cli ✗ | — | Not needed: all new tests use miniredis |

**Missing dependencies with no fallback:** none.
**Note:** no iOS 17.x simulator runtime is installed (STATE.md Blockers, Phase 4 carry-over); new iOS APIs used here were instead typechecked against an `ios17.0` target triple.

## Security Domain

`security_enforcement: true`, `security_asvs_level: 1` (config). Nyquist validation is `false` in config, so no Validation Architecture section is included; test surfaces are covered under Q4.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no (no new auth; existing bearer token unchanged) | — |
| V3 Session Management | no change | token/session TTLs unchanged |
| V4 Access Control | yes | Bot session is reachable only via the human's bearer token; **no new endpoints** (option (a)'s queue-enumeration endpoint would have created an authz surface) |
| V5 Input Validation | yes | `allowBot` decoded as strict `bool`, fail-closed on wrong type/absent; bot lines pass `sessions.CleanLine` |
| V6 Cryptography | no | — (token generation unchanged, `crypto/rand`) |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Client forces a bot on someone else / bot leaks into non-opted-in pairings | Tampering / Elevation | Flag stored per participant's own wait entry; bot never a queue member; test #1/#3 |
| Undisclosed bot (client-supplied or forgotten disclosure) | Spoofing / Repudiation | `partnerIsBot` derived server-side from `Participant.Bot` only; end-to-end invariant tests |
| Flag becomes an identifier / outlives encounter | Information disclosure | One bit on a TTL-bound random-id record, deleted on claim; session records only the outcome; no new Redis keys |
| Bot-path request flooding (cheap session creation) | Denial of service | Existing per-IP rate limiter covers `/v1/enter` and `/v1/waiting`; `BotWindow <= 0` kill switch |
| Bot emits screener-failing text | Tampering / Content | `CleanLine` on every bot line; safe fallback line |
| Over-long/odd JSON body | DoS | Existing `limitBody` 16 KiB cap unchanged |

## Project Constraints (from ./.claude/CLAUDE.md)

- Go stdlib-first backend, SwiftUI iOS 17+, **no third-party iOS dependencies**.
- `.xcodeproj` is gitignored; `ios/project.yml` (XcodeGen) is the source of truth — no project change is needed for this phase (new Swift files under `Strangewords/` are picked up by the existing `sources: - Strangewords` entry; new tests under `StrangewordsTests/`).
- Anonymity model: tests/implementation must not persist identity or poem content beyond the encounter.
- Automated-only verification for this milestone (no human-driven simulator).
- New settings go through `server/internal/config/config.go` with a default (`env`/`envFloat` helpers); never `os.Getenv` in feature packages. Tunables carry `[TUNABLE]`.
- Errors: `errors.Is`, `writeErr(w, status, code, msg)`, never leak `err.Error()`; non-fatal side-effect failures logged, not fatal.
- Handlers are `func (s *Server) handleX(...)`; dependencies injected; time injected as `now func() time.Time`.
- `Backend` changes must be made in the protocol and **both** implementations (`APIClient`, `LocalBackend`); mock and real paths must stay in sync.
- Feature views are pure functions of `AppModel.phase`; new state belongs on `AppModel`, not in views.
- Preserve design-doc citations (`plan.v1.md §…`) when editing the related logic; `gofmt -l server/` must be empty.
- Use the GSD workflow for file changes (the executor handles this; research only writes RESEARCH.md).
- No project skills found under `.claude/skills/` or `.agents/skills/`.

## Sources

### Primary (HIGH confidence) — read this session
- `server/internal/matchmaker/matchmaker.go`, `server/internal/store/store.go`, `server/internal/sessions/session.go`, `server/internal/gateway/gateway.go`, `server/internal/gateway/gateway_test.go`, `server/internal/config/config.go`, `server/cmd/bot/main.go`, `server/cmd/server/main.go`, `server/fly.toml`, `server/internal/push/push.go`, `server/internal/metrics/metrics.go`
- `ios/Strangewords/Net/{Backend,APIClient,LocalBackend,Models,Keychain}.swift`, `App/{AppModel,RootView}.swift`, `Features/{Threshold,Compose,Reveal,Waiting}/*.swift`, `ios/project.yml`, `ios/Strangewords/PrivacyInfo.xcprivacy`
- `ios/StrangewordsTests/{FakeBackend,TestSupport,SessionViewTests,AppModelTests,HostIsolationTests,SeamDefaultsTests,LocalBackendTests}.swift`, `scripts/test-ios.sh`
- `server/internal/gateway/privacy.html`, `privacy_test.go`; `.planning/{STATE,REQUIREMENTS,config.json}`, `05-CONTEXT.md`
- go-redis v9.20.1 and miniredis v2.38.0 sources in the Go module cache (`LRem`, `Watch`, `Register("LREM"`/WATCH)
- Executed probes: `go test ./...` (green); transient Go replay-determinism test, seeds 1–500 (passed, file removed, working tree unchanged); swiftc probes for tolerant Codable, `@Observable` + `didSet`, and the sheet/gear snippet against `arm64-apple-ios17.0-simulator`

### Secondary (MEDIUM confidence)
- None.

### Tertiary (LOW confidence)
- Redis single-command atomicity and sheet environment inheritance are `[ASSUMED]` (A1, A2); no web lookups were needed for this in-repo phase.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all APIs verified in module source or by typecheck
- Architecture (mechanism choice): HIGH — driven by verified repo facts (single Fly `http_service`, dev-only bot binary, `LPOP` matchmaking, zero-keys invariant, privacy.html wording)
- Pitfalls: HIGH for server/test-harness ones (read from code); MEDIUM for sheet rendering (A2)

**Research date:** 2026-10-26
**Valid until:** 2026-11-25 (stable in-repo domain; re-check if Phases 3/4 change `store.DeleteSession` or the test harness before execution)
