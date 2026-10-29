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

	"strangewords/internal/metrics"
	"strangewords/internal/sessions"
	"strangewords/internal/store"
)

// StaleWaiterAfter is how long a queued waiter may go without polling (or since
// enqueue) before an arriver drops it instead of pairing with it. [TUNABLE]
// About 3x the client's 3 s waiting poll (AppModel.defaultPollInterval,
// plan.v1.md §10) plus slack for one slow request. A backgrounded app stops
// polling and is treated as gone; revisit when APNs push lands.
const StaleWaiterAfter = 10 * time.Second

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
	for {
		waiter, err := m.st.PopWaiter(ctx, bucket)
		if errors.Is(err, store.ErrNotFound) {
			// The arriver's EnqueuedAt is its own arrival time, so a stale waiter
			// skipped above never delays its robot-poet window.
			return m.enqueue(ctx, token, pushToken, bucket, allowBot, now)
		}
		if err != nil {
			return Result{}, err
		}
		// Strictly greater: a waiter exactly StaleWaiterAfter old still counts as live.
		if now.UnixMilli()-waiter.LastSeenAt() > StaleWaiterAfter.Milliseconds() {
			// LPOP made this call the waiter's sole owner. Best effort: WaitTTL is
			// the backstop if the delete fails.
			_ = m.st.DropWait(ctx, waiter)
			metrics.StaleWaitersDropped.Inc()
			continue
		}
		sess, bound, err := m.pair(ctx, waiter, token, pushToken, bucket, formID, now)
		if err != nil {
			return Result{}, err
		}
		if !bound {
			continue // the waiter left mid-pairing
		}
		return Result{Session: sess}, nil
	}
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
//
// The waiter's token ref is its ownership record: it is bound last, with SET XX.
// A false bind means the waiter left mid-pairing, so the session is torn down and
// pair reports (nil, false, nil). The arriver's ref is set first so that a leave
// which sees the bind and dissolves the session also erases the arriver's ref.
func (m *Matchmaker) pair(ctx context.Context, waiter *store.WaitEntry, arriverToken, arriverPush, bucket, formID string, now time.Time) (*sessions.Session, bool, error) {
	nowMs := now.UnixMilli()
	sess := &sessions.Session{
		ID: store.NewID(),
		Participants: []sessions.Participant{
			{Token: waiter.Token, PushToken: waiter.PushToken, LastSeen: waiter.LastSeenAt()},
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
		return nil, false, err
	}
	// Point both tokens at the session: the arriver first, then the waiter via
	// the conditional bind.
	if err := m.st.SetRef(ctx, arriverToken, store.Ref{Kind: store.KindSession, RefID: sess.ID, Idx: 1}, store.SessionTTL); err != nil {
		return nil, false, err
	}
	bound, err := m.st.BindWaiter(ctx, waiter.Token, store.Ref{Kind: store.KindSession, RefID: sess.ID, Idx: 0}, store.SessionTTL)
	if err != nil {
		return nil, false, err
	}
	if !bound {
		// Also erases the arriver's ref set above; the waiter's is already gone.
		_ = m.st.DeleteSession(ctx, sess)
		return nil, false, nil
	}
	// Record the match on the wait entry so a polling waiter can find it even
	// before its token ref is consulted; TTL reaps the entry afterward. The
	// write is conditional (SET XX KEEPTTL): it never recreates a deleted record.
	waiter.MatchedSessionID = sess.ID
	_, _ = m.st.UpdateWait(ctx, waiter)
	return sess, true, nil
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
	bound, err := m.st.BindWaiter(ctx, waiter.Token, store.Ref{Kind: store.KindSession, RefID: sess.ID, Idx: 0}, store.SessionTTL)
	if err != nil {
		return nil, false, err
	}
	if !bound {
		// The waiter left between the claim and the bind: tear the session down
		// and let the caller answer waiting to a client that has already gone.
		_ = m.st.DeleteSession(ctx, sess)
		_ = m.st.DelWait(ctx, waiter.ID)
		return nil, false, nil
	}
	// Unlike the human path, drop the wait entry now rather than leaving it to TTL.
	if err := m.st.DelWait(ctx, waiter.ID); err != nil {
		return nil, false, err
	}
	return sess, true, nil
}
