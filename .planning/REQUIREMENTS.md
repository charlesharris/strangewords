# Requirements: Stranger Words — Verification Baseline

**Defined:** 2026-10-08
**Core Value:** A trustworthy, automated proof that the core experience works — so every future change can be verified against a known-good baseline instead of memory and manual poking.

## v1 Requirements

Requirements for this milestone. Each maps to roadmap phases. The "user" is the developer (and later CI) who needs a repeatable answer to "is the core experience still working?"

### Harness

- [x] **HARN-01**: Working tree is reconciled (the six uncommitted/untracked files committed or reverted deliberately) and all existing checks pass: `go test ./...`, `go vet`, `go build`, `xcodegen generate` + `xcodebuild build`
- [x] **HARN-02**: iOS unit-test target exists in `ios/project.yml` (hosted `bundle.unit-test`, scheme `test:` action) and survives `xcodegen generate`
- [x] **HARN-03**: Developer can run the iOS test suite headlessly from the CLI with a trustworthy verdict — non-zero exit on failure, and a run with zero executed tests counts as failure
- [ ] **HARN-04**: Developer can run every verification stage (Go checks, iOS tests, e2e) with one command, with per-stage skip flags
- [ ] **HARN-05**: A dated baseline evidence record exists: commit hash, tool versions, per-suite pass counts, and an explicit not-verified list

### iOS Test Suites

- [x] **IOST-01**: `Syllables` heuristic is covered by table-driven characterization tests (words, lines, edge cases, the 5/7/5 thresholds)
- [x] **IOST-02**: `PoemNaming` determinism is pinned with golden poem→name values (same poem → same name; hash/PRNG stability)
- [x] **IOST-03**: `LocalBackend` semantics tests mirror the server rules: pairing, round-robin turn order, line validation/rejection, idempotent resubmit, teardown
- [x] **IOST-04**: `AppModel` state machine is covered across the full arc (threshold → waiting → compose → reveal → dissolve → dissolved), including submit errors, partner-gone, and begin-again — with no real-time sleeps
- [x] **IOST-05**: Test seams exist as defaulted init parameters with unchanged app behavior: injectable poll interval, mock backend delays, API base, and `UserDefaults` for `TokenStore`

### End-to-End

- [ ] **E2E-01**: A scripted end-to-end run proves match → turns → completion → dissolution against the real server with a pass/fail exit code, unattended and deadline-bounded (includes hardening the robot poet: non-zero exit on failure, machine-readable result)
- [ ] **E2E-02**: The e2e run asserts the anonymity invariant after dissolution on the live path: session gone for both tokens, zero `sw:*` keys, dissolved metric incremented

### Contract

- [ ] **CONT-01**: Swift tests decode wire-format JSON fixtures captured from the Go server (`enter`, `waiting`, session views, errors), catching iOS/Go model drift without a running server

### Fixes

- [ ] **FIX-01**: Every failure found during verification is either fixed with a regression test, or recorded as an expected failure citing a documented reason — no silently weakened assertions (the known `WaitEntry` leak and the late-poll race are expected finds)

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Drift Guards

- **DRFT-01**: Mock/real parity contract — same-named scenarios run against `LocalBackend` and the real server, plus a documented drift list
- **DRFT-02**: `APIClient` tests via `URLProtocol` stub (request shape, bearer header, error mapping)
- **DRFT-03**: Client persistence hygiene test — `UserDefaults` holds only the token and is cleared at terminal phases

### Reporting

- **REPT-01**: Non-gating coverage report (iOS `xccov`, `go test -cover`)
- **REPT-02**: `go test -race ./...` in the verify run
- **REPT-03**: One-off 5× flake check on the iOS suite

### CI

- **CI-01**: CI pipeline running the verify stages as a test gate before Fly deploy (the verify entry point makes this a one-liner later)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| XCUITest / UI automation | Slow, flaky, needs accessibility IDs; UI is a thin layer over the tested AppModel |
| Snapshot / visual regression tests | Needs a third-party lib (violates no-deps convention); pixel/animation output brittle across OS versions |
| Device farm / multi-OS matrix | iOS 17+ pre-TestFlight app; one pinned simulator destination is enough |
| Production / Fly.io verification, load tests | Milestone decision: local/automated only; load tests risk tripping prod rate limiting |
| Coverage thresholds / gates | Arbitrary numbers invite gaming; report only (v2) |
| Third-party test libraries | Breaks the no-third-party-iOS-deps convention; hand-written fakes suffice |
| Re-covering already-tested Go code | Gateway integration tests cover store/matchmaker; new Go tests only for fix-as-we-go bugs |
| Fuzz / property-based testing | Disproportionate for heuristics with known-imperfect specs; golden/table tests give the signal |
| Testability refactors beyond minimal seams | Scope creep in a working app; only seams justified by a specific test |
| Manual feel pass / Dynamic Type audit | User chose automated checks only this milestone |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| HARN-01 | Phase 1 | Complete |
| HARN-02 | Phase 1 | Complete |
| HARN-03 | Phase 1 | Complete |
| IOST-01 | Phase 2 | Complete |
| IOST-02 | Phase 2 | Complete |
| IOST-03 | Phase 2 | Complete |
| IOST-04 | Phase 2 | Complete |
| IOST-05 | Phase 2 | Complete |
| E2E-01 | Phase 3 | Pending |
| E2E-02 | Phase 3 | Pending |
| CONT-01 | Phase 3 | Pending |
| HARN-04 | Phase 4 | Pending |
| HARN-05 | Phase 4 | Pending |
| FIX-01 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0 ✓

---
*Requirements defined: 2026-10-08*
*Last updated: 2026-10-08 after roadmap creation (traceability mapped)*
