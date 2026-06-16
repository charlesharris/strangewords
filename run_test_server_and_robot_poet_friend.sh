#!/usr/bin/env bash
#
# run_test_server_and_robot_poet_friend.sh
#
# Brings up everything you need to play with the app using a single simulator:
#   1. Redis (in Docker)
#   2. the Go backend on :8080
#   3. a "robot poet friend" — an automated second participant
#
# Then you open the app on a simulator, tap "begin", and you'll be matched
# with the robot to write a poem together. Ctrl-C here tears it all down.
#
# Usage:  ./run_test_server_and_robot_poet_friend.sh [--keep] [--once]
#   --keep   leave Redis + backend running after you quit
#   --once   robot plays a single poem then exits
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SERVER="$ROOT/server"
ADDR="${SW_ADDR:-:8080}"
BASE="http://127.0.0.1:8080"

KEEP=0
BOT_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP=1 ;;
    --once) BOT_ARGS+=("-once") ;;
    *) echo "unknown flag: $arg"; exit 2 ;;
  esac
done

STARTED_BACKEND=0
BACKEND_PID=""

cleanup() {
  echo
  if [[ "$KEEP" == "1" ]]; then
    echo "Leaving Redis + backend running (--keep). Backend logs: /tmp/sw-server.log"
    [[ -n "$BACKEND_PID" ]] && echo "Stop the backend later with:  kill $BACKEND_PID"
    return
  fi
  if [[ "$STARTED_BACKEND" == "1" && -n "$BACKEND_PID" ]]; then
    echo "Stopping backend (pid $BACKEND_PID)…"
    kill "$BACKEND_PID" 2>/dev/null || true
  fi
  echo "Stopping Redis…"
  ( cd "$SERVER" && docker compose down ) >/dev/null 2>&1 || true
  echo "Done. Nothing kept."
}
trap cleanup EXIT INT TERM

echo "▸ Starting Redis (Docker)…"
( cd "$SERVER" && docker compose up -d redis ) >/dev/null
sleep 1
# Fresh slate so no stale waiters from a previous run get matched.
( cd "$SERVER" && docker compose exec -T redis redis-cli FLUSHALL ) >/dev/null 2>&1 || true

if curl -sf "$BASE/healthz" >/dev/null 2>&1; then
  echo "▸ Backend already running on $BASE"
else
  echo "▸ Building & starting backend…"
  ( cd "$SERVER" && go build -o /tmp/sw-server ./cmd/server )
  ( cd "$SERVER" && SW_ADDR="$ADDR" /tmp/sw-server ) >/tmp/sw-server.log 2>&1 &
  BACKEND_PID=$!
  STARTED_BACKEND=1
  for _ in $(seq 1 40); do
    curl -sf "$BASE/healthz" >/dev/null 2>&1 && break
    sleep 0.25
  done
  if ! curl -sf "$BASE/healthz" >/dev/null 2>&1; then
    echo "Backend failed to start. See /tmp/sw-server.log"; exit 1
  fi
fi

echo "▸ Building robot poet…"
( cd "$SERVER" && go build -o /tmp/sw-bot ./cmd/bot )

cat <<BANNER

════════════════════════════════════════════════════════════════
  Backend:  $BASE      (logs: /tmp/sw-server.log)
  Metrics:  curl -s $BASE/metrics

  The robot poet is entering the room and will wait for you.
  ▶ Open the app on a simulator and tap "begin" to be matched.

  Watch this window for the poem as it's written together.
  Ctrl-C to stop everything.
════════════════════════════════════════════════════════════════

BANNER

/tmp/sw-bot -base "$BASE" "${BOT_ARGS[@]}"
