package gateway

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/prometheus/client_golang/prometheus/testutil"

	"strangewords/internal/metrics"
	"strangewords/internal/poet"
	"strangewords/internal/sessions"
	"strangewords/internal/store"
)

// tradeFields decodes only the Phase 6 wire keys, straight off the response
// body. Tests read the contract from the JSON itself (route, key names, omitempty
// behavior), not through the server's own View struct.
type tradeFields struct {
	PoemNumber        int  `json:"poemNumber"`
	TradeOpen         bool `json:"tradeOpen"`
	YouWantTrade      bool `json:"youWantTrade"`
	PartnerWantsTrade bool `json:"partnerWantsTrade"`
}

func tradeOf(t *testing.T, raw []byte) tradeFields {
	t.Helper()
	var f tradeFields
	mustJSON(t, raw, &f)
	return f
}

// postTrade POSTs /v1/session/{id}/trade with no body.
func postTrade(r *rig, token, id string) (int, []byte) {
	code, raw, err := r.doRaw("POST", "/v1/session/"+id+"/trade", token, nil)
	if err != nil {
		return 0, []byte(err.Error())
	}
	return code, raw
}

func mustTrade(t *testing.T, r *rig, token, id string) (sessions.View, []byte) {
	t.Helper()
	code, raw := postTrade(r, token, id)
	if code != http.StatusOK {
		t.Fatalf("trade: %d %s", code, raw)
	}
	var v sessions.View
	mustJSON(t, raw, &v)
	return v, raw
}

// writePoem plays a whole poem between two humans, each line written by whoever
// the current view names as author. It returns the author index of every line,
// the final view and its raw body. prefix keeps idem keys unique per poem.
func writePoem(t *testing.T, r *rig, tokens map[int]string, v sessions.View, prefix string) ([]int, sessions.View, []byte) {
	t.Helper()
	texts := []string{"an old silent pond", "a frog jumps into the pond", "splash silence again"}
	var authors []int
	var raw []byte
	for i := 0; i < 3; i++ {
		if v.Status != sessions.StatusActive || v.CurrentLine != i {
			t.Fatalf("%s line %d: unexpected view %+v", prefix, i, v)
		}
		authors = append(authors, v.CurrentAuthor)
		v, raw = postLine(t, r, tokens[v.CurrentAuthor], v.SessionID, i, texts[i], fmt.Sprintf("%s%d", prefix, i))
	}
	return authors, v, raw
}

func sessKey(id string) string { return "sw:sess:" + id }

// assertEncounterGone asserts that a human-paired encounter left nothing behind:
// no session, token ref or cached response. The only key a human pairing may
// still hold is the original waiter's sw:wait: record, which predates the trade,
// is cleared only by its own WaitTTL (privacy.html: "erased after 15 minutes")
// and carries no poem content. Bot sessions drop it at pairing, so they assert
// the stricter assertNoKeysWithPrefix(t, mr, "sw:").
func assertEncounterGone(t *testing.T, mr *miniredis.Miniredis) {
	t.Helper()
	for _, k := range mr.Keys() {
		if strings.HasPrefix(k, "sw:wait:") {
			if ttl := mr.TTL(k); ttl <= 0 || ttl > store.WaitTTL {
				t.Fatalf("leftover wait record %q has TTL %v, want within (0, %v]", k, ttl, store.WaitTTL)
			}
			continue
		}
		t.Fatalf("encounter left key %q behind", k)
	}
}

// TestTradeTracer is the Phase 6 tracer: two humans write poem 1, one offers to
// trade back, the other's ask begins poem 2 with roles swapped and poem 1's
// retry cache purged, poem 2 reveals with no further trade, and dissolution
// leaves zero keys (D-01, D-02, D-03).
func TestTradeTracer(t *testing.T) {
	offered0 := testutil.ToFloat64(metrics.TradesOffered)
	begun0 := testutil.ToFloat64(metrics.TradesBegun)
	poems0 := testutil.ToFloat64(metrics.PoemsCompleted)
	dissolved0 := testutil.ToFloat64(metrics.Dissolved)

	r := newRig(t)
	tokA, tokB, view := r.match(t)
	tokens := map[int]string{0: tokA, 1: tokB}
	id := view.SessionID

	// Poem 1.
	authors1, view, raw := writePoem(t, r, tokens, view, "k")
	opener := authors1[0]
	other := 1 - opener
	if authors1[1] != other || authors1[2] != opener {
		t.Fatalf("poem 1 authors = %v", authors1)
	}
	if view.Status != sessions.StatusComplete {
		t.Fatalf("poem 1 should be complete: %+v", view)
	}
	body := string(raw)
	if !strings.Contains(body, `"tradeOpen":true`) || !strings.Contains(body, `"poemNumber":1`) {
		t.Fatalf("complete poem 1 view must offer the trade: %s", body)
	}
	if strings.Contains(body, `"youWantTrade"`) {
		t.Fatalf("youWantTrade must be omitted until set: %s", body)
	}
	if n := countKeys(r.mr, "sw:idem:"); n != 3 {
		t.Fatalf("poem 1 should hold 3 cached responses, got %d", n)
	}

	// The opener offers. Its own view stays on the reveal.
	v, raw := mustTrade(t, r, tokens[opener], id)
	tf := tradeOf(t, raw)
	if v.Status != sessions.StatusComplete || !tf.YouWantTrade || tf.PartnerWantsTrade || !tf.TradeOpen {
		t.Fatalf("offer view wrong: %s", raw)
	}
	if got := r.mr.TTL(sessKey(id)); got != store.RevealTTL {
		t.Fatalf("offer TTL = %v, want RevealTTL %v", got, store.RevealTTL)
	}

	// The partner sees the offer.
	_, raw = getView(t, r, tokens[other], id)
	tf = tradeOf(t, raw)
	if !tf.PartnerWantsTrade || tf.YouWantTrade {
		t.Fatalf("partner view should show the offer: %s", raw)
	}

	// The partner accepts: poem 2 begins in the same session, roles swapped.
	v, raw = mustTrade(t, r, tokens[other], id)
	tf = tradeOf(t, raw)
	if v.Status != sessions.StatusActive || tf.PoemNumber != 2 || v.CurrentLine != 0 || len(v.Lines) != 0 || tf.TradeOpen {
		t.Fatalf("poem 2 should be active and empty: %s", raw)
	}
	if v.CurrentAuthor != other {
		t.Fatalf("poem 2 line 0 author = %d, want the non-opener %d", v.CurrentAuthor, other)
	}
	if got := r.mr.TTL(sessKey(id)); got != store.SessionTTL {
		t.Fatalf("poem 2 TTL = %v, want SessionTTL %v", got, store.SessionTTL)
	}
	if n := countKeys(r.mr, "sw:idem:"); n != 0 {
		t.Fatalf("poem 1's cache should be purged, %d idem keys remain", n)
	}

	// Poem 2.
	authors2, view, raw := writePoem(t, r, tokens, v, "n")
	if authors2[0] != other || authors2[1] != opener || authors2[2] != other {
		t.Fatalf("poem 2 authors = %v, want [%d %d %d]", authors2, other, opener, other)
	}
	tf = tradeOf(t, raw)
	if view.Status != sessions.StatusComplete || tf.PoemNumber != 2 || tf.TradeOpen {
		t.Fatalf("poem 2 reveal wrong: %s", raw)
	}
	if strings.Contains(string(raw), `"tradeOpen"`) {
		t.Fatalf("tradeOpen must be omitted on poem 2's reveal: %s", raw)
	}

	// No third poem.
	code, raw := postTrade(r, tokens[opener], id)
	if code != http.StatusConflict || !strings.Contains(string(raw), `"trade_closed"`) {
		t.Fatalf("trade after poem 2 = %d %s, want 409 trade_closed", code, raw)
	}

	// Both dismiss; nothing remains.
	r.do(t, "POST", "/v1/session/"+id+"/dismiss", tokA, nil)
	r.do(t, "POST", "/v1/session/"+id+"/dismiss", tokB, nil)
	for _, tok := range []string{tokA, tokB} {
		if code, _ := r.do(t, "GET", "/v1/session/"+id, tok, nil); code != http.StatusGone {
			t.Fatalf("after dissolution expected 410, got %d", code)
		}
	}
	assertEncounterGone(t, r.mr)

	if d := testutil.ToFloat64(metrics.TradesOffered) - offered0; d != 1 {
		t.Fatalf("TradesOffered delta = %v, want 1", d)
	}
	if d := testutil.ToFloat64(metrics.TradesBegun) - begun0; d != 1 {
		t.Fatalf("TradesBegun delta = %v, want 1", d)
	}
	if d := testutil.ToFloat64(metrics.PoemsCompleted) - poems0; d != 2 {
		t.Fatalf("PoemsCompleted delta = %v, want 2", d)
	}
	if d := testutil.ToFloat64(metrics.Dissolved) - dissolved0; d != 1 {
		t.Fatalf("Dissolved delta = %v, want 1", d)
	}
}

// playBotPoem plays the current poem to completion against the robot poet via
// rig r: the human writes on its turn, and the bot's turns are served by
// advancing the fake clock past BotThink and polling. It returns the author
// index of every line and the final view. Bot lines must be CleanLine-identical
// and on their syllable target.
func playBotPoem(t *testing.T, b *botRig, r *rig, tok string, v sessions.View, prefix string) ([]int, sessions.View) {
	t.Helper()
	human := []string{"an old silent pond", "a frog jumps into the pond", "splash silence again"}
	form := sessions.LookupForm("haiku")
	var authors []int
	for guard := 0; v.Status == sessions.StatusActive; guard++ {
		if guard > 10 {
			t.Fatalf("%s: poem did not finish: %+v", prefix, v)
		}
		if v.YourTurn {
			authors = append(authors, v.CurrentAuthor)
			v, _ = postLine(t, r, tok, v.SessionID, v.CurrentLine, human[v.CurrentLine], fmt.Sprintf("%s%d", prefix, v.CurrentLine))
			continue
		}
		before := len(v.Lines)
		b.clock.Advance(b.cfg.BotThink)
		v, _ = getView(t, r, tok, v.SessionID)
		if len(v.Lines) != before+1 {
			t.Fatalf("%s: expected one bot line, had %d now %d", prefix, before, len(v.Lines))
		}
		authors = append(authors, 1) // the waiter is index 0, so the bot is index 1
		line := v.Lines[before]
		if got, err := sessions.CleanLine(line); err != nil || got != line {
			t.Fatalf("%s: bot line %q not CleanLine-identical (%v)", prefix, line, err)
		}
		if want := *form.Targets[before]; poet.Count(line) != want {
			t.Fatalf("%s: bot line %q counts %d, want %d", prefix, line, poet.Count(line), want)
		}
	}
	return authors, v
}

// TestBotTradesBack: the robot poet accepts a human's offer only after its think
// time, survives a restart, swaps roles, and writes poem 2 (D-06, D-03).
func TestBotTradesBack(t *testing.T) {
	ctx := context.Background()
	for start := 0; start < 2; start++ {
		offered0 := testutil.ToFloat64(metrics.TradesOffered)
		begun0 := testutil.ToFloat64(metrics.TradesBegun)

		b := newBotRig(t, nil)
		er, _ := b.enterWith(t, map[string]any{"allowBot": true})
		tok := er.ParticipantToken
		b.clock.Advance(b.cfg.BotWindow)
		wr, raw := b.poll(t, tok)
		if wr.State != "matched" || wr.Session == nil {
			t.Fatalf("start %d: expected matched, got %s", start, raw)
		}
		id := wr.Session.SessionID
		sess, err := b.st.GetSession(ctx, id)
		if err != nil {
			t.Fatalf("load: %v", err)
		}
		sess.StartIndex = start // force the start order, as dueBot does
		if err := b.st.SaveSession(ctx, sess); err != nil {
			t.Fatalf("save: %v", err)
		}
		view, _ := getView(t, b.rig, tok, id)

		authors1, view := playBotPoem(t, b, b.rig, tok, view, "p")
		if view.Status != sessions.StatusComplete {
			t.Fatalf("start %d: poem 1 should be complete: %+v", start, view)
		}

		// The human offers; the bot never answers instantly.
		v, raw := mustTrade(t, b.rig, tok, id)
		if tf := tradeOf(t, raw); v.Status != sessions.StatusComplete || !tf.YouWantTrade {
			t.Fatalf("start %d: offer view wrong: %s", start, raw)
		}
		_, raw = getView(t, b.rig, tok, id)
		if tf := tradeOf(t, raw); tf.PartnerWantsTrade || !tf.YouWantTrade || !strings.Contains(string(raw), `"complete"`) {
			t.Fatalf("start %d: the bot accepted instantly: %s", start, raw)
		}
		b.clock.Advance(b.cfg.BotThink - time.Millisecond)
		if v, raw = getView(t, b.rig, tok, id); v.Status != sessions.StatusComplete {
			t.Fatalf("start %d: 1ms early the reveal must hold: %s", start, raw)
		}

		// A server restart between offer and acceptance changes nothing.
		restarted := b.restart(t)
		b.clock.Advance(time.Millisecond)
		v, raw = getView(t, restarted, tok, id)
		tf := tradeOf(t, raw)
		if v.Status != sessions.StatusActive || tf.PoemNumber != 2 || !v.PartnerIsBot {
			t.Fatalf("start %d: poem 2 should have begun: %s", start, raw)
		}
		if v.CurrentAuthor != authors1[1] {
			t.Fatalf("start %d: poem 2 opener = %d, want poem 1's line-1 author %d", start, v.CurrentAuthor, authors1[1])
		}

		_, view = playBotPoem(t, b, restarted, tok, v, "q")
		tf = tradeOf(t, mustGet(t, restarted, tok, id))
		if view.Status != sessions.StatusComplete || tf.PoemNumber != 2 || tf.TradeOpen {
			t.Fatalf("start %d: poem 2 reveal wrong: %+v", start, view)
		}
		if code, raw := postTrade(restarted, tok, id); code != http.StatusConflict || !strings.Contains(string(raw), `"trade_closed"`) {
			t.Fatalf("start %d: trade after poem 2 = %d %s", start, code, raw)
		}

		code, raw := restarted.do(t, "POST", "/v1/session/"+id+"/dismiss", tok, nil)
		if code != http.StatusOK || !strings.Contains(string(raw), `"dissolved"`) {
			t.Fatalf("start %d: single dismiss should dissolve: %d %s", start, code, raw)
		}
		assertNoKeysWithPrefix(t, b.mr, "sw:")

		if d := testutil.ToFloat64(metrics.TradesOffered) - offered0; d != 1 {
			t.Fatalf("start %d: TradesOffered delta = %v, want 1", start, d)
		}
		if d := testutil.ToFloat64(metrics.TradesBegun) - begun0; d != 1 {
			t.Fatalf("start %d: TradesBegun delta = %v, want 1", start, d)
		}
	}
}

func mustGet(t *testing.T, r *rig, token, id string) []byte {
	t.Helper()
	_, raw := getView(t, r, token, id)
	return raw
}
