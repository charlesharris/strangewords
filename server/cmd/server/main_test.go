package main

import (
	"testing"

	"strangewords/internal/config"
)

func TestRedisOptions(t *testing.T) {
	t.Run("bare host:port", func(t *testing.T) {
		o, err := redisOptions(config.Config{RedisAddr: "fly-x.upstash.io:6379", RedisPassword: "pw"})
		if err != nil {
			t.Fatal(err)
		}
		if o.Addr != "fly-x.upstash.io:6379" || o.Password != "pw" {
			t.Fatalf("addr=%q pass=%q", o.Addr, o.Password)
		}
		if o.TLSConfig != nil {
			t.Error("no TLS expected")
		}
	})

	t.Run("redis:// URL is parsed (the Fly/Upstash paste)", func(t *testing.T) {
		o, err := redisOptions(config.Config{RedisAddr: "redis://default:secret@fly-x.upstash.io:6379"})
		if err != nil {
			t.Fatal(err)
		}
		if o.Addr != "fly-x.upstash.io:6379" {
			t.Fatalf("addr = %q, want host:port extracted from URL", o.Addr)
		}
		if o.Password != "secret" {
			t.Fatalf("password = %q, want it taken from the URL", o.Password)
		}
		if o.TLSConfig != nil {
			t.Error("plain redis:// should not enable TLS")
		}
	})

	t.Run("rediss:// enables TLS", func(t *testing.T) {
		o, err := redisOptions(config.Config{RedisAddr: "rediss://default:secret@fly-x.upstash.io:6380"})
		if err != nil {
			t.Fatal(err)
		}
		if o.TLSConfig == nil {
			t.Error("rediss:// should enable TLS")
		}
	})

	t.Run("explicit password overrides the URL", func(t *testing.T) {
		o, err := redisOptions(config.Config{RedisAddr: "redis://default:fromurl@h:6379", RedisPassword: "override"})
		if err != nil {
			t.Fatal(err)
		}
		if o.Password != "override" {
			t.Fatalf("password = %q, want override", o.Password)
		}
	})

	t.Run("malformed URL errors", func(t *testing.T) {
		if _, err := redisOptions(config.Config{RedisAddr: "redis://%zz"}); err == nil {
			t.Error("expected an error for a malformed URL")
		}
	})
}
