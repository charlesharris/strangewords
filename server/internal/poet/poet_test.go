package poet

import (
	"fmt"
	"strings"
	"testing"

	"strangewords/internal/sessions"
)

// cleanIdentical reports whether the server would accept line unchanged.
func cleanIdentical(line string) bool {
	got, err := sessions.CleanLine(line)
	return err == nil && got == line
}

func TestLineHitsTarget(t *testing.T) {
	for seed := uint64(1); seed <= 50; seed++ {
		for _, target := range []int{5, 7} {
			p := New(seed)
			line := p.Line(target, nil)
			if line == "" {
				t.Fatalf("seed %d target %d: empty line", seed, target)
			}
			if got := Count(line); got != target {
				t.Errorf("seed %d target %d: %q counts %d", seed, target, line, got)
			}
			if !cleanIdentical(line) {
				t.Errorf("seed %d target %d: %q not CleanLine-identical", seed, target, line)
			}
		}
		if got := Count(New(seed).Line(0, nil)); got != 5 && got != 7 {
			t.Errorf("seed %d target 0: counts %d, want 5 or 7", seed, got)
		}
	}
}

// poem composes a 5,7,5 poem from seed, feeding each line back as context.
func poem(seed uint64) (*Poet, []string) {
	p := New(seed)
	var lines []string
	for _, target := range []int{5, 7, 5} {
		lines = append(lines, p.Line(target, lines))
	}
	return p, lines
}

func eachBank(f func(th *theme, pos string, b *bySyl)) {
	for i := range themes {
		th := &themes[i]
		f(th, "noun", &th.nouns)
		f(th, "adjective", &th.adjs)
		f(th, "verb", &th.verbs)
	}
}

func TestBankShape(t *testing.T) {
	if len(themes) < 5 {
		t.Fatalf("%d themes, want at least 5", len(themes))
	}
	mins := map[string][4]int{
		"noun":      {0, 6, 6, 3},
		"adjective": {0, 5, 5, 0},
		"verb":      {0, 5, 5, 0},
	}
	eachBank(func(th *theme, pos string, b *bySyl) {
		for c := 1; c <= 3; c++ {
			if got := len(b[c]); got < mins[pos][c] {
				t.Errorf("%s %ss at %d syllables: %d, want at least %d", th.name, pos, c, got, mins[pos][c])
			}
		}
	})
	if len(preps[1]) == 0 || len(preps[2]) == 0 {
		t.Error("preps needs 1- and 2-syllable buckets")
	}
}

func TestBankCountsMatchEstimator(t *testing.T) {
	check := func(where string, b *bySyl) {
		for c := 1; c <= 3; c++ {
			for _, w := range b[c] {
				if got := Count(w); got != c {
					t.Errorf("%s: %q is bucketed %d but Count says %d", where, w, c, got)
				}
			}
		}
	}
	check("preps", &preps)
	eachBank(func(th *theme, pos string, b *bySyl) { check(th.name+" "+pos, b) })
}

func TestBankWordsUnique(t *testing.T) {
	seen := map[string]string{}
	for _, w := range []string{"the", "a", "an", "of", "and"} {
		seen[w] = "template literal"
	}
	add := func(where string, b *bySyl) {
		for c := 1; c <= 3; c++ {
			for _, w := range b[c] {
				if prev, dup := seen[w]; dup {
					t.Errorf("%q in %s is already in %s", w, where, prev)
				}
				seen[w] = where
			}
		}
	}
	add("preps", &preps)
	eachBank(func(th *theme, pos string, b *bySyl) { add(th.name+" "+pos, b) })
}

func TestSeedSweepHitsTargets(t *testing.T) {
	for seed := uint64(1); seed <= 500; seed++ {
		p := New(seed)
		var lines []string
		for _, target := range []int{5, 7, 5} {
			line := p.Line(target, lines)
			lines = append(lines, line)
			if line == "" || Count(line) != target || !cleanIdentical(line) {
				t.Fatalf("seed %d: %q for target %d (counts %d, clean %v)", seed, line, target, Count(line), cleanIdentical(line))
			}
		}
	}
}

func TestSameSeedSameTheme(t *testing.T) {
	for seed := uint64(1); seed <= 100; seed++ {
		a, la := poem(seed)
		b, lb := poem(seed)
		if a.Theme() != b.Theme() || strings.Join(la, "|") != strings.Join(lb, "|") {
			t.Fatalf("seed %d not deterministic: %q %v vs %q %v", seed, a.Theme(), la, b.Theme(), lb)
		}
	}
}

func TestThemeVariety(t *testing.T) {
	names := map[string]bool{}
	openings := map[string]bool{}
	for seed := uint64(1); seed <= 200; seed++ {
		p := New(seed)
		names[p.Theme()] = true
		openings[p.Line(7, nil)] = true
	}
	for _, th := range themes {
		if !names[th.name] {
			t.Errorf("theme %q never chosen in 200 seeds", th.name)
		}
	}
	if len(openings) < 120 {
		t.Errorf("only %d distinct openings in 200 seeds, want at least 120", len(openings))
	}
}

func TestLinesStayInTheme(t *testing.T) {
	for seed := uint64(1); seed <= 200; seed++ {
		p := New(seed)
		ok := map[string]bool{"the": true, "a": true, "an": true, "of": true, "and": true}
		for c := 1; c <= 3; c++ {
			for _, w := range preps[c] {
				ok[w] = true
			}
		}
		th := &themes[p.theme]
		for _, b := range []*bySyl{&th.nouns, &th.adjs, &th.verbs} {
			for c := 1; c <= 3; c++ {
				for _, w := range b[c] {
					ok[w] = true
				}
			}
		}
		for _, target := range []int{5, 7, 5} {
			line := p.Line(target, nil)
			for _, w := range words(line) {
				if !ok[w] {
					t.Errorf("seed %d (%s): %q has off-theme word %q", seed, th.name, line, w)
				}
			}
		}
	}
}

func TestNoRepeatedWordsInPoem(t *testing.T) {
	bank := map[string]bool{}
	eachBank(func(_ *theme, _ string, b *bySyl) {
		for c := 1; c <= 3; c++ {
			for _, w := range b[c] {
				bank[w] = true
			}
		}
	})
	for seed := uint64(1); seed <= 200; seed++ {
		_, lines := poem(seed)
		seen := map[string]bool{}
		for _, line := range lines {
			for _, w := range words(line) {
				if bank[w] && seen[w] {
					t.Errorf("seed %d: %q repeats %q", seed, lines, w)
				}
				seen[w] = true
			}
		}
	}
}

func TestNearestFitNeverEmpty(t *testing.T) {
	for seed := uint64(1); seed <= 50; seed++ {
		for _, target := range []int{1, 2, 30, 0, -1} {
			line := New(seed).Line(target, nil)
			c := Count(line)
			switch {
			case line == "" || !cleanIdentical(line):
				t.Errorf("seed %d target %d: bad line %q", seed, target, line)
			case (target == 1 || target == 2) && c > 4:
				t.Errorf("seed %d target %d: %q counts %d, want at most 4", seed, target, line, c)
			case target == 30 && c < 10:
				t.Errorf("seed %d target 30: %q counts %d, want at least 10", seed, line, c)
			case target <= 0 && c != 5 && c != 7:
				t.Errorf("seed %d target %d: %q counts %d, want 5 or 7", seed, target, line, c)
			}
		}
	}
}

func ExamplePoet_Line() {
	p := New(7)
	line := p.Line(5, nil)
	fmt.Println(Count(line))
	// Output: 5
}
