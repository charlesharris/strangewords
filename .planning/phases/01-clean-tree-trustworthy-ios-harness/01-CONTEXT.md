# Phase 1: Clean Tree & Trustworthy iOS Harness - Context

**Gathered:** 2026-10-08
**Status:** Ready for planning

<domain>
## Phase Boundary

The developer starts from a deliberate, reconciled tree where every existing check passes, and can run an iOS test suite headlessly with a pass/fail verdict that cannot report a false green. Delivers: reconciled working tree (HARN-01), iOS unit-test target in `ios/project.yml` (HARN-02), and a trustworthy headless CLI test run (HARN-03). Test suites beyond a seed, the e2e harness, and the one-command verify entry point belong to later phases.

</domain>

<decisions>
## Implementation Decisions

### Dirty-tree reconciliation
- **D-01:** Keep ALL six dirty/untracked files — they are one coherent chunk of deliberate App Attest / device-signing prep: `ios/project.yml` (bundle ID → `com.strangerwords.us`, `DEVELOPMENT_TEAM: 2M6QRD8T3A`, `CODE_SIGN_ENTITLEMENTS`, per-config `APP_ATTEST_ENVIRONMENT`, Xcode Run scheme with `SW_LOCAL_MOCK=1`/`SW_DEV=1`), `ios/Strangewords/Strangewords.entitlements` (untracked, App Attest environment), `run.sh` (bundle ID), `server/internal/config/config.go` (`AppAttestAppID` scaffold, env `SW_APP_ATTEST_APPID`, empty disables), `docs/STATUS.md` and `server/DEPLOY.md` (doc updates describing the above). Nothing is reverted. — **Reversibility:** costly — the bundle ID must match the registered App ID (`2M6QRD8T3A.com.strangerwords.us`); reverting it breaks App Attest binding and contradicts the docs that already describe it.
- **D-02:** Commit split by concern, not one lump: (a) iOS signing/scheme changes + the doc updates that describe them, (b) server `AppAttestAppID` config scaffold. Keeps history legible and per-concern revertable.

### Harness entry point
- **D-03:** Headless runner lives in a NEW top-level `scripts/` directory: `scripts/test-ios.sh`. `run.sh` stays untouched (it is the feel loop, not the test loop). Phase 4's `verify.sh` will live beside it and compose it.
- **D-04:** Phase 1 scripts the iOS runner ONLY. HARN-01's Go checks (`go test ./...`, `go vet ./...`, `go build ./...`) run as bare commands this phase; aggregation into one command is Phase 4's job (HARN-04).
- **D-05:** Test evidence (`.xcresult` bundle + parsed summary) lands in gitignored top-level `build/verify/<timestamp>/` — the same location Phase 4's verify.sh will collate all stage evidence into. Add the gitignore entry if missing.

### Simulator policy
- **D-06:** Pin the simulator by NAME only: `iPhone 16` (OS version unpinned — uses the installed runtime, currently iOS 18.6). Rationale: pinning OS breaks on every Xcode runtime update.
- **D-07:** The runner manages the simulator lifecycle: `simctl bootstatus` (boot if needed) before testing, `simctl shutdown` after. Guards the cold-boot "Early unexpected exit" flake; retry only that failure signature once.

### Signing for test runs
- **D-08:** Force `CODE_SIGNING_ALLOWED=NO` on `xcodebuild test` invocations. Simulator tests need no signing; runs stay machine-independent (no team membership required) and avoid the silent-keychain-failure bug class. The now-set `DEVELOPMENT_TEAM` stays in `project.yml` for device builds — it just must not be a prerequisite for the test harness.

### Proof test
- **D-09:** The trivial test that proves the harness is a REAL seed: 2–3 genuine `Syllables` characterization cases. It is kept and grows into Phase 2's suite — nothing thrown away.

### Locked by roadmap/research (carried forward, not re-asked)
- **D-10:** Swift Testing (not XCTest); `@Suite(.serialized)` for suites touching shared state (e.g. `UserDefaults`).
- **D-11:** Verdict comes from the result bundle via `xcresulttool` (+ `jq`), never from xcodebuild's banner or exit code alone: non-zero exit on test failure AND on zero-tests-executed (`totalTestCount > 0` and `result == "Passed"` required).
- **D-12:** The test host app must run isolated: scheme test action sets `SW_LOCAL_MOCK=1` so no test can reach production through a leftover token. Probe `TEST_RUNNER_` env forwarding / scheme test-env mechanics with a one-line check before relying on them (roadmap research flag).

### Claude's Discretion
- Test target naming and its bundle ID (expected `com.strangerwords.*` per the new `bundleIdPrefix`; confirm what XcodeGen generates, roadmap mentions `com.strangerwords.us.tests`).
- Exact `scripts/test-ios.sh` flag surface (e.g. `-only-testing` passthrough), retry mechanics, and summary format.
- Whether `GENERATE_INFOPLIST_FILE: YES` or an explicit plist is used for the test target (PITFALLS notes it's needed when signing is allowed).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone research (prototyped recipes — the planner should lift these, not re-derive)
- `.planning/research/STACK.md` — verified XcodeGen test-target YAML, `xcodebuild test` + `xcresulttool` wrapper recipe, false-green guard details
- `.planning/research/PITFALLS.md` — 18 pitfalls incl. scheme missing `test:` action, Info.plist/signing traps, shared UserDefaults container, cold-boot flake signatures
- `.planning/research/ARCHITECTURE.md` — verification-layer component boundaries, seams list, why existing scripts can't be reused
- `.planning/research/SUMMARY.md` — phase-relevant synthesis and resolved conflicts (Swift Testing vs XCTest; e2e driver choice)

### Codebase ground truth
- `ios/project.yml` — source of truth for the Xcode project (`.xcodeproj` is gitignored; regenerate with `xcodegen generate`); carries the uncommitted App Attest/signing changes described in D-01
- `.planning/codebase/TESTING.md` — existing test inventory and conventions
- `.planning/codebase/CONCERNS.md` — known issues (relevant later phases reference it; Phase 1 only needs awareness)
- `docs/STATUS.md` — human-written project state; its claims are what this milestone verifies

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ios/Syllables/Syllables.swift` (`ios/Strangewords/Syllables/`): pure vowel-cluster heuristic — ideal seed-test target (D-09), no dependencies
- `server/Makefile`, `server/docker-compose.yml`: existing Go-side run conventions; Go checks already pass with no services (miniredis in tests)
- `run.sh`: existing simulator selection/shutdown logic worth reading for conventions — but NOT extended (D-03) and its shutdown-everything behavior is not automatically copied

### Established Patterns
- XcodeGen owns the project: any target/scheme change goes in `ios/project.yml`, then `xcodegen generate`
- No third-party iOS dependencies — Swift Testing ships with Xcode, keeping that invariant
- Scheme Run-action env vars (`SW_LOCAL_MOCK`, `SW_DEV`) apply only to Xcode's Run action — the TEST action needs its own env block (research flag D-12)

### Integration Points
- `scripts/test-ios.sh` is the contract Phase 4's `verify.sh` composes — exit code + evidence dir are its interface
- The test target lands beside the app target in `ios/project.yml`; the scheme gains a `test:` section (currently absent — confirmed failure mode)

</code_context>

<specifics>
## Specific Ideas

- The first commit sequence IS the reconciliation: split-by-concern commits of the App Attest prep (D-02), then `git status` clean is HARN-01's observable.
- Tool versions on this machine (from research probes): Xcode 16.4, iOS 18.6 simulator runtime only (no 17.x), XcodeGen 2.45.4, Go 1.26. The 17.0 deployment target tested on 18.6 is a known, accepted gap recorded for Phase 4's not-verified list.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Known future work — actual App Attest validation server-side, CI — already lives in v2 requirements / later milestones.)

</deferred>

---

*Phase: 1-Clean Tree & Trustworthy iOS Harness*
*Context gathered: 2026-10-08*
