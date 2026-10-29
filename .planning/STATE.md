---
gsd_state_version: "1.0"
current_phase: 05
current_phase_name: Opt-In Robot Poet Collaboration
status: verifying
stopped_at: Completed 05-03-PLAN.md
last_updated: "2026-10-27T23:10:50.884Z"
last_activity: 2026-10-27
last_activity_desc: Phase 05 execution started
state_head: 7a6a0bce081e4484650af1d08c20b56fe41a3552
progress:
  total_phases: 5
  completed_phases: 1
  total_plans: 11
  completed_plans: 9
  percent: 20
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-14)

**Core value:** A trustworthy, automated proof that the core experience works — so every future change can be verified against a known-good baseline instead of memory and manual poking.
**Current focus:** Phase 05 — Opt-In Robot Poet Collaboration

## Current Position

Phase: 05 (Opt-In Robot Poet Collaboration) — EXECUTING
Plan: 3 of 3
Status: Phase complete — ready for verification
Last activity: 2026-10-27 — Phase 05 execution started

Progress: [██░░░░░░░░] 20%

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: -
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 2 | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 9min | 3 tasks | 10 files |
| Phase 01 P02 | 4min | 2 tasks | 7 files |
| Phase 02 P01 | 9min | 3 tasks | 8 files |
| Phase 02 P02 | 4 min | 2 tasks | 2 files |
| Phase 02 P03 | 6 min | 3 tasks | 2 files |
| Phase 02 P04 | 3 min | 2 tasks | 3 files |
| Phase 05 P01 | 14 min | 3 tasks | 9 files |
| Phase 05 P02 | 16 min | 2 tasks | 12 files |
| Phase 05 P03 | 20 min | 1 tasks | 7 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Coarse 4-phase structure. Test seams (IOST-05) folded into the iOS suites phase instead of standing alone.
- [Roadmap]: Phases 2 (iOS suites) and 3 (server e2e + wire contract) depend only on Phase 1 and can run in parallel.
- [Roadmap]: FIX-01 mapped to Phase 4 to close the ledger. Fixes still land in whichever phase surfaces the failure.
- [Research]: Swift Testing with `@Suite(.serialized)` for shared-state suites; Go e2e uses in-process miniredis behind `-tags e2e` (no Docker).
- [Phase 01]: D-13: gofmt -w the four drifted server files in a separate whitespace-only commit (57ba34e), after the two D-02 reconciliation commits; gofmt -l server/ empty at HEAD — Whitespace-only proven by empty git diff -w; keeps 'every existing check passes' true without weakening tests
- [Phase 01]: Test-ios verdict comes only from the xcresult summary (Passed, 0 failed, >0 passed, >0 total); retry only on the cold-boot bootstrap signature — xcodebuild banner and exit code are unreliable (zero-test runs print TEST SUCCEEDED); proven by selfcheck case zero
- [Phase 01]: Pinned simulator is shut down unconditionally at run end, even if pre-booted (D-07) — Locked user decision; ends a run.sh session on the same simulator, documented in script header (T-01-09)
- [Phase 02]: [02-01] D-03 session default read as APIClient.shared with the existing ephemeral 15 s URLSession (not URLSession.shared); needs developer confirmation — URLSession.shared would change timeout to 60 s and add persistent cookies/cache, contradicting IOST-05 and the anonymity posture; reversible via one default argument
- [Phase 02]: [02-01] OBS-1: a waiter who leaves before a match is never reported to the server (AppModel.leave only calls the backend when a session id exists); pinned by leaveWhileWaitingSendsNoLeaveCall, not changed — Server has no wait-leave endpoint; carry to Phase 4 ledger
- [Phase 02]: Plan 02-02: stale-writer race fixed with a session epoch (bumped in begin/reset/dissolve) plus Task.isCancelled via isStale(e), checked after every await and first in apply(_:epoch:) — leave() never cancels action tasks, so the epoch covers begin/resume/submit while isCancelled covers poll tasks (D-08); seven red-first regression tests pin it
- [Phase 02]: 02-03: LocalBackend.cleanLine ports sessions.CleanLine rule for rule (NFC, control reject, zero-width strip, scalar-counted 100 cap, server messages); banned-term screener stays server-only (DRFT-01)
- [Phase 02]: 02-03: Mock leave/dismiss now dissolve and erase the poem (D-11 judgment, reversible, not a defect); turn-violation and idempotent-replay divergences pinned as DRIFT
- [Phase 02]: 02-04: PoemNaming goldens not re-captured; host candidates matched iOS 18.6 simulator
- [Phase 02]: 02-04: Syllables known misses pinned at current wrong counts (D-12), heuristic unchanged
- [Phase 05]: 05-01: robot poet is a tokenless, pre-dismissed flagged participant, never a queue member; bot lines are poll-driven poet replays persisted only via WATCH/MULTI/EXEC UpdateSession (no worker, lock or new Redis key)
- [Phase 05]: 05-01: think time is armed in handleLine (BotReadyAt) so a stale settle cannot slip a bot line in right after the human's; partnerIsBot computed only in ViewFor
- [Phase 05]: 05-02: pref.allowBot lives outside the sw. namespace (SettingsStore, sibling of TokenStore) so TokenStore.clear() and HostIsolationTests are untouched
- [Phase 05]: 05-02: begin() captures AppModel.allowBot before spawning its task; Backend.enter has no overload omitting allowBot
- [Phase 05]: 05-02: LocalBackend opted-in users always wait the full botWindow (mock has no human pool to race); recorded as DRIFT
- [Phase 05]: 05-03: their-turn secondary line stays locked UI-SPEC copy; voice-rule test checks the robot poet is named on the primary line

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 2]: Late-poll race in `AppModel` (no `Task.isCancelled` check after `await`) is an expected finding.
- [Phase 3]: `WaitEntry` leak in `Store.DeleteSession` is expected to fail the zero-keys assertion; triage it as a real bug.
- [Phase 4]: No iOS 17.x simulator runtime is installed, so the 17.0 deployment target is tested only on 18.6. Record this on the not-verified list or install a runtime.
- [Phase 4]: Carry-overs from Phase 1 verification: cold-boot retry path unexercised (override recorded in 01-VERIFICATION.md); App Attest entitlements not applied in unsigned test runs; no concurrent-run lock between harness runs.
- [Phase 4]: Code review 01-REVIEW.md left 4 advisory warnings open (stale SW_VERIFY_OUT verdicts, boot failure reported as exit 1, nondeterministic simulator pick, fail-open AppAttestAppID undocumented in DEPLOY.md) — see 01-REVIEW-DISPOSITION.md.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 261026-n2i | Rebrand backend host and bundle id for the strangewords.app domain switch | 2026-10-26 | 8a95143 | [261026-n2i-rebrand-backend-host-and-bundle-id-for-t](./quick/261026-n2i-rebrand-backend-host-and-bundle-id-for-t/) |
| 261026-nd8 | Repin dev scripts to current-generation simulators for Xcode 27 | 2026-10-26 | fe34596 | [261026-nd8-repin-dev-scripts-to-current-generation-](./quick/261026-nd8-repin-dev-scripts-to-current-generation-/) |
| 261026-no9 | Add App Store privacy manifest and export compliance flag | 2026-10-26 | 9920b1b | [261026-no9-add-app-store-privacy-manifest-and-expor](./quick/261026-no9-add-app-store-privacy-manifest-and-expor/) |
| 4 | fast: opt portrait-only iPad out of multitasking (UIRequiresFullScreen) for App Store validation | 2026-10-26 | ccffe48 | — |
| 261026-og8 | Port brewfighter archive-upload script for TestFlight pushes | 2026-10-26 | 16177e0 | [261026-og8-port-brewfighter-archive-upload-script-f](./quick/261026-og8-port-brewfighter-archive-upload-script-f/) |
| 261026-p8f | Serve a privacy policy page from the backend | 2026-10-26 | 4b0f71c | [261026-p8f-serve-a-privacy-policy-page-from-the-bac](./quick/261026-p8f-serve-a-privacy-policy-page-from-the-bac/) |
| 261026-p8l | Upgrade the robot poet to a generative grammar | 2026-10-26 | 9147a60 | [261026-p8l-upgrade-the-robot-poet-to-a-generative-g](./quick/261026-p8l-upgrade-the-robot-poet-to-a-generative-g/) |
| 8 | fast: fix run.sh Simulator launch for Xcode 27 (DeviceHub) + Swift 6 isolation warning | 2026-10-26 | e00a580 | — |
| 9 | fast: rename user-facing app name to "Strange Words" | 2026-10-27 | eda3ba3 | — |
| 261029-jhu | Server + wire: wait-leave path so abandoned waiters never dead-pair (endpoint, liveness skip, bind-protocol races, iOS leaveWait) | 2026-10-29 | 02d0b7e | .planning/quick/261029-jhu-server-wire-add-a-wait-leave-path-so-abandoned-waiters-never |
| 261029-jhv | iOS: quiet step-away escape from Compose with confirmation, copy pinned by tests | 2026-10-29 | d2ea3a6 | .planning/quick/261029-jhv-ios-add-a-quiet-leave-affordance-to-composeview-both-your-tu |

### Roadmap Evolution

- Phase 5 added: Opt-In Robot Poet Collaboration (2026-10-26)

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-27
Stopped at: Phase 5 executed (3/3 plans), all gates passed (security 17/17, UI 17/24 advisory, code review 0C/2W/6I, verifier 17/17 must-haves). Status human_needed — manual UAT in 05-UAT.md (run /gsd-verify-work 5). Server deployed to api.strangewords.app; TestFlight build 0.1.0 (202610272330) uploaded (a stray "1.0" build from a version-wiring bug, fixed in 43c4cd5, should be expired in ASC). App renamed "Strange Words" (ASC rename + external beta group are user-side steps).
Resume file: None
