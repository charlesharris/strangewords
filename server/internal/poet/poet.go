package poet

import (
	"math/rand/v2"
	"strings"
	"unicode"
)

// Safety-net lines, used only when no template can be solved at all (for
// example, empty banks). Both are verified against Count.
const (
	safetyFive  = "still water at dusk"
	safetySeven = "the river remembers rain"
)

// Poet composes the lines of one poem. Make one per poem with New.
type Poet struct {
	rng   *rand.Rand
	theme int             // index into themes
	used  map[string]bool // words already in the poem (membership only)
	mine  map[string]bool // exact lines this Poet has returned (membership only)

	lastEcho       string  // word echoed into the latest line, or ""
	echoChance     float64 // odds of trying an echo at all
	adjacentChance float64 // odds an echoed bank word becomes a theme sibling
}

// New returns a Poet for seed. Its first RNG draw picks the theme, so the same
// seed always gives the same theme.
func New(seed uint64) *Poet {
	p := &Poet{
		rng:  rand.New(rand.NewPCG(seed, seed^0x9E3779B97F4A7C15)),
		used: map[string]bool{},
		mine: map[string]bool{},

		echoChance:     defaultEchoChance,
		adjacentChance: defaultAdjacentChance,
	}
	p.theme = p.rng.IntN(len(themes))
	return p
}

// Theme returns the name of the poem's theme, e.g. "night sky".
func (p *Poet) Theme() string { return themes[p.theme].name }

// Line composes a line of about target syllables. previous is every line of
// the poem so far. It never blocks and never returns an empty string. A target
// of 0 or less (free verse) gets a 5- or 7-syllable line.
func (p *Poet) Line(target int, previous []string) string {
	p.lastEcho = ""
	for _, l := range previous {
		for _, w := range words(l) {
			p.used[w] = true
		}
	}
	if target <= 0 {
		target = 5 + 2*p.rng.IntN(2)
	}
	if line, ok := p.echoLine(target, previous); ok {
		return p.record(line)
	}
	if line, ok := p.compose(target); ok {
		return p.record(line)
	}
	if line, ok := p.nearest(target); ok {
		return p.record(line)
	}
	if target <= 6 {
		return p.record(safetyFive)
	}
	return p.record(safetySeven)
}

func (p *Poet) record(line string) string {
	p.mine[line] = true
	return line
}

// words returns the lowercase letters-only tokens of a line.
func words(line string) []string {
	return strings.FieldsFunc(strings.ToLower(line), func(r rune) bool { return !unicode.IsLetter(r) })
}

// MARK: - templates

// field is one token of a template: a literal word (kind 0) or a slot.
type field struct {
	kind  byte   // 0 literal; 'N' noun, 'A' adjective, 'V' verb, 'P' preposition, 'E' echo
	text  string // the literal word
	trail string // punctuation attached after the token
}

type template []field

// parseTemplate reads "the {A} {N}, {V}": literal words and {K} slots separated
// by spaces. Punctuation after a slot attaches to it.
func parseTemplate(s string) template {
	var t template
	for _, f := range strings.Fields(s) {
		if strings.HasPrefix(f, "{") && len(f) >= 3 {
			t = append(t, field{kind: f[1], trail: f[3:]})
			continue
		}
		t = append(t, field{text: f})
	}
	return t
}

func parseTemplates(ss ...string) []template {
	ts := make([]template, len(ss))
	for i, s := range ss {
		ts[i] = parseTemplate(s)
	}
	return ts
}

// generalTemplates are the fixed grammar shapes lines are built from.
var generalTemplates = parseTemplates(
	"the {A} {N} {V}",
	"{N} {V} {P} the {N}",
	"a {A} {N} {P} the {N}",
	"{A} {N}, {A} {N}",
	"the {N} of {A} {N}",
	"{N} {V} and {V}",
	"the {N} {V}, the {N} {V}",
	"{A} {N} {P} the {A} {N}",
)

// literalCost is the syllables of t's literal words plus the echo word, if any.
func literalCost(t template, echo string) int {
	n := 0
	for _, f := range t {
		switch f.kind {
		case 0:
			n += Count(f.text)
		case 'E':
			n += Count(echo)
		}
	}
	return n
}

// isSlot reports whether kind is a slot the solver fills from a bank.
func isSlot(kind byte) bool {
	return kind == 'N' || kind == 'A' || kind == 'V' || kind == 'P'
}

func (p *Poet) bank(kind byte) *bySyl {
	th := &themes[p.theme]
	switch kind {
	case 'N':
		return &th.nouns
	case 'A':
		return &th.adjs
	case 'V':
		return &th.verbs
	}
	return &preps
}

// span is the least and most syllables t's slots can sum to.
func (p *Poet) span(t template) (lo, hi int) {
	for _, f := range t {
		if !isSlot(f.kind) {
			continue
		}
		b := p.bank(f.kind)
		first, last := 0, 0
		for c := 1; c <= 3; c++ {
			if len(b[c]) > 0 {
				if first == 0 {
					first = c
				}
				last = c
			}
		}
		lo += first
		hi += last
	}
	return lo, hi
}

// MARK: - solver

// compose tries every template in shuffled order for an exact fit to target.
// It first insists on words not yet in the poem, then relaxes that.
func (p *Poet) compose(target int) (string, bool) {
	order := p.rng.Perm(len(generalTemplates))
	for _, strict := range []bool{true, false} {
		for _, i := range order {
			t := generalTemplates[i]
			if ws, ok := p.fill(t, target-literalCost(t, ""), "", strict); ok {
				return p.render(t, ws), true
			}
		}
	}
	return "", false
}

// nearest picks the template whose reachable length lands closest to target
// and solves for that. Positive targets with no exact fit end up here.
func (p *Poet) nearest(target int) (string, bool) {
	var best []int
	bestD := -1
	sums := make([]int, len(generalTemplates))
	for i, t := range generalTemplates {
		need := target - literalCost(t, "")
		lo, hi := p.span(t)
		sums[i] = min(max(need, lo), hi)
		d := sums[i] - need
		if d < 0 {
			d = -d
		}
		switch {
		case bestD < 0 || d < bestD:
			best, bestD = []int{i}, d
		case d == bestD:
			best = append(best, i)
		}
	}
	i := best[p.rng.IntN(len(best))]
	t := generalTemplates[i]
	ws, ok := p.fill(t, sums[i], "", false)
	if !ok {
		return "", false
	}
	return p.render(t, ws), true
}

// fill chooses a word for every slot of t so the slots total sum syllables. In
// strict mode every word must be new to the poem; otherwise a bucket with no
// new word falls back to a reused one. An {E} field renders as echo. It reports
// false when no choice works.
func (p *Poet) fill(t template, sum int, echo string, strict bool) ([]string, bool) {
	ws := make([]string, len(t))
	var slots []int
	for i, f := range t {
		switch {
		case isSlot(f.kind):
			slots = append(slots, i)
		case f.kind == 'E':
			ws[i] = echo
		}
	}
	// lo[k], hi[k]: least and most the slots from k onward can sum to.
	lo := make([]int, len(slots)+1)
	hi := make([]int, len(slots)+1)
	for k := len(slots) - 1; k >= 0; k-- {
		b := p.bank(t[slots[k]].kind)
		first, last := 0, 0
		for c := 1; c <= 3; c++ {
			if len(b[c]) > 0 {
				if first == 0 {
					first = c
				}
				last = c
			}
		}
		lo[k], hi[k] = lo[k+1]+first, hi[k+1]+last
	}

	var rec func(k, rem int) bool
	rec = func(k, rem int) bool {
		if k == len(slots) {
			return rem == 0
		}
		b := p.bank(t[slots[k]].kind)
		var cs []int
		for c := 1; c <= 3; c++ {
			if len(b[c]) > 0 && rem-c >= lo[k+1] && rem-c <= hi[k+1] {
				cs = append(cs, c)
			}
		}
		p.rng.Shuffle(len(cs), func(i, j int) { cs[i], cs[j] = cs[j], cs[i] })
		for _, c := range cs {
			w, ok := p.pick(b[c], ws, strict)
			if !ok {
				continue
			}
			ws[slots[k]] = w
			if rec(k+1, rem-c) {
				return true
			}
			ws[slots[k]] = ""
		}
		return false
	}
	if !rec(0, sum) {
		return nil, false
	}
	for _, i := range slots {
		p.used[ws[i]] = true
	}
	return ws, true
}

// pick chooses a word from bucket that is new to the poem and not already in
// this line (chosen). If none is, a non-strict pick falls back to a word not
// in this line, then to any word.
func (p *Poet) pick(bucket []string, chosen []string, strict bool) (string, bool) {
	inLine := func(w string) bool {
		for _, c := range chosen {
			if c == w {
				return true
			}
		}
		return false
	}
	var fresh, notInLine []string
	for _, w := range bucket {
		if inLine(w) {
			continue
		}
		notInLine = append(notInLine, w)
		if !p.used[w] {
			fresh = append(fresh, w)
		}
	}
	switch {
	case len(fresh) > 0:
		return fresh[p.rng.IntN(len(fresh))], true
	case strict:
		return "", false
	case len(notInLine) > 0:
		return notInLine[p.rng.IntN(len(notInLine))], true
	}
	return bucket[p.rng.IntN(len(bucket))], true
}

// render joins a solved template into a lowercase line, turning "a" into "an"
// before a vowel.
func (p *Poet) render(t template, ws []string) string {
	toks := make([]string, len(t))
	for i, f := range t {
		w := f.text
		if f.kind != 0 {
			w = ws[i]
		}
		toks[i] = w + f.trail
	}
	for i := 0; i+1 < len(toks); i++ {
		if toks[i] == "a" && strings.ContainsRune("aeiou", rune(toks[i+1][0])) {
			toks[i] = "an"
		}
	}
	return strings.Join(toks, " ")
}
