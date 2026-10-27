---
phase: 05-opt-in-robot-poet-collaboration
verified: 2026-10-27T19:00:00Z
status: human_needed
score: 17/17 must-haves verified
covered_files:
  - ".planning/phases/05-opt-in-robot-poet-collaboration/05-01-PLAN.md"
  - ".planning/phases/05-opt-in-robot-poet-collaboration/05-01-SUMMARY.md"
  - ".planning/phases/05-opt-in-robot-poet-collaboration/05-02-PLAN.md"
  - ".planning/phases/05-opt-in-robot-poet-collaboration/05-02-SUMMARY.md"
  - ".planning/phases/05-opt-in-robot-poet-collaboration/05-03-PLAN.md"
  - ".planning/phases/05-opt-in-robot-poet-collaboration/05-03-SUMMARY.md"
  - "ios/Strangewords/App/AppModel.swift"
  - "ios/Strangewords/App/SettingsStore.swift"
  - "ios/Strangewords/Features/Compose/ComposeView.swift"
  - "ios/Strangewords/Features/Compose/PartnerPresence.swift"
  - "ios/Strangewords/Features/Reveal/RevealView.swift"
  - "ios/Strangewords/Features/Settings/SettingsView.swift"
  - "ios/Strangewords/Features/Threshold/ThresholdView.swift"
  - "ios/Strangewords/Features/Waiting/WaitingView.swift"
  - "ios/Strangewords/Net/APIClient.swift"
  - "ios/Strangewords/Net/Backend.swift"
  - "ios/Strangewords/Net/LocalBackend.swift"
  - "ios/Strangewords/Net/Models.swift"
  - "ios/StrangewordsTests/AppModelTests.swift"
  - "ios/StrangewordsTests/FakeBackend.swift"
  - "ios/StrangewordsTests/LocalBackendTests.swift"
  - "ios/StrangewordsTests/PartnerPresenceTests.swift"
  - "ios/StrangewordsTests/SeamDefaultsTests.swift"
  - "ios/StrangewordsTests/SessionViewTests.swift"
  - "ios/StrangewordsTests/TestSupport.swift"
  - "server/internal/botplayer/botplayer.go"
  - "server/internal/botplayer/botplayer_test.go"
  - "server/internal/config/config.go"
  - "server/internal/gateway/bot_test.go"
  - "server/internal/gateway/gateway.go"
  - "server/internal/matchmaker/matchmaker.go"
  - "server/internal/metrics/metrics.go"
  - "server/internal/sessions/session.go"
  - "server/internal/store/store.go"
covered_digest: "v3:sha256:76ad929d602d8a1e07972628a3402508bfad71cca82bc0d0499e1194be7e0a87"
behavior_unverified: 0
overrides_applied: 0
advisory:
  - finding: "WR-01: PairWithBot claims the waiter (LREM) before SaveSession/SetRef/DelWait; a Redis error after the claim strands the waiter until WaitTTL (15 min)"
    category: other
    reason: "Failure-injection path only (Redis blip), opted-in users only; no goal truth asserts recovery. Logged open in 05-REVIEW-DISPOSITION.md and queued as first follow-up"
    evidence_status: "reviewed in 05-REVIEW.md; no Go test for the failure path"
  - finding: "WR-02: touchPresence and handleLine's idempotency re-save are blind SaveSession writers that bypass UpdateSession's WATCH protection (can resurrect a dissolved session for up to SessionTTL, or drop a bot line when SW_BOT_THINK_MS is tiny)"
    category: other
    reason: "Pre-existing CONCERNS.md known bug that Plan 01 explicitly scoped out (settleBot itself is race-safe and tested). Window is small; resurrected data is TTL-bounded and unreachable (tokens deleted)"
    evidence_status: "reviewed in 05-REVIEW.md; no deterministic repro test"
human_verification:
  - test: "Backgrounded-human pacing against a real server: opt in, get paired with the robot poet, background the app mid-poem, return"
    expected: "The robot poet's pending line appears within one think time plus one poll interval of returning (bot lines advance only on the human's polls; no push is sent for the bot)"
    why_human: "Backstop truth (05-01): real-device pacing and push-out-of-scope behaviour cannot be asserted by an automated test"
  - test: "Run ./run.sh --mock on a simulator and check the Settings gear, sheet and chip across 3 themes x 3 times of day (SW_FORCE_THEME / SW_FORCE_TOD), with and without SW_DEV=1"
    expected: "Gear sits top-leading on the 28pt margin clear of the top-trailing dev chips; the sheet opens at medium with a drag indicator, opaque skyBottom background and readable ink in all 9 palettes (confirms research assumption A2, sheet environment inheritance); toggle persists across relaunch; with it on the waiting room shows the soft line and after 25s the robot poet joins; the chip shows in Compose on both turns and in Reveal and wraps at accessibility Dynamic Type"
    why_human: "Backstop truth (05-03): layout, contrast and sheet rendering can only be confirmed visually; no XCUITest per REQUIREMENTS.md. iPad form-sheet sizing (maxWidth 480) is also unexercised"
  - test: "VoiceOver pass in a robot-poet session"
    expected: "Gear reads 'Settings' with hint; switch reads 'Write with the robot poet, switch button, off'; close reads 'Close settings'; chip reads 'Your partner is the robot poet, software on our server, not a person.'; 'You're now writing with the robot poet.' is announced exactly once when Compose appears"
    why_human: "Backstop truth (05-03): strings are unit-tested but spoken behaviour is not"
  - test: "Judgment review of prohibition: 'MUST NOT describe the robot poet as a person, a stranger or someone, soften or hide the disclosure, or nudge users to opt in (no prompts, badges, timers or default-on)'"
    expected: "No screen, copy or theme nudges toward opt-in or softens the disclosure. Verifier's non-authoritative read: PASS. The only nudge-adjacent surface is the waiting soft line, shown only to users who already opted in; the gear has no badge; the toggle defaults OFF. The robot-partner strings were checked by unit tests (voice rule, never 'stranger'/'someone'), though the waiting line and settings helper say 'a robot poet ... not a person'"
    why_human: "Judgment-tier prohibition: LLM verdict is non-authoritative and flagged unverified-prohibition, human review recommended (ADR-550 D4)"
---

# Phase 5: Opt-in robot poet collaboration - Verification Report

**Phase Goal:** A user can opt in (default OFF) to being paired with the robot poet when no human is waiting. Wire-contract flag on POST /v1/enter (allowBot); matchmaker segregation so the bot only ever pairs with opted-in participants; the app's first Settings surface with the persisted toggle; bot disclosure in the session UI; LocalBackend mirrors the new contract; tests on both sides. Locked decisions: strict opt-in default OFF; bot disclosed in-session; generation uses server/internal/poet (no external AI).
**Verified:** 2026-10-27
**Status:** human_needed
**Re-verification:** No - initial verification

The code delivers the goal. Every truth that can be checked from the codebase is verified against the code and against tests I re-ran. `human_needed` is only because the plans themselves declared three backstop truths (visual/VoiceOver/real-device pacing) and one judgment-tier prohibition that no automated check can resolve. There are no gaps.

## Goal Achievement

### Observable Truths

ROADMAP success criteria were not separately enumerated for this phase beyond the goal sentence, so the goal clauses and the PLAN `must_haves` form the contract.

| #  | Truth | Status | Evidence |
| -- | ----- | ------ | -------- |
| 1  | (Goal) Wire flag `allowBot` on POST /v1/enter, fail-closed | VERIFIED | `gateway.go:101` `AllowBot bool json:"allowBot"`; lenient decode line unchanged (`gateway.go:116`); `matchmaker.enqueue` stores it on `WaitEntry.AllowBot` (`matchmaker.go:57`). `TestBotNeverPairsWithoutOptIn` (nil, `{}`, false, "true" string, 1) PASS under -race |
| 2  | Opted-in waiter whose poll lands at/after BotWindow (25s) is bot-paired; 1ms earlier still waits | VERIFIED | `gateway.go:172` window check + `PairWithBot`; `ClaimWaiter` LREM (`store.go:159`). `TestBotFallbackTracer` PASS (re-run) |
| 3  | `partnerIsBot` appears on every view of a bot session, omitted for human sessions, computed only in `ViewFor` | VERIFIED | `session.go:106,124-140` (`omitempty`, derived from `Participant.Bot` at other index); no `PartnerIsBot` reference in gateway.go (not client-derived). Tracer asserts raw `"partnerIsBot":true`; overlap test asserts key absent for humans |
| 4  | Old clients / non-opted-in never get the bot; no `sw:sess:` key created | VERIFIED | `TestBotNeverPairsWithoutOptIn` 6 subtests PASS (incl. plain arrival after a bot pairing) |
| 5  | Overlapping opted-in humans pair together (matchmaker segregation) | VERIFIED | Bot is never a queue member (tokenless pre-dismissed participant created only in `PairWithBot`). `TestOverlappingOptedInHumansPairTogether` PASS (one sess key, BotPaired +0, Matched +1) |
| 6  | Human-vs-bot race at window boundary never yields two sessions | VERIFIED | LREM vs LPOP atomicity; `TestHumanVsBotRaceSingleSession` 50 iterations PASS under -race |
| 7  | Robot poet writes own lines on the human's polls: think time honoured, one line per settle, CleanLine-clean, on syllable target, both start orders | VERIFIED | `botplayer.NextLine` + `settleBot` (`gateway.go:442`); `TestBotPoemCompletesAndLeavesNoKeys`, `TestNextLineIsCleanAndOnTarget` PASS |
| 8  | Restart mid-poem yields identical next bot line | VERIFIED | Stateless replay seeded by FNV-1a of session id; `TestNextLineReplaysDeterministically` and restart rig in poem test PASS |
| 9  | A bot settle never persists over newer state (stale load writes nothing; in-window write -> ErrConflict) | VERIFIED | `UpdateSession` WATCH/MULTI/EXEC mapping `redis.TxFailedErr` -> `ErrConflict` (`store.go:229-262`); `settleBot` writes only through it; `TestStaleSettleDoesNotOverwriteHumanLine` PASS under -race |
| 10 | After the human's single dismiss a bot session dissolves (410) with zero `sw:` keys | VERIFIED | Bot pre-dismissed; wait entry deleted at claim (`matchmaker.go` DelWait); poem test asserts 410 and no `sw:` keys |
| 11 | `SW_BOT_WAIT_SECONDS <= 0` disables the robot poet | VERIFIED | `s.cfg.BotWindow > 0` guard; `TestBotFallbackDisabledByKillSwitch` PASS |
| 12 | Backgrounded human sees bot line within one think time + one poll of returning | ? UNCERTAIN (backstop) | Plan-declared backstop truth; routed to human verification below |
| 13 | iOS: default OFF, persisted in `SettingsStore` outside `sw.` namespace; `begin()` sends the user's choice; `APIClient` always sends `allowBot` | VERIFIED | `SettingsStore.swift` (`pref.allowBot`, `defaults.bool` -> false when absent); `AppModel.swift:49,103,109` (didSet write-through, `let allow = allowBot` captured, `enter(pushToken:nil, allowBot: allow)`); `APIClient.swift:59` `body["allowBot"] = allowBot`; only 2 `"sw.` literals in app; `HostIsolationTests.swift` unmodified in this phase. Tests `beginSendsHumansOnlyByDefault`, `optInTravelsAndPersists`, `settingsStore*` passed in the recorded run |
| 14 | iOS: `SessionView` decodes `partnerIsBot` tolerantly (absent -> false), memberwise default false | VERIFIED | `Models.swift:17,32-52` `decodeIfPresent ?? false`; tests `decodesPartnerIsBotWhenPresent`, `partnerIsBotDefaultsFalseWhenAbsent`, `memberwiseDefaultsPartnerIsBotFalse` |
| 15 | LocalBackend mirrors contract (non-opted: immediate match, no bot; opted-in: waits, then matched with partnerIsBot true) | VERIFIED | `LocalBackend.swift` `defaultBotWindow = 25`, `waitingSince`, `partnerIsBot`, DRIFT notes; `Backend` protocol, `APIClient`, `LocalBackend`, `FakeBackend` all take `allowBot`; zero `enter(pushToken: nil)` one-arg calls remain; tests `notOptedIn...`, `optedInWaits...`, `optedInStillWaiting...` passed |
| 16 | Settings surface: top-leading gear -> sheet with the single toggle bound to `AppModel.allowBot`, environment re-injected | VERIFIED (structure) | `ThresholdView.swift` overlay `.topLeading`, `.sheet`, detents, `presentationBackground(palette.skyBottom)`, `.environment(\.sceneTheme, theme)`; `SettingsView.swift` `Toggle(isOn: $model.allowBot)`, `.tint(palette.accent)` the only accent use. Rendering itself is a backstop item (below) |
| 17 | Bot disclosure in session UI: chip in Compose and Reveal from `session.partnerIsBot`, honest their-turn copy, waiting soft line only when opted in, copy voice-rule tested | VERIFIED (wiring + copy) | `ComposeView.swift:15,45,114`, `RevealView.swift:15`, `WaitingView.swift:28,47` all route through `PartnerPresence` pure functions; `PartnerPresenceTests` (15 tests) all passed incl. voice rule and nil-caption-for-humans |

**Score:** 17/17 must-haves verified (truth 12 and the visual/VoiceOver backstops are carried as human-verification items rather than failed)

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `server/internal/store/store.go` | `AllowBot`, `ClaimWaiter`, `UpdateSession`, `ErrConflict` | VERIFIED | All present; `"sw:` literal count still 5 (no new key namespace) |
| `server/internal/matchmaker/matchmaker.go` | opt-in carried; `PairWithBot` | VERIFIED | Claim-before-build; DelWait at claim |
| `server/internal/sessions/session.go` | `Participant.Bot`, `BotReadyAt`, `PartnerIsBot`, `AuthorOf`, `BotTurn` | VERIFIED | |
| `server/internal/botplayer/botplayer.go` | `Seed`, `NextLine` | VERIFIED | Imports only `hash/fnv`, `poet`, `sessions`; no net/redis/os imports (D-05, no external AI) |
| `server/internal/gateway/gateway.go` | allowBot decode, fallback, `settleBot`, push skip for bots | VERIFIED | One `go` statement (janitor) - no new goroutines/workers |
| `server/internal/gateway/bot_test.go` | tracer, poem, stale-settle, invariants, race | VERIFIED | 7 top-level tests PASS under -race |
| `server/internal/config/config.go`, `metrics/metrics.go` | `SW_BOT_WAIT_SECONDS`, `SW_BOT_THINK_MS`, `sw_bot_paired_total` | VERIFIED | `[TUNABLE]` markers present |
| `ios/.../SettingsStore.swift` | `pref.allowBot` | VERIFIED | |
| `ios/.../Models.swift`, `Backend.swift`, `APIClient.swift`, `LocalBackend.swift`, `FakeBackend.swift` | contract mirror | VERIFIED | |
| `ios/.../SettingsView.swift`, `PartnerPresence.swift`, `PartnerPresenceTests.swift` | UI + copy tests | VERIFIED | |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | -- | --- | ------ | ------- |
| gateway.handleEnter | matchmaker.Enter | `s.mm.Enter(..., req.AllowBot, ...)` | WIRED | `gateway.go:122` |
| gateway.handleWaiting | matchmaker.PairWithBot | window check | WIRED | `gateway.go:172-173` |
| matchmaker.PairWithBot | store.ClaimWaiter | claim before build | WIRED | `matchmaker.go:112` |
| store.ClaimWaiter | Redis | `LRem(ctx, queueKey(...), 1, id)` | WIRED | `store.go:160` |
| gateway.settleBot | botplayer.NextLine | append replayed line | WIRED | `gateway.go:453` |
| gateway.settleBot | store.UpdateSession | CAS write only | WIRED | `gateway.go:448`; no direct Save in settleBot |
| store.UpdateSession | Redis | `rdb.Watch` | WIRED | `store.go:231` |
| botplayer | poet | `poet.New(Seed(...))` | WIRED | `botplayer.go:34` |
| AppModel | SettingsStore | `settings.allowBot = allowBot` | WIRED | `AppModel.swift:50` |
| AppModel.begin | Backend.enter | `enter(pushToken: nil, allowBot: allow)` | WIRED | `AppModel.swift:109` |
| APIClient | POST /v1/enter | `body["allowBot"]` | WIRED | `APIClient.swift:59` |
| ThresholdView | SettingsView | `.sheet(isPresented: $showSettings)` | WIRED | |
| SettingsView | AppModel | `Toggle(isOn: $model.allowBot)` | WIRED | |
| ComposeView / RevealView | PartnerPresence | `caption(partnerIsBot: session.partnerIsBot, ...)` | WIRED | |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| Compose/Reveal chip | `session.partnerIsBot` | Server `ViewFor` (Participant.Bot set only in `PairWithBot`) -> JSON -> tolerant decode; LocalBackend in mock | Yes | FLOWING |
| Waiting soft line | `model.allowBot` | `SettingsStore` (UserDefaults) via toggle | Yes | FLOWING |
| `enter` body `allowBot` | `AppModel.allowBot` captured in `begin()` | persisted toggle | Yes | FLOWING |
| Bot poem lines | `botplayer.NextLine(session)` | `server/internal/poet` replay | Yes (CleanLine-checked, fallback constant) | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Full Go suite | `cd server && go test ./... -count=1` | all packages ok | PASS |
| vet / gofmt | `go vet ./...`; `gofmt -l .` | no output | PASS |
| Bot invariants under race detector | `go test ./internal/gateway ./internal/botplayer -race -run 'TestBot\|TestHuman\|TestOverlapping\|TestStale\|TestSeed\|TestNextLine\|TestFallback'` | 11/11 PASS | PASS |
| iOS suite | Not re-run (several minutes, boots simulator). Recorded evidence `build/verify/green2-05-03/ios-verdict.txt`: PASS 93 passed / 0 failed / 1 skipped (the skip is the intentional `failsOnPurpose` harness canary). Its `xcodebuild-1.log` shows the new Phase 5 tests passed. `git diff c58be8e HEAD -- ios server` is empty and the working tree has no ios/server changes, so source equals what was tested | PASS (cited) | PASS |

### Probe Execution

SKIPPED: the phase declares no probe scripts, and none are referenced by the plans.

### Requirements Coverage

All seven IDs appear in PLAN frontmatter and in REQUIREMENTS.md (lines 43-49, marked `[x]`, traceability table "Complete"). No orphaned Phase 5 requirements.

| Requirement | Source Plan(s) | Description | Status | Evidence |
| ----------- | -------------- | ----------- | ------ | -------- |
| P5-OPTIN | 05-01, 05-02, 05-03 | Opt-in only, default OFF, absent/false/malformed -> humans only | SATISFIED | Truths 1, 4, 13; `TestBotNeverPairsWithoutOptIn`, `beginSendsHumansOnlyByDefault` |
| P5-FALLBACK | 05-01 | Human first, bot after ~25s window, overlap pairs humans, race-safe, lines from poet, never overwrite newer line | SATISFIED | Truths 2, 5, 6, 7, 9, 11 |
| P5-DISCLOSE | 05-01, 05-02, 05-03 | `partnerIsBot` server-only, tolerant decode, named presence in Compose and Reveal | SATISFIED | Truths 3, 14, 17 (visual rendering in human items) |
| P5-ANON | 05-01 | Opt-in only on TTL wait entry, no new keys/locks, zero `sw:` keys after dissolve, pref outside identity namespace | SATISFIED | Truths 10, 13; `sw:` literal count 5 unchanged; HostIsolationTests unmodified. Caveat: WR-02 resurrection path (advisory) |
| P5-SETTINGS | 05-02, 05-03 | Gear -> sheet with one toggle persisted in TokenStore sibling | SATISFIED | Truths 13, 16 (visual rendering in human items) |
| P5-PARITY | 05-02 | Contract mirrored in Models, Backend, APIClient, LocalBackend, FakeBackend | SATISFIED | Truth 15 |
| P5-TESTS | 05-01, 05-02, 05-03 | Go and Swift Testing proof for each behavior | SATISFIED | Go re-run green; iOS 93/0/1 recorded at unchanged source |

### Prohibitions (ADR-550)

| Prohibition | Tier | Result |
| ----------- | ---- | ------ |
| Never pair bot with a participant who did not send `allowBot` true; bot never a queue member | test | HELD: segregation tests + structural (bot only created in `PairWithBot`) |
| `partnerIsBot` never derived from client input | test | HELD: only in `ViewFor` from `Participant.Bot`; absent from gateway request handling |
| No external AI / network service for bot lines | test | HELD: `botplayer.go` imports only `hash/fnv`, `poet`, `sessions` |
| No new Redis keys/locks/workers/durable state | test | HELD: `"sw:` literal count 5; one `go` statement in gateway.go; zero-keys assertion after dissolve. WATCH adds no key |
| iOS: never send `allowBot` true unless toggled | test | HELD: `beginSendsHumansOnlyByDefault` |
| iOS: preference outside `sw.` namespace, not cleared with token | test | HELD: `settingsStoreIsolatesAndSurvivesTokenClear`, `settingsStoreKeyIsOutsideSessionNamespace` |
| iOS: never compute/infer partner-is-robot client-side | test | HELD: chip derives only from `session.partnerIsBot` (grep: Compose/Reveal call sites) |
| iOS: never call robot a person/stranger, soften disclosure, or nudge opt-in | judgment | FLAGGED `unverified-prohibition - human review recommended`; non-authoritative verifier read: PASS (see human item 4) |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| (all 21 modified source files) | - | TBD/FIXME/XXX/TODO/HACK scan | None | Zero matches; no debt markers |
| `server/internal/matchmaker/matchmaker.go` | 111-147 | Post-claim steps not recoverable (WR-01) | Warning | Stranded waiter on Redis error; advisory, open in disposition ledger |
| `server/internal/gateway/gateway.go` | 496-504, 306-311 | Blind `SaveSession` after `settleBot` (WR-02) | Warning | Pre-existing, deliberately out of scope; small window; TTL-bounded |
| `server/internal/sessions/session.go` | 82-89 | `IndexForToken("")` matches bot (IN-01) | Info | Latent only; empty token 410s at `GetRef` |

### Human Verification Required

#### 1. Backgrounded-human pacing on a real server

**Test:** Opt in, get bot-paired, background the app mid-poem, return.
**Expected:** The bot's pending line appears within one think time plus one poll interval of returning.
**Why human:** Backstop truth; real-device timing, push is out of scope.

#### 2. Visual pass in mock mode

**Test:** `./run.sh --mock`, across 3 themes x 3 times of day, with and without `SW_DEV=1`.
**Expected:** Gear top-leading and clear of dev chips; sheet at medium with opaque `skyBottom` background and readable ink in all 9 palettes; toggle persists across relaunch; soft line while waiting; robot poet joins after 25s; chip visible in Compose (both turns) and Reveal; wraps at accessibility Dynamic Type. Check iPad form-sheet sizing.
**Why human:** Backstop truth; no XCUITest, and sheet environment inheritance (research A2) is only visually confirmable.

#### 3. VoiceOver pass

**Test:** Walk gear, switch, close, chip, and Compose arrival in a robot-poet session.
**Expected:** Labels as specified; the arrival announcement fires once.
**Why human:** Backstop truth; spoken behaviour is not unit-testable.

#### 4. Judgment prohibition sign-off (no nudging / disclosure never softened)

**Test:** Read the gear, sheet, waiting line and chip copy as a user would.
**Expected:** Nothing pushes opt-in or implies the robot is a person.
**Why human:** Judgment-tier prohibition; verifier verdict is non-authoritative.

### Gaps Summary

No gaps. The server half is implemented and proven by re-run tests (full suite, vet, gofmt clean; bot invariants pass under the race detector). The iOS half is implemented and wired end to end, with the 93/0/1 result taken from recorded evidence on source identical to HEAD. Status is `human_needed` solely for the four items above. Two open warnings (WR-01 stranded waiter on a post-claim Redis error, WR-02 pre-existing blind savers) are advisory and recorded in `05-REVIEW-DISPOSITION.md`; I recommend scheduling them before App Store submission, as the disposition ledger already states.

---

_Verified: 2026-10-27_
_Verifier: Claude (gsd-verifier)_
