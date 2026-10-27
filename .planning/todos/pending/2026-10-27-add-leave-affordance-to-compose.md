---
created: 2026-10-27T23:56:07.547Z
title: Add a leave affordance to Compose so a stuck session has an escape
area: ui
severity: blocker
files:
  - ios/Strangewords/Features/Compose/ComposeView.swift
  - ios/Strangewords/App/AppModel.swift:122 (resume() restores the session on relaunch)
  - ios/Strangewords/Features/Waiting/WaitingView.swift:39 (existing "step back out" pattern)
---

## Problem

During the first production TestFlight session (2026-10-27, build 0.1.0), the user got stuck
at "the stranger is with the poem now" in Compose with a partner that would never write (a
dead waiter token). Compose has NO leave affordance — the only exits are "step back out"
(Waiting) and "let it go" (Reveal). Killing the app does not help: `AppModel.resume()`
faithfully restores the in-progress session on cold launch, so the only user escape is
deleting the app (which wipes the anonymous token). A trapped user has no way to
refresh/close the encounter for up to SessionTTL (90 minutes).

## Solution

Add a quiet leave action to ComposeView (both your-turn and their-turn states), calling the
existing `AppModel.leave()` (which already POSTs /v1/session/{id}/leave and dissolves
locally). Match the ritual tone — e.g. the same quiet-chrome treatment as the Threshold gear,
or "step away" phrasing consistent with the waiting room. Consider also a gentle assist when
the partner has been silent for a long time (e.g. surface the option more visibly after N
minutes). Needs UI-SPEC treatment for copy/placement; pin copy with tests like
PartnerPresenceTests.
