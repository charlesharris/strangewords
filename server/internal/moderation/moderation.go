// Package moderation is the seam for the one durable exception to the app's
// ephemerality: abuse reports. A report captures a poem's content and session
// metadata while the session is still live, routing it to a moderation queue
// (brief.final.md §23). Everything else about a session stays ephemeral.
//
// Sink is the interface; LogSink is the v1 implementation (structured logs,
// which Fly retains and can forward to a drain). A real durable store
// (Postgres / object storage) can replace it without touching callers — the
// same Noop-now/real-later pattern the push package uses.
package moderation

import (
	"context"
	"log/slog"
)

// Report is the captured evidence for a single abuse report. It deliberately
// omits participant and push tokens: the anonymity model holds even here. The
// evidence is the poem content plus which session and form it came from.
type Report struct {
	SessionID    string   `json:"sessionId"`
	Form         string   `json:"form"`
	Lines        []string `json:"lines"`
	Participants int      `json:"participants"`
	ReporterIdx  int      `json:"reporterIdx"`
	Reason       string   `json:"reason,omitempty"`
	CompletedAt  int64    `json:"completedAt,omitempty"` // unix millis, 0 if still active
	ReportedAt   int64    `json:"reportedAt"`            // unix millis
}

// Sink persists a report durably. Capture is called synchronously on a
// still-live session, so it always runs before the session is erased.
type Sink interface {
	Capture(ctx context.Context, r Report) error
}

// LogSink writes reports to the structured log at WARN. On Fly these land in
// the retained log stream and can be forwarded to a log drain — enough for the
// first internal TestFlight. Swap in a database-backed Sink for review tooling.
type LogSink struct{ Log *slog.Logger }

func (s LogSink) Capture(_ context.Context, r Report) error {
	s.Log.Warn("moderation report",
		"session", r.SessionID,
		"form", r.Form,
		"participants", r.Participants,
		"reporterIdx", r.ReporterIdx,
		"reason", r.Reason,
		"lines", r.Lines,
		"completedAt", r.CompletedAt,
		"reportedAt", r.ReportedAt,
	)
	return nil
}
