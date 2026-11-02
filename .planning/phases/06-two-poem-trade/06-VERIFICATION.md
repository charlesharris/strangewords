---
phase: 06-two-poem-trade
verified: 2026-11-02T18:40:00Z
status: passed
score: 9/9 must-haves verified
covered_files:
  - .planning/phases/06-two-poem-trade/06-01-PLAN.md
  - .planning/phases/06-two-poem-trade/06-01-SUMMARY.md
  - .planning/phases/06-two-poem-trade/06-02-PLAN.md
  - .planning/phases/06-two-poem-trade/06-02-SUMMARY.md
  - .planning/phases/06-two-poem-trade/06-03-PLAN.md
  - .planning/phases/06-two-poem-trade/06-03-SUMMARY.md
  - ios/Strangewords/App/AppModel.swift
  - ios/Strangewords/Features/Dissolved/DissolvedView.swift
  - ios/Strangewords/Features/Reveal/RevealView.swift
  - ios/Strangewords/Features/Reveal/TradeBack.swift
  - ios/Strangewords/Naming/PoemNaming.swift
  - ios/Strangewords/Net/APIClient.swift
  - ios/Strangewords/Net/LocalBackend.swift
  - ios/Strangewords/Net/Models.swift
  - server/internal/botplayer/botplayer.go
  - server/internal/gateway/gateway.go
  - server/internal/gateway/privacy.html
  - server/internal/sessions/session.go
  - server/internal/store/store.go
covered_digest: "v3:sha256:8d0c472cd465afd64cc6a1747e541edb6c14794cf12aa45470c83566f0bd5dba"
behavior_unverified: 0
overrides_applied: 0
re_verification: false
advisory:
  - finding: "A reveal-state save (an offer, or the dismiss compare-and-set) resets the session TTL to the full RevealTTL, so a finished poem can outlive the privacy page's 'two-minute reveal window' by up to roughly one more window (WR-02)"
    category: other
    reason: "State stays TTL-bounded and ephemeral; this is copy-versus-behavior drift, not a leak. Dismiss already behaved this way before Phase 6. Tracked in .planning/todos/pending/2026-11-02-reveal-ttl-reset-vs-privacy-wording.md"
    evidence_status: "code read (gateway.go:441, :506); no failing test"
  - finding: "A failed or transient trade tap (503 busy, 404, transport) and a stale reveal poll give the user no feedback (WR-03)"
    category: other
    reason: "Fail-safe: the reveal stays and the default path (let it go) is untouched. Tracked in .planning/todos/pending/2026-11-02-trade-tap-and-poll-silent-failures.md"
    evidence_status: "code read (AppModel.swift:235-237, :423-425)"
---

# Phase 6: Two-Poem Trade Verification Report

**Phase Goal:** An encounter can become a two-poem trade. After poem 1's reveal, either participant may offer to trade back; when both accept, poem 2 begins in the same session with the start roles swapped. Reveal happens after each poem; declining or leaving dissolves as today. The robot poet trades too (accepts automatically, continues its deterministic replay). Keepsakes become one coined name per poem, and the keepsake's kind line is removed everywhere. LocalBackend mirrors the full trade arc; tests on both sides.
**Verified:** 2026-11-02
**Status:** passed (all automatable truths hold; manual UAT is deferred by milestone constraint and listed below)
**Re-verification:** No, initial verification

## Goal Achievement

### Observable Truths (ROADMAP goal and PLAN must-haves)

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | Either participant can offer; poem 2 begins in the same session only when every participant has asked | VERIFIED | `handleTrade` (gateway.go:468-531) sets the caller's `WantsTrade` on the WATCHed fresh read and calls `BeginNextPoem` only when `AllWantTrade()` (gateway.go:492-493); `TradeOpen()` (session.go:93) gates it. `TestTradeTracer` (trade_test.go:103) walks offer, partner view, accept, poem 2 active/empty, `SessionTTL` restored. |
| 2  | Roles swap for poem 2 (whoever wrote lines 1 and 3 of poem 1 writes line 2 of poem 2), derived from `StartIndex` plus the poem ordinal, not a policy change | VERIFIED | `poemStart()` = `(StartIndex + max(PoemCount-1,0)) % n` feeding `AuthorOf` (session.go:74-88); `StartIndex` and policy are untouched. Tracer asserts poem 2 authors `[other, opener, other]` (trade_test.go:170); `TestPoemTwoSwapsRoles` in sessions. |
| 3  | Each poem gets its own reveal; at most two poems; no third poem | VERIFIED | `MaxPoems = 2` (session.go:33); `TradeOpen` is false when `PoemCount >= MaxPoems`; tracer asserts poem 2's view omits `tradeOpen` and a further `/trade` returns 409 `trade_closed` (trade_test.go:177-185). |
| 4  | Declining (let it go), leaving, or lapsing dissolves as today; an old client that never calls `/trade` is never pulled into poem 2 | VERIFIED | `handleDismiss` (gateway.go:409-460) clears the caller's `WantsTrade`, which makes `TradeOpen` false for the partner; a dismiss landing after poem 2 began dissolves (DEC-06-01). Tests: `TestTradeDeclinedByLettingGo`, `TestDismissAfterPoemTwoBeganDissolves`, `TestDismissDuringPoemOneKeepsHeadSemantics`, `TestOldClientNeverTrades`. The offer is stored under `RevealTTL` (gateway.go:506), so there is no new timer. |
| 5  | Races are safe: two concurrent accepts start one poem 2; a let-go racing an accept never reverts poem 2 or resurrects a dissolved session | VERIFIED | All three trade paths use the bounded CAS helper `updateSession` (gateway.go:707, `casAttempts = 3`). `TestConcurrentAcceptsBeginOnePoem` and `TestAcceptVersusLetGoRace` pass, including under `-race` (rerun this verification). |
| 6  | The robot poet accepts only after `BotThink` (never on the immediate poll), then writes poem 2 from a replay seeded by session id plus poem number; a restart changes nothing | VERIFIED | `settleBot` (gateway.go:626-696) gates on `now >= BotReadyAt` and `BotTradeDue()`; `handleTrade` arms `BotReadyAt` only on the first write (gateway.go:500-505). `PoemSeed` (botplayer.go:34) is pure in id and poem, with poem 1 keeping `Seed`. `TestBotTradesBack` (both start orders) checks the immediate poll, 1 ms early, a `b.restart`, then poem 2 playthrough with `CleanLine`-identical, on-target bot lines, and zero `sw:` keys at the end. |
| 7  | Anonymity: no new identifier or key class; poem 1's lines and retry cache erased when poem 2 begins; zero `sw:` keys after dissolution | VERIFIED | `grep -c '"sw:' store.go` = 5 (queue, wait, tok, sess, idem); `DeleteIdem` reuses `idemKey` (store.go:372); `BeginNextPoem` resets `Lines` (session.go:162); `purgePoemCache` is called on both begin paths (gateway.go:528, :693). Tracer asserts 3 idem keys before and 0 after the trade, and `assertEncounterGone` after dismissal. |
| 8  | Wire tolerance both ways | VERIFIED | Go: `omitempty` on all four new `View` fields (session.go:216-219). iOS: `decodeIfPresent ... ?? default` for all four (Models.swift:68-71); `SessionViewTests` pins the old-server and omitted-false decodes. `RevealView` and `AppModel.tradeBack`/`pollReveal` act only on the server's `tradeOpen`, so an old server never shows or polls a trade. |
| 9  | Parity: `Backend.tradeBack` in protocol, `APIClient`, `LocalBackend`, `FakeBackend`; mock mode walks the full arc | VERIFIED | Backend.swift:34, APIClient.swift:84-88 (`POST /v1/session/{id}/trade`, decodes `SessionView`), LocalBackend.swift:197-208 plus `settleTrade`/`beginNextPoem` (roles swapped, 5-syllable lines for 5-syllable slots, robot poet accepts but never offers), FakeBackend.swift:125. 29 `LocalBackendTests`, including `tradeBackSwapsRolesIntoPoemTwo` and `tradeBackOutsideAnOpenTradeIsRejected`. |
| 10 | UI: quiet "trade back" beside "let it go", only while the server says open; caption for waiting/passed; pure, test-pinned strings; robot-poet copy names the robot poet | VERIFIED | `TradeBack.offer` is a pure function of `tradeOpen/youWantTrade/partnerWantsTrade` (TradeBack.swift:19); `RevealView` renders the button only via `TradeBack.showsButton` and calls `model.tradeBack()` (RevealView.swift:41-56). Robot strings say "the robot poet" and humans' say "the stranger". `TradeBackTests` (7) pin copy; `PartnerPresenceTests` carries the voice rule. A reveal with no open trade maps to `.none`: no caption, no button. |
| 11 | Keepsakes: one coined name per completed poem; poem 1's coined while its lines are in hand as poem 2 begins; `CoinedName.kind` and its line removed everywhere, goldens lose a column but no name or lead changes | VERIFIED | `CoinedName` has only `lead` and `name` (PoemNaming.swift:10-14); no `kind` or "scented candle" remains in `Naming/`, `Features/Dissolved/` or `AppModel.swift`. `AppModel.apply` coins on `s.poemNumber > outgoing.poemNumber` (AppModel.swift:335-338); `finishDissolving` coins the last (:274-279). `git show 7295325` shows the golden diff removes only `kind:` values. Keepsakes are in memory only, cleared by `begin()`/`reset()` (:122, :302); `Keychain.swift` is still the only `"sw.` literal pair (2). |
| 12 | Tests on both sides, no wall-clock sleeps | VERIFIED | Go: no `time.Sleep` in the trade, sessions-trade or botplayer tests (fake clock). iOS: gated `FakeBackend` tests, no trade-related sleeps. Counts and results under Behavioral Spot-Checks. |

**Score:** 9/9 requirements verified (12/12 truths); 0 present-but-behavior-unverified.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `server/internal/sessions/session.go` | `WantsTrade`, `MaxPoems`, `TradeOpen`, `BeginNextPoem`, `poemStart`, View trade fields | VERIFIED | All present and used (session.go:25-33, 74-169, 212-262) |
| `server/internal/gateway/gateway.go` | `POST /v1/session/{id}/trade`, CAS helper, `settleBot` accept, CAS dismiss | VERIFIED | Route at gateway.go:63; `handleTrade` :468; `settleBot` :626; `updateSession` :707 |
| `server/internal/store/store.go` | `DeleteIdem` | VERIFIED | store.go:372, wired from `purgePoemCache` |
| `server/internal/botplayer/botplayer.go` | `PoemSeed` | VERIFIED | botplayer.go:34, used by `NextLine` at :50 |
| `server/internal/metrics/metrics.go` | trade counters | VERIFIED | `TradesOffered`/`TradesBegun` incremented in gateway.go and asserted in tracer and bot tests |
| `server/internal/gateway/privacy.html` | second-poem disclosure | VERIFIED | Line 75; effective date 2026-11-02 (line 59); `TestPrivacyPageMatchesCode` requires "second poem" |
| `ios/Strangewords/Net/Models.swift` | tolerant trade fields | VERIFIED | Models.swift:24-30, 48, 68-71 |
| `ios/Strangewords/Net/{Backend,APIClient,LocalBackend}.swift`, `StrangewordsTests/FakeBackend.swift` | `tradeBack` mirrored | VERIFIED | See truth 9 |
| `ios/Strangewords/App/AppModel.swift` | `tradeBack()`, `pollReveal`, hardened `release()`, `keepsakes` | VERIFIED | :216, :405, :262, :46 |
| `ios/Strangewords/Features/Reveal/TradeBack.swift`, `RevealView.swift` | pure mapping and affordance | VERIFIED | See truth 10 |
| `ios/Strangewords/Features/Dissolved/DissolvedView.swift` | one block per keepsake, no category | VERIFIED | DissolvedView.swift:19-73 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `handleTrade` | `store.UpdateSession` | `s.updateSession` | WIRED | gateway.go:476; same helper used by `handleDismiss` (:416) |
| `Session.AuthorOf` | `PoemCount` | `poemStart()` | WIRED | session.go:75, 82-88 |
| `botplayer.NextLine` | `PoemSeed` | `poet.New(PoemSeed(s.ID, s.PoemCount))` | WIRED | botplayer.go:50 |
| `APIClient.tradeBack` | server `/trade` | `send("POST", ".../trade")` | WIRED | APIClient.swift:85 |
| `AppModel.apply` | `pollReveal` | complete view with `tradeOpen` | WIRED | AppModel.swift:349 |
| `AppModel.release` | epoch / `stopPolling` | bump and stop | WIRED | AppModel.swift:264-265 |
| `RevealView` | `AppModel.tradeBack()` | button action | WIRED | RevealView.swift:52 |
| `RevealView` | `TradeBack.offer` | server fields only | WIRED | RevealView.swift:18-20 |
| `AppModel.apply` | `PoemNaming.coin` | outgoing reveal's lines | WIRED | AppModel.swift:335-337 |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| `RevealView` trade button and caption | `session.tradeOpen/youWantTrade/partnerWantsTrade` | `Session.ViewFor` computed from stored `WantsTrade` flags and `TradeOpen()`, decoded in `Models.swift` | Yes | FLOWING |
| `DissolvedView` | `model.keepsakes` | `PoemNaming.coin(from:)` over the outgoing poem's lines in `AppModel` | Yes | FLOWING |
| Robot poet poem 2 lines | `botplayer.NextLine` | seeded `poet` over the current poem's lines only (`BeginNextPoem` empties `Lines`) | Yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command / Evidence | Result | Status |
|----------|--------------------|--------|--------|
| Go suite | `go test ./...` (run now) | all packages ok | PASS |
| Race-sensitive paths | `go test -race -count=1 ./internal/gateway ./internal/sessions ./internal/botplayer` (run now) | ok | PASS |
| Static checks | `go vet ./...`, `gofmt -l .` (run now) | no output | PASS |
| iOS suite, final plan state | `build/verify/p6-03-final/ios-verdict.txt` | 174 passed / 0 failed / 1 skipped | PASS (cited, not re-run) |
| iOS suite, regression | `build/verify/p6-regression/ios-verdict.txt` | 174 / 0 / 1 | PASS (cited) |
| iOS suite after review fixes | `build/verify/p6-fix/ios-verdict.txt` (12:11, after the last source commit `b0b56b9`) | 177 passed / 0 failed / 1 skipped | PASS (cited) |
| Structural gates | `grep -c '"sw:' server/internal/store/store.go` | 5 | PASS |
| Structural gates | `"sw.` literals under `ios/Strangewords` | 2 (`Keychain.swift:17-18`) | PASS |
| Commits since the last iOS run touch no source | `git log` shows only `f776c9d` (docs) after `b0b56b9` | confirmed | PASS |

### Probe Execution

Step 7c: SKIPPED. No probe scripts are declared by this phase's PLANs, and none exist under `scripts/*/tests/probe-*.sh`.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| P6-TRADE | 06-01, 06-02 | SATISFIED | Truths 1, 3, 4; `handleTrade`, `TestTradeTracer`, `TestTradeDeclinedByLettingGo`, `TestTradeRepeatIsIdempotent`, `AppModelTradeTests` |
| P6-ROLES | 06-01, 06-02 | SATISFIED | Truth 2; `poemStart()` derives the swap from `StartIndex` plus `PoemCount`; mock mirrors it (`tradeBackSwapsRolesIntoPoemTwo`) |
| P6-BOT | 06-01 | SATISFIED | Truth 6; think-time gate, restart tolerance and per-poem seed all tested in `TestBotTradesBack` and `TestPoemSeed` |
| P6-KEEPSAKE | 06-03 | SATISFIED | Truth 11; two names after a full trade, none sent anywhere, `kind` gone, goldens column-removed only |
| P6-ANON | 06-01 | SATISFIED | Truth 7; 5 `"sw:` literals, cache purge, zero keys after dissolution; `06-SECURITY.md` has `threats_open: 0` |
| P6-COMPAT | 06-01, 06-02 | SATISFIED | Truth 8 and the old-client test |
| P6-PARITY | 06-02 | SATISFIED | Truth 9 |
| P6-UI | 06-03 | SATISFIED | Truth 10 |
| P6-TESTS | 06-01, 06-02, 06-03 | SATISFIED | Truth 12; Go suite and `-race` rerun clean, iOS suite 177/0/1 |

No orphaned requirements: every P6-* ID mapped to Phase 6 in REQUIREMENTS.md appears in at least one PLAN.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (phase-modified files) | - | TBD/FIXME/XXX debt markers | none found | - |
| `gateway.go` | 441, 506 | reveal-state saves reset TTL to full `RevealTTL` (WR-02) | Warning | Privacy-page "two-minute" wording can be exceeded by up to about one more window; bounded, no leak. Deferred to a todo; not a Phase 6 must-have |
| `AppModel.swift` | 235-237, 423-425 | silent catch on transient trade-call or poll failure (WR-03) | Warning | No feedback on a network blip; default path unaffected. Deferred to a todo |

The code review's Critical finding (CR-01, double-tap and a late 409/410 cancelling poem 2's poll) and WR-01 (stale trade response regressing the phase and double-coining poem 1's keepsake) are fixed in `8671b71` and `e44e380` (AppModel.swift:77, 216-239, 363-370); the fixes are present in the code read and in the 177-test run. No later phase in the milestone absorbs the two deferred items, so they stay as open todos, not as deferred-to-phase items.

### Deferred Manual UAT (recorded, not performed; automated-only milestone)

These are not gating. They are for `/gsd-verify-work` when manual UAT is taken up.

1. **Simulator feel of the trade arc.** Test: in mock mode (`./run.sh --mock`), finish poem 1, wait for the stranger's offer, tap "trade back", write poem 2 (stranger opens), reach its reveal, let go. Expected: the caption, button, hand-off into poem 2 and the two keepsake names read naturally, with no flicker back to poem 1's reveal. Why human: timing and visual rhythm.
2. **VoiceOver on Reveal and Dissolved.** Test: with VoiceOver, reach the Reveal during an offer and the Dissolved screen with two keepsakes. Expected: the announcement fires when the partner asks or the moment passes, and "begin again" stays reachable. `06-UI-REVIEW.md` flags that the Dissolved screen's `.accessibilityElement(children: .combine)` wraps the button (a pattern that predates Phase 6, `git show 7295325^`), which could block it. Why human: needs the screen reader.
3. **Dynamic Type and layout at accessibility sizes.** Test: raise Dynamic Type to the largest accessibility size on Reveal (two buttons plus caption) and Dissolved (two keepsake blocks). Expected: nothing clips and everything scrolls or fits. Why human: the fixed 30/36 pt spacing has no accessibility-size fallback (UI review, 16/24).
4. **Real-device two-human trade against the live backend.** Expected: offer, accept, role swap and dissolution behave as in the Go end-to-end tests. Why human: needs two devices and the deployed server.

### Gaps Summary

No gaps. Every ROADMAP goal clause and all nine P6-* requirements are backed by code I read and by tests that pass: the server contract (`handleTrade`, `settleBot`, CAS dismiss, `PoemSeed`, `DeleteIdem`), the iOS wire and model, the mock arc, the UI and the keepsake changes. Structural privacy gates (5 `"sw:`, 2 `"sw.`) hold. Two minor review warnings (WR-02 TTL wording drift, WR-03 silent trade-tap failures) remain open as todos and do not affect goal achievement.

Status-semantics note: the verifier's decision tree reserves `passed` for an empty human-verification list. The orchestrator instructed `passed` when all automatable truths hold, with manual items handed to `/gsd-verify-work`, and the project constraint defers manual UAT. The four items above are therefore reported as deferred, not gating. If a consumer needs strict routing, the same findings map to `human_needed` with no code gaps.

---

_Verified: 2026-11-02_
_Verifier: Claude (gsd-verifier)_
