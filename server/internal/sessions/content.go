package sessions

import (
	_ "embed"
	"errors"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

// ErrContentRejected is returned for a line that trips the abuse filter. Its
// message is deliberately generic and never echoes the matched term.
var ErrContentRejected = errors.New("content not allowed")

// bannedTerms is a minimal seed list of unambiguous slurs, kept in a data file
// (not source) and loaded at init. It targets hate slurs only — the brief errs
// toward allowing creative expression (brief.v4.md §8), so general profanity is
// intentionally not policed. Operators should replace this with a maintained,
// externally-sourced list before a wide release.
//
//go:embed banned_terms.txt
var bannedTerms string

var defaultScreener = NewScreener(parseTermList(bannedTerms))

// Screener rejects lines containing a banned term. It matches whole tokens
// after folding (lowercase, diacritic-strip, light leet-fold), so it avoids the
// Scunthorpe problem — an innocent word that merely contains a banned substring
// is never flagged. Known limitation: a slur split by interior symbols (e.g. a
// star in the middle) tokenizes apart and slips through; a maintained filter
// would layer on more, but this is the conservative v1 floor.
type Screener struct {
	banned map[string]struct{}
}

// NewScreener builds a screener from raw terms. Exported so the matching logic
// can be tested with placeholder words instead of real slurs.
func NewScreener(terms []string) *Screener {
	s := &Screener{banned: make(map[string]struct{}, len(terms))}
	for _, t := range terms {
		if f := fold(t); f != "" {
			s.banned[f] = struct{}{}
		}
	}
	return s
}

// Rejects reports whether any token of the line matches a banned term.
func (sc *Screener) Rejects(line string) bool {
	for _, tok := range strings.FieldsFunc(line, isSeparator) {
		if f := fold(tok); f != "" {
			if _, ok := sc.banned[f]; ok {
				return true
			}
		}
	}
	return false
}

// Len reports how many terms loaded — used to assert the seed list is non-empty.
func (sc *Screener) Len() int { return len(sc.banned) }

// isSeparator splits the line into tokens. '@' and '$' are kept inside tokens
// (not treated as separators) so the leet substitutions @->a and $->s in fold
// can still match; all other non-alphanumerics separate.
func isSeparator(r rune) bool {
	if r == '@' || r == '$' {
		return false
	}
	return !unicode.IsLetter(r) && !unicode.IsDigit(r)
}

// fold normalizes a token for comparison: lowercase, strip diacritics, map a
// few common leet substitutions to letters, and drop everything non-alphabetic.
func fold(s string) string {
	s = norm.NFKD.String(strings.ToLower(s))
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		if unicode.Is(unicode.Mn, r) {
			continue // combining mark left by NFKD (a stripped diacritic)
		}
		switch r {
		case '0':
			r = 'o'
		case '1':
			r = 'i'
		case '3':
			r = 'e'
		case '4', '@':
			r = 'a'
		case '5', '$':
			r = 's'
		case '7':
			r = 't'
		}
		if r >= 'a' && r <= 'z' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// parseTermList splits an embedded list: one term per line, '#' comments and
// blank lines ignored.
func parseTermList(raw string) []string {
	var out []string
	for _, line := range strings.Split(raw, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		out = append(out, line)
	}
	return out
}
