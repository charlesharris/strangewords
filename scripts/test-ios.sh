#!/usr/bin/env bash
#
# test-ios.sh — run the iOS unit tests headlessly and print a verdict that
# cannot report a false green.
#
#   scripts/test-ios.sh [extra xcodebuild args]
#   scripts/test-ios.sh -only-testing:StrangewordsTests/SyllablesTests
#
# The verdict comes ONLY from the result-bundle summary (xcresulttool): result
# "Passed", failedTests 0, passedTests > 0, totalTestCount > 0. xcodebuild's own
# exit code and "** TEST SUCCEEDED **" banner never decide it: a mistyped
# -only-testing filter prints that banner with zero tests executed.
#
# Exit codes:
#   0  PASS
#   1  verdict FAIL (a test failed, zero tests executed, or no result bundle)
#   2  environment/preflight (missing tool, xcodegen failure, or no simulator
#      with the pinned name)
#
# Env overrides:
#   SW_SIM_NAME    simulator name to pin, matched exactly (default: iPhone 16)
#   SW_VERIFY_OUT  evidence directory (default: build/verify/<timestamp>;
#                  Phase 4 verify.sh sets it)
#
# Per-attempt outputs in the evidence dir (N is the attempt number):
#   ios-tests-N.xcresult   xcodebuild-N.log   ios-summary-N.json
#   ios-verdict.txt        the final verdict line
#
# Side effects:
#   - The host app runs in mock mode and clears the participant token in the
#     app.strangewords container of the test simulator.
#   - The pinned simulator is shut down when the run ends, even if it was already
#     booted before the run (D-07). That ends any run.sh session on the same
#     simulator, so do not run this at the same time as run.sh on one simulator.
#
# Re-proving that a failing test yields a failing verdict:
#   TEST_RUNNER_SW_HARNESS_CANARY_FAIL=1 scripts/test-ios.sh    # must exit 1
#   scripts/test-ios-selfcheck.sh                               # all six verdicts
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS="$ROOT/ios"
SIM_NAME="${SW_SIM_NAME:-iPhone 16}"
OUT="${SW_VERIFY_OUT:-$ROOT/build/verify/$(date +%Y%m%d-%H%M%S)}"
DERIVED="$ROOT/build/derived/ios-test"

mkdir -p "$OUT" || { echo "test-ios: cannot create evidence dir: $OUT" >&2; exit 2; }
OUT="$(cd "$OUT" && pwd)"

for t in xcodegen xcodebuild xcrun jq; do
  command -v "$t" >/dev/null || { echo "test-ios: missing tool: $t" >&2; exit 2; }
done

( cd "$IOS" && xcodegen generate >/dev/null ) || { echo "test-ios: xcodegen failed" >&2; exit 2; }

# Resolve the simulator by EXACT name (D-06); the OS version is left unpinned.
UDID="$(xcrun simctl list devices available -j \
  | jq -r --arg n "$SIM_NAME" '[.devices[][] | select(.name==$n)][0].udid // empty')"
[ -n "$UDID" ] || { echo "test-ios: no available simulator named '$SIM_NAME'" >&2; exit 2; }

# D-07: shut down the pinned simulator, and only it, when the run ends.
cleanup() { xcrun simctl shutdown "$UDID" >/dev/null 2>&1; true; }
trap cleanup EXIT

# Boots the device if needed and blocks until it is ready.
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

XC_RC=0
SUMMARY=""
LOG=""

# run_once N [xcodebuild args...]
run_once() {
  local n="$1"; shift
  local rb="$OUT/ios-tests-$n.xcresult"
  LOG="$OUT/xcodebuild-$n.log"
  SUMMARY="$OUT/ios-summary-$n.json"
  rm -rf "$rb"   # xcodebuild refuses an existing result-bundle path
  xcodebuild test \
      -project "$IOS/Strangewords.xcodeproj" -scheme Strangewords \
      -destination "id=$UDID" \
      -derivedDataPath "$DERIVED" \
      -resultBundlePath "$rb" \
      CODE_SIGNING_ALLOWED=NO \
      "$@" >"$LOG" 2>&1
  XC_RC=$?
  if [ -d "$rb" ] && xcrun xcresulttool get test-results summary --path "$rb" >"$SUMMARY" 2>/dev/null; then
    :
  else
    echo '{}' >"$SUMMARY"   # jq comparisons against {} are false, so the verdict is FAIL
  fi
}

run_once 1 "$@"

# D-07: retry once, and only for the cold-boot bootstrap-crash signature
# (zero tests executed AND "Early unexpected exit" in the log). Any other
# outcome, including a real test failure, is never retried.
if [ "$(jq -r '.totalTestCount // 0' "$SUMMARY")" = 0 ] && grep -q "Early unexpected exit" "$LOG"; then
  echo "test-ios: cold-boot bootstrap crash signature seen; retrying once" >&2
  run_once 2 "$@"
fi

# D-11: positive match on Passed with a non-empty run. Never a negative match on
# Failed, since a compile error also yields result "unknown" with 0 tests.
if jq -e '.result=="Passed" and .failedTests==0 and .passedTests>0 and .totalTestCount>0' "$SUMMARY" >/dev/null 2>&1; then
  LINE="test-ios: PASS $(jq -c '{passedTests,failedTests,skippedTests,totalTestCount}' "$SUMMARY") (xcodebuild rc=$XC_RC) evidence: $OUT"
  echo "$LINE" | tee "$OUT/ios-verdict.txt"
  exit 0
fi

LINE="test-ios: FAIL $(jq -c '{result,passedTests,failedTests,totalTestCount}' "$SUMMARY" 2>/dev/null) (xcodebuild rc=$XC_RC) evidence: $OUT"
echo "$LINE" >&2
echo "$LINE" >"$OUT/ios-verdict.txt"
exit 1
