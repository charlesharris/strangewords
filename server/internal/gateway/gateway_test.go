package gateway

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"strangewords/internal/config"
	"strangewords/internal/matchmaker"
	"strangewords/internal/push"
	"strangewords/internal/sessions"
	"strangewords/internal/store"
)

type rig struct {
	ts  *httptest.Server
	mr  *miniredis.Miniredis
	cl  *http.Client
}

func newRig(t *testing.T) *rig {
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
	srv := New(st, mm, push.Noop{Log: log}, log, config.Load())

	ts := httptest.NewServer(srv.Routes())
	t.Cleanup(ts.Close)
	return &rig{ts: ts, mr: mr, cl: ts.Client()}
}

// ---- response shapes ----

type enterResp struct {
	ParticipantToken string         `json:"participantToken"`
	State            string         `json:"state"`
	Session          *sessions.View `json:"session"`
	WaitID           string         `json:"waitId"`
}

type waitingResp struct {
	State   string         `json:"state"`
	Session *sessions.View `json:"session"`
}

func (r *rig) do(t *testing.T, method, path, token string, body any) (int, []byte) {
	t.Helper()
	var rdr io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, r.ts.URL+path, rdr)
	if err != nil {
		t.Fatalf("request: %v", err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := r.cl.Do(req)
	if err != nil {
		t.Fatalf("do: %v", err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, data
}

func (r *rig) enter(t *testing.T) enterResp {
	t.Helper()
	code, body := r.do(t, "POST", "/v1/enter", "", map[string]any{})
	if code != 200 {
		t.Fatalf("enter: status %d body %s", code, body)
	}
	var er enterResp
	mustJSON(t, body, &er)
	return er
}

func mustJSON(t *testing.T, b []byte, v any) {
	t.Helper()
	if err := json.Unmarshal(b, v); err != nil {
		t.Fatalf("unmarshal %s: %v", b, err)
	}
}

// match returns (tokenA waiter idx0, tokenB arriver idx1, B's matched view).
func (r *rig) match(t *testing.T) (string, string, sessions.View) {
	t.Helper()
	a := r.enter(t)
	if a.State != "waiting" {
		t.Fatalf("first enter should wait, got %q", a.State)
	}
	b := r.enter(t)
	if b.State != "matched" || b.Session == nil {
		t.Fatalf("second enter should match, got %q", b.State)
	}
	return a.ParticipantToken, b.ParticipantToken, *b.Session
}

func TestFullPoemHappyPath(t *testing.T) {
	r := newRig(t)
	tokenA, tokenB, view := r.match(t)
	tokens := map[int]string{0: tokenA, 1: tokenB}

	// The waiter learns it's matched by polling /waiting.
	code, body := r.do(t, "GET", "/v1/waiting", tokenA, nil)
	if code != 200 {
		t.Fatalf("waiting poll: %d %s", code, body)
	}
	var wr waitingResp
	mustJSON(t, body, &wr)
	if wr.State != "matched" || wr.Session == nil || wr.Session.You != 0 {
		t.Fatalf("waiter view wrong: %s", body)
	}

	lines := []string{"an old silent pond", "a frog jumps into the pond", "splash silence again"}
	for i := 0; i < 3; i++ {
		if view.Status != sessions.StatusActive {
			t.Fatalf("line %d: expected active, got %s", i, view.Status)
		}
		author := tokens[view.CurrentAuthor]
		code, body := r.do(t, "POST", "/v1/session/"+view.SessionID+"/line", author,
			map[string]any{"line": i, "text": lines[i], "idemKey": "k" + string(rune('0'+i))})
		if code != 200 {
			t.Fatalf("submit line %d: status %d body %s", i, code, body)
		}
		mustJSON(t, body, &view)
		if view.CurrentLine != i+1 {
			t.Fatalf("line %d: currentLine=%d want %d", i, view.CurrentLine, i+1)
		}
	}

	if view.Status != sessions.StatusComplete {
		t.Fatalf("after 3 lines expected complete, got %s", view.Status)
	}
	if strings.Join(view.Lines, "|") != strings.Join(lines, "|") {
		t.Fatalf("lines mismatch: %v", view.Lines)
	}

	// Both dismiss -> dissolved -> zero keys.
	r.do(t, "POST", "/v1/session/"+view.SessionID+"/dismiss", tokenA, nil)
	code, _ = r.do(t, "POST", "/v1/session/"+view.SessionID+"/dismiss", tokenB, nil)
	if code != 200 {
		t.Fatalf("dismiss: %d", code)
	}
	// A subsequent fetch should be gone.
	code, _ = r.do(t, "GET", "/v1/session/"+view.SessionID, tokenA, nil)
	if code != http.StatusGone {
		t.Fatalf("after dissolution expected 410, got %d", code)
	}
	assertNoSessionKeys(t, r.mr)
}

func TestTurnOrderViolations(t *testing.T) {
	r := newRig(t)
	tokenA, tokenB, view := r.match(t)
	tokens := map[int]string{0: tokenA, 1: tokenB}
	author := tokens[view.CurrentAuthor]
	other := tokens[1-view.CurrentAuthor]

	// Wrong person.
	code, body := r.do(t, "POST", "/v1/session/"+view.SessionID+"/line", other,
		map[string]any{"line": 0, "text": "not my turn"})
	if code != http.StatusConflict {
		t.Fatalf("not-your-turn: got %d %s", code, body)
	}

	// Right person, wrong line index.
	code, body = r.do(t, "POST", "/v1/session/"+view.SessionID+"/line", author,
		map[string]any{"line": 2, "text": "wrong line"})
	if code != http.StatusConflict {
		t.Fatalf("wrong-turn: got %d %s", code, body)
	}

	// Empty content is rejected.
	code, body = r.do(t, "POST", "/v1/session/"+view.SessionID+"/line", author,
		map[string]any{"line": 0, "text": "   "})
	if code != http.StatusUnprocessableEntity {
		t.Fatalf("content-rejected: got %d %s", code, body)
	}
}

func TestIdempotentResubmit(t *testing.T) {
	r := newRig(t)
	tokenA, tokenB, view := r.match(t)
	tokens := map[int]string{0: tokenA, 1: tokenB}
	author := tokens[view.CurrentAuthor]

	code, first := r.do(t, "POST", "/v1/session/"+view.SessionID+"/line", author,
		map[string]any{"line": 0, "text": "first words here", "idemKey": "dupe"})
	if code != 200 {
		t.Fatalf("first submit: %d %s", code, first)
	}
	// Replaying the same idemKey returns the original response verbatim, even
	// though it is no longer this token's turn.
	code, second := r.do(t, "POST", "/v1/session/"+view.SessionID+"/line", author,
		map[string]any{"line": 0, "text": "different text", "idemKey": "dupe"})
	if code != 200 {
		t.Fatalf("replay: %d %s", code, second)
	}
	if !bytes.Equal(first, second) {
		t.Fatalf("idempotent replay differed:\n%s\n%s", first, second)
	}
	var v sessions.View
	mustJSON(t, second, &v)
	if v.CurrentLine != 1 || len(v.Lines) != 1 {
		t.Fatalf("replay must not add a second line: %s", second)
	}
}

func TestLeaveDissolves(t *testing.T) {
	r := newRig(t)
	tokenA, tokenB, view := r.match(t)

	code, _ := r.do(t, "POST", "/v1/session/"+view.SessionID+"/leave", tokenA, nil)
	if code != 200 {
		t.Fatalf("leave: %d", code)
	}
	code, _ = r.do(t, "GET", "/v1/session/"+view.SessionID, tokenB, nil)
	if code != http.StatusGone {
		t.Fatalf("partner after leave expected 410, got %d", code)
	}
	assertNoSessionKeys(t, r.mr)
}

// TestMatchRaceSingleSession: with one waiter, two concurrent arrivals must
// produce exactly one match and one new waiter — never two sessions.
func TestMatchRaceSingleSession(t *testing.T) {
	r := newRig(t)
	first := r.enter(t)
	if first.State != "waiting" {
		t.Fatalf("expected waiting, got %q", first.State)
	}

	var wg sync.WaitGroup
	results := make([]string, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			code, body := r.do(t, "POST", "/v1/enter", "", map[string]any{})
			if code != 200 {
				t.Errorf("concurrent enter: %d", code)
				return
			}
			var er enterResp
			_ = json.Unmarshal(body, &er)
			results[i] = er.State
		}(i)
	}
	wg.Wait()

	matched, waiting := 0, 0
	for _, s := range results {
		switch s {
		case "matched":
			matched++
		case "waiting":
			waiting++
		}
	}
	if matched != 1 || waiting != 1 {
		t.Fatalf("race produced matched=%d waiting=%d (want 1/1): %v", matched, waiting, results)
	}
}

func assertNoSessionKeys(t *testing.T, mr *miniredis.Miniredis) {
	t.Helper()
	for _, k := range mr.Keys() {
		if strings.HasPrefix(k, "sw:sess:") || strings.HasPrefix(k, "sw:tok:") || strings.HasPrefix(k, "sw:idem:") {
			t.Fatalf("dissolved session left key %q", k)
		}
	}
}
