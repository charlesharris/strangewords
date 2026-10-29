# Phase 6 Context — Two-Poem Trade

Captured 2026-10-29 in conversation with the user (via AskUserQuestion). These are LOCKED user
decisions; planner and executors honor them without revisiting.

## Locked decisions

- **D-01 — Reveal cadence: after each poem.** Finish poem 1 → the pair sees it together on the
  Reveal screen → (optionally) trade back → poem 2 → its own reveal → dissolution. The existing
  single-poem rhythm is kept and doubled, not replaced by a combined end reveal.
- **D-02 — The trade is OFFERED, not automatic.** After poem 1's reveal, either participant may
  offer to trade back; poem 2 begins only when BOTH accept. Declining — or leaving, or simply
  walking away until TTL/presence lapses — dissolves exactly as today. (User explicitly chose
  "Offered" over the recommended automatic option.)
- **D-03 — Roles swap for poem 2.** Whoever wrote lines 1 and 3 of poem 1 writes line 2 of poem 2;
  the other participant opens and closes poem 2. The session model's encounter/poem split
  (`StartIndex` separate from poem fields, per plan.v1.md's "continue with this person" design
  intent) is the intended mechanism.
- **D-04 — Keepsakes: one coined name per poem.** The on-device coiner runs once per completed
  poem (two keepsakes after a full trade). Nothing new leaves the device.
- **D-05 — The keepsake's "kind" line is REMOVED everywhere.** `CoinedName.kind` ("a scented
  candle", "a beer", …) and its rendering line (DissolvedView keepsakeBody's kind Text) go away —
  for single poems too, not just trades. The lead and the coined name stay.
- **D-06 — Bot sessions trade too.** The robot poet accepts a trade offer automatically (with its
  usual think-time pacing, never instantly) and continues its deterministic seeded replay into
  poem 2. Consistency with human encounters is the point.

## Orchestrator-interpreted defaults (reasonable, reversible — flag in the plan if they bind)

- The offer lives on the Reveal screen beside "let it go" — a quiet "trade back" affordance in the
  app's existing ritual voice. No push, no modal pressure; the default path (doing nothing,
  dismissing) remains dissolution.
- An offer with no answer simply ages out with the session (RevealTTL/SessionTTL discipline as
  today); no new timers beyond existing TTLs.
- Anonymity model unchanged: no new identifiers, all new state TTL-bounded inside the existing
  session blob, zero `sw:` key-class growth preferred (the store's 5-literal structural gate).
- Wire changes must be tolerant for old clients (an old client that never offers/accepts simply
  dissolves as today — fail-safe, like allowBot).

## Constraints carried from the project

- Go stdlib-first server; no third-party iOS deps; `ios/project.yml` is the source of truth.
- LocalBackend/FakeBackend mirror every Backend protocol change (parity rule).
- Automated-only verification; manual UAT items recorded, not performed.
- iOS tests: no wall-clock sleeps, models via TestSupport makeModel, suite via scripts/test-ios.sh
  (currently 117 passed / 1 skipped canary — PoemNaming golden tests will need deliberate
  re-capture when `kind` is removed, call that out in the plan).
