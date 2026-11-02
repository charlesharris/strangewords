package sessions

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

// tradeSession is a two-human haiku session for the domain tests.
func tradeSession(status Status, poems, start int) *Session {
	return &Session{
		ID:           "sess-trade",
		Participants: []Participant{{Token: "tok-a", LastSeen: 11}, {Token: "tok-b", LastSeen: 22}},
		StartIndex:   start,
		Bucket:       "haiku",
		CreatedAt:    5,
		Status:       status,
		FormID:       "haiku",
		PolicyID:     DefaultPolicyID,
		Lines:        []string{"one", "two", "three"},
		CurrentLine:  3,
		CompletedAt:  9,
		BotReadyAt:   7,
		PoemCount:    poems,
		IdemKeys:     []string{"k0", "k1"},
	}
}

func TestPoemTwoSwapsRoles(t *testing.T) {
	for start := 0; start < 2; start++ {
		for _, poems := range []int{1, 0} { // 0 is a pre-Phase-6 blob
			s := tradeSession(StatusComplete, poems, start)
			opener, other := s.AuthorOf(0), 1-s.AuthorOf(0)
			if opener != start || s.AuthorOf(2) != opener || s.AuthorOf(1) != other {
				t.Fatalf("start %d poems %d: poem 1 roles wrong: %d %d %d", start, poems, s.AuthorOf(0), s.AuthorOf(1), s.AuthorOf(2))
			}
			s.BeginNextPoem()
			if s.AuthorOf(1) != opener || s.AuthorOf(0) != other || s.AuthorOf(2) != other {
				t.Fatalf("start %d poems %d: poem 2 roles did not swap: %d %d %d", start, poems, s.AuthorOf(0), s.AuthorOf(1), s.AuthorOf(2))
			}
			if s.StartIndex != start {
				t.Fatalf("StartIndex mutated: %d, want %d", s.StartIndex, start)
			}
		}
	}
}

func TestTradeOpen(t *testing.T) {
	bot := func(s *Session) *Session {
		s.Participants[1] = Participant{Bot: true, Dismissed: true}
		return s
	}
	human := func(s *Session) *Session { s.Participants[0].Dismissed = true; return s }
	cases := []struct {
		name string
		s    *Session
		want bool
	}{
		{"active poem 1", tradeSession(StatusActive, 1, 0), false},
		{"complete poem 1", tradeSession(StatusComplete, 1, 0), true},
		{"complete poem 2", tradeSession(StatusComplete, 2, 0), false},
		{"complete poem 1, a human let go", human(tradeSession(StatusComplete, 1, 0)), false},
		{"complete poem 1, only the pre-dismissed robot poet", bot(tradeSession(StatusComplete, 1, 0)), true},
	}
	for _, c := range cases {
		if got := c.s.TradeOpen(); got != c.want {
			t.Errorf("%s: TradeOpen = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestBeginNextPoemKeepsTheEncounter(t *testing.T) {
	s := tradeSession(StatusComplete, 1, 1)
	s.Participants[0].WantsTrade = true
	s.Participants[1].WantsTrade = true
	before := *s
	before.Participants = append([]Participant(nil), s.Participants...)

	s.BeginNextPoem()

	if s.ID != before.ID || s.StartIndex != before.StartIndex || s.Bucket != before.Bucket || s.CreatedAt != before.CreatedAt ||
		s.FormID != before.FormID || s.PolicyID != before.PolicyID || !reflect.DeepEqual(s.IdemKeys, before.IdemKeys) {
		t.Fatalf("encounter fields changed: %+v", s)
	}
	for i, p := range s.Participants {
		if p.Token != before.Participants[i].Token || p.LastSeen != before.Participants[i].LastSeen || p.Dismissed != before.Participants[i].Dismissed || p.Bot != before.Participants[i].Bot {
			t.Fatalf("participant %d changed: %+v", i, p)
		}
		if p.WantsTrade {
			t.Fatalf("participant %d still wants a trade", i)
		}
	}
	if s.Status != StatusActive || s.Lines == nil || len(s.Lines) != 0 || s.CurrentLine != 0 || s.CompletedAt != 0 || s.BotReadyAt != 0 || s.PoemCount != 2 {
		t.Fatalf("poem-level fields not reset: %+v", s)
	}
}

func TestViewForTradeFields(t *testing.T) {
	s := tradeSession(StatusComplete, 1, 0)
	s.Participants[0].WantsTrade = true
	a, b := s.ViewFor("tok-a"), s.ViewFor("tok-b")
	if !a.YouWantTrade || a.PartnerWantsTrade || b.YouWantTrade || !b.PartnerWantsTrade {
		t.Fatalf("flags wrong: a=%+v b=%+v", a, b)
	}
	if !a.TradeOpen || a.PoemNumber != 1 {
		t.Fatalf("complete poem 1 should be tradeable: %+v", a)
	}

	active := tradeSession(StatusActive, 1, 0)
	raw, err := json.Marshal(active.ViewFor("tok-a"))
	if err != nil {
		t.Fatal(err)
	}
	body := string(raw)
	if !strings.Contains(body, `"poemNumber":1`) {
		t.Fatalf("poemNumber missing: %s", body)
	}
	for _, key := range []string{"tradeOpen", "youWantTrade", "partnerWantsTrade"} {
		if strings.Contains(body, key) {
			t.Fatalf("%s must be omitted on an active poem 1: %s", key, body)
		}
	}
}
