// Package botplayer is the robot poet's brain. It is pure: no HTTP, no Redis,
// no outside service.
package botplayer

import "strangewords/internal/sessions"

// fallbackLine is the fixed safe line used if poet output fails CleanLine.
const fallbackLine = ""

// Seed derives a poet seed from a session id.
func Seed(sessionID string) uint64 { return 0 }

// NextLine returns the robot poet's line for s.CurrentLine.
func NextLine(s *sessions.Session) string { return "" }
