package gateway

import (
	"net/http"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"

	"strangewords/internal/metrics"
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
