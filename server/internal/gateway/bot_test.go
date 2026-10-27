package gateway

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/redis/go-redis/v9"

	"strangewords/internal/config"
	"strangewords/internal/matchmaker"
	"strangewords/internal/metrics"
	"strangewords/internal/moderation"
	"strangewords/internal/push"
	"strangewords/internal/store"
)

// fakeClock is a mutex-guarded manual clock so the 25 s bot window and the bot's
// think time are crossed by Advance, never by sleeping.
type fakeClock struct {
	mu sync.Mutex
	t  time.Time
}

func newFakeClock() *fakeClock {
	return &fakeClock{t: time.Date(2026, 10, 27, 12, 0, 0, 0, time.UTC)}
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

// botRig is a rig whose server runs on a fake clock and a mutable config.
type botRig struct {
	*rig
	cfg   config.Config
	clock *fakeClock
}

// newBotRig mirrors newRig's wiring but injects the clock before the HTTP
// server starts (srv.now is read by handlers, so setting it later would race).
func newBotRig(t *testing.T, mutate func(*config.Config)) *botRig {
	t.Helper()
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	t.Cleanup(mr.Close)

	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	st := store.New(rdb)
	mm := matchmaker.New(st)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	cfg := config.Load()
	cfg.RateRPS = 0 // the limiter keys on wall-clock time and is not under test
	if mutate != nil {
		mutate(&cfg)
	}
	clock := newFakeClock()
	srv := New(st, mm, push.Noop{Log: log}, moderation.LogSink{Log: log}, log, cfg)
	srv.now = clock.Now

	ts := httptest.NewServer(srv.Routes())
	t.Cleanup(ts.Close)
	return &botRig{
		rig:   &rig{ts: ts, mr: mr, cl: ts.Client()},
		cfg:   cfg,
		clock: clock,
	}
}

// enterWith posts /v1/enter with an arbitrary body (nil sends no body at all).
func (b *botRig) enterWith(t *testing.T, body any) (enterResp, []byte) {
	t.Helper()
	code, raw := b.do(t, "POST", "/v1/enter", "", body)
	if code != http.StatusOK {
		t.Fatalf("enter: status %d body %s", code, raw)
	}
	var er enterResp
	mustJSON(t, raw, &er)
	return er, raw
}

// poll GETs /v1/waiting for token and decodes the reply.
func (b *botRig) poll(t *testing.T, token string) (waitingResp, []byte) {
	t.Helper()
	code, raw := b.do(t, "GET", "/v1/waiting", token, nil)
	if code != http.StatusOK {
		t.Fatalf("waiting: status %d body %s", code, raw)
	}
	var wr waitingResp
	mustJSON(t, raw, &wr)
	return wr, raw
}

// TestBotFallbackTracer is the phase tracer: one opted-in waiter, one poll past
// the window, an atomic LREM claim, a bot-paired session, and partnerIsBot on
// every view of it.
func TestBotFallbackTracer(t *testing.T) {
	b := newBotRig(t, nil)
	paired0 := testutil.ToFloat64(metrics.BotPaired)
	matched0 := testutil.ToFloat64(metrics.Matched)

	er, _ := b.enterWith(t, map[string]any{"allowBot": true})
	if er.State != "waiting" {
		t.Fatalf("opted-in enter should wait, got %q", er.State)
	}

	b.clock.Advance(b.cfg.BotWindow - time.Millisecond)
	if wr, raw := b.poll(t, er.ParticipantToken); wr.State != "waiting" {
		t.Fatalf("1ms before the window must still wait, got %s", raw)
	}

	b.clock.Advance(time.Millisecond)
	wr, raw := b.poll(t, er.ParticipantToken)
	if wr.State != "matched" || wr.Session == nil {
		t.Fatalf("at the window expected matched, got %s", raw)
	}
	if wr.Session.You != 0 || wr.Session.ParticipantCount != 2 || !wr.Session.PartnerIsBot {
		t.Fatalf("bot-paired view wrong: %s", raw)
	}
	if !strings.Contains(string(raw), `"partnerIsBot":true`) {
		t.Fatalf("raw waiting body must carry partnerIsBot:true, got %s", raw)
	}

	code, raw := b.do(t, "GET", "/v1/session/"+wr.Session.SessionID, er.ParticipantToken, nil)
	if code != http.StatusOK {
		t.Fatalf("get session: %d %s", code, raw)
	}
	if !strings.Contains(string(raw), `"partnerIsBot":true`) {
		t.Fatalf("session body must carry partnerIsBot:true, got %s", raw)
	}

	for _, k := range b.mr.Keys() {
		if strings.HasPrefix(k, "sw:wait:") || strings.HasPrefix(k, "sw:queue:") {
			t.Fatalf("claim left key %q behind", k)
		}
	}
	if d := testutil.ToFloat64(metrics.BotPaired) - paired0; d != 1 {
		t.Fatalf("BotPaired delta = %v, want 1", d)
	}
	if d := testutil.ToFloat64(metrics.Matched) - matched0; d != 0 {
		t.Fatalf("Matched delta = %v, want 0", d)
	}
}
