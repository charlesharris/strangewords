---
phase: quick-261029-jhv
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - ios/Strangewords/Features/Compose/StepAway.swift
  - ios/Strangewords/Features/Compose/ComposeView.swift
  - ios/StrangewordsTests/StepAwayTests.swift
autonomous: true
requirements: [QUICK-261029-jhv]
coupling_justified:
  - "261029-jhu: no source file overlaps. This plan only calls AppModel.leave()'s session branch, which jhu leaves alone (jhu changes the no-session branch). It reads AppModelTests.Rig, makeModel, haikuView and FakeBackend's .leave/.submitLine/recordedCalls/arrivals without editing them, and jhu's Backend/FakeBackend changes are additive, so either merge order compiles and passes. The shared resource is the simulator: scripts/test-ios.sh shuts its pinned simulator down at the end of a run and has no concurrent-run lock. Every run in this plan pins SW_SIM_NAME='iPhone 17e', so it never shares jhu's default 'iPhone 17'"

must_haves:
  truths:
    - "In Compose, in both the your-turn and their-turn states, a quiet 'step away' control is the last child of ComposeView's root VStack, directly after the existing trailing Spacer(minLength: 24) and outside the writingArea/theirTurn branches. It is styled like the waiting room's 'step back out': Theme.label, palette.secondary, no backing, no accent, a 44pt minimum hit area, and no fixed point sizes"
    - "Tapping 'step away' asks first. A confirmation dialog titled 'step away from this poem?' with the message 'the poem will dissolve unfinished and won't come back' offers a destructive 'step away' and a cancel 'stay with the poem'. Only the destructive button calls model.leave(). Cancelling leaves the poem, turn and draft untouched"
    - "Confirming reuses AppModel.leave() unchanged. With a parked their-turn poll (the reported trap), leave is sent exactly once, the phase becomes .dissolved(.ended) (the plain DissolvedView farewell, then 'begin again'), pollTask is nil, the late poll cannot bring the session back, and an unfinished poem coins no keepsake"
    - "Stepping away fixes the relaunch trap. After it, both identity keys are gone, so a freshly built model over the same defaults stays at .threshold on resume(), starts no action task and makes zero backend calls. Before stepping away, the same defaults held token 'tok' and session 's1'"
    - "Stepping away mid-draft during your turn sends leave and never sends submitLine: a half-written line is never offered"
    - "All six strings are static lets on StepAway and are pinned exactly by StepAwayTests. The five visible strings are lowercase. No string uses cold vocabulary (bot, ai, assistant, chatbot, algorithm, queue, searching, matched, session, quit, exit, cancel, leave), and none names a partner (stranger, someone, robot, person), so the copy is truthful in both human and robot-poet sessions. The Phase 5 D-04 chip (first child, leading, first in VoiceOver order) and PartnerPresence copy are unchanged"
    - "Running scripts/test-ios.sh on SW_SIM_NAME='iPhone 17e' gives PASS with passedTests >= 100 and failedTests == 0. No wall-clock waits exist under ios/StrangewordsTests, and models are built only through makeModel/Rig. No quick-261029-jhv commit touches AppModel.swift, Net/, PartnerPresence.swift, PartnerPresenceTests.swift, AppModelTests.swift, FakeBackend.swift, TestSupport.swift or project.yml"
  artifacts:
    - path: "ios/Strangewords/Features/Compose/StepAway.swift"
      provides: "StepAway view (quiet text button + confirmation dialog wired to model.leave()) and its six pinned static copy strings"
      contains: "struct StepAway: View"
    - path: "ios/Strangewords/Features/Compose/ComposeView.swift"
      provides: "StepAway() as the last child of the root VStack, shown in both turn states"
      contains: "StepAway()"
    - path: "ios/StrangewordsTests/StepAwayTests.swift"
      provides: "7 Swift Testing cases: copy pins, voice rules, their-turn leave, your-turn draft, relaunch"
      contains: "struct StepAwayTests"
  key_links:
    - from: "ios/Strangewords/Features/Compose/ComposeView.swift"
      to: "ios/Strangewords/Features/Compose/StepAway.swift"
      via: "StepAway() placed after the trailing Spacer(minLength: 24), outside both turn branches"
      pattern: "StepAway\\(\\)"
    - from: "ios/Strangewords/Features/Compose/StepAway.swift"
      to: "ios/Strangewords/App/AppModel.swift"
      via: "the confirmation dialog's destructive button calls Haptics.soft() then model.leave()"
      pattern: "model\\.leave\\(\\)"
    - from: "ios/StrangewordsTests/StepAwayTests.swift"
      to: "ios/StrangewordsTests/AppModelTests.swift"
      via: "private typealias Rig = AppModelTests.Rig (read-only reuse, as AppModelRaceTests does)"
      pattern: "AppModelTests\\.Rig"
---

<objective>
Give a user who is stuck in Compose a way out that matches the app's ritual tone. During the 2026-10-27 TestFlight session a dead partner held the user at "the stranger is with the poem now". Compose had no exit, and `AppModel.resume()` restored the trap on every relaunch. The fix is a quiet "step away" control in both Compose states. It asks once, then calls the existing `AppModel.leave()`, which POSTs leave, dissolves locally to `.dissolved(.ended)`, clears identity, and lands on the plain farewell and "begin again". All of its copy is pinned by tests, following the PartnerPresenceTests pattern.

Design choices, made at Claude's discretion (this quick item has no UI-SPEC, so this plan is the copy and placement contract):
- **Placement: bottom, last child of the root VStack.** The todo allows either "quiet chrome like the Threshold gear" or "step away phrasing like the waiting room", and this plan takes the second. Top-leading is ruled out because the Phase 5 D-04 robot-poet chip holds that slot, in layout and first in VoiceOver order (05-UI-SPEC "Placement"). Moving the chip would change a locked disclosure layout. Top-trailing is ruled out because it collides with the dev chips (`RootView.devControls`, shown in `./run.sh --mock`), which is the same reason the gear went top-leading. The bottom is where every exit in the app already lives: "step back out", "let it go", "begin again".
- **Asks before leaving.** Leaving ends the shared poem for both writers and can't be undone, and the control sits below the primary "offer this line" button. A one-time `confirmationDialog` with "stay with the poem" as the cancel protects against stray taps. Reversible: deleting the dialog makes it one tap.
- **Partner-neutral copy.** The same strings appear in human and robot-poet sessions, so they never say "stranger" or "robot poet". This keeps the Phase 5 D-04 / T-05-13 voice rule.

Out of scope, stated rather than dropped silently: the todo's "Consider also a gentle assist when the partner has been silent for a long time" is not in this batch item's description, so it is not planned here. The SUMMARY recommends capturing it as a follow-up todo. AppModel, Backend and FakeBackend are not modified, because sibling 261029-jhu owns `AppModel.leave()`'s no-session branch and the Backend protocol in this batch.

Purpose: unblocks the "compose escape" blocker todo from the first TestFlight session.
Output: `StepAway.swift` (view + copy), a one-line placement in `ComposeView.swift`, and `StepAwayTests.swift` (7 tests).
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.claude/CLAUDE.md
@.planning/todos/pending/2026-10-27-add-leave-affordance-to-compose.md
@ios/Strangewords/Features/Compose/ComposeView.swift
@ios/Strangewords/Features/Compose/PartnerPresence.swift
@ios/Strangewords/Features/Waiting/WaitingView.swift
@ios/Strangewords/Features/Threshold/ThresholdView.swift
@ios/Strangewords/Features/Reveal/RevealView.swift
@ios/Strangewords/App/AppModel.swift
@ios/StrangewordsTests/PartnerPresenceTests.swift
@ios/StrangewordsTests/AppModelRaceTests.swift
@ios/StrangewordsTests/TestSupport.swift

<interfaces>
Existing APIs this plan consumes and does not modify:

- `AppModel.leave()`: if `tokenStore.sessionId` and `token` are both present, `actionTask = Task { await api.leave(id:token:) }`. It then always calls `dissolve(.ended)`, which bumps the epoch, stops polling, runs `tokenStore.clear()` and sets `phase = .dissolved(.ended)`. It does not coin a keepsake and does not clear `draft` (`reset()` does that).
- `AppModel.resume()`: with no token it sets `phase = .threshold` and returns synchronously without creating `actionTask`.
- `Haptics.soft()`: the static haptic that RevealView fires before `model.release()`.
- Theme tokens: `Theme.label` (Inter 13, relativeTo .caption) and `Theme.chrome`. Palette: `palette.secondary`.
- Test seams (ios/StrangewordsTests):
  - `AppModelTests.Rig()` provides `.defaults`, `.cleanup`, `.fake: FakeBackend`, `.arrivals: Arrivals`, `.model`, `.identityIsClear`, `beginMatched(_ view: SessionView = haikuView())`, which resolves enter with participantToken "tok", and `beginWaiting()`.
  - `makeModel(backend:defaults:)` is the only AppModel factory.
  - `haikuView(id: "s1", status:, currentLine:, yourTurn:, lines:, partnerIsBot:)`.
  - `FakeBackend.recordedCalls() -> [Kind]` with `Kind` cases `.enter .waiting .getSession .submitLine .leave .dismiss`. `leave` records and returns at once, while getSession and the other calls park until `Pending.resolve(_:)` or `Pending.fail(_:)`.
  - `Arrivals.next()` returns the next parked call. `finish(model, fake, cleanup)` leaves, drains, awaits `actionTask` and runs cleanup.
  - `TokenStore(defaults:)` exposes `.token` and `.sessionId`.
- Race-test sync rule (AppModelRaceTests header): capture `model.pollTask` BEFORE `leave()`, because `stopPolling()` sets it to nil. Sync on `await stale?.value`, never on the clock.
</interfaces>
</context>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: End-to-end escape from a stuck their-turn: "step away" → confirm → AppModel.leave() → dissolved</name>
  <files>ios/StrangewordsTests/StepAwayTests.swift, ios/Strangewords/Features/Compose/StepAway.swift, ios/Strangewords/Features/Compose/ComposeView.swift</files>
  <behavior>
    - copyIsPinned: StepAway.label == "step away"; StepAway.accessibilityHint == "Asks before letting this unfinished poem go. It will not be saved."; StepAway.confirmTitle == "step away from this poem?"; StepAway.confirmMessage == "the poem will dissolve unfinished and won't come back"; StepAway.confirmAction == "step away"; StepAway.stayAction == "stay with the poem"
    - stepAwayWhileTheirTurnSendsLeaveAndDissolves: matched with haikuView(currentLine: 1, yourTurn: false, lines: ["an old silent pond"]); the first arrival is a parked .getSession poll (the stuck wait); capture pollTask, call model.leave(), await actionTask, resolve the stale poll with another their-turn view and await it. Then: phase == .dissolved(.ended); recordedCalls has exactly one .leave; rig.identityIsClear; keepsake == nil; pollTask == nil
  </behavior>
  <action>
Write the tests first. They won't compile until StepAway exists, which is the red step. Then build the view and place it.

(a) Create ios/StrangewordsTests/StepAwayTests.swift with `import Testing`, `import Foundation` and `@testable import Strangewords`. Declare a `@MainActor` `@Suite(.serialized, .timeLimit(.minutes(1)))` struct named StepAwayTests containing `private typealias Rig = AppModelTests.Rig`, the same reuse AppModelRaceTests uses. Give it a doc comment saying it pins the Compose escape copy and the leave contract for the 2026-10-27 stuck-session todo, and that every test syncs on actionTask, pollTask or parked FakeBackend arrivals, never on the wall clock. Add the two tests in `<behavior>`. Assert the copy test exactly as written there. For the their-turn test, follow latePollRefreshAfterLeaveDoesNotResurrect's sync shape: beginMatched with the their-turn view, `rig.arrivals.next()`, `#expect(poll.kind == .getSession)`, capture `let stale = model.pollTask`, call model.leave() (the test stands in for the dialog's destructive button; XCUITest is out of scope for this milestone), `await model.actionTask?.value`, `poll.resolve(...)`, `await stale?.value`, run the expectations, then `await finish(model, rig.fake, rig.cleanup)`. Count leave calls with `filter { $0 == .leave }.count == 1`. Build models only through Rig/makeModel; never call the initializer directly.

(b) Create ios/Strangewords/Features/Compose/StepAway.swift containing one primary type, `struct StepAway: View`. It takes `@Environment(AppModel.self) private var model`, `@Environment(\.palette) private var palette`, and `@State private var confirming = false`. That flag is view-local UI state for the same reason ThresholdView keeps showSettings in a @State. The body is a Button whose action sets confirming = true. Its label is `Text(Self.label)` in `Theme.label` with `palette.secondary`, given `.frame(minWidth: 44, minHeight: 44)` and `.contentShape(Rectangle())` for a 44pt hit area. That is the same quiet look as WaitingView's "step back out": no backing, no ritual capsule, no accent, Theme tokens only, no fixed point sizes, and every dimension a multiple of 4. Add `.accessibilityHint(Self.accessibilityHint)`. The visible text is the label. Attach `.confirmationDialog(Self.confirmTitle, isPresented: $confirming, titleVisibility: .visible)` with two buttons:
- `Button(Self.confirmAction, role: .destructive)`, whose action calls `Haptics.soft()` and then `model.leave()`. This mirrors RevealView's "let it go", which fires the haptic and then the model call.
- `Button(Self.stayAction, role: .cancel)` with an empty action.

Pass `Text(Self.confirmMessage)` as the dialog's message. Add a `// MARK: - Copy (pure, unit-tested)` section declaring the six `static let` strings exactly as pinned in `<behavior>`. Write a header `///` doc comment that covers four points. First, why the control exists: the TestFlight trap, where a dead partner held the user in their-turn and resume() restored the trap on relaunch (cite .planning/todos/pending/2026-10-27-add-leave-affordance-to-compose.md). Second, that it reuses AppModel.leave() unchanged, which POSTs leave, dissolves to .dissolved(.ended) and shows the plain farewell, then "begin again". Third, why it asks first: it ends the poem for both writers and cannot be undone. Fourth, why the copy is partner-neutral: it is shared by human and robot-poet sessions (Phase 5 D-04 voice rule). Do not add any AppModel method or state, and no Backend call. The view calls model.leave() and nothing else.

(c) Edit ComposeView.swift. Add `StepAway()` as the LAST child of the root `VStack(spacing: 28)` in `body`, directly after the existing trailing `Spacer(minLength: 24)` and before the VStack's closing brace that precedes `.onAppear`. That puts it outside both the writingArea and theirTurn branches, so it appears in both turn states and stays its own VoiceOver element after the combined their-turn element. Change nothing else:
- Keep every existing spacer and spacing value.
- Keep the PartnerPresence chip block as the first child, exactly as it is. Phase 5 UI-SPEC requires the chip first, leading, in layout, and first in VoiceOver order.
- Keep the their-turn copy, the accessibility combine, the onAppear announcement and the focus handling.

Add a one-line `//` comment above `StepAway()` explaining the bottom slot: the chip owns top-leading, the dev chips own top-trailing, and the app's exits live at the bottom.

(d) Run the verify. Then commit with scope `quick-261029-jhv` (for example `feat(quick-261029-jhv): quiet step-away escape from Compose`), staging these three explicit paths only and never `git add -A` or `.`. If the red step is committed separately, use `test(quick-261029-jhv): ...`.
  </action>
  <verify>
    <automated>cd "$(git rev-parse --show-toplevel)" && test -f ios/Strangewords/Features/Compose/StepAway.swift && grep -v '^[[:space:]]*//' ios/Strangewords/Features/Compose/ComposeView.swift | grep -q 'StepAway()' && awk '/^[[:space:]]*\/\//{next} /Spacer\(minLength: 24\)/{s=NR} /StepAway\(\)/{a=NR} /\.onAppear/{if(!o)o=NR} END{exit !(s>0 && a>s && a<o)}' ios/Strangewords/Features/Compose/ComposeView.swift && grep -v '^[[:space:]]*//' ios/Strangewords/Features/Compose/StepAway.swift | grep -q 'model.leave()' && grep -v '^[[:space:]]*//' ios/Strangewords/Features/Compose/StepAway.swift | grep -q 'confirmationDialog' && grep -v '^[[:space:]]*//' ios/Strangewords/Features/Compose/StepAway.swift | grep -q 'Theme.label' && ! grep -nE 'system\(size' ios/Strangewords/Features/Compose/StepAway.swift ios/Strangewords/Features/Compose/ComposeView.swift && grep -qF 'PartnerPresence.caption(partnerIsBot: session.partnerIsBot, finished: false)' ios/Strangewords/Features/Compose/ComposeView.swift && OUT="$PWD/build/verify/quick-261029-jhv-t1" && rm -rf "$OUT" && SW_SIM_NAME="iPhone 17e" SW_VERIFY_OUT="$OUT" scripts/test-ios.sh -only-testing:StrangewordsTests/StepAwayTests && S=$(ls -t "$OUT"/ios-summary-*.json | head -1) && jq -e '.result=="Passed" and .failedTests==0 and .passedTests==2' "$S"</automated>
  </verify>
  <reversibility rating="reversible">The confirmation dialog and the bottom placement are view-local SwiftUI choices. Removing the dialog or moving the control changes only StepAway.swift and one line of ComposeView, and doesn't touch AppModel or the server.</reversibility>
  <done>In both Compose states a quiet "step away" sits at the bottom. Tapping it opens a confirmation, and confirming calls model.leave(), which lands on the plain farewell. On the iPhone 17e simulator, the two StepAwayTests (copy pinned, and their-turn leave with no resurrection, no keepsake and cleared identity) pass with exactly 2 passed and 0 failed. The chip line in ComposeView is unchanged, and the work is committed under quick-261029-jhv.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Pin the rest of the escape contract (your-turn draft, relaunch, voice rules) and run the full suite</name>
  <files>ios/StrangewordsTests/StepAwayTests.swift</files>
  <behavior>
    - visibleCopyIsLowercase: label, confirmTitle, confirmMessage, confirmAction and stayAction each equal their own lowercased() (the app's chrome voice: "step back out", "let it go", "offer this line"). The accessibility hint is sentence case like RevealView's and is excluded
    - copyKeepsTheRitualVoice: for all six strings, the word set (lowercased, split on non-letters) is disjoint from {bot, ai, assistant, chatbot, algorithm, queue, searching, matched, session, quit, exit, cancel, leave}
    - copyFitsEitherPartner: for all six strings, the word set is disjoint from {stranger, someone, robot, person}, because the same copy is shown with human and robot-poet partners (Phase 5 D-04 / T-05-13)
    - stepAwayMidDraftNeverOffersTheLine: beginMatched() (your turn), set model.draft = "half a line", leave, await actionTask. Then recordedCalls contains .leave and does not contain .submitLine; phase == .dissolved(.ended); rig.identityIsClear; keepsake == nil
    - relaunchAfterSteppingAwayStartsAtTheThreshold: beginMatched(haikuView(yourTurn: false)), take the parked .getSession poll, capture pollTask. Check that TokenStore(defaults: rig.defaults) holds token "tok" and sessionId "s1" (proof that a relaunch before stepping away would resume the trap). Leave, await actionTask, resolve the stale poll with a their-turn view, await it. Build a second FakeBackend and a second model with makeModel over rig.defaults, call resume(). Then: relaunched.phase == .threshold, relaunched.actionTask == nil, the second fake's recordedCalls() is empty, and rig.identityIsClear
  </behavior>
  <action>
Add the five tests in `<behavior>` to ios/StrangewordsTests/StepAwayTests.swift, for 7 `@Test` functions in total. Don't use parameterized tests, because the xcresult passed-count gate expects exactly one count per function.

For the word-set tests, add a private `words(_:)` helper to StepAwayTests that matches PartnerPresenceTests' one-liner (lowercase, split on non-letters, Set of String). Duplicate it here and don't edit PartnerPresenceTests. Give each `#expect` a message that names the offending string, as PartnerPresenceTests does.

For the relaunch test:
- Build the second model through makeModel(backend:defaults:) with the rig's defaults. That stands in for a cold launch over the same device container.
- Tear down both models: first `await finish(relaunched, relaunchFake, {})`, then `await finish(model, rig.fake, rig.cleanup)`, so the suite is erased exactly once.
- Leave the before-leave identity check in. It is what keeps this test from passing vacuously.

These tests characterize existing AppModel behavior plus Task 1's copy, so they should pass the first time. If one fails, the defect is in Task 1's StepAway copy or ComposeView wiring, so fix it there. Do NOT edit AppModel.swift, anything under ios/Strangewords/Net, FakeBackend.swift, TestSupport.swift, AppModelTests.swift, PartnerPresence.swift, PartnerPresenceTests.swift or ios/project.yml. Sibling 261029-jhu owns the AppModel/Backend/FakeBackend changes in this batch, and the Phase 5 disclosure files are locked. If an AppModel defect does turn up, stop and report it in the SUMMARY instead of patching it.

Keep every test free of wall-clock waits and real-time delays. Sync only on actionTask, pollTask and parked arrivals.

Run the verify, then commit as `test(quick-261029-jhv): pin the Compose escape contract`, staging only ios/StrangewordsTests/StepAwayTests.swift.
  </action>
  <verify>
    <automated>cd "$(git rev-parse --show-toplevel)" && test "$(grep -cE '^[[:space:]]*@Test' ios/StrangewordsTests/StepAwayTests.swift)" -ge 7 && grep -q 'AppModelTests.Rig' ios/StrangewordsTests/StepAwayTests.swift && grep -q 'makeModel(backend:' ios/StrangewordsTests/StepAwayTests.swift && ! grep -rnE '(Task|Thread)\.sleep|usleep|asyncAfter' ios/StrangewordsTests && test -z "$(grep -rn 'AppModel(' ios/StrangewordsTests | grep -v '^ios/StrangewordsTests/TestSupport.swift:' | grep -v 'tokenStore:')" && git diff --quiet HEAD -- ios/Strangewords/App/AppModel.swift ios/Strangewords/Net ios/Strangewords/Features/Compose/PartnerPresence.swift ios/StrangewordsTests/PartnerPresenceTests.swift ios/StrangewordsTests/AppModelTests.swift ios/StrangewordsTests/FakeBackend.swift ios/StrangewordsTests/TestSupport.swift ios/project.yml && test -z "$(git log --format=%h -F --grep='quick-261029-jhv' -- ios/Strangewords/App/AppModel.swift ios/Strangewords/Net ios/Strangewords/Features/Compose/PartnerPresence.swift ios/StrangewordsTests/PartnerPresenceTests.swift ios/StrangewordsTests/AppModelTests.swift ios/StrangewordsTests/FakeBackend.swift ios/StrangewordsTests/TestSupport.swift ios/project.yml)" && test -n "$(git log --format=%h -F --grep='quick-261029-jhv' -- ios/Strangewords/Features/Compose/StepAway.swift)" && OUT="$PWD/build/verify/quick-261029-jhv-t2" && rm -rf "$OUT" && SW_SIM_NAME="iPhone 17e" SW_VERIFY_OUT="$OUT" scripts/test-ios.sh && S=$(ls -t "$OUT"/ios-summary-*.json | head -1) && jq -e '.result=="Passed" and .failedTests==0 and .passedTests>=100' "$S"</automated>
    <human-check>Deferred manual UAT (non-blocking; this milestone is automated-only). On the smallest supported iPhone, in a your-turn session with the keyboard open, check that "step away" sits above the keyboard below "offer this line" without clipping the poem lines or the robot-poet chip. In a their-turn session, check that it sits at the bottom where "step back out" sat in the waiting room. Record this in the SUMMARY as an open UAT item; do not perform it.</human-check>
  </verify>
  <done>StepAwayTests has 7 tests: copy pinned, lowercase visible copy, ritual voice, partner-neutral copy, their-turn leave, your-turn draft never offered, and relaunch starting at the threshold with zero backend calls. The full suite on iPhone 17e reports PASS with passedTests >= 100 and 0 failed. The sleep and constructor grep gates are clean, no quick-261029-jhv commit touches a protected file, and the work is committed.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| user tap → AppModel | A single tap in Compose can now end a shared poem for both participants, guarded by a confirmation |
| AppModel → server (POST /v1/session/{id}/leave) | Existing, unchanged call carrying the bearer participant token; this plan adds only a new UI entry to it |
| device storage (UserDefaults via TokenStore) | Identity must not survive stepping away (anonymity model); tests must not write to UserDefaults.standard |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-jhv-01 | Denial of service | ComposeView their-turn with a dead partner (the reported trap, up to SessionTTL 90 min) | high | mitigate | StepAway is a root-VStack sibling of both turn branches and is wired to AppModel.leave(). stepAwayWhileTheirTurnSendsLeaveAndDissolves pins that leave is sent once, the phase dissolves, pollTask is nil, and a late parked poll can't bring the session back. The ComposeView placement is gated by awk ordering. |
| T-jhv-02 | Information disclosure | Identity and poem after stepping away (anonymity model) | medium | mitigate | leave() → dissolve() clears both TokenStore keys, and an unfinished poem coins no keepsake (asserted). relaunchAfterSteppingAwayStartsAtTheThreshold proves a fresh model over the same defaults finds no identity and makes zero backend calls. AppModel itself is unchanged, enforced by the protected-file gates. |
| T-jhv-03 | Denial of service | Accidental one-tap end of a partner's poem | low | mitigate | A confirmationDialog appears with a cancel "stay with the poem". Only the destructive button calls model.leave(), and StepAway sits below the trailing Spacer(minLength: 24), away from "offer this line". stepAwayMidDraftNeverOffersTheLine pins that leaving never submits a half-written line. |
| T-jhv-04 | Spoofing | Copy shared by human and robot-poet sessions (Phase 5 D-04 / T-05-13) | medium | mitigate | copyFitsEitherPartner bans stranger/someone/robot/person and copyKeepsTheRitualVoice bans cold vocabulary. The D-04 chip line in ComposeView is count-gated unchanged, and PartnerPresence.swift and PartnerPresenceTests.swift are protected by the diff and log gates. |
| T-jhv-05 | Information disclosure | Tests writing identity into UserDefaults.standard | low | mitigate | Models are built only through makeModel/Rig (suite-named defaults, erased by finish). The existing constructor grep gate and the wall-clock-wait grep gate both run in Task 2's verify. |
| T-jhv-06 | Tampering | Parallel batch sibling 261029-jhu (shared simulator, shared test seams) | low | mitigate | Every test-ios.sh run pins SW_SIM_NAME="iPhone 17e" with its own SW_VERIFY_OUT, so jhu's default "iPhone 17" is never shut down mid-run. Commits stage explicit paths only. The log and diff gates prove no quick-261029-jhv commit touches AppModel, Net/, FakeBackend, TestSupport or AppModelTests. |
| T-jhv-SC | Tampering | SPM/npm/pip/cargo installs | high | mitigate | No packages are installed. The iOS app keeps its no-third-party-dependencies convention, and ios/project.yml is untouched (protected-file gate), so the package-legitimacy gate is satisfied vacuously. |
</threat_model>

<verification>
Run from the repo root after both tasks:
1. `SW_SIM_NAME="iPhone 17e" SW_VERIFY_OUT="$PWD/build/verify/quick-261029-jhv-t2" scripts/test-ios.sh` exits 0, and the newest ios-summary json shows result Passed, failedTests 0, passedTests >= 100 (baseline 93 + 7).
2. `grep -rnE '(Task|Thread)\.sleep|usleep|asyncAfter' ios/StrangewordsTests` prints nothing.
3. The constructor gate (every `AppModel(` hit under ios/StrangewordsTests is in TestSupport.swift or carries `tokenStore:`) prints nothing.
4. `git log --format=%h -F --grep='quick-261029-jhv' -- ios/Strangewords/App/AppModel.swift ios/Strangewords/Net ios/Strangewords/Features/Compose/PartnerPresence.swift ios/StrangewordsTests/PartnerPresenceTests.swift ios/StrangewordsTests/AppModelTests.swift ios/StrangewordsTests/FakeBackend.swift ios/StrangewordsTests/TestSupport.swift ios/project.yml` prints nothing, and the same log over the three files_modified paths prints this item's commits.
5. `StepAway()` appears (non-comment) in ComposeView.swift after the trailing `Spacer(minLength: 24)` and before `.onAppear` (awk ordering gate). The D-04 chip line is still present.
</verification>

<success_criteria>
- A user stuck at "the stranger is with the poem now" (or "the robot poet is with the poem now") can tap "step away", confirm, and land on "That's the end of it." with "begin again". A relaunch then starts fresh at the threshold, so the trap is gone.
- The same control works during your turn and never submits the draft.
- The copy is pinned, lowercase, ritual in voice and partner-neutral. The Phase 5 disclosure chip and copy are untouched.
- The full iOS suite passes on iPhone 17e with at least 100 passed and none failed, and every existing grep gate still holds.
</success_criteria>

<output>
Create `.planning/quick/261029-jhv-ios-add-a-quiet-leave-affordance-to-composeview-both-your-tu/261029-jhv-SUMMARY.md` when done. Record:
- the placement rationale (chip owns top-leading, dev chips own top-trailing, exits live at the bottom) and the confirmation-dialog decision
- the final pinned copy
- the test-ios evidence directories and pass counts
- the deferred human-check from Task 2 as an open UAT item
- the out-of-scope silence assist ("surface the option more visibly after N minutes" from the todo), recommended as a follow-up todo

Leave `.planning/todos/` untouched, since it is outside files_modified. Note in the SUMMARY that this item resolves the compose-escape todo apart from that optional assist.
</output>
