---
phase: 01-clean-tree-trustworthy-ios-harness
reviewed: 2026-10-14T00:00:00Z
depth: standard
files_reviewed: 16
files_reviewed_list:
  - .gitignore
  - docs/STATUS.md
  - ios/Strangewords/Strangewords.entitlements
  - ios/StrangewordsTests/HarnessCanary.swift
  - ios/StrangewordsTests/HostIsolationTests.swift
  - ios/StrangewordsTests/SyllablesTests.swift
  - ios/project.yml
  - run.sh
  - scripts/test-ios-selfcheck.sh
  - scripts/test-ios.sh
  - server/DEPLOY.md
  - server/internal/config/config.go
  - server/internal/gateway/gateway_test.go
  - server/internal/sessions/session.go
  - server/internal/sessions/validate.go
  - server/internal/store/store.go
findings:
  critical: 0
  warning: 4
  info: 5
  total: 9
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-10-14
**Depth:** standard
**Files Reviewed:** 16
**Status:** issues_found

## Summary

The phase's core claims hold up under inspection.

- **gofmt commits are semantics-preserving.** `git diff a3ecbcd..HEAD -w` over `gateway_test.go`, `session.go`, `validate.go` and `store.go` is empty, so only whitespace changed. `gofmt -l server/` is clean, and `go build`, `go vet` and `go test ./...` pass. The `[TUNABLE]` marker and the `plan.v1.md` citations on the touched blocks are intact.
- **The verdict logic is sound.** `scripts/test-ios.sh` derives PASS only from a positive jq match on the xcresult summary. A missing or unparseable bundle falls back to `{}`, which cannot match. The existing evidence under `build/verify/` shows all six selfcheck paths behaving as claimed (canary rc=65 to exit 1, zero-tests to FAIL under the green banner, nobundle to `{}`).
- **Env isolation between Run and Test actions is correct.** The scheme's `test:` block sets its own environment, so XcodeGen emits `shouldUseLaunchSchemeArgsEnv = NO`. `HostIsolationTests` guards it.
- **The anonymity model is not violated.** The test code persists no identity or poem content. The hosted app does run `TokenStore.clear()` in the simulator container, and `test-ios.sh` documents that.
- **`SyllablesTests` expectations are correct.** I traced `fire` to 1, `""` to 0, and `"A frog jumps into the pond"` to 7.

No blockers were found. The warnings concern the harness's reliability as an evidence producer for the Phase 4 `verify.sh` consumer, plus one forward-looking fail-open config default.

## Warnings

### WR-01: Stale evidence and a stale `ios-verdict.txt` survive when `SW_VERIFY_OUT` is reused, including on exit-2 paths

**File:** `scripts/test-ios.sh:45-60, 76-79, 109, 115`
**Issue:** The header says Phase 4 `verify.sh` will set `SW_VERIFY_OUT`, so the directory may be shared or reused across runs. The script never clears prior outputs. Two consequences follow.

1. **Wrong verdict file.** The exit-2 paths (missing tool, xcodegen failure, no simulator, lines 52/55/60) exit without writing or removing `ios-verdict.txt`. A previous run's `test-ios: PASS ...` line stays in the evidence dir while the process exits 2. A consumer that reads the file instead of the exit code gets a false green.
2. **Misleading extra attempt files.** `ios-tests-2.xcresult` and `ios-summary-2.json` from an earlier retried run linger after a later single-attempt run. The selfcheck canary proof (`[ -e canary/ios-tests-2.xcresult ]`, selfcheck line 110) would then report "a real test failure was retried" falsely whenever `SW_VERIFY_OUT` is pinned and reused.

**Fix:** After `OUT` is resolved (line 49), delete the per-attempt outputs. Also write an explicit verdict line on the exit-2 paths.
```bash
rm -rf "$OUT"/ios-tests-*.xcresult "$OUT"/xcodebuild-*.log "$OUT"/ios-summary-*.json "$OUT/ios-verdict.txt"
# and on preflight failure, e.g.:
die2() { echo "test-ios: $*" >&2; echo "test-ios: ERROR $*" >"$OUT/ios-verdict.txt"; exit 2; }
```

### WR-02: A simulator boot failure is swallowed and then reported as a test FAIL (exit 1) instead of an environment error (exit 2)

**File:** `scripts/test-ios.sh:67` (contract at lines 14-18)
**Issue:** `xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true` discards the boot result. If the device cannot boot (corrupt device, CoreSimulatorService down, no disk), xcodebuild fails with no usable summary and the verdict is `FAIL` with exit 1. The header defines exit 2 as environment/preflight, and exit 1 as "a test failed, zero tests executed, or no result bundle". A broken simulator is indistinguishable from a broken test, which weakens the "trustworthy baseline" signal. The retry only covers the "Early unexpected exit" signature.

**Fix:** Treat a non-zero `bootstatus` as a preflight failure, then verify the boot.
```bash
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 \
  || { echo "test-ios: simulator $UDID failed to boot" >&2; exit 2; }
```
Do this only if `bootstatus -b` is reliably non-zero on failure for the pinned Xcode. Otherwise confirm with `simctl list devices booted` and exit 2 if the UDID is absent.

### WR-03: Simulator selection is non-deterministic across runtimes, differs from `run.sh`, and the evidence does not record what was used

**File:** `scripts/test-ios.sh:58-60`, `run.sh:74-78`
**Issue:** `[.devices[][] | select(.name==$n)][0]` takes the first "iPhone 16" in the order `simctl` emits runtimes. That order is not guaranteed, so with two iOS runtimes installed (for example 17.x and 18.x) different runs can pick different OS versions, and the baseline is not reproducible. `run.sh` uses a separate grep-based first-match with its own ordering. Neither the PASS line nor the files in the evidence dir record the UDID, the runtime, or the Xcode version. The selfcheck header itself says the xcresulttool summary schema is unpublished and must be re-proven after Xcode upgrades, yet the evidence cannot show which Xcode produced it.

**Fix:** Select deterministically by highest runtime version, and write the environment into the evidence.
```bash
UDID="$(xcrun simctl list devices available -j | jq -r --arg n "$SIM_NAME" \
  '[.devices | to_entries[] | select(.key|test("iOS")) | .key as $rt
    | .value[] | select(.name==$n) | {udid, rt:$rt}]
    | sort_by(.rt) | last | .udid // empty')"
{ xcodebuild -version; echo "udid=$UDID"; } >"$OUT/ios-env.txt"
```

### WR-04: `AppAttestAppID` is fail-open by default and is not yet read or documented for deploy

**File:** `server/internal/config/config.go:20-24, 40-43`; `server/DEPLOY.md`
**Issue:** The doc comment says empty "disables App Attest enforcement", and `env("SW_APP_ATTEST_APPID", "")` defaults to empty. Nothing in the server reads the field yet, so this is scaffolding. The contract being set is that a missing or mistyped Fly secret silently turns attestation off in production, with no log line or startup check. `DEPLOY.md` was edited for the bundle id but does not mention the new `SW_APP_ATTEST_APPID` secret, so the one place that should prompt the operator to set it does not. A later phase wiring the validator could inherit this fail-open behavior without noticing.

**Fix:** Before the validator lands, add an explicit opt-out for the dev loop, such as `SW_APP_ATTEST_DISABLE=1`. Fail startup, or at minimum log a Warn, when the App ID is empty on a non-dev deploy. Add the secret to `server/DEPLOY.md` (`fly secrets set SW_APP_ATTEST_APPID=2M6QRD8T3A.com.strangerwords.us`).

## Info

### IN-01: The selfcheck header claims it proves the verdict paths, but the retry path is never exercised

**File:** `scripts/test-ios-selfcheck.sh:9-17`; `scripts/test-ios.sh:100-103`
**Issue:** The retry branch is the only logic that can turn a first-attempt zero-test result into a PASS. It keys on the literal string `Early unexpected exit` plus `totalTestCount==0`. None of the six cases triggers it, and a log-format change in a new Xcode would silently disable the retry. The branch that can turn a bad first attempt into a green is the least proven.
**Fix:** Add a seventh case that stubs `xcodebuild` via `PATH`, or a runner hook, to emit the signature once and then pass, asserting exit 0 and that `ios-tests-2.xcresult` exists. Alternatively, note the gap in the header.

### IN-02: `hostRunsInLocalMockMode` verifies only environment variables, not the backend actually selected

**File:** `ios/StrangewordsTests/HostIsolationTests.swift:15-19`
**Issue:** The test name and doc comment say the host runs in local-mock mode, but it only asserts `SW_LOCAL_MOCK == "1"` and `SW_API_BASE`. `AppModel.api` is private, so the assertion that `AppModel.init` really chose `LocalBackend` and cleared the token is indirect. The isolation guarantee rests on `AppModel.init`'s branch order staying the same. A change that checks a different flag first would pass these tests while reaching production.
**Fix:** Expose a read-only `var backendKind` (or similar) on `AppModel` under `#if DEBUG`, or assert `TokenStore.token == nil` after constructing `AppModel()`. Rename the test to `schemeSetsMockEnv` if no stronger check is added.

### IN-03: The PASS verdict has no minimum-test floor

**File:** `scripts/test-ios.sh:107`
**Issue:** `passedTests>0` guards against zero tests but not against silent loss. Removing a test file, or a `sources:` regression in `project.yml` that drops `SyllablesTests`, still yields PASS as long as one test runs. The goal is a trustworthy baseline against future change.
**Fix:** Optionally accept `SW_MIN_TESTS` (default 4 today) and add `and .passedTests>=$min` to the jq expression. Record the floor in the PASS line.

### IN-04: `docs/STATUS.md` is partly stale and does not mention the new harness

**File:** `docs/STATUS.md:138` (and the run/test sections around lines 26 and 121)
**Issue:** Line 138 still lists "iOS device signing (`DEVELOPMENT_TEAM`)" as TODO, but `ios/project.yml` now sets `DEVELOPMENT_TEAM: "2M6QRD8T3A"`. The test sections describe only `go test ./...`, not `scripts/test-ios.sh`, the selfcheck, or the side effect that shuts down the pinned simulator.
**Fix:** Update line 138 and add a short iOS-tests paragraph pointing at `scripts/test-ios.sh`, including the "do not run concurrently with `run.sh` on one simulator" warning.

### IN-05: Pass-through args can override the runner's pinned destination or result bundle path

**File:** `scripts/test-ios.sh:80-86`
**Issue:** `"$@"` comes after `-destination`, `-resultBundlePath` and `-derivedDataPath`. A caller passing, for example, `-destination ...` or `-resultBundlePath ...` overrides them. That would make the script summarize a stale or different `$rb`, or test a simulator the `cleanup` trap does not shut down. This is an unlikely footgun.
**Fix:** Reject these flags up front in the argument loop (`case "$a" in -destination*|-resultBundlePath*|-derivedDataPath*) exit 2 ;; esac`), or document that only `-only-testing` and `-skip-testing` are supported.

---

_Reviewed: 2026-10-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
