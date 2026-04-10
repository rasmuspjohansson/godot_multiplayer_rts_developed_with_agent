#!/usr/bin/env bash
# Human play session: dedicated server + two windowed clients (3D World.tscn).
#
# What you already have:
#   ./run_tests.sh       — headless checks only (textures, spawn, goal arrival); no Main/lobby.
#   ./run_test.sh        — full stack: server + 2 clients; defaults to auto-test bots.
#   ./run_test.sh --no_test — same server + 2 human clients (this wrapper).
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
exec "$SCRIPT_DIR/run_test.sh" --no_test "$@"
