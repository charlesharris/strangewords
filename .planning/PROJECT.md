# Stranger Words

## What This Is

An anonymous, ephemeral iOS app ("Stranger Words") for writing a 3-line poem with a stranger, then letting it go. A SwiftUI client (iOS 17+) drives a phase state machine against a Go backend (live on Fly.io, Redis-backed, all state TTL-bounded); no accounts, no history — the only durable keepsake is a whimsical name the poem coins for itself on-device.

The current milestone is not a new feature: it is **verifying the current state under GSD** — exercising everything automated, closing the iOS automated-test gap, fixing what breaks, and capturing the result as a validated baseline that future milestones (push, safety, TestFlight) build on.

## Core Value

A trustworthy, automated proof that the core experience works — so every future change can be verified against a known-good baseline instead of memory and manual poking.

## Requirements

### Validated

Inferred from the existing codebase (`.planning/codebase/`, `docs/STATUS.md`); live-verified informally, now to be re-proven under this milestone.

- ✓ Anonymous matchmaking: enter → queue or atomic pair (Redis LPOP), bearer `participantToken`, no durable identity — existing
- ✓ Turn-based haiku composition: `Form` registry (5-7-5), round-robin `TurnPolicy`, server-authoritative validation + banned-term screener, idempotent line submission — existing
- ✓ Full arc on the client: threshold → waiting → compose → reveal → dissolve → dissolved, polling every 3s, `AppModel` state machine — existing
- ✓ Clean dissolution: session + token teardown, zero-keys-after-dissolution invariant covered by Go tests — existing
- ✓ Go backend test suite: `go test ./...` via miniredis — turn policy, validation, full poem, idempotency, teardown, match race, anonymity invariant — existing
- ✓ End-to-end tooling: robot poet (`cmd/bot`), `live_test.sh`, `run_test_server_and_robot_poet_friend.sh` — existing
- ✓ Deploy-hardened backend live on Fly.io: Prometheus metrics, rate limiting, body cap, timeouts, panic recovery, healthz — existing
- ✓ Theme system (Nature / Sci-Fi / Fantasy), per-theme dissolutions, time-of-day palettes, haptics, bundled fonts, keepsake naming (`PoemNaming`), syllable hints — existing
- ✓ Mock backend (`LocalBackend`) replicating server semantics for the one-simulator dev loop — existing
- ✓ All existing automated checks run clean: `go test ./...`, backend build, iOS build (XcodeGen + xcodebuild), `gofmt -l server/` empty — Phase 1
- ✓ iOS test target wired into the XcodeGen project (`project.yml`) and runnable headlessly from the command line: hosted `StrangewordsTests` + `scripts/test-ios.sh` (xcresult-derived verdict, zero-tests guard, six-path self-check) — Phase 1

### Active

- [ ] End-to-end automated verification: scripted session via the robot poet proves match → turns → completion → dissolution against a locally running server
- [ ] iOS unit test suite exists and passes: `AppModel` state machine, `LocalBackend` semantics, `Syllables`, `PoemNaming` determinism
- [ ] Anything found broken or drifted during verification is fixed within this milestone (fix-as-we-go)
- [ ] Verified state captured as the GSD baseline: requirements traceability + verification evidence recorded in `.planning/`

### Out of Scope

- Push notifications (Phase 2) — blocked on Apple Developer account; separate milestone
- TestFlight / device signing / App Store — needs the Apple account; separate milestone
- iOS-side safety rails (in-app report, EULA gate) — next milestone after the baseline is trusted
- Manual feel pass / Dynamic Type audit / final copy — user chose automated checks only for this milestone
- Live Fly.io production verification — this milestone verifies locally/automated; prod checks deferred
- CI pipeline for the new tests — valuable follow-on, but not required to establish the baseline
- New features (4th theme, new forms, per-theme tuning) — nothing new until the baseline is proven

## Context

- Brownfield: full codebase map exists at `.planning/codebase/` (ARCHITECTURE, STACK, STRUCTURE, CONVENTIONS, TESTING, INTEGRATIONS, CONCERNS), mapped at commit `d441ac6`.
- `docs/STATUS.md` is the human-written state-of-the-world; its claims are exactly what this milestone turns into verified fact.
- The Go side is well-tested (miniredis, no external services). The iOS side has **no test target at all** — `project.yml` defines only the app target. On-device logic (`AppModel`, `LocalBackend`, `Syllables`, `PoemNaming`) is pure/injectable and testable by design.
- `LocalBackend` intentionally duplicates server semantics in Swift; tests pinning its behavior also guard the mock/real drift risk flagged in the codebase map.
- `PoemNaming` is deterministic by construction (FNV-1a seed → SplitMix64), which makes it directly unit-testable.
- Working-tree note at milestone start: uncommitted edits exist in `docs/STATUS.md`, `ios/project.yml`, `run.sh`, `server/DEPLOY.md`, `server/internal/config/config.go`, plus an untracked `Strangewords.entitlements` — verification should start from a reconciled tree.

## Constraints

- **Tech stack**: Go stdlib-first backend, SwiftUI iOS 17+, no third-party iOS dependencies — established project convention
- **Tooling**: `.xcodeproj` is gitignored; `ios/project.yml` (XcodeGen) is the source of truth — test targets must be added there
- **Anonymity model**: tests must not introduce anything that persists identity or poem content beyond the encounter
- **Automated-only**: this milestone's verification must run without a human driving a simulator; manual UAT is explicitly deferred

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Verification depth: automated checks only | Repeatable proof first; manual feel pass and prod checks deferred | — Pending |
| Fix-as-we-go on failures | Baseline should end clean, not just measured | — Pending |
| Add a real iOS unit test suite (not just smoke tests) | iOS is the untested half; baseline isn't trustworthy without it | — Pending |
| Test verdict comes only from the xcresult summary, never xcodebuild's exit/banner | xcodebuild prints TEST SUCCEEDED on zero-test runs; a false green defeats the baseline | ✓ Good — proven by six-path self-check (Phase 1) |
| Commits allowed directly on `main` (`git.allow_default_branch_commits: true`) | `branching_strategy: none` is the project workflow; user authorized at the Phase 1 gate | ✓ Good |
| Cold-boot retry path accepted as unverified, carried to Phase 4 | Crash signature unproducible on demand (plan 01-02 `verification: backstop`); no-retry-on-real-failure half proven by canary | — Pending (override recorded in 01-VERIFICATION.md) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-14 after Phase 1*
