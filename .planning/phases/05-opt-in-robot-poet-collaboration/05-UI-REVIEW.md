---
phase: "05"
slug: "opt-in-robot-poet-collaboration"
audited: "2026-10-27"
baseline: 05-UI-SPEC.md (approved revision 1)
method: static source audit (native SwiftUI app; no screenshots, interaction_capture off)
overall: 17/24
---

# Phase 05 — UI Review

> Static review of the Swift source against `05-UI-SPEC.md`. Every visual, contrast, and
> VoiceOver claim below is code-derived and still needs a simulator pass (deferred manual UAT).

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | All strings match the contract exactly; voice rules pinned by tests. The toggle's VoiceOver label merges the whole helper sentence, which the spec did not intend. |
| 2. Visuals | 3/4 | Gear is top-leading and clear of the dev chips. Chip and row card follow the spec. Hierarchy holds; device rendering unverified. |
| 3. Color | 3/4 | No hardcoded colors; accent limited to the switch tint. On-track contrast ~2.3:1 in light Nature palette (spec-accepted limitation). Palette-wide text contrast asserted, not measured. |
| 4. Typography | 3/4 | Only the declared 13/15/20 tokens used. The gear glyph pins `.font(.system(size: 20))`, breaking the spec's no-fixed-size rule — does not scale with Dynamic Type. |
| 5. Spacing | 3/4 | All introduced values are multiples of 4 and on-scale. Vertical load in Compose/Reveal unverified on compact-height screens with keyboard open. |
| 6. Experience Design | 2/4 | Waiting room root combines children for VoiceOver, likely swallowing the "step back out" button (pre-existing, but in a surface this phase edited). State coverage otherwise good. |

## Top 3 Priority Fixes

1. **BLOCKER candidate (pre-existing): VoiceOver cannot reach "step back out" in the waiting room.**
   `WaitingView.swift` applies `.accessibilityElement(children: .combine)` plus a label to the whole
   root VStack, folding the button into one element. Predates Phase 5 (confirmed in history).
   Impact: a VoiceOver user cannot leave the waiting room. Fix: move the combine + label onto the
   status text group only, keeping the button separately focusable. Confirm on device before App Store.
2. **Toggle VoiceOver label carries the whole helper sentence.** `SettingsView.swift` combines title
   and helper into the Toggle label. Spec wants "Write with the robot poet, switch button, off" with
   the helper as description. Fix: title as label, helper via `.accessibilityHint(Self.helperText)`.
3. **Gear glyph ignores Dynamic Type.** `ThresholdView.swift` `settingsGear` uses
   `.font(.system(size: 20, weight: .regular))`. Fix: `@ScaledMetric(relativeTo: .body)` for the
   glyph size. Also resolves the spec contradiction between "SF Symbol scaled by the system" and
   the no-fixed-size rule.

## Additional Findings

- **Compose/Reveal vertical budget (Spacing, WARNING):** the chip adds ~32pt of stack height above
  `Spacer(minLength: 24)` in `ComposeView.swift` and `RevealView.swift`. Check on an SE-class
  device with the keyboard open.
- **Announcement "once per session" (Experience, LOW):** `ComposeView.onAppear` posts the arrival
  announcement on every mount; mounts only occur on the `.waiting → .composing` transition, so it
  is effectively once per session. Guard it if mounting behavior changes.
- **Accepted contract limitations:** switch-track contrast (~2.3:1) and palette contrast figures
  were not measured; both deferred to manual UAT per the spec.

## Disposition

All findings are advisory for the TestFlight build (none are Phase 5 regressions; finding 1 is
pre-existing). Findings 1–3 are queued as follow-up fixes before App Store submission; finding 1
should be treated as a release blocker for the public App Store release.

## Files Audited

`SettingsView.swift`, `PartnerPresence.swift`, `ThresholdView.swift`, `WaitingView.swift`,
`ComposeView.swift`, `RevealView.swift`, `Design/Theme.swift`, `App/RootView.swift`,
`App/AppModel.swift`, plus the Phase 5 plans, summaries, and `05-UI-SPEC.md`.
