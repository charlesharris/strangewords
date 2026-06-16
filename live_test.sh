#!/usr/bin/env bash
#
# live_test.sh — one command for a live test:
#   • 1 live person   → you, in the iOS simulator
#   • 1 automated poet → the robot, responding from the backend
#
# It brings up Redis + the backend + the robot poet, builds and launches the
# app on a single simulator (via run.sh --solo), then streams the poem to this
# terminal as you write it together. Ctrl-C tears everything down — nothing
# kept. Use --keep to leave the backend running afterward.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SERVER="$ROOT/server"
BASE="http://127.0.0.1:8080"
SERVER_LOG="/tmp/sw-live-server.log"
BOT_LOG="/tmp/sw-live-bot.log"

KEEP=0
for a in "$@"; do
  case "$a" in
    --keep) KEEP=1 ;;
    *) echo "unknown flag: $a"; exit 2 ;;
  esac
done

BACKEND_PID=""
BOT_PID=""
TAIL_PID=""

cleanup() {
  trap - EXIT INT TERM
  echo
  echo "▸ Tearing down…"
  [[ -n "$TAIL_PID" ]] && kill "$TAIL_PID" 2>/dev/null || true
  [[ -n "$BOT_PID" ]] && kill "$BOT_PID" 2>/dev/null || true
  if [[ "$KEEP" == "1" ]]; then
    echo "  Leaving backend running (--keep). Logs: $SERVER_LOG"
    [[ -n "$BACKEND_PID" ]] && echo "  Stop it later with:  kill $BACKEND_PID  &&  (cd server && docker compose down)"
  else
    [[ -n "$BACKEND_PID" ]] && kill "$BACKEND_PID" 2>/dev/null || true
    ( cd "$SERVER" && docker compose down ) >/dev/null 2>&1 || true
    echo "  Done. Nothing kept."
  fi
}
trap cleanup EXIT INT TERM

echo "▸ Starting Redis (Docker)…"
( cd "$SERVER" && docker compose up -d redis ) >/dev/null
sleep 1
( cd "$SERVER" && docker compose exec -T redis redis-cli FLUSHALL ) >/dev/null 2>&1 || true

echo "▸ Building backend + robot poet…"
( cd "$SERVER" && go build -o /tmp/sw-server ./cmd/server && go build -o /tmp/sw-bot ./cmd/bot )

echo "▸ Starting backend on ${BASE} ..."
SW_ADDR=":8080" /tmp/sw-server >"$SERVER_LOG" 2>&1 &
BACKEND_PID=$!
for _ in $(seq 1 40); do
  curl -sf "$BASE/healthz" >/dev/null 2>&1 && break
  sleep 0.25
done
if ! curl -sf "$BASE/healthz" >/dev/null 2>&1; then
  echo "Backend failed to start. See $SERVER_LOG"; exit 1
fi

# Build + launch the app on one simulator (backend is already healthy, so
# run.sh won't warn). This returns once the app is on screen.
echo "▸ Launching the app on a simulator…"
"$ROOT/run.sh" --solo

# Now slip the robot into the pool so it's waiting for you.
echo "▸ Waking the robot poet…"
/tmp/sw-bot -base "$BASE" >"$BOT_LOG" 2>&1 &
BOT_PID=$!

cat <<BANNER

════════════════════════════════════════════════════════════════
  LIVE TEST READY — you vs. the robot poet
  ▶ In the simulator, tap "begin". You'll be matched with the robot.

  The poem appears below as the two of you write it.
  Metrics:  curl -s $BASE/metrics
  Ctrl-C to end (nothing is kept).
════════════════════════════════════════════════════════════════

BANNER

# Stream the robot's view of the session until you quit. Run tail in the
# background and wait, so the cleanup trap fires promptly on Ctrl-C/SIGTERM
# (a foreground `tail -f` would defer the trap until it exits, i.e. never).
tail -n +1 -f "$BOT_LOG" &
TAIL_PID=$!
wait "$TAIL_PID" 2>/dev/null || true
