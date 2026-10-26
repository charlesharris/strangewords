package poet

import (
	"slices"
	"testing"
)

func TestContentWords(t *testing.T) {
	cases := []struct {
		in   []string
		want []string
	}{
		{[]string{"An old silent pond", "The moon, the MOON!"}, []string{"old", "silent", "pond", "moon"}},
		{[]string{"don't wait for the moon"}, []string{"wait", "moon"}},
		{[]string{"it is a, an; to"}, nil},
	}
	for _, c := range cases {
		if got := contentWords(c.in); !slices.Equal(got, c.want) {
			t.Errorf("contentWords(%q) = %q, want %q", c.in, got, c.want)
		}
	}
	for _, w := range []string{"the", "still", "anymore", "maybe", "between"} {
		if !stopwords[w] {
			t.Errorf("%q should be a stopword", w)
		}
	}
}

// echoPoet returns a Poet with the echo rolls pinned.
func echoPoet(seed uint64, echo, adjacent float64) *Poet {
	p := New(seed)
	p.echoChance, p.adjacentChance = echo, adjacent
	return p
}

func hasWord(line, w string) bool { return slices.Contains(words(line), w) }

func TestEchoDirect(t *testing.T) {
	for seed := uint64(1); seed <= 200; seed++ {
		p := echoPoet(seed, 1, 0)
		line := p.Line(7, []string{"a heron folds into mist"})
		if !slices.Contains([]string{"heron", "folds", "mist"}, p.lastEcho) {
			t.Fatalf("seed %d: lastEcho %q, line %q", seed, p.lastEcho, line)
		}
		if !hasWord(line, p.lastEcho) || Count(line) != 7 {
			t.Errorf("seed %d: %q (echo %q) counts %d", seed, line, p.lastEcho, Count(line))
		}
	}
}

func TestEchoUnknownWord(t *testing.T) {
	for seed := uint64(1); seed <= 200; seed++ {
		p := echoPoet(seed, 1, 0)
		line := p.Line(5, []string{"the lighthouse keeper hums"})
		if !slices.Contains([]string{"lighthouse", "keeper", "hums"}, p.lastEcho) {
			t.Fatalf("seed %d: lastEcho %q, line %q", seed, p.lastEcho, line)
		}
		if !hasWord(line, p.lastEcho) || Count(line) != 5 {
			t.Errorf("seed %d: %q (echo %q) counts %d", seed, line, p.lastEcho, Count(line))
		}
	}
}

func TestEchoOverBudgetSkipped(t *testing.T) {
	for seed := uint64(1); seed <= 50; seed++ {
		p := echoPoet(seed, 1, 0)
		line := p.Line(5, []string{"incomprehensibility"})
		if p.lastEcho != "" || hasWord(line, "incomprehensibility") || Count(line) != 5 {
			t.Errorf("seed %d: %q echo %q counts %d", seed, line, p.lastEcho, Count(line))
		}
	}
}

func TestEchoStopwordsOnly(t *testing.T) {
	for seed := uint64(1); seed <= 50; seed++ {
		for _, target := range []int{5, 7} {
			p := echoPoet(seed, 1, 1)
			line := p.Line(target, []string{"and the with"})
			if p.lastEcho != "" || Count(line) != target {
				t.Errorf("seed %d target %d: %q echo %q", seed, target, line, p.lastEcho)
			}
		}
	}
}

func TestEchoIgnoresOwnLines(t *testing.T) {
	for seed := uint64(1); seed <= 100; seed++ {
		p := echoPoet(seed, 1, 0)
		l0 := p.Line(5, nil)
		p.Line(7, []string{l0, "the lighthouse hums"})
		if p.lastEcho != "lighthouse" && p.lastEcho != "hums" {
			t.Errorf("seed %d: lastEcho %q after own line %q", seed, p.lastEcho, l0)
		}
	}
}

func TestEchoThemeAdjacent(t *testing.T) {
	for k := range themes {
		w := themes[k].nouns[2][0]
		for seed := uint64(1); seed <= 50; seed++ {
			p := echoPoet(seed, 1, 1)
			line := p.Line(7, []string{w})
			isNoun := false
			for c := 1; c <= 3; c++ {
				isNoun = isNoun || slices.Contains(themes[k].nouns[c], p.lastEcho)
			}
			if p.lastEcho == "" || p.lastEcho == w || !isNoun || !hasWord(line, p.lastEcho) || Count(line) != 7 {
				t.Errorf("theme %s seed %d: %q echo %q (from %q)", themes[k].name, seed, line, p.lastEcho, w)
			}
		}
	}
}

func TestSeedSweepWithPartner(t *testing.T) {
	partners := []string{
		"the old pond is quiet",
		"don't you wonder where it goes",
		"incomprehensibility",
		"a cat sleeps on the warm windowsill",
	}
	for seed := uint64(1); seed <= 500; seed++ {
		p := New(seed)
		var lines []string
		for i, target := range []int{5, 7, 5} {
			lines = append(lines, partners[(int(seed)+i)%len(partners)])
			line := p.Line(target, lines)
			if line == "" || Count(line) != target || !cleanIdentical(line) {
				t.Fatalf("seed %d line %d: %q for target %d (counts %d)", seed, i, line, target, Count(line))
			}
			lines = append(lines, line)
		}
	}
}
