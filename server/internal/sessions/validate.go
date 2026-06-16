package sessions

import (
	"errors"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

// MaxLineLen is the cap on a submitted line in characters (runes). [TUNABLE]
const MaxLineLen = 100

var (
	ErrEmptyLine = errors.New("line is empty")
	ErrLineTooLong = errors.New("line exceeds maximum length")
	ErrBadChars  = errors.New("line contains disallowed characters")
)

// CleanLine normalizes and validates a submitted line. It never checks
// syllables (brief.v4.md §9). Returns the cleaned text or an error.
func CleanLine(raw string) (string, error) {
	// Normalize to NFC first so length and character checks are stable.
	s := norm.NFC.String(raw)

	// Reject control characters (except none are allowed; newlines included).
	for _, r := range s {
		if r == '\n' || r == '\r' || r == '\t' {
			// collapse handled below; treat as whitespace, not a hard reject
			continue
		}
		if unicode.IsControl(r) {
			return "", ErrBadChars
		}
	}

	// Collapse any run of whitespace (incl. tabs/newlines) to a single space,
	// then trim. Zero-width characters are stripped.
	s = stripZeroWidth(s)
	s = collapseWhitespace(s)
	s = strings.TrimSpace(s)

	if s == "" {
		return "", ErrEmptyLine
	}
	if len([]rune(s)) > MaxLineLen {
		return "", ErrLineTooLong
	}
	return s, nil
}

func collapseWhitespace(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	prevSpace := false
	for _, r := range s {
		if unicode.IsSpace(r) {
			if !prevSpace {
				b.WriteRune(' ')
			}
			prevSpace = true
			continue
		}
		b.WriteRune(r)
		prevSpace = false
	}
	return b.String()
}

func stripZeroWidth(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		switch r {
		case 0x200B, 0x200C, 0x200D, 0xFEFF, 0x2060:
			// zero-width space / non-joiner / joiner / BOM / word-joiner
			continue
		}
		b.WriteRune(r)
	}
	return b.String()
}
