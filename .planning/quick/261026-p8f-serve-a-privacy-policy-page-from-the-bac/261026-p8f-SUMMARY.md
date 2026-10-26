---
phase: quick-261026-p8f
plan: 01
subsystem: gateway
tags: [privacy, testflight, embed, go]
status: complete
requires: []
provides:
  - "GET /privacy public privacy policy page (embedded static HTML)"
affects: [server/internal/gateway]
tech-stack:
  added: []
  patterns: ["go:embed static page + constants-pinned drift test"]
key-files:
  created:
    - server/internal/gateway/privacy.html
    - server/internal/gateway/privacy.go
    - server/internal/gateway/privacy_test.go
  modified:
    - server/internal/gateway/gateway.go
decisions:
  - "Page served inside the normal middleware chain; not exempt from rate limiting"
  - "limiterMaxIdle constant extracted so the page's 10-minute claim is test-pinned"
metrics:
  tasks: 2
completed: 2026-10-26
commits: 2
plan_head_before: 4d1647e4768e3ea86ac58d6c75adf13b4fa6564b
plan_head_after: 4b0f71c66b093bf6b166b42f593c435051dd073a
actuals:
  tasks: 2
  commits: 2
---

# Quick Task 261026-p8f: Serve a privacy policy page from the backend

`GET /privacy` now serves an embedded, self-contained Stranger Words privacy policy (no JS, no external resources, dark mode via prefers-color-scheme) with CSP `default-src 'none'`, nosniff, and no-referrer. A test pins the page's numbers to the code constants.

## Commits

- `69d6257` feat: serve embedded privacy policy page at GET /privacy (tracer: shell, handler, route, TestPrivacyPage)
- `4b0f71c` feat: write verified privacy policy sections and pin page facts to code constants

## privacy.html sections

Intro, No accounts / no identity, Your poem is ephemeral, The one exception: reported poems, What our server handles while it runs, On your device, The robot poet, Who else is involved, Changes to this policy, Contact (privacy@strangewords.app). Effective October 26, 2026.

## Tests

- `TestPrivacyPage` - pass (200, exact content-type, security headers, byte-identity with embed, POST 405, `route="GET /privacy"` in /metrics)
- `TestPrivacyPageMatchesCode` - pass (15/90/10-minute TTLs, limiter idle, 280 chars, two-minute reveal, 32-byte token, required phrases, banned constructs)
- RED confirmed before each implementation step. `go test ./... -count=1`, `go vet ./...`, `gofmt -l server/` all clean. go.mod/go.sum unchanged. No p8f commit touches server/cmd/bot. origin/main still d1e0d60.

## Brief corrections (applied as the plan directed)

1. No per-request access log exists; the page says server logs hold only operational events.
2. The app sends no push token (`enter(pushToken: nil)`, `push.Noop`); the page says push is not currently used.
3. No in-app report button yet; the page says "if a poem is reported".
4. Managed Redis is Upstash via Fly.io; both providers are named.

## Deviations from Plan

None - plan executed exactly as written. (`allow_default_branch_commits: true` in `.planning/config.json` permitted committing on main.)

## Notes for the developer

- The URL goes live only after you push `server/**` to main (Fly auto-deploy) and the api.strangewords.app certificate and DNS are in place. Nothing was pushed.
- Flag carried from T-no9-02: the page discloses that reported poem lines are kept in server logs, while `ios/Strangewords/PrivacyInfo.xcprivacy` declares no collected data types. Decide whether the App Store Connect privacy label and manifest should declare "Other User Content" for moderation.

## Known Stubs

None.

## Self-Check: PASSED

Files privacy.html, privacy.go, privacy_test.go exist; commits 69d6257 and 4b0f71c are on HEAD.
