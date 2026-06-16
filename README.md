# strangewords

Haiku for strangers — an anonymous, ephemeral iOS app for writing a tiny poem
with someone you'll never meet, then letting it go.

- **Intent / philosophy:** [`brief.v4.md`](brief.v4.md)
- **Build plan:** [`plan.v1.md`](plan.v1.md)

## Layout

- `server/` — Go coordination backend (HTTPS + Redis; APNs later)
- `ios/` — SwiftUI app (generated from `ios/project.yml` via XcodeGen)

## Run the backend

```sh
cd server
make run          # starts local Redis (docker) + the Go service on :8080
# or: go test ./...   to run the suite (no external services; uses miniredis)
```

## Run the iOS app

Requires Xcode 16+ and [XcodeGen](https://github.com/yonom/XcodeGen) (`brew install xcodegen`).

```sh
cd ios
xcodegen generate                                   # regenerate the .xcodeproj
open Strangewords.xcodeproj                          # then run on a simulator
```

The app talks to `http://127.0.0.1:8080` (the simulator shares the host
network). Start the backend first.

## Manual two-participant runbook (Phase 3 acceptance)

The full live/async loop is verified across two clients:

1. Start the backend (`make run`).
2. Run the app on **two** simulators (or one simulator + `curl` as the second
   participant). Tap **begin** on the first — it shows the quiet waiting room.
3. Tap **begin** on the second — both are now matched into a poem.
4. Whoever's turn it is writes a line (a syllable hint guides, never blocks);
   the other sees the held-breath waiting state. Repeat for all three lines.
5. The completed poem reveals on both, then dissolves; nothing is kept.
6. **Async check:** background one client mid-poem; the other can still submit.
   Re-open the backgrounded client — it resumes the poem in its current state.
   (Push-driven re-engagement arrives in Phase 2.)
