# Phase 5: Opt-In Robot Poet Collaboration - Pattern Map

**Mapped:** 2026-10-26
**Files analyzed:** 27 (11 Go, 16 Swift incl. tests)
**Analogs found:** 25 / 27 (all analogs verified git-tracked via `git ls-files`)

Design basis: RESEARCH option (c'): server-side, poll-driven bot. `LREM` claim, lazy deterministic poet replay, `Participant.Bot`, `View.PartnerIsBot`. No worker, no new Redis keys.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `server/internal/config/config.go` (mod: `BotWindow`, `BotThink`) | config | n/a | itself, lines 16-18, 34-39 | self |
| `server/internal/sessions/session.go` (mod: `Participant.Bot`, `Session.BotReadyAt`, `View.PartnerIsBot`) | model | transform | itself, lines 17-22, 73-111 | self |
| `server/internal/store/store.go` (mod: `WaitEntry.AllowBot`, `ClaimWaiter`) | store | CRUD / atomic claim | `PopWaiter` lines 124-145 | exact |
| `server/internal/matchmaker/matchmaker.go` (mod: `Enter(allowBot)`, new `PairWithBot`) | service | CRUD | `pair()` lines 63-98, `enqueue()` 46-61 | exact |
| `server/internal/botplayer/botplayer.go` (new: `Seed`, `NextLine`) | utility | transform | `server/cmd/bot/main.go` (`seedFor`, `composeLine`, `target`) + `poet.go` | role-match |
| `server/internal/botplayer/botplayer_test.go` (new) | test | transform | `server/cmd/bot/main_test.go`, `poet_test.go` | role-match |
| `server/internal/metrics/metrics.go` (mod: `BotPaired`) | config | pub-sub (counter) | `Matched` line 26 | exact |
| `server/internal/gateway/gateway.go` (mod: `enterRequest.AllowBot`, `handleWaiting` fallback, `settleBot`, `handleLine`/`maybePush` arming) | controller | request-response | itself, lines 96-182, 202-284, 419-432 | self |
| `server/internal/gateway/gateway_test.go` (mod: `newRigWith`, fake clock, bot tests) | test | request-response | `newRig` lines 31-48, `TestMatchRaceSingleSession` 283-320, `assertNoSessionKeys` 322-329 | exact |
| `server/internal/store/store_test.go` (new: `ClaimWaiter`) | test | CRUD | `newRig` miniredis setup (no store tests exist) | partial |
| `server/internal/sessions/session_test.go` (new/ext: `ViewFor` PartnerIsBot, JSON compat) | test | transform | existing `sessions/*_test.go` (`policy_test.go`, `validate_test.go`) | role-match |
| `ios/Strangewords/App/SettingsStore.swift` (new) | store | CRUD (UserDefaults) | `TokenStore` in `Net/Keychain.swift` lines 16-41 | exact |
| `ios/Strangewords/App/AppModel.swift` (mod: `settings` seam, `allowBot`, `begin()`) | state machine | request-response | itself, lines 51-106 | self |
| `ios/Strangewords/Net/Backend.swift` / `APIClient.swift` / `LocalBackend.swift` / `Models.swift` (mod) | service / model | request-response | themselves | self |
| `ios/Strangewords/Features/Settings/SettingsView.swift` (new) | component | request-response | `ThresholdView.swift` (env + palette + Theme tokens) | role-match |
| `ios/Strangewords/Features/Threshold/ThresholdView.swift` (mod: gear + sheet) | component | event-driven | itself | self |
| `ios/Strangewords/Features/Compose/PartnerPresence.swift` (new) | component + pure fn | transform | `ComposeView.theirTurn` (lines 101-113) | role-match |
| `ios/Strangewords/Features/Compose/ComposeView.swift`, `Reveal/RevealView.swift`, `Waiting/WaitingView.swift` (mod) | component | request-response | themselves | self |
| `ios/StrangewordsTests/FakeBackend.swift`, `TestSupport.swift` (mod) | test double / util | event-driven | themselves | self |
| `ios/StrangewordsTests/SettingsStoreTests.swift` (new) | test | CRUD | `SeamDefaultsTests.swift` (`tokenStoreIsolatesSuites`, key pin) | exact |
| `ios/StrangewordsTests/SessionViewTests.swift`, `AppModelTests.swift`, `LocalBackendTests.swift`, `SeamDefaultsTests.swift` (ext) | test | transform / event-driven | themselves | self |
| `ios/StrangewordsTests/PartnerPresenceTests.swift` (new) | test | transform | `SessionViewTests.swift` / `SyllablesTests.swift` | role-match |
| `server/internal/gateway/privacy.html` + `privacy_test.go` (mod, recommended) | config | n/a | existing page and pinned date | self |

No-analog list is at the bottom.

---

## Pattern Assignments (Go)

### `server/internal/store/store.go` (store, atomic claim)

**Analog:** `PopWaiter`, store.go lines 124-145. Add `WaitEntry.AllowBot` beside `MatchedSessionID` (lines 47-54), `omitempty`.

**Struct field pattern** (lines 47-54):
```go
type WaitEntry struct {
	ID               string `json:"id"`
	Token            string `json:"token"`
	PushToken        string `json:"pushToken,omitempty"`
	Bucket           string `json:"bucket"`
	EnqueuedAt       int64  `json:"enqueuedAt"`
	MatchedSessionID string `json:"matchedSessionId,omitempty"`
	// add: AllowBot bool `json:"allowBot,omitempty"`
}
```

**Core atomic-op pattern to copy** (lines 127-134): single Redis command decides ownership, sentinel `ErrNotFound`, `errors.Is`:
```go
id, err := s.rdb.LPop(ctx, queueKey(bucket)).Result()
if errors.Is(err, redis.Nil) { return nil, ErrNotFound }
if err != nil { return nil, err }
```
`ClaimWaiter(ctx, bucket, id) (bool, error)` is `s.rdb.LRem(ctx, queueKey(bucket), 1, id).Result()` and returns `n == 1`. Key builders stay in this file only (`queueKey`, line 69).

---

### `server/internal/matchmaker/matchmaker.go` (service)

**Analog:** same file. `Enter` signature (line 31) gains `allowBot bool`; pass into `enqueue` which sets `WaitEntry.AllowBot` (lines 46-53). The human-human pair path (lines 32-44) is unchanged, flag ignored.

**`PairWithBot` copies `pair()`** (lines 65-98). Differences: participant 1 is `{Bot: true, Dismissed: true, LastSeen: nowMs}` with no token; only one `SetRef` (waiter, Idx 0, `store.SessionTTL`); call `DelWait` instead of `SaveWait(MatchedSessionID)`; set `BotReadyAt = now + think`; first call `st.ClaimWaiter`, return `(nil, false, nil)` when lost. Session literal to mirror:
```go
sess := &sessions.Session{
	ID: store.NewID(),
	Participants: []sessions.Participant{ /* human idx 0, bot idx 1 */ },
	StartIndex:  rand.IntN(2),
	Bucket:      bucket,
	CreatedAt:   nowMs,
	Status:      sessions.StatusActive,
	FormID:      formID,
	PolicyID:    sessions.DefaultPolicyID,
	Lines:       []string{},
	CurrentLine: 0,
	PoemCount:   1,
}
```
Error wrapping: return raw `err` like the rest of the file; `errors.Is(err, store.ErrNotFound)` for sentinels. Verify `DelWait` exists in store.go (lines 160+, not read here); add it there if missing, mirroring `DelRef` (lines 109-111).

---

### `server/internal/sessions/session.go` (model)

**Participant** (lines 17-22): add `Bot bool \`json:"bot,omitempty"\``. **Session** (lines 27-44): add `BotReadyAt int64 \`json:"botReadyAt,omitempty"\`` in the poem-level block (unix millis, same convention as `CompletedAt`).

**View/ViewFor choke point** (lines 73-111). Add `PartnerIsBot bool \`json:"partnerIsBot,omitempty"\`` and compute in `ViewFor` as "any participant at index != you has Bot". Redaction logic lives here, never in handlers (CLAUDE.md anti-pattern). Unit helpers (e.g. `BotTurn()`/`IsBotTurn`) go next to `CurrentAuthor` (lines 51-53):
```go
func (s *Session) CurrentAuthor() int {
	return s.policy().Author(s.CurrentLine, len(s.Participants), s.StartIndex)
}
```

---

### `server/internal/botplayer/botplayer.go` (utility, transform; NEW package)

**Analog:** `server/cmd/bot/main.go` (`seedFor`, `composeLine`, `target`; imports `strangewords/internal/poet`, `strangewords/internal/sessions`, uses `hash/fnv`). Read it before extracting (only lines 1-80 were read here; helpers sit below). Move or delegate: `cmd/bot` must keep its `main_test.go` passing.

**Replay pattern (RESEARCH Pattern 2):** `p := poet.New(Seed(sessionID))`; for each earlier bot-authored line index call `p.Line(target, previous[:i])` and discard; then `p.Line(target, previous)`; pass the result through `sessions.CleanLine`; on error use a fixed safe fallback line. `poet.Line(target int, previous []string) string` (poet.go lines 46-72). `poet.New(seed uint64)` (lines 30-41).

Package must be pure: no HTTP, no Redis. Imports only `poet`, `sessions`, stdlib. Direction stays `gateway -> botplayer -> poet/sessions`.

---

### `server/internal/config/config.go` (config)

**Analog:** itself. Field block (lines 10-18) and `Load()` (lines 27-45). Add:
```go
BotWindow time.Duration // [TUNABLE] ...; <= 0 disables the bot (kill switch)
BotThink  time.Duration // [TUNABLE]
```
Use the existing helper, never `os.Getenv` (lines 54-61), mirroring the `PresenceWindow` and `RateRPS` styles:
```go
PresenceWindow: 20 * time.Second, // [TUNABLE] plan.v1.md §5
RateRPS:   envFloat("SW_RATE_RPS", 30),
```
So: `BotWindow: time.Duration(envFloat("SW_BOT_WAIT_SECONDS", 25) * float64(time.Second))`, `BotThink` from `SW_BOT_THINK_MS` default 2500. Keep `[TUNABLE]` markers.

---

### `server/internal/metrics/metrics.go`

**Analog:** line 26. Copy the form, and keep `Matched` unchanged:
```go
Matched = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_matched_total", Help: "Enters that paired immediately into a session."})
```
New: `BotPaired` with `Name: "sw_bot_paired_total"`.

---

### `server/internal/gateway/gateway.go` (controller)

**enterRequest** (lines 96-101): add `AllowBot bool \`json:"allowBot"\``. Keep the lenient decode (line 112) exactly as is; a wrong-typed value fails closed to false.
```go
var req enterRequest
_ = json.NewDecoder(r.Body).Decode(&req) // tolerate empty body
...
res, err := s.mm.Enter(r.Context(), token, req.PushToken, bucket, formID, s.now())
```
Add `req.AllowBot` to the `Enter` call (line 118).

**handleWaiting fallback insertion point:** inside `ref.Kind == store.KindWait` after the `MatchedSessionID == ""` check (lines 164-167). Existing shape:
```go
if wfe.MatchedSessionID == "" {
	writeJSON(w, http.StatusOK, map[string]string{"state": "waiting"})
	return
}
```
Insert the bot-window check before that `return` (RESEARCH "Server: fallback inside handleWaiting"), use `s.now()` and `s.cfg.BotWindow`, `sessions.LookupForm(wfe.Bucket).ID`, `metrics.BotPaired.Inc()`, and `s.fail(w, err)` on error. On `claimed == false` fall through to the "waiting" reply.

**settleBot** (new method on `*Server`, called in `handleGetSession` lines 186-194 before `ViewFor`, and in the matched tail of `handleWaiting` lines 174-181): at most one bot line per call, only when `sess.Status == StatusActive`, it is the bot's turn and `s.now() >= BotReadyAt`. Completion branch copies `handleLine` lines 251-258:
```go
if sess.IsComplete() {
	sess.Status = sessions.StatusComplete
	sess.CompletedAt = now.UnixMilli()
	metrics.PoemsCompleted.Inc()
	if err := s.st.SaveSessionTTL(r.Context(), sess, store.RevealTTL); err != nil { ... }
} else { s.st.SaveSession(...) }
```
Count `metrics.LinesSubmitted.Inc()` as at line 249. No locks, no new keys (RESEARCH Pattern 2).

**Arming in handleLine** (lines 259-266, the non-complete branch): after `SaveSession`, if the next author is a bot set `sess.BotReadyAt = now + BotThink` and re-save. The existing `maybePush(..., sess.CurrentAuthor(), push.YourTurn)` call (line 265) must be made harmless for bots:

**maybePush guard** (lines 419-432): add an early return for bots next to the existing bounds check:
```go
if i < 0 || i >= len(sess.Participants) { return }
p := sess.Participants[i]
// add: if p.Bot { return }
```

**Dismiss** (lines 295-317): no code change. The bot participant is created `Dismissed: true`, so the existing all-dismissed loop (lines 301-312) dissolves on the human's single dismiss.

**Error handling to keep:** `s.fail(w, err)` for internal errors (lines 444-451); `writeErr(w, status, code, msg)` (line 475); never `err.Error()` to clients except the existing `content_rejected` case. Non-fatal side effects use `s.log.Warn(...)` (line 430, 436).

---

### `server/internal/gateway/gateway_test.go` (test, request-response)

**Rig to extend** (lines 25-48): `newRig` does not keep `srv`. Add `newRigWith(t, func(*config.Config)) (*rig, *fakeClock)` by copying lines 31-48 verbatim but mutating `cfg := config.Load()` through the callback, setting `srv.now = clock.Now` BEFORE `httptest.NewServer(srv.Routes())`. Fake clock type is in RESEARCH "Fake-clock rig".
```go
mr, err := miniredis.Run()
t.Cleanup(mr.Close)
rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
st := store.New(rdb)
mm := matchmaker.New(st)
log := slog.New(slog.NewTextHandler(io.Discard, nil))
srv := New(st, mm, push.Noop{Log: log}, moderation.LogSink{Log: log}, log, config.Load())
```
**Request helpers:** `r.do(t, method, path, token, body)` (lines 64-85) with `map[string]any{"allowBot": true}`; `enter` helper (87-96) sends `map[string]any{}` so add `enterAllow(t, allow any)` rather than changing it. Response shapes `enterResp` / `waitingResp` (52-62) decode `sessions.View`, so `PartnerIsBot` is available for free.

**Race test model** (`TestMatchRaceSingleSession`, lines 283-320): `sync.WaitGroup`, goroutines calling `r.do`, assert from collected results, `t.Errorf` (not `Fatalf`) inside goroutines. Copy for human-vs-bot: A past window polls `/v1/waiting` while B enters concurrently, ~50 iterations with a fresh rig each; assert exactly one `sw:sess:` key.

**Zero-keys invariant** (lines 322-329) is the template for a stricter bot-path helper (no key at all with prefix `sw:`):
```go
for _, k := range mr.Keys() {
	if strings.HasPrefix(k, "sw:sess:") || strings.HasPrefix(k, "sw:tok:") || strings.HasPrefix(k, "sw:idem:") {
		t.Fatalf("dissolved session left key %q", k)
	}
}
```
Do NOT assert the stricter form on the human-human path (known `sw:wait:*` leak).

Test list is RESEARCH Q4 (10 cases); restart-safety case builds a second `Server` over the same miniredis. Existing golden-path test to mirror for full bot poem: `TestFullPoemHappyPath` (line 155).

---

### `server/internal/store/store_test.go` (NEW)

No store tests exist. Use the miniredis setup from `newRig` (lines 32-41) without the HTTP layer. Cases: `ClaimWaiter` returns true once then false; false when a prior `PopWaiter` took the id.

---

## Pattern Assignments (Swift)

### `ios/Strangewords/App/SettingsStore.swift` (NEW, store)

**Analog:** `TokenStore`, `ios/Strangewords/Net/Keychain.swift` lines 16-41. Copy the struct shape exactly:
```swift
struct TokenStore {
    static let tokenKey = "sw.participantToken"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var token: String? {
        get { defaults.string(forKey: Self.tokenKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.tokenKey) }
    }
}
```
`SettingsStore.allowBot: Bool` with `static let allowBotKey = "pref.allowBot"`. The key MUST NOT start with `sw.` (`HostIsolationTests.standardDefaultsHoldNoSessionKeys` filters `hasPrefix("sw.")`, HostIsolationTests.swift lines 28-31; do not loosen it). Do not touch it from `TokenStore.clear()` (lines 37-40). `defaults.bool(forKey:)` returns false when absent, which gives default OFF.

---

### `ios/Strangewords/App/AppModel.swift`

**Seam pattern** (init, lines 67-83): add `settings: SettingsStore = SettingsStore()` between `tokenStore` and `pollInterval`, matching how `tokenStore` is stored (`private let tokenStore: TokenStore`, line 52):
```swift
init(backend: (any Backend)? = nil,
     tokenStore: TokenStore = TokenStore(),
     pollInterval: Duration = AppModel.defaultPollInterval) {
    self.tokenStore = tokenStore
```
Property: `var allowBot: Bool { didSet { settings.allowBot = allowBot } }` with `@ObservationIgnored private let settings` (compile-verified in RESEARCH). Init order: assign `settings`, then `allowBot = settings.allowBot`.

**begin()** (lines 88-106): change `api.enter(pushToken: nil)` (line 96) to `api.enter(pushToken: nil, allowBot: allowBot)`, capturing the value before the `Task` (like `let e = epoch`, line 90). `dissolve`/`reset` (lines 195, 247-250) call `tokenStore.clear()` only; do not clear settings.

---

### `Net/Backend.swift`, `APIClient.swift`, `LocalBackend.swift`, `Models.swift`

Land all of these plus `FakeBackend`, `AppModel`, and the 10 `LocalBackendTests` call sites in ONE plan so the tree builds (RESEARCH Pitfall 6).

**Backend.swift line 11:** `func enter(pushToken: String?, allowBot: Bool) async throws -> EnterResponse`. No forwarding overload.

**APIClient.swift lines 56-62:**
```swift
func enter(pushToken: String?) async throws -> EnterResponse {
    var body: [String: Any] = [:]
    if let pushToken { body["pushToken"] = pushToken }
    let (data, status) = try await send("POST", "/v1/enter", token: nil, json: body)
```
Add `body["allowBot"] = allowBot` (always sent).

**Models.swift lines 5-24:** `SessionView` is `let`-based, `Codable, Equatable`. Add `var partnerIsBot: Bool = false` LAST in the struct and a tolerant `init(from:)` in an `extension` that lists all coding keys (RESEARCH "Tolerant SessionView decode"), keeping the memberwise init for `haikuView` and `LocalBackend.view()`.

**LocalBackend.swift:** `enter` is lines 71-79, `waiting` lines 81-83, `view()` lines 55-67, init seam lines 43-48:
```swift
init(strangerThinkTime: TimeInterval = LocalBackend.defaultStrangerThinkTime, enterDelay: Duration = LocalBackend.defaultEnterDelay)
static let defaultStrangerThinkTime: TimeInterval = 1.6   // [TUNABLE] pattern
```
Add `static let defaultBotWindow` `[TUNABLE]` and init param `botWindow`. `allowBot == false`: unchanged path, `partnerIsBot` false. `allowBot == true`: return `state: "waiting"`, non-nil `waitId`, record wait start; `waiting(token:)` returns `waiting` until the window elapses (same `Date().timeIntervalSince(since) >= ...` idiom as `getSession` lines 89-90), then `matched` with `partnerIsBot: true` in `view()`. Pin divergences with `DRIFT` comments (style at lines 126-128).

---

### `Features/Threshold/ThresholdView.swift` (gear + sheet)

**Analog:** itself (lines 5-33): `@Environment(AppModel.self) private var model`, `@Environment(\.palette) private var palette`, `@State private var tagline`, root `VStack(spacing: 40)`. Add `@State private var showSettings = false`, `.overlay(alignment: .topLeading)` gear (UI-SPEC Surface 1 geometry: 44pt hit, 36pt `Circle` backing `palette.onAccent.opacity(0.6)`, `-12` x offset, `.padding(.top, 8)`, plain `ButtonStyle` NOT `.ritual`), and `.sheet(isPresented:)` with re-injected `\.palette`, `\.sceneTheme`, `.environment(model)`, `.preferredColorScheme`. Existing button style to keep for "begin" (lines 25-29).

### `Features/Settings/SettingsView.swift` (NEW)

**Analog:** `ThresholdView` conventions for tokens: `Theme.poem(20)` title, `Theme.chrome`, `Theme.label`, `palette.ink`. Binding idiom copied from `ComposeView` line 12 (`@Bindable var model = model`) then `Toggle(isOn: $model.allowBot)`. Rows in a `VStack(spacing: 16)` (UI-SPEC). Copy strings are fixed in UI-SPEC Surface 1.

### `Features/Compose/PartnerPresence.swift` (NEW) and Compose/Reveal/Waiting edits

**Pure-function + view split:** `PartnerPresence.caption(...) -> String?` (nil for human, `"writing with the robot poet"` / `"written with the robot poet"` for bot; UI-SPEC Surface 2). View is a `Text` in `Theme.label` on a `Capsule`.

**ComposeView** (lines 11-37): insert chip as first child of `VStack(spacing: 28)` before `Spacer(minLength: 24)` (line 14); `theirTurn` (lines 101-113) switches copy on `session.partnerIsBot`:
```swift
Text("the stranger is with the poem now").font(Theme.chrome).foregroundStyle(palette.secondary)
...
.accessibilityLabel("Waiting for the stranger to write their line.")
```
**RevealView** (lines 14-17): first child of `VStack(spacing: 30)` before the first `Spacer()`.
**WaitingView** (lines 13-25): wrap the existing `Text(connecting ? ...)` in `VStack(spacing: 12)` and add the soft line only when `model.allowBot && !connecting`; update the combined `accessibilityLabel` (line 41) per UI-SPEC Surface 3.

---

### Swift tests

**FakeBackend.swift:** `enter` is line 101 (`func enter(pushToken: String?)`), `Pending` (lines 26-47) carries `id/token/line/text/idemKey` and is built in `park` (lines 145-155). Add `allowBot: Bool?` to `Pending`, its `fileprivate init`, and `park(...)`; update the `enter` conformance to `enter(pushToken: String?, allowBot: Bool)` passing it through.

**TestSupport.swift lines 19-21:** `makeModel` is the ONLY AppModel factory; extend to also pass `settings: SettingsStore(defaults: defaults)`:
```swift
AppModel(backend: backend, tokenStore: TokenStore(defaults: defaults), pollInterval: .zero)
```
`haikuView` (lines 24-30) can gain a `partnerIsBot: Bool = false` parameter.

**SettingsStoreTests.swift (NEW):** copy `SeamDefaultsTests.tokenStoreKeysAreUnchanged` / `tokenStoreDefaultsToStandard` / `tokenStoreIsolatesSuites` (SeamDefaultsTests.swift lines 22-50): pin `SettingsStore.allowBotKey == "pref.allowBot"` and `!hasPrefix("sw.")`, default false, round-trip, suite isolation, `TokenStore.clear()` leaves it. Struct-style suite, `makeIsolatedDefaults()` + `defer { cleanup() }`, Swift Testing `@Test` / `#expect`.

**AppModelTests.swift:** copy the `Rig` struct (lines 17-50) and `beginMatched` flow; assert `Pending.allowBot` for the `.enter` arrival is false by default and true after `model.allowBot = true`; allowBot survives dissolve/reset. Suite attributes to keep: `@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))`; end with `await finish(model, fake, cleanup)`.

**LocalBackendTests.swift:** copy `enterPairsImmediatelyWithAStranger` (lines 24-45) style: `LocalBackend(strangerThinkTime: 0, enterDelay: .zero, botWindow: 0)`; update all `enter(pushToken: nil)` call sites with `allowBot: false`; add `defaultsMatchShippedPacing` (lines 16-19) assertion for `defaultBotWindow`.

**SessionViewTests.swift:** add decode cases (JSON without `partnerIsBot` is false; with true is true; memberwise default false).

**Run:** `scripts/test-ios.sh` (headless; verdict from xcresult). No XCUITest (out of scope).

---

## Shared Patterns

### Fail-closed opt-in flag
**Source:** `server/internal/gateway/gateway.go` lines 111-112.
**Apply to:** `handleEnter` only. Keep `_ = json.NewDecoder(r.Body).Decode(&req)`; absent, false, or wrong-typed `allowBot` all yield false. Pin with a test.

### Single choke point for disclosure
**Source:** `Session.ViewFor`, `server/internal/sessions/session.go` lines 92-111.
**Apply to:** every route that returns a view (`handleEnter` 128, `handleWaiting` 180, `handleGetSession` 192, `handleLine` 268, `handleDismiss` 315). Never compute `partnerIsBot` in a handler or accept it from the client.

### Ephemerality / zero keys
**Source:** `store.DeleteSession` via `Server.dissolve` (gateway.go lines 434-440), `assertNoSessionKeys` (gateway_test.go 322-329).
**Apply to:** all bot-path code. No new Redis keys, no locks. `allowBot` lives only on the TTL-bound `WaitEntry` and is deleted on claim.

### Tunables
**Source:** `config.go` line 34; `LocalBackend.swift` lines 19-23 (`/// ... [TUNABLE]`).
**Apply to:** `BotWindow`, `BotThink`, `LocalBackend.defaultBotWindow`.

### Injected time
**Source:** `Server.now func() time.Time` (gateway.go lines 31, 36); `Matchmaker.Enter(..., now time.Time)`.
**Apply to:** all window/think logic and tests; no `time.Sleep` for the 25 s window.

### Mock/real parity
**Source:** `Backend` protocol (Backend.swift lines 10-17) plus both conformers.
**Apply to:** the `enter(pushToken:allowBot:)` change; `LocalBackend` simulates the opted-in wait-then-bot arc.

### Error handling (Go)
**Source:** gateway.go lines 444-451, 475-480; `errors.Is` throughout.
**Apply to:** new handler code. Never leak `err.Error()`; non-fatal side effects log at Warn.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| Settings sheet idiom (`.sheet`, `.presentationDetents`) in `ThresholdView`/`SettingsView` | component | event-driven | No sheet exists in the app. Use RESEARCH "Gear + sheet" snippet and UI-SPEC Surface 1 |
| `fakeClock` + `newRigWith` | test util | request-response | No injectable-clock rig in gateway tests yet (a `rateLimiter.now` injection exists in `middleware_test.go` lines 61-63; use it as a stylistic reference) |
| `store_test.go` | test | CRUD | No store tests exist |

## Notes for the planner

- `handleWaiting` fall-through on a lost claim must reply `waiting`, never an error (RESEARCH Pitfall 1).
- `cmd/bot` is a dev tool that queues undisclosed; do not run it against production. If `Seed`/`NextLine` move into `internal/botplayer`, keep `cmd/bot/main_test.go` green.
- If `privacy.html` changes, update the pinned date in `privacy_test.go` in the same commit.
- I did not read `server/cmd/bot/main.go` past line 80, `DeleteSession`/`DelWait` in store.go past line 160, or `middleware_test.go`; the executor should read those before editing.

## Metadata

**Analog search scope:** `server/internal/{gateway,store,matchmaker,sessions,config,metrics,poet}`, `server/cmd/bot`, `ios/Strangewords/{App,Net,Features}`, `ios/StrangewordsTests`
**Files scanned:** ~30
**Pattern extraction date:** 2026-10-26
