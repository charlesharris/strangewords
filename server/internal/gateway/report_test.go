package gateway

import (
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"

	"strangewords/internal/metrics"
)

// TestReportEndpoint: a member can file a report on a live session (captured to
// the sink, counter advanced); a request with no token is rejected.
func TestReportEndpoint(t *testing.T) {
	r := newRig(t)
	before := testutil.ToFloat64(metrics.Reports)
	_, tokenB, v := r.match(t)

	// No bearer token → 401, and nothing captured.
	if code, _ := r.do(t, "POST", "/v1/session/"+v.SessionID+"/report", "", nil); code != 401 {
		t.Fatalf("no-token report: %d, want 401", code)
	}

	// Member reports → 200, counter advances by one.
	code, body := r.do(t, "POST", "/v1/session/"+v.SessionID+"/report", tokenB,
		map[string]any{"reason": "abusive line"})
	if code != 200 {
		t.Fatalf("member report: %d body %s", code, body)
	}
	if got := testutil.ToFloat64(metrics.Reports) - before; got != 1 {
		t.Fatalf("Reports delta = %v, want 1", got)
	}
}

// TestReportRejectsNonMember: a valid token for a different session cannot
// report someone else's session.
func TestReportRejectsNonMember(t *testing.T) {
	r := newRig(t)
	_, _, v := r.match(t)         // session under test
	_, outsiderB, _ := r.match(t) // a second, unrelated session

	code, _ := r.do(t, "POST", "/v1/session/"+v.SessionID+"/report", outsiderB,
		map[string]any{"reason": "x"})
	if code != 403 {
		t.Fatalf("non-member report: %d, want 403", code)
	}
}
