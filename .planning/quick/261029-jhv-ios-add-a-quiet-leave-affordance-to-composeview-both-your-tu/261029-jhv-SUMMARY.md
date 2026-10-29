---
phase: quick-261029-jhv
plan: 01
subsystem: ios-compose
tags: [ios, compose, leave, step-away, tests]
status: complete
key-files:
  created:
    - ios/Strangewords/Features/Compose/StepAway.swift
    - ios/StrangewordsTests/StepAwayTests.swift
  modified:
    - ios/Strangewords/Features/Compose/ComposeView.swift
commits: 2
plan_head_before: b5ad8fd90a305b8055894b93dfde4db72ced51c9
plan_head_after: d2ea3a62453327c5a8f780696f6753dba6d0e7c7
actuals:
  tasks: 2
  commits: 2
---

# Quick 261029-jhv: Quiet "step away" escape from Compose

A quiet "step away" control now sits at the bottom of ComposeView in both the your-turn and their-turn states. It asks once through a confirmation dialog, then calls the existing `AppModel.leave()`. That sends leave, dissolves to `.dissolved(.ended)`, clears identity, and shows the plain farewell and "begin again". A relaunch then starts at the threshold, so the TestFlight trap is gone.

## Placement and confirmation rationale
- Placed as the last child of ComposeView's root VStack, after the trailing `Spacer(minLength: 24)` and outside both turn branches. The Phase 5 D-04 chip owns top-leading (first in VoiceOver order), the dev chips own top-trailing, and the app's other exits ("step back out", "let it go", "begin again") live at the bottom.
- A `confirmationDialog` asks first, since stepping away ends the poem for both writers and can't be undone. Only the destructive button (haptic, then `model.leave()`) leaves. Removing the dialog would make it a one-tap exit.
- The control is styled like the waiting room's "step back out": `Theme.label`, `palette.secondary`, no backing, a 44pt minimum hit area.

## Pinned copy (all `static let` on `StepAway`)
- label: "step away"
- accessibilityHint: "Asks before letting this unfinished poem go. It will not be saved."
- confirmTitle: "step away from this poem?"
- confirmMessage: "the poem will dissolve unfinished and won't come back"
- confirmAction: "step away"
- stayAction: "stay with the poem"

The copy is partner-neutral (same text for human and robot-poet sessions) and avoids cold vocabulary. Both rules are pinned by tests.

## Tests and evidence
- `StepAwayTests`: 7 tests (copy pin, lowercase, ritual voice, partner-neutral, their-turn leave and dissolve, your-turn draft never submitted, relaunch starts at the threshold with zero backend calls).
- Task 1 (only StepAwayTests, iPhone 17e): PASS, 2 passed, 0 failed. Evidence: `build/verify/quick-261029-jhv-t1` in the worktree.
- Task 2 (full suite, iPhone 17e): PASS, 100 passed, 0 failed, 1 skipped (101 total). Evidence: `build/verify/quick-261029-jhv-t2` in the worktree.
- Gates: no wall-clock waits and no direct `AppModel(` constructors in tests. No quick-261029-jhv commit touches AppModel, Net/, PartnerPresence, FakeBackend, TestSupport, AppModelTests or project.yml. The `StepAway()` ordering in ComposeView was checked with the awk gate, and the D-04 chip line is unchanged.

## Commits
- 3126117 feat(quick-261029-jhv): quiet step-away escape from Compose
- d2ea3a6 test(quick-261029-jhv): pin the Compose escape contract

## Deviations from Plan
None. The plan was executed as written. The Task 1 and Task 2 verify commands were run as separate plain commands rather than the single compound shell line, because the sandbox refused the compound form in the worktree. The same gates were checked.

## Open items
- Deferred manual UAT (not performed, non-blocking): on the smallest supported iPhone, check in a your-turn session with the keyboard open that "step away" sits below "offer this line" without clipping the poem lines or the robot-poet chip. In a their-turn session, check that it sits at the bottom where "step back out" sat in the waiting room.
- Out of scope, recommended as a follow-up todo: the compose-escape todo's optional gentle assist, which surfaces the option more visibly after the partner has been silent for N minutes. Apart from that assist, this item resolves the compose-escape todo (`.planning/todos/` left untouched).

## Known Stubs
None.

## Self-Check: PASSED
Files StepAway.swift, StepAwayTests.swift and the ComposeView.swift edit exist in the worktree, and commits 3126117 and d2ea3a6 are on branch worktree-agent-a301ee22e15915b5a.
