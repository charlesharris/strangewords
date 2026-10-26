---
phase: quick-261026-p8l
plan: 01
subsystem: server/internal/poet, server/cmd/bot
tags: [go, robot-poet, generative, syllables, bot]
requires: []
provides:
  - "server/internal/poet: Count, New, (*Poet).Theme, (*Poet).Line"
  - "bot lines composed generatively; seedFor and composeLine seams"
affects: [server/cmd/bot]
tech-stack:
  added: []
  patterns:
    - "seeded math/rand/v2 PCG; slices (never maps) for every RNG choice"
    - "template solver: depth-first search over per-slot syllable buckets"
key-files:
  created:
    - server/internal/poet/syllables.go
    - server/internal/poet/syllables_test.go
    - server/internal/poet/themes.go
    - server/internal/poet/poet.go
    - server/internal/poet/poet_test.go
    - server/internal/poet/echo.go
    - server/internal/poet/echo_test.go
    - server/cmd/bot/main_test.go
  modified:
    - server/cmd/bot/main.go
key-decisions:
  - "Pure stdlib generative grammar, no external AI or API calls (locked)"
  - "Go estimator is a superset of the iOS heuristic; iOS untouched"
  - "Echo never uses nearest fit; it either fits exactly or the bot composes normally"
requirements-completed: [QUICK-261026-p8l]
status: complete
duration: ~35min
completed: 2026-10-26
commits: 3
plan_head_before: 73ba1e94669389a338b694b7d695b6157ab6d1fc
plan_head_after: 9147a60c243ce3cf2ed0de3eabecfd198a40706c
actuals:
  tokens: 10700
  tasks: 3
  commits: 3
---

# Phase quick-261026-p8l Plan 01: Generative Robot Poet Summary

**Stdlib-only generative poet (5 themes, seeded template solver, partner-word echo with theme siblings) replaces the bot's two hardcoded line pools, hitting 5 and 7 syllables exactly across 500-seed sweeps.**

## What was built

- `server/internal/poet/syllables.go`: `Count`, a port of the iOS vowel-cluster heuristic plus suffix rules and an overrides map (poem, quiet, rhythm, create, café). Corrects every known miss pinned in `SyllablesTests.swift`.
- `themes.go`: five themes (night sky, seasons, water, small creatures, quiet rooms), nouns/adjectives/verbs bucketed by true syllable count, a shared preposition bank, and a `[TUNABLE]` registry.
- `poet.go`: `New(seed)` (first RNG draw picks the theme), `Line(target, previous)`. Eight grammar templates; a depth-first solver over per-slot syllable buckets; a strict pass that avoids reusing words, then a lenient pass; nearest-fit for off-range targets; a last-resort safety-net line. Never blocks, never empty.
- `echo.go`: stopwords ported from `PoemNaming.swift`, `contentWords`, four echo templates, a reverse bank index, and a theme-sibling swap. Own lines are never echoed.
- `server/cmd/bot/main.go`: pools and old picker removed. `poet.New(seedFor(view.SessionID))` is created right after the match; `composeLine(p, view)` returns `p.Line(target(v), v.Lines)`. The think pause is now `[TUNABLE]` consts with the same values (1500 + up to 1800 ms). Enter, wait, poll, submit, dismiss, and the HTTP helpers are untouched.

## Verification

- `go test ./...`, `go vet ./...`, `go build ./...`, and `gofmt -l server/` are clean. No gateway failures occurred.
- All 14 Task 2 and 13 Task 3 named tests pass: 500-seed sweeps with and without partner lines, determinism, variety (all 5 themes, 120+ distinct openings in 200 seeds), in-theme vocabulary, no repeated bank words, nearest-fit, echo (direct, unknown word, over budget, stopwords only, own lines, theme-adjacent), and the bot seam tests against the real haiku form.
- Non-test poet files import only `math/rand/v2`, `strings`, and `unicode`.
- Commit scope: only `server/internal/poet/`, `server/cmd/bot/main.go`, and `server/cmd/bot/main_test.go`. No ios/, gateway, or sessions changes. `go.mod` and `go.sum` untouched. Nothing pushed: origin/main is still 73ba1e9.

Sample poem (water theme, partner line in the middle): "shell spills on the stream / a heron folds into mist / heron above the inlet".

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Estimator over-dropped a final "e" that ends a vowel group**
- **Found during:** Task 2 (TestBankCountsMatchEstimator rejected "chickadee", a correct 3-syllable word)
- **Issue:** The plan's rule (a) dropped a trailing "e" whenever the word ended in "e", so "agree", "movie", and "chickadee" lost a real syllable (the "ee" or "ie" is already one counted group).
- **Fix:** Drop the final "e" only when a consonant precedes it. consonant+"le" still keeps its syllable. All 67 pinned rows are unaffected; added rows for agree, movie, chickadee.
- **Files modified:** server/internal/poet/syllables.go, syllables_test.go
- **Commit:** ffc013e

**2. [Rule 1 - Bug] Estimator dropped the syllabic l in consonant+"led"**
- **Found during:** Task 1 design (tangled, rippled would count one short under rule (c))
- **Fix:** rule (c) keeps the syllable for consonant+"led", mirroring rule (a)'s consonant+"le" exemption. Added rows for tangled and sailed.
- **Files modified:** server/internal/poet/syllables.go, syllables_test.go
- **Commit:** 744be70 (code), ffc013e (tests)

**3. [Rule 2 - Missing critical] Cap echoed word length**
- **Issue:** A partner word of 100 letters counts as 1 syllable, so echoing it could push the line past the server's 100-rune cap and get the bot's line rejected.
- **Fix:** added `maxEchoWordLen = 24` (`[TUNABLE]`); longer candidates are skipped.
- **Files modified:** server/internal/poet/echo.go
- **Commit:** 9147a60

**4. Bank word swaps (not rule changes)**
- "hyacinth", "shoreline", and "firefly" (planning example) were avoided or replaced because their dictionary syllable count disagrees with the estimator (replaced by "equinox" and "seashore"). Per the plan, no word was put in a wrong bucket.

Otherwise the plan was executed as written.

## Known Stubs

None.

## Notes for the user

- The bot may echo the same partner word on more than one of its lines when the partner's line is the most recent one in `v.Lines` each time. Harmless; tune `defaultEchoChance` if it feels repetitive.
- Tunables: `defaultEchoChance` (0.8), `defaultAdjacentChance` (0.3), `maxEchoCandidates` (8), `maxEchoWordLen` (24), `thinkBaseMS`, `thinkJitterMS`, and the `themes` registry.

## Threat Flags

None. The poet package has no network, file, logging, or fmt imports.

## Self-Check: PASSED

- server/internal/poet/{syllables,themes,poet,echo}.go and their tests: FOUND
- server/cmd/bot/main_test.go: FOUND
- Commits 744be70, ffc013e, 9147a60: FOUND in HEAD history
