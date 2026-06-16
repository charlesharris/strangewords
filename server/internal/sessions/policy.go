package sessions

// TurnPolicy decides who authors each line — the pluggable seam that lets us
// later support round-robin poetry circles, alternate orders, etc. without
// touching the session machinery (see plan.v1.md §5, §13).
//
// It is expressed over an ordered participant list and is therefore N-ready,
// even though v1 only ever runs it with two participants.
type TurnPolicy interface {
	ID() string
	// Author returns the participant index that should write the given line,
	// resolved against the participant count and the session's start offset.
	Author(lineIndex, participantCount, startIndex int) int
}

// roundRobin rotates authorship through participants in order. For two
// participants over three lines it yields p, q, p — exactly the haiku A-B-A,
// so the brief's "intentional asymmetry" emerges for free.
type roundRobin struct{}

func (roundRobin) ID() string { return "round-robin" }

func (roundRobin) Author(lineIndex, participantCount, startIndex int) int {
	if participantCount <= 0 {
		return 0
	}
	return (startIndex + lineIndex) % participantCount
}

// policyRegistry holds every known policy. v1 ships exactly one.
var policyRegistry = map[string]TurnPolicy{
	"round-robin": roundRobin{},
}

// DefaultPolicyID is used when a session does not specify a policy.
const DefaultPolicyID = "round-robin"

// LookupPolicy returns the policy for an id, falling back to the default.
func LookupPolicy(id string) TurnPolicy {
	if p, ok := policyRegistry[id]; ok {
		return p
	}
	return policyRegistry[DefaultPolicyID]
}
