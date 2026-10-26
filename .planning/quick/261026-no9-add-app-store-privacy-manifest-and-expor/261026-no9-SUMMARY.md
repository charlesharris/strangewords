---
phase: quick-261026-no9
plan: 01
subsystem: ios-app-store-readiness
tags: [privacy-manifest, export-compliance, xcodegen, testflight]
requires: []
provides:
  - "PrivacyInfo.xcprivacy shipped at the .app bundle root"
  - "ITSAppUsesNonExemptEncryption=false in the app Info.plist"
affects: [ios/project.yml]
key-files:
  created: [ios/Strangewords/PrivacyInfo.xcprivacy]
  modified: [ios/project.yml]
decisions:
  - "UserDefaults declared with reason CA92.1 (no App Groups, no suiteName in app target)"
  - "No explicit buildPhase entry; XcodeGen files .xcprivacy under Resources automatically"
metrics:
  duration: ~10m
  completed: 2026-10-26
status: complete
commits: 2
plan_head_before: 9b9fce45f591869b6e894582797b0d27311fcdb5
plan_head_after: 9920b1b3ed0457faa285a2b91a681e07282b4468
actuals:
  tokens: 2500
  tasks: 2
  commits: 2
---

# Quick 261026-no9: App Store privacy manifest and export compliance Summary

Added a privacy manifest (no tracking, no collected data, UserDefaults CA92.1) and `ITSAppUsesNonExemptEncryption: false`, removing two App Store Connect upload blockers without behavior changes.

## Tasks

| Task | Commit | Files |
| ---- | ------ | ----- |
| 1. Privacy manifest, verified at the built bundle root | ce2f148 | ios/Strangewords/PrivacyInfo.xcprivacy, ios/project.yml (comment) |
| 2. Export-compliance flag, built Info.plist check, full iOS suite | 9920b1b | ios/project.yml |

## Verification

- Manifest lints; jq gate confirms exactly four keys and the single UserDefaults/CA92.1 entry.
- Generated pbxproj lists `PrivacyInfo.xcprivacy in Resources`; simulator build contains it byte-identical (`cmp`) at `Strangewords.app/PrivacyInfo.xcprivacy`.
- Generated and built Info.plist carry `ITSAppUsesNonExemptEncryption` as boolean false; bundle id remains `app.strangewords`.
- `scripts/test-ios.sh` (iPhone 17, iOS 27.0): Passed, 67 passed, 0 failed, 1 skipped, 68 total. Evidence: `build/verify/no9/ios-summary-1.json`.
- Required-reason invariant scan (other API families, suiteName, application-groups): clean.
- Scope guard: feat commits touch only the two declared paths; run.sh and scripts/test-ios.sh untouched. origin/main still db4ff78. Nothing pushed.

## Deviations from Plan

None - plan executed exactly as written. Notes: the nd8 task had already finished, so the suite ran on the iPhone 17 pin (counts unchanged). Commits were made on `main` as the sequential-executor instructions and plan require (no phase branch exists for quick tasks).

## Flagged for developer review

T-no9-02 (accepted per locked decision): the empty `NSPrivacyCollectedDataTypes` should be confirmed against the App Store Connect privacy label, since the server logs reported poem lines (`moderation.LogSink`) and holds lines in Redis up to 90 minutes.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: ios/Strangewords/PrivacyInfo.xcprivacy
- FOUND commits: ce2f148, 9920b1b
