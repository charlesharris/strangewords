---
gsd_state_version: "1.0"
current_phase: 02
current_phase_name: iOS Client Logic Suites
status: verifying
stopped_at: Completed 02-04-PLAN.md
last_updated: "2026-10-26T23:43:50.752Z"
last_activity: 2026-10-26
last_activity_desc: Phase 02 execution started
state_head: 9147a60c243ce3cf2ed0de3eabecfd198a40706c
progress:
  total_phases: 4
  completed_phases: 1
  total_plans: 6
  completed_plans: 6
  percent: 25
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-14)

**Core value:** A trustworthy, automated proof that the core experience works — so every future change can be verified against a known-good baseline instead of memory and manual poking.
**Current focus:** Phase 02 — iOS Client Logic Suites

## Current Position

Phase: 02 (iOS Client Logic Suites) — EXECUTING
Plan: 4 of 4
Status: Phase complete — ready for verification
Last activity: 2026-10-26 - Completed quick task 261026-p8l: Upgrade the robot poet to a generative grammar

Progress: [███░░░░░░░] 25%

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

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-15T18:38:49.062Z
Stopped at: Completed 02-04-PLAN.md
Resume file: None
