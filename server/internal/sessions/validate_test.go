package sessions

import (
	"strings"
	"testing"
)

func TestCleanLineAccepts(t *testing.T) {
	got, err := CleanLine("  an old   silent\tpond  ")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "an old silent pond" {
		t.Fatalf("whitespace not collapsed/trimmed: %q", got)
	}
}

func TestCleanLineRejectsEmpty(t *testing.T) {
	for _, in := range []string{"", "   ", "\t\n", "​​"} {
		if _, err := CleanLine(in); err != ErrEmptyLine {
			t.Fatalf("CleanLine(%q): got %v want ErrEmptyLine", in, err)
		}
	}
}

func TestCleanLineRejectsTooLong(t *testing.T) {
	long := strings.Repeat("a", MaxLineLen+1)
	if _, err := CleanLine(long); err != ErrLineTooLong {
		t.Fatalf("got %v want ErrLineTooLong", err)
	}
	ok := strings.Repeat("a", MaxLineLen)
	if _, err := CleanLine(ok); err != nil {
		t.Fatalf("max-length line should pass: %v", err)
	}
}

func TestCleanLineRejectsControl(t *testing.T) {
	if _, err := CleanLine("hello\x07world"); err != ErrBadChars {
		t.Fatalf("got %v want ErrBadChars", err)
	}
}

func TestCleanLineStripsZeroWidth(t *testing.T) {
	got, err := CleanLine("frog​jumps")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "frogjumps" {
		t.Fatalf("zero-width not stripped: %q", got)
	}
}
