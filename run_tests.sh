#!/usr/bin/env bash
# Run automated checks: headless PNG path test + optional client log verification.
# Usage:
#   ./run_tests.sh              — headless texture paths only
#   ./run_tests.sh --with-logs  — also verify logs/client_*.log (after ./run_test.sh)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
GODOT_BIN="${GODOT_BIN:-godot}"

echo "=== Headless: test_texture_paths.gd ==="
"$GODOT_BIN" --headless --path . -s test_texture_paths.gd

echo "=== Headless: test_world3d_spawn.gd ==="
"$GODOT_BIN" --headless --path . -s test_world3d_spawn.gd

echo "=== Headless: test_world3d_goal_arrival.gd ==="
"$GODOT_BIN" --headless --path . -s test_world3d_goal_arrival.gd

if [[ "${1:-}" == "--with-logs" ]]; then
	echo "=== verify_test_logs.sh ==="
	./verify_test_logs.sh
fi

echo "=== All requested checks passed ==="
