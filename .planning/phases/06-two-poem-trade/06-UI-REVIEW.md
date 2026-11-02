---
phase: "06"
slug: "two-poem-trade"
audited: "2026-11-02"
baseline: abstract-6-pillar
overall_score: 16
max_score: 24
---

# Phase 06 (Two-Poem Trade) UI Review

**Audited:** 2026-11-02
**Baseline:** Abstract 6-pillar standards. No UI-SPEC.md exists for this phase.
**Screenshots:** Not captured. Native SwiftUI app with no dev server; the audit is code-only.
**Interaction captures:** off (`interaction_capture: false`).

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | Trade copy is lowercase, pinned by tests and voice-checked. The interrupted-ending message contradicts the kept name below it. |
| 2. Visuals | 3/4 | "trade back" and "let it go" are the same `.ritual` style at equal weight, so the optional action competes with the default path. |
| 3. Color | 3/4 | Caption reuses `palette.secondary` with `legibilityBacking`, and no hardcoded colors appear in the audited files. Contrast is asserted by the l7k suite, not verified on device. |
| 4. Typography | 3/4 | All text uses Theme tokens that scale with Dynamic Type (`relativeTo:`). Sizes stay within the existing scale. |
| 5. Spacing | 2/4 | New Reveal code uses off-grid values 14, 18 and 30 against the 4pt grid. The fixed 30pt and 36pt spacing has no accessibility-size fallback. |
| 6. Experience Design | 2/4 | A likely VoiceOver defect on the Dissolved screen can block "begin again". Failed trade taps give no feedback. |

**Overall: 16/24**

## Top 3 Priority Fixes

1. **BLOCKER (needs device confirmation): "begin again" may be unreachable by VoiceOver on the Dissolved screen.** `keepsakeBody` (`DissolvedView.swift:69`) and `farewellBody` (`:89`) wrap the content, including the `beginAgainButton`, in `.accessibilityElement(children: .combine)`. That merges the button into one custom-labelled element, so a VoiceOver user may not be able to activate it separately. Fix: keep `.combine` only on the message and keepsake `VStack`s, and leave the button as its own element. Confirm with VoiceOver on a device, since this is from code analysis. (Same pattern as the carried Phase 5 waiting-room advisory.)
2. **Off-grid spacing in the new Reveal layout.** `RevealView.swift` uses `VStack(spacing: 14)` for the caption and buttons, `spacing: 18` for poem lines, and `spacing: 30` for the outer stack. Change them to 12, 16 and 32 (or the project's approved scale), and check that the stack still fits at the largest accessibility text sizes.
3. **A failed trade tap gives no feedback.** `AppModel.tradeBack()` (`AppModel.swift:218-223`) swallows transient errors, so tapping "trade back" during a network blip does nothing visible. Add a quiet inline message in the style of `submitError`, such as "the trade didn't go through. try once more.", while leaving the reveal in place.

## Detailed Findings

### Pillar 1: Copywriting (3/4)
- Strengths: every trade string is a pure value in `Features/Reveal/TradeBack.swift:25-61`, pinned by `TradeBackTests`, and checked against the robot-poet voice rule in `PartnerPresenceTests`. Visible copy is lowercase, as the ritual voice requires.
- `DissolvedView.swift:41-45` shows "The stranger slipped away. / The poem went with them." above poem 1's keepsake in an interrupted poem 2. "The poem went with them" conflicts with the name shown below it. Suggested: "The stranger slipped away. The first poem stays with you." or similar.
- `DissolvedView.swift:43-47` also needs a human-check for a partner-left message after a full reveal, since that path is untested for tone.

### Pillar 2: Visuals (3/4)
- `RevealView.swift:49-64`: the "trade back" button and "let it go" both use `.buttonStyle(.ritual)` with `Theme.poem(18)`. The optional offer has the same weight as the default dismissive path, which can read as pressure. Consider a secondary style for "trade back".
- The caption at `Theme.label` (13pt) is the smallest text on the screen. Acceptable under the existing contrast recipe, but the easiest element to lose at a glance.
- Hierarchy is otherwise clear: the poem is the focal point, and the caption sits between the poem and the buttons.

### Pillar 3: Color (3/4)
- `RevealView.swift:45-47` uses `palette.secondary` with `.legibilityBacking(palette)`. Same recipe the l7k suite already covers for caption-size text; no new palette role was added.
- No hardcoded colors appear in `Features/Reveal`, `Features/Dissolved`, `Naming` or `App/AppModel.swift`.
- Not verified: contrast across all three themes at each time of day on device (covered in code by the l7k suite).

### Pillar 4: Typography (3/4)
- Fonts come from `Design/Theme.swift`: `poem(18)` for buttons, `label` (13pt) for captions, `chrome` for keepsake leads, and `display(34)` for names. All use `relativeTo:` text styles, so they scale with Dynamic Type.
- Usage is four sizes across the two screens, within the existing scale, no new weights.

### Pillar 5: Spacing (2/4)
- Off-grid values in new code: `RevealView.swift:23` (`spacing: 30`), `:30` (`spacing: 18`), `:41` (`spacing: 14`). The 4pt grid is violated in three places.
- `RevealView.swift:68` pins `Spacer().frame(height: 36)` and `:27` pins `.padding(.top, 8)`. Fixed values that do not adapt to accessibility sizes.
- Partly offset by consistent `Spacer()` use and `spacing: 28` / `32` / `16` on the Dissolved screen, which sit on the grid.

### Pillar 6: Experience Design (2/4)
- Strengths: the trade state is derived only from the three server fields through `TradeBack.offer` (`RevealView.swift:18-20`). Late writers are guarded by `isStale` and the epoch bump in `release()`. Two race tests and two mutation checks cover them. VoiceOver announcements fire on `.accept` and `.passed` (`RevealView.swift:71-78`).
- BLOCKER (see Top 3, item 1): `DissolvedView.swift:69` and `:89` can hide "begin again" from VoiceOver.
- WARNING: `AppModel.tradeBack()` swallows transient errors with no user feedback (see Top 3, item 3).
- WARNING: `pollReveal` (`AppModel.swift:390-413`) keeps polling on any non-410 error with no bound beyond the server's RevealTTL. Acceptable, but the user cannot tell the reveal is stale.
- Not verified: large Dynamic Type layout, and the VoiceOver announcement feel. Both are recorded as UAT deferrals in `06-03-SUMMARY.md`.

## Files Audited
- `ios/Strangewords/Features/Reveal/RevealView.swift`
- `ios/Strangewords/Features/Reveal/TradeBack.swift`
- `ios/Strangewords/Features/Dissolved/DissolvedView.swift`
- `ios/Strangewords/App/AppModel.swift`
- `ios/Strangewords/Naming/PoemNaming.swift`
- `ios/Strangewords/Design/Theme.swift` (typography, read for the scaling check)
- `ios/Strangewords/Design/Legibility.swift` (helper definitions only)
- Phase artifacts: `06-01/02/03-SUMMARY.md`, the three PLAN files, and `06-CONTEXT.md`
