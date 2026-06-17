#!/usr/bin/env bash
#
# run.sh — build the iOS app with Xcode's toolchain and launch it on
# simulator(s).
#
#   ./run.sh                ONE simulator, mock mode — the everyday dev loop:
#                           an on-device stranger auto-replies (no backend) and
#                           the dev time-of-day toggle is on.
#   ./run.sh --solo         one simulator against a REAL backend (pair with the
#                           robot poet — used by live_test.sh).
#   ./run.sh --two          two simulators, be both strangers yourself (backend).
#   ./run.sh --night        force a theme: --morning | --afternoon | --night
#
# Dev controls (the time-of-day toggle) are enabled in every run.sh launch.
# A backend is needed only for --solo / --two; start it in another terminal:
#   ./run_test_server_and_robot_poet_friend.sh        (backend + robot)
#   …or  (cd server && make run)                      (backend only)
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IOS="$ROOT/ios"
PROJ="$IOS/Strangewords.xcodeproj"
APP="$IOS/build/Build/Products/Debug-iphonesimulator/Strangewords.app"
BUNDLE="com.strangewords.app"
BASE="http://127.0.0.1:8080"

# Default: a single simulator in mock mode — an on-device stranger auto-replies
# (no backend needed). Dev controls (the time-of-day toggle) are on for every
# run.sh launch, regardless of mode.
DEVICES=("iPhone 16")
MOCK=1
export SIMCTL_CHILD_SW_DEV=1
for a in "$@"; do
  case "$a" in
    --solo|--one)  DEVICES=("iPhone 16"); MOCK=0 ;;                  # one sim, real backend (live_test.sh + robot poet)
    --two|--pair)  DEVICES=("iPhone 16" "iPhone 16 Pro"); MOCK=0 ;;  # two sims, be both strangers (real backend)
    --mock)        DEVICES=("iPhone 16"); MOCK=1 ;;                  # explicit; same as the default
    --morning|--afternoon|--night) export SIMCTL_CHILD_SW_FORCE_TOD="${a#--}" ;;
    *) echo "unknown flag: $a"; exit 2 ;;
  esac
done
[[ "$MOCK" == "1" ]] && export SIMCTL_CHILD_SW_LOCAL_MOCK=1
[[ -n "${SIMCTL_CHILD_SW_FORCE_TOD:-}" ]] && echo "▸ Forcing theme: $SIMCTL_CHILD_SW_FORCE_TOD"
[[ "$MOCK" == "1" ]] && echo "▸ Mock mode: on-device stranger, no backend needed (dev toggle on)."

command -v xcodegen >/dev/null || { echo "xcodegen not found — brew install xcodegen"; exit 1; }
command -v xcodebuild >/dev/null || { echo "xcodebuild not found — install Xcode"; exit 1; }

echo "▸ Generating Xcode project…"
( cd "$IOS" && xcodegen generate >/dev/null )

echo "▸ Building (this can take a bit the first time)…"
if ! xcodebuild -project "$PROJ" -scheme Strangewords \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$IOS/build" \
      CODE_SIGNING_ALLOWED=NO -quiet build; then
  echo "Build failed."; exit 1
fi
[[ -d "$APP" ]] || { echo "Built app not found at $APP"; exit 1; }

if [[ "$MOCK" != "1" ]] && ! curl -sf "$BASE/healthz" >/dev/null 2>&1; then
  echo
  echo "⚠  Backend isn't running on $BASE — the app will show 'couldn't reach"
  echo "   the quiet room' when you tap begin. Start it in another terminal:"
  echo "     ./run_test_server_and_robot_poet_friend.sh"
  echo "   (or run ./run.sh --mock to use the on-device stranger instead)"
  echo
fi

resolve_udid() {
  xcrun simctl list devices available \
    | grep -E "^[[:space:]]*$1 \(" | head -1 \
    | grep -oiE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"
}

# Shut down any of *our* known simulators that aren't part of this run, so a
# leftover (e.g. the second sim from a prior two-up run) doesn't linger as a
# confusing idle window. Only touches devices this script family uses.
ALL_DEVICES=("iPhone 16" "iPhone 16 Pro")
is_target() { for d in "${DEVICES[@]}"; do [[ "$d" == "$1" ]] && return 0; done; return 1; }
booted="$(xcrun simctl list devices booted)"
for name in "${ALL_DEVICES[@]}"; do
  is_target "$name" && continue
  udid="$(resolve_udid "$name")"
  if [[ -n "$udid" ]] && grep -q "$udid" <<<"$booted"; then
    echo "▸ Shutting down stray simulator not in this run: $name"
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  fi
done

open -a Simulator

for name in "${DEVICES[@]}"; do
  udid="$(resolve_udid "$name")"
  if [[ -z "$udid" ]]; then
    echo "⚠  No available simulator named '$name' — skipping."
    continue
  fi
  echo "▸ $name ($udid): boot · install · launch"
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP"
  xcrun simctl launch "$udid" "$BUNDLE" >/dev/null
done

echo
echo "════════════════════════════════════════════════════════════════"
if [[ "$MOCK" == "1" ]]; then
  echo "  One simulator is up in mock mode. Tap \"begin\" — an on-device"
  echo "  stranger will match you and write its lines. No backend needed."
  echo "  The chip in the top-right cycles the time-of-day backdrop."
elif [[ "${#DEVICES[@]}" -ge 2 ]]; then
  echo "  Two simulators are up. Tap \"begin\" on BOTH to match them"
  echo "  together and write a poem across the two windows."
else
  echo "  One simulator is up. Make sure the robot poet is running"
  echo "  (./run_test_server_and_robot_poet_friend.sh), then tap \"begin\"."
fi
echo "  Re-run ./run.sh anytime to rebuild and relaunch with your changes."
echo "════════════════════════════════════════════════════════════════"
