package sessions

import (
	"errors"
	"testing"
)

func TestScreenerMatching(t *testing.T) {
	sc := NewScreener([]string{"badword"})

	reject := []string{
		"badword",
		"a badword here",
		"BADWORD",       // case-folded
		"b4dword",       // leet 4 -> a
		"b@dword",       // leet @ -> a
		"...badword!!!", // surrounded by punctuation
	}
	for _, s := range reject {
		if !sc.Rejects(s) {
			t.Errorf("expected reject: %q", s)
		}
	}

	allow := []string{
		"a gentle word",
		"badwordsmith", // banned term is a substring of one token — Scunthorpe guard
		"word bad",     // tokens present but not the banned token
		"",
	}
	for _, s := range allow {
		if sc.Rejects(s) {
			t.Errorf("expected allow: %q", s)
		}
	}
}

func TestDefaultScreenerLoaded(t *testing.T) {
	if defaultScreener.Len() == 0 {
		t.Fatal("default screener loaded no terms from banned_terms.txt")
	}
}

// TestCleanLineScreens confirms CleanLine routes a banned line to
// ErrContentRejected (using a placeholder term, not a real slur) while clean
// poetry passes.
func TestCleanLineScreens(t *testing.T) {
	old := defaultScreener
	defaultScreener = NewScreener([]string{"badword"})
	t.Cleanup(func() { defaultScreener = old })

	if _, err := CleanLine("the badword falls"); !errors.Is(err, ErrContentRejected) {
		t.Fatalf("banned line: got %v, want ErrContentRejected", err)
	}
	if got, err := CleanLine("cherry blossoms fall"); err != nil {
		t.Fatalf("clean line rejected: %v (%q)", err, got)
	}
}
