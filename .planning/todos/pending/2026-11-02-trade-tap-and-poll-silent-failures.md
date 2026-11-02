---
created: 2026-11-02T18:30:00.000Z
title: Failed trade taps and stale reveals give no user feedback
area: ios
severity: minor
files:
  - ios/Strangewords/App/AppModel.swift (tradeBack() transient catch is silent; pollReveal keeps polling on non-410 errors)
  - ios/Strangewords/Features/Reveal/RevealView.swift (no inline error surface on the reveal)
---

## Problem

Two findings from the Phase 6 reviews (06-REVIEW.md WR-03 and 06-UI-REVIEW.md Experience
Design warnings, 2026-11-02):

1. `AppModel.tradeBack()` swallows 503 `busy`, 404 and transport errors. Tapping
   "trade back" during a network blip does nothing visible — the user cannot tell
   whether the offer went through.
2. `pollReveal` keeps polling on any non-410 error with no bound beyond the server's
   RevealTTL, and the user cannot tell the reveal has gone stale.

## Solution sketch

Add a quiet inline message in the style of `submitError` (e.g. "the trade didn't go
through. try once more.") shown on the reveal when a trade call fails transiently,
cleared on the next successful action. New visible copy must join the pinned copy
tests and the robot-poet voice-rule lists in PartnerPresenceTests.
