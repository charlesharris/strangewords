package sessions

// Form describes the *text shape* of a poem: an ordered list of lines, each
// with an optional syllable target (the "soft nudge"). Authorship is NOT part
// of the Form — that lives in a TurnPolicy. Targets are display-only and are
// never enforced server-side (see brief.v4.md §9).
type Form struct {
	ID      string `json:"id"`
	Targets []*int `json:"targets"` // one per line; nil means "no nudge" (e.g. free verse)
}

// LineCount is the number of lines this form expects.
func (f Form) LineCount() int { return len(f.Targets) }

func intp(n int) *int { return &n }

// formRegistry holds every known form. v1 ships exactly one.
var formRegistry = map[string]Form{
	"haiku": {ID: "haiku", Targets: []*int{intp(5), intp(7), intp(5)}},
}

// DefaultFormID is used when a request does not (yet) choose a form.
const DefaultFormID = "haiku"

// LookupForm returns the form for an id, falling back to the default.
func LookupForm(id string) Form {
	if f, ok := formRegistry[id]; ok {
		return f
	}
	return formRegistry[DefaultFormID]
}
