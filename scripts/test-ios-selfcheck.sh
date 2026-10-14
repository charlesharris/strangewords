#!/usr/bin/env bash
#
# test-ios-selfcheck.sh — re-prove that scripts/test-ios.sh cannot report a
# false green. Re-run it after any Xcode upgrade: the xcresulttool summary schema
# is unpublished.
#
#   scripts/test-ios-selfcheck.sh
#
# Runs the runner once per case, sequentially (there is one simulator):
#   pass       default run exits 0 and the simulator is shut down afterwards,
#              even though it was booted before the run
#   isolation  HostIsolationTests alone exits 0
#   zero       -only-testing for a missing suite exits 1 although xcodebuild
#              prints ** TEST SUCCEEDED **; the summary shows 0 tests
#   canary     the env-gated failing test exits 1 and is not retried
#   nobundle   an invalid xcodebuild option leaves no result bundle: exit 1, {}
#   nosim      an unknown simulator name exits 2
#
# Exit codes:
#   0  every proof held
#   1  a proof failed
#   2  preflight (jq or xcrun missing, or scripts/test-ios.sh not executable)
#
# Env overrides:
#   SW_SIM_NAME    simulator name to pin (default: iPhone 16)
#   SW_VERIFY_OUT  evidence dir (default: build/verify/<timestamp>-selfcheck)
#
# Side effects: boots and shuts down the pinned simulator six times; see the
# side-effect notes in scripts/test-ios.sh.
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/scripts/test-ios.sh"
SIM_NAME="${SW_SIM_NAME:-iPhone 16}"
SELF="${SW_VERIFY_OUT:-$ROOT/build/verify/$(date +%Y%m%d-%H%M%S)-selfcheck}"

for t in jq xcrun; do
  command -v "$t" >/dev/null || { echo "selfcheck: missing tool: $t" >&2; exit 2; }
done
[ -x "$RUNNER" ] || { echo "selfcheck: $RUNNER is not executable" >&2; exit 2; }

mkdir -p "$SELF" || { echo "selfcheck: cannot create $SELF" >&2; exit 2; }
SELF="$(cd "$SELF" && pwd)"

UDID="$(xcrun simctl list devices available -j \
  | jq -r --arg n "$SIM_NAME" '[.devices[][] | select(.name==$n)][0].udid // empty')"
[ -n "$UDID" ] || { echo "selfcheck: no available simulator named '$SIM_NAME'" >&2; exit 2; }
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1; true' EXIT

is_booted() {
  xcrun simctl list devices booted -j \
    | jq -e --arg u "$UDID" '[.devices[][] | select(.udid==$u)] | length > 0' >/dev/null 2>&1
}

FAILS=0
RC=0
REASON=""

# run_case NAME [runner args...]; runs the runner with SW_VERIFY_OUT=$SELF/NAME,
# saves combined output to $SELF/NAME.out, and sets RC.
run_case() {
  local name="$1"; shift
  SW_VERIFY_OUT="$SELF/$name" "$RUNNER" "$@" >"$SELF/$name.out" 2>&1
  RC=$?
}

# report NAME: prints ok/FAIL for the case from $REASON (empty means ok).
report() {
  if [ -z "$REASON" ]; then
    echo "selfcheck: ok $1"
  else
    echo "selfcheck: FAIL $1: $REASON"
    FAILS=$((FAILS + 1))
  fi
  REASON=""
}

# 1. pass, with the simulator booted beforehand.
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
run_case pass
[ "$RC" -eq 0 ] || REASON="expected exit 0, got $RC"
if [ -z "$REASON" ] && is_booted; then REASON="simulator still booted after the run"; fi
report pass

# 2. isolation guard alone.
run_case isolation -only-testing:StrangewordsTests/HostIsolationTests
[ "$RC" -eq 0 ] || REASON="expected exit 0, got $RC"
report isolation

# 3. zero tests under xcodebuild's green banner.
run_case zero -only-testing:StrangewordsTests/DoesNotExist
if [ "$RC" -ne 1 ]; then
  REASON="expected exit 1, got $RC"
elif ! jq -e '.totalTestCount==0' "$SELF/zero/ios-summary-1.json" >/dev/null 2>&1; then
  REASON="summary totalTestCount is not 0"
elif ! grep -q '\*\* TEST SUCCEEDED \*\*' "$SELF/zero/xcodebuild-1.log"; then
  REASON="xcodebuild did not print its success banner, so the banner-override proof is vacuous"
fi
report zero

# 4. failing test via the env-gated canary; a real failure is never retried.
TEST_RUNNER_SW_HARNESS_CANARY_FAIL=1 run_case canary
if [ "$RC" -ne 1 ]; then
  REASON="expected exit 1, got $RC"
elif ! jq -e '.result=="Failed" and ([.testFailures[]?.testIdentifierString] | any(test("HarnessCanary")))' \
       "$SELF/canary/ios-summary-1.json" >/dev/null 2>&1; then
  REASON="summary lacks result Failed with a HarnessCanary failure"
elif [ -e "$SELF/canary/ios-tests-2.xcresult" ]; then
  REASON="a real test failure was retried"
fi
report canary

# 5. no result bundle at all.
run_case nobundle -thisFlagDoesNotExist
if [ "$RC" -ne 1 ]; then
  REASON="expected exit 1, got $RC"
elif [ "$(cat "$SELF/nobundle/ios-summary-1.json" 2>/dev/null)" != "{}" ]; then
  REASON="summary is not exactly {}"
fi
report nobundle

# 6. missing simulator.
SW_SIM_NAME="SW No Such Simulator" run_case nosim
if [ "$RC" -ne 2 ]; then
  REASON="expected exit 2, got $RC"
elif ! grep -q "no available simulator named" "$SELF/nosim.out"; then
  REASON="output lacks 'no available simulator named'"
fi
report nosim

# Whatever happened, the pinned simulator must not be left booted.
if is_booted; then
  echo "selfcheck: FAIL final: pinned simulator is still booted"
  FAILS=$((FAILS + 1))
fi

if [ "$FAILS" -eq 0 ]; then
  echo "selfcheck: PASS 6/6 evidence: $SELF"
  exit 0
fi
echo "selfcheck: FAIL $FAILS/6 evidence: $SELF"
exit 1
