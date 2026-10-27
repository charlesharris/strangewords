---
phase: 05-opt-in-robot-poet-collaboration
plan: 03
subsystem: ios-ui
tags: [swift, swiftui, swift-testing, settings-sheet, disclosure, robot-poet, accessibility]

requires:
  - phase: 05-opt-in-robot-poet-collaboration
    provides: "Plan 02: AppModel.allowBot (persisted, default OFF), SessionView.partnerIsBot, LocalBackend wait-then-robot-poet arc"
provides:
  - "SettingsView: the one-switch settings sheet bound to AppModel.allowBot"
  - "PartnerPresence: persistent named-presence chip plus pure copy functions for every robot-poet string"
  - "Quiet top-leading gear on the Threshold that presents the sheet with re-injected palette, theme, model and color scheme"
  - "Waiting-room soft line, shown only when opted in and not connecting"
  - "Chip in Compose and Reveal, honest their-turn copy, and a one-time VoiceOver arrival announcement"
affects: [ship, privacy, manual-uat, safety-settings]

actuals:
  tokens: 5000
  tasks: 1
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Disclosure copy as pure static functions on the view type, pinned by unit tests (the chip renders only from partnerIsBot)"
    - "Sheet content re-injects palette, sceneTheme, model and color scheme explicitly instead of trusting inheritance"
    - "Private plain ButtonStyle (opacity-only press) for quiet chrome, never .ritual"

key-files:
  created:
    - ios/Strangewords/Features/Settings/SettingsView.swift
    - ios/Strangewords/Features/Compose/PartnerPresence.swift
    - ios/StrangewordsTests/PartnerPresenceTests.swift
  modified:
    - ios/Strangewords/Features/Threshold/ThresholdView.swift
    - ios/Strangewords/Features/Waiting/WaitingView.swift
    - ios/Strangewords/Features/Compose/ComposeView.swift
    - ios/Strangewords/Features/Reveal/RevealView.swift

key-decisions:
  - "The their-turn secondary line 'its line will be here in a moment' is locked UI-SPEC copy and does not name the robot poet; the test checks naming on the primary line instead of rewording the spec"
  - "Settings and sheet use only Theme and Palette tokens; accent appears once, as the switch tint"

patterns-established:
  - "Any new robot-poet string goes through PartnerPresence (or SettingsView) statics so the voice-rule test covers it"

requirements-completed: [P5-OPTIN, P5-SETTINGS, P5-DISCLOSE, P5-TESTS]

coverage:
  - id: D1
    description: "Disclosure copy: caption is nil for human partners and names the robot poet for bot partners (writing/written); their-turn copy differs by partner and promises no push for the robot poet"
    requirement: P5-DISCLOSE
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#humanPartnerHasNoCaption"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#robotPoetCaptionWhileWriting"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#robotPoetCaptionOnceFinished"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#humanTheirTurnCopyIsUnchanged"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#robotPoetTheirTurnCopyPromisesNoPush"
        status: pass
    human_judgment: false
  - id: D2
    description: "Waiting soft line and its accessibility label appear only for an opted-in user who is not connecting; default waiting room unchanged"
    requirement: P5-OPTIN
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#waitingLineOnlyWhenOptedInAndNotConnecting"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#waitingAccessibilityDefaultIsUnchanged"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#waitingAccessibilityMentionsTheRobotPoetWhenOptedIn"
        status: pass
    human_judgment: false
  - id: D3
    description: "Voice rule across every robot-poet string: no bot/ai/assistant/chatbot/algorithm/queue/searching/matched, robot poet is named, and the bot partner is never a stranger or someone; settings helper says software, not a person"
    requirement: P5-DISCLOSE
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#voiceRuleBansColdVocabulary"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#everyRobotStringNamesTheRobotPoet"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#botPartnerCopyNeverCallsItAStrangerOrSomeone"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/PartnerPresenceTests.swift#settingsCopyIsPinned"
        status: pass
    human_judgment: false
  - id: D4
    description: "Gear, settings sheet, chip placement and waiting line are wired where UI-SPEC anchors them (top-leading overlay, detents, skyBottom background, environment re-injection, toggle bound to allowBot, Compose/Reveal chip, announcement)"
    requirement: P5-SETTINGS
    verification:
      - kind: other
        ref: "plan verify grep chain over ThresholdView, SettingsView, ComposeView, RevealView, WaitingView (ANCHORS_OK)"
        status: pass
    human_judgment: true
    rationale: "No XCUITest per REQUIREMENTS.md; layout, contrast across 9 palettes, sheet environment inheritance, iPad form-sheet sizing and spoken VoiceOver behaviour can only be confirmed on a simulator or device (deferred end-of-phase manual UAT)"

duration: 20 min
completed: 2026-10-27
status: complete
plan_head_before: 0d6939c34f08b658f6214727b7a9a6a2e7631b38
plan_head_after: c58be8e059755e286b6b358a89c65e91f62fe8ce
commits: 2
---

# Phase 5 Plan 3: Robot Poet UI Summary

**A quiet Threshold gear opens a one-switch settings sheet (default OFF, bound to the persisted AppModel.allowBot), the waiting room gains an opt-in soft line, and any robot-poet session shows a persistent "writing/written with the robot poet" chip with push-free their-turn copy, all pinned by 15 copy and voice-rule tests.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-10-27T22:50:00Z
- **Completed:** 2026-10-27T23:10:00Z
- **Tasks:** 1 (TDD: RED then GREEN)
- **Files modified:** 7 (3 created, 4 modified)

## Accomplishments

- `PartnerPresence` holds the chip view and every robot-poet string as pure statics (`caption`, `theirTurn`, `waitingLine`, `waitingAccessibility`, `accessibilityText`, `arrivalAnnouncement`). The caption is nil for human partners, so no chip is in the hierarchy; the chip backing becomes a rounded rectangle at accessibility Dynamic Type sizes.
- `SettingsView` is a scrolling sheet with the header (title, 44pt "close" labelled "Close settings") and a single `Toggle(isOn: $model.allowBot)` row card, tinted with accent only on the switch.
- `ThresholdView` gets a top-leading gearshape (44pt hit area, 36pt backing, opacity-only `QuietPressStyle`) and presents the sheet with medium and large detents, a `skyBottom` background, and explicit re-injection of palette, sceneTheme, model and color scheme. Nothing is placed top-trailing, so the dev chips are untouched.
- `WaitingView` shows the soft line only when `allowBot` is true and the view is not connecting; Compose and Reveal render the chip first in their stacks; Compose reads its their-turn copy from `PartnerPresence.theirTurn` and announces the arrival once on appear.
- Full headless suite: 93 passed, 0 failed, 1 skipped (the pre-existing skip), up from 78. `HostIsolationTests.swift` is unchanged, and `go test ./... -count=1` is still green (no server file touched).

## Task Commits

1. **Task 1: Settings gear and sheet, waiting soft line, persistent chip** - `d34eceb` (test, RED), `c58be8e` (feat, GREEN)

**Plan metadata:** committed separately (docs: complete plan)

## Files Created/Modified

- `ios/Strangewords/Features/Settings/SettingsView.swift` - the sheet, copy constants `title`, `toggleTitle`, `helperText`
- `ios/Strangewords/Features/Compose/PartnerPresence.swift` - chip view and pure disclosure copy
- `ios/StrangewordsTests/PartnerPresenceTests.swift` - 15 Swift Testing cases (copy, nil case, voice rule)
- `ios/Strangewords/Features/Threshold/ThresholdView.swift` - gear overlay, `showSettings`, sheet presentation, private `QuietPressStyle`
- `ios/Strangewords/Features/Waiting/WaitingView.swift` - soft line and shared accessibility label
- `ios/Strangewords/Features/Compose/ComposeView.swift` - chip, their-turn copy from `PartnerPresence`, arrival announcement
- `ios/Strangewords/Features/Reveal/RevealView.swift` - finished chip

## TDD Gate Compliance

- **RED** (`d34eceb`): `scripts/test-ios.sh -only-testing:StrangewordsTests/PartnerPresenceTests` ran 15 tests, 13 failed on the planned assertions. The record (target `robotPoetCaptionWhileWriting()`, expected `writing with the robot poet`, actual empty string) was classified `RED_EVIDENCE_OK` / `target_test_failed` by `gsd_run check tdd-red-evidence`. Semantic assessment: the tests executed and failed on the planned copy assertions, not on a build or fixture fault. The 2 tests that passed (`voiceRuleBansColdVocabulary`, `botPartnerCopyNeverCallsItAStrangerOrSomeone`) pass vacuously against empty stub strings and are guards that become meaningful in GREEN.
- **Compile scaffolding in RED:** `PartnerPresence` and `SettingsView` existed as API-shape-only stubs (empty strings, nil-free returns) because a build failure is INVALID_RED.
- **GREEN** (`c58be8e`): all 15 tests plus the existing 78 pass. No refactor commit was needed.

## Decisions Made

- The their-turn secondary line is verbatim UI-SPEC copy and does not contain "robot poet"; the naming assertion covers the primary line for that pair. Copy was not altered to satisfy the test.
- No other departures from the plan's mechanisms.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Voice-rule test over-asserted that every robot string names "robot poet"**
- **Found during:** Task 1 (first GREEN run)
- **Issue:** The plan's behavior bullet says every robot-poet string except the settings title contains "robot poet", but the locked their-turn secondary "its line will be here in a moment" does not. One test failed against correct, spec-conformant copy.
- **Fix:** `everyRobotStringNamesTheRobotPoet` now asserts the their-turn primary names the robot poet and skips only that continuation line for the per-string check. UI-SPEC copy is unchanged.
- **Files modified:** `ios/StrangewordsTests/PartnerPresenceTests.swift`
- **Verification:** `scripts/test-ios.sh` full suite, 93 passed, 0 failed
- **Committed in:** `c58be8e`

---

**Total deviations:** 1 auto-fixed (1 test bug). **Impact on plan:** Test-only correction; the disclosure copy and the voice-rule intent are intact.

## Issues Encountered

- `scripts/test-ios.sh` runs exceed the 10 minute foreground tool limit on this machine, so they were run to completion in the background and read from the xcresult verdict.

## Known Stubs

None. The RED-phase stubs were replaced in the GREEN commit.

## Threat Flags

None. The only new surface is local UI bound to existing Plan 02 state; it is covered by T-05-13 and T-05-16.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 5 has its complete vertical slice: server fallback (Plan 01), iOS wire and model (Plan 02), and the UI (this plan). Mock mode (`./run.sh --mock`) walks gear, toggle, waiting soft line, robot poet joins after 25 s, chip in Compose and Reveal.
- Deferred to manual UAT (no XCUITest): gear placement clear of the SW_DEV=1 chips, sheet legibility in all 9 palettes (research assumption A2), toggle persistence across relaunch, chip wrapping at accessibility Dynamic Type, spoken VoiceOver labels and the single arrival announcement, and iPad form-sheet sizing with `maxWidth: 480`.

---
*Phase: 05-opt-in-robot-poet-collaboration*
*Completed: 2026-10-27*

## Self-Check: PASSED

- Created files exist: `SettingsView.swift`, `PartnerPresence.swift`, `PartnerPresenceTests.swift` (FOUND)
- Commits are ancestors of HEAD: `d34eceb`, `c58be8e`
- `scripts/test-ios.sh` full suite PASS (93 passed, 1 skipped, 0 failed); UI-SPEC anchor greps pass; `go test ./... -count=1` green; `HostIsolationTests.swift` unchanged
