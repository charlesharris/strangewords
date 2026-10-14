---
phase: 01
review: 01-REVIEW.md
titles: json
findings:
  - id: WR-01
    severity: warning
    disposition: open
    title: "Stale evidence and a stale `ios-verdict.txt` survive when `SW_VERIFY_OUT` is reused, including on exit-2 paths"
  - id: WR-02
    severity: warning
    disposition: open
    title: "A simulator boot failure is swallowed and then reported as a test FAIL (exit 1) instead of an environment error (exit 2)"
  - id: WR-03
    severity: warning
    disposition: open
    title: "Simulator selection is non-deterministic across runtimes, differs from `run.sh`, and the evidence does not record what was used"
  - id: WR-04
    severity: warning
    disposition: open
    title: "`AppAttestAppID` is fail-open by default and is not yet read or documented for deploy"
  - id: IN-01
    severity: info
    disposition: open
    title: "The selfcheck header claims it proves the verdict paths, but the retry path is never exercised"
  - id: IN-02
    severity: info
    disposition: open
    title: "`hostRunsInLocalMockMode` verifies only environment variables, not the backend actually selected"
  - id: IN-03
    severity: info
    disposition: open
    title: "The PASS verdict has no minimum-test floor"
  - id: IN-04
    severity: info
    disposition: open
    title: "`docs/STATUS.md` is partly stale and does not mention the new harness"
  - id: IN-05
    severity: info
    disposition: open
    title: "Pass-through args can override the runner's pinned destination or result bundle path"
open: 9
total: 9
recorded: 2026-10-14T17:59:36.163Z
---

# Phase 01: Code Review Disposition

| Finding | Severity | Disposition | Source |
|---------|----------|-------------|--------|
| WR-01 | warning | open | - |
| WR-02 | warning | open | - |
| WR-03 | warning | open | - |
| WR-04 | warning | open | - |
| IN-01 | info | open | - |
| IN-02 | info | open | - |
| IN-03 | info | open | - |
| IN-04 | info | open | - |
| IN-05 | info | open | - |

Dispositions: `open` (recorded, not yet triaged), `fixed`, `skipped`, `deferred`.
Set `deferred` by hand and put the reason in the Source cell; both are preserved. A `|` in the reason is kept as prose and escaped on the next run.
Re-running the gate keeps every row it can. A row the current review no longer reports is kept and its Source cell flagged, so a finding does not leave this record silently. ONE exception: when a finding id is REUSED by a different finding, the earlier decision cannot keep a row — the id is taken — and it is dropped. A RECORDED decision (anything but `open`) is named on the console when that happens; a row still at `open` is replaced silently, because `open` records no decision to lose.
