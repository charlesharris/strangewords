# Project Research Summary

**Project:** Stranger Words — verification-baseline milestone
**Domain:** Automated test/verification infrastructure for a SwiftUI (iOS 17+) client + Go/Redis backend
**Researched:** 2026-10-08
**Confidence:** HIGH (iOS recipe and phase structure), MEDIUM (Go e2e until built)

## Executive Summary

This is a verification-baseline milestone for an existing, working app — no features ship. The goal is one unattended command that proves the iOS client logic, the server lifecycle, and the client-server wire contract, and records the result as a trusted baseline. It adds no dependencies:

- **iOS:** Swift Testing in one hosted `bundle.unit-test` target declared in `ios/project.yml`, run with `xcodebuild test`. Judge the verdict from `xcresulttool` + `jq`, not from exit codes alone (a typo in `-only-testing` produces `** TEST SUCCEEDED **` with zero tests run).
- **Server e2e:** a Go package behind `//go:build e2e`. It runs the real server against in-process miniredis over TCP, plays the robot poet against a scripted human client, and asserts the full arc and zero keys after dissolution.
- **Seams:** a few defaulted init parameters in the app (poll interval, think time, API base, injectable `UserDefaults`) so tests don't sleep.

**Main risks:** false greens (zero-test runs pass; the bot exits 0 on failure), hosted tests reaching production through a leftover token in the shared `UserDefaults.standard` container, and simulator cold-boot flake. The e2e will likely fail on the known `WaitEntry` leak in `DeleteSession` — that is a real bug to triage, not a check to weaken.

## Key Findings

### Recommended Stack

The iOS recipe was prototyped during research (copied `ios/` to a scratchpad, added the target, ran it): Swift Testing on Xcode 16.4, hosted test target, headless run ~13s cold. Full detail in `STACK.md`.

**Core technologies:**
- Swift Testing (ships with Xcode): iOS unit suites — no third-party dependency, parameterized/async/`@MainActor` tests all verified working
- `xcodebuild test -resultBundlePath` + `xcresulttool get test-results summary` + `jq`: headless verdict — wrapper must require `totalTestCount > 0` and `result == "Passed"`
- XcodeGen `bundle.unit-test` target in `project.yml` with a `test:` block on the explicit scheme and `GENERATE_INFOPLIST_FILE: YES`
- Go e2e behind `-tags e2e` + miniredis (already used by gateway tests): no Docker, no local redis-server needed
- Avoid: Quick/Nimble, ViewInspector, SnapshotTesting, xcpretty/xcbeautify, testify — none needed

### Expected Features

**Must have (table stakes):**
- Clean reconciled tree with existing checks green (gates everything)
- iOS test target wired in `project.yml`, runnable headlessly
- Unit suites: `Syllables`, `PoemNaming` (golden outputs), `Models` decoding, `LocalBackend`, `AppModel`
- Scripted e2e with pass/fail exit codes proving match → turns → completion → dissolution → zero keys
- One `verify` entry point and a recorded evidence file

**Should have (competitive):**
- Wire-contract JSON fixtures generated from the Go side, decoded in Swift tests (guards iOS/Go model drift)
- Lightweight mock-vs-real parity check for `LocalBackend` (covering only shared behavior; differences go on a drift list)
- One `go test -race` run; non-gating coverage report

**Defer (v2+):**
- XCUITest / snapshot tests, CI pipeline, device farms, coverage thresholds, production/load testing

### Architecture Approach

Four-ring structure under one headless runner (`scripts/verify/verify.sh`): Go checks (vet/build/`go test -race`), iOS (`xcodegen generate` → `xcodebuild test` → `.xcresult` summary), e2e (real server + scripted clients), evidence collation into `build/verify/<ts>/` with a blessed run summarized into a committed baseline record. The existing `live_test.sh` scripts cannot be reused — they kill port-holders, `FLUSHALL` shared Redis, require a human at a simulator, and never exit.

**Major components:**
1. `StrangewordsTests` hosted unit-test target — `@testable import`, Backend protocol is the only abstraction needed
2. Testability seams — defaulted init params for `AppModel.pollInterval`, `LocalBackend` delays (600ms/1.6s), `APIClient.base`, injectable `UserDefaults` for `TokenStore`
3. Hardened robot poet — non-zero exit on failure, machine-readable `-json` result line, `-fast` flag
4. Go e2e harness — in-process miniredis, ephemeral port, deadline on every wait, dissolution asserted three ways (410 on session, zero `sw:*` keys, dissolved metric)
5. `verify.sh` + evidence — per-stage skips, gitignored run artifacts, committed baseline record

### Critical Pitfalls

1. **False green** — `xcodebuild` reports success with zero tests run; the bot exits 0 even when `playOne` errors. Gate on executed-test count and fix the bot's exit contract first.
2. **Hosted tests run the real app** — `StrangewordsApp` launches during tests and shares the `com.strangerwords.us` UserDefaults container with manual runs; a leftover token can send tests at production. Set `SW_LOCAL_MOCK=1` in the scheme's test env; clear `TokenStore` per test; serialize those suites.
3. **Slow/flaky `AppModel` tests as written** — unstructured `Task {}`, private 3s poll, real-time mock delays make a full arc 5–8s. Add the seams before writing the suites.
4. **Known `WaitEntry` leak** — the zero-keys-after-dissolution assertion will likely fail today (CONCERNS.md). Triage as a real bug; record design-level gaps as expected failures rather than weakening assertions.
5. **Late-poll race** — poll loops `apply()` after an `await` without checking `Task.isCancelled`; a late response can resurrect state after dissolution. Expose with a gated fake, fix with a cancellation guard.
6. **Simulator cold-boot flake** — first run on a shut-down simulator can die with "Early unexpected exit"; `simctl bootstatus` first, retry only that signature, `simctl shutdown all` after.

## Implications for Roadmap

### Phase 1: Reconcile and gate
**Rationale:** The dirty tree (6 modified/untracked files incl. `project.yml`, entitlements) would make any first failure ambiguous; the scheme lacks a test action entirely.
**Delivers:** Committed/reverted tree, existing Go checks green, test target + scheme `test:` block in `project.yml`, one trivial headless iOS test proving the harness, `SW_LOCAL_MOCK=1` test env confirmed.
**Avoids:** Missing test action, signing/Info.plist failures, host-app production reach.

### Phase 2: Testability seams
**Rationale:** Suites are slow/flaky without them; changes are small defaulted parameters with behavior unchanged.
**Delivers:** Injectable poll interval, mock timings, API base, `UserDefaults`.

### Phase 3: iOS suites + server e2e (parallel tracks)
**Rationale:** Independent tracks after the seams; easiest-first ordering proves the harness incrementally.
**Delivers:** iOS — `Syllables`, `PoemNaming`, `Models` decoding (+ wire fixtures), `LocalBackend`, `AppModel` against a scripted actor fake. Server — bot hardening (exit codes, `-json`), Go e2e over miniredis with the three-way dissolution assertion.

### Phase 4: Verify entry point + fix-as-we-go
**Rationale:** Single command makes verification repeatable; fixes land with regression tests as found throughout.
**Delivers:** `verify.sh` with per-stage skips, evidence under gitignored `build/verify/`, triage rule (fix cheap bugs; record design gaps as expected failures).

### Phase 5: Baseline record
**Rationale:** The milestone's point — capture the blessed run as the GSD baseline.
**Delivers:** Committed baseline record: commit hash, tool versions (Xcode 16.4, Swift 6.1.2, XcodeGen 2.45.4, Go 1.26.0, iOS 18.6 sim), pass counts, explicit not-verified list.

### Phase Ordering Rationale

- Tree reconciliation and harness proof gate everything (first failure must be unambiguous).
- Seams before suites (otherwise suites are written against sleeps and get rewritten).
- iOS and server tracks parallelize after the seams; evidence/baseline must come last.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** confirm `TEST_RUNNER_` env forwarding and scheme test env actually isolate the host app (MEDIUM confidence, one-line probe settles it)
- **Phase 3 (server track):** miniredis fidelity vs real Redis; the bot `-json` contract design

Phases with standard patterns (skip research-phase):
- **Phase 2 and Phase 3 (iOS track):** standard, prototyped during this research

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | iOS recipe prototyped locally (pass, fail, and zero-test cases observed); Go e2e MEDIUM-HIGH, not yet run |
| Features | HIGH | Scope driven by PROJECT.md, TESTING.md, and direct inspection |
| Architecture | HIGH | Shape and seams read from source; MEDIUM on some Xcode mechanics |
| Pitfalls | HIGH | Several reproduced live on Xcode 16.4 / iOS 18.6 sim; MEDIUM for general XCTest behavior from training knowledge |

**Overall confidence:** HIGH (iOS recipe, phase structure), MEDIUM (Go e2e until built)

### Gaps to Address

- **Framework split:** STACK says Swift Testing; PITFALLS/ARCHITECTURE lean XCTest over parallel-execution risk → resolve as Swift Testing with `@Suite(.serialized)` on shared-state suites.
- **E2E driver split:** ARCHITECTURE proposed bash + Docker Redis; the other files prefer in-process Go over miniredis → use the Go/miniredis path (cost: weaker real-Redis proof; optional one binary smoke test).
- **Bundle ID:** working tree changes it; test target planned as `com.strangerwords.us.tests` — confirm in Phase 1.
- **No iOS 17 runtime installed:** 17.0 deployment target is tested only on the 18.6 simulator — accept or install a 17.x runtime.
- **Xcode 26.x unverified:** pin the `jq` fields on `xcresulttool` output; re-check on upgrade.

## Sources

### Primary (HIGH confidence)
- Local prototyping on this machine: Xcode 16.4, iOS 18.6 simulator runtime, XcodeGen 2.45.4, Docker 29, Go 1.26 — test target added to a scratchpad copy of `ios/` and run headlessly
- Direct source reading: `ios/Strangewords/**` (AppModel, LocalBackend, TokenStore, Models), `server/cmd/bot/main.go`, `live_test.sh`, `run_test_server_and_robot_poet_friend.sh`, `ios/project.yml`
- `.planning/codebase/` map (ARCHITECTURE, TESTING, CONCERNS, STACK)

### Secondary (MEDIUM confidence)
- Established XcodeGen/`TEST_RUNNER_` env-forwarding practice — not re-fetched; one-line probe recommended
- General XCTest/Swift Testing behavior from training knowledge — not re-checked against current Apple docs

---
*Research completed: 2026-10-08*
*Ready for roadmap: yes*
