// Package poet is the robot poet's generative, syllable-aware line composer.
//
// It is pure Go stdlib: there are no external AI, API, or network calls (a
// locked decision), and no file, logging, or fmt use. A Poet is deterministic
// for a given seed: the same seed yields the same theme and the same lines for
// the same inputs. A Poet lives for one poem and keeps no state beyond it.
package poet

import (
	"strings"
	"unicode"
)

// Count estimates the syllables in text. It ports the vowel-cluster heuristic
// of ios/Strangewords/Syllables/Syllables.swift (brief.v4.md §9): per word,
// count contiguous vowel groups over "aeiouy", then floor a non-empty word at
// 1. Go adds suffix rules and a small known-word overrides map so it corrects
// the misses the iOS tests pin (poem, quiet, rhythm, table, create, café,
// don't). iOS only counts the user's own draft, so the two never disagree on
// anything a user sees.
//
// Apostrophes are deleted, so a contraction counts as one word. Any other
// non-letter splits words. Empty or letterless input counts 0.
func Count(text string) int {
	text = strings.Map(func(r rune) rune {
		if r == '\'' || r == '’' {
			return -1
		}
		return r
	}, strings.ToLower(text))
	n := 0
	for _, w := range strings.FieldsFunc(text, func(r rune) bool { return !unicode.IsLetter(r) }) {
		n += countWord(w)
	}
	return n
}

// overrides holds true counts for words the rules miss. Read-only data.
var overrides = map[string]int{
	"poem":   2, // "oe" is one vowel cluster
	"quiet":  2, // "uie" is one vowel cluster
	"rhythm": 2, // only "y" is a vowel
	"create": 2, // "ea" is one cluster, then the silent-e drop
	"café":   2, // "é" is outside the vowel set
}

func isVowel(r rune) bool { return strings.ContainsRune("aeiouy", r) }

func countWord(word string) int {
	if n, ok := overrides[word]; ok {
		return n
	}
	rs := []rune(word)
	count, prev := 0, false
	for _, r := range rs {
		v := isVowel(r)
		if v && !prev {
			count++
		}
		prev = v
	}
	if count > 1 {
		count = adjustSuffix(rs, count)
	}
	return max(count, 1)
}

// adjustSuffix applies at most one suffix rule to a multi-cluster word.
func adjustSuffix(rs []rune, count int) int {
	n := len(rs)
	has := func(suffix string) bool { return strings.HasSuffix(string(rs), suffix) }
	cons := func(i int) bool { return i >= 0 && i < n && !isVowel(rs[i]) }
	switch {
	case has("e"):
		// Drop the silent e only when it stands alone after a consonant. An e
		// that ends a vowel group (agree, movie, value) is already counted
		// with it. consonant+"le" keeps its syllable (table, candle, maple).
		if !cons(n-2) || (has("le") && cons(n-3)) {
			return count
		}
		return count - 1
	case has("es") && n > 3:
		// settles, candles keep their syllable.
		if has("les") && cons(n-4) {
			return count
		}
		// glides, fades, lines drop; rises, dances, ashes, branches keep.
		if c := n - 3; cons(c) && !sibilant(rs, c) {
			return count - 1
		}
	case has("ed") && n > 3:
		// bloomed, rained drop; folded, lifted keep.
		if c := n - 3; cons(c) && rs[c] != 't' && rs[c] != 'd' {
			// consonant+"led" (tangled, rippled) keeps its syllabic l.
			if rs[c] == 'l' && cons(n-4) {
				return count
			}
			return count - 1
		}
	}
	return count
}

// sibilant reports whether rs[i] makes an "es" ending its own syllable.
func sibilant(rs []rune, i int) bool {
	switch rs[i] {
	case 's', 'x', 'z', 'c', 'g':
		return true
	case 'h':
		return i > 0 && (rs[i-1] == 'c' || rs[i-1] == 's')
	}
	return false
}
