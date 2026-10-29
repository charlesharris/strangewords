// Package matchmaker pairs waiting participants into poem sessions
// (plan.v1.md §12). v1 forms exactly a pair; the pieces are index-based so the
// turn logic is already N-ready (§13).
package matchmaker

import (
	"context"
	"errors"
	"fmt"
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
//
// allowBot is the arriver's opt-in to the robot poet. It only travels with the
// wait entry when the arriver has to wait; the human-human pairing path
// ignores it (D-03: humans first).
func (m *Matchmaker) Enter(ctx context.Context, token, pushToken, bucket, formID string, allowBot bool, now time.Time) (Result, error) {
	waiter, err := m.st.PopWaiter(ctx, bucket)
	if errors.Is(err, store.ErrNotFound) {
		return m.enqueue(ctx, token, pushToken, bucket, allowBot, now)
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

func (m *Matchmaker) enqueue(ctx context.Context, token, pushToken, bucket string, allowBot bool, now time.Time) (Result, error) {
	w := &store.WaitEntry{
		ID:         store.NewID(),
		Token:      token,
		PushToken:  pushToken,
		Bucket:     bucket,
		EnqueuedAt: now.UnixMilli(),
		AllowBot:   allowBot,
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

// LeaveWait is the "step back out" path (plan.v1.md §7): a waiter withdraws
// before seeing a match. It removes the waiter from its queue (LREM) and then
// deletes the wait record and token ref, but only if the token ref still points
// at the wait. When a pairing bound the ref first, nothing is deleted and the
// session id is returned so the caller dissolves it; otherwise it returns "".
func (m *Matchmaker) LeaveWait(ctx context.Context, token, waitID string) (matchedSessionID string, err error) {
	w, err := m.st.GetWait(ctx, waitID)
	switch {
	case err == nil:
		// Whether this call removed the entry does not matter: correctness rests
		// on the conditional delete below.
		if _, err := m.st.ClaimWaiter(ctx, w.Bucket, w.ID); err != nil {
			return "", err
		}
	case errors.Is(err, store.ErrNotFound):
		// Record expired; PopWaiter already skips ids whose record is gone.
	default:
		return "", err
	}

	ref, dropped, err := m.st.DropWaitIfUnbound(ctx, token, waitID)
	if errors.Is(err, store.ErrNotFound) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	if dropped {
		return "", nil
	}
	if ref.Kind == store.KindSession {
		return ref.RefID, nil
	}
	return "", fmt.Errorf("matchmaker: wait leave found unexpected ref kind %q", ref.Kind)
}

// PairWithBot pairs an opted-in waiter with the robot poet. It first claims the
// waiter out of the bucket queue (one atomic LREM); if a human arrival popped
// the waiter first the claim is lost and it returns (nil, false, nil) so the
// caller falls back to the normal waiting/matched reply. The bot is a flagged,
// tokenless, pre-dismissed participant and is never a queue member, so no
// arrival can be paired with it. Its first line is armed after think.
func (m *Matchmaker) PairWithBot(ctx context.Context, waiter *store.WaitEntry, formID string, think time.Duration, now time.Time) (*sessions.Session, bool, error) {
	claimed, err := m.st.ClaimWaiter(ctx, waiter.Bucket, waiter.ID)
	if err != nil {
		return nil, false, err
	}
	if !claimed {
		return nil, false, nil
	}
	nowMs := now.UnixMilli()
	sess := &sessions.Session{
		ID: store.NewID(),
		Participants: []sessions.Participant{
			{Token: waiter.Token, PushToken: waiter.PushToken, LastSeen: nowMs},
			{Bot: true, Dismissed: true, LastSeen: nowMs},
		},
		StartIndex:  rand.IntN(2),
		Bucket:      waiter.Bucket,
		CreatedAt:   nowMs,
		Status:      sessions.StatusActive,
		FormID:      formID,
		PolicyID:    sessions.DefaultPolicyID,
		Lines:       []string{},
		CurrentLine: 0,
		PoemCount:   1,
		BotReadyAt:  nowMs + think.Milliseconds(),
	}
	if err := m.st.SaveSession(ctx, sess); err != nil {
		return nil, false, err
	}
	if err := m.st.SetRef(ctx, waiter.Token, store.Ref{Kind: store.KindSession, RefID: sess.ID, Idx: 0}, store.SessionTTL); err != nil {
		return nil, false, err
	}
	// Unlike the human path, drop the wait entry now rather than leaving it to TTL.
	if err := m.st.DelWait(ctx, waiter.ID); err != nil {
		return nil, false, err
	}
	return sess, true, nil
}
