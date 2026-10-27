// Package metrics is the observability core: Prometheus counters/histograms for
// business events, RED HTTP metrics (Rate/Errors/Duration) via middleware, and
// a go-redis hook that times every Redis command centrally (plan.v1.md §18).
//
// All series use bounded label sets — routes are templates ("GET /v1/session/
// {id}"), never concrete ids — so cardinality stays flat under any traffic.
package metrics

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
)

// ---- business counters ----

var (
	Entered        = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_entered_total", Help: "Participants that entered the matchmaker."})
	Matched        = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_matched_total", Help: "Enters that paired immediately into a session."})
	Waiting        = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_waiting_total", Help: "Enters that were enqueued to wait."})
	BotPaired      = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_bot_paired_total", Help: "Opted-in waiters paired with the robot poet after the wait window."})
	LinesSubmitted = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_lines_submitted_total", Help: "Poem lines accepted."})
	PoemsCompleted = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_poems_completed_total", Help: "Poems that reached completion."})
	Dissolved      = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_dissolved_total", Help: "Sessions torn down."})
)

// ---- hardening counters ----

var (
	PanicsRecovered = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_panics_recovered_total", Help: "Handler panics caught by the recovery middleware."})
	RateLimited     = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_rate_limited_total", Help: "Requests rejected by the per-IP rate limiter."})
)

// ---- safety / moderation ----

var (
	ContentRejected = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_content_rejected_total", Help: "Lines rejected by the abuse content filter."})
	Reports         = promauto.NewCounter(prometheus.CounterOpts{Name: "sw_reports_total", Help: "Abuse reports captured."})
)

// ---- RED: HTTP ----

var (
	httpRequests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "sw_http_requests_total",
		Help: "HTTP requests by route template, method, and status code.",
	}, []string{"route", "method", "code"})

	httpDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "sw_http_request_duration_seconds",
		Help:    "HTTP request latency by route template and method.",
		Buckets: []float64{.0005, .001, .0025, .005, .01, .025, .05, .1, .25, .5, 1, 2.5},
	}, []string{"route", "method"})

	httpInFlight = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "sw_http_requests_in_flight",
		Help: "HTTP requests currently being served.",
	})
)

// ---- Redis command timing ----

var (
	redisDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "sw_redis_command_duration_seconds",
		Help:    "Redis command latency by command name.",
		Buckets: []float64{.0001, .00025, .0005, .001, .0025, .005, .01, .025, .05, .1, .25},
	}, []string{"cmd"})

	redisErrors = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "sw_redis_command_errors_total",
		Help: "Redis commands that returned a real error (cache misses excluded).",
	}, []string{"cmd"})
)

// Handler serves the Prometheus exposition format at /metrics.
func Handler() http.Handler { return promhttp.Handler() }

// HTTPMiddleware records RED metrics for every request. It wraps the mux, so
// after next.ServeHTTP returns the request's matched Pattern is populated
// (Go 1.23+) and used as the route label — keeping cardinality bounded.
func HTTPMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		httpInFlight.Inc()
		defer httpInFlight.Dec()

		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		start := time.Now()
		next.ServeHTTP(rec, r)
		dur := time.Since(start).Seconds()

		route := r.Pattern
		if route == "" {
			route = "unmatched" // 404s and unrouted paths share one low-cardinality bucket
		}
		httpDuration.WithLabelValues(route, r.Method).Observe(dur)
		httpRequests.WithLabelValues(route, r.Method, strconv.Itoa(rec.status)).Inc()
	})
}

// statusRecorder captures the response status for the requests_total code label.
type statusRecorder struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func (r *statusRecorder) WriteHeader(code int) {
	if !r.wroteHeader {
		r.status = code
		r.wroteHeader = true
	}
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	r.wroteHeader = true // an implicit 200 if WriteHeader was never called
	return r.ResponseWriter.Write(b)
}

// ---- go-redis hook ----

// RedisHook returns a hook that times every command and pipeline stage. Attach
// it once via rdb.AddHook so all store methods are instrumented centrally.
func RedisHook() redis.Hook { return redisHook{} }

type redisHook struct{}

func (redisHook) DialHook(next redis.DialHook) redis.DialHook { return next }

func (redisHook) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, cmd redis.Cmder) error {
		start := time.Now()
		err := next(ctx, cmd)
		observe(cmd.Name(), start, err)
		return err
	}
}

func (redisHook) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return func(ctx context.Context, cmds []redis.Cmder) error {
		start := time.Now()
		err := next(ctx, cmds)
		for _, cmd := range cmds {
			observe(cmd.Name(), start, cmd.Err())
		}
		return err
	}
}

func observe(cmd string, start time.Time, err error) {
	redisDuration.WithLabelValues(cmd).Observe(time.Since(start).Seconds())
	// redis.Nil is an expected "key absent" sentinel, not a failure.
	if err != nil && !errors.Is(err, redis.Nil) {
		redisErrors.WithLabelValues(cmd).Inc()
	}
}
