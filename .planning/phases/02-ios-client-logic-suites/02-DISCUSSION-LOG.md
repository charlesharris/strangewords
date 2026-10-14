# Phase 2: iOS Client Logic Suites - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-14
**Phase:** 2-iOS Client Logic Suites
**Areas discussed:** Seam shape (IOST-05), Driving async & time, Late-poll race fix, Test content & naming

---

## Seam shape (IOST-05)

| Option | Description | Selected |
|--------|-------------|----------|
| Static + injectable defaults (Recommended) | Keep the static enum; add `static var defaults`. Zero call-site changes; still process-global | |
| Instance injected into AppModel | Convert TokenStore to a struct with `init(defaults:)`, pass as defaulted AppModel init param | ✓ |
| You decide | Planner picks | |

**User's choice:** Instance injected into AppModel

| Option | Description | Selected |
|--------|-------------|----------|
| Zero-delay init params (Recommended) | `init(strangerThinkTime: 1.6, enterDelay: 600ms)`; tests pass 0; pacing feel untested | ✓ |
| Also inject a clock (now closure) | Zero-delay params plus injectable `now` to test the pacing rule itself | |
| You decide | Planner picks | |

**User's choice:** Zero-delay init params

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, minimal (Recommended) | pollInterval + base params only; no URLSession injection (DRFT-02 deferred) | |
| Also inject URLSession now | Add `session: URLSession = .shared` to APIClient as v2 groundwork | ✓ |
| You decide | Planner keeps defaults identical | |

**User's choice:** Also inject URLSession now
**Notes:** Seam only — URLProtocol stub tests themselves stay v2 (DRFT-02).

| Option | Description | Selected |
|--------|-------------|----------|
| Guard test + ephemeral suites (Recommended) | Suite-named UserDefaults + explicit test asserting `.standard` has no `sw.*` keys | ✓ |
| Injection alone is enough | Instance TokenStore means tests never touch `.standard`; skip guard test | |
| You decide | Planner weighs it | |

**User's choice:** Guard test + ephemeral suites

---

## Driving async & time

| Option | Description | Selected |
|--------|-------------|----------|
| Scripted fake in test bundle (Recommended) | Test-only FakeBackend with scripted responses/errors and continuation gates; LocalBackend stays production-pure | ✓ |
| Extend LocalBackend with failure injection | One double for both suites; pollutes the production mock | |
| Both as needed | Fake for arc/errors + one LocalBackend happy-path arc test | |

**User's choice:** Scripted fake in test bundle

| Option | Description | Selected |
|--------|-------------|----------|
| Near-zero interval + gated fake (Recommended) | pollInterval ≈ .zero; pacing from the fake's gates; no extra seam | ✓ |
| Injected sleeper closure | `sleep:` closure seam; more explicit, needs justification | |
| You decide | Planner prototypes | |

**User's choice:** Near-zero interval + gated fake

| Option | Description | Selected |
|--------|-------------|----------|
| Track in-flight task (Recommended) | Actions store their Task in `@ObservationIgnored private(set) var`; tests await it | ✓ |
| Actions return their Task | `@discardableResult` Task returns | |
| Poll state with timeout | Yield-loops with deadline; classic flake source | |

**User's choice:** Track in-flight task

---

## Late-poll race fix

| Option | Description | Selected |
|--------|-------------|----------|
| Cancellation check after await (Recommended) | Guard `!Task.isCancelled` before mutations in poll loops | |
| Session epoch/generation guard | Counter bumped on begin/reset/dissolve; apply() rejects stale generations | |
| Both: isCancelled in loops + epoch in apply() | Loops stop when cancelled AND apply() rejects any stale writer | ✓ |

**User's choice:** Both layers

| Option | Description | Selected |
|--------|-------------|----------|
| Stale poll + stale submit (Recommended) | Gated poll and gated submitLine responses released after leave(); second test justifies the epoch | ✓ |
| Stale poll only | Only the criterion-named case | |
| All writer paths | Also stale begin/resume/refresh; diminishing value | |

**User's choice:** Stale poll + stale submit

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, red-then-green (Recommended) | Test first, record failure against unfixed code, then fix; evidence for FIX-01 ledger | ✓ |
| Fix and test together | One commit; weaker evidence | |

**User's choice:** Yes, red-then-green

---

## Test content & naming

| Option | Description | Selected |
|--------|-------------|----------|
| Fix AppModel-visible drift (Recommended) | Bring LocalBackend up to server semantics where the divergence changes what AppModel/user experiences (e.g., line rejection); pin cosmetic-equivalent drift with a note | ✓ |
| Pin current behavior, document all drift | Pure characterization; no mock changes | |
| Full parity now | Pulls DRFT-01 into this phase; scope risk | |

**User's choice:** Fix AppModel-visible drift

| Option | Description | Selected |
|--------|-------------|----------|
| Pin misses as characterization (Recommended) | Include poem/quiet/rhythm at current wrong counts, commented as known limits | ✓ |
| Fix the heuristic for the misses | Feature work in a verification milestone | |
| Leave misses out of the table | Half-pinned heuristic | |

**User's choice:** Pin misses as characterization

| Option | Description | Selected |
|--------|-------------|----------|
| Capture from current code (Recommended) | Run coin() over ~6–10 varied poems, sanity-check, commit input→name goldens | ✓ |
| Hand-derive from the algorithm | Laborious; word lists make it transcription | |
| Property-style only | Determinism asserts only; misses hash/PRNG swaps | |

**User's choice:** Capture from current code

| Option | Description | Selected |
|--------|-------------|----------|
| Doc comment citing server test/file (Recommended) | `/// mirrors TestRoundRobinHaikuIsABA (server/internal/sessions/policy_test.go)` | ✓ |
| Shared scenario-name table | DRFT-01 shape pulled forward | |
| Test display names only | Lighter, less precise | |

**User's choice:** Doc comment citing server test/file

---

## Claude's Discretion

- Exact seam parameter labels; where the epoch counter lives in AppModel
- FakeBackend gating API design (continuations vs AsyncStream) — whatever is least flaky under `@Suite(.serialized)`
- Which suites need `.serialized` vs can run parallel
- Suite/file organization in `ios/StrangewordsTests/`
- Syllables table size and edge cases beyond named misses and 5/7/5 thresholds
- Case-by-case judgment of which LocalBackend divergences are "AppModel-visible" (line rejection confirmed in)

## Deferred Ideas

- URLProtocol stub tests for APIClient — DRFT-02 (v2); only the session seam lands now
- Full LocalBackend/server parity contract (shared scenario table, drift list doc) — DRFT-01 (v2)
- Fixing the Syllables heuristic misses — deliberate non-goal; would change the in-app nudge
