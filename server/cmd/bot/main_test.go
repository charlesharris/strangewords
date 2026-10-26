package main

import (
	"slices"
	"strings"
	"testing"
	"unicode"

	"strangewords/internal/poet"
	"strangewords/internal/sessions"
)

func haikuView(t *testing.T, current int, lines []string) sessions.View {
	t.Helper()
	f := sessions.LookupForm("haiku")
	return sessions.View{
		Form:        sessions.FormView{ID: f.ID, Targets: f.Targets},
		CurrentLine: current,
		Lines:       lines,
	}
}

func TestComposeLineFollowsForm(t *testing.T) {
	for seed := uint64(1); seed <= 50; seed++ {
		p := poet.New(seed)
		var lines []string
		for i := 0; i < 3; i++ {
			v := haikuView(t, i, lines)
			line := composeLine(p, v)
			if want := *v.Form.Targets[i]; poet.Count(line) != want {
				t.Errorf("seed %d line %d: %q counts %d, want %d", seed, i, line, poet.Count(line), want)
			}
			if got, err := sessions.CleanLine(line); err != nil || got != line {
				t.Errorf("seed %d line %d: %q not CleanLine-identical", seed, i, line)
			}
			lines = append(lines, line)
		}
	}
}

func TestComposeLineFreeVerse(t *testing.T) {
	for seed := uint64(1); seed <= 50; seed++ {
		v := sessions.View{Form: sessions.FormView{Targets: []*int{nil}}}
		line := composeLine(poet.New(seed), v)
		if c := poet.Count(line); c != 5 && c != 7 {
			t.Errorf("seed %d: %q counts %d, want 5 or 7", seed, line, c)
		}
	}
}

func TestComposeLineEchoesPartner(t *testing.T) {
	hits := 0
	for seed := uint64(1); seed <= 50; seed++ {
		v := haikuView(t, 1, []string{"a heron folds into mist"})
		toks := strings.FieldsFunc(composeLine(poet.New(seed), v), func(r rune) bool { return !unicode.IsLetter(r) })
		for _, w := range []string{"heron", "folds", "mist"} {
			if slices.Contains(toks, w) {
				hits++
				break
			}
		}
	}
	if hits < 25 {
		t.Errorf("only %d of 50 lines echoed the partner, want at least 25", hits)
	}
}

func TestSeedFor(t *testing.T) {
	if seedFor("abc") != seedFor("abc") {
		t.Error("seedFor is not stable")
	}
	if seedFor("a") == seedFor("b") {
		t.Error("seedFor collides on a and b")
	}
}
