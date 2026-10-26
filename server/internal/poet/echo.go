package poet

import (
	"strings"
	"unicode"
)

// Echo knobs. All [TUNABLE].
const (
	// defaultEchoChance is the odds the poet echoes a word from the partner's
	// latest line when one fits. [TUNABLE]
	defaultEchoChance = 0.8
	// defaultAdjacentChance is the odds an echoed word that sits in a theme bank
	// is swapped for a sibling from the same theme and part of speech. [TUNABLE]
	defaultAdjacentChance = 0.3
	// maxEchoCandidates caps how many partner words are tried per line. [TUNABLE]
	maxEchoCandidates = 8
	// maxEchoWordLen skips absurdly long partner words so an echo can never push
	// a line past the server's length cap. [TUNABLE]
	maxEchoWordLen = 24
)

// stopwords are function words never echoed. Ported verbatim from the
// `stopwords` set in ios/Strangewords/Naming/PoemNaming.swift. Lookup only.
var stopwords = map[string]bool{}

func init() {
	for _, w := range strings.Fields(`
		the and but for nor yet with without into onto
		from off out over under upon about above below
		between through near are was were been being its
		this that these those you your yours him her
		his hers she they them their theirs our ours
		who whom which what when where while then than
		all any some each every not too very just yes
		will would can could shall should may might must
		does did done has have had get got let lets
		until still here there such only also even ever
		anymore twice once again almost always never maybe`) {
		stopwords[w] = true
	}
}

// echoTemplates lead with {E}, the echoed word, which may be any part of
// speech. Its cost is Count(word).
var echoTemplates = parseTemplates(
	"{E}, and the {N} {V}",
	"{E} — the {A} {N}",
	"{E} {P} the {N}",
	"{E} — the {N}",
)

// contentWords returns the echoable words of lines, in first-appearance order:
// letters-only, lowercase, 3 or more letters, not a stopword, not a contraction.
// It matches the content-word rule of PoemNaming.swift.
func contentWords(lines []string) []string {
	var out []string
	seen := map[string]bool{}
	for _, line := range lines {
		toks := strings.FieldsFunc(line, func(r rune) bool {
			return !unicode.IsLetter(r) && r != '\'' && r != '’'
		})
		for _, tok := range toks {
			if strings.ContainsAny(tok, "'’") {
				continue
			}
			tok = strings.ToLower(tok)
			if len([]rune(tok)) < 3 || stopwords[tok] || seen[tok] {
				continue
			}
			seen[tok] = true
			out = append(out, tok)
		}
	}
	return out
}

// bankRef locates a bank word: its theme and part of speech ('N', 'A', 'V').
type bankRef struct {
	theme int
	pos   byte
}

// bankIndex maps every theme-bank word to where it lives. Lookup only: never
// iterate it to make a choice.
var bankIndex = func() map[string]bankRef {
	idx := map[string]bankRef{}
	for i := range themes {
		for _, pb := range []struct {
			pos byte
			b   *bySyl
		}{{'N', &themes[i].nouns}, {'A', &themes[i].adjs}, {'V', &themes[i].verbs}} {
			for c := 1; c <= 3; c++ {
				for _, w := range pb.b[c] {
					idx[w] = bankRef{i, pb.pos}
				}
			}
		}
	}
	return idx
}()

// sibling picks a word from the same theme and part of speech as w (any
// syllable bucket), other than w, preferring one new to the poem.
func (p *Poet) sibling(w string, ref bankRef) string {
	th := &themes[ref.theme]
	b := &th.nouns
	switch ref.pos {
	case 'A':
		b = &th.adjs
	case 'V':
		b = &th.verbs
	}
	var all, fresh []string
	for c := 1; c <= 3; c++ {
		for _, x := range b[c] {
			if x == w {
				continue
			}
			all = append(all, x)
			if !p.used[x] {
				fresh = append(fresh, x)
			}
		}
	}
	if len(fresh) > 0 {
		return fresh[p.rng.IntN(len(fresh))]
	}
	if len(all) > 0 {
		return all[p.rng.IntN(len(all))]
	}
	return w
}

// echoCandidates gathers up to maxEchoCandidates words from the partner's
// lines: the most recent partner line first (shuffled), then earlier ones.
// Lines this Poet wrote are skipped, so the bot never echoes itself.
func (p *Poet) echoCandidates(previous []string) []string {
	var cands []string
	seen := map[string]bool{}
	first := true
	for i := len(previous) - 1; i >= 0; i-- {
		if p.mine[previous[i]] {
			continue
		}
		ws := contentWords([]string{previous[i]})
		if first {
			p.rng.Shuffle(len(ws), func(a, b int) { ws[a], ws[b] = ws[b], ws[a] })
			first = false
		}
		for _, w := range ws {
			if seen[w] || len([]rune(w)) > maxEchoWordLen {
				continue
			}
			seen[w] = true
			cands = append(cands, w)
		}
	}
	if len(cands) > maxEchoCandidates {
		cands = cands[:maxEchoCandidates]
	}
	return cands
}

// echoLine tries to weave a partner word (or a theme sibling) into an exact fit
// for target. Echo never falls back to nearest fit: if no candidate fits it
// reports false and the caller composes normally.
func (p *Poet) echoLine(target int, previous []string) (string, bool) {
	cands := p.echoCandidates(previous)
	if len(cands) == 0 || p.rng.Float64() >= p.echoChance {
		return "", false
	}
	for _, w := range cands {
		e := w
		if ref, ok := bankIndex[w]; ok && p.rng.Float64() < p.adjacentChance {
			e = p.sibling(w, ref)
		}
		if Count(e) > target {
			continue
		}
		for _, strict := range []bool{true, false} {
			for _, i := range p.rng.Perm(len(echoTemplates)) {
				t := echoTemplates[i]
				if ws, ok := p.fill(t, target-literalCost(t, e), e, strict); ok {
					p.used[e] = true
					p.lastEcho = e
					return p.render(t, ws), true
				}
			}
		}
	}
	return "", false
}
