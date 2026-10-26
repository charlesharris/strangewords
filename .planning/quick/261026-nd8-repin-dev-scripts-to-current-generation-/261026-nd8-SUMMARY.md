---
phase: quick-261026-nd8
plan: 01
subsystem: dev-tooling
tags: [ios, simulator, test-harness, run-sh]
status: complete
requires: []
provides:
  - "scripts/test-ios.sh default pin iPhone 17 (iOS 27.0)"
  - "scripts/test-ios-selfcheck.sh default pin in lockstep"
  - "run.sh on iPhone 17 / iPhone 17e"
key-files:
  modified:
    - scripts/test-ios.sh
    - scripts/test-ios-selfcheck.sh
    - run.sh
decisions:
  - "Deterministic exact-name pin (iPhone 17), no dynamic newest-device selection"
commits: 2
plan_head_before: cb86399cc5536f9b8cb407e3413619650c1603d3
plan_head_after: fe34596
actuals:
  tokens: 3000
  tasks: 2
  commits: 2
---

# Quick 261026-nd8: Repin dev scripts to current-generation simulators Summary

Default simulator for the iOS test harness, its selfcheck, and `run.sh` moved from the iOS 18.6 iPhone 16 family to exact-name pins on the iOS 27.0 runtime (iPhone 17; iPhone 17e for `--two`), with the `SW_SIM_NAME` override intact.

## Commits

- e504b91: `chore(quick-261026-nd8): repin iOS test harness default simulator to iPhone 17` (scripts/test-ios.sh, scripts/test-ios-selfcheck.sh)
- fe34596: `chore(quick-261026-nd8): repin run.sh simulators to iPhone 17 and iPhone 17e` (run.sh)

## Evidence (Xcode 27.1)

| Run | Verdict | Device / OS recorded | Evidence dir |
|-----|---------|----------------------|--------------|
| Default (SW_SIM_NAME unset) | `test-ios: PASS` 67 passed, 0 failed, 1 skipped, 68 total | iPhone 17 / 27.0 | `build/verify/nd8-default` |
| Override `SW_SIM_NAME="iPhone 16 Pro"`, HostIsolationTests | `test-ios: PASS` 3/3 | iPhone 16 Pro / 18.6 | `build/verify/nd8-override` |
| Unknown name (`No Such Phone`) | `test-ios: no available simulator named 'No Such Phone'` (preflight exit 2) | n/a | n/a |
| Selfcheck, no env override | `selfcheck: PASS 6/6` | iPhone 17 | `build/verify/nd8-selfcheck` |

run.sh: no `iPhone 16` remains in any of the three scripts, `bash -n` clean on all, DEVICES sequence is as specified, "iPhone 17" and "iPhone 17e" each match exactly one available simulator, and `run.sh --bogus` exits 2 (run.sh was not launched). origin/main unchanged at db4ff78fe39ab2abc1a84e191ad6f6c0b3fa0653; only the three script files changed outside `.planning/`.

## Deviations from Plan

None - plan executed as written. One cosmetic touch: the inline comment on the `--two` line in run.sh was re-padded for column alignment as the plan specified.

Scope addition (from the plan): `scripts/test-ios-selfcheck.sh` moved in lockstep with the harness. It resolves its own UDID from its own default for the booted-before/still-booted-after proofs, while `run_case` does not forward `SW_SIM_NAME` to the runner; diverging defaults would make the pass case boot one simulator while the runner tests and shuts down another.

## Left unchanged (out of scope, for a later docs pass)

- `.planning/ROADMAP.md:63` (Phase 2 prose naming the old pin)
- `docs/STATUS.md:119` (stray-simulator example, still a valid stray)
- `ios/StrangewordsTests/PoemNamingTests.swift:7` (golden-capture provenance; the goldens still pass on Xcode 27.1 / iOS 27.0)
- the jq `[0]` / `head -1` duplicate-name pick (stays on the Phase 4 ledger)

## Notes for the orchestrator (carry into STATE.md, Phase 4 ledger)

1. Refinement: the default harness now runs on iOS 27.0. The iOS 18.6 runtime (closest installed runtime to the 17.0 deployment target) is exercised only through an explicit `SW_SIM_NAME` override, and only while Xcode keeps that runtime installed.
2. Candidate, observed but NOT fixed (harness logic out of scope): under Xcode 27.1 any failing harness run spends about 10 extra minutes because xcodebuild hits the 600 s "Failure collecting diagnostics from simulator" timeout, making the selfcheck about 14 min. A candidate remedy is xcodebuild's `-collect-test-diagnostics never` (present in Xcode 27.1 `xcodebuild -help`); it is a separate change that needs its own selfcheck re-proof.

## Known Stubs

None.

## Self-Check: PASSED

- scripts/test-ios.sh, scripts/test-ios-selfcheck.sh, run.sh: FOUND
- Commits e504b91 and fe34596: FOUND on main
