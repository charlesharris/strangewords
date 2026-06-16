#!/usr/bin/env bash
#
# run.sh — build the iOS app with Xcode's toolchain and launch it on
# simulator(s) so you can run both sides of the test.
#
#   ./run.sh           two simulators (be both strangers yourself)
#   ./run.sh --solo    one simulator   (pair with the robot poet instead)
#
# The backend must be running. Start it in another terminal with:
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

DEVICES=("iPhone 16" "iPhone 16 Pro")
for a in "$@"; do
  case "$a" in
    --solo|--one) DEVICES=("iPhone 16") ;;
    *) echo "unknown flag: $a"; exit 2 ;;
  esac
done

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

if ! curl -sf "$BASE/healthz" >/dev/null 2>&1; then
  echo
  echo "⚠  Backend isn't running on $BASE — the app will show 'couldn't reach"
  echo "   the quiet room' when you tap begin. Start it in another terminal:"
  echo "     ./run_test_server_and_robot_poet_friend.sh"
  echo
fi

resolve_udid() {
  xcrun simctl list devices available \
    | grep -E "^[[:space:]]*$1 \(" | head -1 \
    | grep -oiE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"
}

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
if [[ "${#DEVICES[@]}" -ge 2 ]]; then
  echo "  Two simulators are up. Tap \"begin\" on BOTH to match them"
  echo "  together and write a poem across the two windows."
else
  echo "  One simulator is up. Make sure the robot poet is running"
  echo "  (./run_test_server_and_robot_poet_friend.sh), then tap \"begin\"."
fi
echo "  Re-run ./run.sh anytime to rebuild and relaunch with your changes."
echo "════════════════════════════════════════════════════════════════"
