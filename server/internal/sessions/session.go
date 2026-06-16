package sessions

import "time"

// Status is the session lifecycle state (plan.v1.md §5).
type Status string

const (
	StatusActive    Status = "active"    // a poem is in progress
	StatusComplete  Status = "complete"  // every line filled; reveal window open
	StatusDissolved Status = "dissolved" // terminal; record being/already erased
)

// Participant is one anonymous member of an encounter. Referenced by ordinal
// index within the session; A/B never appears. Token/PushToken are
// infrastructural only and are erased when the session dissolves.
type Participant struct {
	Token     string `json:"token"`
	PushToken string `json:"pushToken,omitempty"`
	LastSeen  int64  `json:"lastSeen"` // unix millis
	Dismissed bool   `json:"dismissed,omitempty"`
}

// Session is the encounter between participants plus its current poem.
// Encounter-level fields are stable across a future continuation; poem-level
// fields would reset (see plan.v1.md §6, §13). v1 has exactly one poem.
type Session struct {
	// Encounter-level
	ID           string        `json:"id"`
	Participants []Participant `json:"participants"`
	StartIndex   int           `json:"startIndex"`
	Bucket       string        `json:"bucket"`
	CreatedAt    int64         `json:"createdAt"`

	// Poem-level
	Status      Status   `json:"status"`
	FormID      string   `json:"formId"`
	PolicyID    string   `json:"policyId"`
	Lines       []string `json:"lines"`
	CurrentLine int      `json:"currentLine"`
	CompletedAt int64    `json:"completedAt,omitempty"`
	PoemCount   int      `json:"poemCount"`
	IdemKeys    []string `json:"idemKeys,omitempty"` // tracked so teardown erases cached responses
}

func (s *Session) form() Form         { return LookupForm(s.FormID) }
func (s *Session) policy() TurnPolicy { return LookupPolicy(s.PolicyID) }

// CurrentAuthor is the participant index whose turn it is, derived (never
// stored) from the TurnPolicy.
func (s *Session) CurrentAuthor() int {
	return s.policy().Author(s.CurrentLine, len(s.Participants), s.StartIndex)
}

// IsComplete reports whether every line of the form has been written.
func (s *Session) IsComplete() bool {
	return s.CurrentLine >= s.form().LineCount()
}

// IndexForToken returns the participant ordinal for a token, or -1.
func (s *Session) IndexForToken(token string) int {
	for i, p := range s.Participants {
		if p.Token == token {
			return i
		}
	}
	return -1
}

// View is the client-facing projection of a session for a given caller. It
// speaks participant indices, never A/B, so the client is participant-count
// agnostic (plan.v1.md §7).
type View struct {
	SessionID        string     `json:"sessionId"`
	You              int        `json:"you"`
	ParticipantCount int        `json:"participantCount"`
	Status           Status     `json:"status"`
	Form             FormView   `json:"form"`
	CurrentLine      int        `json:"currentLine"`
	CurrentAuthor    int        `json:"currentAuthor"`
	YourTurn         bool       `json:"yourTurn"`
	Lines            []string   `json:"lines"`
}

// FormView is the structure descriptor the client renders from.
type FormView struct {
	ID      string `json:"id"`
	Targets []*int `json:"targets"`
}

// ViewFor builds the projection for the participant identified by token.
func (s *Session) ViewFor(token string) View {
	you := s.IndexForToken(token)
	author := s.CurrentAuthor()
	lines := s.Lines
	if lines == nil {
		lines = []string{}
	}
	f := s.form()
	return View{
		SessionID:        s.ID,
		You:              you,
		ParticipantCount: len(s.Participants),
		Status:           s.Status,
		Form:             FormView{ID: f.ID, Targets: f.Targets},
		CurrentLine:      s.CurrentLine,
		CurrentAuthor:    author,
		YourTurn:         s.Status == StatusActive && you == author,
		Lines:            lines,
	}
}

// present reports whether participant i has been seen within the window.
func (s *Session) present(i int, window time.Duration, now time.Time) bool {
	if i < 0 || i >= len(s.Participants) {
		return false
	}
	last := s.Participants[i].LastSeen
	if last == 0 {
		return false
	}
	return now.Sub(time.UnixMilli(last)) <= window
}
