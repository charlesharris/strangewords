# Roadmap: Stranger Words

## Overview

This milestone ships no features. It turns the claims in `docs/STATUS.md` into repeatable, automated proof and records the result as a known-good baseline. Phase 1 starts from a reconciled tree with every existing check green, and sets up an iOS test harness whose verdict can be trusted. After that, two independent tracks run in parallel. Phase 2 covers the on-device logic: syllables, keepsake naming, the mock backend, and the AppModel arc. Phase 3 covers the real server end to end and the wire contract between server and client. Phase 4 wraps every stage in one command, closes out the fix-as-we-go ledger, and commits the blessed run as the GSD baseline that the push, safety, and TestFlight milestones will build on.

**Fix-as-we-go:** a failure surfaced in Phases 1-3 is fixed in the phase that finds it, and each fix comes with a regression test. FIX-01 is mapped to Phase 4, where the full run confirms that every finding is either fixed or recorded as an expected failure with a documented reason.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Clean Tree & Trustworthy iOS Harness** - Reconcile the working tree, get all existing checks green, and prove a headless iOS test run whose verdict can't lie (completed 2026-10-14)
- [ ] **Phase 2: iOS Client Logic Suites** - Add minimal test seams and pin Syllables, PoemNaming, LocalBackend, and the AppModel arc with fast, deterministic tests
- [ ] **Phase 3: Server End-to-End & Wire Contract** - Prove match through dissolution against the real server with zero keys left behind, and decode real server JSON in Swift
- [ ] **Phase 4: One-Command Verify & Baseline** - Wrap every stage in one command, close the fix ledger, and commit the dated baseline evidence

## Phase Details

### Phase 1: Clean Tree & Trustworthy iOS Harness

**Goal**: The developer starts from a deliberate, reconciled tree where every existing check passes, and can run an iOS test suite headlessly with a pass/fail verdict that cannot report a false green
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: HARN-01, HARN-02, HARN-03
**Success Criteria** (what must be TRUE):
  1. Each of the six files that were uncommitted or untracked at milestone start (`docs/STATUS.md`, `ios/project.yml`, `run.sh`, `server/DEPLOY.md`, `server/internal/config/config.go`, `ios/Strangewords/Strangewords.entitlements`) has been deliberately committed or reverted, and `git status` is clean
  2. `go test ./...`, `go vet ./...`, and `go build ./...` pass in `server/`, and `xcodegen generate` followed by `xcodebuild build` succeeds for the app
  3. After a fresh `xcodegen generate`, the scheme has a test action and a hosted unit-test target, and a trivial test runs headlessly from the CLI and passes
  4. The CLI test command exits non-zero when a test fails AND when zero tests execute (e.g. a mistyped `-only-testing` filter); the verdict comes from the result bundle, not from xcodebuild's banner
  5. While tests run, the host app launches in local-mock mode, so no test can reach the production server through a leftover token

**Notes**: Research flag: before relying on scheme test env / `TEST_RUNNER_` forwarding to isolate the host app, confirm it with a one-line probe. Also confirm the test bundle ID (`com.strangerwords.us.tests`) against the bundle-ID change in the working tree.
**Plans**: 2/2 plans complete

Plans:
**Wave 1**
- [x] 01-01-PLAN.md — Reconcile the dirty tree in two concern-split commits, accept gofmt output in a separate formatting-only commit, and prove every existing check green, including an empty `gofmt -l server/` and a fresh-clone build (HARN-01)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 01-02-PLAN.md — Hosted StrangewordsTests target, isolated scheme test action, `scripts/test-ios.sh` result-bundle verdict, and a re-runnable self-check proving it cannot report a false green (HARN-02, HARN-03)

### Phase 2: iOS Client Logic Suites

**Goal**: The on-device logic (syllable counting, keepsake naming, the mock backend, and the full AppModel arc) is pinned by fast, deterministic unit tests that catch regressions without a human at a simulator
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: IOST-01, IOST-02, IOST-03, IOST-04, IOST-05
**Success Criteria** (what must be TRUE):
  1. Poll interval, mock backend delays, API base, and the `TokenStore` defaults container are injectable as defaulted init parameters, and the app built with defaults behaves as before (same 3s poll, same mock timings, same server)
  2. `Syllables` table-driven tests and `PoemNaming` golden poem-to-name tests pass, and changing the heuristic, hash, or PRNG makes a named test fail
  3. `LocalBackend` tests pass for pairing, round-robin turn order, line validation/rejection, idempotent resubmit, and teardown, each mirroring a named server rule
  4. `AppModel` tests drive the full arc (threshold, waiting, compose, reveal, dissolve, dissolved) plus submit errors, partner-gone, begin-again, and leaving mid-poll, where a poll response that lands after leaving does not bring the session back
  5. The whole iOS suite finishes in seconds with no real-time sleeps, and no test leaves a token behind in the app's shared `UserDefaults` container

**Notes**: Expected finding: the late-poll race (poll loops call `apply()` after an `await` without checking `Task.isCancelled`). Expose it with a gated fake and fix it here under fix-as-we-go. Use `@Suite(.serialized)` for suites that share state.
**Plans**: 4/4 plans executed

Plans are chained one per wave. Each plan proves itself through `scripts/test-ios.sh`, which boots and shuts down the single pinned "iPhone 16" simulator, and the harness has no concurrent-run lock.

Plans:
**Wave 1**
- [x] 02-01-PLAN.md — Tracer: an injectable TokenStore, AppModel `tokenStore:`/`pollInterval:` seams with task handles, and a gated FakeBackend. Covers the full AppModel arc and error paths, the APIClient `base:`/`session:` seam (ephemeral default kept), defaults-preservation tests, and the `UserDefaults.standard` guard (IOST-04, IOST-05)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 02-02-PLAN.md — The late-poll race, red then green: stale poll writes after `leave()` and stale action writes (submit, enter, begin-again, resume), fixed with `Task.isCancelled` plus an epoch checked in `apply()` (IOST-04, D-08/D-09/D-10)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 02-03-PLAN.md — LocalBackend: zero-able delay seams with unchanged defaults; a `sessions.CleanLine` port, red-first; round-robin, pacing, turn violations and resubmit pinned against named Go tests; minimal teardown (IOST-03, IOST-05)

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 02-04-PLAN.md — PoemNaming goldens captured on the simulator, plus the hash/PRNG mutation checks; the Syllables table with known misses pinned; 5/7/5 targets via `SessionView.currentTarget`; a heuristic mutation check (IOST-01, IOST-02)

### Phase 3: Server End-to-End & Wire Contract

**Goal**: An unattended run proves that the real server takes two strangers from match to dissolution and leaves nothing behind, and that the iOS models decode what the server actually sends
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: E2E-01, E2E-02, CONT-01
**Success Criteria** (what must be TRUE):
  1. The robot poet exits non-zero when its session fails and prints a machine-readable result line
  2. One command runs the real server on an ephemeral port against in-process miniredis, drives a scripted client and the robot poet through match, turns, completion, and dissolution, and exits pass/fail within a deadline, with no human, no simulator, and no shared Redis touched
  3. After dissolution, the run asserts that the session is gone (410) for both tokens, that zero `sw:*` keys remain (including the matched waiter's wait record), and that the dissolved metric went up
  4. Wire-format JSON fixtures captured from the Go server (enter matched/waiting, waiting, active and complete session, and 409/410/422 error bodies) are committed, Swift tests decode every one into the iOS models, and renaming a field on either side fails a test without a running server

**Notes**: Independent of Phase 2 (needs only the Phase 1 test target), so it can run in parallel. Expected finding: the `WaitEntry` leak in `Store.DeleteSession` will fail the zero-keys assertion. Triage it as a real anonymity bug, not an assertion to weaken. Research flags: miniredis fidelity vs real Redis, and the design of the bot's `-json` result contract. The existing `live_test.sh` scripts can't be reused (they kill port-holders, `FLUSHALL` shared Redis, and never exit).
**Plans**: TBD

### Phase 4: One-Command Verify & Baseline

**Goal**: One command answers "is the core experience still working?", and its blessed answer is committed as the GSD baseline that future milestones verify against
**Mode:** mvp
**Depends on**: Phase 2, Phase 3
**Requirements**: HARN-04, HARN-05, FIX-01
**Success Criteria** (what must be TRUE):
  1. A single command runs Go checks, iOS tests, and e2e, exits non-zero if any stage fails, and lets the developer skip any stage with a flag
  2. Every failure found during the milestone is either fixed with a regression test or listed as an expected failure with a documented reason, and no assertion was weakened, skipped, or commented out without a cited reason
  3. A dated baseline record committed under `.planning/` lists the commit hash, tool versions (Xcode, Swift, XcodeGen, Go, simulator runtime), per-suite pass counts, and an explicit not-verified list
  4. A fresh full verify run on the baseline commit is green, and its per-suite counts match the baseline record

**Notes**: Run artifacts go under a gitignored `build/verify/<timestamp>/`. Only the blessed summary is committed. The not-verified list should name at least: production/Fly.io, push, manual feel / Dynamic Type, and iOS 17.x runtime (only the 18.6 simulator is installed).
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4. Phases 2 and 3 depend only on Phase 1 and can run in parallel.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Clean Tree & Trustworthy iOS Harness | 2/2 | Complete    | 2026-10-14 |
| 2. iOS Client Logic Suites | 4/4 | In Progress | - |
| 3. Server End-to-End & Wire Contract | 0/TBD | Not started | - |
| 4. One-Command Verify & Baseline | 0/TBD | Not started | - |
