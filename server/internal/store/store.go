// Package store is the single Redis layer. Everything operational lives here
// with bounded TTLs (plan.v1.md §6); the domain (package sessions) stays pure.
package store

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"strangewords/internal/sessions"
)

// TTLs. [TUNABLE] — see plan.v1.md §5/§6.
const (
	SessionTTL = 90 * time.Minute      // outer bound for an in-progress poem
	RevealTTL  = 120 * time.Second     // reveal-window cap once complete
	WaitTTL    = 15 * time.Minute
	IdemTTL    = 10 * time.Minute
)

// ErrNotFound is returned when a key has expired or never existed.
var ErrNotFound = errors.New("not found")

// Kind distinguishes what a participant token currently points at.
type Kind string

const (
	KindWait    Kind = "wait"
	KindSession Kind = "session"
)

// Ref resolves a participant token to its current waiting entry or session.
type Ref struct {
	Kind  Kind   `json:"kind"`
	RefID string `json:"refId"`
	Idx   int    `json:"idx"` // participant ordinal within a session
}

// WaitEntry is a participant sitting in the matching queue.
type WaitEntry struct {
	ID               string `json:"id"`
	Token            string `json:"token"`
	PushToken        string `json:"pushToken,omitempty"`
	Bucket           string `json:"bucket"`
	EnqueuedAt       int64  `json:"enqueuedAt"`
	MatchedSessionID string `json:"matchedSessionId,omitempty"`
}

type Store struct {
	rdb *redis.Client
}

func New(rdb *redis.Client) *Store { return &Store{rdb: rdb} }

func (s *Store) Ping(ctx context.Context) error { return s.rdb.Ping(ctx).Err() }

// ---- key helpers ----

func queueKey(bucket string) string  { return "sw:queue:" + bucket }
func waitKey(id string) string       { return "sw:wait:" + id }
func tokKey(token string) string     { return "sw:tok:" + token }
func sessKey(id string) string       { return "sw:sess:" + id }
func idemKey(sid, key string) string { return fmt.Sprintf("sw:idem:%s:%s", sid, key) }

// NewToken returns a 32-byte base64url participant token.
func NewToken() string { return randB64(32) }

// NewID returns a 16-byte base64url id (session / wait).
func NewID() string { return randB64(16) }

func randB64(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

// ---- token refs ----

func (s *Store) SetRef(ctx context.Context, token string, ref Ref, ttl time.Duration) error {
	b, _ := json.Marshal(ref)
	return s.rdb.Set(ctx, tokKey(token), b, ttl).Err()
}

func (s *Store) GetRef(ctx context.Context, token string) (Ref, error) {
	v, err := s.rdb.Get(ctx, tokKey(token)).Bytes()
	if errors.Is(err, redis.Nil) {
		return Ref{}, ErrNotFound
	}
	if err != nil {
		return Ref{}, err
	}
	var ref Ref
	if err := json.Unmarshal(v, &ref); err != nil {
		return Ref{}, err
	}
	return ref, nil
}

func (s *Store) DelRef(ctx context.Context, token string) error {
	return s.rdb.Del(ctx, tokKey(token)).Err()
}

// ---- waiting queue ----

// Enqueue stores a wait entry and pushes it onto its bucket queue.
func (s *Store) Enqueue(ctx context.Context, w *WaitEntry) error {
	b, _ := json.Marshal(w)
	if err := s.rdb.Set(ctx, waitKey(w.ID), b, WaitTTL).Err(); err != nil {
		return err
	}
	return s.rdb.RPush(ctx, queueKey(w.Bucket), w.ID).Err()
}

// PopWaiter atomically removes the oldest waiter id from a bucket and returns
// its (still-live) entry. Skips entries whose wait record has expired. Returns
// ErrNotFound when the queue holds no live waiter.
func (s *Store) PopWaiter(ctx context.Context, bucket string) (*WaitEntry, error) {
	for {
		id, err := s.rdb.LPop(ctx, queueKey(bucket)).Result()
		if errors.Is(err, redis.Nil) {
			return nil, ErrNotFound
		}
		if err != nil {
			return nil, err
		}
		w, err := s.GetWait(ctx, id)
		if errors.Is(err, ErrNotFound) {
			continue // stale id whose wait entry expired; skip it
		}
		if err != nil {
			return nil, err
		}
		return w, nil
	}
}

func (s *Store) GetWait(ctx context.Context, id string) (*WaitEntry, error) {
	v, err := s.rdb.Get(ctx, waitKey(id)).Bytes()
	if errors.Is(err, redis.Nil) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	var w WaitEntry
	if err := json.Unmarshal(v, &w); err != nil {
		return nil, err
	}
	return &w, nil
}

func (s *Store) SaveWait(ctx context.Context, w *WaitEntry) error {
	b, _ := json.Marshal(w)
	return s.rdb.Set(ctx, waitKey(w.ID), b, WaitTTL).Err()
}

func (s *Store) DelWait(ctx context.Context, id string) error {
	return s.rdb.Del(ctx, waitKey(id)).Err()
}

// ---- sessions ----

func (s *Store) SaveSession(ctx context.Context, sess *sessions.Session) error {
	return s.SaveSessionTTL(ctx, sess, SessionTTL)
}

// SaveSessionTTL persists a session with an explicit TTL (e.g. RevealTTL once
// complete, so the reveal window self-expires).
func (s *Store) SaveSessionTTL(ctx context.Context, sess *sessions.Session, ttl time.Duration) error {
	b, _ := json.Marshal(sess)
	return s.rdb.Set(ctx, sessKey(sess.ID), b, ttl).Err()
}

func (s *Store) GetSession(ctx context.Context, id string) (*sessions.Session, error) {
	v, err := s.rdb.Get(ctx, sessKey(id)).Bytes()
	if errors.Is(err, redis.Nil) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	var sess sessions.Session
	if err := json.Unmarshal(v, &sess); err != nil {
		return nil, err
	}
	return &sess, nil
}

// DeleteSession erases the session and every associated infrastructural
// identifier (token refs, idempotency keys) — full teardown (plan.v1.md §6).
func (s *Store) DeleteSession(ctx context.Context, sess *sessions.Session) error {
	keys := []string{sessKey(sess.ID)}
	for _, p := range sess.Participants {
		keys = append(keys, tokKey(p.Token))
	}
	for _, k := range sess.IdemKeys {
		keys = append(keys, idemKey(sess.ID, k))
	}
	return s.rdb.Del(ctx, keys...).Err()
}

// ---- idempotency ----

// IdemGet returns a previously stored response for an (session, key) pair.
func (s *Store) IdemGet(ctx context.Context, sid, key string) ([]byte, bool, error) {
	v, err := s.rdb.Get(ctx, idemKey(sid, key)).Bytes()
	if errors.Is(err, redis.Nil) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	return v, true, nil
}

func (s *Store) IdemSet(ctx context.Context, sid, key string, resp []byte) error {
	return s.rdb.Set(ctx, idemKey(sid, key), resp, IdemTTL).Err()
}
