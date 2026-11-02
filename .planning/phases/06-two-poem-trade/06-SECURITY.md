---
phase: "06"
slug: "two-poem-trade"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-11-02"
---

# Phase 06 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| client → POST /v1/session/{id}/trade | Untrusted bearer token and path id; body ignored | Bearer token (secret), session id |
| concurrent participant writes → Redis session blob | Two humans, or a human and the robot poet's settle, race to read-modify-write one key | Session state, trade flags |
| finished poem → server storage | Poem 1's lines and cached responses must not outlive the trade | Poem content (ephemeral) |
| server JSON → SessionView | Trade fields arrive from the network and gate whether the app offers a trade at all | Trade booleans, poem ordinal |
| in-flight async responses → AppModel phase | Late poll or action responses must not overwrite a newer phase | Session views |
| server trade fields → Reveal UI | The trade affordance is decided by server-derived values only | Trade booleans |
| finished poem lines → on-device keepsake | Poem text becomes a name on device; never kept or sent | Poem content (in-memory only) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-06-01 | Elevation of Privilege | handleTrade | high | mitigate | authSession binds bearer to path id and participant index before any write; 401/403 not_a_member/410 (TestTradeErrors); a caller can only set its own WantsTrade | closed |
| T-06-02 | Tampering | both-asked transition | high | mitigate | Decision re-made on UpdateSession's WATCHed fresh read in MULTI/EXEC, bounded retries then 503 busy; concurrent accepts begin exactly one poem 2 (TestConcurrentAcceptsBeginOnePoem under -race) | closed |
| T-06-03 | Tampering | handleDismiss vs trade | high | mitigate | Dismiss moved onto the same compare-and-set; stale write can never revert poem 2 to poem 1's reveal; DEC-06-01 three-case split (TestAcceptVersusLetGoRace, TestDismissAfterPoemTwoBeganDissolves, TestDismissDuringPoemOneKeepsHeadSemantics) | closed |
| T-06-04 | Information Disclosure | poem 1 content after the trade | high | mitigate | BeginNextPoem empties Lines; purgePoemCache DELs poem 1's cached responses at the transition; IdemKeys stays listed for DeleteSession; TestTradeTracer asserts zero sw:idem: keys after transition and zero sw: keys after dissolution; privacy.html states it | closed |
| T-06-05 | Information Disclosure | anonymity model | medium | mitigate | No new key builder (store.go keeps 5 "sw: literals), no new identifier, no timer; trade flags live in the TTL-bound blob; View exposes only booleans and an ordinal; token refs never refreshed by a trade | closed |
| T-06-06 | Denial of Service | repeated /trade | low | mitigate | Repeat with flag already set writes nothing (TestTradeRepeatIsIdempotent); limitBody caps the body; per-IP limiter applies | closed |
| T-06-07 | Elevation of Privilege | old clients (TestFlight 0.1.0) | medium | mitigate | Poem 2 needs every participant's explicit /trade; a client that never calls it dissolves as before (TestOldClientNeverTrades, TestTradeIgnoresRequestBody) | closed |
| T-06-08 | Tampering | robot poet acceptance pacing | medium | mitigate | BotReadyAt armed at the human's first offer and re-checked on the fresh read inside UpdateSession (TestBotTradesBack) | closed |
| T-06-09 | Tampering | handleLine's post-completion idempotency re-save | low | accept | Plain SET microseconds after the completing save in the same request; human timing cannot interleave an offer; no state corrupted | closed |
| T-06-10 | Spoofing | SessionView trade-field decode | medium | mitigate | decodeIfPresent only, defaulting closed when absent (tradeFieldsDefaultWhenAbsent); old server never shows a trade (oldServerRevealNeverPollsOrTrades) | closed |
| T-06-11 | Tampering | late writers after release() | medium | mitigate | release() bumps the epoch and stops polling; every reveal writer guards isStale(e) after each await; two red-first race tests plus two mutations prove both guards load-bearing | closed |
| T-06-12 | Information Disclosure | device persistence | low | mitigate | No new UserDefaults key; app "sw. literal count stays 2 (grep gate); HostIsolationTests unmodified and green; tests write only to suite-named containers | closed |
| T-06-13 | Denial of Service | reveal polling | low | accept | Poll runs only while tradeOpen at the existing 3 s cadence, stops on close/410/poem 2/release; server bounds with RevealTTL | closed |
| T-06-14 | Information Disclosure | AppModel.keepsakes | low | mitigate | Names coined on device from in-memory lines, held in an in-memory list cleared by begin() and reset(); nothing written or sent; privacy.html's on-device sentence stays true | closed |
| T-06-15 | Repudiation | robot-poet trade copy | medium | mitigate | Five robot-poet trade strings join PartnerPresenceTests' voice-rule lists (T-05-13 extended); human strings never mention the robot | closed |
| T-06-16 | Spoofing | trade affordance rendering | medium | mitigate | RevealView derives state only through TradeBack.offer of the three server fields (grep-anchored); pure mapping covered over all 8 combinations; button exists only for .offer and .accept | closed |
| T-06-17 | Tampering | PoemNaming goldens | medium | mitigate | Category removal left all six golden names and leads byte-identical (grep gates + golden test); documented as a column removal so a draw-order regression cannot hide behind a re-capture | closed |
| T-06-SC | Tampering | npm/pip/cargo/SPM installs | low | accept | No package installed or added; Go module deps unchanged; zero third-party iOS dependencies kept | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-06-01 | T-06-09 | handleLine's post-completion idempotency re-save is a plain SET in the same request window; an interleaving offer requires sub-millisecond human timing and corrupts no state (offerer's poll self-heals) | plan-time register (06-01-PLAN.md) | 2026-11-02 |
| R-06-02 | T-06-13 | Reveal polling is bounded by RevealTTL and the existing 3 s cadence; load matches today's compose polling | plan-time register (06-02-PLAN.md) | 2026-11-02 |
| R-06-03 | T-06-SC | No dependency added in any ecosystem during phase 6 | plan-time register (all plans) | 2026-11-02 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-11-02 | 18 | 18 | 0 | orchestrator (L1 short-circuit: plan-time register, grep-verified mitigations, cited tests present) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-11-02
