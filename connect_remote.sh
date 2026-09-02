#!/usr/bin/env bash
# Join a remote game server as a human client.
# Usage:
#   ./connect_remote.sh --host=SERVER_IP
#   ./connect_remote.sh --host=SERVER_IP --name=Human
# Other game flags are passed through (e.g. --map=XL --color=2).

set -e
GODOT_BIN="${GODOT_BIN:-godot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_PATH="$SCRIPT_DIR/game_assets"

NAME="Human"
HOST=""
EXTRA=()

args=("$@")
i=0
while [ $i -lt ${#args[@]} ]; do
  arg="${args[$i]}"
  case "$arg" in
    --host=*) HOST="${arg#*=}" ;;
    --host)
      i=$((i + 1))
      HOST="${args[$i]:-}"
      ;;
    --name=*) NAME="${arg#*=}" ;;
    --name)
      i=$((i + 1))
      NAME="${args[$i]:-}"
      ;;
    *) EXTRA+=("$arg") ;;
  esac
  i=$((i + 1))
done

if [ -z "$HOST" ]; then
  echo "Usage: $0 --host=SERVER_IP [--name=Human] [other flags...]"
  echo "Example: $0 --host=91.99.144.8"
  exit 1
fi

if [[ ! -f "$GAME_PATH/project.godot" ]]; then
  echo "ERROR: Godot project not found at $GAME_PATH"
  exit 1
fi

if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [[ ! -x "$GODOT_BIN" ]]; then
  echo "ERROR: Godot not found. Install Godot 4.6.x or set GODOT_BIN."
  exit 1
fi

echo "Connecting as '$NAME' to $HOST:8910 ..."
echo "In the lobby: press Ready when you are set."

exec "$GODOT_BIN" --rendering-driver opengl3 --path "$GAME_PATH" -- \
  --client --name="$NAME" --color=1 --host="$HOST" "${EXTRA[@]}"
