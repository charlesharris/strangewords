package gateway

import (
	"context"
	"errors"
	"fmt"
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
	"strangewords/internal/poet"
	"strangewords/internal/push"
	"strangewords/internal/sessions"
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
	st    *store.Store
	srv   *Server
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
		st:    st,
		srv:   srv,
	}
}

// restart builds a second Server (new store, matchmaker, HTTP listener) over the
// same miniredis, config and clock: a stand-in for a server restart mid-poem.
func (b *botRig) restart(t *testing.T) *rig {
	t.Helper()
	rdb := redis.NewClient(&redis.Options{Addr: b.mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	st := store.New(rdb)
	mm := matchmaker.New(st)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := New(st, mm, push.Noop{Log: log}, moderation.LogSink{Log: log}, log, b.cfg)
	srv.now = b.clock.Now
	ts := httptest.NewServer(srv.Routes())
	t.Cleanup(ts.Close)
	return &rig{ts: ts, mr: b.mr, cl: ts.Client()}
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

// getView GETs /v1/session/{id} through rig r and decodes the view.
func getView(t *testing.T, r *rig, token, id string) (sessions.View, []byte) {
	t.Helper()
	code, raw := r.do(t, "GET", "/v1/session/"+id, token, nil)
	if code != http.StatusOK {
		t.Fatalf("get session: %d %s", code, raw)
	}
	var v sessions.View
	mustJSON(t, raw, &v)
	return v, raw
}

// postLine submits a line through rig r and decodes the returned view.
func postLine(t *testing.T, r *rig, token, id string, line int, text, idem string) (sessions.View, []byte) {
	t.Helper()
	code, raw := r.do(t, "POST", "/v1/session/"+id+"/line", token,
		map[string]any{"line": line, "text": text, "idemKey": idem})
	if code != http.StatusOK {
		t.Fatalf("post line %d: %d %s", line, code, raw)
	}
	var v sessions.View
	mustJSON(t, raw, &v)
	return v, raw
}

func assertNoKeysWithPrefix(t *testing.T, mr *miniredis.Miniredis, prefix string) {
	t.Helper()
	for _, k := range mr.Keys() {
		if strings.HasPrefix(k, prefix) {
			t.Fatalf("left key %q behind", k)
		}
	}
}

// TestBotPoemCompletesAndLeavesNoKeys plays a whole haiku against the robot
// poet in both start orders: think time is honored, a long gap yields exactly
// one line per settle, a restarted server produces the next line, every bot
// line is clean and on target, and one dismiss leaves zero sw: keys.
func TestBotPoemCompletesAndLeavesNoKeys(t *testing.T) {
	human := []string{"an old silent pond", "a frog jumps into the pond", "splash silence again"}
	form := sessions.LookupForm("haiku")
	seenBotFirst, seenHumanFirst := false, false

	for iter := 0; iter < 64 && !(seenBotFirst && seenHumanFirst); iter++ {
		b := newBotRig(t, nil)
		er, _ := b.enterWith(t, map[string]any{"allowBot": true})
		tok := er.ParticipantToken
		b.clock.Advance(b.cfg.BotWindow)
		wr, raw := b.poll(t, tok)
		if wr.State != "matched" || wr.Session == nil || !wr.Session.PartnerIsBot {
			t.Fatalf("expected bot-matched view, got %s", raw)
		}
		view := *wr.Session
		if view.YourTurn {
			seenHumanFirst = true
		} else {
			seenBotFirst = true
		}
		restarted := b.restart(t)

		humanN := 0
		for guard := 0; view.Status == sessions.StatusActive; guard++ {
			if guard > 10 {
				t.Fatalf("poem did not finish: %+v", view)
			}
			if view.YourTurn {
				var raw []byte
				view, raw = postLine(t, b.rig, tok, view.SessionID, view.CurrentLine, human[humanN], fmt.Sprintf("h%d", humanN))
				if !strings.Contains(string(raw), `"partnerIsBot":true`) {
					t.Fatalf("line response lost partnerIsBot: %s", raw)
				}
				humanN++
				continue
			}
			before := len(view.Lines)
			// Think time honored: an immediate poll adds no line.
			v, _ := getView(t, b.rig, tok, view.SessionID)
			if len(v.Lines) != before {
				t.Fatalf("bot wrote before its think time: %q", v.Lines)
			}
			// A long gap (backgrounded app), served by a restarted server.
			b.clock.Advance(b.cfg.BotThink + 10*time.Minute)
			view, _ = getView(t, restarted, tok, view.SessionID)
			if len(view.Lines) != before+1 {
				t.Fatalf("expected exactly one new line after the gap, had %d now %d", before, len(view.Lines))
			}
			line := view.Lines[before]
			if got, err := sessions.CleanLine(line); err != nil || got != line {
				t.Fatalf("bot line %q not CleanLine-identical (%v)", line, err)
			}
			if want := *form.Targets[before]; poet.Count(line) != want {
				t.Fatalf("bot line %q counts %d, want %d", line, poet.Count(line), want)
			}
		}

		if len(view.Lines) != 3 || view.Status != sessions.StatusComplete || !view.PartnerIsBot {
			t.Fatalf("finished poem wrong: %+v", view)
		}
		code, raw := b.do(t, "POST", "/v1/session/"+view.SessionID+"/dismiss", tok, nil)
		if code != http.StatusOK || !strings.Contains(string(raw), `"dissolved"`) {
			t.Fatalf("single dismiss should dissolve: %d %s", code, raw)
		}
		if code, _ := b.do(t, "GET", "/v1/session/"+view.SessionID, tok, nil); code != http.StatusGone {
			t.Fatalf("after dissolution expected 410, got %d", code)
		}
		assertNoKeysWithPrefix(t, b.mr, "sw:")
	}
	if !seenBotFirst || !seenHumanFirst {
		t.Fatalf("start orders not both observed: botFirst=%v humanFirst=%v", seenBotFirst, seenHumanFirst)
	}
}

// dueBot opens a bot session with the given start index and advances until the
// bot's line k is due. It returns the rig, token, session id and k. The bot's
// line k is always followed by the human's line k+1.
func dueBot(t *testing.T, start int) (b *botRig, tok, id string, k int) {
	t.Helper()
	b = newBotRig(t, nil)
	er, _ := b.enterWith(t, map[string]any{"allowBot": true})
	tok = er.ParticipantToken
	b.clock.Advance(b.cfg.BotWindow)
	wr, raw := b.poll(t, tok)
	if wr.State != "matched" || wr.Session == nil {
		t.Fatalf("expected matched, got %s", raw)
	}
	id = wr.Session.SessionID
	// Force the start order so both are covered deterministically.
	sess, err := b.st.GetSession(context.Background(), id)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	sess.StartIndex = start
	if err := b.st.SaveSession(context.Background(), sess); err != nil {
		t.Fatalf("save: %v", err)
	}
	k = 0
	if start == 0 { // human writes line 0, then the bot's line 1 is next
		postLine(t, b.rig, tok, id, 0, "an old silent pond", "h0")
		k = 1
	}
	b.clock.Advance(b.cfg.BotThink)
	return b, tok, id, k
}

// TestStaleSettleDoesNotOverwriteHumanLine pins the interleaving where a poll
// loads on the bot's turn, another poll settles, the human writes the next
// line, and the first poll then tries to settle.
func TestStaleSettleDoesNotOverwriteHumanLine(t *testing.T) {
	const humanText = "a quiet kettle sings"
	ctx := context.Background()

	t.Run("stale handler load", func(t *testing.T) {
		for start := 0; start < 2; start++ {
			b, tok, id, k := dueBot(t, start)
			stale, err := b.st.GetSession(ctx, id) // poll A's load
			if err != nil {
				t.Fatalf("load: %v", err)
			}
			v, _ := getView(t, b.rig, tok, id) // poll B settles
			if len(v.Lines) != k+1 {
				t.Fatalf("start %d: poll B should settle line %d, lines %q", start, k, v.Lines)
			}
			postLine(t, b.rig, tok, id, k+1, humanText, "stale-h")

			got, err := b.srv.settleBot(ctx, stale)
			if err != nil {
				t.Fatalf("start %d: settleBot: %v", start, err)
			}
			stored, err := b.st.GetSession(ctx, id)
			if err != nil {
				t.Fatalf("reload: %v", err)
			}
			if len(stored.Lines) != k+2 || stored.Lines[k+1] != humanText || stored.CurrentLine != k+2 {
				t.Fatalf("start %d: human line lost: stored lines %q currentLine %d", start, stored.Lines, stored.CurrentLine)
			}
			if got.CurrentLine != stored.CurrentLine {
				t.Fatalf("start %d: settleBot returned currentLine %d, stored %d", start, got.CurrentLine, stored.CurrentLine)
			}
		}
	})

	t.Run("write inside the read-to-save window", func(t *testing.T) {
		for start := 0; start < 2; start++ {
			b, tok, id, k := dueBot(t, start)
			_, err := b.st.UpdateSession(ctx, id, func(fresh *sessions.Session) (time.Duration, bool) {
				getView(t, b.rig, tok, id) // poll B settles, writing the key
				postLine(t, b.rig, tok, id, k+1, humanText, "window-h")
				fresh.Lines = append(fresh.Lines, "stale settle line")
				fresh.CurrentLine++
				return store.SessionTTL, true
			})
			if !errors.Is(err, store.ErrConflict) {
				t.Fatalf("start %d: want store.ErrConflict, got %v", start, err)
			}
			stored, err := b.st.GetSession(ctx, id)
			if err != nil {
				t.Fatalf("reload: %v", err)
			}
			if len(stored.Lines) != k+2 || stored.Lines[k+1] != humanText {
				t.Fatalf("start %d: human line lost: stored lines %q", start, stored.Lines)
			}
			for _, l := range stored.Lines {
				if l == "stale settle line" {
					t.Fatalf("start %d: stale line was stored: %q", start, stored.Lines)
				}
			}
		}
	})
}
