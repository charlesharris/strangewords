package poet

import (
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
