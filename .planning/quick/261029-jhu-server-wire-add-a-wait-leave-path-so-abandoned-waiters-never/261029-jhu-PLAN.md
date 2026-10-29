---
phase: quick-261029-jhu
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - server/internal/store/store.go
  - server/internal/matchmaker/matchmaker.go
  - server/internal/gateway/gateway.go
  - server/internal/metrics/metrics.go
  - server/internal/gateway/wait_test.go
  - server/internal/gateway/bot_test.go
  - plan.v1.md
  - ios/Strangewords/Net/Backend.swift
  - ios/Strangewords/Net/APIClient.swift
  - ios/Strangewords/Net/LocalBackend.swift
  - ios/Strangewords/App/AppModel.swift
  - ios/StrangewordsTests/FakeBackend.swift
  - ios/StrangewordsTests/AppModelTests.swift
  - ios/StrangewordsTests/LocalBackendTests.swift
autonomous: true
requirements: [QUICK-261029-jhu]

must_haves:
  truths:
    - "A waiter who taps 'step back out' leaves the server queue. AppModel.leave() with a stored token and no session id calls Backend.leaveWait(token:). APIClient POSTs /v1/wait/leave with the bearer token. The server removes the queue entry (LREM) and deletes the wait record and token ref. The next arriver, including the same device entering again, waits instead of pairing with the departed waiter (OBS-1 production incidents 1 and 2)"
    - "If a match landed before the wait-leave reached the server (the waiter's ref is already bound to a session), wait-leave dissolves that session and answers {\"status\":\"dissolved\"}, so the partner gets 410 rather than a dead poem"
    - "If a queued waiter has not polled within matchmaker.StaleWaiterAfter (10 s, about 3x the 3 s poll), the arriver that pops it drops its wait record and token ref, then pairs with the next live waiter or waits. At exactly StaleWaiterAfter the waiter still counts as live. A waiter that keeps polling every 3 s is never dropped, however long it waits. A poll never extends WaitTTL"
    - "An opted-in arriver that finds only stale waiters is enqueued with its own EnqueuedAt. It is paired with the robot poet exactly at its own BotWindow: one millisecond earlier it still waits. The stale waiter never delays or blocks that window"
    - "Race safety: a wait-leave racing a human arrival, or racing the waiter's own bot claim at the window boundary, never leaves a live session holding the departed waiter. It never produces two sessions and never returns a 500. B matched happens if and only if the leave reported dissolved. 50-iteration tests pass under -race, and TestHumanVsBotRaceSingleSession still holds with a live, polling waiter"
    - "Anonymity and ephemerality hold. There is no new Redis key class (store.go keeps exactly 5 \"sw: literals). LastPolledAt lives only on the TTL-bound wait entry. Every write to a waiter's wait record or token ref after creation is conditional (SET XX), so nothing a leave, stale drop or dissolve deleted is ever recreated. No token or poem text is logged"
    - "LocalBackend and FakeBackend implement leaveWait(token:). In LocalBackend, leaveWait ends the wait and dissolves the poem, and later waiting and getSession calls throw APIError.gone, as on the server. scripts/test-ios.sh reports PASS with zero wall-clock sleeps in ios/StrangewordsTests. go test -race ./..., go vet ./... and gofmt -l server/ are clean, and go.mod and go.sum are unchanged"
  artifacts:
    - path: "server/internal/gateway/wait_test.go"
      provides: "Wait-leave tracer, error, matched-before-leave, pre-bot-window, stale-drop, liveness, opted-in-window and two race tests"
      contains: "func TestWaitLeaveVsArrivalRace("
    - path: "server/internal/store/store.go"
      provides: "WaitEntry.LastPolledAt plus LastSeenAt, UpdateWait (SET XX KEEPTTL), DropWait, DropWaitIfUnbound (WATCH compare-and-delete), BindWaiter (SET XX)"
      contains: "func (s *Store) DropWaitIfUnbound("
    - path: "server/internal/matchmaker/matchmaker.go"
      provides: "StaleWaiterAfter [TUNABLE], the Enter stale-skip loop, LeaveWait, and pair/PairWithBot binding through BindWaiter"
      contains: "func (m *Matchmaker) LeaveWait("
    - path: "server/internal/gateway/gateway.go"
      provides: "POST /v1/wait/leave route and handleWaitLeave; the handleWaiting liveness touch; the migration through BindWaiter"
      contains: "\"POST /v1/wait/leave\""
    - path: "ios/Strangewords/Net/Backend.swift"
      provides: "leaveWait(token:) on the Backend protocol"
      contains: "func leaveWait(token: String) async"
    - path: "ios/Strangewords/App/AppModel.swift"
      provides: "leave() reports a pre-match exit through api.leaveWait"
      contains: "api.leaveWait"
  key_links:
    - from: "ios/Strangewords/App/AppModel.swift leave()"
      to: "Backend.leaveWait(token:)"
      via: "token present and tokenStore.sessionId nil; token captured before dissolve() clears identity"
      pattern: "api.leaveWait"
    - from: "ios/Strangewords/Net/APIClient.swift leaveWait"
      to: "server/internal/gateway/gateway.go route"
      via: "the identical path literal /v1/wait/leave on both sides"
      pattern: "/v1/wait/leave"
    - from: "gateway.handleWaiting (KindWait, unmatched)"
      to: "matchmaker.Enter staleness check"
      via: "store.UpdateWait writes LastPolledAt; Enter compares now against WaitEntry.LastSeenAt()"
      pattern: "LastSeenAt"
    - from: "matchmaker pair / PairWithBot / handleWaiting migration"
      to: "matchmaker.LeaveWait -> store.DropWaitIfUnbound"
      via: "the waiter's token ref is the ownership record: binds use SET XX, the leave uses a WATCH compare-and-delete, so exactly one side wins"
      pattern: "BindWaiter"
---

<objective>
Close OBS-1: abandoned waiters must never dead-pair with the next arriver. It hit production twice on 2026-10-27, once as a ghost waiter left by a deploy check and once when a user re-entered and paired with their own ghost.

There are two complementary halves, as the todo specifies, plus the race closure that makes "never" true:
1. **Wait-leave path.** `POST /v1/wait/leave` takes the bearer participant token. It removes the queue entry (LREM) and deletes the wait record and token ref. The iOS "step back out" calls it through `AppModel.leave()` whenever there is a token and no session id yet. `LocalBackend` and `FakeBackend` mirror the protocol change (parity rule).
2. **Liveness at pair time.** `handleWaiting` records `LastPolledAt` on the existing wait entry. `matchmaker.Enter` drops queue entries whose owner has not polled within `StaleWaiterAfter`. This covers crashes, backgrounded apps, offline devices and old clients that never call the new endpoint. An opted-in arriver's own bot window is never blocked.
3. **Race closure.** The waiter's token ref is the single ownership record. Every pairing binds it with SET XX, and the leave deletes it with a WATCH compare-and-delete. A leave racing an arrival or a bot claim therefore either drops the waiter before any bind, or sees the bind and dissolves the session. Race tests sit alongside `TestHumanVsBotRaceSingleSession`.

Purpose: this is the top pre-App-Store fix. Combined with the missing Compose escape (sibling item 261029-jhv), OBS-1 traps users for up to 90 minutes.
Output: server endpoint, liveness and race protocol with tests; iOS wire, AppModel change and mirrored test doubles with tests; the plan.v1.md §6/§7 contract updated.

Claude's discretion (recorded here, reversible):
- `StaleWaiterAfter = 10 s`: 3.3x the 3 s poll, with slack for one slow request.
- The endpoint answers `{"status":"left"}` or `{"status":"dissolved"}`, and 410 `session_gone` when the caller has nothing to leave.
- Two business counters: `sw_wait_left_total` and `sw_stale_waiters_dropped_total`. They let production confirm the fix.
- Behavior change, intended by the todo ("covers crashes/offline"): a waiter whose app is backgrounded stops polling. After 10 s an arriver may drop them, and on return their next poll gets 410. AppModel already maps that to `.dissolved(.noOneCame)`. Revisit when APNs push lands.

Out of scope:
- The Compose leave affordance (sibling item 261029-jhv).
- The pre-existing Phase 3 leak of a matched waiter's wait entry, which is left to WaitTTL after a normal match. This plan must not worsen it.
- A leave during `.connecting`. WaitingView shows no "step back out" while connecting.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.claude/CLAUDE.md
@.planning/todos/pending/2026-10-27-abandoned-waiters-dead-pair-with-next-arriver.md
@server/internal/store/store.go
@server/internal/matchmaker/matchmaker.go
@server/internal/gateway/gateway.go
@server/internal/gateway/bot_test.go
@server/internal/gateway/gateway_test.go
@server/internal/metrics/metrics.go
@ios/Strangewords/Net/Backend.swift
@ios/Strangewords/Net/APIClient.swift
@ios/Strangewords/Net/LocalBackend.swift
@ios/Strangewords/App/AppModel.swift
@ios/StrangewordsTests/FakeBackend.swift
@ios/StrangewordsTests/AppModelTests.swift
@ios/StrangewordsTests/LocalBackendTests.swift
@ios/StrangewordsTests/TestSupport.swift

<interfaces>
These signatures are new or changed. Executors implement exactly these names.

server/internal/store/store.go
- WaitEntry gains `LastPolledAt int64` with json tag `lastPolledAt,omitempty`: unix ms of the waiter's latest poll, zero until the first poll.
- `func (w *WaitEntry) LastSeenAt() int64`: max(EnqueuedAt, LastPolledAt).
- `func (s *Store) UpdateWait(ctx context.Context, w *WaitEntry) (bool, error)`: rewrites an EXISTING wait record with SET XX KEEPTTL (go-redis `SetXX(ctx, key, b, redis.KeepTTL)`). It returns false when the record is gone. It never recreates a record and never extends WaitTTL. It replaces SaveWait, whose only caller is pair().
- `func (s *Store) DropWait(ctx context.Context, w *WaitEntry) error`: a single DEL of waitKey(w.ID) and tokKey(w.Token). Only a caller that already owns the waiter may use it, meaning it has removed the waiter from the queue by LPOP.
- `func (s *Store) DropWaitIfUnbound(ctx context.Context, token, waitID string) (Ref, bool, error)`: a WATCH on tokKey(token), modelled on UpdateSession. Inside, it GETs the ref; redis.Nil gives ErrNotFound. If the ref is Kind==KindWait and RefID==waitID, a MULTI DELs the token ref and the wait record, and it returns (ref, true, nil). Otherwise it returns (current ref, false, nil) and deletes nothing. On redis.TxFailedErr (a bind landed after the WATCH) it re-reads the ref once with GetRef and returns (that ref, false, nil), or ErrNotFound. One attempt, no retry loop.
- `func (s *Store) BindWaiter(ctx context.Context, token string, ref Ref, ttl time.Duration) (bool, error)`: SetXX(tokKey(token), ref JSON, ttl). It returns false when the token ref no longer exists, which means the waiter left or was dropped.

server/internal/matchmaker/matchmaker.go
- `const StaleWaiterAfter = 10 * time.Second`, carrying a [TUNABLE] doc comment.
- `func (m *Matchmaker) LeaveWait(ctx context.Context, token, waitID string) (matchedSessionID string, err error)`.
- pair() returns `(*sessions.Session, bool, error)`. A false bool means the waiter left mid-pairing and the session was torn down.

server/internal/metrics/metrics.go (business counters block)
- `WaitLeft`, named `sw_wait_left_total`.
- `StaleWaitersDropped`, named `sw_stale_waiters_dropped_total`.

server/internal/gateway/gateway.go
- `mux.HandleFunc("POST /v1/wait/leave", s.handleWaitLeave)`.

iOS
- Backend protocol, APIClient, LocalBackend and FakeBackend all gain `func leaveWait(token: String) async`.
- FakeBackend.Kind gains `leaveWait`. FakeBackend gains `func recordedLeaveWaitTokens() -> [String]`.
</interfaces>
</context>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: Tracer — POST /v1/wait/leave removes a waiter end to end (route, handler, matchmaker, store)</name>
  <reversibility rating="costly">This adds a public wire endpoint that shipped iOS builds will call, so the path must stay stable. It is additive: an old server 404s it and the client ignores that. The todo already settled the path, so this is flagged but not checkpointed.</reversibility>
  <files>server/internal/store/store.go, server/internal/matchmaker/matchmaker.go, server/internal/gateway/gateway.go, server/internal/metrics/metrics.go, server/internal/gateway/wait_test.go</files>
  <behavior>
    - TestWaitLeaveTracer (newBotRig):
      - Plain A enters and gets waiting. POST /v1/wait/leave with A's bearer returns 200 and a body containing "status":"left".
      - countKeys reports 0 for "sw:wait:", "sw:tok:" and "sw:queue:". GET /v1/waiting with A's token returns 410. The WaitLeft delta is 1.
      - A' then enters (the same device re-entering) and gets waiting, not matched, with 0 "sw:sess:" keys.
      - B enters and is matched, which proves the queue still pairs live waiters.
    - TestWaitLeaveErrors:
      - No Authorization header gives 401 with "no_token" in the body.
      - Bearer "not-a-real-token" gives 410 with "session_gone".
      - A second wait-leave with the same token, after a successful one, gives 410.
    - TestWaitLeaveAfterMatchDissolves:
      - A enters (waiting) and B enters (matched). A, whose client has not polled yet and has no session id, calls wait-leave and gets 200 with "status":"dissolved".
      - B's GET /v1/session/{id} gives 410 and A's GET /v1/waiting gives 410. "sw:sess:" and "sw:tok:" counts are 0. The metrics.Dissolved delta and the WaitLeft delta are both 1.
      - Do NOT assert "sw:wait:" here. A's matched wait entry is the known Phase 3 leak, left to WaitTTL.
    - TestWaitLeaveBeforeBotWindow:
      - Opted-in A enters, then wait-leaves and gets "left".
      - Advance past cfg.BotWindow. A's poll gives 410. A new opted-in arriver X enters and gets waiting.
      - The BotPaired delta is 0 and there are 0 "sw:sess:" keys.
  </behavior>
  <action>
    Write wait_test.go first (package gateway, red). Reuse newBotRig, enterWith, poll, b.do, countKeys and assertNoKeysWithPrefix from bot_test.go and gateway_test.go, and read metric deltas with testutil.ToFloat64 the way bot_test.go does. Nothing may wait on the wall clock: cross windows with b.clock.Advance only.

    Then implement:

    (1) metrics.go: in the business counters block, add `WaitLeft` (Name sw_wait_left_total, Help "Waiters who stepped back out before seeing a match.") and `StaleWaitersDropped` (Name sw_stale_waiters_dropped_total, Help "Queued waiters dropped at pair time because they had stopped polling."). Task 3 increments the second one. Declaring both here keeps metrics.go owned by one task.

    (2) store.go: add DropWaitIfUnbound exactly as specified in the interfaces block. Mirror UpdateSession's structure: s.rdb.Watch keyed on tokKey(token), tx.Get, json.Unmarshal into Ref, tx.TxPipelined with one Del of tokKey(token) and waitKey(waitID), and map redis.TxFailedErr to the re-read. Reuse the existing key helpers. Do not add a key helper or any new "sw: literal; the 5-literal structural gate must stay at 5. Write a doc comment explaining that the token ref is the waiter's ownership record and why the delete is conditional. A pairing that bound the ref first must not have its participant silently deleted out from under its partner.

    (3) matchmaker.go: add LeaveWait(ctx, token, waitID).
    - GetWait(waitID). If the record exists, call ClaimWaiter(w.Bucket, w.ID) to LREM it from its queue. Ignore the claimed bool, because correctness rests on the conditional delete. A missing record (ErrNotFound) is fine, since PopWaiter already skips ids whose record is gone. Return any other error.
    - Call st.DropWaitIfUnbound(ctx, token, waitID):
      - ErrNotFound means it was already gone (expired or dropped): return "" and nil.
      - dropped means return "" and nil.
      - Otherwise, if the returned ref is KindSession, return its RefID: a pairing won, and the caller must dissolve the session.
      - Any other ref is unexpected: return fmt.Errorf with context. Do not include the token in the message.
    - Doc comment: this is the "step back out" path, per plan.v1.md §7.

    (4) gateway.go: register "POST /v1/wait/leave" in Routes(), next to the waiting route. Add handleWaitLeave:
    - Use bearer(r). If it is missing, return writeErr 401 "no_token" "missing bearer token".
    - GetRef. ErrNotFound gives 410 "session_gone" "your wait has ended". Any other error goes to s.fail.
    - If ref.Kind is KindWait, remember waitID = ref.RefID and call s.mm.LeaveWait. An error goes to s.fail. An empty session id means: metrics.WaitLeft.Inc() and writeJSON 200 with status "left". A non-empty id becomes the session to dissolve.
    - If ref.Kind is KindSession, the match landed before the leave and the session is ref.RefID.
    - For a session to dissolve: load it with s.loadSession (errGone surfaces as 410 through s.fail) and call s.dissolve. If waitID is known, call s.st.DelWait(ctx, waitID) best-effort. Then metrics.WaitLeft.Inc() and writeJSON 200 with status "dissolved".
    - Never log the token. The body needs no decoding, and limitBody and the rate limiter already wrap every route.
  </action>
  <verify>
    <automated>OUT=$(cd server && go test -race -count=1 -v -run 'TestWaitLeave' ./internal/gateway/) && ( for t in TestWaitLeaveTracer TestWaitLeaveErrors TestWaitLeaveAfterMatchDissolves TestWaitLeaveBeforeBotWindow; do printf '%s\n' "$OUT" | grep -q "^--- PASS: $t " || { echo "missing or failing: $t" >&2; exit 1; }; done ) && (cd server && go test -race -count=1 ./... && go vet ./...) && test -z "$(gofmt -l server/)" && grep -qF '"POST /v1/wait/leave"' server/internal/gateway/gateway.go && grep -qF 'func (s *Store) DropWaitIfUnbound(' server/internal/store/store.go && grep -qF 'func (m *Matchmaker) LeaveWait(' server/internal/matchmaker/matchmaker.go && test "$(grep -o '"sw:' server/internal/store/store.go | wc -l | tr -d ' ')" = 5</automated>
    Baselines at HEAD: the route literal 0, DropWaitIfUnbound 0, LeaveWait 0, wait_test.go absent, so each positive gate fails before the work. The "sw: count is 5, an invariant that must stay 5.
  </verify>
  <done>Over real HTTP through miniredis, a waiter who calls POST /v1/wait/leave is gone: no queue entry, wait record or token ref, and its polls get 410. A re-entering device waits instead of pairing with its own ghost. A wait-leave that arrives after a match dissolves that session, so the partner sees 410. The four TestWaitLeave* tests and the full server suite pass under -race, and vet and gofmt are clean.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: iOS wire — "step back out" calls leaveWait through every Backend conformer</name>
  <reversibility rating="costly">Every conformer of the Backend protocol (APIClient, LocalBackend, FakeBackend) must change in this one commit. Undoing it is a coordinated change, not a migration.</reversibility>
  <files>ios/Strangewords/Net/Backend.swift, ios/Strangewords/Net/APIClient.swift, ios/Strangewords/Net/LocalBackend.swift, ios/Strangewords/App/AppModel.swift, ios/StrangewordsTests/FakeBackend.swift, ios/StrangewordsTests/AppModelTests.swift, ios/StrangewordsTests/LocalBackendTests.swift</files>
  <behavior>
    - leaveWhileWaitingSendsLeaveWait:
      - This renames and inverts the OBS-1 pin leaveWhileWaitingSendsNoLeaveCall.
      - beginWaiting, then leave(), then await model.actionTask?.value.
      - The recorded calls contain exactly one .leaveWait and no .leave. recordedLeaveWaitTokens() == ["tok"].
      - phase == .dissolved(.ended) and identityIsClear.
    - leaveWhileWaitingTwiceSendsOneLeaveWait: two leave() calls send exactly one .leaveWait, because the second finds no token.
    - leaveAfterResumeIntoWaitingSendsLeaveWait:
      - Seed token "tok" with sessionId nil. resume() is answered waiting, and the next poll parks.
      - leave() sends .leaveWait with ["tok"].
    - leaveAtThresholdSendsNothing: leave() on a fresh Rig records no calls at all.
    - leaveMidSessionSendsLeave (existing) additionally expects no .leaveWait.
    - LocalBackendTests leaveWaitEndsTheWait (mirrors TestWaitLeaveTracer):
      - Use botWindow 3600. An opted-in enter is waiting. After leaveWait(token: "local"), waiting(token:) throws APIError.gone.
      - A fresh enter(allowBot: false) is then matched, active, with empty lines.
    - LocalBackendTests leaveWaitAfterMatchDissolves (mirrors TestWaitLeaveAfterMatchDissolves): enter(allowBot: false) is matched. After leaveWait, getSession throws APIError.gone.
  </behavior>
  <action>
    Tests first. Use the gated FakeBackend, the Rig, makeModel and finish. Sync only on actionTask, pollTask and the arrivals walker, never on the wall clock. The no-sleep gate is pinned at 0.

    (1) FakeBackend.swift:
    - Add `leaveWait` to Kind.
    - Add `func leaveWait(token: String) async`. Like leave and dismiss, it records the kind and returns at once without parking; it also appends the token to a new private `leaveWaitTokens` array.
    - Add `func recordedLeaveWaitTokens() -> [String]` under the Test surface mark.
    - Update the type's doc comment so it lists leaveWait with leave and dismiss.

    (2) AppModelTests.swift, Leaving section:
    - Rename leaveWhileWaitingSendsNoLeaveCall to leaveWhileWaitingSendsLeaveWait and invert it as the behavior block says. Replace its doc comment with: OBS-1 fixed by quick 261029-jhu; a pre-match exit is reported through leaveWait.
    - Add the other new tests and extend leaveMidSessionSendsLeave.
    - Leave every other test, AppModelRaceTests and TestSupport untouched. They assert phases and identity, not exact call lists that include a leave, so they keep passing.

    (3) Backend.swift: add `func leaveWait(token: String) async` after leave. Its doc comment: step out of the waiting queue before any match (the "step back out" action). It is fire-and-forget like leave. The server removes the queue entry, wait record and token ref, or dissolves the session if a match landed first. If the call never arrives, the server's liveness rule drops the waiter within StaleWaiterAfter. An older server 404s it, which is ignored.

    (4) APIClient.swift: leaveWait POSTs "/v1/wait/leave" with the bearer token and an empty JSON object, using the same best-effort try? shape as leave.

    (5) LocalBackend.swift: leaveWait calls the existing dissolve(). waiting(token:) gains a first-line guard that throws APIError.gone when status is "dissolved", mirroring the server's 410 once the token ref is gone. Update the header doc:
    - leaveWait joins leave and dismiss in "Like the server, ... dissolve the poem".
    - Add one DRIFT line: the server also drops waiters who stop polling (StaleWaiterAfter) when an arriver pops them; the mock has no queue or other arrivers, so there is nothing to drop.

    (6) AppModel.swift leave():
    - If a token exists and tokenStore.sessionId exists, keep the current api.leave(id:token:) task.
    - If a token exists but there is no session id, set actionTask to a Task that awaits api.leaveWait(token:).
    - In both cases capture the token before dissolve(.ended) clears identity, then dissolve as today.
    - Update the doc comment: a pre-match exit is reported so the server never pairs the next arriver with a departed waiter (OBS-1).
    - Do not persist anything new. Nothing else in AppModel changes.
  </action>
  <verify>
    <automated>scripts/test-ios.sh && grep -qF 'func leaveWait(token: String) async' ios/Strangewords/Net/Backend.swift && grep -qF '"/v1/wait/leave"' ios/Strangewords/Net/APIClient.swift && grep -qF 'api.leaveWait' ios/Strangewords/App/AppModel.swift && grep -qF 'leaveWait' ios/Strangewords/Net/LocalBackend.swift && grep -qF 'leaveWait' ios/StrangewordsTests/FakeBackend.swift && grep -qF 'func leaveWhileWaitingSendsLeaveWait' ios/StrangewordsTests/AppModelTests.swift && test "$(grep -c 'func leaveWhileWaitingSendsNoLeaveCall' ios/StrangewordsTests/AppModelTests.swift)" = 0 && test "$(grep -rnE 'Task\.sleep|Thread\.sleep|usleep' ios/StrangewordsTests | wc -l | tr -d ' ')" = 0</automated>
    Baselines at HEAD: each positive grep is 0, and the old pin test count is 1, so the negative gate shows something to remove. The sleep count is 0, an invariant. scripts/test-ios.sh takes its verdict only from the xcresult summary and exits 0 only on PASS.
  </verify>
  <done>Tapping "step back out" while waiting sends exactly one leaveWait carrying the stored token, then dissolves locally with identity cleared. A mid-session leave still sends only leave. All three Backend conformers compile and implement leaveWait. LocalBackend's wait ends with gone, mirroring the server. The full iOS suite reports PASS through scripts/test-ios.sh.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Liveness at pair time plus the race-closing bind protocol, with race tests beside TestHumanVsBotRaceSingleSession</name>
  <files>server/internal/store/store.go, server/internal/matchmaker/matchmaker.go, server/internal/gateway/gateway.go, server/internal/gateway/bot_test.go, server/internal/gateway/wait_test.go, plan.v1.md</files>
  <behavior>
    - TestStaleWaiterDroppedAtPairTime has two subtests.
    - Subtest "live at the boundary": plain A enters, the clock advances exactly matchmaker.StaleWaiterAfter, and B enters and is matched with A. The StaleWaitersDropped delta is 0.
    - Subtest "stale one millisecond later": plain A enters, the clock advances StaleWaiterAfter+1ms, and B enters.
      - B waits, and A's poll gets 410. The StaleWaitersDropped delta is 1.
      - countKeys gives 1 for "sw:wait:" and 1 for "sw:tok:" (B's only).
      - C enters and is matched, and B's next poll shows C's session id.
    - TestPollingKeepsWaiterLive:
      - Plain A enters. b.mr.FastForward(time.Minute), then A polls. The TTL of "sw:wait:"+A.WaitID must equal store.WaitTTL-time.Minute, so the touch kept the TTL rather than resetting it.
      - Then five rounds of advance 3s and poll (waiting), more than StaleWaiterAfter after EnqueuedAt in total. B enters and is matched, and A's next poll shows B's session id.
    - TestStaleWaiterDoesNotBlockOptedInArrival has subtests for a stale plain S and a stale opted-in S. S enters and never polls.
      - Advance StaleWaiterAfter+1ms. Opted-in X enters and waits.
      - Advance BotWindow-1ms: X polls and still waits.
      - Advance 1ms: X polls and is matched with PartnerIsBot true.
      - Exactly 1 "sw:sess:" key, a BotPaired delta of 1, and S's poll gets 410.
    - TestWaitLeaveVsArrivalRace, 50 iterations, each with a fresh newBotRig.
      - A enters plain. Concurrently, A's POST /v1/wait/leave and B's POST /v1/enter run, through doRaw, a start channel and a WaitGroup.
      - Both return 200 and the leave status is left or dissolved.
      - B's state is matched if and only if the leave status is dissolved. Every iteration ends with 0 "sw:sess:" keys and A's poll gets 410.
      - Matched branch: B's GET /v1/session/{id} gets 410 and "sw:tok:" count is 0.
      - Waiting branch: B's poll waits. Then C enters and is matched, and B's next poll shows C's session id.
    - TestWaitLeaveVsBotClaimRace, 50 iterations.
      - Opted-in A enters. Advance BotWindow-1ms, A polls and waits, then advance 1ms.
      - Concurrently, A's GET /v1/waiting and A's POST /v1/wait/leave run. The poll returns 200 or 410, never 500. The leave returns 200, left or dissolved.
      - Every iteration ends with 0 keys for "sw:sess:", "sw:tok:", "sw:wait:" and "sw:queue:".
    - TestHumanVsBotRaceSingleSession, modified in bot_test.go:
      - Before the race, advance BotWindow-1ms and A polls, asserting waiting. Then advance 1ms.
      - A is now a live, polling waiter, as a real client is. Every existing assertion stays unchanged.
  </behavior>
  <action>
    Write the new wait_test.go tests and the TestHumanVsBotRaceSingleSession precondition first.

    Why that precondition change is required, not a weakening: the test's waiter never polled during the 25 s jump. Under the new rule that is indistinguishable from an abandoned waiter, and the race under test stays human-arrival versus bot-claim. Put that reason in a comment.

    Concurrency tests use doRaw and t.Errorf only inside goroutines. Every window is crossed with b.clock.Advance; miniredis TTLs move only through b.mr.FastForward. No wall-clock sleeps anywhere.

    (1) store.go:
    - Add LastPolledAt to WaitEntry, documented as liveness only, never an identifier, living only on the TTL-bound entry.
    - Add LastSeenAt, UpdateWait, DropWait and BindWaiter exactly as the interfaces block specifies.
    - Remove SaveWait, since UpdateWait replaces it.
    - Every doc comment states why the write is conditional: SET XX, and KEEPTTL for the wait record. A leave, stale drop or dissolve may already have deleted the key, and recreating it would break ephemerality and resurrect a departed waiter. KEEPTTL keeps the 15-minute bound that privacy.html states.
    - Add no key helper and no new "sw: literal.

    (2) matchmaker.go:
    - Add StaleWaiterAfter with a [TUNABLE] doc comment covering: about 3x the client's 3 s waiting poll (AppModel.defaultPollInterval, plan.v1.md §10) plus slack; a backgrounded app stops polling and is treated as gone; revisit when APNs push lands.
    - Turn Enter into a loop over PopWaiter. NotFound means enqueue, exactly as today, carrying allowBot and now. That is why a stale waiter never delays an opted-in arriver's own bot window: the arriver's EnqueuedAt is its own arrival time.
    - A popped waiter with now.UnixMilli() minus LastSeenAt() greater than StaleWaiterAfter.Milliseconds() (strictly greater, so the boundary counts as live) is stale. LPOP already made this call its sole owner. Call DropWait best-effort (WaitTTL is the backstop), increment metrics.StaleWaitersDropped, and continue the loop. Each LPOP stays atomic per entry.
    - Otherwise call pair(). A false bound result also continues the loop: the waiter left mid-pairing.
    - pair():
      - Use waiter.LastSeenAt() for the waiter's LastSeen.
      - After SaveSession, bind the waiter's ref with BindWaiter in place of the unconditional SetRef. If that returns false, DeleteSession the just-saved session and return (nil, false, nil).
      - Then SetRef the arriver as today, and record MatchedSessionID through UpdateWait, ignoring the bool.
    - PairWithBot: after SaveSession, bind with BindWaiter. If that returns false, DeleteSession the session, DelWait best-effort, and return (nil, false, nil), so the handler answers waiting to a client that has already gone.

    (3) gateway.go handleWaiting:
    - In the KindWait branch, when MatchedSessionID is empty and before the bot-claim check, set wfe.LastPolledAt to s.now().UnixMilli() and call s.st.UpdateWait. On error, log at Warn ("wait touch failed") without the token.
    - Never touch EnqueuedAt, because it anchors the bot window.
    - In the matched-migration lines, replace the unconditional SetRef with BindWaiter. False gives 410 "session_gone" "your wait has ended"; an error goes to s.fail.
    - A touch that overwrites MatchedSessionID with an empty value after a concurrent pair is benign, because pair binds the token ref before writing MatchedSessionID and handleWaiting reads the ref first. Say so in a comment.

    (4) plan.v1.md:
    - §6: add lastPolledAt to the sw:wait row's field list. Under the table, add one sentence: an arriver drops a waiter whose last poll (or enqueue) is older than the liveness window (10 s, about 3x the 3 s poll).
    - §7: after the GET /v1/waiting section, add a "POST /v1/wait/leave" section. Bearer only, no body. It answers {"status":"left"}, or {"status":"dissolved"} when a match landed first, and 410 session_gone when there is nothing to leave.
  </action>
  <verify>
    <automated>OUT=$(cd server && go test -race -count=1 -v -run 'TestWaitLeave|TestStaleWaiter|TestPollingKeepsWaiterLive|TestHumanVsBotRaceSingleSession|TestOverlappingOptedInHumansPairTogether|TestMatchRaceSingleSession|TestBotFallbackTracer' ./internal/gateway/) && ( for t in TestWaitLeaveTracer TestWaitLeaveAfterMatchDissolves TestWaitLeaveVsArrivalRace TestWaitLeaveVsBotClaimRace TestStaleWaiterDroppedAtPairTime TestStaleWaiterDoesNotBlockOptedInArrival TestPollingKeepsWaiterLive TestHumanVsBotRaceSingleSession TestOverlappingOptedInHumansPairTogether TestMatchRaceSingleSession TestBotFallbackTracer; do printf '%s\n' "$OUT" | grep -q "^--- PASS: $t " || { echo "missing or failing: $t" >&2; exit 1; }; done ) && (cd server && go test -race -count=3 ./internal/gateway/ && go test -race -count=1 ./... && go vet ./...) && test -z "$(gofmt -l server/)" && grep -qF 'StaleWaiterAfter' server/internal/matchmaker/matchmaker.go && grep -qF 'LastPolledAt' server/internal/store/store.go && grep -qF 'func (s *Store) BindWaiter(' server/internal/store/store.go && grep -qF 'func (s *Store) UpdateWait(' server/internal/store/store.go && grep -qF '/v1/wait/leave' plan.v1.md && grep -qF 'lastPolledAt' plan.v1.md && test "$(grep -o '"sw:' server/internal/store/store.go | wc -l | tr -d ' ')" = 5</automated>
    Baselines at HEAD: StaleWaiterAfter 0, LastPolledAt 0, BindWaiter 0, UpdateWait 0, plan.v1.md /v1/wait/leave 0, lastPolledAt 0. The "sw: count is 5, an invariant. -count=3 on the gateway package repeats the 50-iteration race tests to shake out interleavings.
  </verify>
  <done>An arriver drops a waiter that stopped polling more than 10 s ago and never pairs with it. A polling waiter stays live indefinitely, and a poll never extends WaitTTL. An opted-in arriver meets the robot poet at its own window even when only stale waiters were queued. A wait-leave racing a human arrival or a bot claim never leaves a live session with the departed waiter, never yields two sessions, and never 500s, repeated three times under -race. TestHumanVsBotRaceSingleSession still pins exactly one session with a live waiter. plan.v1.md documents the endpoint and the liveness field. The full server suite, vet and gofmt are clean, and store.go keeps exactly 5 "sw: literals.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| iOS client to POST /v1/wait/leave and GET /v1/waiting | Untrusted. The only credential is a 32-byte bearer participant token; request timing and concurrency are attacker-controlled. |
| Concurrent handlers to Redis | Several goroutines (an arrival's pair, a waiter's own bot claim, the leave, a poll's touch) read and write the same waiter's token ref and wait record. Atomicity comes only from single Redis commands, SET XX, and WATCH/MULTI. |
| Local repo to origin/main and Fly | A push that touches server/** auto-deploys via .github/workflows/fly-deploy.yml. |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-jhu-01 | Spoofing / Elevation of privilege | handleWaitLeave | medium | mitigate | The route takes no path id; it acts only on the ref resolved from the caller's own bearer token, so there is no IDOR. A missing bearer gives 401 no_token, and an unknown or already-used token gives 410. Dissolving a matched session through this route grants nothing beyond what POST /v1/session/{id}/leave already allows the same token. Pinned by TestWaitLeaveErrors and TestWaitLeaveAfterMatchDissolves. |
| T-jhu-02 | Tampering / Denial of service (partner trapped in a dead session) | matchmaker.pair, PairWithBot, LeaveWait; store.BindWaiter, DropWaitIfUnbound | high | mitigate | The waiter's token ref is the single ownership record. Every bind of it to a session is SET XX, and the leave deletes it only through a WATCH compare-and-delete while it still points at the wait. Exactly one side wins: a failed bind tears down the session it just built, and a lost delete hands back the bound session for dissolution. Pinned by TestWaitLeaveVsArrivalRace and TestWaitLeaveVsBotClaimRace (50 iterations, -race, run 3 times) with 0 session keys at the end of every iteration. |
| T-jhu-03 | Information disclosure / Tampering (ephemerality) | store.UpdateWait, BindWaiter; handleWaiting touch | medium | mitigate | No new key class: the store.go "sw: literal count stays 5 (gated). LastPolledAt is a timestamp on the existing TTL-bound wait entry and is never returned to clients. Post-creation writes are conditional (SET XX), and the wait record also keeps its TTL (KEEPTTL), so a deleted wait record or ref is never resurrected and WaitTTL (the "15 minutes" in privacy.html, pinned by TestPrivacyPageMatchesCode) is never extended. Pinned by TestPollingKeepsWaiterLive's TTL check and the zero-key assertions. Logs never carry tokens. |
| T-jhu-04 | Denial of service (flooding the new endpoint) | POST /v1/wait/leave | low | accept | The existing per-IP token bucket and 16 KiB body cap already wrap every route, and each call is a bounded handful of O(1) Redis commands. No new limiter is needed at ASVS L1. |
| T-jhu-05 | Denial of service (arrival cost from a queue of ghosts) | matchmaker.Enter stale-skip loop | low | accept | Each stale entry is LPOPed and dropped permanently, so total skip work is bounded by entries ever enqueued (amortized O(1) per enter). Before this change each ghost cost a whole dead session instead. |
| T-jhu-06 | Spoofing (a client fakes liveness by polling) | handleWaiting touch | low | accept | Polling is the definition of liveness. A client that polls but never writes only holds its own place, exactly as before this change. A partner it pairs with can leave a session today and gains a Compose escape in sibling item 261029-jhv. |
| T-jhu-07 | Repudiation | wait-leave | low | accept | No per-participant audit trail, by the anonymity design. Only aggregate counters (sw_wait_left_total, sw_stale_waiters_dropped_total) are recorded. |
| T-jhu-SC | Tampering | npm/pip/cargo/go/SPM installs | high | mitigate | No package installs in this plan. go.mod and go.sum must be unchanged (git diff gate in verification), and the iOS app stays at zero third-party dependencies. The package-legitimacy gate therefore has nothing to check, and no human checkpoint is needed. |
</threat_model>

<verification>
Run from the repo root, after all three tasks:
- (cd server && go test -race -count=1 ./... && go vet ./...) and test -z "$(gofmt -l server/)"
- scripts/test-ios.sh exits 0 (PASS from the xcresult summary)
- git diff --quiet HEAD -- server/go.mod server/go.sum (no dependency change, T-jhu-SC)
- test "$(grep -o '"sw:' server/internal/store/store.go | wc -l | tr -d ' ')" = 5 (no new key class)
- The path literal /v1/wait/leave appears in both server/internal/gateway/gateway.go and ios/Strangewords/Net/APIClient.swift (wire parity)
- Nothing is pushed to origin. A push touching server/** auto-deploys. When this ships, deploy the server before (or with) the iOS build that calls leaveWait. An older server 404s the call, which the client ignores, so neither order breaks anything.
</verification>

<success_criteria>
- OBS-1 is closed for both production incidents. A deploy-check ghost (never polls) is dropped by the first arriver after 10 s. A user who steps back out and re-enters waits instead of pairing with their own ghost.
- A pre-match exit from iOS reaches the server through leaveWait. A mid-session exit still uses session leave.
- Leave racing an arrival or a bot claim never strands a partner (race tests green under -race x3). The opted-in robot-poet window is unaffected.
- The full server and iOS suites pass. Anonymity invariants hold: 5 key literals, no resurrection, no extended TTL, no token logging, no new dependency.
</success_criteria>

<output>
Create `.planning/quick/261029-jhu-server-wire-add-a-wait-leave-path-so-abandoned-waiters-never/261029-jhu-SUMMARY.md` when done. Record:
- the StaleWaiterAfter value;
- the intentional rename of the OBS-1 pin test;
- the TestHumanVsBotRaceSingleSession precondition change and why;
- the backgrounded-waiter behavior change;
- that the todo .planning/todos/pending/2026-10-27-abandoned-waiters-dead-pair-with-next-arriver.md is resolved, for the close-out step to move.
</output>
