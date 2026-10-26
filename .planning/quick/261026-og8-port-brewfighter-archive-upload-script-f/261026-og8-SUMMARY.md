---
phase: quick-261026-og8
plan: 01
subsystem: build-tooling
tags: [testflight, xcodebuild, archive, app-store-connect, bash]
requires: []
provides:
  - scripts/archive-upload.sh
  - ios/ExportOptions.plist
affects: [release, testflight]
tech-stack:
  added: []
  patterns: [unsigned-archive-then-export-sign, runtime-teamID-injection, fresh-timestamp-build-number]
key-files:
  created:
    - scripts/archive-upload.sh
    - ios/ExportOptions.plist
  modified: []
decisions:
  - "Partial ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH set exits 2 instead of silently falling back to the Xcode account (tightens the brewfighter reference)"
  - "teamID is never committed in ExportOptions.plist; inserted into build/archive copy at run time"
  - "Archive sanity gates (privacy manifest, MinimumOSVersion 17.0, encryption flag, UIRequiresFullScreen, bundle id app.strangewords) run before export and exit 1"
  - "Known Xcode-account export flake documented only; no automatic retry"
metrics:
  duration: "~10m"
  completed: 2026-10-26
status: complete
commits: 2
plan_head_before: d1e0d60a16002b02e560c0e6b8d5bccd17fc965f
plan_head_after: 16177e0f48d8dd284034050c3de59db52610412d
actuals:
  tokens: 5000
  tasks: 2
  commits: 2
---

# Quick 261026-og8: Port TestFlight archive-and-upload script Summary

One-command, gated TestFlight upload: test gate, unsigned Release archive, bundle sanity gates, then export-sign and upload, with optional headless ASC API key auth.

## What was built

- `scripts/archive-upload.sh` (mode 100755, bash 3.2 safe). Preflight first (SW_TEAM_ID `^[A-Z0-9]{10}$`, BUILD_NUMBER 1-3 dot-separated integers, ASC all-or-none, key file exists, tools), all exit 2 before any side effect. Then `go test ./...` and `scripts/test-ios.sh` (skippable with `SKIP_TESTS=1`), `xcodegen generate`, unsigned archive into `build/archive/`, sanity gates, runtime teamID insertion into a copy of the export options, `-exportArchive` with `-allowProvisioningUpdates` and the empty-safe auth array.
- `ios/ExportOptions.plist`: five keys, no teamID. Lives outside `ios/Strangewords/` so XcodeGen never bundles it (verified: zero references in the generated pbxproj).
- Task 2 added the six sanity gates (exit 1), the known "Failed to Use Accounts" flake comment, and the unverified App Attest entitlement comment.

## Commits

- 5334bd8: feat(quick-261026-og8): add TestFlight archive-and-upload script and export options
- 16177e0: feat(quick-261026-og8): gate archive-upload on bundle sanity checks before upload

## Verification

- Both tasks' automated verify chains passed: `bash -n` under /bin/bash 3.2, static content and ordering checks (gates after archive, before teamID insertion and export), no leftover reference identifiers or absolute paths, no xtrace, no echo of ASC values.
- env -i preflight probes: bad team ID, bad build number, partial ASC set, missing key file, missing xcodegen each exit 2 with the expected message.
- Gate helper exercised against a scratch copy of the generated Info.plist: passes on a correct value, exits 1 with `<missing>` for an absent key.
- Expectations cross-checked against live Release build settings (Strangewords.app, app.strangewords, 17.0) and the generated Info.plist flags.
- `build/archive` never created; no archive or upload was run. shellcheck not installed, skipped.
- origin/main unchanged by this task (d1e0d60, already pushed by the user before execution; the plan's db4ff78 check was stale). No push or fetch performed.
- brewfighter reference files byte-identical (sha256 match). Commits touch only the two files.

## Deviations from Plan

**1. [Rule 1 - Bug] Renamed helper variable.** The first draft held the list of unset ASC variable names in a variable whose name matched the plan's negative grep for `echo ... $ASC_`. It held names only, never values; renamed to `UNSET_VARS` so the guard stays a clean invariant. Files: scripts/archive-upload.sh (before the first commit).

**2. Stale origin/main check.** Verified non-modification instead of equality to db4ff78, per the orchestrator note.

## Known Stubs

None.

## Threat Flags

None. The App Attest entitlement survival through export signing remains unverified (T-og8-06, accepted, recorded in a script comment).

## Self-Check: PASSED

- scripts/archive-upload.sh: FOUND (100755)
- ios/ExportOptions.plist: FOUND
- 5334bd8, 16177e0: FOUND in history
