// Package push abstracts re-engagement notifications (APNs). Phase 2 will
// implement an APNs HTTP/2 client behind this interface; Phase 1 ships a no-op
// so the core loop never depends on Apple credentials (plan.v1.md §9, §13 risk).
package push

import (
	"context"
	"log/slog"
)

// Kind names the two notification types.
type Kind string

const (
	MatchReady Kind = "match-ready"
	YourTurn   Kind = "your-turn"
)

// Notifier sends a content-free push for a session to a device push token.
type Notifier interface {
	Notify(ctx context.Context, kind Kind, pushToken, sessionID string) error
}

// Noop logs intent and does nothing. Used until Phase 2.
type Noop struct{ Log *slog.Logger }

func (n Noop) Notify(ctx context.Context, kind Kind, pushToken, sessionID string) error {
	if n.Log != nil && pushToken != "" {
		n.Log.Debug("push (noop)", "kind", string(kind), "session", sessionID)
	}
	return nil
}
