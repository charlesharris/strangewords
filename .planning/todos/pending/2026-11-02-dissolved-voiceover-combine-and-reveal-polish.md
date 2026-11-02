---
created: 2026-11-02T18:30:00.000Z
title: Dissolved screen VoiceOver may hide "begin again"; Reveal spacing and copy polish
area: ios
severity: major
files:
  - ios/Strangewords/Features/Dissolved/DissolvedView.swift:69 (keepsakeBody .accessibilityElement(children: .combine) wraps the begin-again button)
  - ios/Strangewords/Features/Dissolved/DissolvedView.swift:89 (farewellBody, same pattern)
  - ios/Strangewords/Features/Reveal/RevealView.swift (off-grid spacing 14/18/30; fixed 36pt spacer)
  - ios/Strangewords/Features/Dissolved/DissolvedView.swift:41-45 (interrupted-ending copy contradicts the kept keepsake)
---

## Problem

From 06-UI-REVIEW.md (2026-11-02):

1. **Likely VoiceOver blocker (needs device confirmation):** `keepsakeBody` and
   `farewellBody` wrap their content INCLUDING `beginAgainButton` in
   `.accessibilityElement(children: .combine)`, which can merge the button into one
   custom-labelled element so a VoiceOver user cannot activate it separately. Same
   pattern as the carried Phase 5 waiting-room advisory ("step back out" swallowed).
2. Off-grid spacing in the new Reveal layout (14/18/30 against the 4pt grid) and
   fixed 36pt / 8pt values with no accessibility-size fallback.
3. Interrupted-poem-2 copy "The poem went with them." contradicts poem 1's keepsake
   name shown directly below it.

## Solution sketch

1. Keep `.combine` only on the message/keepsake VStacks; leave the button its own
   element. Confirm with VoiceOver on device (UAT item).
2. Move spacing onto the grid (12/16/32) and check the largest accessibility sizes.
3. Reword the interrupted ending (e.g. "The stranger slipped away. The first poem
   stays with you.") — pinned copy tests move with it.
