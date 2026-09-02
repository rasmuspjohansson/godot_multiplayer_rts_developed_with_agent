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
# Optional: --map NAME — map JSON name (default S). S/L/XL or any maps/map_NAME.json.
#
# Set GODOT_BIN to the full path to your Godot executable if "godot" is not in PATH.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_PATH="$SCRIPT_DIR/game_assets"
GODOT_BUNDLED="$SCRIPT_DIR/tools/godot/Godot_v4.6.1-stable_linux.x86_64"
if [[ -z "${GODOT_BIN:-}" && -x "$GODOT_BUNDLED" ]]; then
  GODOT_BIN="$GODOT_BUNDLED"
else
  GODOT_BIN="${GODOT_BIN:-godot}"
fi
cd "$SCRIPT_DIR"

AUTO_TEST=true
REMOTE_DEBUG=false
REMOTE_DEBUG_URI="tcp://127.0.0.1:6007"
SERVER_WINDOW=false
MAP_SIZE="S"

args=("$@")
i=0
while [ $i -lt ${#args[@]} ]; do
  arg="${args[$i]}"
  case "$arg" in
    --no_test|--no-test) AUTO_TEST=false ;;
    --remote-debug) REMOTE_DEBUG=true ;;
    --remote-debug-uri=*) REMOTE_DEBUG=true; REMOTE_DEBUG_URI="${arg#*=}" ;;
    --server-window) SERVER_WINDOW=true ;;
    --map=*)
      MAP_SIZE="${arg#*=}"
      ;;
    --map)
      if [ $((i + 1)) -lt ${#args[@]} ]; then
        i=$((i + 1))
        MAP_SIZE="${args[$i]}"
      fi
      ;;
  esac
  i=$((i + 1))
done
case "${MAP_SIZE^^}" in
  S|L|XL) MAP_SIZE="${MAP_SIZE^^}" ;;
esac
if [[ ! "$MAP_SIZE" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "ERROR: Invalid --map name '$MAP_SIZE'"
  exit 1
fi
if [[ ! -f "$GAME_PATH/project.godot" ]]; then
  echo "ERROR: Godot project not found at $GAME_PATH"
  exit 1
fi

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

SERVER_EXTRA_ARGS=()
if [ "$AUTO_TEST" = true ]; then
  SERVER_EXTRA_ARGS+=(--auto-test)
fi
nohup "$GODOT_BIN" "${REMOTE_DEBUG_ARGS[@]}" "${SERVER_RENDER_ARGS[@]}" --path "$GAME_PATH" -- --server "${SERVER_EXTRA_ARGS[@]}" --map="$MAP_SIZE" >> logs/server.log 2>&1 &
echo $! > logs/server.pid
echo "Server starting (PID $(cat logs/server.pid), map=$MAP_SIZE). Waiting for server to be ready..."

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
  nohup "$GODOT_BIN" "${REMOTE_DEBUG_ARGS[@]}" --rendering-driver opengl3 --path "$GAME_PATH" -- --client --name=A --auto-test --map="$MAP_SIZE" > logs/client_A.log 2>&1 &
  echo $! > logs/client_A.pid
  sleep 2
  nohup "$GODOT_BIN" "${REMOTE_DEBUG_ARGS[@]}" --rendering-driver opengl3 --path "$GAME_PATH" -- --client --name=B --auto-test --color=1 --map="$MAP_SIZE" > logs/client_B.log 2>&1 &
  echo $! > logs/client_B.pid
  echo "Clients A and B started (auto-test). Logs: logs/client_A.log, logs/client_B.log"
else
  echo "Starting human-play clients Player1 and Player2..."
  export DISPLAY="${DISPLAY:-:0}"
  nohup "$GODOT_BIN" "${REMOTE_DEBUG_ARGS[@]}" --rendering-driver opengl3 --path "$GAME_PATH" -- --client --name=Player1 --map="$MAP_SIZE" > logs/client_Player1.log 2>&1 &
  echo $! > logs/client_Player1.pid
  sleep 2
  nohup "$GODOT_BIN" "${REMOTE_DEBUG_ARGS[@]}" --rendering-driver opengl3 --path "$GAME_PATH" -- --client --name=Player2 --map="$MAP_SIZE" > logs/client_Player2.log 2>&1 &
  echo $! > logs/client_Player2.pid
  echo "Two game windows should open. Connect, set name/color, press Ready in both."
  echo "Logs: logs/client_Player1.log, logs/client_Player2.log"
fi
