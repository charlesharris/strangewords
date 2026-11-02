---
phase: 06-two-poem-trade
plan: 03
subsystem: ios-ui
tags: [swift, swiftui, swift-testing, accessibility, voiceover, keepsakes, privacy]

requires:
  - phase: 06-two-poem-trade
    provides: "Plan 02: AppModel.tradeBack(), SessionView's four trade fields, the reveal poll, release() epoch semantics, TestSupport.haikuView trade parameters"
provides:
  - "TradeBack: the pure offer/accept/waiting/passed mapping over the server's three trade fields, and every pinned trade string (button, captions, VoiceOver hints)"
  - "RevealView's quiet 'trade back' affordance beside 'let it go', with a VoiceOver announcement when the partner asks or the moment passes"
  - "CoinedName(lead:name:) — the category removed everywhere (D-05) with every golden name and lead byte-identical"
  - "AppModel.keepsakes: one coined name per completed poem (D-04), poem 1's coined as poem 2 begins, poem 2's at dissolution"
  - "DissolvedView rendering every keepsake, with the farewell line above them after an interrupted second poem"
affects: [ship, testflight, verify-work]

actuals:
  tokens: 12240
  tasks: 3
  commits: 6

plan_head_before: c7b7e43a9c562002d9008b219508fc35876c72b1
plan_head_after: 9c8853c9c49fa32f6006f69674be67a619cf91c6
commits: 6

tech-stack:
  added: []
  patterns:
    - "Trade UI state is a pure function of the server view: RevealView derives one TradeBack.Offer and never infers anything (T-06-16)"
    - "Every user-facing trade string lives in a pure static home (TradeBack), pinned exactly by tests, lowercase visible voice, Phase 5 robot-poet voice rule extended"
    - "Keepsakes are an in-memory list cleared by begin()/reset(); coining sites are exactly two (apply's reveal-to-next-poem transition and finishDissolving)"

key-files:
  created:
    - ios/Strangewords/Features/Reveal/TradeBack.swift
    - ios/StrangewordsTests/TradeBackTests.swift
  modified:
    - ios/Strangewords/Features/Reveal/RevealView.swift
    - ios/Strangewords/Naming/PoemNaming.swift
    - ios/Strangewords/Features/Dissolved/DissolvedView.swift
    - ios/Strangewords/App/AppModel.swift
    - ios/StrangewordsTests/PartnerPresenceTests.swift
    - ios/StrangewordsTests/PoemNamingTests.swift
    - ios/StrangewordsTests/AppModelTests.swift
    - ios/StrangewordsTests/StepAwayTests.swift
    - ios/StrangewordsTests/AppModelTradeTests.swift
    - ios/StrangewordsTests/ContrastTests.swift
    - docs/STATUS.md

key-decisions:
  - "The reveal caption uses palette.secondary with the shared legibilityBacking — the exact recipe the l7k contrast suite already proves for caption-size low-screen text — rather than a new palette role"
  - "ContrastTests' dead dissolved.keepsakeKind surface was removed with the kind line (22 surfaces, 198 matrix rows) so the inventory keeps describing what the views render"
  - "Coiner closures keep their position, count and every RNG draw; duplicate name shapes left unmerged so catalogue weights and the seeded draw order stay pinned"

patterns-established:
  - "Per-test xcodebuild filters for swift-testing need the () suffix: -only-testing:Target/Suite/testName() — without it zero tests run"
  - "RED compile scaffolding: an inert enum stub / current-behavior helper / never-appending property lets RED fail on assertions instead of compilation"

requirements-completed: [P6-UI, P6-KEEPSAKE, P6-TESTS]

coverage:
  - id: D1
    description: "The Reveal screen offers or accepts a trade back beside 'let it go', driven only by the server's tradeOpen/youWantTrade/partnerWantsTrade, with every string pinned, lowercase visible copy, and the robot-poet voice rule extended to the five new strings"
    requirement: "P6-UI"
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/TradeBackTests.swift (7 tests: offerStateMapping, buttonOnlyForOfferAndAccept, humanCopyIsPinned, robotPoetCopyIsPinned, visibleCopyIsLowercase, copyKeepsTheRitualVoice, humanCopyNeverNamesTheRobotPoet)"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift (voice-rule suites over robotStrings + botCopy, now carrying the five trade strings)"
        status: pass
      - kind: other
        ref: "grep gates: RevealView anchored to TradeBack.offer(tradeOpen: session.tradeOpen, ...) and model.tradeBack(); let-it-go label, hint and release() intact"
        status: pass
    human_judgment: false
  - id: D2
    description: "CoinedName carries only lead and name; no category line or VoiceOver mention anywhere, single poems included; all six golden names and leads byte-identical (column removal, not re-capture)"
    requirement: "P6-KEEPSAKE"
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/PoemNamingTests.swift#golden (6 goldens, name+lead), #coinedNameCarriesOnlyLeadAndName, #keepsakeAccessibilityNamesNoCategory"
        status: pass
      - kind: other
        ref: "grep gates: no kind property/argument/literal survives; all six lead-and-name pairs matched verbatim"
        status: pass
    human_judgment: false
  - id: D3
    description: "One keepsake per completed poem: two after a full trade (poem 1's coined as poem 2 begins), one for a single poem, poem 1's kept when poem 2 is interrupted; in memory only, cleared by begin() and reset()"
    requirement: "P6-KEEPSAKE"
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelTradeTests.swift#fullTradeLeavesTwoKeepsakes, #partnerLeavingPoemTwoKeepsPoemOnesName, #aSinglePoemLeavesOneKeepsakeAndBeginClearsIt"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelTests.swift and StepAwayTests.swift (every keepsake assertion rewritten against the list, none dropped)"
        status: pass
      - kind: other
        ref: "grep gates: exactly two PoemNaming.coin(from: sites in AppModel; no .keepsake singular reference anywhere; sw. literal count stays 2 (T-06-14)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The full iOS suite proves the plan: 174 passed / 0 failed / 1 skipped (baseline 162 + the 12 new tests), no wall-clock sleeps, models only via TestSupport.makeModel"
    requirement: "P6-TESTS"
    verification:
      - kind: unit
        ref: "SW_VERIFY_OUT=build/verify/p6-03-final scripts/test-ios.sh — verdict PASS 174/0/1"
        status: pass
    human_judgment: false
  - id: D5
    description: "The Reveal layout with a caption plus two buttons at large Dynamic Type sizes, two stacked keepsakes on a small screen, and the VoiceOver announcement when the partner offers, all feel right on a device"
    verification: []
    human_judgment: true
    rationale: "Automated-only milestone: visual layout at accessibility sizes and the announcement's feel are not asserted by any test; recorded for UAT, not performed"

duration: 17min
completed: 2026-11-02
status: complete
---

# Phase 6 Plan 03: Two-Poem Trade, iOS UI and Keepsakes Summary

**RevealView gains a quiet test-pinned "trade back" affordance driven only by the server's trade fields, CoinedName loses its category everywhere with all six goldens byte-identical, and AppModel.keepsakes holds one coined name per completed poem — two after a full trade, poem 1's kept through an interrupted poem 2.**

## Performance

- **Duration:** 17 min
- **Started:** 2026-11-02T17:38:32Z
- **Completed:** 2026-11-02T17:55:17Z
- **Tasks:** 3 (1 tracer, 2 auto; all TDD)
- **Files modified:** 13 (2 created, 11 modified), 492 insertions and 100 deletions across the six task commits

## Test Evidence

- **Baseline** (precondition, before any edit): `passedTests` **162**, 0 failed, 1 skipped (the harness canary), at `build/verify/p6-03-base`.
- **Final** full suite: `passedTests` **174**, 0 failed, 1 skipped, at `build/verify/p6-03-final`. That is baseline + 12: 7 TradeBackTests, 2 PoemNamingTests, 3 AppModelTradeTests — the plan's `final >= base + 12` gate passes exactly.
- Grep gates all pass: RevealView anchored to the three server fields and `model.tradeBack()` with the let-it-go button intact; no category property, argument or literal survives; all six golden lead-and-name pairs verbatim; no `.keepsake` singular reference; `"sw.` literal count in `ios/Strangewords` is 2 (unchanged); no wall-clock waits in the test tree.
- `coiners` still holds 16 closures and `soloCoiners` 7, in their original order.

## Golden column removal (D-05)

Carried forward in place of the Phase 4 fix ledger, which does not yet exist as a file:

- **Reason:** Phase 6 D-05 removes `CoinedName`'s category and its rendering line everywhere, single poems included. Only the lead and the name remain.
- **This was a column removal, not a re-capture.** Category strings were compile-time constants, never RNG draws, so every coiner closure kept its position, its name expression and every draw it makes (the beer-style pick through `one(beerStyles, &r)`, the perfume `Int.random`, the indie-band `Bool.random`). The seeded draw order is therefore provably undisturbed.
- **The six unchanged names (and their leads, all byte-identical):** Old Splash, Moon No. 5, The Moon, Lantern, Straße Café, Lanterns Drift.
- Duplicate name patterns that remain after the category left (several coiners now share one shape) were **not** deduplicated, because merging them would change the catalogue weights and the names. A comment above `coiners` records this rule.
- `PoemNamingTests` carries a dated header note (2026-11-02) stating no name or lead value changed and that the stdlib-drift re-capture rule still governs future value changes.

## Task Commits

1. **Task 1 (tracer): the Reveal screen offers "trade back"**
   - RED `e44e17a` (test): 7 TradeBackTests + the five robot-poet trade strings into PartnerPresenceTests' voice-rule lists; TradeBack landed as an inert compile scaffold
   - GREEN `bcbbbf1` (feat): the real mapping and pinned copy, RevealView wiring (caption + trade button + untouched let-it-go), VoiceOver announcement on .accept/.passed
2. **Task 2: D-05, the category removed everywhere**
   - RED `d8d665e` (test): coinedNameCarriesOnlyLeadAndName, keepsakeAccessibilityNamesNoCategory; keepsakeAccessibility scaffolded with current behavior
   - GREEN `7295325` (feat): CoinedName(lead:name:), name-only Coiner with draws intact, DissolvedView's kind line gone, golden column dropped, ContrastTests dead surface removed, docs/STATUS.md rewritten
3. **Task 3: D-04, one keepsake per completed poem**
   - RED `75990de` (test): the three keepsake tests; every existing keepsake assertion rewritten against the list; naive never-appending scaffold
   - GREEN `9c8853c` (feat): coining wired at apply's reveal-to-next-poem transition and finishDissolving; DissolvedView renders every name with the farewell above an interrupted ending

**Plan metadata:** recorded in the following `docs(06-03)` commit (SUMMARY, STATE, ROADMAP, REQUIREMENTS).

## TDD Gate Compliance

Every task has a `test(06-03)` RED commit before its `feat(06-03)` GREEN commit. No refactor commits were needed. `gsd_run check tdd-red-evidence` returned `RED_EVIDENCE_OK` (reason `target_test_failed`) for all three RED targets.

- **RED 1** (target `offerStateMapping()`): 4/7 TradeBackTests failed on assertion against the inert scaffold (mapping always `.none`, empty copy); the three voice tests passed vacuously over empty string sets. Semantic assessment: the target ran and failed on the planned mapping assertions — the intended reason (the real mapping did not exist).
- **RED 2** (target `coinedNameCarriesOnlyLeadAndName()`): both new tests failed — Mirror labels were `[lead, name, kind]`, and the scaffold accessibility string still named the kind. Semantic assessment: failed on the planned assertions because the category still existed, the intended reason.
- **RED 3** (target `fullTradeLeavesTwoKeepsakes()`): all three keepsake tests failed on their `keepsakes ==` assertions against the naive never-appending scaffold. Semantic assessment: failed on the planned assertions because no coining site existed, the intended reason.

## Files Created/Modified

- `ios/Strangewords/Features/Reveal/TradeBack.swift` — the pure trade state mapping and every trade string (new)
- `ios/StrangewordsTests/TradeBackTests.swift` — 7 tests pinning the mapping and copy (new)
- `ios/Strangewords/Features/Reveal/RevealView.swift` — the trade-back affordance beside "let it go"
- `ios/Strangewords/Naming/PoemNaming.swift` — CoinedName(lead:name:), name-only Coiner, draw order intact
- `ios/Strangewords/Features/Dissolved/DissolvedView.swift` — no category line; renders every keepsake; keepsakeAccessibility
- `ios/Strangewords/App/AppModel.swift` — keepsakes list with exactly two coining sites
- `ios/StrangewordsTests/PartnerPresenceTests.swift` — the five robot-poet trade strings in the voice-rule lists
- `ios/StrangewordsTests/PoemNamingTests.swift` — golden column removal + the two D-05 tests
- `ios/StrangewordsTests/AppModelTests.swift`, `StepAwayTests.swift` — keepsake assertions rewritten against the list
- `ios/StrangewordsTests/AppModelTradeTests.swift` — the three D-04 keepsake tests
- `ios/StrangewordsTests/ContrastTests.swift` — dead keepsakeKind surface removed (22 surfaces, 198 rows)
- `docs/STATUS.md` — keepsake paragraph rewritten for per-poem names without a category

## Decisions Made

- The reveal caption uses `palette.secondary` with the shared `legibilityBacking` — the exact recipe the l7k contrast suite already proves for caption-size low-screen text (`compose.theirTurnPrimary`, `compose.stepAway`); no dedicated caption role exists.
- The VoiceOver announcement posts from `.onChange(of:)` on the derived offer state, the way ComposeView posts its arrival announcement, only for `.accept` and `.passed`.
- The interrupted-ending accessibility label is the farewell message followed by `keepsakeAccessibility(keepsakes)`, matching the visual order.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] RED commits needed compile scaffolding**
- **Found during:** Tasks 1, 2 and 3 RED
- **Issue:** A test naming `TradeBack`, `DissolvedView.keepsakeAccessibility` or `AppModel.keepsakes` before it exists is a build failure, which the RED classifier refuses as `INVALID_RED`.
- **Fix:** Task 1's RED carried an inert `TradeBack` (mapping always `.none`, empty copy); Task 2's RED carried a current-behavior `keepsakeAccessibility` (still naming the kind); Task 3's RED carried a declared-and-cleared, never-appending `keepsakes` list. Each GREEN replaced its scaffold; no scaffold remains in HEAD.
- **Files modified:** `TradeBack.swift`, `DissolvedView.swift`, `AppModel.swift`
- **Verification:** all three RED records classified `RED_EVIDENCE_OK` (`target_test_failed`); all GREENs pass
- **Committed in:** `e44e17a`, `d8d665e`, `75990de` (replaced in `bcbbbf1`, `7295325`, `9c8853c`)

**2. [Rule 1 - Stale test data] ContrastTests' keepsakeKind surface removed with the kind line**
- **Found during:** Task 2 (D-05 removal)
- **Issue:** `ContrastTests.inventory` pins "the styling the views render today" and carried a `dissolved.keepsakeKind` surface; after D-05 that surface corresponds to nothing rendered, so the pinned matrix would measure a dead element and misdescribe the UI.
- **Fix:** Removed the surface and updated the pinned counts (23 → 22 surfaces, 207 → 198 matrix rows) and the doc comment. `ContrastTests.swift` was not in the plan's `files_modified` list.
- **Files modified:** `ios/StrangewordsTests/ContrastTests.swift`
- **Verification:** ContrastTests pass (8/8) in the Task 2 GREEN run and the full suite
- **Committed in:** `7295325`

---

**Total deviations:** 2 auto-fixed (1 Rule 3 TDD scaffolding, 1 Rule 1 stale test data)
**Impact on plan:** Both are test-harness matters. Production behavior matches the plan exactly; no golden value changed.

## Issues Encountered

- Per-test `-only-testing` filters for swift-testing silently select zero tests without the `()` suffix (`.../coinedNameCarriesOnlyLeadAndName` ran nothing; `.../coinedNameCarriesOnlyLeadAndName()` ran it). One RED evidence run was repeated with the corrected syntax; `scripts/test-ios.sh`'s zero-tests-is-FAIL verdict caught it immediately.
- Per-test filters were used for the Task 2 and 3 RED evidence because the swift-testing adapter rejects reports containing parameterized tests (the `golden(_:)` and `noContentWordsCoinsNothing(_:)` suitesmates), as plan 06-02 had already recorded.

## Manual UAT (recorded, not performed — automated-only milestone)

- The Reveal layout with a caption plus two buttons at large Dynamic Type sizes
- Two stacked keepsakes on a small screen
- The VoiceOver announcement when the partner offers

## Known Stubs

None. The RED scaffolds above were replaced by their GREEN commits; no placeholder text or empty data source remains.

## Threat Flags

None. T-06-14 through T-06-17 are mitigated as planned: keepsakes stay in memory (the `sw.` literal count is still 2), the five robot-poet strings sit in the voice-rule lists, the trade affordance renders only through `TradeBack.offer` of the three server fields, and the goldens are grep-anchored byte-identical. No new network, auth or storage surface was introduced.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 6 is fully executed: server (06-01), client contract (06-02) and UI + keepsakes (06-03). `./run.sh --mock` walks the whole trade arc — offer, role-swapped poem 2, two keepsakes — on one simulator.
- Ready for `/gsd-verify-work 6`; the one human-judgment deliverable (D5) plus plan 06-02's mock-feel check are the recorded UAT items.

## Self-Check: PASSED

All 13 code files and the SUMMARY exist; commits `e44e17a`, `bcbbbf1`, `d8d665e`, `7295325`, `75990de`, `9c8853c` are ancestors of HEAD; the full suite is green at 174 passed (baseline 162 + 12); the measured commit count (6) matches `commits:`; the grep and structural gates pass; the working tree is clean of tracked changes.

---
*Phase: 06-two-poem-trade*
*Completed: 2026-11-02*
