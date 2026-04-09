#!/usr/bin/env bash
# Human 3D session: dedicated server + two windowed clients using World3D (--3d).
#
# What you already have:
#   ./run_tests.sh       — headless checks only (textures, spawn, goal arrival); no Main/lobby.
#   ./run_test.sh        — full stack: server + 2 clients; defaults to 3D + auto-test bots.
#   ./run_test.sh --no_test — same server + 2 human clients (this wrapper).
#
# Optional: ./run_test.sh --no_test --2d  — 2D world instead of 3D.
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
exec "$SCRIPT_DIR/run_test.sh" --no_test "$@"
