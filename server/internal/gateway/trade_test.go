package gateway

import (
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"

	"strangewords/internal/metrics"
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
	assertNoKeysWithPrefix(t, r.mr, "sw:")

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
