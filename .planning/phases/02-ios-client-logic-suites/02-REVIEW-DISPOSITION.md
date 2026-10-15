---
phase: 02
review: 02-REVIEW.md
titles: json
findings:
  - id: WR-01
    severity: warning
    disposition: open
    title: "Enter-failure message is never shown at the threshold and leaks into ComposeView on retry"
  - id: WR-02
    severity: warning
    disposition: open
    title: "`begin()` does not clear a leftover sessionId, so a waiting engagement can persist the wrong session"
  - id: WR-03
    severity: warning
    disposition: open
    title: "`submitting` reset in `defer` is not epoch-guarded"
  - id: WR-04
    severity: warning
    disposition: open
    title: "Two tests assert before the action they check could have run (vacuous)"
  - id: WR-05
    severity: warning
    disposition: open
    title: "Test cleanup is skipped on any early exit, leaving on-disk UserDefaults suites"
  - id: WR-06
    severity: warning
    disposition: open
    title: "Race tests cannot detect a stale token write, and some skip the identity assertion"
  - id: WR-07
    severity: warning
    disposition: open
    title: "LocalBackend `cleanLine` can drift from the Go source without any test failing"
  - id: WR-08
    severity: warning
    disposition: open
    title: "`refresh` swallows every error, including `.gone`, after a 409"
  - id: IN-01
    severity: info
    disposition: open
    title: "Polling loops make one more backend call after cancellation"
  - id: IN-02
    severity: info
    disposition: open
    title: "Leaving while connecting or waiting leaves a server-side ghost; the tests pin it"
  - id: IN-03
    severity: info
    disposition: open
    title: "LocalBackend paces with wall-clock `Date()`"
  - id: IN-04
    severity: info
    disposition: open
    title: "Hosted-env and golden tests are tied to environment details"
  - id: IN-05
    severity: info
    disposition: open
    title: "Smaller items"
---

# Phase 2 Code Review Disposition

One row per finding from `02-REVIEW.md`. Default disposition is `open`. Update a row to
`fixed`, `skipped`, or `deferred` (with the reason in Source) when a finding is triaged.

| ID | Title | Severity | Disposition | Source |
|----|-------|----------|-------------|--------|
| WR-01 | Enter-failure message is never shown at the threshold and leaks into ComposeView on retry | warning | open | |
| WR-02 | `begin()` does not clear a leftover sessionId, so a waiting engagement can persist the wrong session | warning | open | |
| WR-03 | `submitting` reset in `defer` is not epoch-guarded | warning | open | |
| WR-04 | Two tests assert before the action they check could have run (vacuous) | warning | open | |
| WR-05 | Test cleanup is skipped on any early exit, leaving on-disk UserDefaults suites | warning | open | |
| WR-06 | Race tests cannot detect a stale token write, and some skip the identity assertion | warning | open | |
| WR-07 | LocalBackend `cleanLine` can drift from the Go source without any test failing | warning | open | |
| WR-08 | `refresh` swallows every error, including `.gone`, after a 409 | warning | open | |
| IN-01 | Polling loops make one more backend call after cancellation | info | open | |
| IN-02 | Leaving while connecting or waiting leaves a server-side ghost; the tests pin it | info | open | |
| IN-03 | LocalBackend paces with wall-clock `Date()` | info | open | |
| IN-04 | Hosted-env and golden tests are tied to environment details | info | open | |
| IN-05 | Smaller items | info | open | |
