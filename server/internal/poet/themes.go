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
	{
		name: "seasons",
		nouns: bySyl{
			1: {"snow", "frost", "leaf", "thaw", "plum", "rain", "bloom", "sun", "ice", "bud", "grass", "fern"},
			2: {"willow", "maple", "meadow", "winter", "summer", "autumn", "blossom", "harvest", "orchard", "petal", "snowfall"},
			3: {"lavender", "afternoon", "november", "september", "sycamore", "equinox"},
		},
		adjs: bySyl{
			1: {"warm", "green", "soft", "brief", "crisp", "bare", "sweet", "gold"},
			2: {"tender", "blooming", "fallen", "early", "wintry", "frosted", "sunny", "mellow", "fragrant", "fragile"},
			3: {"delicate"},
		},
		verbs: bySyl{
			1: {"thaws", "blooms", "melts", "turns", "sways", "wilts", "warms", "stirs", "wakes"},
			2: {"ripens", "scatters", "shivers", "softens", "blossoms", "rustles", "returns"},
			3: {"awakens"},
		},
	},
	{
		name: "water",
		nouns: bySyl{
			1: {"pond", "reed", "tide", "shell", "mist", "wave", "stream", "brook", "lake", "foam"},
			2: {"river", "harbor", "puddle", "ripple", "pebble", "current", "seashore", "island", "lagoon", "inlet", "mirror"},
			3: {"waterfall", "reflection", "riverbank", "undertow", "rainwater", "cataract"},
		},
		adjs: bySyl{
			1: {"calm", "cool", "wet", "slow", "swift", "wide", "damp", "fresh"},
			2: {"muddy", "rippling", "flowing", "shallow", "winding", "sparkling", "restless", "murky", "silent"},
			3: {"glistening", "shimmering"},
		},
		verbs: bySyl{
			1: {"flows", "laps", "runs", "spills", "pours", "swirls", "rolls", "drips", "glides"},
			2: {"ripples", "murmurs", "trickles", "babbles", "rises", "washes", "echoes", "empties", "carries"},
			3: {"overflows"},
		},
	},
	{
		name: "small creatures",
		nouns: bySyl{
			1: {"moth", "wren", "snail", "crow", "bee", "frog", "toad", "fawn", "hawk", "duck", "swan", "mouse"},
			2: {"beetle", "sparrow", "heron", "cricket", "spider", "rabbit", "robin", "swallow", "lizard", "otter", "badger", "falcon", "turtle"},
			3: {"dragonfly", "butterfly", "hummingbird", "nightingale", "chickadee", "mockingbird", "grasshopper"},
		},
		adjs: bySyl{
			1: {"small", "quick", "shy", "wild", "brown", "gray", "fierce", "lone", "sleek", "plump"},
			2: {"tiny", "nimble", "furry", "hungry", "dusty", "feathered", "clever", "spotted", "timid"},
		},
		verbs: bySyl{
			1: {"hops", "sings", "darts", "hums", "crawls", "swims", "nests", "flits", "creeps", "dives"},
			2: {"flutters", "scurries", "burrows", "nibbles", "scuttles", "listens", "buzzes", "wriggles", "twitters"},
		},
	},
	{
		name: "quiet rooms",
		nouns: bySyl{
			1: {"cup", "chair", "bed", "lamp", "door", "desk", "clock", "rug", "shelf", "book", "quilt", "bowl", "key", "wall"},
			2: {"kettle", "candle", "teapot", "window", "thimble", "curtain", "cushion", "pillow", "table", "blanket", "mantel", "doorway", "bookshelf", "carpet"},
			3: {"envelope", "telephone", "photograph", "tablecloth", "wallpaper", "gramophone", "umbrella"},
		},
		adjs: bySyl{
			1: {"dim", "old", "worn", "plain", "neat", "snug", "dry", "hushed", "mild"},
			2: {"quiet", "empty", "faded", "folded", "creaking", "cozy", "sleepy", "tidy", "open", "spotless"},
			3: {"forgotten"},
		},
		verbs: bySyl{
			1: {"ticks", "creaks", "sits", "rests", "hangs", "sighs", "stands", "leans", "stays", "breathes"},
			2: {"whispers", "rattles", "hushes", "dozes", "slumbers", "stretches"},
		},
	},
}
