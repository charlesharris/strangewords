---
phase: 02-ios-client-logic-suites
plan: 04
subsystem: testing
tags: [swift-testing, golden-tests, characterization, syllables, poem-naming, mutation-check]

requires:
  - phase: 02-ios-client-logic-suites
    provides: "Plan 02-01: scripts/test-ios.sh harness and the Phase 1 SyllablesTests seed. Plans 02-02/02-03 serialized use of the single pinned simulator"
provides:
  - "PoemNamingTests: six golden poem-to-name pins captured on the iOS 18.6 simulator, nil cases, case-insensitivity, determinism"
  - "SyllablesTests grown to a table-driven characterization with seven known misses pinned at their current counts"
  - "SessionViewTests: 5/7/5 currentTarget thresholds, out-of-range and null handling, classic haiku meets each target"
  - "Three mutation checks (FNV basis, SplitMix64 constant, vowel set), each caught by a named test and reverted"
affects: [phase-04 verify ledger, DRIFT-TOOLCHAIN golden re-capture rule]

actuals:
  tokens: 2074
  tasks: 2
  commits: 2

plan_head_before: e16c1e3c646836e71ee905db9b24f232247fc69c
plan_head_after: d0b6488adbed1208cdbf36d30493bd30b1b1b043

tech-stack:
  added: []
  patterns:
    - "Goldens captured on the pinned simulator runtime with the runtime recorded in the file header"
    - "Mutation check as verification only: apply with sed, run on the simulator, git checkout to revert, keep evidence under gitignored build/verify"
    - "Known heuristic misses pinned as-is in a dedicated knownMiss test, each row commented with the true count and the reason"

key-files:
  created:
    - ios/StrangewordsTests/PoemNamingTests.swift
    - ios/StrangewordsTests/SessionViewTests.swift
  modified:
    - ios/StrangewordsTests/SyllablesTests.swift

key-decisions:
  - "Goldens were not re-captured: all six host-captured RESEARCH candidates matched the iOS 18.6 simulator on the first run"
  - "Known Syllables misses are pinned at their wrong counts (D-12) and not fixed; PoemNaming.swift and Syllables.swift are unchanged"

patterns-established:
  - "A golden failure after an Xcode or iOS update is first suspected as stdlib shuffle drift; re-capture only with a cited reason in the commit and the Phase 4 ledger"

requirements-completed: [IOST-01, IOST-02]

coverage:
  - id: D1
    description: "Keepsake naming pinned by goldens, with nil cases, case-insensitivity, and determinism"
    requirement: IOST-02
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/PoemNamingTests.swift (golden, noContentWordsCoinsNothing, caseDoesNotChangeTheName, coinIsDeterministic) via scripts/test-ios.sh"
        status: pass
    human_judgment: false
  - id: D2
    description: "A hash mutation and a PRNG mutation each fail a named PoemNamingTests test"
    requirement: IOST-02
    verification:
      - kind: integration
        ref: "build/verify/02-04-mut-fnv and build/verify/02-04-mut-splitmix ios-summary-1.json: result Failed, PoemNamingTests/golden(_:)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Syllable heuristic characterized word by word, including known misses, and 5/7/5 targets pinned through SessionView.currentTarget"
    requirement: IOST-01
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/SyllablesTests.swift and SessionViewTests.swift via scripts/test-ios.sh"
        status: pass
    human_judgment: false
  - id: D4
    description: "A vowel-set mutation fails a named SyllablesTests test"
    requirement: IOST-01
    verification:
      - kind: integration
        ref: "build/verify/02-04-mut-vowels ios-summary-1.json: result Failed, SyllablesTests/word(_:_:) on the happy row"
        status: pass
    human_judgment: false

duration: 3min
completed: 2026-10-15
status: complete
---

# Phase 2 Plan 04: Poem Naming and Syllable Suites Summary

**PoemNaming goldens captured on the iOS 18.6 simulator, a Syllables characterization table with seven known misses pinned, and 5/7/5 targets pinned through SessionView, with FNV, SplitMix64, and vowel-set mutations each caught by a named test**

## Performance

- **Duration:** 3 min
- **Started:** 2026-10-15T18:34:34Z
- **Completed:** 2026-10-15T18:38:08Z
- **Tasks:** 2
- **Files modified:** 3 (two created, one extended); no app code touched

## Accomplishments

- Keepsake naming is pinned by six golden poem-to-name rows (classic haiku, repeated lines, single word, 40-repeat long line, unicode, mock-stranger lines), plus the nil cases, case-insensitivity, and determinism tests.
- Syllables is a table-driven characterization: correct words, edge inputs, seven known misses pinned as-is, and haiku lines including punctuation and whitespace-only input.
- `SessionView.currentTarget` is pinned: 5/7/5 for lines 0/1/2, nil for line 3 and -1, nil for a null form entry, and the classic haiku counts exactly its target on each line.
- ROADMAP success criterion 2 is met: all three mutations (hash, PRNG, heuristic) were run on the simulator and each failed a named test.
- ROADMAP success criterion 5 closes: the full suite passes 67 tests (1 skipped, the harness canary `failsOnPurpose`) in 5.37 s of test time, with no wall-clock waits under `ios/StrangewordsTests`.

## Capture runtime and host-vs-simulator differences

- **Captured on:** iPhone 16 simulator, iOS 18.6 (22G86), Xcode 16.4 (16F6). Recorded in the `PoemNamingTests` doc comment.
- **Host vs simulator:** none. All six RESEARCH candidates (captured on the macOS host stdlib) matched the simulator on the first run, so no golden was changed. Each captured name is title-cased content words from its poem, each kind is a catalogue kind, and each lead is one of the six leads.

## Mutation-check outcomes (verification only, never committed)

| Mutation | Command target | Exit | Failing test id |
|----------|----------------|------|-----------------|
| FNV offset basis `0xcbf29ce484222325` to `...324` | `-only-testing:StrangewordsTests/PoemNamingTests` | 1 | `PoemNamingTests/golden(_:)` |
| SplitMix64 `0xBF58476D1CE4E5B9` to `...B8` | `-only-testing:StrangewordsTests/PoemNamingTests` | 1 | `PoemNamingTests/golden(_:)` |
| Vowel set `Set("aeiouy")` to `Set("aeiou")` | `-only-testing:StrangewordsTests/SyllablesTests` | 1 | `SyllablesTests/word(_:_:)` (`"happy"`, expected 2, got 1) |

Each mutation was reverted with `git checkout --`; `git diff --quiet` on `PoemNaming.swift` and `Syllables.swift` exits 0, and no commit since `cbfa2da` touches either file. Evidence is under the gitignored `build/verify/02-04-mut-fnv/`, `02-04-mut-splitmix/`, and `02-04-mut-vowels/`.

## Task Commits

1. **Task 1: PoemNaming goldens, mutation-proven** - `cfb5a6e` (test)
2. **Task 2: Syllables characterization, 5/7/5 thresholds, vowel mutation** - `d0b6488` (test)

**Plan metadata:** committed separately as `docs(02-04): complete poem naming and syllable suites plan`

## Files Created/Modified

- `ios/StrangewordsTests/PoemNamingTests.swift` - golden pins, nil cases, case-insensitivity, determinism, runtime recorded
- `ios/StrangewordsTests/SyllablesTests.swift` - extended `word` and `haikuLine` tables, new `knownMiss` test, updated header (D-12)
- `ios/StrangewordsTests/SessionViewTests.swift` - `currentTarget` thresholds and haiku-meets-target test

## Decisions Made

- Goldens were not re-captured: the host candidates matched the simulator, so there was no drift to cite. The no-silent-re-capture prohibition holds.
- Known Syllables misses are pinned at their current, wrong counts rather than fixed (D-12); the nudge users receive is unchanged.

## Deviations from Plan

None - plan executed exactly as written. No Syllables row needed correcting: every measured RESEARCH value matched the simulator.

## Issues Encountered

None.

## Known Stubs

None.

## Threat Flags

None. These are pure-function tests over fixed literals; nothing is written to disk or defaults (T-2-11 accepted). T-2-10 is mitigated by the recorded runtime, the two mutation proofs, and the unchanged `PoemNaming.swift` and `Syllables.swift`.

## Next Phase Readiness

- Phase 2 plans are all complete; the phase is ready for verification. `scripts/test-ios.sh` passes with 67 passed, 0 failed, 1 skipped (canary) in 5.37 s.
- DRIFT-TOOLCHAIN carries to Phase 4: the PoemNaming goldens depend on the iOS 18.6 stdlib's seeded shuffle, and only iOS 18.6 is installed. A golden failure after an Xcode or iOS update should first be suspected as toolchain drift.

## Self-Check: PASSED

- `ios/StrangewordsTests/PoemNamingTests.swift`, `SyllablesTests.swift`, `SessionViewTests.swift` exist on disk.
- Commits `cfb5a6e` and `d0b6488` are ancestors of HEAD.
- `scripts/test-ios.sh` exits 0 (67 passed); the three mutation summaries each report `Failed` naming the expected suite; `git status --porcelain -- . ':(exclude).planning'` is empty.

---
*Phase: 02-ios-client-logic-suites*
*Completed: 2026-10-15*
