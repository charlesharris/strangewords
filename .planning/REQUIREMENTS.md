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

### Robot Poet (Phase 5)

Added with Phase 5 (Opt-In Robot Poet Collaboration). Each ID traces to the locked decisions and constraints in `.planning/phases/05-opt-in-robot-poet-collaboration/05-CONTEXT.md` (decisions 1-5, cited as D-01 to D-05).

- [x] **P5-OPTIN**: A user is paired with the robot poet only after opting in. The setting defaults OFF, and an absent, false or malformed `allowBot` on `POST /v1/enter` means humans only, so TestFlight 0.1.0, which sends no flag, stays humans-only (D-01; the backward-compatibility constraint)
- [x] **P5-FALLBACK**: Opted-in users try for a human first. Only after a `[TUNABLE]` wait window (about 25s) does the robot poet step in. Two overlapping opted-in humans pair with each other, and a human-vs-robot race never yields two sessions. The robot poet writes its lines from `server/internal/poet` with no external AI, and its lines never overwrite a newer line (D-03, D-05)
- [x] **P5-DISCLOSE**: Every view of a robot-poet session discloses it. `partnerIsBot` is computed only server-side, decoded tolerantly on iOS, and shown as named presence ("the robot poet") for the whole session in Compose and Reveal (D-04)
- [x] **P5-ANON**: The anonymity model holds. The opt-in bit lives only on the TTL-bound wait entry, no new Redis keys or locks are added, zero `sw:` keys remain after dissolution, and the on-device preference sits outside the identity namespace and is never an identifier (the CONTEXT anonymity constraint)
- [x] **P5-SETTINGS**: A quiet gear on the Threshold opens a minimal settings sheet holding the one robot-poet toggle, persisted in a UserDefaults sibling of `TokenStore` (D-02)
- [x] **P5-PARITY**: The wire change is mirrored in `Models.swift`, the `Backend` protocol, `APIClient` and `LocalBackend` (and the test `FakeBackend`), so mock mode walks the same wait-then-robot-poet arc as the server (the CONTEXT mock/real parity constraint)
- [x] **P5-TESTS**: Every behavior above ships with automated proof on both sides: Go tests under `go test ./...` and Swift Testing suites under `scripts/test-ios.sh` (the CONTEXT tests-on-both-sides constraint)

### Two-Poem Trade (Phase 6)

Added with Phase 6 (Two-Poem Trade). Each ID traces to the locked decisions D-01 to D-06 and the orchestrator defaults in `.planning/phases/06-two-poem-trade/06-CONTEXT.md`.

- [x] **P6-TRADE**: After poem 1's reveal either participant may offer to trade back (`POST /v1/session/{id}/trade`), and poem 2 begins in the same session only when every participant has asked. Each poem gets its own reveal, an encounter holds at most two poems, and declining (letting go), leaving or letting the reveal lapse dissolves exactly as today; an unanswered offer ages out with the existing RevealTTL, with no new timer (D-01, D-02)
- [x] **P6-ROLES**: Poem 2's roles swap: whoever wrote lines 1 and 3 of poem 1 writes line 2 of poem 2. The swap is derived from the encounter's `StartIndex` plus the poem ordinal (`PoemCount`) in `Session.AuthorOf`, never a policy change (D-03)
- [x] **P6-BOT**: The robot poet accepts a trade offer on its own, only after its think time (never on the immediate poll), and writes poem 2 from a deterministic replay seeded by the session id and poem number, so a server restart mid-trade changes nothing (D-06)
- [ ] **P6-KEEPSAKE**: The on-device coiner runs once per completed poem (two names after a full trade, poem 1's coined while its lines are still in hand as poem 2 begins), and `CoinedName.kind` and its line on the Dissolved screen are removed everywhere, for single poems too. Nothing new leaves the device (D-04, D-05)
- [x] **P6-ANON**: The anonymity model holds. All trade state is TTL-bound inside the existing session blob, no new identifier or `sw:` key class is added, poem 1's lines and retry cache are erased when poem 2 begins, the encounter stays bounded by the token refs' `SessionTTL`, and zero `sw:` keys remain after dissolution (the CONTEXT anonymity default)
- [x] **P6-COMPAT**: Wire changes are tolerant both ways. New `View` fields are `omitempty` and decoded leniently on iOS, an old client that never calls `/trade` dissolves as today (no one is ever pulled into a second poem), and a new client facing an old server never shows the trade (the CONTEXT wire-tolerance default)
- [x] **P6-PARITY**: The trade is mirrored in `Models.swift`, the `Backend` protocol, `APIClient`, `LocalBackend` and the test `FakeBackend`, so mock mode walks the full arc: offer, acceptance, poem 2 with roles swapped, its own reveal, dissolution (the CONTEXT parity constraint)
- [ ] **P6-UI**: The Reveal screen offers a quiet "trade back" beside "let it go" in the app's ritual voice, shown only when the server says the trade is open, with a caption while an offer waits or after it passes. Every string is a pure function pinned by tests, and robot-poet copy names the robot poet (orchestrator default; Phase 5 voice rule)
- [ ] **P6-TESTS**: Every behavior above ships with automated proof on both sides: Go tests under `go test ./...` (race-sensitive paths also under `-race`) and Swift Testing suites under `scripts/test-ios.sh`, with no wall-clock sleeps (the CONTEXT tests-on-both-sides constraint)

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
| P5-OPTIN | Phase 5 | Complete |
| P5-FALLBACK | Phase 5 | Complete |
| P5-DISCLOSE | Phase 5 | Complete |
| P5-ANON | Phase 5 | Complete |
| P5-SETTINGS | Phase 5 | Complete |
| P5-PARITY | Phase 5 | Complete |
| P5-TESTS | Phase 5 | Complete |
| P6-TRADE | Phase 6 | Complete |
| P6-ROLES | Phase 6 | Complete |
| P6-BOT | Phase 6 | Complete |
| P6-KEEPSAKE | Phase 6 | Pending |
| P6-ANON | Phase 6 | Complete |
| P6-COMPAT | Phase 6 | Complete |
| P6-PARITY | Phase 6 | Complete |
| P6-UI | Phase 6 | Pending |
| P6-TESTS | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 30 total (14 baseline + 7 Phase 5 + 9 Phase 6)
- Mapped to phases: 30
- Unmapped: 0 ✓

---
*Requirements defined: 2026-10-08*
*Last updated: 2026-10-29 after Phase 6 planning (P6-* IDs defined and mapped)*
