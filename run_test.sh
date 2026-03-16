#!/usr/bin/env bash
# Start server + two clients for Automated RTS.
# Default: auto-test with events 1. Use --no_test for two human-playable clients.
# Use --events 1 or --events 2 to select the event sequence for auto-test.
#
# Run from a terminal that has a display (not over SSH without X). Two game
# windows will open for the clients. Set GODOT_BIN to the full path to your
# Godot executable if "godot" is not in PATH, e.g.:
#   export GODOT_BIN=/path/to/Godot_v4.6.1-stable_linux.x86_64

set -e
GODOT_BIN="${GODOT_BIN:-godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

AUTO_TEST=true
EVENTS=1
for arg in "$@"; do
  case "$arg" in
    --no_test|--no-test) AUTO_TEST=false ;;
    --events=1) EVENTS=1 ;;
    --events=2) EVENTS=2 ;;
  esac
done

# Clean up any existing instances
pkill -9 -f Godot_v4 2>/dev/null || true
fuser -k 8910/tcp 2>/dev/null || true
sleep 2

mkdir -p logs

# Server: run under nohup so it survives script exit (no SIGHUP)
nohup "$GODOT_BIN" --headless --path . -- --server > logs/server.log 2>&1 &
echo $! > logs/server.pid
echo "Server started (PID $(cat logs/server.pid))."
sleep 4

if [ "$AUTO_TEST" = true ]; then
  echo "Starting auto-test clients A and B (events=$EVENTS)..."
  echo "Two game windows should open shortly."
  echo $EVENTS > .test_events
  export DISPLAY="${DISPLAY:-:0}"
  nohup "$GODOT_BIN" --rendering-driver opengl3 --path . -- --client --name=A --auto-test > logs/client_A.log 2>&1 &
  echo $! > logs/client_A.pid
  sleep 2
  nohup "$GODOT_BIN" --rendering-driver opengl3 --path . -- --client --name=B --auto-test > logs/client_B.log 2>&1 &
  echo $! > logs/client_B.pid
  echo "Clients A and B started (auto-test, events=$EVENTS). Logs: logs/client_A.log, logs/client_B.log"
else
  echo "Starting human-play clients Player1 and Player2..."
  nohup "$GODOT_BIN" --rendering-driver opengl3 --path . -- --client --name=Player1 > /dev/null 2>&1 &
  sleep 2
  nohup "$GODOT_BIN" --rendering-driver opengl3 --path . -- --client --name=Player2 > /dev/null 2>&1 &
  echo "Two game windows should open. Connect, set name/color, press Ready in both."
fi
