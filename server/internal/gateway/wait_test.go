package gateway

import (
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"

	"strangewords/internal/matchmaker"
	"strangewords/internal/metrics"
	"strangewords/internal/store"
)

// leaveWait POSTs /v1/wait/leave for token and returns status and raw body.
func (b *botRig) leaveWait(t *testing.T, token string) (int, []byte) {
	t.Helper()
	return b.do(t, "POST", "/v1/wait/leave", token, nil)
}

// TestWaitLeaveTracer is the OBS-1 tracer: a waiter who steps back out is gone
// from the queue, the wait record and the token ref, so a re-entering device
// waits rather than pairing with its own ghost.
func TestWaitLeaveTracer(t *testing.T) {
	b := newBotRig(t, nil)
	left0 := testutil.ToFloat64(metrics.WaitLeft)

	a, _ := b.enterWith(t, nil)
	if a.State != "waiting" {
		t.Fatalf("A should wait, got %q", a.State)
	}

	code, raw := b.leaveWait(t, a.ParticipantToken)
	if code != http.StatusOK || !strings.Contains(string(raw), `"status":"left"`) {
		t.Fatalf("wait-leave: %d %s", code, raw)
	}
	for _, p := range []string{"sw:wait:", "sw:tok:", "sw:queue:"} {
		if n := countKeys(b.mr, p); n != 0 {
			t.Fatalf("%d %q keys left behind", n, p)
		}
	}
	if code, _ := b.do(t, "GET", "/v1/waiting", a.ParticipantToken, nil); code != http.StatusGone {
		t.Fatalf("poll after leave: want 410, got %d", code)
	}
	if d := testutil.ToFloat64(metrics.WaitLeft) - left0; d != 1 {
		t.Fatalf("WaitLeft delta = %v, want 1", d)
	}

	// The same device re-enters: it must wait, not pair with its ghost.
	a2, raw2 := b.enterWith(t, nil)
	if a2.State != "waiting" {
		t.Fatalf("re-entry should wait, got %s", raw2)
	}
	if n := countKeys(b.mr, "sw:sess:"); n != 0 {
		t.Fatalf("%d session keys after re-entry", n)
	}

	// The queue still pairs live waiters.
	bb, raw3 := b.enterWith(t, nil)
	if bb.State != "matched" || bb.Session == nil {
		t.Fatalf("B should match the live waiter, got %s", raw3)
	}
}

func TestWaitLeaveErrors(t *testing.T) {
	b := newBotRig(t, nil)

	code, raw := b.do(t, "POST", "/v1/wait/leave", "", nil)
	if code != http.StatusUnauthorized || !strings.Contains(string(raw), "no_token") {
		t.Fatalf("no bearer: %d %s", code, raw)
	}
	code, raw = b.leaveWait(t, "not-a-real-token")
	if code != http.StatusGone || !strings.Contains(string(raw), "session_gone") {
		t.Fatalf("unknown token: %d %s", code, raw)
	}

	a, _ := b.enterWith(t, nil)
	if code, raw := b.leaveWait(t, a.ParticipantToken); code != http.StatusOK {
		t.Fatalf("first leave: %d %s", code, raw)
	}
	if code, _ := b.leaveWait(t, a.ParticipantToken); code != http.StatusGone {
		t.Fatalf("second leave: want 410, got %d", code)
	}
}

// TestWaitLeaveAfterMatchDissolves: the match landed before the leave reached the
// server, so the leave dissolves the session and the partner sees 410.
func TestWaitLeaveAfterMatchDissolves(t *testing.T) {
	b := newBotRig(t, nil)
	left0 := testutil.ToFloat64(metrics.WaitLeft)
	diss0 := testutil.ToFloat64(metrics.Dissolved)

	a, _ := b.enterWith(t, nil)
	bb, _ := b.enterWith(t, nil)
	if bb.State != "matched" || bb.Session == nil {
		t.Fatalf("B should be matched, got %q", bb.State)
	}

	code, raw := b.leaveWait(t, a.ParticipantToken)
	if code != http.StatusOK || !strings.Contains(string(raw), `"status":"dissolved"`) {
		t.Fatalf("leave after match: %d %s", code, raw)
	}
	if code, _ := b.do(t, "GET", "/v1/session/"+bb.Session.SessionID, bb.ParticipantToken, nil); code != http.StatusGone {
		t.Fatalf("partner session: want 410, got %d", code)
	}
	if code, _ := b.do(t, "GET", "/v1/waiting", a.ParticipantToken, nil); code != http.StatusGone {
		t.Fatalf("A poll: want 410, got %d", code)
	}
	// The matched waiter's wait entry is the known Phase 3 leak (WaitTTL); not asserted.
	for _, p := range []string{"sw:sess:", "sw:tok:"} {
		if n := countKeys(b.mr, p); n != 0 {
			t.Fatalf("%d %q keys left behind", n, p)
		}
	}
	if d := testutil.ToFloat64(metrics.Dissolved) - diss0; d != 1 {
		t.Fatalf("Dissolved delta = %v, want 1", d)
	}
	if d := testutil.ToFloat64(metrics.WaitLeft) - left0; d != 1 {
		t.Fatalf("WaitLeft delta = %v, want 1", d)
	}
}

// TestWaitLeaveBeforeBotWindow: an opted-in waiter who leaves is never paired
// with the robot poet afterwards.
func TestWaitLeaveBeforeBotWindow(t *testing.T) {
	b := newBotRig(t, nil)
	paired0 := testutil.ToFloat64(metrics.BotPaired)

	a, _ := b.enterWith(t, map[string]any{"allowBot": true})
	if code, raw := b.leaveWait(t, a.ParticipantToken); code != http.StatusOK || !strings.Contains(string(raw), `"status":"left"`) {
		t.Fatalf("leave: %d %s", code, raw)
	}
	b.clock.Advance(b.cfg.BotWindow)
	if code, _ := b.do(t, "GET", "/v1/waiting", a.ParticipantToken, nil); code != http.StatusGone {
		t.Fatalf("poll after window: want 410, got %d", code)
	}
	x, raw := b.enterWith(t, map[string]any{"allowBot": true})
	if x.State != "waiting" {
		t.Fatalf("X should wait, got %s", raw)
	}
	if d := testutil.ToFloat64(metrics.BotPaired) - paired0; d != 0 {
		t.Fatalf("BotPaired delta = %v, want 0", d)
	}
	if n := countKeys(b.mr, "sw:sess:"); n != 0 {
		t.Fatalf("%d session keys", n)
	}
}

// TestStaleWaiterDroppedAtPairTime: an arriver drops a queued waiter that has
// not polled within matchmaker.StaleWaiterAfter, and pairs with the next live one.
func TestStaleWaiterDroppedAtPairTime(t *testing.T) {
	t.Run("live at the boundary", func(t *testing.T) {
		b := newBotRig(t, nil)
		dropped0 := testutil.ToFloat64(metrics.StaleWaitersDropped)

		a, _ := b.enterWith(t, nil)
		b.clock.Advance(matchmaker.StaleWaiterAfter)
		bb, raw := b.enterWith(t, nil)
		if bb.State != "matched" || bb.Session == nil {
			t.Fatalf("exactly at the window A is still live; B should match, got %s", raw)
		}
		wr, rawA := b.poll(t, a.ParticipantToken)
		if wr.State != "matched" || wr.Session == nil || wr.Session.SessionID != bb.Session.SessionID {
			t.Fatalf("A should share B's session, got %s", rawA)
		}
		if d := testutil.ToFloat64(metrics.StaleWaitersDropped) - dropped0; d != 0 {
			t.Fatalf("StaleWaitersDropped delta = %v, want 0", d)
		}
	})

	t.Run("stale one millisecond later", func(t *testing.T) {
		b := newBotRig(t, nil)
		dropped0 := testutil.ToFloat64(metrics.StaleWaitersDropped)

		a, _ := b.enterWith(t, nil)
		b.clock.Advance(matchmaker.StaleWaiterAfter + time.Millisecond)
		bb, raw := b.enterWith(t, nil)
		if bb.State != "waiting" {
			t.Fatalf("A is stale; B should wait, got %s", raw)
		}
		if code, _ := b.do(t, "GET", "/v1/waiting", a.ParticipantToken, nil); code != http.StatusGone {
			t.Fatalf("stale A poll: want 410, got %d", code)
		}
		if d := testutil.ToFloat64(metrics.StaleWaitersDropped) - dropped0; d != 1 {
			t.Fatalf("StaleWaitersDropped delta = %v, want 1", d)
		}
		if n := countKeys(b.mr, "sw:wait:"); n != 1 {
			t.Fatalf("want 1 wait key (B's), got %d", n)
		}
		if n := countKeys(b.mr, "sw:tok:"); n != 1 {
			t.Fatalf("want 1 tok key (B's), got %d", n)
		}

		c, rawC := b.enterWith(t, nil)
		if c.State != "matched" || c.Session == nil {
			t.Fatalf("C should match B, got %s", rawC)
		}
		wr, rawB := b.poll(t, bb.ParticipantToken)
		if wr.State != "matched" || wr.Session == nil || wr.Session.SessionID != c.Session.SessionID {
			t.Fatalf("B should be in C's session, got %s", rawB)
		}
	})
}

// TestPollingKeepsWaiterLive: a waiter that keeps polling is never dropped,
// however long it waits, and a poll never extends WaitTTL.
func TestPollingKeepsWaiterLive(t *testing.T) {
	b := newBotRig(t, nil)
	a, _ := b.enterWith(t, nil)

	b.mr.FastForward(time.Minute)
	b.poll(t, a.ParticipantToken)
	if got, want := b.mr.TTL("sw:wait:"+a.WaitID), store.WaitTTL-time.Minute; got != want {
		t.Fatalf("wait TTL after a poll = %v, want %v (a poll must not extend it)", got, want)
	}

	for i := 0; i < 5; i++ {
		b.clock.Advance(3 * time.Second)
		if wr, raw := b.poll(t, a.ParticipantToken); wr.State != "waiting" {
			t.Fatalf("round %d: expected waiting, got %s", i, raw)
		}
	}
	bb, raw := b.enterWith(t, nil)
	if bb.State != "matched" || bb.Session == nil {
		t.Fatalf("B should match the polling waiter, got %s", raw)
	}
	wr, rawA := b.poll(t, a.ParticipantToken)
	if wr.State != "matched" || wr.Session == nil || wr.Session.SessionID != bb.Session.SessionID {
		t.Fatalf("A should be in B's session, got %s", rawA)
	}
}

// TestStaleWaiterDoesNotBlockOptedInArrival: a stale waiter ahead in the queue
// never delays or blocks an opted-in arriver's own robot-poet window.
func TestStaleWaiterDoesNotBlockOptedInArrival(t *testing.T) {
	for _, tc := range []struct {
		name    string
		sOptsIn bool
	}{{"stale plain waiter", false}, {"stale opted-in waiter", true}} {
		t.Run(tc.name, func(t *testing.T) {
			b := newBotRig(t, nil)
			paired0 := testutil.ToFloat64(metrics.BotPaired)

			s, _ := b.enterWith(t, map[string]any{"allowBot": tc.sOptsIn})
			b.clock.Advance(matchmaker.StaleWaiterAfter + time.Millisecond)
			x, raw := b.enterWith(t, map[string]any{"allowBot": true})
			if x.State != "waiting" {
				t.Fatalf("X should wait, got %s", raw)
			}

			b.clock.Advance(b.cfg.BotWindow - time.Millisecond)
			if wr, raw := b.poll(t, x.ParticipantToken); wr.State != "waiting" {
				t.Fatalf("1ms before X's window must still wait, got %s", raw)
			}
			b.clock.Advance(time.Millisecond)
			wr, raw := b.poll(t, x.ParticipantToken)
			if wr.State != "matched" || wr.Session == nil || !wr.Session.PartnerIsBot {
				t.Fatalf("X should meet the robot poet exactly at its own window, got %s", raw)
			}
			if n := countKeys(b.mr, "sw:sess:"); n != 1 {
				t.Fatalf("want exactly 1 session key, got %d", n)
			}
			if d := testutil.ToFloat64(metrics.BotPaired) - paired0; d != 1 {
				t.Fatalf("BotPaired delta = %v, want 1", d)
			}
			if code, _ := b.do(t, "GET", "/v1/waiting", s.ParticipantToken, nil); code != http.StatusGone {
				t.Fatalf("stale S poll: want 410, got %d", code)
			}
		})
	}
}

// TestWaitLeaveVsArrivalRace: a wait-leave racing a human arrival never leaves a
// live session holding the departed waiter. B is matched iff the leave reported
// dissolved.
func TestWaitLeaveVsArrivalRace(t *testing.T) {
	for i := 0; i < 50; i++ {
		b := newBotRig(t, nil)
		a, _ := b.enterWith(t, nil)

		var (
			wg        sync.WaitGroup
			start     = make(chan struct{})
			leaveCode int
			leaveRaw  []byte
			bEnter    enterResp
			bEnterOK  bool
		)
		wg.Add(2)
		go func() {
			defer wg.Done()
			<-start
			code, raw, err := b.doRaw("POST", "/v1/wait/leave", a.ParticipantToken, nil)
			if err != nil {
				t.Errorf("iter %d: leave: %v", i, err)
			}
			leaveCode, leaveRaw = code, raw
		}()
		go func() {
			defer wg.Done()
			<-start
			code, raw, err := b.doRaw("POST", "/v1/enter", "", map[string]any{})
			if err != nil || code != http.StatusOK {
				t.Errorf("iter %d: B enter: %d %v %s", i, code, err, raw)
				return
			}
			if err := json.Unmarshal(raw, &bEnter); err != nil {
				t.Errorf("iter %d: B enter decode: %v", i, err)
				return
			}
			bEnterOK = true
		}()
		close(start)
		wg.Wait()
		if t.Failed() || !bEnterOK {
			t.Fatalf("iter %d: concurrent requests failed", i)
		}
		if leaveCode != http.StatusOK {
			t.Fatalf("iter %d: leave status %d %s", i, leaveCode, leaveRaw)
		}
		dissolved := strings.Contains(string(leaveRaw), `"status":"dissolved"`)
		if !dissolved && !strings.Contains(string(leaveRaw), `"status":"left"`) {
			t.Fatalf("iter %d: unexpected leave body %s", i, leaveRaw)
		}
		if matched := bEnter.State == "matched"; matched != dissolved {
			t.Fatalf("iter %d: B state %q but leave said %s", i, bEnter.State, leaveRaw)
		}
		if n := countKeys(b.mr, "sw:sess:"); n != 0 {
			t.Fatalf("iter %d: %d session keys left", i, n)
		}
		if code, _ := b.do(t, "GET", "/v1/waiting", a.ParticipantToken, nil); code != http.StatusGone {
			t.Fatalf("iter %d: A poll: want 410, got %d", i, code)
		}

		if dissolved {
			if code, _ := b.do(t, "GET", "/v1/session/"+bEnter.Session.SessionID, bEnter.ParticipantToken, nil); code != http.StatusGone {
				t.Fatalf("iter %d: B session: want 410, got %d", i, code)
			}
			if n := countKeys(b.mr, "sw:tok:"); n != 0 {
				t.Fatalf("iter %d: %d tok keys left", i, n)
			}
			continue
		}
		if wr, raw := b.poll(t, bEnter.ParticipantToken); wr.State != "waiting" {
			t.Fatalf("iter %d: B should wait, got %s", i, raw)
		}
		c, rawC := b.enterWith(t, nil)
		if c.State != "matched" || c.Session == nil {
			t.Fatalf("iter %d: C should match B, got %s", i, rawC)
		}
		wr, rawB := b.poll(t, bEnter.ParticipantToken)
		if wr.State != "matched" || wr.Session == nil || wr.Session.SessionID != c.Session.SessionID {
			t.Fatalf("iter %d: B should be in C's session, got %s", i, rawB)
		}
	}
}

// TestWaitLeaveVsBotClaimRace: a wait-leave racing the waiter's own bot claim at
// the window boundary never 500s and always ends with no keys at all.
func TestWaitLeaveVsBotClaimRace(t *testing.T) {
	for i := 0; i < 50; i++ {
		b := newBotRig(t, nil)
		a, _ := b.enterWith(t, map[string]any{"allowBot": true})
		b.clock.Advance(b.cfg.BotWindow - time.Millisecond)
		if wr, raw := b.poll(t, a.ParticipantToken); wr.State != "waiting" {
			t.Fatalf("iter %d: expected waiting before the window, got %s", i, raw)
		}
		b.clock.Advance(time.Millisecond)

		var (
			wg        sync.WaitGroup
			start     = make(chan struct{})
			pollCode  int
			leaveCode int
			leaveRaw  []byte
		)
		wg.Add(2)
		go func() {
			defer wg.Done()
			<-start
			code, _, err := b.doRaw("GET", "/v1/waiting", a.ParticipantToken, nil)
			if err != nil {
				t.Errorf("iter %d: poll: %v", i, err)
			}
			pollCode = code
		}()
		go func() {
			defer wg.Done()
			<-start
			code, raw, err := b.doRaw("POST", "/v1/wait/leave", a.ParticipantToken, nil)
			if err != nil {
				t.Errorf("iter %d: leave: %v", i, err)
			}
			leaveCode, leaveRaw = code, raw
		}()
		close(start)
		wg.Wait()
		if t.Failed() {
			t.Fatalf("iter %d: concurrent requests failed", i)
		}

		if pollCode != http.StatusOK && pollCode != http.StatusGone {
			t.Fatalf("iter %d: poll status %d", i, pollCode)
		}
		if leaveCode != http.StatusOK ||
			(!strings.Contains(string(leaveRaw), `"status":"left"`) && !strings.Contains(string(leaveRaw), `"status":"dissolved"`)) {
			t.Fatalf("iter %d: leave: %d %s", i, leaveCode, leaveRaw)
		}
		for _, p := range []string{"sw:sess:", "sw:tok:", "sw:wait:", "sw:queue:"} {
			if n := countKeys(b.mr, p); n != 0 {
				t.Fatalf("iter %d: %d %q keys left", i, n, p)
			}
		}
	}
}
