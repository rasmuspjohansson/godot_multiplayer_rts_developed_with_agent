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
USE_3D=true
for arg in "$@"; do
  case "$arg" in
    --no_test|--no-test) AUTO_TEST=false ;;
    --events=1) EVENTS=1 ;;
    --events=2) EVENTS=2 ;;
    --3d) USE_3D=true ;;
    --2d) USE_3D=false ;;
  esac
done

# Clean up any existing instances: kill Godot engines and free port 8910.
# Do NOT use `pkill -f godot` — it matches any argv containing "godot", including
# shells running scripts under a directory named .../godot/... (kills this script).
# Our launches always pass --path to the engine, so match that.
echo "Stopping any existing Godot processes..."
pkill -9 -f '[g]odot.*--path' 2>/dev/null || true
pkill -9 -f 'Godot.*--path' 2>/dev/null || true
fuser -k 8910/tcp 2>/dev/null || true
sleep 2
# Wait until port 8910 is actually free (up to 10s)
for i in 1 2 3 4 5 6 7 8 9 10; do
  if ! fuser 8910/tcp 2>/dev/null; then break; fi
  sleep 1
done
if fuser 8910/tcp 2>/dev/null; then
  echo "ERROR: Port 8910 still in use. Stop the process using it and run again."
  exit 1
fi

mkdir -p logs
# Start with a fresh server log so we can detect our server
: > logs/server.log

# Server: run under nohup so it survives script exit (no SIGHUP)
nohup "$GODOT_BIN" --headless --path . -- --server >> logs/server.log 2>&1 &
echo $! > logs/server.pid
echo "Server starting (PID $(cat logs/server.pid)). Waiting for server to be ready..."

# Wait for TEST_001 so we know our new server is the one listening (up to 20s)
for i in $(seq 1 20); do
  if grep -q "TEST_001" logs/server.log 2>/dev/null; then
    echo "Server is ready."
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "ERROR: Server did not print TEST_001 in time. Check logs/server.log"
    exit 1
  fi
  sleep 1
done
sleep 2

if [ "$AUTO_TEST" = true ]; then
  echo "Starting auto-test clients A and B (events=$EVENTS)..."
  echo "Two game windows should open shortly."
  echo $EVENTS > .test_events
  export DISPLAY="${DISPLAY:-:0}"
  CLIENT_ARGS="--client --name=A --auto-test --events=$EVENTS"
  [ "$USE_3D" = true ] && CLIENT_ARGS="$CLIENT_ARGS --3d"
  nohup "$GODOT_BIN" --rendering-driver opengl3 --path . -- $CLIENT_ARGS > logs/client_A.log 2>&1 &
  echo $! > logs/client_A.pid
  sleep 2
  CLIENT_ARGS="--client --name=B --auto-test --events=$EVENTS"
  [ "$USE_3D" = true ] && CLIENT_ARGS="$CLIENT_ARGS --3d"
  nohup "$GODOT_BIN" --rendering-driver opengl3 --path . -- $CLIENT_ARGS > logs/client_B.log 2>&1 &
  echo $! > logs/client_B.pid
  echo "Clients A and B started (auto-test, events=$EVENTS). Logs: logs/client_A.log, logs/client_B.log"
else
  echo "Starting human-play clients Player1 and Player2..."
  export DISPLAY="${DISPLAY:-:0}"
  CLIENT_ARGS="--client --name=Player1"
  [ "$USE_3D" = true ] && CLIENT_ARGS="$CLIENT_ARGS --3d"
  nohup "$GODOT_BIN" --rendering-driver opengl3 --path . -- $CLIENT_ARGS > logs/client_Player1.log 2>&1 &
  echo $! > logs/client_Player1.pid
  sleep 2
  CLIENT_ARGS="--client --name=Player2"
  [ "$USE_3D" = true ] && CLIENT_ARGS="$CLIENT_ARGS --3d"
  nohup "$GODOT_BIN" --rendering-driver opengl3 --path . -- $CLIENT_ARGS > logs/client_Player2.log 2>&1 &
  echo $! > logs/client_Player2.pid
  echo "Two game windows should open. Connect, set name/color, press Ready in both."
  echo "Logs: logs/client_Player1.log, logs/client_Player2.log"
fi
