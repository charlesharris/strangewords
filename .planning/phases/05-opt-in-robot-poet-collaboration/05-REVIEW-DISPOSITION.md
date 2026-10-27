---
phase: 05
review: 05-REVIEW.md
titles: json
findings:
  - id: WR-01
    severity: warning
    disposition: open
    title: "PairWithBot strands the waiter if a step after the LREM claim fails (no rollback or next-poll completion); stuck until WaitTTL"
  - id: WR-02
    severity: warning
    disposition: open
    title: "touchPresence and handleLine's idempotency re-save still do blind SaveSession writes, bypassing UpdateSession's WATCH protection (dissolution write-back; bot-line overwrite with short SW_BOT_THINK_MS)"
  - id: IN-01
    severity: info
    disposition: open
    title: "IndexForToken(\"\") matches the bot (empty Token); latent only — empty token already 410s at GetRef"
  - id: IN-02
    severity: info
    disposition: open
    title: "Abuse reports and metrics don't record that the partner was the robot poet"
  - id: IN-03
    severity: info
    disposition: open
    title: "Poet replay determinism holds only within one build; a deploy mid-poem can change the next line"
  - id: IN-04
    severity: info
    disposition: open
    title: "fallbackLine is 5 syllables even for the 7-syllable middle line, and nothing is logged when it fires"
  - id: IN-05
    severity: info
    disposition: open
    title: "envFloat accepts NaN/Inf/huge values for bot tunables; duration conversion for those is implementation-defined"
  - id: IN-06
    severity: info
    disposition: open
    title: "LocalBackend.waiting returns a matched dissolved view after leave instead of APIError.gone; newBotRig leaks its Redis client; two missing tests (opted-in AppModel poll arc; PairWithBot failure paths)"
---

# Phase 05 — Review Disposition

All findings recorded `open` at phase close. Advisory gate: none block the TestFlight ship.
WR-01 and WR-02 are queued as the first follow-up work before App Store submission (WR-02's
touchPresence half is the pre-existing CONCERNS.md known bug the plan deliberately left unchanged).
