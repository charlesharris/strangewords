---
phase: "05"
slug: "opt-in-robot-poet-collaboration"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-10-27"
---

# Phase 05 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| iOS client → POST /v1/enter | Untrusted JSON body; allowBot is a caller preference, never authority over anyone else | Opt-in bit, optional push token |
| iOS client → GET /v1/waiting, GET /v1/session/{id} | Untrusted bearer token; these polls drive the bot claim and bot lines | Bearer token |
| gateway → Redis | Queue ownership decided by single atomic commands (LPOP vs LREM); session writes via WATCH/MULTI/EXEC | Session/queue state (TTL-bound) |
| botplayer → session text | Bot output joins the poem shown to the human and must meet the same content rules | Generated poem lines |
| user → settings toggle → UserDefaults | Local preference persisted on-device; defaults OFF, outside the sw. identity namespace | One preference bit |
| server view → SessionView decode → screen | The disclosure travels server → model → chip/copy; a gap would hide the robot poet | partnerIsBot flag |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-05-01 | Elevation of Privilege | handleWaiting fallback / matchmaker.PairWithBot | high | mitigate | Bot created only from the caller's own WaitEntry when AllowBot set; never enqueued. TestBotNeverPairsWithoutOptIn, TestOverlappingOptedInHumansPairTogether | closed |
| T-05-02 | Spoofing | Session.ViewFor PartnerIsBot | high | mitigate | PartnerIsBot computed only in ViewFor from Participant.Bot (session.go:140); no request field read into it. Tracer + full-poem tests assert it on all views | closed |
| T-05-03 | Tampering | enterRequest.AllowBot decode | medium | mitigate | Lenient decode: absent/false/wrong-typed → false (fail-closed); 5 fail-closed subtests | closed |
| T-05-04 | Information Disclosure | bot-path Redis state | high | mitigate | allowBot lives only on TTL-bound WaitEntry, deleted at claim; store.go `"sw:` literal count still 5; TestBotPoemCompletesAndLeavesNoKeys asserts zero sw: keys after dissolution | closed |
| T-05-05 | Tampering | human-vs-bot race on one waiter | medium | mitigate | LREM claim vs LPOP pop: exactly one owner; lost claim falls through to waiting. TestHumanVsBotRaceSingleSession (50x under -race) | closed |
| T-05-06 | Denial of Service | bot session creation by opted-in clients | low | accept | One bot session per wait; per-IP rate limiter covers /v1/enter + /v1/waiting; SW_BOT_WAIT_SECONDS<=0 kill switch (config.go:52) | closed |
| T-05-07 | Tampering | botplayer line content | medium | mitigate | Every bot line passes sessions.CleanLine with CleanLine-identical fallback (botplayer.go:41); TestNextLineIsCleanAndOnTarget sweeps 200 ids | closed |
| T-05-08 | Denial of Service | restart / auto-stop mid bot poem | low | mitigate | No worker, no in-process state; lines replayed from Redis on each poll. Restart instance in TestBotPoemCompletesAndLeavesNoKeys | closed |
| T-05-09 | Repudiation | partial failure after won claim (SaveSession fails) | low | accept | Waiter keeps wait entry until WaitTTL, then the existing no-one-came path; only occurs while Redis is failing | closed |
| T-05-10 | Spoofing | SessionView decode | high | mitigate | Tolerant decode: decodesPartnerIsBotWhenPresent, partnerIsBotDefaultsFalseWhenAbsent; model's only path to the flag | closed |
| T-05-11 | Elevation of Privilege | AppModel.begin / SettingsStore default | medium | mitigate | Absent key reads false; begin() sends captured AppModel.allowBot; beginSendsHumansOnlyByDefault proves fresh-install false | closed |
| T-05-12 | Information Disclosure | pref.allowBot in UserDefaults | low | mitigate | Key outside sw. namespace (SettingsStore.swift:18; app still has exactly 2 "sw. literals); never tied to the token; one bit, not an identifier; HostIsolationTests unchanged and green | closed |
| T-05-13 | Repudiation | disclosure copy | medium | mitigate | Voice-rule tests ban "bot"/"ai"/"assistant"/"chatbot" and "stranger"/"someone" in robot-partner copy; settings helper says "software on our server, not a person". Spoken VoiceOver behaviour deferred to manual UAT | closed |
| T-05-14 | Tampering | old server receiving allowBot | low | accept | Older server ignores unknown JSON keys → users stay humans-only (fail-safe); server deploys from main via CI before the app ships | closed |
| T-05-15 | Tampering | settleBot vs concurrent session writers | medium | mitigate | settleBot re-decides on UpdateSession's fresh read; persists only via WATCH/MULTI/EXEC (gateway.go:448) — concurrent write or delete aborts the save. TestStaleSettleDoesNotOverwriteHumanLine under -race | closed |
| T-05-16 | Spoofing | PartnerPresence chip and their-turn copy | high | mitigate | Chip/copy derive only from session.partnerIsBot through pure functions (PartnerPresence.swift) pinned by PartnerPresenceTests (15 tests); caption nil for humans; Compose/Reveal anchors grep-verified | closed |
| T-05-SC | Tampering | package installs (go modules / SPM) | low | accept | No package installed or added in any plan; go.mod untouched since 73ba1e9; zero third-party iOS dependencies | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-05-01 | T-05-06 | Bot sessions cost the same Redis as human ones; rate limiter + kill switch bound abuse | plan 05-01 (user-approved plan) | 2026-10-27 |
| R-05-02 | T-05-09 | Failure window exists only while Redis itself is failing, when every route fails anyway | plan 05-01 (user-approved plan) | 2026-10-27 |
| R-05-03 | T-05-14 | Fail-safe: unknown JSON key ignored → humans-only; deploy order (server first via CI) enforced by the ship pipeline | plan 05-02 (user-approved plan) | 2026-10-27 |
| R-05-04 | T-05-SC | No dependency changes in the phase | plans 05-01/02/03 | 2026-10-27 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-10-27 | 17 | 17 | 0 | gsd-secure-phase (L1 short-circuit: register authored at plan time, all mitigations grep-verified) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-10-27
