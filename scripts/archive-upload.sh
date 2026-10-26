#!/usr/bin/env bash
#
# archive-upload.sh — test gate, archive, bundle sanity gates, then export and
# upload to App Store Connect for TestFlight. Ported from the brewfighter
# project's archive-upload script.
#
#   scripts/archive-upload.sh
#   SKIP_TESTS=1 scripts/archive-upload.sh
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=... scripts/archive-upload.sh
#
# Env vars (all optional):
#   SW_TEAM_ID     10-character Apple team ID (default 2M6QRD8T3A, which is already
#                  public as DEVELOPMENT_TEAM in ios/project.yml). Uses the SW_
#                  prefix per project convention.
#   ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH
#                  App Store Connect API key, for headless signing and upload. Set
#                  all three together to use it. Setting none uses Xcode's signed-in
#                  account. Setting only some is refused (exit 2).
#   SKIP_TESTS=1   skip the test gate (go test + scripts/test-ios.sh)
#   BUILD_NUMBER   override the timestamp build number (1-3 dot-separated integers)
#   SW_SIM_NAME    simulator name; reaches scripts/test-ios.sh through the environment
#
# Exit codes:
#   0  uploaded
#   1  an archive sanity gate failed (nothing was uploaded)
#   2  environment or preflight failure (bad env value, partial ASC set, missing
#      key file, missing tool). Refused before any test, xcodegen, archive, or write.
#   other  a failing step (go test, test-ios.sh, xcodegen, xcodebuild) exits with
#          its own status through `set -e`.
#
# Outputs: everything goes under build/archive/, which is gitignored by /build/ and
# wiped at the start of every run. It is separate from the build/verify/ and
# build/derived/ dirs that scripts/test-ios.sh uses.
#
# Re-run safety: every run gets a fresh build number, so a re-run cannot collide
# with an earlier attempt. The upload is the final step, so a failed run uploads
# nothing.
#
# Never enable xtrace here: it would echo the ASC arguments.
set -euo pipefail
cd "$(dirname "$0")/.."

# Team ID. Stricter than a length check because the value is interpolated into
#    a build setting and a plist.
SW_TEAM_ID="${SW_TEAM_ID:-2M6QRD8T3A}"
TEAM_RE='^[A-Z0-9]{10}$'
if ! [[ "$SW_TEAM_ID" =~ $TEAM_RE ]]; then
  echo "archive-upload: SW_TEAM_ID must be 10 uppercase letters or digits" >&2
  exit 2
fi

# Build number. Each run gets a fresh, strictly increasing build number (UTC
#    timestamp, never committed), so a re-run after a failed or interrupted upload
#    cannot collide with an earlier attempt (App Store Connect rejects a repeated
#    build number). Override with BUILD_NUMBER=<n> if needed.
#    manageAppVersionAndBuildNumber stays on in ios/ExportOptions.plist as a backstop.
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
BUILD_RE='^[0-9]+(\.[0-9]+){0,2}$'
if ! [[ "$BUILD_NUMBER" =~ $BUILD_RE ]]; then
  echo "archive-upload: BUILD_NUMBER must be 1-3 dot-separated integers" >&2
  exit 2
fi
echo "archive-upload: build number $BUILD_NUMBER" >&2

# Auth. All three ASC variables select API key auth; none selects the Xcode
#    account. A partial set is refused rather than silently falling back, which
#    would hide a misconfigured headless run. Only variable names are ever printed.
AUTH_ARGS=()
ASC_SET=0
UNSET_VARS=""
if [ -n "${ASC_KEY_ID:-}" ]; then ASC_SET=$((ASC_SET + 1)); else UNSET_VARS="$UNSET_VARS ASC_KEY_ID"; fi
if [ -n "${ASC_ISSUER_ID:-}" ]; then ASC_SET=$((ASC_SET + 1)); else UNSET_VARS="$UNSET_VARS ASC_ISSUER_ID"; fi
if [ -n "${ASC_KEY_PATH:-}" ]; then ASC_SET=$((ASC_SET + 1)); else UNSET_VARS="$UNSET_VARS ASC_KEY_PATH"; fi
if [ "$ASC_SET" -eq 3 ]; then
  if [ ! -f "$ASC_KEY_PATH" ]; then
    echo "archive-upload: ASC_KEY_PATH does not point to a file" >&2
    exit 2
  fi
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "archive-upload: using App Store Connect API key authentication" >&2
elif [ "$ASC_SET" -eq 0 ]; then
  echo "archive-upload: using Xcode's signed-in account for signing and upload" >&2
else
  echo "archive-upload: ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH must be set together; missing:$UNSET_VARS" >&2
  exit 2
fi

# Tools.
for t in xcodegen xcodebuild plutil; do
  command -v "$t" >/dev/null || { echo "archive-upload: missing tool: $t" >&2; exit 2; }
done
if [ "${SKIP_TESTS:-0}" != "1" ]; then
  command -v go >/dev/null || { echo "archive-upload: missing tool: go" >&2; exit 2; }
fi

# Test gate. set -e aborts the run on any failure.
if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "archive-upload: test gate (backend: go test)" >&2
  (cd server && go test ./...)
  echo "archive-upload: test gate (iOS: scripts/test-ios.sh)" >&2
  scripts/test-ios.sh
else
  echo "archive-upload: SKIP_TESTS=1, skipping the test gate" >&2
fi

# Regenerate the Xcode project (ios/project.yml is the source of truth).
(cd ios && xcodegen generate)

# Output dir. A literal, never derived from env.
OUT=build/archive
rm -rf "$OUT"
mkdir -p "$OUT"
ARCHIVE="$OUT/Strangewords.xcarchive"
EXPORT="$OUT/export"

# The archive is deliberately unsigned (CODE_SIGNING_ALLOWED=NO). A signed
#    Release archive makes Xcode look for an iOS App Development profile, which
#    fails on a team with no registered devices. The -exportArchive step below signs
#    with the cloud-managed distribution certificate and profile (signingStyle
#    automatic), which needs no registered device.
#    Entitlements: the archived binary carries no code signature, so no entitlements
#    are attached until the export step signs it. It has not been verified that the
#    export step carries the App Attest environment entitlement
#    (ios/Strangewords/Strangewords.entitlements) into the uploaded build. No App
#    Attest client exists yet, so nothing depends on it today. Check the processed
#    build's entitlements before shipping one.
xcodebuild archive \
  -project ios/Strangewords.xcodeproj \
  -scheme Strangewords \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$SW_TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO

APP="$ARCHIVE/Products/Applications/Strangewords.app"

# Archive sanity gates: refuse to export or upload a bundle that App Store
# validation would reject. Expected values come from ios/project.yml.
# Reads one Info.plist key (or the sentinel <missing>) and exits 1 on a mismatch.
check_plist() {
  local key="$1" want="$2" got
  got=$(plutil -extract "$key" raw "$APP/Info.plist" 2>/dev/null) || got="<missing>"
  if [ "$got" != "$want" ]; then
    echo "archive-upload: archived $key is $got, expected $want" >&2
    exit 1
  fi
}

if [ ! -d "$APP" ]; then
  echo "archive-upload: archived app not found at $APP" >&2
  exit 1
fi
# Required-reason API manifest that App Store Connect checks (quick task 261026-no9).
if [ ! -f "$APP/PrivacyInfo.xcprivacy" ]; then
  echo "archive-upload: archived app is missing PrivacyInfo.xcprivacy" >&2
  exit 1
fi
# Matches deploymentTarget in ios/project.yml.
check_plist MinimumOSVersion 17.0
# Export-compliance flag (quick task 261026-no9).
check_plist ITSAppUsesNonExemptEncryption false
# App Store validation rejected the upload as an invalid bundle without this on
# 2026-10-26: a portrait-only, iPad-capable app must opt out of multitasking.
check_plist UIRequiresFullScreen true
# PRODUCT_BUNDLE_IDENTIFIER in ios/project.yml.
check_plist CFBundleIdentifier app.strangewords
echo "archive-upload: archive sanity gates passed" >&2

# Runtime export options: the committed plist has no teamID, so a run can never
#     silently export under a stale team. plutil -insert fails if the key exists.
cp ios/ExportOptions.plist "$OUT/ExportOptions.plist"
plutil -insert teamID -string "$SW_TEAM_ID" "$OUT/ExportOptions.plist"

# Export (signs) and upload.
# Known flake: with Xcode-account auth, -exportArchive can transiently fail with
# "Failed to Use Accounts" and a missing Xcode-Username, caused by a
# DVTDeveloperAccountManager keychain read. Re-running the script usually succeeds,
# and a re-run gets a fresh build number. The App Store Connect API key path
# (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH) avoids the problem entirely.
# There is deliberately no automatic retry: a blind retry would also mask a real
# sign-in or keychain failure.
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates \
  ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"}

# With manageAppVersionAndBuildNumber, App Store Connect may assign a different
#     build number; this line prints the archived one.
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw "$APP/Info.plist")
echo "archive-upload: uploaded $VERSION ($BUILD)"
