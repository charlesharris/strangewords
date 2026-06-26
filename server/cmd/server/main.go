// Command server is the single deployable for Haiku for Strangers (plan.v1.md §3).
package main

import (
	"context"
	"crypto/tls"
	"errors"
	"log/slog"
	"net/http"
	_ "net/http/pprof" // registers /debug/pprof on http.DefaultServeMux
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"
	_ "go.uber.org/automaxprocs" // align GOMAXPROCS to the cgroup CPU quota (Fly fractional vCPU)

	"strangewords/internal/config"
	"strangewords/internal/gateway"
	"strangewords/internal/matchmaker"
	"strangewords/internal/moderation"
	"strangewords/internal/push"
	"strangewords/internal/store"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	cfg := config.Load()

	redisOpts := &redis.Options{Addr: cfg.RedisAddr, Password: cfg.RedisPassword}
	if cfg.RedisTLS {
		redisOpts.TLSConfig = &tls.Config{}
	}
	rdb := redis.NewClient(redisOpts)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Error("cannot reach redis", "addr", cfg.RedisAddr, "err", err)
		os.Exit(1)
	}

	st := store.New(rdb)
	mm := matchmaker.New(st)
	notifier := push.Noop{Log: log}
	mod := moderation.LogSink{Log: log} // v1: reports captured to structured logs
	srv := gateway.New(st, mm, notifier, mod, log, cfg)

	httpSrv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           srv.Routes(),
		ReadHeaderTimeout: 5 * time.Second,  // slow-header (Slowloris) guard
		ReadTimeout:       10 * time.Second, // whole request, incl. a slow body
		WriteTimeout:      15 * time.Second, // comfortably above any handler
		IdleTimeout:       60 * time.Second, // reap idle keep-alive connections
	}
	srv.StartMaintenance() // rate-limiter idle sweep

	go func() {
		log.Info("listening", "addr", cfg.Addr, "redis", cfg.RedisAddr)
		if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("server error", "err", err)
			os.Exit(1)
		}
	}()

	// Debug server: pprof + a plain heap/goroutine view. Disabled unless
	// SW_DEBUG_ADDR is set; never add it to fly.toml's http_service, so it
	// stays off the public router (reach it with `fly proxy 6060:6060`).
	if cfg.DebugAddr != "" {
		dbg := &http.Server{Addr: cfg.DebugAddr, Handler: http.DefaultServeMux, ReadHeaderTimeout: 5 * time.Second}
		go func() {
			log.Info("debug listening", "addr", cfg.DebugAddr)
			if err := dbg.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				log.Warn("debug server error", "err", err)
			}
		}()
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	log.Info("shutting down")
	shutCtx, shutCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutCancel()
	_ = httpSrv.Shutdown(shutCtx)
}
