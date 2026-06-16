# Haiku for Strangers — v1 Implementation Plan

> **Drives:** the v1 thin-slice build toward TestFlight
> **Source of truth for intent:** `brief.v4.md`
> **This document:** concrete architecture, contracts, and a phased task breakdown to implement against
> **Status:** ready to build

This plan turns the brief into buildable decisions. Where the brief left tuning values open, this plan picks a v1 default and marks it `[TUNABLE]`. Where it makes a structural choice not in the brief, it marks it `[DECISION]` with a one-line rationale.

---

## 1. Scope of v1

**In:** the full emotional core loop, end to end.

* anonymous entry (threshold)
* matchmaking (instant if a partner waits, otherwise wait-and-be-pushed)
* hybrid composition: live-ish when both present, note-and-wait + push when apart
* three-turn poem (A-B-A, 5-7-5 soft guidance, on-device syllable hint)
* leave / return to an in-progress poem (resume token)
* completed-poem reveal, then dissolution
* 1–2h outer expiration + clean teardown of all state
* APNs re-engagement (match-ready, your-turn)
* minimal safety rails (length/empty checks, basic rate limits)

**In before TestFlight goes beyond the internal circle:** reporting + minimal moderation store, EULA/objectionable-content gate, content filter (Phase 5).

**Deferred (noted, not built in v1):** WebSocket live transport, DeviceCheck/App Attest, language segmentation, "found poem"/solo fallback, full observability dashboards, Android/web clients.

**Deferred but seam-reserved:** multiple poem forms (and their soft-nudge structure), "continue with this person," and match preferences. These are *not* built in v1, but the data model and contracts are deliberately shaped so each is additive rather than a rewrite. v1 ships single-form, single-poem-per-encounter, single-bucket defaults. See **Section 13**.

---

## 2. Architecture Overview

```
┌────────────────────────┐         HTTPS (JSON)          ┌───────────────────────┐
│   iOS app (SwiftUI)     │  ───────────────────────────▶ │   Go service           │
│                         │                                │  (one deployable)      │
│  - threshold/waiting/   │  ◀─── APNs (re-engagement) ─── │                        │
│    compose/reveal UI    │            via Apple           │  packages:             │
│  - URLSession client    │                                │   gateway  (http)      │
│  - Keychain token       │                                │   matchmaker           │
│  - syllable hint        │                                │   sessions (runtime)   │
│  - push handling        │                                │   push     (APNs)      │
└────────────────────────┘                                │   moderation (Ph.5)    │
                                                           │   metrics              │
                                                           └───────────┬───────────┘
                                                                       │
                                                          ┌────────────▼───────────┐
                                                          │  Redis (ephemeral)      │
                                                          │  queue, sessions, tokens│
                                                          │  all TTL-bounded        │
                                                          └─────────────────────────┘
                                       (Phase 5) reports ─▶ Postgres (the one durable store)
```

**Transport:** HTTPS request/response only in v1. No held socket. "Live, both present" is approximated by APNs-to-foreground + light client polling (Section 7). A WebSocket layer is a clean future add and nothing here precludes it.

**State:** everything operational lives in Redis with TTLs. The only durable store is the Phase 5 moderation `reports` table.

---

## 3. Repository Layout

Monorepo.

```
strangewords/
  brief.final.md            # v3 archive
  brief.v4.md               # current brief (intent)
  plan.v1.md                # this file
  server/                   # Go service
    cmd/server/main.go
    internal/
      gateway/              # http handlers, routing, auth middleware, rate limit
      matchmaker/           # waiting pool + pairing
      sessions/            # session state machine + Redis repo
      push/                 # APNs client
      moderation/           # (Phase 5) report capture + store
      metrics/              # counters/gauges
      config/               # env config
    go.mod
    docker-compose.yml      # local redis (+ postgres in Phase 5)
    Makefile
  ios/                      # SwiftUI app (Xcode project)
    Strangewords/
      App/                  # app entry, root state
      Net/                  # API client, models, Keychain
      Features/
        Threshold/
        Waiting/
        Compose/
        Reveal/
      Design/               # type scale, motion, haptics, colors
      Syllables/            # on-device heuristic
  docs/
    api.md                  # generated/maintained API reference
```

`[DECISION]` Monorepo: one product, two artifacts that move together; shared docs; simpler to keep the API contract honest.

---

## 4. Identity & Auth Model

No accounts. Two opaque secrets, both infrastructural (per `brief.v4.md` §7):

* **`participantToken`** — 32 random bytes, base64url. Issued by the server on `enter`. Sent as `Authorization: Bearer <token>` on every subsequent request. Server maps it to the participant's current waiting entry or session + participant index (0-based ordinal within the session). Stored client-side in the **Keychain**, scoped to the single active engagement, deleted on dissolution.
* **`sessionId`** — 16 random bytes, base64url. Identifies a poem session. Not secret on its own; actions require the matching `participantToken`.

The `participantToken` *is* the resume token: returning to the app re-uses it to fetch current state. No identifier the other participant could see, recognize, or re-contact is ever issued. Push tokens live only inside the session record and die with it.

`[DECISION]` Single bearer token (not separate participant-id + resume-token): fewer moving parts, same guarantees.

---

## 5. Session State Machine

Server-side state derives from two nested concepts. Getting this split right in v1 is what lets later features (multiple forms, "continue together") be additive rather than a rewrite — see Section 13.

* **Session = the encounter** between two anonymous participants: the pair, their tokens, push tokens, presence. The `participantToken` is bound to the *encounter*, not to a single poem.
* **Poem = the current collaborative artifact** inside the encounter: a chosen `Form`, the lines so far, and whose turn it is. v1 runs **exactly one poem per encounter**, then dissolves.

### Form (data-driven structure)

A poem's structure is a **`Form` value**, not hardcoded constants. A Form describes the *text shape only*: an ordered list of lines, each with an optional syllable target (the "soft nudge"; `null` = no nudge, e.g. free verse). **Authorship — who writes which line — is not part of the Form; it lives in a separate, pluggable `TurnPolicy` (below).**

v1 ships **one** Form in a registry, `haiku`:

```
haiku = { id: "haiku", lineCount: 3, targets: [5, 7, 5] }
```

The session runtime reads the text shape (line count, targets) **from the Form**, never from inline constants. Adding tanka (`[5,7,5,7,7]`), couplet, or free verse (`targets: [null, null]`) later is a registry entry, not a code change.

### Statuses (stored on the session record)

| status        | meaning                                                                    |
|---------------|----------------------------------------------------------------------------|
| `active`      | a poem is in progress; `currentLine` indexes the Form; the TurnPolicy names the author |
| `complete`    | every line of the Form is filled; reveal window open                       |
| `dissolved`   | terminal; record being/already erased                                      |

(`waiting` is not a session — it is a queue entry, Section 6. A reserved future status, `continuing`, is covered in Section 13.)

### Turn-taking (pluggable `TurnPolicy`)

Who writes the next line is decided by a **`TurnPolicy`** — a small strategy, chosen per session, separate from the Form. Given the ordered participant list and the lines written so far, it answers one question: **who authors line `i`?** (and, by extension, when the poem is complete). This is the seam for the "fun things later" — poetry circles, alternate orders — without touching the session machinery.

Conceptually:

```
TurnPolicy.author(lineIndex, participants, startIndex) -> participantIndex   // or CLAIMABLE
```

v1 ships **one** policy, `round-robin`: `author(i) = participants[(startIndex + i) mod n]`, with `startIndex` chosen at random at match. A pleasing consequence: round-robin over **2 participants × 3 lines** yields `p, q, p` — exactly the haiku **A-B-A**. The brief's "intentional asymmetry" (one voice frames, the other interrupts) is no longer a special case; it *emerges* from round-robin over an odd line count. `firstSide` is gone, replaced by `startIndex`.

Policies the seam enables later (not built): **round-robin circles** (the same policy, `n > 2`), **random-next**, **free-claim** ("whoever takes the next line writes it" — natural for open circles), **role-based** (a fixed frame author writes first and last). A session pairs a Form with a policy; some artistic modes will fix both together.

Targets come from the Form and are **display-only, never enforced**. A `null` target renders no nudge.

### Transitions

```
            match (matchmaker)
   [queue] ───────────────────────▶ active(line 0, author per TurnPolicy)
                                          │
   valid submit by owner advances         │  (each submit refreshes outer TTL)
   currentLine through the Form           ▼
                                   active(line i, owner per Form)
                                          │  … until every Form line is filled
                                          ▼
                                      complete  ──(reveal cap elapses
                                          │         OR both dismiss)──▶ dissolved
                                          │
                                          └─(reserved §13: both opt "continue")─▶ active(new poem, fields reset)
   any active/complete state:
     - explicit leave by either side ───────────────────────────────▶ dissolved
     - outer TTL (90 min) elapses without activity ──────────────────▶ dissolved (TTL expiry)
     - report submitted ─────────────▶ (content captured) ───────────▶ dissolved
```

`[TUNABLE]` outer bound = **90 min**, refreshed on each line submit.
`[TUNABLE]` reveal window = shown until both dismiss, hard cap **120s**, then dissolve.
`[DECISION]` no per-turn timer in v1 — the outer bound is the only deadline. Keeps the live case unhurried and the implementation simple. A soft live-turn nudge can come later.

### Presence (approximate, HTTPS model)

Each participant carries a `lastSeen` timestamp (in the `participants` array), updated on any authenticated request from them. "Present" = last seen within `[TUNABLE]` **20s**. Presence is advisory (drives "they're here" UI hints and whether to bother sending a your-turn push); it never gates correctness.

---

## 6. Redis Data Model

All keys TTL-bounded. `sw:` prefix.

| key                                   | type        | contents                                                                 | TTL |
|---------------------------------------|-------------|--------------------------------------------------------------------------|-----|
| `sw:queue:{bucket}`                   | list (FIFO) | waiting entry ids for a match bucket, oldest first                       | —   |
| `sw:wait:{waitId}`                    | hash        | `token`, `pushToken`, `enqueuedAt`, `bucket`, `matchedSessionId?`        | 15m |
| `sw:tok:{participantToken}`           | hash        | `kind`=wait\|session, `refId`=waitId\|sessionId, `side`=A\|B            | 15m / 90m |
| `sw:sess:{sessionId}`                 | hash        | see fields below                                                         | 90m |
| `sw:idem:{sessionId}:{idemKey}`       | string      | stored response hash, prevents duplicate submit                          | 10m |
| `sw:rl:ip:{ip}`                       | string/int  | rate-limit counter (sliding window via token bucket)                     | 1m  |
| `sw:rl:tok:{participantToken}`        | string/int  | per-token submit rate counter                                            | 1m  |

**Session hash fields.** Split so a continuation (Section 13) resets only the poem, not the encounter:

* *Encounter-level (stable across continuation):* `sessionId`, `participants` (ordered JSON array of `{ token, pushToken, lastSeen }`; length 2 in v1), `startIndex`, `bucket`, `createdAt`.
* *Poem-level (reset if a pair continues):* `status`, `formId`, `policyId`, `lines` (JSON array, grows to the Form's line count), `currentLine`, `completedAt`, `poemCount` (1 in v1).

`turnOwner` is not stored — it is derived on read as `TurnPolicy(policyId).author(currentLine, participants, startIndex)`. Storing `participants` as an ordered array (not `A`/`B` fields) and `lines` as an array is what keeps the record N-participant- and variable-length-ready with no schema change.

**Matchmaking is atomic.** Pop-and-pair runs in a Lua script (or `MULTI`/`WATCH`) so two simultaneous arrivals can't both grab the same waiter or both create sessions. Single-node v1; the Lua approach already scales to multi-node behind shared Redis.

`[DECISION]` FIFO list per **bucket** (not a single global queue, not a sorted set): v1 matching is "pair the two who've waited longest *in the same bucket*," no scoring needed. A bucket is the matching segment derived from a participant's `prefs` — in v1 there is exactly one bucket (the sole `haiku` Form). Choosing a poem type or a language later just means more buckets; the matchmaker code is unchanged.

Teardown: dissolution deletes `sw:sess:{id}`, every participant's `sw:tok:*`, and any `sw:idem:*`. TTLs are the backstop so nothing leaks even if explicit teardown is missed.

---

## 7. HTTP API Contract

JSON over HTTPS. Base path `/v1`. All errors: `{ "error": { "code": "...", "message": "..." } }` with appropriate HTTP status. Auth header `Authorization: Bearer <participantToken>` on everything except `POST /enter`.

### `POST /v1/enter`
Begin. Issues a token, then either matches immediately or enqueues.

Request (`prefs` optional; v1 accepts and defaults it):
```json
{ "pushToken": "base64-apns-token-or-null", "prefs": { "form": "haiku" } }
```
`prefs` selects the match bucket. v1 only knows `haiku`, so any value resolves to the single bucket — but the slot exists so adding poem-type/language choice later is not a breaking change.

Response — matched immediately:
```json
{
  "participantToken": "…",
  "state": "matched",
  "session": { "sessionId": "…", "you": 1, "participantCount": 2, "status": "active",
               "form": { "id": "haiku", "targets": [5,7,5] },
               "currentLine": 0, "currentAuthor": 0, "yourTurn": false,
               "lines": [] }
}
```
The client renders structure from `form` (line count = `targets.length`, per-line nudge = `targets[currentLine]`). Participants are referenced by index: `you` is the caller's ordinal, `currentAuthor` is whose turn it is, and `yourTurn` is the server's `currentAuthor == you`. The client needs only `yourTurn`, `lines`, and `form` — so it is already agnostic to participant count and hardcodes nothing about haiku.
Response — enqueued:
```json
{ "participantToken": "…", "state": "waiting", "waitId": "…" }
```

### `GET /v1/waiting`
Poll while waiting (foreground) or after a match-ready push. Returns `waiting` or, once paired, the `matched` payload above (the session is created by whoever arrived second; the waiter learns here).

### `GET /v1/session/{id}`
Fetch current session state (poll while it's the partner's turn; also the return-to-poem entry point). Updates this side's `lastSeen`. Returns the session view (same shape as `session` above, with `lines` populated and `yourTurn` computed for the caller).

### `POST /v1/session/{id}/line`
Submit a line. Owner-only, current-turn-only.

Request (`line` is the zero-based index into the Form):
```json
{ "line": 0, "text": "an old silent pond", "idemKey": "client-uuid" }
```
Server validates, in order: token→session membership; `status == active`; `line == currentLine`; caller is the current author per the TurnPolicy; content checks (Section 8); idempotency. On success: appends the line, advances `currentLine` (or marks `complete` after the Form's last line), refreshes outer TTL, returns the updated session view, and fires a your-turn push to the next author if they're absent (Section 9).

Errors: `409 not_your_turn`, `409 wrong_turn`, `410 session_gone`, `422 content_rejected`, `429 rate_limited`.

### `POST /v1/session/{id}/leave`
Explicit leave. Dissolves the session; partner sees the gentle "they stepped away" conclusion on next fetch.

### `POST /v1/session/{id}/dismiss`
During `complete`: this side dismisses the reveal. When both have dismissed (or the 120s cap hits), the session dissolves.

### `POST /v1/session/{id}/continue` *(reserved, Section 13 — not built in v1)*
During `complete`: this side opts to start another poem with the same partner. When both opt in, poem-level fields reset and the encounter returns to `active`; otherwise it dissolves. Documented here so the contract has a stable slot; v1 does not implement it (the reveal always leads to dissolution).

### `POST /v1/report` *(Phase 5)*
```json
{ "sessionId": "…", "reason": "optional-short-string" }
```
Captures the poem content + minimal metadata to the moderation store before erasure, then dissolves the session. Available during `complete` and a brief grace window after.

### `GET /healthz` / `GET /metrics`
Liveness and metrics scrape.

`docs/api.md` is the maintained reference; keep it in sync with handlers.

---

## 8. Content Validation (server-side, non-meter)

Applied on every line submit. Never checks syllables.

* non-empty after trimming whitespace
* length ≤ `[TUNABLE]` **100** characters
* no control characters; normalize to NFC; collapse runs of whitespace
* reject if all-whitespace or zero-width-only
* (Phase 5) run through the basic abusive-content filter; reject with `422` so the worst material never reaches the partner's push

---

## 9. Push (APNs)

Token-based APNs (`.p8` auth key, key id, team id, bundle id) over HTTP/2. Two notification types:

* **match-ready** — to a waiting participant when paired while they're away. Body copy `[TUNABLE]`: *"Someone is here. Your poem is beginning."*
* **your-turn** — to the next author after a line is submitted, when they're absent (presence stale). Body copy `[TUNABLE]`: *"A line is waiting for you."*

Rules:
* never send if the target participant is currently present (fresh `lastSeen`)
* push payload carries `sessionId` only — no poem content, nothing identifying
* tapping a notification opens the app, which loads the token from Keychain and calls `GET /v1/session/{id}`
* APNs failures are logged and metered, never fatal to the session (a missed push degrades gracefully to "they'll see it next time they open the app")

`[DECISION]` content is never in the push body — preserves anonymity/ephemerality and avoids leaking poems to the lock screen.

---

## 10. iOS App

* **Target:** iOS 17+ `[DECISION]` (modern SwiftUI animation/transition APIs, `ContentUnavailableView`, observation).
* **No third-party dependencies** `[DECISION]` — URLSession, Security (Keychain), SwiftUI, UserNotifications only. Keeps it austere and review-clean.
* **Architecture:** one observable `AppModel` holding the current `AppState` enum; feature views are pure functions of state. Networking is an `actor`-based `APIClient` with async/await.

### Client state enum (mirrors §5)
`threshold → waiting → composing(view) → reveal(poem) → dissolved(reason)`
where `composing` carries: lines so far, whose turn, `yourTurn`, targets, partner-presence hint.

### Screens
| screen     | shows                                                                       |
|------------|------------------------------------------------------------------------------|
| Threshold  | the invitation + single "begin" action. No queue language.                  |
| Waiting    | quiet anteroom; ambient motion; "you can close this — we'll reach out." |
| Compose/mine | lines so far + input + live syllable hint + target for this line.        |
| Compose/theirs | lines so far + held-breath waiting state; "it's fine to put this down." |
| Reveal     | the full poem, centered, typographic; dismiss action.                        |
| Dissolved  | gentle conclusion (completed-and-gone, partner-left, or no-one-came).        |

### Networking & lifecycle
* Keychain stores `participantToken`; on cold launch, if present, call `GET /session/{id}` to resume (or clear if `410`).
* **Polling** `[TUNABLE]`: while foregrounded and it's the partner's turn or we're waiting, poll every **3s**; stop when backgrounded (push takes over) or when it becomes our turn.
* Register for remote notifications; send the APNs token on `enter`; refresh it via `/session` if it changes.
* Handle foreground notifications (show subtle in-app cue) and notification taps (resume via stored token).

### Syllables (on-device, `Syllables/`)
Vowel-cluster heuristic: lowercase, strip non-alpha, count contiguous vowel groups, subtract trailing silent "e", floor at 1 per word. Displayed as a small number next to the target. Guidance only; never blocks submit. The per-line target comes from the server's `form` descriptor (`form.targets[currentLine]`), not a hardcoded haiku — a `null` target shows no nudge, so free-verse and longer Forms need no client change.

### Design / motion / a11y (`Design/`)
* type scale built on Dynamic Type; poem remains beautiful at accessibility sizes
* `[DECISION]` system serif (`.serif` design) for the poem; sans for chrome
* transitions: deliberate, breath-paced; the **dissolution** is the signature animation
* honor **Reduce Motion** (cross-fade instead of dissolve)
* **VoiceOver**: announce turn handoff, partner-arrival, completion, dissolution via accessibility notifications
* soft haptic on partner's line arrival and on dissolution; nowhere else

---

## 11. Phased Task Breakdown

> **Current progress:** see [`docs/STATUS.md`](docs/STATUS.md). As of 2026-06-16: phases 0, 1, 3 done; 4 partial; 2, 5, 6 not started (2 & 6 blocked on an Apple Developer account).

Each phase ends in something runnable and verifiable. Phases 1–4 need no SQL and no Apple developer account beyond the device/simulator; Phase 5–6 need Apple/APNs credentials.

### Phase 0 — Scaffolding
- [ ] monorepo dirs (§3); Go module; `docker-compose.yml` with Redis; `Makefile` (run/test/lint)
- [ ] Go service boots, `/healthz` returns 200, connects to Redis, structured logging, env config
- [ ] Xcode project boots to an empty Threshold screen on simulator
- **Done when:** `make run` serves health check against local Redis; iOS app launches.

### Phase 1 — Backend core coordination (no push, no moderation)
- [ ] Redis repo for sessions + queue + tokens (§6), with the atomic match Lua script
- [ ] `sessions` state machine; pluggable `TurnPolicy` interface + `round-robin` impl; turn validation runs through the policy (§5)
- [ ] handlers: `enter`, `waiting`, `session/{id}`, `line`, `leave`, `dismiss` (§7)
- [ ] content validation (§8); idempotency; outer-TTL refresh; full teardown on dissolve
- [ ] unit tests (state machine, validation) + integration tests against real Redis (two-participant happy path, wrong-turn/not-your-turn, leave, expiry)
- **Done when:** a scripted two-client integration test completes a full A-B-A poem and observes clean dissolution; all state gone from Redis afterward.

### Phase 2 — APNs re-engagement
- [ ] `push` package: token-based APNs HTTP/2 client; sandbox + prod env
- [ ] capture push token on `enter`; store in session/queue records
- [ ] match-ready push on async pairing; your-turn push on submit when partner absent (§9)
- [ ] presence gating so present partners aren't pushed; metrics on send/success/failure
- **Done when:** with one client backgrounded, submitting a line delivers a your-turn push that deep-links back into the correct session.

### Phase 3 — iOS core loop
- [ ] `APIClient` actor + Codable models matching §7; Keychain token store
- [ ] `AppModel`/`AppState`; wire all six screens (§10) to real backend
- [ ] polling loop + background/foreground handling; resume-on-launch via stored token
- [ ] push registration + tap-to-resume + foreground-notification handling
- [ ] syllable hint
- **Done when:** two simulators/devices complete a full poem end to end — live (both foreground) and async (one backgrounded, pulled back by push) — including leave/return and expiry.

### Phase 4 — Pacing, motion, accessibility, copy
- [ ] transition timing pass; dissolution + reveal animations; Reduce Motion variants
- [ ] haptics (arrival, dissolution)
- [ ] Dynamic Type + VoiceOver announcements + focus management across states
- [ ] first real copy pass for threshold, both waiting states, return, dissolution (resolve relevant §21 open questions in brief)
- **Done when:** the arc *anticipation → intimacy → revelation → loss* is legible without explanation; VoiceOver narrates every state change; Reduce Motion path verified.

### Phase 5 — Safety rails (before widening TestFlight)
- [ ] rate limits: per-IP connect/enter, per-token submit (§6)
- [ ] basic abusive-content filter on submit (§8); `422` path
- [ ] `report` endpoint + Postgres `reports` table (the one durable store); capture-before-erase
- [ ] in-app report action during reveal + brief grace window
- [ ] EULA / objectionable-content agreement gate at first run (App Store UGC requirement)
- **Done when:** a reported poem is captured to Postgres before dissolution; abusive sample lines are rejected pre-push; rate limits trip under a load script.

### Phase 6 — Observability & deploy → TestFlight
- [ ] metrics (§ brief 18): active sessions, queue depth, match wait, completion rate, push success, abandonment, return rate
- [ ] deploy Go service + Redis (+ Postgres) to host `[TUNABLE]` (Fly.io / Render / small VM)
- [ ] APNs prod credentials; signing; archive; upload to TestFlight
- **Done when:** an internal TestFlight build completes a real cross-device poem over the network.

---

## 12. Testing Strategy

* **Go unit:** state machine transitions, turn/author validation, content validation. **`TurnPolicy` tests:** `round-robin` over 2 participants × 3 lines == haiku A-B-A, plus n=3/4 to lock the interface even though v1 never runs them.
* **Go integration:** real Redis (docker-compose); two-participant scenarios incl. races (two simultaneous `enter`s → exactly one session), idempotent resubmits, expiry/teardown, leave.
* **Load smoke:** a small Go script spinning N concurrent participants to watch queue depth, match latency, and that Redis memory returns to baseline after sessions end (no leaks).
* **iOS:** unit-test the syllable heuristic and the `AppState` reducer; manual two-device runbook for the full arc (the brief's "Done when" for Phase 3/4 is the script).
* **Anonymity assertions (test as invariants):** no endpoint ever returns the partner's token/pushToken/IP; push bodies contain no content; dissolved sessions leave zero Redis keys.

---

## 13. Extensibility & Forward Compatibility

This section exists so v1 doesn't foreclose the features that give the project room to grow. The rule: **v1 ships the simplest concrete behavior, but the data model and contracts are shaped as the *default case* of a more general structure** — so each feature below is additive (new data, new endpoint, new UI), not a migration of the core.

### Feature → seam map

| Future feature | What enables it | What v1 ships |
|----------------|-----------------|---------------|
| **Choose poem type / soft-nudge structure** (haiku, tanka, couplet, free verse) | `Form` is data and is *text-shape only* (§5): ordered lines, per-line nullable target. Runtime reads it from the Form; `lines` is a JSON array (§6); API returns the `form` descriptor; client renders what it's handed (§7, §10). | One Form (`haiku`); clients hardcode nothing. |
| **Alternate turn orders / round-robin poetry circles** | Authorship is a pluggable `TurnPolicy` (§5), decoupled from the Form, expressed over an *ordered participant list* with a derived author per line. Session stores `participants[]` + `policyId` + `startIndex` (§6); the API speaks participant *indices*, not A/B (§7). | One policy (`round-robin`) over 2 participants — which is exactly the haiku back-and-forth. |
| **Continue with this person** | Session = encounter ≠ poem (§5). Token bound to the encounter. Poem-level fields are resettable; reserved `continuing` status, `/continue` endpoint (§7), and `poemCount`. | One poem per encounter, then dissolve. |
| **Match preferences / language segmentation** | Bucketed queue `sw:queue:{bucket}` (§6); `enter` accepts optional `prefs`; `bucket` stored on wait + session records. | One bucket from the sole Form; `prefs` accepted and defaulted. |
| **Themes / seed prompts** | A poem-level attribute that travels with the Form/poem config and the session view. | Not present; the slot exists. |
| **Reactions / wordless acknowledgment at reveal** | Additive endpoint + poem-level field; no core change. | Not present. |

### "Continue together" — design sketch (reserved, not built)

When a poem reaches `complete`, both participants may be offered "stay together for another." Mechanics that keep it consistent with the brief's anonymity stance (`brief.v4.md` §7):

* **Mutual and live only.** Both must opt in within the reveal window; either declining (or staying silent) dissolves the encounter. Continuation extends the *current* connection — it never creates a handle to re-contact someone after the encounter ends.
* **State:** `complete → continuing` (awaiting both opt-ins) `→ active` with poem-level fields reset, `startIndex` re-randomized, `poemCount++`; or `→ dissolved`.
* **No identity leaks.** The same token/encounter is reused; nothing new about either person is exchanged or surfaced. When the encounter finally dissolves, it is gone — no re-contact, no history.
* **Abuse guard:** cap continuations per encounter `[TUNABLE]`; the 90-min outer bound still applies; either side can leave at any moment.

This is the one extension that touches the philosophy, so it is sketched deliberately rather than left implicit: a durable *connection* may be voluntarily extended; a durable *identity* still never forms.

### Multi-participant: turn logic is seam-reserved; the rest is not (yet)

This supersedes the earlier "two participants is a hard boundary" stance. The pieces that decide *authorship* are now N-ready: the `TurnPolicy` (§5), the ordered `participants[]` record (§6), and an API that speaks participant indices rather than A/B (§7). Round-robin over `n` participants is the *same code* that runs the 2-person back-and-forth.

What is **still 2-party and would need work to open up circles** — deliberately not built in v1:

* **Matchmaking** forms exactly a pair. Circles need either matching `n` waiters at once or an "open circle" people join until it's full/started — a different lifecycle (quorum, a start trigger, late-join rules).
* **Presence & liveness** assume two sides. With `n > 2`, "is everyone still here," what happens when one of several drops, and whether the poem continues with a gap are all open questions.
* **Push fan-out** targets one absent partner; circles push to whoever is next (already index-based) but the absence/timeout semantics multiply.

So: the turn-taking abstraction removes the *turn-logic* blocker cheaply and now, exactly as requested. Delivering circles later is then a matchmaking + presence + push effort, not a rewrite of how turns work.

---

## 14. Risks & Watch-items

* **App Store "block users" expectation vs. anonymity** (brief §13). Validate reviewer acceptance of report-only + device throttling *early* — before investing in a public submission. TestFlight first.
* **Hybrid feel on HTTPS polling.** If "both present" feels laggy in real use, that's the trigger to build the deferred WebSocket-foreground layer — not a v1 blocker.
* **Cold start / empty pool.** With low traffic, most entries wait. Push re-engagement is the mitigation; watch match-failure rate. A "no one came" fallback experience is an open brief question if this bites.
* **APNs token-auth setup friction** (keys, environments). Isolate behind the `push` package so the core loop (Phase 1) never depends on it.
* **Outer-bound vs. intimacy.** 90 min is a guess; treat completion-time distribution as the signal to retune.

---

## 15. First Move

Phase 0 + Phase 1 are the critical path and have no external dependencies (no Apple account, no APNs). Recommended start: scaffold the repo and build the backend coordination core with its integration test proving a full poem completes and dissolves cleanly. Everything else hangs off that contract.
