package gateway

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"

	"strangewords/internal/metrics"
)

// TestLimitBody caps oversized bodies while leaving small ones untouched.
func TestLimitBody(t *testing.T) {
	var readErr error
	h := limitBody(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, readErr = io.ReadAll(r.Body)
	}))

	// A body just over the cap must fail to read.
	big := strings.NewReader(strings.Repeat("x", maxBodyBytes+1))
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("POST", "/v1/enter", big))
	if readErr == nil {
		t.Fatal("oversized body: expected a read error, got nil")
	}

	// A small body passes through cleanly.
	readErr = nil
	small := strings.NewReader(strings.Repeat("x", 64))
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("POST", "/v1/enter", small))
	if readErr != nil {
		t.Fatalf("small body: unexpected read error: %v", readErr)
	}
}

// TestRecoverPanic turns a handler panic into a 500 plus a counter bump.
func TestRecoverPanic(t *testing.T) {
	before := testutil.ToFloat64(metrics.PanicsRecovered)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	h := recoverPanic(log, http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic("boom")
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/v1/waiting", nil))

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if got := testutil.ToFloat64(metrics.PanicsRecovered) - before; got != 1 {
		t.Fatalf("PanicsRecovered delta = %v, want 1", got)
	}
}

// TestRateLimiterAllow exercises the token-bucket math with a fixed clock.
func TestRateLimiterAllow(t *testing.T) {
	now := time.Unix(0, 0)
	l := newRateLimiter(10, 3) // 10 rps, depth 3
	l.now = func() time.Time { return now }

	// Burst: the first 3 succeed, the 4th is denied (no time has passed).
	for i := 0; i < 3; i++ {
		if !l.allow("ip") {
			t.Fatalf("burst token %d denied", i)
		}
	}
	if l.allow("ip") {
		t.Fatal("4th request should be denied")
	}

	// After 0.1s one token (10 rps) refills, allowing exactly one more.
	now = now.Add(100 * time.Millisecond)
	if !l.allow("ip") {
		t.Fatal("refilled token should allow one request")
	}
	if l.allow("ip") {
		t.Fatal("only one token should have refilled")
	}

	// A different IP has its own independent bucket.
	if !l.allow("other") {
		t.Fatal("independent IP should start full")
	}
}

// TestRateLimiterSweep drops buckets idle past the threshold.
func TestRateLimiterSweep(t *testing.T) {
	now := time.Unix(0, 0)
	l := newRateLimiter(1, 1)
	l.now = func() time.Time { return now }

	l.allow("stale")
	now = now.Add(2 * time.Minute)
	l.allow("fresh")

	l.sweep(time.Minute)
	if _, ok := l.buckets["stale"]; ok {
		t.Error("stale bucket should have been swept")
	}
	if _, ok := l.buckets["fresh"]; !ok {
		t.Error("fresh bucket should survive the sweep")
	}
}

// TestRateLimitMiddleware enforces the budget on app routes and exempts infra.
func TestRateLimitMiddleware(t *testing.T) {
	l := newRateLimiter(0, 2) // depth 2, no refill within the test
	ok := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(200) })
	h := l.middleware(ok)

	call := func(path string) int {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest("GET", path, nil)
		req.RemoteAddr = "203.0.113.5:443"
		h.ServeHTTP(rec, req)
		return rec.Code
	}

	if c := call("/v1/waiting"); c != 200 {
		t.Fatalf("1st request: %d, want 200", c)
	}
	if c := call("/v1/waiting"); c != 200 {
		t.Fatalf("2nd request: %d, want 200", c)
	}
	if c := call("/v1/waiting"); c != http.StatusTooManyRequests {
		t.Fatalf("3rd request: %d, want 429", c)
	}
	// Infra endpoints are exempt even after the budget is spent.
	if c := call("/healthz"); c != 200 {
		t.Fatalf("/healthz should be exempt, got %d", c)
	}
	if c := call("/metrics"); c != 200 {
		t.Fatalf("/metrics should be exempt, got %d", c)
	}
}

// TestClientIP prefers Fly's header and falls back to the socket peer.
func TestClientIP(t *testing.T) {
	r := httptest.NewRequest("GET", "/", nil)
	r.RemoteAddr = "10.0.0.1:5000"
	if got := clientIP(r); got != "10.0.0.1" {
		t.Errorf("fallback: got %q, want 10.0.0.1", got)
	}
	r.Header.Set("Fly-Client-IP", "198.51.100.7")
	if got := clientIP(r); got != "198.51.100.7" {
		t.Errorf("Fly header: got %q, want 198.51.100.7", got)
	}
}
