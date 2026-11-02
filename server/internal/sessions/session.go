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
	// Bot marks the robot poet. It has no token or push token and is created
	// already dismissed, so a human's single dismiss dissolves the session.
	Bot bool `json:"bot,omitempty"`
	// WantsTrade records that the participant asked to trade back after the
	// current poem's reveal (Phase 6 D-02). Offer and acceptance are the same
	// signal, and the flag is reset when the next poem begins.
	WantsTrade bool `json:"wantsTrade,omitempty"`
}

// MaxPoems is how many poems one encounter holds: the first, and one trade back
// (D-01, D-02). It is a product rule, not a tunable.
const MaxPoems = 2

// Session is the encounter between participants plus its current poem.
// Encounter-level fields are stable across poems; poem-level fields reset when
// a trade back (Phase 6) begins the next poem in the same encounter, see
// BeginNextPoem (plan.v1.md §6, §13).
type Session struct {
	// Encounter-level
	ID           string        `json:"id"`
	Participants []Participant `json:"participants"`
	StartIndex   int           `json:"startIndex"`
	Bucket       string        `json:"bucket"`
	CreatedAt    int64         `json:"createdAt"`
	// PoemCount is the encounter's poem ordinal: 1 for the first poem.
	PoemCount int `json:"poemCount"`
	// IdemKeys is the teardown list, spanning every poem, so dissolution erases
	// every cached response (poem content).
	IdemKeys []string `json:"idemKeys,omitempty"`

	// Poem-level
	Status      Status   `json:"status"`
	FormID      string   `json:"formId"`
	PolicyID    string   `json:"policyId"`
	Lines       []string `json:"lines"`
	CurrentLine int      `json:"currentLine"`
	CompletedAt int64    `json:"completedAt,omitempty"`
	// BotReadyAt is unix millis: the earliest moment the robot poet may write
	// its current line (think time).
	BotReadyAt int64 `json:"botReadyAt,omitempty"`
}

func (s *Session) form() Form         { return LookupForm(s.FormID) }
func (s *Session) policy() TurnPolicy { return LookupPolicy(s.PolicyID) }

// CurrentAuthor is the participant index whose turn it is, derived (never
// stored) from the TurnPolicy.
func (s *Session) CurrentAuthor() int {
	return s.AuthorOf(s.CurrentLine)
}

// AuthorOf is the participant index the policy assigns to the given line.
func (s *Session) AuthorOf(line int) int {
	return s.policy().Author(line, len(s.Participants), s.poemStart())
}

// poemStart is the start offset of the current poem. Roles swap per poem by
// deriving it from the poem ordinal (Phase 6 D-03), so StartIndex is never
// mutated and the turn policy is untouched. A pre-Phase-6 blob (PoemCount 0)
// is poem 1.
func (s *Session) poemStart() int {
	n := len(s.Participants)
	if n == 0 {
		return 0
	}
	return (s.StartIndex + max(s.PoemCount-1, 0)) % n
}

// TradeOpen reports whether the current reveal may still be traded back: the
// poem is complete, it is not the last allowed poem, and no human has let go.
// The robot poet is created pre-dismissed, so bots are skipped.
func (s *Session) TradeOpen() bool {
	if s.Status != StatusComplete || s.PoemCount >= MaxPoems {
		return false
	}
	for _, p := range s.Participants {
		if !p.Bot && p.Dismissed {
			return false
		}
	}
	return true
}

// AnyWantsTrade reports whether some participant has asked to trade back.
func (s *Session) AnyWantsTrade() bool {
	for _, p := range s.Participants {
		if p.WantsTrade {
			return true
		}
	}
	return false
}

// AllWantTrade reports whether every participant has asked to trade back.
func (s *Session) AllWantTrade() bool {
	for _, p := range s.Participants {
		if !p.WantsTrade {
			return false
		}
	}
	return len(s.Participants) > 0
}

// HasBot reports whether any participant is the robot poet.
func (s *Session) HasBot() bool {
	for _, p := range s.Participants {
		if p.Bot {
			return true
		}
	}
	return false
}

// BotTradeDue reports whether the robot poet owes an acceptance: the reveal is
// still tradeable, some human has asked, and some bot has not answered. The
// robot poet only ever accepts, never offers (D-06).
func (s *Session) BotTradeDue() bool {
	if !s.TradeOpen() {
		return false
	}
	human, bot := false, false
	for _, p := range s.Participants {
		switch {
		case !p.Bot && p.WantsTrade:
			human = true
		case p.Bot && !p.WantsTrade:
			bot = true
		}
	}
	return human && bot
}

// BeginNextPoem resets the poem-level fields in place and bumps the poem
// ordinal (Phase 6 D-01, D-03). The encounter persists: ID, Participants
// (tokens, LastSeen, Dismissed, Bot), StartIndex, Bucket, CreatedAt, FormID,
// PolicyID and IdemKeys are kept. Every WantsTrade is cleared. Callers arm
// BotReadyAt when the robot poet opens the new poem.
func (s *Session) BeginNextPoem() {
	s.PoemCount = max(s.PoemCount, 1) + 1
	s.Status = StatusActive
	s.Lines = []string{}
	s.CurrentLine = 0
	s.CompletedAt = 0
	s.BotReadyAt = 0
	for i := range s.Participants {
		s.Participants[i].WantsTrade = false
	}
}

// BotTurn reports whether the session is active and the robot poet authors the
// current line.
func (s *Session) BotTurn() bool {
	if s.Status != StatusActive {
		return false
	}
	a := s.CurrentAuthor()
	return a >= 0 && a < len(s.Participants) && s.Participants[a].Bot
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
	SessionID        string   `json:"sessionId"`
	You              int      `json:"you"`
	ParticipantCount int      `json:"participantCount"`
	Status           Status   `json:"status"`
	Form             FormView `json:"form"`
	CurrentLine      int      `json:"currentLine"`
	CurrentAuthor    int      `json:"currentAuthor"`
	YourTurn         bool     `json:"yourTurn"`
	Lines            []string `json:"lines"`
	// PartnerIsBot is true when any other participant is the robot poet. It is
	// computed only in ViewFor (D-04), never read from a request.
	PartnerIsBot bool `json:"partnerIsBot,omitempty"`
	// The trade fields are computed only in ViewFor, never read from a request
	// (Phase 6 D-02). PoemNumber is the encounter's poem ordinal; TradeOpen says
	// the reveal may still be traded back; the two flags are the caller's own and
	// the partner's ask.
	PoemNumber        int  `json:"poemNumber,omitempty"`
	TradeOpen         bool `json:"tradeOpen,omitempty"`
	YouWantTrade      bool `json:"youWantTrade,omitempty"`
	PartnerWantsTrade bool `json:"partnerWantsTrade,omitempty"`
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
	partnerIsBot, partnerWants := false, false
	for i, p := range s.Participants {
		if i != you && p.Bot {
			partnerIsBot = true
		}
		if i != you && p.WantsTrade {
			partnerWants = true
		}
	}
	youWant := you >= 0 && you < len(s.Participants) && s.Participants[you].WantsTrade
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
		PartnerIsBot:     partnerIsBot,

		PoemNumber:        max(s.PoemCount, 1),
		TradeOpen:         s.TradeOpen(),
		YouWantTrade:      youWant,
		PartnerWantsTrade: partnerWants,
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
