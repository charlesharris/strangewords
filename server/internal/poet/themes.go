package poet

// bySyl buckets words by true dictionary syllable count. Index 0 is unused;
// indexes 1-3 hold words. Always a slice, never a map: the RNG chooses from
// these, and Go map iteration order would break seed determinism.
type bySyl [4][]string

// theme is one poem's vocabulary. Nouns are singular. Verbs are intransitive
// third-person-singular present forms that read naturally after a singular
// noun (drifts, settles).
type theme struct {
	name  string
	nouns bySyl
	adjs  bySyl
	verbs bySyl
}

// preps is shared by every theme.
var preps = bySyl{
	1: {"in", "on", "through", "past", "by", "near"},
	2: {"over", "under", "beneath", "across", "along", "above"},
}

// themes is the registry of poem vocabularies. [TUNABLE] Adding or removing
// entries tunes the theme count and therefore the variety of poems.
var themes = []theme{
	{
		name: "night sky",
		nouns: bySyl{
			1: {"moon", "star", "dusk", "night", "sky", "dawn", "cloud", "owl"},
			2: {"comet", "lantern", "planet", "midnight", "twilight", "starlight", "moonlight", "shadow", "beacon", "orbit"},
			3: {"galaxy", "satellite", "aurora", "horizon", "universe", "telescope", "nebula"},
		},
		adjs: bySyl{
			1: {"pale", "cold", "dark", "vast", "bright", "deep", "high", "faint", "clear"},
			2: {"silver", "distant", "hollow", "patient", "gentle", "frozen", "golden", "endless", "ancient"},
			3: {"luminous", "infinite"},
		},
		verbs: bySyl{
			1: {"drifts", "burns", "fades", "wheels", "glows", "shines", "gleams", "waits", "falls", "sleeps"},
			2: {"settles", "flickers", "wanders", "lingers", "gathers", "shimmers", "trembles", "hovers", "glitters"},
			3: {"disappears"},
		},
	},
}
