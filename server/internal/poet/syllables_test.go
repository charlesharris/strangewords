package poet

import "testing"

func checkCounts(t *testing.T, rows []struct {
	in   string
	want int
}) {
	t.Helper()
	for _, r := range rows {
		if got := Count(r.in); got != r.want {
			t.Errorf("Count(%q) = %d, want %d", r.in, got, r.want)
		}
	}
}

// The correct-word and edge-input rows pinned in
// ios/StrangewordsTests/SyllablesTests.swift.
func TestCountWords(t *testing.T) {
	checkCounts(t, []struct {
		in   string
		want int
	}{
		{"fire", 1}, {"", 0}, {"the", 1}, {"pond", 1}, {"jumps", 1}, {"hour", 1},
		{"into", 2}, {"silence", 2}, {"again", 2}, {"autumn", 2}, {"lanterns", 2},
		{"happy", 2}, {"beautiful", 3},
		{"hmm", 1}, {"e", 1}, {"Y", 1}, {"123", 0}, {"😀", 0},
	})
}

// Words the iOS heuristic gets wrong (pinned there at the wrong count) are
// counted correctly here.
func TestCountKnownMissesFixed(t *testing.T) {
	checkCounts(t, []struct {
		in   string
		want int
	}{
		{"poem", 2}, {"quiet", 2}, {"rhythm", 2}, {"table", 2}, {"create", 2},
		{"café", 2}, {"don't", 1}, {"don’t", 1},
	})
}

func TestCountSuffixRules(t *testing.T) {
	checkCounts(t, []struct {
		in   string
		want int
	}{
		{"candle", 2}, {"whale", 1}, {"settles", 2}, {"candles", 2}, {"glides", 1},
		{"fades", 1}, {"rises", 2}, {"dances", 2}, {"ashes", 2}, {"branches", 2},
		{"smiles", 1}, {"trees", 1}, {"goes", 1}, {"lines", 1}, {"bloomed", 1},
		{"rained", 1}, {"hushed", 1}, {"folded", 2}, {"lifted", 2}, {"red", 1},
		{"seed", 1},
		// consonant+"led" keeps its syllabic l, like consonant+"le".
		{"tangled", 2}, {"sailed", 1},
		// an e that ends a vowel group is not a separate silent e.
		{"agree", 2}, {"movie", 2}, {"chickadee", 3},
	})
}

func TestCountLines(t *testing.T) {
	checkCounts(t, []struct {
		in   string
		want int
	}{
		{"A frog jumps into the pond", 7},
		{"An old silent pond", 5},
		{"Splash! Silence again.", 5},
		{"a frog leaps into the pond", 7},
		{"the autumn wind scatters them", 7},
		{"   ", 0},
		// The old curated pool called these 5; they are 6.
		{"morning fog is lifting", 6},
		{"wind through the empty halls", 6},
		{"incomprehensibility", 8},
	})
}
