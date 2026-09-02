#!/usr/bin/env bash
# Download Godot 4.6.1 (Linux x86_64) into tools/godot/ so connect_remote.sh / run_test.sh find it.
# Usage:
#   ./install_godot_linux.sh
#   ./install_godot_linux.sh --force

set -euo pipefail

GODOT_VERSION="4.6.1-stable"
BIN_NAME="Godot_v4.6.1-stable_linux.x86_64"
ZIP_NAME="Godot_v4.6.1-stable_linux.x86_64.zip"
DOWNLOAD_URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/${ZIP_NAME}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools/godot"
BIN_PATH="$TOOLS_DIR/$BIN_NAME"
ZIP_PATH="$TOOLS_DIR/$ZIP_NAME"
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=true ;;
  esac
done

echo "Godot Linux installer"
echo "  Target: $BIN_PATH"
echo

if [[ -x "$BIN_PATH" && "$FORCE" != true ]]; then
  echo "Already installed. Use --force to re-download."
  echo
  echo "Next step:"
  echo "  ./connect_remote.sh --host=SERVER_IP"
  exit 0
fi

mkdir -p "$TOOLS_DIR"

echo "Downloading $DOWNLOAD_URL ..."
if command -v curl >/dev/null 2>&1; then
  curl -fL --progress-bar -o "$ZIP_PATH" "$DOWNLOAD_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$ZIP_PATH" "$DOWNLOAD_URL"
else
  echo "ERROR: need curl or wget to download Godot."
  exit 1
fi

if [[ ! -s "$ZIP_PATH" ]]; then
  echo "ERROR: Download failed or file empty: $ZIP_PATH"
  exit 1
fi

echo "Extracting to $TOOLS_DIR ..."
if command -v unzip >/dev/null 2>&1; then
  unzip -o "$ZIP_PATH" -d "$TOOLS_DIR"
else
  python3 - "$ZIP_PATH" "$TOOLS_DIR" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
fi
rm -f "$ZIP_PATH"

if [[ ! -f "$BIN_PATH" ]]; then
  found="$(find "$TOOLS_DIR" -name "$BIN_NAME" -type f | head -1 || true)"
  if [[ -z "$found" ]]; then
    echo "ERROR: Download finished but $BIN_NAME was not found under $TOOLS_DIR"
    exit 1
  fi
  if [[ "$found" != "$BIN_PATH" ]]; then
    mv -f "$found" "$BIN_PATH"
  fi
fi

chmod +x "$BIN_PATH"

echo
echo "Godot 4.6.1 installed successfully."
echo
echo "Next step (join a remote game):"
echo "  ./connect_remote.sh --host=SERVER_IP"
echo "Then press Ready in the lobby."
