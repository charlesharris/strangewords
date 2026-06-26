package gateway

import (
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"sync"
	"time"

	"strangewords/internal/metrics"
)

// maxBodyBytes caps request bodies. Poem lines, tokens, and prefs are tiny; a
// kilobyte is already generous, so 16 KiB leaves headroom while making a
// memory-exhaustion POST impossible.
const maxBodyBytes = 16 << 10

// limitBody wraps every request body in a MaxBytesReader so an oversized POST
// can't be read into memory. Decoders downstream surface the cap as a normal
// read error (handlers already turn that into a 400).
func limitBody(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
		}
		next.ServeHTTP(w, r)
	})
}

// recoverPanic turns a handler panic into a logged 500 (and a metric) instead
// of a dropped connection with a bare stack trace. It is the outermost wrap so
// it covers every inner middleware and handler.
func recoverPanic(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				metrics.PanicsRecovered.Inc()
				log.Error("panic recovered", "err", fmt.Sprint(v), "method", r.Method, "path", r.URL.Path)
				// Best-effort 500. If the handler already wrote a status this is
				// a no-op header-wise; the goal is to not crash the connection.
				writeErr(w, http.StatusInternalServerError, "internal", "something went wrong")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// ---- per-IP rate limiting ----

// rateLimiter is an in-memory token bucket per client IP. Buckets refill at rps
// tokens/sec up to burst depth; an idle sweep bounds the map's memory.
type rateLimiter struct {
	mu      sync.Mutex
	buckets map[string]*tokenBucket
	rps     float64
	burst   float64
	now     func() time.Time // injectable for tests
}

type tokenBucket struct {
	tokens float64
	last   time.Time
}

func newRateLimiter(rps, burst float64) *rateLimiter {
	return &rateLimiter{buckets: map[string]*tokenBucket{}, rps: rps, burst: burst, now: time.Now}
}

// allow reports whether a request from key may proceed, spending one token.
func (l *rateLimiter) allow(key string) bool {
	now := l.now()
	l.mu.Lock()
	defer l.mu.Unlock()
	b := l.buckets[key]
	if b == nil {
		b = &tokenBucket{tokens: l.burst, last: now}
		l.buckets[key] = b
	} else {
		b.tokens += now.Sub(b.last).Seconds() * l.rps
		if b.tokens > l.burst {
			b.tokens = l.burst
		}
		b.last = now
	}
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// sweep drops buckets idle longer than maxIdle so the map can't grow unbounded
// under a churn of distinct source IPs.
func (l *rateLimiter) sweep(maxIdle time.Duration) {
	now := l.now()
	l.mu.Lock()
	defer l.mu.Unlock()
	for k, b := range l.buckets {
		if now.Sub(b.last) > maxIdle {
			delete(l.buckets, k)
		}
	}
}

// runJanitor periodically sweeps idle buckets. Runs for the process lifetime.
func (l *rateLimiter) runJanitor(interval, maxIdle time.Duration) {
	t := time.NewTicker(interval)
	defer t.Stop()
	for range t.C {
		l.sweep(maxIdle)
	}
}

// middleware rejects requests from an IP that has exhausted its bucket. Infra
// endpoints (Fly health checks, metric scrapes) are exempt so they can't be
// throttled and never count against a client's budget.
func (l *rateLimiter) middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" || r.URL.Path == "/metrics" {
			next.ServeHTTP(w, r)
			return
		}
		if !l.allow(clientIP(r)) {
			metrics.RateLimited.Inc()
			w.Header().Set("Retry-After", "1")
			writeErr(w, http.StatusTooManyRequests, "rate_limited", "slow down")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// clientIP resolves the real client address. Behind Fly's proxy the socket peer
// is the proxy, so the per-client identity comes from Fly-Client-IP; off Fly we
// fall back to the connection's remote host.
func clientIP(r *http.Request) string {
	if ip := r.Header.Get("Fly-Client-IP"); ip != "" {
		return ip
	}
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}
