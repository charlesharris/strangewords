---
phase: quick-261026-n2i
plan: 01
subsystem: infra
tags: [rebrand, bundle-id, fly, app-attest, docs]
status: complete
requirements: [QUICK-261026-n2i]
key-files:
  modified:
    - ios/Strangewords/Net/APIClient.swift
    - ios/StrangewordsTests/SeamDefaultsTests.swift
    - ios/project.yml
    - server/fly.toml
    - run.sh
    - server/internal/config/config.go
    - scripts/test-ios.sh
    - server/DEPLOY.md
    - docs/STATUS.md
    - .claude/CLAUDE.md
    - .planning/codebase/STACK.md
    - .planning/codebase/ARCHITECTURE.md
    - .planning/codebase/STRUCTURE.md
    - .planning/codebase/INTEGRATIONS.md
decisions:
  - "Production host is https://api.strangewords.app; Fly app is strangewords; bundle id is app.strangewords (tests: app.strangewords.tests); App Attest App ID is 2M6QRD8T3A.app.strangewords"
actuals:
  tokens: 30000
  tasks: 3
  commits: 4
plan_head_before: ef915af0a1e12ebf4f2953bf82e4ac60ba9615b1
plan_head_after: 8a951430463ee433fb1be554a5dc6a0a6ecd4abc
---

# Quick 261026-n2i: Rebrand backend host, Fly app, and bundle id Summary

Production host, Fly app name, and iOS bundle ids moved to the strangewords.app identity across code, project spec, scripts, operator docs, and agent-facing docs. All commits are local; nothing was pushed.

## Commits

| Task | Commit | Description |
| ---- | ------ | ----------- |
| 1 (red) | 4e05a38 | SeamDefaultsTests pins `https://api.strangewords.app` |
| 1 (green) | ca80a73 | APIClient default, project.yml bundle ids, fly.toml app, run.sh BUNDLE |
| 2 | bc9a9ba | config.go and test-ios.sh comments, DEPLOY.md (name note, bootstrap, cutover section), STATUS.md |
| 3 | 8a95143 | CLAUDE.md and the codebase-map sources (STACK, ARCHITECTURE, STRUCTURE, INTEGRATIONS) |

## Verification evidence

- Red (before APIClient change), SeamDefaultsTests only: `test-ios: FAIL {"result":"Failed","passedTests":6,"failedTests":1,"totalTestCount":7} (xcodebuild rc=65)`, evidence `build/verify/20261026-164549`
- Green, same filter: `test-ios: PASS {"passedTests":7,"failedTests":0,"skippedTests":0,"totalTestCount":7}`, evidence `build/verify/20261026-164641`
- Generated build settings: `PRODUCT_BUNDLE_IDENTIFIER = app.strangewords` and `app.strangewords.tests`
- Full suite on iPhone 16 Pro (iOS 18.6): `test-ios: PASS {"passedTests":67,"failedTests":0,"skippedTests":1,"totalTestCount":68}`, evidence `build/verify/20261026-164700`
- `gofmt -l server/` empty; `go test ./...` passes
- `git grep` for the old `.us` domain outside historical artifacts: 0; old name outside `.planning`, DEPLOY.md, STATUS.md: 0
- `origin/main` is still `db4ff78fe39ab2abc1a84e191ad6f6c0b3fa0653`

## Deviations from Plan

None. The plan executed as written. One fix during execution: the project.yml test-target comment wraps across lines 56-57, so the bundle id on line 57 was edited separately from the sed pass.

Note on DEPLOY.md: the cutover section states the 2026-10-26 plan-time observation that the `strangewords` app and `api.strangewords.app` DNS did not exist. Since then (per the orchestrator) the Fly app has been created, the Redis secret staged, and a cert added, but DNS is not live and nothing is deployed. The runbook steps are therefore partly done already; the section was written as planned and may deserve a refresh.

## Known Stubs

None.

## Out-of-repo follow-ups (NOT done by this plan; required before any push to `main`)

1. `fly apps create strangewords` plus Redis and secrets (app and Redis secret now reportedly staged)
2. Regenerate `FLY_API_TOKEN` for the new app and update the GitHub secret
3. Cert/DNS for `api.strangewords.app` (cert added, DNS pending)
4. Register App ID `app.strangewords` with the App Attest capability in the Apple Developer portal
5. Destroy the legacy Fly app `strangerwords` after cutover

## Self-Check: PASSED

Commits 4e05a38, ca80a73, bc9a9ba, 8a95143 are on HEAD; all modified files exist.
