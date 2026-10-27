---
status: testing
phase: 05-opt-in-robot-poet-collaboration
source: [05-VERIFICATION.md]
started: 2026-10-27T23:30:00Z
updated: 2026-10-27T23:30:00Z
---

## Current Test

number: 1
name: Backgrounded-human pacing against the real server
expected: |
  Opt in, enter, let the bot claim you (~25s), then background the app mid-poem.
  On returning, the bot's line appears promptly on the next poll (no stuck turn,
  no instant unnatural reply). Declared a backstop truth in 05-01-PLAN.md.
awaiting: user response

## Tests

### 1. Backgrounded-human pacing against the real server
expected: Opt in, get the bot after the ~25s window, background the app mid-poem; on return the bot's line arrives on the next poll with natural think-time pacing.
result: [pending]

### 2. Visual pass in mock mode (SW_LOCAL_MOCK)
expected: Gear, settings sheet, and robot-poet chip render correctly across all 9 theme × time-of-day palettes; Dynamic Type sizes hold; iPad shows the sheet as a form sheet. Also settles assumption A2 — the sheet inherits the scene's environment (theme + palette).
result: [pending]

### 3. VoiceOver pass
expected: The gear is reachable and labeled; the switch reads "Write with the robot poet, switch button, off/on"; the close button is reachable; the chip is announced in Compose/Reveal; the one-time arrival announcement ("You're now writing with the robot poet.") fires once. Known pre-existing issue to confirm: the waiting room's combined root may swallow "step back out" (UI-REVIEW finding 1).
result: [pending]

### 4. Judgment sign-off: no nudging, honest disclosure
expected: Nothing in the flow nudges users to opt in (default OFF, quiet gear, neutral copy), and the disclosure is never softened — "writing/written with the robot poet" appears whenever the partner is the bot. Verifier's non-authoritative read: pass.
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
