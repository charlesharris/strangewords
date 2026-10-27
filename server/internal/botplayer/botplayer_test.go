package botplayer

import (
	"fmt"
	"testing"

	"strangewords/internal/poet"
	"strangewords/internal/sessions"
)

// humanLines are varied accepted lines, including words the poet can echo.
var humanLines = []string{
	"a heron folds into mist",
	"the lantern hums softly",
	"somewhere a kettle sings",
	"rain on the tin roof tonight",
}

func humanLine(i int) string { return humanLines[i%len(humanLines)] }

// botSession builds a human(0)+bot(1) haiku session. startIndex 1 makes the bot
// author lines 0 and 2; startIndex 0 makes it author line 1.
func botSession(id string, startIndex int, lines []string) *sessions.Session {
	return &sessions.Session{
		ID: id,
		Participants: []sessions.Participant{
			{Token: "human"},
			{Bot: true, Dismissed: true},
		},
		StartIndex:  startIndex,
		Status:      sessions.StatusActive,
		FormID:      "haiku",
		PolicyID:    sessions.DefaultPolicyID,
		Lines:       lines,
		CurrentLine: len(lines),
	}
}

func TestSeedIsStable(t *testing.T) {
	if Seed("abc") != Seed("abc") {
		t.Error("Seed is not stable")
	}
	if Seed("a") == Seed("b") {
		t.Error("Seed collides on a and b")
	}
}

func TestNextLineReplaysDeterministically(t *testing.T) {
	for n := 1; n <= 500; n++ {
		id := fmt.Sprintf("sess-%d", n)
		h := humanLine(n)

		// Bot-first: bot writes lines 0 and 2.
		p := poet.New(Seed(id))
		want0 := p.Line(5, nil)
		if got := NextLine(botSession(id, 1, nil)); got != want0 {
			t.Fatalf("%s line 0: got %q want %q", id, got, want0)
		}
		prev := []string{want0, h}
		want2 := p.Line(5, prev)
		if got := NextLine(botSession(id, 1, prev)); got != want2 {
			t.Fatalf("%s line 2: got %q want %q", id, got, want2)
		}

		// Human-first: bot writes line 1.
		q := poet.New(Seed(id))
		want1 := q.Line(7, []string{h})
		if got := NextLine(botSession(id, 0, []string{h})); got != want1 {
			t.Fatalf("%s human-first line 1: got %q want %q", id, got, want1)
		}
	}
}

func TestNextLineIsCleanAndOnTarget(t *testing.T) {
	form := sessions.LookupForm("haiku")
	for n := 1; n <= 200; n++ {
		for start := 0; start < 2; start++ {
			id := fmt.Sprintf("clean-%d", n)
			var lines []string
			for i := 0; i < form.LineCount(); i++ {
				s := botSession(id, start, lines)
				if s.CurrentAuthor() != 1 { // index 1 is the bot
					lines = append(lines, humanLine(n+i))
					continue
				}
				r := NextLine(s)
				if got, err := sessions.CleanLine(r); err != nil || got != r {
					t.Fatalf("%s start %d line %d: %q not CleanLine-identical (%v)", id, start, i, r, err)
				}
				if want := *form.Targets[i]; poet.Count(r) != want {
					t.Fatalf("%s start %d line %d: %q counts %d, want %d", id, start, i, r, poet.Count(r), want)
				}
				lines = append(lines, r)
			}
		}
	}
}

func TestFallbackLineIsClean(t *testing.T) {
	if got, err := sessions.CleanLine(fallbackLine); err != nil || got != fallbackLine {
		t.Fatalf("fallback %q not CleanLine-identical (%v)", fallbackLine, err)
	}
}
