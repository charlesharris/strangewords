// Package config loads service configuration from the environment.
package config

import (
	"os"
	"time"
)

type Config struct {
	Addr             string        // HTTP listen address
	RedisAddr        string        // Redis host:port
	RedisPassword    string        // optional
	RedisTLS         bool          // dial Redis over TLS (e.g. a rediss:// endpoint)
	PresenceWindow   time.Duration // how recently a participant must be seen to count as "present"
}

func Load() Config {
	return Config{
		Addr:           env("SW_ADDR", ":8080"),
		RedisAddr:      env("SW_REDIS_ADDR", "127.0.0.1:6379"),
		RedisPassword:  env("SW_REDIS_PASSWORD", ""),
		RedisTLS:       env("SW_REDIS_TLS", "") != "",
		PresenceWindow: 20 * time.Second, // [TUNABLE] plan.v1.md §5
	}
}

func env(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}
