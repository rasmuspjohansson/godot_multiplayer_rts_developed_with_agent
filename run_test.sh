#!/usr/bin/env bash
# Start server + two clients for Automated RTS.
# Default: auto-test (both clients run MockPlayer). Use --no_test to start two
# human-playable clients (no MockPlayer).
#
# Remote debugging (Scene dock → Remote, Debugger → session picker):
#   ./run_test.sh --remote-debug
#   ./run_test.sh --remote-debug --remote-debug-uri=tcp://127.0.0.1:6007
#   GODOT_REMOTE_DEBUG=tcp://127.0.0.1:6007 ./run_test.sh
# Open the Godot editor first, enable Debug → Keep Debug Server Open, then run this script.
#
# Optional: --server-window — run the dedicated server with a visible window (OpenGL).
#
# Set GODOT_BIN to the full path to your Godot executable if "godot" is not in PATH.

set -e
GODOT_BIN="${GODOT_BIN:-godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

AUTO_TEST=true
REMOTE_DEBUG=false
REMOTE_DEBUG_URI="tcp://127.0.0.1:6007"
SERVER_WINDOW=false

for arg in "$@"; do
  case "$arg" in
    --no_test|--no-test) AUTO_TEST=false ;;
    --remote-debug) REMOTE_DEBUG=true ;;
    --remote-debug-uri=*) REMOTE_DEBUG=true; REMOTE_DEBUG_URI="${arg#*=}" ;;
    --server-window) SERVER_WINDOW=true ;;
  esac
done

if [ -n "${GODOT_REMOTE_DEBUG:-}" ]; then
  REMOTE_DEBUG=true
  REMOTE_DEBUG_URI="$GODOT_REMOTE_DEBUG"
fi

REMOTE_DEBUG_ARGS=()
if [ "$REMOTE_DEBUG" = true ]; then
  REMOTE_DEBUG_ARGS=(--remote-debug "$REMOTE_DEBUG_URI")
fi

if [ "$SERVER_WINDOW" = true ]; then
  SERVER_RENDER_ARGS=(--rendering-driver opengl3)
else
  SERVER_RENDER_ARGS=(--headless)
fi

# Clean up any prior game instances (do NOT kill the editor).
echo "Stopping any existing dedicated server / client Godot processes..."
pkill -9 -f -- '[g]odot.*-- --server' 2>/dev/null || true
pkill -9 -f -- 'Godot.*-- --server' 2>/dev/null || true
pkill -9 -f -- '[g]odot.*-- --client' 2>/dev/null || true
pkill -9 -f -- 'Godot.*-- --client' 2>/dev/null || true
fuser -k 8910/tcp 2>/dev/null || true
sleep 2
for i in 1 2 3 4 5 6 7 8 9 10; do
  if ! fuser 8910/tcp 2>/dev/null; then break; fi
  sleep 1
done
if fuser 8910/tcp 2>/dev/null; then
  echo "ERROR: Port 8910 still in use. Stop the process using it and run again."
  exit 1
fi

mkdir -p logs
: > logs/server.log

if [ "$SERVER_WINDOW" = true ]; then
  export DISPLAY="${DISPLAY:-:0}"
fi

nohup "$GODOT_BIN" "${REMOTE_DEBUG_ARGS[@]}" "${SERVER_RENDER_ARGS[@]}" --path . -- --server >> logs/server.log 2>&1 &
echo $! > logs/server.pid
echo "Server starting (PID $(cat logs/server.pid)). Waiting for server to be ready..."

for i in $(seq 1 20); do
  if grep -q "TEST_SERVER_START" logs/server.log 2>/dev/null; then
    echo "Server is ready."
    break
  fi
  if [ "$i" -eq 20 ]; then
    echo "ERROR: Server did not print TEST_SERVER_START in time. Check logs/server.log"
    exit 1
  fi
  sleep 1
done
sleep 2

if [ "$AUTO_TEST" = true ]; then
  echo "Starting auto-test clients A and B..."
  echo "Two game windows should open shortly."
  export DISPLAY="${DISPLAY:-:0}"
  nohup "$GODOT_BIN" "${REMOTE_DEBUG_ARGS[@]}" --rendering-driver opengl3 --path . -- --client --name=A --auto-test > logs/client_A.log 2>&1 &
  echo $! > logs/client_A.pid
  sleep 2
  nohup "$GODOT_BIN" "${REMOTE_DEBUG_ARGS[@]}" --rendering-driver opengl3 --path . -- --client --name=B --auto-test > logs/client_B.log 2>&1 &
  echo $! > logs/client_B.pid
  echo "Clients A and B started (auto-test). Logs: logs/client_A.log, logs/client_B.log"
else
  echo "Starting human-play clients Player1 and Player2..."
  export DISPLAY="${DISPLAY:-:0}"
  nohup "$GODOT_BIN" "${REMOTE_DEBUG_ARGS[@]}" --rendering-driver opengl3 --path . -- --client --name=Player1 > logs/client_Player1.log 2>&1 &
  echo $! > logs/client_Player1.pid
  sleep 2
  nohup "$GODOT_BIN" "${REMOTE_DEBUG_ARGS[@]}" --rendering-driver opengl3 --path . -- --client --name=Player2 > logs/client_Player2.log 2>&1 &
  echo $! > logs/client_Player2.pid
  echo "Two game windows should open. Connect, set name/color, press Ready in both."
  echo "Logs: logs/client_Player1.log, logs/client_Player2.log"
fi
