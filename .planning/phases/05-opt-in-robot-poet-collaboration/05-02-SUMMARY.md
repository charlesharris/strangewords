---
phase: 05-opt-in-robot-poet-collaboration
plan: 02
subsystem: ios-client
tags: [swift, swiftui, swift-testing, userdefaults, codable, opt-in, robot-poet, localbackend]

requires:
  - phase: 05-opt-in-robot-poet-collaboration
    provides: "Plan 01 wire contract: POST /v1/enter allowBot, session view partnerIsBot (omitted when false)"
provides:
  - "SessionView.partnerIsBot with a tolerant decode (absent key reads false) and a memberwise default of false"
  - "SettingsStore: device preference store (pref.allowBot, default OFF, outside the sw. namespace), sibling of TokenStore"
  - "AppModel.allowBot with didSet write-through; begin() sends the captured choice"
  - "Backend.enter(pushToken:allowBot:) across APIClient, LocalBackend, FakeBackend; APIClient always sends the allowBot key"
  - "LocalBackend mirror of the opted-in wait-then-robot-poet arc (defaultBotWindow 25, botWindow seam)"
affects: [05-03 settings sheet, waiting soft line and disclosure chip, ship, privacy]

actuals:
  tokens: 8400
  tasks: 2
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Preference store as a TokenStore sibling: injected UserDefaults, nonmutating setter, absent key = OFF"
    - "Hand-written tolerant Decodable (decodeIfPresent) extension so the memberwise init keeps its default"
    - "Mock arc driven by an injected window (botWindow 0 / 3600) so no test waits on the wall clock"

key-files:
  created:
    - ios/Strangewords/App/SettingsStore.swift
  modified:
    - ios/Strangewords/Net/Models.swift
    - ios/Strangewords/Net/Backend.swift
    - ios/Strangewords/Net/APIClient.swift
    - ios/Strangewords/Net/LocalBackend.swift
    - ios/Strangewords/App/AppModel.swift
    - ios/StrangewordsTests/FakeBackend.swift
    - ios/StrangewordsTests/TestSupport.swift
    - ios/StrangewordsTests/SessionViewTests.swift
    - ios/StrangewordsTests/SeamDefaultsTests.swift
    - ios/StrangewordsTests/LocalBackendTests.swift
    - ios/StrangewordsTests/AppModelTests.swift

key-decisions:
  - "pref.allowBot lives outside the sw. namespace so HostIsolationTests stays unmodified and TokenStore.clear() cannot erase it"
  - "begin() captures allowBot before creating the Task, so a toggle flipped mid-enter cannot change what was sent"
  - "No forwarding overload for Backend.enter: every caller must state the opt-in explicitly"
  - "LocalBackend opted-in users always wait the full window (no human pool to race); DRIFT notes record this"

patterns-established:
  - "Every new wire field is mirrored in Models, Backend, APIClient, LocalBackend and FakeBackend in the same plan"
  - "Tests write preferences only into suite-named containers via makeModel"

requirements-completed: [P5-OPTIN, P5-DISCLOSE, P5-SETTINGS, P5-PARITY, P5-TESTS]

coverage:
  - id: D1
    description: "SessionView decodes partnerIsBot when present and reads an absent key as false; memberwise construction defaults it to false"
    requirement: P5-DISCLOSE
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/SessionViewTests.swift#decodesPartnerIsBotWhenPresent"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/SessionViewTests.swift#partnerIsBotDefaultsFalseWhenAbsent"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/SessionViewTests.swift#memberwiseDefaultsPartnerIsBotFalse"
        status: pass
    human_judgment: false
  - id: D2
    description: "The robot-poet preference is default OFF, persists in a suite-isolated store outside the sw. namespace, and survives TokenStore.clear()"
    requirement: P5-SETTINGS
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/SeamDefaultsTests.swift#settingsStoreKeyIsOutsideSessionNamespace"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/SeamDefaultsTests.swift#settingsStoreDefaultsToStandard"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/SeamDefaultsTests.swift#settingsStoreIsolatesAndSurvivesTokenClear"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/HostIsolationTests.swift#standardDefaultsHoldNoSessionKeys"
        status: pass
    human_judgment: false
  - id: D3
    description: "begin() sends allowBot false on a fresh install and the user's choice after opt-in; the choice survives leave, reset and a new model over the same defaults"
    requirement: P5-OPTIN
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelTests.swift#beginSendsHumansOnlyByDefault"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/AppModelTests.swift#optInTravelsAndPersists"
        status: pass
    human_judgment: false
  - id: D4
    description: "LocalBackend mirrors the server arc: not opted in matches at once with partnerIsBot false; opted in waits inside the window, then matches with partnerIsBot true"
    requirement: P5-PARITY
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/LocalBackendTests.swift#notOptedInNeverMeetsTheRobotPoet"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/LocalBackendTests.swift#optedInWaitsThenMeetsTheRobotPoet"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/LocalBackendTests.swift#optedInStillWaitingInsideTheWindow"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/LocalBackendTests.swift#defaultsMatchShippedPacing"
        status: pass
    human_judgment: false
  - id: D5
    description: "APIClient always includes the allowBot key in the POST /v1/enter body"
    requirement: P5-OPTIN
    verification:
      - kind: other
        ref: "grep -qF 'body[\"allowBot\"] = allowBot' ios/Strangewords/Net/APIClient.swift"
        status: pass
    human_judgment: true
    rationale: "No test intercepts the real URLSession request body; the key is grep-anchored and compile-enforced by the Backend protocol, and is exercised end to end only against the Plan 01 server in a later phase check"

duration: 16 min
completed: 2026-10-27
status: complete
plan_head_before: 43f4c287876b3fcc7d0f9c495e813667087ffe29
plan_head_after: 5d71dff8d4f9f1a2ec74cd06eeaec8f245b78f33
commits: 4
---

# Phase 5 Plan 2: iOS Opt-In Wire and Model Summary

**Default-OFF robot-poet preference (pref.allowBot via a TokenStore-style SettingsStore) that begin() sends as allowBot on POST /v1/enter, a tolerant partnerIsBot decode on SessionView, and a LocalBackend that walks the same wait-then-robot-poet arc as the server, all proven headlessly by 78 passing Swift Testing tests.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-10-27T22:29:33Z
- **Completed:** 2026-10-27T22:45:18Z
- **Tasks:** 2
- **Files modified:** 12 (1 created, 11 modified)

## Accomplishments

- Task 1: `SessionView` gains `partnerIsBot` (declared last, default false) with a hand-written `init(from:)` using `decodeIfPresent`, so the server's omitted key never throws `keyNotFound`. `SettingsStore` persists `pref.allowBot` outside the `sw.` namespace; `AppModel.allowBot` writes through and is untouched by `dissolve()` and `reset()`.
- Task 2: `Backend.enter(pushToken:allowBot:)` is the only enter requirement (no overload), implemented by `APIClient` (always sends the key), `LocalBackend` and `FakeBackend`. `begin()` captures the preference before spawning its task. `LocalBackend` with `allowBot: true` answers waiting with a `waitId`, keeps answering waiting for `botWindow` (default 25 s), then matches with `partnerIsBot` true.
- Suite went from 73 to 78 passing tests (74 to 79 total, the 1 skipped test is the pre-existing one); `HostIsolationTests.swift` is byte-identical to HEAD and `"sw.` key literals in the app remain exactly 2.

## Task Commits

1. **Task 1: tolerant partnerIsBot, SettingsStore, AppModel.allowBot seam** - `0b8a452` (test, RED), `8fa2f01` (feat, GREEN)
2. **Task 2: opt-in crosses the wire, mock mirrors the arc** - `1a615f7` (test, RED), `5d71dff` (feat, GREEN)

**Plan metadata:** committed separately (docs: complete plan)

## Files Created/Modified

- `ios/Strangewords/App/SettingsStore.swift` - device preference store, `allowBotKey = "pref.allowBot"`, absent reads false
- `ios/Strangewords/Net/Models.swift` - `partnerIsBot`, `SessionView.CodingKeys`, tolerant `init(from:)`
- `ios/Strangewords/Net/Backend.swift` - two-parameter `enter` requirement with the opt-in doc
- `ios/Strangewords/Net/APIClient.swift` - `body["allowBot"] = allowBot` on every enter
- `ios/Strangewords/Net/LocalBackend.swift` - `defaultBotWindow` [TUNABLE] 25, `botWindow` seam, `waitingSince`/`partnerIsBot` state, DRIFT notes
- `ios/Strangewords/App/AppModel.swift` - `settings:` init seam, observed `allowBot`, `begin()` sends the captured value
- `ios/StrangewordsTests/FakeBackend.swift` - `Pending.allowBot`, enter conformance parks with the value
- `ios/StrangewordsTests/TestSupport.swift` - `makeModel` injects an isolated `SettingsStore`; `haikuView(partnerIsBot:)`
- `ios/StrangewordsTests/{SessionViewTests,SeamDefaultsTests,LocalBackendTests,AppModelTests}.swift` - the 11 new tests and the 10 updated enter call sites

## TDD Gate Compliance

RED evidence was classified with `gsd_run check tdd-red-evidence` (`RED_EVIDENCE_OK`, reason `target_test_failed`) before each GREEN commit.

- **RED 1** (`0b8a452`): target `partnerIsBotDefaultsFalseWhenAbsent()` failed with `DecodingError.keyNotFound: Key 'partnerIsBot'`; `settingsStoreIsolatesAndSurvivesTokenClear()` failed on the round-trip expectations. Semantic assessment: both executed and failed on the planned behavior, not on a build or fixture fault.
- **RED 2** (`1a615f7`): target `optedInWaitsThenMeetsTheRobotPoet()` failed on `entered.state == "waiting"` / `partnerIsBot == true`; `optedInStillWaitingInsideTheWindow()` and `optInTravelsAndPersists()` (`enter.allowBot == true`) failed too. Semantic assessment: the stub LocalBackend ignored allowBot and begin() hardcoded false, so the failures are the planned assertions.
- GREEN commits `8fa2f01` and `5d71dff` follow; no refactor commit was needed.

Both RED commits carry compile scaffolding that is not behavior (the `partnerIsBot` field with plain synthesized Codable and a non-persisting `SettingsStore` stub; the `Backend.enter` signature plumbing with a stub LocalBackend and a hardcoded-false `begin()`), because a build failure is INVALID_RED.

## Decisions Made

- Followed the plan's mechanisms as written (see key-decisions in the frontmatter).
- The first RED classification attempt used the full-filter run and returned `invalid_record` ("Incomplete swift-testing report") because the swift-testing adapter does not understand parameterized-test summary lines (`with 3 test cases passed`). Per the TDD reference, the RED run was repeated through `scripts/test-ios.sh` with `-only-testing` filters naming only the non-parameterized target tests, which the classifier accepted. No report was edited.

## Deviations from Plan

None - plan executed exactly as written.

**Total deviations:** 0 auto-fixed. **Impact on plan:** none.

## Issues Encountered

- `scripts/test-ios.sh` runs take several minutes each (build, simulator boot, xcresult summary), so the full-suite runs were executed once per task GREEN rather than after every edit.

## Known Stubs

None. (The RED-phase stubs, the non-persisting `SettingsStore` and the allowBot-ignoring `LocalBackend`, were replaced in the GREEN commits.)

## Threat Flags

None - the new surface (`allowBot` request key, `partnerIsBot` decode, `pref.allowBot` preference) is covered by T-05-10, T-05-11 and T-05-12 in the plan's threat model.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Ready for 05-03: `AppModel.allowBot` is the observable toggle the settings sheet binds to, `SessionView.partnerIsBot` is the model flag the disclosure chip and waiting soft line read, and mock mode (`SW_LOCAL_MOCK=1`) now walks the opted-in arc for UI iteration.
- Not covered by an automated test: the real `APIClient` request body (the key is grep-anchored and enforced by the protocol signature); `server/` is untouched and its `go test ./... -count=1` is still green.

---
*Phase: 05-opt-in-robot-poet-collaboration*
*Completed: 2026-10-27*

## Self-Check: PASSED

- Created file exists: `ios/Strangewords/App/SettingsStore.swift` (FOUND)
- Commits are ancestors of HEAD: `0b8a452`, `8fa2f01`, `1a615f7`, `5d71dff`
- `scripts/test-ios.sh` full suite: PASS (78 passed, 1 skipped, 0 failed); grep gates and `go test ./... -count=1` green
