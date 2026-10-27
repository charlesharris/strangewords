# Phase 5 Context: Opt-In Robot Poet Collaboration

**Gathered:** 2026-10-26 — decisions locked by the user in conversation; do not revisit.

## Locked Decisions

1. **Strict opt-in, default OFF.** A user is never paired with the bot unless they enabled the setting. No dark patterns; the default experience is humans-only.
2. **Settings UI: quiet gear on the Threshold.** A small, unobtrusive settings affordance on the entry screen opening a minimal sheet containing the one toggle (persisted via the existing UserDefaults-backed TokenStore pattern or a sibling store — UserDefaults use is already declared CA92.1 in PrivacyInfo.xcprivacy). The sheet should leave room for future settings (safety/EULA later), but this phase ships only the bot toggle.
3. **Pairing rule: bot as fallback after a wait window.** Opted-in users still try for a human first. Only if no human pairs within a tunable window (~20–30s, mark `[TUNABLE]`) does the bot step in. Two opted-in humans who overlap must pair with each other, never each get a bot. The mechanism (server-side pairing vs. bot-client polling for lonely opted-in waiters) is the planner's/researcher's call — the behavior above is what's fixed.
4. **Disclosure: named presence.** The session UI quietly labels the partner as the robot poet (e.g. in the compose header where turn state shows), visible for the whole session — matching the repo's existing "robot poet friend" voice. No undisclosed bots, ever.
5. **Bot generation: the existing `server/internal/poet` package** (quick task 261026-p8l). No external AI/API calls.

## Constraints carried from the project

- Wire-contract change (e.g. `allowBot` on `POST /v1/enter`) must be mirrored in: server handlers, `ios/Strangewords/Net/Models.swift`, the `Backend` protocol, `APIClient`, **and `LocalBackend`** (mock/real parity is a standing convention).
- Anonymity model holds: the opt-in flag must not persist beyond the encounter's existing TTLs or become an identifier.
- Tests on both sides (Go + Swift) are required; this project's current milestone is an automated-verification baseline — new behavior ships with automated proof.
- Backward compatibility: the already-shipped TestFlight build 0.1.0 sends no flag; absent flag must mean `allowBot=false` (matches default OFF).

## Out of scope for this phase

- Push notifications, safety/EULA UI, public-link beta hardening.
- Any change to the poet package's generation quality (separate concern).
