// Package metrics holds lightweight in-process counters (plan.v1.md §?/brief
// §18). v1 keeps it minimal; a real exporter can wrap these later.
package metrics

import (
	"fmt"
	"io"
	"sync/atomic"
)

type Counters struct {
	Entered        atomic.Int64
	Matched        atomic.Int64
	Waiting        atomic.Int64
	LinesSubmitted atomic.Int64
	PoemsCompleted atomic.Int64
	Dissolved      atomic.Int64
}

var C = &Counters{}

// WriteText dumps counters in a trivial text format for /metrics.
func WriteText(w io.Writer) {
	fmt.Fprintf(w, "sw_entered %d\n", C.Entered.Load())
	fmt.Fprintf(w, "sw_matched %d\n", C.Matched.Load())
	fmt.Fprintf(w, "sw_waiting %d\n", C.Waiting.Load())
	fmt.Fprintf(w, "sw_lines_submitted %d\n", C.LinesSubmitted.Load())
	fmt.Fprintf(w, "sw_poems_completed %d\n", C.PoemsCompleted.Load())
	fmt.Fprintf(w, "sw_dissolved %d\n", C.Dissolved.Load())
}
