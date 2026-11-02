---
phase: quick-261029-l7l
plan: 01
subsystem: ios-compose
tags: [swiftui, textfield, return-key, input-rule, swift-testing]

requires:
  - phase: quick-261029-l7k
    provides: ComposeView legibility backings (already on main; this plan edits different regions of the file)
provides:
  - "Return key in Compose offers the line through the button's path; line breaks can never enter the draft"
  - "DraftInput pure edit rule plus additive AppModel.canSubmit / draftChanged / returnKeyPressed"
affects: [compose, ios-tests]

actuals:
  tokens: 9000
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - "Model-level input path: view forwards every draft change to AppModel.draftChanged; a pure helper classifies the edit"
    - "Single shared submit gate (AppModel.canSubmit) for button and return key"

key-files:
  created:
    - ios/Strangewords/Features/Compose/DraftInput.swift
    - ios/StrangewordsTests/DraftInputTests.swift
    - ios/StrangewordsTests/ReturnKeyTests.swift
  modified:
    - ios/Strangewords/App/AppModel.swift
    - ios/Strangewords/Features/Compose/ComposeView.swift

key-decisions:
  - "onChange intercept on the unfiltered $model.draft binding plus an onSubmit backstop, not a filtering custom Binding (a binding that hands back an unchanged value can leave the UITextView showing the stray break)"
  - "A lone inserted line break (common prefix/suffix diff over Characters, CRLF is one) is the return key and leaves the draft unchanged; a paste never offers"
  - "Every run of isNewline Characters becomes one space, matching the server's whitespace collapse"
  - "Return key label changed from .done to .send"

requirements-completed: [QUICK-261029-l7l]

coverage:
  - id: D1
    description: "Return on a valid draft offers the line once through the shared gate; the wire text has no line break and the draft clears on success"
    requirement: QUICK-261029-l7l
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/ReturnKeyTests.swift#returnKeyOffersTheLineLikeTheButton"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/ReturnKeyTests.swift#returnWhileALineIsInFlightSendsOnlyOne"
        status: pass
    human_judgment: false
  - id: D2
    description: "Return is a no-op on a blank draft, on the partner's turn and while a line is in flight; pastes never offer and join with a space; every Unicode line break is removed"
    requirement: QUICK-261029-l7l
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/ReturnKeyTests.swift (returnOnABlankDraftDoesNothing, returnOnTheirTurnDoesNothing, pastedLinesNeverOfferAndReachTheWireAsOneLine, canSubmitIsSharedByButtonAndReturn)"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/DraftInputTests.swift (11 tests)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The software keyboard actually shows a 'send' return key, and the UITextView redraws without a visible blank second line after the onChange write-back"
    verification: []
    human_judgment: true
    rationale: "Real keyboard and UITextView redraw behavior needs a simulator session; this milestone is automated-only and XCUITest is out of scope"

duration: 35min
completed: 2026-11-02
status: complete
plan_head_before: 39bf101dbe7bd376734be8dc7ccceda67cabd41a
plan_head_after: e8b6f5563ce5b1f84076f3f6bcd23621b8c586e3
---

# Phase quick-261029-l7l Plan 01: Return key offers the line Summary

**Compose's return key now offers the line through the same canSubmit-gated submit() path as the button, and line breaks can no longer be typed or pasted into the draft (lone break = return, other breaks = one space), pinned by 17 new model-level tests.**

## Performance

- **Duration:** about 35 min
- **Tasks:** 2 (tracer + guards)
- **Files:** 3 created, 2 modified (plus 0 protected paths)
- **Commits:** 3 (`342cc1d` RED, `4ddd222` GREEN, `e8b6f55` tests)

## Accomplishments

- `DraftInput` (pure enum) classifies each field edit: a lone inserted line break is the return key and leaves the draft untouched; every other line-break run becomes one space.
- `AppModel` gained `canSubmit`, `returnKeyPressed()` and `draftChanged(from:to:)` (additions only, `submit()` byte-for-byte unchanged).
- `ComposeView`: `$model.draft` binding kept, `.onChange` forwards to `draftChanged`, `.onSubmit` backstop calls `returnKeyPressed()`, label `.send`, button `.disabled(!model.canSubmit)`, old private gate helper deleted.

## Task Commits

1. **Task 1 (tracer): return offers the line end to end** - `342cc1d` (test, compile-red), `4ddd222` (feat)
2. **Task 2: pin the edit rule and every guard** - `e8b6f55` (test)

## Evidence

- RED: `build/verify/quick-261029-l7l-t1-red` - compile failure, `AppModel has no member 'draftChanged'` (build failure, not a semantic RED; the model API did not exist yet).
- t1: `build/verify/quick-261029-l7l-t1` - PASS, 1 passed / 0 failed (`-only-testing:StrangewordsTests/ReturnKeyTests`).
- t2: `build/verify/quick-261029-l7l-t2` - full suite on iPhone Air: PASS, 142 passed / 0 failed / 1 skipped (the canary). Baseline 125 + 11 DraftInputTests + 6 ReturnKeyTests = 142; the plan floor was 134 (written against an older 117 baseline).

## Premise correction

The item assumed the server rejects a newline through CleanLine's control-character rule. It does not: `sessions.CleanLine` and `LocalBackend.cleanLine` skip `\n`, `\r`, `\t` in the control check and collapse whitespace runs to one space, so a typed return was silently stored as a space (the stored line differed from the two-line draft the user saw). VT, FF and NEL are control characters and a paste containing them is rejected. The client-side strip fixes both; neither cleaner was changed.

## Design notes

- Mechanism: onChange intercept plus onSubmit backstop; a filtering custom Binding was rejected because returning an unchanged value can leave the UITextView still showing the stray break. A double fire (both paths) sends one line because `canSubmit` includes `!submitting`, which `submit()` sets synchronously.
- Rules: a lone inserted break is return; a paste never offers (offering is irreversible and shared with a stranger). Edge case: if autocorrect and the line break land as one edit, it is read as a paste, the draft keeps the corrected text plus a trailing space, and a second return offers it. Pinned by `autocorrectFoldedIntoReturnIsNotAPress`.
- `.send` label: the key now offers the line instead of dismissing the keyboard; reversible with one modifier.

## Decisions Made

None beyond the plan's design choices listed in the frontmatter.

## Deviations from Plan

**1. [Rule 1 - Bug] Test compile error in `noEditEverLeavesALineBreak`**
- **Found during:** Task 2 first full-suite run
- **Issue:** `#expect(!result.draft.contains(where: \.isNewline), ...)` fails to compile because the key-path argument inside the `#expect` macro is treated as a throwing closure.
- **Fix:** compute `let hasBreak = result.draft.contains { $0.isNewline }` outside the macro.
- **Files modified:** `ios/StrangewordsTests/DraftInputTests.swift` (before the Task 2 commit)

**2. [Rule 1 - Gate literal vs sibling work] Protected-paths diff against 878735d**
- **Found during:** Task 2 verify
- **Issue:** `git diff --quiet 878735d -- <protected paths>` fails only because sibling item l7k's commit `daf7478` added one `.legibilityBacking(palette)` line to `StepAway.swift`. No quick-261029-l7l commit touches a protected path.
- **Fix:** verified the gate's real property instead: `git log -F --grep='quick-261029-l7l' -- <protected paths>` is empty, and `git diff 878735d` of those paths shows only `StepAway.swift` (l7k). The AppModel diff against 878735d is 27 insertions, 0 removals, and no added line mentions tokenStore/settings./UserDefaults.

**3. [Info] Pass-count floor**
- The plan's `>= 134` assumed a 117 baseline; the real post-l7k baseline was 125, so the suite reports 142 (125 + 17 as designed).

**Total deviations:** 2 auto-fixed/documented (Rule 1), 1 informational. **Impact:** none on scope.

## Issues Encountered

None.

## Known Stubs

None.

## Threat Flags

None. All new code is pure input handling; nothing new reads or writes identity, settings or UserDefaults.

## Open UAT item (deferred, non-blocking)

On a simulator in mock mode (`./run.sh --mock`): confirm the Compose keyboard's return key reads "send" and offers a typed line; that no visible blank second line appears in the field (the UITextView must redraw after the onChange write-back); that pasting two lines shows them joined by a space; and that return on an empty field does nothing. Not performed (this milestone is automated-only).

## Next Phase Readiness

Ready. SUMMARY is intentionally uncommitted (batch coordinator commits docs); STATE.md and ROADMAP.md untouched per instructions.

## Self-Check: PASSED

- FOUND: DraftInput.swift, DraftInputTests.swift, ReturnKeyTests.swift
- FOUND commits: 342cc1d, 4ddd222, e8b6f55 (all ancestors of HEAD)
