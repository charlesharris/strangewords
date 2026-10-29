---
phase: quick-261029-l7k
plan: 01
subsystem: ui
tags: [swiftui, accessibility, wcag, contrast, swift-testing, themes]

requires:
  - phase: quick-261029-k47
    provides: scenery selector and the three themes (nature, sci-fi, fantasy) that the suite crosses with three times of day
provides:
  - ContrastTests, an automated WCAG AA suite over 23 text surfaces x 9 palettes (207 printed CONTRAST| cells)
  - Legibility, the shared onAccent 0.6 backing (always-on and sky-flag-gated)
  - Palette.backsSkyText, true only for sci-fi morning and afternoon
  - six darkened day-palette secondary colors
affects: [theme work, any copy or palette change, Phase 6 two-poem trade UI (new text surfaces must be added to the inventory)]

plan_head_before: eb0375c1080d2efa020a18883c43b026fba097d9
plan_head_after: 2a297f3ef93e13a24fa3b330e7f80ac37a702027

actuals:
  tokens: 8800
  tasks: 3
  commits: 4

tech-stack:
  added: []
  patterns:
    - "Contrast is measured, not eyeballed: ContrastTests resolves palettes from Themes.all and models the real backdrop set each surface renders over"
    - "A legibility backing is earned: Palette.backsSkyText may be true only where no text color can reach 4.5:1 (test-enforced)"

key-files:
  created:
    - ios/StrangewordsTests/ContrastTests.swift
    - ios/Strangewords/Design/Legibility.swift
  modified:
    - ios/Strangewords/Design/Theme.swift
    - ios/Strangewords/Design/Themes/SciFiTheme.swift
    - ios/Strangewords/Design/Themes/FantasyTheme.swift
    - ios/Strangewords/Features/Threshold/ThresholdView.swift
    - ios/Strangewords/Features/Waiting/WaitingView.swift
    - ios/Strangewords/Features/Compose/ComposeView.swift
    - ios/Strangewords/Features/Compose/StepAway.swift
    - ios/Strangewords/Features/Dissolved/DissolvedView.swift

key-decisions:
  - "Reuse the existing onAccent 0.6 frosted-backing idiom (robot-poet chip, settings gear and cards) for the cells where text color alone provably cannot pass, rather than touching any locked scene color"
  - "Day secondary text is darkened by a uniform RGB scale (hue kept) to the largest scale that passes; night secondary is left alone and the 0.7/0.8 dimming is removed instead"
  - "The submit error renders in ink, not accent; accent stays a scene and tint color and is pinned"

patterns-established:
  - "Pinned scene colors: sceneColorsAreUnchanged fails if a text fix leaks into any background or scene-borrowed color"
  - "New text surface = new row in ContrastTests.inventory"

requirements-completed: [QUICK-261029-l7k]

coverage:
  - id: D1
    description: "Automated WCAG model over the nine real palettes: 23 surfaces, 207 cells, each with a ratio, threshold and best-any-color feasibility"
    requirement: QUICK-261029-l7k
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/ContrastTests.swift#contrastMatrix"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/ContrastTests.swift#wcagMathMatchesReferenceValues"
        status: pass
    human_judgment: false
  - id: D2
    description: "Every non-poem text surface meets WCAG AA in all nine palettes; poem text holds 3:1"
    requirement: QUICK-261029-l7k
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/ContrastTests.swift#nonPoemTextMeetsAA"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/ContrastTests.swift#poemTextNeverFailsBadly"
        status: pass
      - kind: unit
        ref: "ios/StrangewordsTests/ContrastTests.swift#everySurfaceSitsWhereSomeTextColorCanPass"
        status: pass
    human_judgment: false
  - id: D3
    description: "Scenes render exactly as before: every background and scene-borrowed color is pinned"
    requirement: QUICK-261029-l7k
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/ContrastTests.swift#sceneColorsAreUnchanged"
        status: pass
    human_judgment: false
  - id: D4
    description: "Day secondary stays the quieter voice (lighter than ink by at least 1.3:1; night stays darker)"
    requirement: QUICK-261029-l7k
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/ContrastTests.swift#textHierarchyIsPreserved"
        status: pass
    human_judgment: false
  - id: D5
    description: "The sky backing is applied only where no text color can pass (sci-fi morning and afternoon)"
    requirement: QUICK-261029-l7k
    verification:
      - kind: unit
        ref: "ios/StrangewordsTests/ContrastTests.swift#skyBackingOnlyWhereNoTextColorCanPass"
        status: pass
    human_judgment: false
  - id: D6
    description: "The new frosted backings read as quiet pills rather than buttons, and darker day secondary still reads as quieter than ink"
    verification: []
    human_judgment: true
    rationale: "Visual taste across nine palettes; the milestone is automated-only, so the check is deferred (see Open item)"

duration: 28min
completed: 2026-10-29
status: complete
---

# Phase quick-261029-l7k Plan 01: Non-poem text contrast Summary

**WCAG AA contrast suite (23 surfaces x 9 palettes, 207 printed cells) that took 87 failing cells to zero by darkening six day-palette secondary colors, removing secondary dimming, and putting the existing onAccent 0.6 backing behind lower-screen copy and sci-fi day sky copy, with every scene color pinned unchanged**

## Performance

- **Duration:** about 28 min (start time was not captured at launch; estimated from the first file written)
- **Started:** approx. 2026-10-29T20:35:00Z
- **Completed:** 2026-10-29T21:05:00Z
- **Tasks:** 3 (one tracer, two auto), 4 commits
- **Files modified:** 10 (2 created, 8 modified)

## Accomplishments

- `ContrastTests` (8 Swift Testing cases) models the backdrop set each of 23 text surfaces renders over: sky bands built with the scene's own `Color.mix`, ground silhouettes, the phase dusk, and the onAccent backings, then composites in sRGB and prints 207 `CONTRAST|` lines. It reads palettes from `Themes.all`, constructs no AppModel, Backend or UserDefaults, and has no wall-clock waits.
- At HEAD styling 87 of 207 cells failed (44 were infeasible for any text color). After the change all 207 pass, none is infeasible, and the tightest margin is +0.01 over its threshold.
- Scenes are pixel-identical: `sceneColorsAreUnchanged` pins skyTop, skyBottom, sun, far, near, accent, onAccent and isDark in all 9 palettes, ink in all 9, and secondary in the 3 night palettes.
- Full `scripts/test-ios.sh` run: PASS, 125 passed, 0 failed, 1 skipped (126 total). The 117 baseline plus the 8 new cases.

## Task Commits

1. **Task 1: Contrast harness end to end, then the sci-fi sky slice** (tracer, tdd)
   - `a6962d3` test: measure text contrast across all nine palettes (RED: the AA, poem and feasibility tests fail; 207 lines)
   - `86dc1f5` feat: back sci-fi day sky text where no text color can pass
2. **Task 2: Back the lower-screen copy, back remaining sky copy where flagged, floor dimmed secondary, ink submit error** - `daf7478` (feat)
3. **Task 3: Darken the six day secondary colors until every cell passes** - `2a297f3` (fix)

**Plan metadata:** not committed here; the batch coordinator commits the docs.

The tracer gate re-ran as a RED/GREEN end-to-end proof: the before run failed exactly the three expected tests, and the post-slice run kept the same three failing while `poem.line` and `threshold.title` passed in all 9 palettes (18 PASS records, no INFEASIBLE `threshold.*` or `poem.line` cell).

## Files Created/Modified

- `ios/StrangewordsTests/ContrastTests.swift` - WCAG math, the backdrop model, 23-surface inventory, pins, 8 test cases, printed matrix
- `ios/Strangewords/Design/Legibility.swift` - `Legibility.backingOpacity` (0.6, [TUNABLE]), `legibilityBacking(_:)` and `skyTextBacking(_:)`
- `ios/Strangewords/Design/Theme.swift` - `Palette.backsSkyText` (defaults false), `PoemLine` adopts the sky backing, nature day secondary darkened
- `ios/Strangewords/Design/Themes/SciFiTheme.swift` - `backsSkyText: true` on morning and afternoon; day secondary darkened
- `ios/Strangewords/Design/Themes/FantasyTheme.swift` - day secondary darkened; nothing else changed
- `ios/Strangewords/Features/Threshold/ThresholdView.swift` - title and tagline block adopt the sky backing
- `ios/Strangewords/Features/Waiting/WaitingView.swift` - status and robot-poet line adopt the sky backing and lose their dimming; "step back out" gets the always-on backing
- `ios/Strangewords/Features/Compose/ComposeView.swift` - draft, syllable hint (not its blank placeholder), submit error (now ink) and their-turn block get the always-on backing; hint and their-turn dimming removed
- `ios/Strangewords/Features/Compose/StepAway.swift` - label gets the always-on backing inside the unchanged 44pt hit frame
- `ios/Strangewords/Features/Dissolved/DissolvedView.swift` - keepsake block and farewell adopt the sky backing

## Palette changes

Secondary colors were scaled uniformly in RGB (hue kept). The scale f is the largest in 1/255 steps for which every surface using secondary in that palette passes. The search ran on a scratch mirror of the model (not committed) and the result was confirmed by the Swift suite.

| Palette | Old | New | f |
|---|---|---|---|
| nature morning | 927A70 | 6B5952 | 0.7333 |
| nature afternoon | 8E837C | 635B57 | 0.6980 |
| sci-fi morning | 5E6E86 | 343C4A | 0.5490 |
| sci-fi afternoon | 5C7A8C | 394B56 | 0.6157 |
| fantasy morning | 7B6E92 | 453E52 | 0.5647 |
| fantasy afternoon | 7E7596 | 4F495E | 0.6275 |

Ink, all night values and all background/scene values unchanged (pinned). Each new secondary stays lighter than ink by at least 1.35:1 (test requires 1.3). The planning advisory for fantasy morning was 473F54; the Swift model needed 453E52.

## Text-color infeasible palettes (why the backings exist)

"Best" is the highest minimum contrast any gray text could reach over the unbacked backdrop. A cell is infeasible when best is below its threshold, so no text-color choice could fix it and the scene colors are locked.

- **Sky copy** (normal text needs 4.5, large 3.0): sci-fi morning best 2.17 and sci-fi afternoon best 2.96 (the dawn sky and near-black skyline share the centered copy column). Every other palette's sky best is 9.59 or more. So `backsSkyText` is true for exactly these two palettes, and `skyBackingOnlyWhereNoTextColorCanPass` enforces it.
- **Lower screen** (draft, hint, error, their-turn lines, exits, over ground and dusk): sci-fi morning best 2.56, sci-fi afternoon 2.74, fantasy morning 3.34, fantasy afternoon 3.39, all under 4.5. So lower-screen copy sits on the backing in every palette, which keeps the rule uniform instead of palette-by-palette.

In total 44 of the 207 cells were infeasible at HEAD styling, all in the sci-fi and fantasy day palettes.

## Model limits

Reference device iPhone 17 (402x874pt); smaller screens shift centered copy up by 2-5% and can graze one more sky band. Point decorations (stars, motes, clouds, blossoms, lit windows, antennas, beacons, celestial discs and glows) are excluded. The Bayer-dithered sky is treated per cell, which is strict. The radial vignette is assumed clear for centered copy. Dissolution text, disabled ritual labels, the system confirmation dialog and the dev chips are excluded. Dynamic Type only enlarges text, which only relaxes the threshold. The test measures the declared point sizes and the opacity and backing the inventory states; it does not read the view tree, so a view that drifts from its inventory row is not caught (the inventory is the contract, adopted per view in this plan).

## Failing-cell digest (every cell that failed at HEAD, before -> after)

- **threshold.title** (2): sci-fi morning 1.02 -> 6.20; sci-fi afternoon 1.94 -> 7.07
- **threshold.tagline** (6): nature morning 3.15 -> 5.19; nature afternoon 2.85 -> 5.13; sci-fi morning 1.09 -> 4.52; sci-fi afternoon 1.28 -> 4.65; fantasy morning 2.14 -> 4.64; fantasy afternoon 2.48 -> 4.94
- **waiting.status** (6): nature morning 3.15 -> 5.19; nature afternoon 2.85 -> 5.13; sci-fi morning 1.09 -> 4.52; sci-fi afternoon 1.28 -> 4.65; fantasy morning 2.14 -> 4.64; fantasy afternoon 2.48 -> 4.94
- **waiting.botLine** (9): nature morning 2.41 -> 5.19; nature afternoon 2.24 -> 5.13; nature night 3.56 -> 4.64; sci-fi morning 1.08 -> 4.52; sci-fi afternoon 1.22 -> 4.65; sci-fi night 3.46 -> 4.68; fantasy morning 1.81 -> 4.64; fantasy afternoon 2.03 -> 4.94; fantasy night 4.21 -> 5.66
- **dissolved.keepsakeLead** (6): nature morning 3.04 -> 5.02; nature afternoon 2.76 -> 4.96; sci-fi morning 1.07 -> 4.53; sci-fi afternoon 1.25 -> 4.63; fantasy morning 2.07 -> 4.51; fantasy afternoon 2.41 -> 4.79
- **dissolved.keepsakeName** (2): sci-fi morning 1.02 -> 6.21; sci-fi afternoon 1.91 -> 7.04
- **dissolved.keepsakeKind** (6): nature morning 3.04 -> 5.02; nature afternoon 2.76 -> 4.96; sci-fi morning 1.07 -> 4.53; sci-fi afternoon 1.25 -> 4.63; fantasy morning 2.07 -> 4.51; fantasy afternoon 2.41 -> 4.79
- **dissolved.farewell** (2): sci-fi morning 1.02 -> 6.21; sci-fi afternoon 1.91 -> 7.04
- **poem.line** (2): sci-fi morning 1.02 -> 6.21; sci-fi afternoon 1.92 -> 7.05
- **compose.draft** (4): sci-fi morning 1.03 -> 6.23; sci-fi afternoon 1.80 -> 6.93; fantasy morning 2.18 -> 7.16; fantasy afternoon 1.99 -> 6.48
- **compose.syllableHint** (9): nature morning 1.29 -> 4.56; nature afternoon 1.18 -> 4.53; nature night 3.27 -> 5.55; sci-fi morning 1.01 -> 4.54; sci-fi afternoon 1.08 -> 4.56; sci-fi night 2.99 -> 4.91; fantasy morning 1.17 -> 5.30; fantasy afternoon 1.18 -> 4.52; fantasy night 3.78 -> 6.87
- **compose.submitError** (6): nature morning 1.05 -> 7.25; nature afternoon 1.09 -> 6.27; sci-fi morning 1.04 -> 6.23; sci-fi afternoon 1.08 -> 6.93; fantasy morning 1.05 -> 7.16; fantasy afternoon 1.06 -> 6.48
- **compose.theirTurnPrimary** (6): nature morning 1.44 -> 4.56; nature afternoon 1.27 -> 4.53; sci-fi morning 1.02 -> 4.54; sci-fi afternoon 1.12 -> 4.56; fantasy morning 1.26 -> 5.30; fantasy afternoon 1.27 -> 4.52
- **compose.theirTurnSecondary** (9): nature morning 1.34 -> 4.56; nature afternoon 1.21 -> 4.53; nature night 3.79 -> 5.55; sci-fi morning 1.01 -> 4.54; sci-fi afternoon 1.09 -> 4.56; sci-fi night 3.52 -> 4.91; fantasy morning 1.20 -> 5.30; fantasy afternoon 1.21 -> 4.52; fantasy night 4.46 -> 6.87
- **compose.stepAway** (6): nature morning 1.44 -> 4.56; nature afternoon 1.27 -> 4.53; sci-fi morning 1.02 -> 4.54; sci-fi afternoon 1.12 -> 4.56; fantasy morning 1.26 -> 5.30; fantasy afternoon 1.27 -> 4.52
- **waiting.stepBackOut** (6): nature morning 1.69 -> 4.80; nature afternoon 1.49 -> 4.76; sci-fi morning 1.09 -> 4.52; sci-fi afternoon 1.28 -> 4.65; fantasy morning 1.23 -> 5.44; fantasy afternoon 1.31 -> 4.65

## Contrast before/after

Before is HEAD styling (`build/verify/quick-261029-l7k-before/contrast.txt`); after is final (`build/verify/quick-261029-l7k-t3/contrast.txt`). Both are gitignored evidence under `build/verify/`. Role shows `before->after` when it changed (the submit error moved from accent to ink).

| theme | tod | surface | role | threshold | before | after | before verdict -> after verdict |
|---|---|---|---|---|---|---|---|
| nature | morning | threshold.title | ink | 3.00 | 8.25 | 8.25 | PASS -> PASS |
| nature | morning | threshold.tagline | secondary | 4.50 | 3.15 | 5.19 | FAIL -> PASS |
| nature | morning | waiting.status | secondary | 4.50 | 3.15 | 5.19 | FAIL -> PASS |
| nature | morning | waiting.botLine | secondary | 4.50 | 2.41 | 5.19 | FAIL -> PASS |
| nature | morning | dissolved.keepsakeLead | secondary | 4.50 | 3.04 | 5.02 | FAIL -> PASS |
| nature | morning | dissolved.keepsakeName | ink | 3.00 | 7.97 | 7.97 | PASS -> PASS |
| nature | morning | dissolved.keepsakeKind | secondary | 4.50 | 3.04 | 5.02 | FAIL -> PASS |
| nature | morning | dissolved.farewell | ink | 4.50 | 7.97 | 7.97 | PASS -> PASS |
| nature | morning | poem.line | ink | 3.00 | 8.06 | 8.06 | PASS -> PASS |
| nature | morning | compose.draft | ink | 3.00 | 3.77 | 7.25 | PASS -> PASS |
| nature | morning | compose.syllableHint | secondary | 4.50 | 1.29 | 4.56 | FAIL -> PASS |
| nature | morning | compose.submitError | accent->ink | 4.50 | 1.05 | 7.25 | FAIL -> PASS |
| nature | morning | compose.theirTurnPrimary | secondary | 4.50 | 1.44 | 4.56 | FAIL -> PASS |
| nature | morning | compose.theirTurnSecondary | secondary | 4.50 | 1.34 | 4.56 | FAIL -> PASS |
| nature | morning | compose.stepAway | secondary | 4.50 | 1.44 | 4.56 | FAIL -> PASS |
| nature | morning | waiting.stepBackOut | secondary | 4.50 | 1.69 | 4.80 | FAIL -> PASS |
| nature | morning | ritual.label | ink | 4.50 | 8.63 | 8.63 | PASS -> PASS |
| nature | morning | presence.chip | ink | 4.50 | 7.63 | 7.63 | PASS -> PASS |
| nature | morning | threshold.gear | ink | 3.00 | 4.68 | 4.68 | PASS -> PASS |
| nature | morning | settings.title | ink | 4.50 | 9.32 | 9.32 | PASS -> PASS |
| nature | morning | settings.close | ink | 4.50 | 9.32 | 9.32 | PASS -> PASS |
| nature | morning | settings.rowText | ink | 4.50 | 10.02 | 10.02 | PASS -> PASS |
| nature | morning | settings.helper | ink | 4.50 | 6.48 | 6.48 | PASS -> PASS |
| nature | afternoon | threshold.title | ink | 3.00 | 7.11 | 7.11 | PASS -> PASS |
| nature | afternoon | threshold.tagline | secondary | 4.50 | 2.85 | 5.13 | FAIL -> PASS |
| nature | afternoon | waiting.status | secondary | 4.50 | 2.85 | 5.13 | FAIL -> PASS |
| nature | afternoon | waiting.botLine | secondary | 4.50 | 2.24 | 5.13 | FAIL -> PASS |
| nature | afternoon | dissolved.keepsakeLead | secondary | 4.50 | 2.76 | 4.96 | FAIL -> PASS |
| nature | afternoon | dissolved.keepsakeName | ink | 3.00 | 6.87 | 6.87 | PASS -> PASS |
| nature | afternoon | dissolved.keepsakeKind | secondary | 4.50 | 2.76 | 4.96 | FAIL -> PASS |
| nature | afternoon | dissolved.farewell | ink | 4.50 | 6.87 | 6.87 | PASS -> PASS |
| nature | afternoon | poem.line | ink | 3.00 | 6.94 | 6.94 | PASS -> PASS |
| nature | afternoon | compose.draft | ink | 3.00 | 3.17 | 6.27 | PASS -> PASS |
| nature | afternoon | compose.syllableHint | secondary | 4.50 | 1.18 | 4.53 | FAIL -> PASS |
| nature | afternoon | compose.submitError | accent->ink | 4.50 | 1.09 | 6.27 | FAIL -> PASS |
| nature | afternoon | compose.theirTurnPrimary | secondary | 4.50 | 1.27 | 4.53 | FAIL -> PASS |
| nature | afternoon | compose.theirTurnSecondary | secondary | 4.50 | 1.21 | 4.53 | FAIL -> PASS |
| nature | afternoon | compose.stepAway | secondary | 4.50 | 1.27 | 4.53 | FAIL -> PASS |
| nature | afternoon | waiting.stepBackOut | secondary | 4.50 | 1.49 | 4.76 | FAIL -> PASS |
| nature | afternoon | ritual.label | ink | 4.50 | 7.53 | 7.53 | PASS -> PASS |
| nature | afternoon | presence.chip | ink | 4.50 | 6.60 | 6.60 | PASS -> PASS |
| nature | afternoon | threshold.gear | ink | 3.00 | 4.18 | 4.18 | PASS -> PASS |
| nature | afternoon | settings.title | ink | 4.50 | 8.02 | 8.02 | PASS -> PASS |
| nature | afternoon | settings.close | ink | 4.50 | 8.02 | 8.02 | PASS -> PASS |
| nature | afternoon | settings.rowText | ink | 4.50 | 8.71 | 8.71 | PASS -> PASS |
| nature | afternoon | settings.helper | ink | 4.50 | 5.76 | 5.76 | PASS -> PASS |
| nature | night | threshold.title | ink | 3.00 | 9.26 | 9.26 | PASS -> PASS |
| nature | night | threshold.tagline | secondary | 4.50 | 4.64 | 4.64 | PASS -> PASS |
| nature | night | waiting.status | secondary | 4.50 | 4.64 | 4.64 | PASS -> PASS |
| nature | night | waiting.botLine | secondary | 4.50 | 3.56 | 4.64 | FAIL -> PASS |
| nature | night | dissolved.keepsakeLead | secondary | 4.50 | 4.71 | 4.71 | PASS -> PASS |
| nature | night | dissolved.keepsakeName | ink | 3.00 | 9.39 | 9.39 | PASS -> PASS |
| nature | night | dissolved.keepsakeKind | secondary | 4.50 | 4.71 | 4.71 | PASS -> PASS |
| nature | night | dissolved.farewell | ink | 4.50 | 9.39 | 9.39 | PASS -> PASS |
| nature | night | poem.line | ink | 3.00 | 9.35 | 9.35 | PASS -> PASS |
| nature | night | compose.draft | ink | 3.00 | 10.01 | 11.07 | PASS -> PASS |
| nature | night | compose.syllableHint | secondary | 4.50 | 3.27 | 5.55 | FAIL -> PASS |
| nature | night | compose.submitError | accent->ink | 4.50 | 6.39 | 11.07 | PASS -> PASS |
| nature | night | compose.theirTurnPrimary | secondary | 4.50 | 5.02 | 5.55 | PASS -> PASS |
| nature | night | compose.theirTurnSecondary | secondary | 4.50 | 3.79 | 5.55 | FAIL -> PASS |
| nature | night | compose.stepAway | secondary | 4.50 | 5.02 | 5.55 | PASS -> PASS |
| nature | night | waiting.stepBackOut | secondary | 4.50 | 4.64 | 5.39 | PASS -> PASS |
| nature | night | ritual.label | ink | 4.50 | 11.95 | 11.95 | PASS -> PASS |
| nature | night | presence.chip | ink | 4.50 | 10.75 | 10.75 | PASS -> PASS |
| nature | night | threshold.gear | ink | 3.00 | 7.47 | 7.47 | PASS -> PASS |
| nature | night | settings.title | ink | 4.50 | 9.26 | 9.26 | PASS -> PASS |
| nature | night | settings.close | ink | 4.50 | 9.26 | 9.26 | PASS -> PASS |
| nature | night | settings.rowText | ink | 4.50 | 10.75 | 10.75 | PASS -> PASS |
| nature | night | settings.helper | ink | 4.50 | 8.22 | 8.22 | PASS -> PASS |
| sci-fi | morning | threshold.title | ink | 3.00 | 1.02 | 6.20 | FAIL -> PASS |
| sci-fi | morning | threshold.tagline | secondary | 4.50 | 1.09 | 4.52 | FAIL -> PASS |
| sci-fi | morning | waiting.status | secondary | 4.50 | 1.09 | 4.52 | FAIL -> PASS |
| sci-fi | morning | waiting.botLine | secondary | 4.50 | 1.08 | 4.52 | FAIL -> PASS |
| sci-fi | morning | dissolved.keepsakeLead | secondary | 4.50 | 1.07 | 4.53 | FAIL -> PASS |
| sci-fi | morning | dissolved.keepsakeName | ink | 3.00 | 1.02 | 6.21 | FAIL -> PASS |
| sci-fi | morning | dissolved.keepsakeKind | secondary | 4.50 | 1.07 | 4.53 | FAIL -> PASS |
| sci-fi | morning | dissolved.farewell | ink | 4.50 | 1.02 | 6.21 | FAIL -> PASS |
| sci-fi | morning | poem.line | ink | 3.00 | 1.02 | 6.21 | FAIL -> PASS |
| sci-fi | morning | compose.draft | ink | 3.00 | 1.03 | 6.23 | FAIL -> PASS |
| sci-fi | morning | compose.syllableHint | secondary | 4.50 | 1.01 | 4.54 | FAIL -> PASS |
| sci-fi | morning | compose.submitError | accent->ink | 4.50 | 1.04 | 6.23 | FAIL -> PASS |
| sci-fi | morning | compose.theirTurnPrimary | secondary | 4.50 | 1.02 | 4.54 | FAIL -> PASS |
| sci-fi | morning | compose.theirTurnSecondary | secondary | 4.50 | 1.01 | 4.54 | FAIL -> PASS |
| sci-fi | morning | compose.stepAway | secondary | 4.50 | 1.02 | 4.54 | FAIL -> PASS |
| sci-fi | morning | waiting.stepBackOut | secondary | 4.50 | 1.09 | 4.52 | FAIL -> PASS |
| sci-fi | morning | ritual.label | ink | 4.50 | 10.97 | 10.97 | PASS -> PASS |
| sci-fi | morning | presence.chip | ink | 4.50 | 6.20 | 6.20 | PASS -> PASS |
| sci-fi | morning | threshold.gear | ink | 3.00 | 4.31 | 4.31 | PASS -> PASS |
| sci-fi | morning | settings.title | ink | 4.50 | 7.01 | 7.01 | PASS -> PASS |
| sci-fi | morning | settings.close | ink | 4.50 | 7.01 | 7.01 | PASS -> PASS |
| sci-fi | morning | settings.rowText | ink | 4.50 | 10.99 | 10.99 | PASS -> PASS |
| sci-fi | morning | settings.helper | ink | 4.50 | 7.50 | 7.50 | PASS -> PASS |
| sci-fi | afternoon | threshold.title | ink | 3.00 | 1.94 | 7.07 | FAIL -> PASS |
| sci-fi | afternoon | threshold.tagline | secondary | 4.50 | 1.28 | 4.65 | FAIL -> PASS |
| sci-fi | afternoon | waiting.status | secondary | 4.50 | 1.28 | 4.65 | FAIL -> PASS |
| sci-fi | afternoon | waiting.botLine | secondary | 4.50 | 1.22 | 4.65 | FAIL -> PASS |
| sci-fi | afternoon | dissolved.keepsakeLead | secondary | 4.50 | 1.25 | 4.63 | FAIL -> PASS |
| sci-fi | afternoon | dissolved.keepsakeName | ink | 3.00 | 1.91 | 7.04 | FAIL -> PASS |
| sci-fi | afternoon | dissolved.keepsakeKind | secondary | 4.50 | 1.25 | 4.63 | FAIL -> PASS |
| sci-fi | afternoon | dissolved.farewell | ink | 4.50 | 1.91 | 7.04 | FAIL -> PASS |
| sci-fi | afternoon | poem.line | ink | 3.00 | 1.92 | 7.05 | FAIL -> PASS |
| sci-fi | afternoon | compose.draft | ink | 3.00 | 1.80 | 6.93 | FAIL -> PASS |
| sci-fi | afternoon | compose.syllableHint | secondary | 4.50 | 1.08 | 4.56 | FAIL -> PASS |
| sci-fi | afternoon | compose.submitError | accent->ink | 4.50 | 1.08 | 6.93 | FAIL -> PASS |
| sci-fi | afternoon | compose.theirTurnPrimary | secondary | 4.50 | 1.12 | 4.56 | FAIL -> PASS |
| sci-fi | afternoon | compose.theirTurnSecondary | secondary | 4.50 | 1.09 | 4.56 | FAIL -> PASS |
| sci-fi | afternoon | compose.stepAway | secondary | 4.50 | 1.12 | 4.56 | FAIL -> PASS |
| sci-fi | afternoon | waiting.stepBackOut | secondary | 4.50 | 1.28 | 4.65 | FAIL -> PASS |
| sci-fi | afternoon | ritual.label | ink | 4.50 | 10.39 | 10.39 | PASS -> PASS |
| sci-fi | afternoon | presence.chip | ink | 4.50 | 7.07 | 7.07 | PASS -> PASS |
| sci-fi | afternoon | threshold.gear | ink | 3.00 | 4.65 | 4.65 | PASS -> PASS |
| sci-fi | afternoon | settings.title | ink | 4.50 | 10.46 | 10.46 | PASS -> PASS |
| sci-fi | afternoon | settings.close | ink | 4.50 | 10.46 | 10.46 | PASS -> PASS |
| sci-fi | afternoon | settings.rowText | ink | 4.50 | 12.12 | 12.12 | PASS -> PASS |
| sci-fi | afternoon | settings.helper | ink | 4.50 | 7.84 | 7.84 | PASS -> PASS |
| sci-fi | night | threshold.title | ink | 3.00 | 13.52 | 13.52 | PASS -> PASS |
| sci-fi | night | threshold.tagline | secondary | 4.50 | 4.68 | 4.68 | PASS -> PASS |
| sci-fi | night | waiting.status | secondary | 4.50 | 4.68 | 4.68 | PASS -> PASS |
| sci-fi | night | waiting.botLine | secondary | 4.50 | 3.46 | 4.68 | FAIL -> PASS |
| sci-fi | night | dissolved.keepsakeLead | secondary | 4.50 | 4.70 | 4.70 | PASS -> PASS |
| sci-fi | night | dissolved.keepsakeName | ink | 3.00 | 13.57 | 13.57 | PASS -> PASS |
| sci-fi | night | dissolved.keepsakeKind | secondary | 4.50 | 4.70 | 4.70 | PASS -> PASS |
| sci-fi | night | dissolved.farewell | ink | 4.50 | 13.57 | 13.57 | PASS -> PASS |
| sci-fi | night | poem.line | ink | 3.00 | 13.56 | 13.56 | PASS -> PASS |
| sci-fi | night | compose.draft | ink | 3.00 | 13.81 | 14.17 | PASS -> PASS |
| sci-fi | night | compose.syllableHint | secondary | 4.50 | 2.99 | 4.91 | FAIL -> PASS |
| sci-fi | night | compose.submitError | accent->ink | 4.50 | 11.28 | 14.17 | PASS -> PASS |
| sci-fi | night | compose.theirTurnPrimary | secondary | 4.50 | 4.78 | 4.91 | PASS -> PASS |
| sci-fi | night | compose.theirTurnSecondary | secondary | 4.50 | 3.52 | 4.91 | FAIL -> PASS |
| sci-fi | night | compose.stepAway | secondary | 4.50 | 4.78 | 4.91 | PASS -> PASS |
| sci-fi | night | waiting.stepBackOut | secondary | 4.50 | 4.68 | 4.87 | PASS -> PASS |
| sci-fi | night | ritual.label | ink | 4.50 | 14.46 | 14.46 | PASS -> PASS |
| sci-fi | night | presence.chip | ink | 4.50 | 14.06 | 14.06 | PASS -> PASS |
| sci-fi | night | threshold.gear | ink | 3.00 | 9.31 | 9.31 | PASS -> PASS |
| sci-fi | night | settings.title | ink | 4.50 | 13.53 | 13.53 | PASS -> PASS |
| sci-fi | night | settings.close | ink | 4.50 | 13.53 | 13.53 | PASS -> PASS |
| sci-fi | night | settings.rowText | ink | 4.50 | 14.11 | 14.11 | PASS -> PASS |
| sci-fi | night | settings.helper | ink | 4.50 | 10.40 | 10.40 | PASS -> PASS |
| fantasy | morning | threshold.title | ink | 3.00 | 6.28 | 6.28 | PASS -> PASS |
| fantasy | morning | threshold.tagline | secondary | 4.50 | 2.14 | 4.64 | FAIL -> PASS |
| fantasy | morning | waiting.status | secondary | 4.50 | 2.14 | 4.64 | FAIL -> PASS |
| fantasy | morning | waiting.botLine | secondary | 4.50 | 1.81 | 4.64 | FAIL -> PASS |
| fantasy | morning | dissolved.keepsakeLead | secondary | 4.50 | 2.07 | 4.51 | FAIL -> PASS |
| fantasy | morning | dissolved.keepsakeName | ink | 3.00 | 6.09 | 6.09 | PASS -> PASS |
| fantasy | morning | dissolved.keepsakeKind | secondary | 4.50 | 2.07 | 4.51 | FAIL -> PASS |
| fantasy | morning | dissolved.farewell | ink | 4.50 | 6.09 | 6.09 | PASS -> PASS |
| fantasy | morning | poem.line | ink | 3.00 | 6.15 | 6.15 | PASS -> PASS |
| fantasy | morning | compose.draft | ink | 3.00 | 2.18 | 7.16 | FAIL -> PASS |
| fantasy | morning | compose.syllableHint | secondary | 4.50 | 1.17 | 5.30 | FAIL -> PASS |
| fantasy | morning | compose.submitError | accent->ink | 4.50 | 1.05 | 7.16 | FAIL -> PASS |
| fantasy | morning | compose.theirTurnPrimary | secondary | 4.50 | 1.26 | 5.30 | FAIL -> PASS |
| fantasy | morning | compose.theirTurnSecondary | secondary | 4.50 | 1.20 | 5.30 | FAIL -> PASS |
| fantasy | morning | compose.stepAway | secondary | 4.50 | 1.26 | 5.30 | FAIL -> PASS |
| fantasy | morning | waiting.stepBackOut | secondary | 4.50 | 1.23 | 5.44 | FAIL -> PASS |
| fantasy | morning | ritual.label | ink | 4.50 | 10.22 | 10.22 | PASS -> PASS |
| fantasy | morning | presence.chip | ink | 4.50 | 7.35 | 7.35 | PASS -> PASS |
| fantasy | morning | threshold.gear | ink | 3.00 | 4.76 | 4.76 | PASS -> PASS |
| fantasy | morning | settings.title | ink | 4.50 | 10.33 | 10.33 | PASS -> PASS |
| fantasy | morning | settings.close | ink | 4.50 | 10.33 | 10.33 | PASS -> PASS |
| fantasy | morning | settings.rowText | ink | 4.50 | 11.86 | 11.86 | PASS -> PASS |
| fantasy | morning | settings.helper | ink | 4.50 | 7.69 | 7.69 | PASS -> PASS |
| fantasy | afternoon | threshold.title | ink | 3.00 | 7.08 | 7.08 | PASS -> PASS |
| fantasy | afternoon | threshold.tagline | secondary | 4.50 | 2.48 | 4.94 | FAIL -> PASS |
| fantasy | afternoon | waiting.status | secondary | 4.50 | 2.48 | 4.94 | FAIL -> PASS |
| fantasy | afternoon | waiting.botLine | secondary | 4.50 | 2.03 | 4.94 | FAIL -> PASS |
| fantasy | afternoon | dissolved.keepsakeLead | secondary | 4.50 | 2.41 | 4.79 | FAIL -> PASS |
| fantasy | afternoon | dissolved.keepsakeName | ink | 3.00 | 6.86 | 6.86 | PASS -> PASS |
| fantasy | afternoon | dissolved.keepsakeKind | secondary | 4.50 | 2.41 | 4.79 | FAIL -> PASS |
| fantasy | afternoon | dissolved.farewell | ink | 4.50 | 6.86 | 6.86 | PASS -> PASS |
| fantasy | afternoon | poem.line | ink | 3.00 | 6.93 | 6.93 | PASS -> PASS |
| fantasy | afternoon | compose.draft | ink | 3.00 | 1.99 | 6.48 | FAIL -> PASS |
| fantasy | afternoon | compose.syllableHint | secondary | 4.50 | 1.18 | 4.52 | FAIL -> PASS |
| fantasy | afternoon | compose.submitError | accent->ink | 4.50 | 1.06 | 6.48 | FAIL -> PASS |
| fantasy | afternoon | compose.theirTurnPrimary | secondary | 4.50 | 1.27 | 4.52 | FAIL -> PASS |
| fantasy | afternoon | compose.theirTurnSecondary | secondary | 4.50 | 1.21 | 4.52 | FAIL -> PASS |
| fantasy | afternoon | compose.stepAway | secondary | 4.50 | 1.27 | 4.52 | FAIL -> PASS |
| fantasy | afternoon | waiting.stepBackOut | secondary | 4.50 | 1.31 | 4.65 | FAIL -> PASS |
| fantasy | afternoon | ritual.label | ink | 4.50 | 9.23 | 9.23 | PASS -> PASS |
| fantasy | afternoon | presence.chip | ink | 4.50 | 6.66 | 6.66 | PASS -> PASS |
| fantasy | afternoon | threshold.gear | ink | 3.00 | 4.35 | 4.35 | PASS -> PASS |
| fantasy | afternoon | settings.title | ink | 4.50 | 10.02 | 10.02 | PASS -> PASS |
| fantasy | afternoon | settings.close | ink | 4.50 | 10.02 | 10.02 | PASS -> PASS |
| fantasy | afternoon | settings.rowText | ink | 4.50 | 11.02 | 11.02 | PASS -> PASS |
| fantasy | afternoon | settings.helper | ink | 4.50 | 7.12 | 7.12 | PASS -> PASS |
| fantasy | night | threshold.title | ink | 3.00 | 10.21 | 10.21 | PASS -> PASS |
| fantasy | night | threshold.tagline | secondary | 4.50 | 5.66 | 5.66 | PASS -> PASS |
| fantasy | night | waiting.status | secondary | 4.50 | 5.66 | 5.66 | PASS -> PASS |
| fantasy | night | waiting.botLine | secondary | 4.50 | 4.21 | 5.66 | FAIL -> PASS |
| fantasy | night | dissolved.keepsakeLead | secondary | 4.50 | 5.73 | 5.73 | PASS -> PASS |
| fantasy | night | dissolved.keepsakeName | ink | 3.00 | 10.35 | 10.35 | PASS -> PASS |
| fantasy | night | dissolved.keepsakeKind | secondary | 4.50 | 5.73 | 5.73 | PASS -> PASS |
| fantasy | night | dissolved.farewell | ink | 4.50 | 10.35 | 10.35 | PASS -> PASS |
| fantasy | night | poem.line | ink | 3.00 | 10.31 | 10.31 | PASS -> PASS |
| fantasy | night | compose.draft | ink | 3.00 | 10.95 | 12.41 | PASS -> PASS |
| fantasy | night | compose.syllableHint | secondary | 4.50 | 3.78 | 6.87 | FAIL -> PASS |
| fantasy | night | compose.submitError | accent->ink | 4.50 | 6.47 | 12.41 | PASS -> PASS |
| fantasy | night | compose.theirTurnPrimary | secondary | 4.50 | 6.07 | 6.87 | PASS -> PASS |
| fantasy | night | compose.theirTurnSecondary | secondary | 4.50 | 4.46 | 6.87 | FAIL -> PASS |
| fantasy | night | compose.stepAway | secondary | 4.50 | 6.07 | 6.87 | PASS -> PASS |
| fantasy | night | waiting.stepBackOut | secondary | 4.50 | 5.66 | 6.70 | PASS -> PASS |
| fantasy | night | ritual.label | ink | 4.50 | 13.42 | 13.42 | PASS -> PASS |
| fantasy | night | presence.chip | ink | 4.50 | 12.10 | 12.10 | PASS -> PASS |
| fantasy | night | threshold.gear | ink | 3.00 | 8.25 | 8.25 | PASS -> PASS |
| fantasy | night | settings.title | ink | 4.50 | 10.21 | 10.21 | PASS -> PASS |
| fantasy | night | settings.close | ink | 4.50 | 10.21 | 10.21 | PASS -> PASS |
| fantasy | night | settings.rowText | ink | 4.50 | 12.10 | 12.10 | PASS -> PASS |
| fantasy | night | settings.helper | ink | 4.50 | 9.13 | 9.13 | PASS -> PASS |

## Decisions Made

- Reused the app's existing frosted onAccent 0.6 idiom for the cells where text color alone cannot pass, rather than changing scene colors (locked) or inventing a new component. This is a planner judgment recorded in the plan and flagged for the developer; it is reversible by removing the modifier and the defaulted `Palette.backsSkyText` flag.
- Removed the 0.7 and 0.8 secondary dimming instead of lightening night secondary, because night secondary at full opacity already passes at 4.64 or more and lightening it would also brighten the night cherry branch and dim stars.

## Deviations from Plan

None - plan executed exactly as written. Two minor notes that are within the plan's own latitude:

- The fantasy morning secondary landed at 453E52 rather than the advisory 473F54; the plan said to step the scale down if the Swift model missed by a hair.
- The test header and helper names differ cosmetically from the plan's prose (for example the card opacity lives in a tiny `Legibility0` helper in the test, because the production `Legibility` enum only owns the backing opacity).

**Total deviations:** 0 auto-fixed.

## Issues Encountered

- The first `scripts/test-ios.sh` run builds the app from scratch and exceeded a single 10-minute foreground call, so it ran in the background; subsequent runs were fast.
- The full suite reports 1 skipped test, `failsOnPurpose()`, the harness canary that is skipped by design unless its env flag is set; this plan did not touch it.

## Authentication Gates

None.

## Known Stubs

None.

## Threat Flags

None. No new network endpoints, auth paths or storage. `PartnerPresence` (the robot-poet disclosure), `RitualButton`, `SettingsView`, `RootView`, `NatureTheme`, `PixelScene`, `Pixel`, `Dissolution` and `project.yml` are byte-identical to HEAD, and the chip, ritual labels, gear and settings text are measured and pass in all 9 palettes (T-l7k-01).

## User Setup Required

None - no external service configuration required.

## Open item (deferred, non-blocking)

Visual check, deferred because this milestone is automated-only: in `./run.sh` with `SW_DEV=1`, step through the dev chips across all 9 palettes. Confirm the new backings read as quiet frosted pills and not as buttons competing with the ritual buttons. Look at the sci-fi day panels around the Threshold title, poem lines and keepsake, and confirm the darker day secondary still reads as quieter than ink. The tightest passing cells (about +0.01 to +0.02 over 4.5) are fantasy morning keepsake lead and kind, and fantasy afternoon lower-screen copy; a smaller screen could graze one more band there.

## Next Phase Readiness

- Any new text surface (for example the Phase 6 two-poem trade UI) should be added as a row in `ContrastTests.inventory`; the suite then guards it in all 9 palettes.
- Nothing blocks the next quick item. `261029-l7l` also edits `ComposeView.swift`; this plan touched only the call-site modifiers, hint, error and their-turn block.

## Self-Check: PASSED

- Files exist: `ios/StrangewordsTests/ContrastTests.swift`, `ios/Strangewords/Design/Legibility.swift`.
- Commits reachable from HEAD: `a6962d3`, `86dc1f5`, `daf7478`, `2a297f3`.
- `git rev-list --count eb0375c..HEAD` measured 4, matching `actuals.commits`.
- Task 3 automated gate exited 0: ContrastTests 8/8, 207 lines, zero FAIL or INFEASIBLE; full suite PASS with 125 passed, 0 failed.

---
*Phase: quick-261029-l7k*
*Completed: 2026-10-29*
