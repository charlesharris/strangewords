// Package matchmaker pairs waiting participants into poem sessions
// (plan.v1.md §12). v1 forms exactly a pair; the pieces are index-based so the
// turn logic is already N-ready (§13).
package matchmaker

import (
	"context"
	"errors"
	"math/rand/v2"
	"time"

	"strangewords/internal/sessions"
	"strangewords/internal/store"
)

type Matchmaker struct {
	st *store.Store
}

func New(st *store.Store) *Matchmaker { return &Matchmaker{st: st} }

// Result is the outcome of an enter attempt: exactly one of Session/Wait is set.
type Result struct {
	Session *sessions.Session // set when matched immediately
	Wait    *store.WaitEntry  // set when enqueued to wait
}

// Enter issues nothing itself — the caller supplies the freshly minted token.
// It either pairs the arriver with a waiting participant (returning a new
// active session) or enqueues the arriver to wait.
func (m *Matchmaker) Enter(ctx context.Context, token, pushToken, bucket, formID string, now time.Time) (Result, error) {
	waiter, err := m.st.PopWaiter(ctx, bucket)
	if errors.Is(err, store.ErrNotFound) {
		return m.enqueue(ctx, token, pushToken, bucket, now)
	}
	if err != nil {
		return Result{}, err
	}
	sess, err := m.pair(ctx, waiter, token, pushToken, bucket, formID, now)
	if err != nil {
		return Result{}, err
	}
	return Result{Session: sess}, nil
}

func (m *Matchmaker) enqueue(ctx context.Context, token, pushToken, bucket string, now time.Time) (Result, error) {
	w := &store.WaitEntry{
		ID:         store.NewID(),
		Token:      token,
		PushToken:  pushToken,
		Bucket:     bucket,
		EnqueuedAt: now.UnixMilli(),
	}
	if err := m.st.Enqueue(ctx, w); err != nil {
		return Result{}, err
	}
	if err := m.st.SetRef(ctx, token, store.Ref{Kind: store.KindWait, RefID: w.ID}, store.WaitTTL); err != nil {
		return Result{}, err
	}
	return Result{Wait: w}, nil
}

// pair builds an active session from the waiter (index 0) and arriver (index
// 1), assigns a random start offset, and points both tokens at the session.
func (m *Matchmaker) pair(ctx context.Context, waiter *store.WaitEntry, arriverToken, arriverPush, bucket, formID string, now time.Time) (*sessions.Session, error) {
	nowMs := now.UnixMilli()
	sess := &sessions.Session{
		ID: store.NewID(),
		Participants: []sessions.Participant{
			{Token: waiter.Token, PushToken: waiter.PushToken, LastSeen: waiter.EnqueuedAt},
			{Token: arriverToken, PushToken: arriverPush, LastSeen: nowMs},
		},
		StartIndex:  rand.IntN(2),
		Bucket:      bucket,
		CreatedAt:   nowMs,
		Status:      sessions.StatusActive,
		FormID:      formID,
		PolicyID:    sessions.DefaultPolicyID,
		Lines:       []string{},
		CurrentLine: 0,
		PoemCount:   1,
	}
	if err := m.st.SaveSession(ctx, sess); err != nil {
		return nil, err
	}
	// Point both tokens at the session.
	if err := m.st.SetRef(ctx, waiter.Token, store.Ref{Kind: store.KindSession, RefID: sess.ID, Idx: 0}, store.SessionTTL); err != nil {
		return nil, err
	}
	if err := m.st.SetRef(ctx, arriverToken, store.Ref{Kind: store.KindSession, RefID: sess.ID, Idx: 1}, store.SessionTTL); err != nil {
		return nil, err
	}
	// Record the match on the wait entry so a polling waiter can find it even
	// before its token ref is consulted; TTL reaps the entry afterward.
	waiter.MatchedSessionID = sess.ID
	_ = m.st.SaveWait(ctx, waiter)
	return sess, nil
}
