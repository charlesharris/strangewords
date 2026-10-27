// Package botplayer is the robot poet's brain. It is pure: no HTTP, no Redis,
// no outside service. Each line comes from a stateless, deterministic replay of
// a poet seeded by the session id (D-05: server/internal/poet only), so a
// server restart mid-poem changes nothing and no in-process state is kept.
package botplayer

import (
	"hash/fnv"

	"strangewords/internal/poet"
	"strangewords/internal/sessions"
)

// fallbackLine is the fixed safe line returned if poet output ever fails
// sessions.CleanLine, so unchecked text is never returned. It is five
// syllables, matching the haiku's first and last lines.
const fallbackLine = "still water at dusk"

// Seed derives a poem's poet seed from its session id (FNV-1a 64). It is the
// same derivation as cmd/bot's seedFor, so one session keeps one theme.
func Seed(sessionID string) uint64 {
	h := fnv.New64a()
	h.Write([]byte(sessionID))
	return h.Sum64()
}

// NextLine returns the robot poet's line for s.CurrentLine. It rebuilds the
// poet from the session id and replays, discarding the output, every earlier
// line the bot authored, so the RNG and the poet's used/mine state advance
// exactly as they did when those lines were first written.
func NextLine(s *sessions.Session) string {
	p := poet.New(Seed(s.ID))
	form := sessions.LookupForm(s.FormID)
	for i := 0; i < s.CurrentLine && i < len(s.Lines); i++ {
		a := s.AuthorOf(i)
		if a >= 0 && a < len(s.Participants) && s.Participants[a].Bot {
			p.Line(target(form, i), s.Lines[:i])
		}
	}
	line := p.Line(target(form, s.CurrentLine), s.Lines)
	if clean, err := sessions.CleanLine(line); err == nil && clean != "" {
		return clean
	}
	return fallbackLine
}

// target is the syllable target for line i; 0 means free verse to the poet.
func target(form sessions.Form, i int) int {
	if i >= 0 && i < len(form.Targets) && form.Targets[i] != nil {
		return *form.Targets[i]
	}
	return 0
}
