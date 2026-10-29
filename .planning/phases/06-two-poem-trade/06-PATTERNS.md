# Phase 6: Two-Poem Trade - Pattern Map

**Mapped:** 2026-10-29
**Files analyzed:** 20 new/modified surfaces
**Analogs found:** 19 / 20 (all tracked; verified with `git ls-files`)

## File Classification

| New/Modified Surface | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `server/internal/sessions/session.go` — trade state + poem reset | model | state machine | itself: encounter/poem field split, `session.go:30-50` | exact (modify in place) |
| `server/internal/sessions/session.go` — `View` trade fields | model | request-response | `PartnerIsBot` on View, `session.go:94-141` | exact |
| `server/internal/gateway/gateway.go` — trade offer/accept handler | controller | request-response | `handleDismiss` `gateway.go:399-421` | exact |
| `server/internal/gateway/gateway.go` — trade request decode | wire contract | request-response | `enterRequest.AllowBot` `gateway.go:98-117` | exact |
| `server/internal/gateway/gateway.go` — bot auto-accept | service | event-driven (poll-settled) | `settleBot` `gateway.go:514-556` | exact |
| `server/internal/gateway/gateway.go` — route registration | config | request-response | `Routes()` `gateway.go:51-71` | exact |
| `server/internal/botplayer/botplayer.go` — replay into poem 2 | service | deterministic replay | `NextLine`/`Seed` `botplayer.go:21-45` | exact (modify) |
| `server/internal/store/store.go` — concurrent both-accept write | repository | CAS write | `UpdateSession` `store.go:306-339` | exact (reuse, likely no store change) |
| `server/internal/metrics/metrics.go` — trade counters | config | counters | `WaitLeft`/`BotPaired` `metrics.go:28-34` | exact |
| `server/internal/gateway/` trade tests | test | HTTP + fake clock | `bot_test.go:34-113` (`fakeClock`, `newBotRig`) | exact |
| `ios/Strangewords/Net/Backend.swift` — trade protocol method | protocol | request-response | `leaveWait` doc+decl `Backend.swift:20-25` | exact |
| `ios/Strangewords/Net/APIClient.swift` — trade call | service | request-response | `submitLine` (throwing) `APIClient.swift:77-82` / `leaveWait` (fire-and-forget) `:88-90` | exact |
| `ios/Strangewords/Net/Models.swift` — `SessionView` trade fields | model | tolerant decode | `partnerIsBot` `Models.swift:14-56` | exact |
| `ios/Strangewords/Net/LocalBackend.swift` — mock trade arc | service | state machine | `advance()`/`dissolve()`/`waiting()` `LocalBackend.swift:101-233` | exact (modify) |
| `ios/Strangewords/App/AppModel.swift` — trade action + phase plumbing | store (state machine) | event-driven | `release()`/`apply()`/epoch `AppModel.swift:193-283` | exact (modify) |
| `ios/Strangewords/Features/Reveal/RevealView.swift` — trade-back affordance | component | request-response | "let it go" button `RevealView.swift:32-39` | exact (modify) |
| Trade copy (new pure-function strings) | utility | pure function | `PartnerPresence` statics `PartnerPresence.swift:42-88` | exact |
| `ios/Strangewords/Naming/PoemNaming.swift` — remove `kind` | model | pure function | itself `PoemNaming.swift:12-36,65-102` | exact (modify) |
| `ios/Strangewords/Features/Dissolved/DissolvedView.swift` — drop kind line, two keepsakes | component | render | `keepsakeBody` `DissolvedView.swift:29-54` | exact (modify) |
| iOS tests (trade flow, copy, goldens re-capture) | test | gated fake | `FakeBackend.swift`, `TestSupport.swift:19-33`, `PoemNamingTests.swift:26-47` | exact |

## Pattern Assignments

### Server domain: trade state on `Session` (`server/internal/sessions/session.go`)

**Analog:** the file's own encounter/poem split — the seam this phase was designed for.

**Encounter vs poem split** (`session.go:30-50`): `StartIndex`, `Participants`, `Bucket` are encounter-level; `Status`, `Lines`, `CurrentLine`, `CompletedAt`, `BotReadyAt`, `IdemKeys` are poem-level and reset when poem 2 begins. `PoemCount` (`session.go:48`) already exists — increment it on trade. Role swap (D-03) is `StartIndex` arithmetic through `AuthorOf` (`session.go:62-64`) and `roundRobin.Author` (`policy.go:23-28`): poem 2 starts from the *other* index, i.e. `StartIndex = (StartIndex + 1) % len(Participants)` — never a policy change.

**Per-participant trade flag pattern** — copy `Participant.Dismissed` (`session.go:21`): a bool with `omitempty`, one per participant, "both set" triggers the transition. The bot participant precedent (`session.go:22-24`): the robot poet is "created already dismissed"; its trade acceptance is instead time-paced via settleBot (below), per D-06's never-instantly rule.

**View projection** (`session.go:94-141`): any new client-visible trade state (e.g. `tradeOffered`, `poemNumber`) goes on `View` with `omitempty` and is computed only in `ViewFor` — copy the `PartnerIsBot` comment discipline at `session.go:104-106` ("computed only in ViewFor (D-04), never read from a request").

### Server flow: offer/accept handler (`server/internal/gateway/gateway.go`)

**Analog:** `handleDismiss` (`gateway.go:399-421`) — the one existing "participant signals during the reveal window; all-signed triggers a transition" handler.

```go
func (s *Server) handleDismiss(w http.ResponseWriter, r *http.Request) {
	sess, token, idx, ok := s.authSession(w, r)
	if !ok { return }
	sess.Participants[idx].Dismissed = true
	allDismissed := true
	for _, p := range sess.Participants {
		if !p.Dismissed { allDismissed = false; break }
	}
	if allDismissed {
		s.dissolve(r.Context(), sess)
		writeJSON(w, http.StatusOK, map[string]string{"status": "dissolved"})
		return
	}
	// Preserve the reveal countdown rather than extending it.
	_ = s.st.SaveSessionTTL(r.Context(), sess, store.RevealTTL)
	v := sess.ViewFor(token)
	writeJSON(w, http.StatusOK, v)
}
```

The trade handler mirrors this shape ("both accepted" instead of "all dismissed"), but the both-accepted transition is a read-modify-write race (two humans accept concurrently), so the body belongs inside `store.UpdateSession` (CAS pattern below), not a plain `SaveSession`. Status gate precedent: `handleLine`'s `if sess.Status != sessions.StatusActive { writeErr(w, 409, "not_active", ...) }` (`gateway.go:324-326`) — a trade offer outside `StatusComplete` should 409 with a stable snake_case code via `writeErr` (`gateway.go:637-642`).

**Route registration** — copy `Routes()` (`gateway.go:56-63`): `mux.HandleFunc("POST /v1/session/{id}/trade", s.handleTrade)` style, Go 1.22 method+path.

**Reveal-TTL discipline** — "offer ages out with the session": copy `handleDismiss`'s `SaveSessionTTL(..., store.RevealTTL)` (`gateway.go:418`) which preserves rather than extends the countdown; when poem 2 begins, flip back to `SaveSession` / `store.SessionTTL` (`store.go:270-279`, TTL constants `store.go:22-23`). Zero new `sw:` key classes — all trade state lives inside the session blob.

### Wire contract: lenient request decode (allowBot precedent)

**Analog:** `enterRequest.AllowBot` (`gateway.go:98-106, 115-117`):

```go
// AllowBot is the caller's own opt-in to the robot poet (D-01). The lenient
// decode below leaves it false when absent or wrongly typed (fail-closed).
AllowBot bool `json:"allowBot"`
...
_ = json.NewDecoder(r.Body).Decode(&req) // tolerate empty body
```

Any trade request field defaults false on absence (old client never offers → dissolves as today — the fail-safe the context requires). On the response side, new `View` fields are `omitempty` so old clients never see them.

### Bot auto-accept + replay (`gateway.go` settleBot, `botplayer.go`)

**Analog:** `settleBot` (`gateway.go:514-556`) — the poll-settled, think-time-paced, CAS-guarded bot action. The bot's trade acceptance is the same shape: a cheap pre-check (`BotTurn()`-style predicate + `now < BotReadyAt`-style readiness, `gateway.go:516-518`), then re-decide inside `s.st.UpdateSession` on the fresh read, returning `(ttl, write)`; `ErrConflict` → reload (`gateway.go:541-548`); metrics incremented only `if wrote` (`gateway.go:549-554`). Arm the pacing exactly as `handleLine` arms `BotReadyAt` (`gateway.go:361-363`): `sess.BotReadyAt = now.Add(s.cfg.BotThink).UnixMilli()` — D-06's "usual think-time, never instantly".

**Replay:** `botplayer.NextLine` (`botplayer.go:31-45`) rebuilds the poet from `Seed(s.ID)` and replays every bot-authored earlier line. For poem 2 the replay input changes (new `Lines`, new `StartIndex`); keep determinism by deriving the poem-2 seed from stable session state — the `Seed` FNV-1a derivation (`botplayer.go:21-25`) is the pattern (e.g. seed over `s.ID` + poem ordinal). Note the matching derivation comment "same derivation as cmd/bot's seedFor" — `server/cmd/bot` must stay in lockstep if it participates in trades.

### Store: both-accept concurrency (`server/internal/store/store.go`)

**Analog:** `UpdateSession` (`store.go:296-339`) — WATCH/read-fresh/apply/MULTI-EXEC, one attempt, `ErrConflict` on abort, `apply` returns `(ttl, write)`. Reuse as-is for "second accepter flips the session to poem 2"; the TTL return value is how the accept writes `RevealTTL` (still offered) vs `SessionTTL` (poem 2 begun). No new store methods expected; no new key builders (the 5-literal structural gate).

### Metrics (`server/internal/metrics/metrics.go`)

**Analog:** the Phase 5 counter block (`metrics.go:28-34`):

```go
BotPaired = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_bot_paired_total", Help: "Opted-in waiters paired with the robot poet after the wait window."})
WaitLeft  = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_wait_left_total", Help: "Waiters who stepped back out before seeing a match."})
```

New counters (e.g. `sw_trades_offered_total`, `sw_trades_begun_total`) follow the `sw_*_total` naming and one-line Help. Assert in tests via `prometheus/testutil` as `bot_test.go` does.

### Server tests

**Analog:** `bot_test.go:34-113` — `fakeClock` (mutex-guarded manual clock, `Advance` not sleep, lines 34-53), `newBotRig` (miniredis + `cfg.RateRPS = 0` + `srv.now = clock.Now` injected before `httptest.NewServer`, lines 66-97), and `restart` (lines 101-113) for proving the trade state survives a restart (it's all in the session blob). `enterWith` (lines 116-121) is the arbitrary-body wire-tolerance probe — reuse for old-client/no-field trade decode tests. Wait/leave tests in `wait_test.go` are the freshest endpoint-test precedent.

---

### iOS: Backend protocol + clients

**Analog:** `leaveWait` — today's quick-batch precedent, the freshest full parity chain.

- Protocol decl with old-server behavior documented: `Backend.swift:20-25` ("An older server 404s it, which is ignored"). A trade method documents its old-server story the same way. "There is deliberately no overload that omits it" (`Backend.swift:11-14`) — no defaulted parameters.
- `APIClient`: if the trade action must return the updated `SessionView` (it should — the UI needs to know "offered" vs "poem 2 begun"), copy the throwing `submitLine` shape (`APIClient.swift:77-82`); if fire-and-forget, copy `leaveWait` (`APIClient.swift:88-90`, `_ = try? await send(...)`). Error mapping via `mapError` (`APIClient.swift:120-129`) — new 409 codes land as `.wrongTurn` unless added.
- Parity rule: the method must land in `APIClient`, `LocalBackend` (`LocalBackend.swift:150-152` shows the one-liner trio), and `FakeBackend` simultaneously.

### iOS: `SessionView` tolerant decode (`ios/Strangewords/Net/Models.swift`)

**Analog:** `partnerIsBot` (`Models.swift:14-18, 29-56`): `var` with default, declared last ("keeps the memberwise initializer compiling at every call site"), added to the explicit `CodingKeys` AND the hand-written `init(from:)` as `decodeIfPresent ... ?? default`. Any new field (`tradeOffered`, `poemNumber`) copies all three steps — the CodingKeys comment at `Models.swift:31-33` warns exactly this.

### iOS: `AppModel` trade action + second reveal (`ios/Strangewords/App/AppModel.swift`)

**Analogs within the file:**
- New user action → copy `release()` (`AppModel.swift:193-199`): guard on `.reveal(let s)`, capture token, `actionTask = Task { ... }`. A trade offer that awaits a response copies `submit()` (`AppModel.swift:159-189`): capture `let e = epoch` before the Task, `guard !isStale(e)` after every await, map `APIError` cases.
- Phase transitions → `apply()` (`AppModel.swift:248-272`) already routes `"active"` → `.composing` and `"complete"` → `.reveal`; a trade that returns an active poem-2 view flows through it for free. The `wasReveal`/`wasComposing` haptic-transition detection (lines 250-253) is the pattern for any new trade haptic.
- Keepsake per poem (D-04) → coining lives in `finishDissolving()` (`AppModel.swift:203-208`), currently single `keepsake: CoinedName?` (`:44`). Poem-1's coining must move to the moment the trade begins/poem completes (lines still in hand — same "while the lines are still in hand" comment discipline); storage becomes a collection. The epoch rules (`:73-76`, `isStale` `:333-335`): `begin`/`reset`/`dissolve` bump it; a trade transition does NOT dissolve, so it does not bump the epoch — same session, same token.

### iOS: Reveal trade-back affordance (`ios/Strangewords/Features/Reveal/RevealView.swift`)

**Analog:** the "let it go" button (`RevealView.swift:32-39`):

```swift
Button {
    Haptics.soft()
    model.release()
} label: {
    Text("let it go").font(Theme.poem(18))
}
.buttonStyle(.ritual)
.accessibilityHint("Dismisses the poem. It will not be saved.")
```

The trade-back offer sits beside it: same `.ritual` style, `Theme.poem` font, `Haptics.soft()`, an `.accessibilityHint`. The `PartnerPresence.caption(partnerIsBot:finished:)` call at `RevealView.swift:15-19` shows how reveal already consumes pure-function copy.

### iOS: trade copy (new strings)

**Analog:** `PartnerPresence` statics (`PartnerPresence.swift:42-88`) — every user-facing string is a pure static function/constant so `PartnerPresenceTests` can pin it:

```swift
static func caption(partnerIsBot: Bool, finished: Bool) -> String? {
    guard partnerIsBot else { return nil }
    return finished ? "written with the robot poet" : "writing with the robot poet"
}
```

New trade copy (offer label, "the stranger offered to trade back", bot variant) goes in a pure-function home the same way, with matching accessibility strings, pinned by a copy-voice test.

### iOS: `LocalBackend` trade arc (`ios/Strangewords/Net/LocalBackend.swift`)

**Analog:** its own state machine. Poem transition → `advance()` (`LocalBackend.swift:224-233`, flips `status`/`strangerTurnSince`); mock stranger pacing → `getSession`'s think-time check (`:130-139`) is the pattern for "the mock stranger accepts the trade after `strangerThinkTime`"; reset-for-a-new-poem → `enter()`'s field zeroing (`:101-108`). Injectable timings with `[TUNABLE]` defaults and zero-in-tests (`:35-47, 71-77`) — any new trade pacing knob follows this. Document divergences with `// DRIFT:` lines as the header does (`:20-29`). Role swap: the mock hardcodes `currentAuthor = currentLine % 2` from start 0 (`:80`); poem 2 needs a start-offset term mirroring `roundRobin.Author`.

### iOS: keepsake `kind` removal (`PoemNaming.swift`, `DissolvedView.swift`)

- `CoinedName` (`PoemNaming.swift:12-16`): drop `kind`; `Coiner` typealias (`:65`) returns `(name, kind)` — collapse to name-only across `coiners` (`:71-90`) and `soloCoiners` (`:93-102`); `coin` (`:22-36`) stops threading kind. CAUTION: keep every `rng` draw order intact (the kind strings are compile-time constants, not draws, so removing them does not disturb the stream — but `beerStyles` picks and `Int.random`/`Bool.random` calls inside coiners DO draw; preserve them or the golden names change).
- `DissolvedView.keepsakeBody` (`DissolvedView.swift:29-54`): delete the `Text(keepsake.kind)` line (`:40-42`) and its accessibility mention (`:53`); the lead + name stay. Two-keepsake rendering copies the existing `VStack(spacing: 16)` block per poem.
- Golden re-capture: `PoemNamingTests.goldens` (`PoemNamingTests.swift:26-47`) asserts `coined.kind == g.kind` per golden — drop the kind column and re-capture only with a cited reason, per the file's own header rule (pinned simulator, RESEARCH Pitfall 5). CONTEXT.md explicitly flags this.

### iOS tests

**Analogs:**
- `FakeBackend` (`FakeBackend.swift`): new trade `Kind` case + parked call via `park(...)` (`:157-167`) if the model awaits a result, or the `calls.append` one-liner shape (`:125-136`) if fire-and-forget. Recorded-argument accessor precedent: `recordedLeaveWaitTokens()` (`:141`).
- `TestSupport.makeModel` (`TestSupport.swift:19-23`) is the ONLY model factory; `haikuView(...)` (`:26-33`) grows trade parameters with defaults; `Arrivals`/`finish` (`:42-66`) for gated, sleep-free sequencing.
- Copy tests: `PartnerPresenceTests.swift` style — pure-function assertions on exact strings.

## Shared Patterns

### Error contract
**Source:** `writeErr`/`errBody` (`gateway.go:630-642`), `s.fail` (`gateway.go:606-613`), `APIError` mapping (`APIClient.swift:120-129`). New 409 trade codes are stable snake_case tokens; never leak `err.Error()`.

### Epoch / stale-writer discipline (iOS)
**Source:** `AppModel.swift:73-76, 333-335`. Every async writer captures `let e = epoch` and guards `!isStale(e)` after each await. Trade transitions stay inside the current epoch.

### TTL discipline
**Source:** `store.go:22-23` (TTL constants with `[TUNABLE]`-style doc), `gateway.go:417-418` (preserve the reveal countdown), `handleLine`'s complete-vs-active TTL fork (`gateway.go:352-367`). Offered-but-unanswered trades ride `RevealTTL`; accepted trades return to `SessionTTL`.

### Design-doc citations and markers
Preserve/extend `plan.v1.md §` citations and `[TUNABLE]` markers on any constant expected to be tuned (per CLAUDE.md); cite this phase's D-numbers in comments as Phase 5 code does (`gateway.go:100`, `session.go:105`).

## No Analog Found

| Surface | Role | Data Flow | Reason / fallback |
|---|---|---|---|
| Multi-keepsake UI arrangement (two coined names on one Dissolved screen) | component | render | No multi-item keepsake exists; compose from `keepsakeBody`'s single-name VStack (`DissolvedView.swift:30-47`) repeated, per orchestrator discretion |

## Metadata

**Analog search scope:** `server/internal/{sessions,gateway,store,botplayer,metrics}`, `server/cmd/bot` (noted for seed lockstep), `ios/Strangewords/{App,Net,Features,Naming}`, `ios/StrangewordsTests`
**Files scanned:** 22 (all verified git-tracked)
**Pattern extraction date:** 2026-10-29
