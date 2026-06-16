package sessions

import "testing"

func TestRoundRobinHaikuIsABA(t *testing.T) {
	p := LookupPolicy("round-robin")
	// Two participants over three lines, starting with participant 0:
	// the haiku A-B-A falls out for free.
	got := []int{
		p.Author(0, 2, 0),
		p.Author(1, 2, 0),
		p.Author(2, 2, 0),
	}
	want := []int{0, 1, 0}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("start=0 line %d: got %d want %d (seq %v)", i, got[i], want[i], got)
		}
	}
}

func TestRoundRobinStartOffset(t *testing.T) {
	p := roundRobin{}
	// Starting with participant 1 mirrors the pattern: B-A-B.
	want := []int{1, 0, 1}
	for i, w := range want {
		if g := p.Author(i, 2, 1); g != w {
			t.Fatalf("start=1 line %d: got %d want %d", i, g, w)
		}
	}
}

func TestRoundRobinCircles(t *testing.T) {
	// Interface is N-ready even though v1 never runs n>2.
	p := roundRobin{}
	for n := 3; n <= 4; n++ {
		for line := 0; line < 2*n; line++ {
			want := line % n
			if g := p.Author(line, n, 0); g != want {
				t.Fatalf("n=%d line=%d: got %d want %d", n, line, g, want)
			}
		}
	}
}

func TestLookupFallbacks(t *testing.T) {
	if LookupForm("nonexistent").ID != DefaultFormID {
		t.Fatal("unknown form should fall back to default")
	}
	if LookupPolicy("nonexistent").ID() != DefaultPolicyID {
		t.Fatal("unknown policy should fall back to default")
	}
	if LookupForm("haiku").LineCount() != 3 {
		t.Fatal("haiku should have 3 lines")
	}
}
