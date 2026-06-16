// Command bot is a "robot poet friend": an automated participant that enters
// the pool, gets matched with you, and writes its lines when it's its turn —
// so you can test and play with the app using a single simulator.
//
//	go run ./cmd/bot -base http://127.0.0.1:8080
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math/rand/v2"
	"net/http"
	"time"

	"strangewords/internal/sessions"
)

// Curated lines by syllable count, so the bot honors the haiku's soft nudges.
var fiveSyllable = []string{
	"an old silent pond",
	"the moon over snow",
	"soft rain on the leaves",
	"a crow on the branch",
	"morning fog is lifting",
	"the last cherry bloom",
	"still water at dusk",
	"wind through the empty halls",
}

var sevenSyllable = []string{
	"a frog jumps into the pond",
	"the autumn wind scatters them",
	"cicadas sing in the heat",
	"lanterns drift down the dark stream",
	"snow settles on the pine boughs",
	"the river remembers rain",
	"shadows grow long on the path",
}

type enterResp struct {
	ParticipantToken string         `json:"participantToken"`
	State            string         `json:"state"`
	Session          *sessions.View `json:"session"`
	WaitID           string         `json:"waitId"`
}

type waitingResp struct {
	State   string         `json:"state"`
	Session *sessions.View `json:"session"`
}

type bot struct {
	base  string
	token string
	http  *http.Client
}

func main() {
	base := flag.String("base", "http://127.0.0.1:8080", "backend base URL")
	once := flag.Bool("once", false, "play a single poem then exit (default: keep playing)")
	flag.Parse()

	b := &bot{base: *base, http: &http.Client{Timeout: 15 * time.Second}}
	fmt.Println("🤖  robot poet is awake.")
	for {
		if err := b.playOne(); err != nil {
			fmt.Println("   (hiccup:", err, "— trying again in a moment)")
			time.Sleep(2 * time.Second)
		}
		if *once {
			return
		}
		fmt.Println("\n🤖  back to the quiet room…")
		time.Sleep(1 * time.Second)
	}
}

// playOne enters, waits to be matched, and plays a poem to its end.
func (b *bot) playOne() error {
	view, err := b.enterAndMatch()
	if err != nil {
		return err
	}
	fmt.Printf("🤝  matched! I'm participant %d. Let's make something.\n", view.You)

	for {
		switch view.Status {
		case sessions.StatusComplete:
			b.printPoem(view)
			b.dismiss(view.SessionID)
			return nil
		case sessions.StatusActive:
			if view.YourTurn {
				time.Sleep(time.Duration(1500+rand.IntN(1800)) * time.Millisecond) // a thoughtful pause
				line := b.composeLine(view)
				next, err := b.submit(view.SessionID, view.CurrentLine, line)
				if err != nil {
					return err
				}
				fmt.Printf("✍️   me: %s\n", line)
				view = *next
			} else {
				time.Sleep(1500 * time.Millisecond)
				v, err := b.getSession(view.SessionID)
				if err != nil {
					return err
				}
				// Echo a freshly arrived line from the human.
				if len(v.Lines) > len(view.Lines) {
					fmt.Printf("👤  you: %s\n", v.Lines[len(v.Lines)-1])
				}
				view = *v
			}
		default:
			return nil // dissolved
		}
	}
}

func (b *bot) enterAndMatch() (sessions.View, error) {
	var er enterResp
	if err := b.post("/v1/enter", "", map[string]any{}, &er); err != nil {
		return sessions.View{}, err
	}
	b.token = er.ParticipantToken
	if er.State == "matched" && er.Session != nil {
		return *er.Session, nil
	}
	fmt.Println("⏳  waiting for a stranger… (open the app and tap “begin”)")
	for {
		time.Sleep(1500 * time.Millisecond)
		var wr waitingResp
		err := b.get("/v1/waiting", &wr)
		if err == errGone {
			// Our wait expired; slip back into the pool.
			return b.enterAndMatch()
		}
		if err != nil {
			return sessions.View{}, err
		}
		if wr.State == "matched" && wr.Session != nil {
			return *wr.Session, nil
		}
	}
}

// composeLine picks a line that fits the current target, avoiding repeats.
func (b *bot) composeLine(v sessions.View) string {
	var pool []string
	switch target(v) {
	case 5:
		pool = fiveSyllable
	case 7:
		pool = sevenSyllable
	default:
		pool = append(append([]string{}, fiveSyllable...), sevenSyllable...)
	}
	used := map[string]bool{}
	for _, l := range v.Lines {
		used[l] = true
	}
	for i := 0; i < 12; i++ {
		c := pool[rand.IntN(len(pool))]
		if !used[c] {
			return c
		}
	}
	return pool[rand.IntN(len(pool))]
}

func target(v sessions.View) int {
	if v.CurrentLine >= 0 && v.CurrentLine < len(v.Form.Targets) {
		if t := v.Form.Targets[v.CurrentLine]; t != nil {
			return *t
		}
	}
	return 0
}

func (b *bot) submit(id string, line int, text string) (*sessions.View, error) {
	var v sessions.View
	body := map[string]any{"line": line, "text": text, "idemKey": fmt.Sprintf("bot-%d-%d", line, time.Now().UnixNano())}
	if err := b.post("/v1/session/"+id+"/line", b.token, body, &v); err != nil {
		return nil, err
	}
	return &v, nil
}

func (b *bot) getSession(id string) (*sessions.View, error) {
	var v sessions.View
	if err := b.get("/v1/session/"+id, &v); err != nil {
		return nil, err
	}
	return &v, nil
}

func (b *bot) dismiss(id string) {
	_ = b.post("/v1/session/"+id+"/dismiss", b.token, map[string]any{}, nil)
}

func (b *bot) printPoem(v sessions.View) {
	fmt.Println("\n🌸  the poem is complete:")
	fmt.Println("   ┄┄┄┄┄┄┄┄┄┄┄┄")
	for _, l := range v.Lines {
		fmt.Printf("   %s\n", l)
	}
	fmt.Println("   ┄┄┄┄┄┄┄┄┄┄┄┄")
	fmt.Println("   …and now we let it go.")
}

// ---- tiny HTTP helpers ----

var errGone = fmt.Errorf("gone")

func (b *bot) get(path string, out any) error {
	req, _ := http.NewRequest("GET", b.base+path, nil)
	if b.token != "" {
		req.Header.Set("Authorization", "Bearer "+b.token)
	}
	return b.do(req, out)
}

func (b *bot) post(path, token string, body any, out any) error {
	data, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", b.base+path, bytes.NewReader(data))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	return b.do(req, out)
}

func (b *bot) do(req *http.Request, out any) error {
	resp, err := b.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == http.StatusGone {
		return errGone
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%s -> %d: %s", req.URL.Path, resp.StatusCode, bytes.TrimSpace(data))
	}
	if out != nil {
		return json.Unmarshal(data, out)
	}
	return nil
}
