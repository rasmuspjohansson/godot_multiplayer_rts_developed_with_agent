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

echo "=== Headless: test_terrain_feature_types.gd ==="
"$GODOT_BIN" --headless --path . -s test_terrain_feature_types.gd

echo "=== Headless: test_xl_map_bounds.gd (--map=XL) ==="
"$GODOT_BIN" --headless --path . --map=XL -s test_xl_map_bounds.gd

echo "=== Headless: test_camera_w_pan_zoom_out.gd (--map=XL) ==="
"$GODOT_BIN" --headless --path . --map=XL -s test_camera_w_pan_zoom_out.gd

echo "=== Headless: test_water_lakes.gd (--map=XL) ==="
"$GODOT_BIN" --headless --path . --map=XL -s test_water_lakes.gd

echo "=== Headless: test_water_polygon.gd ==="
"$GODOT_BIN" --headless --path . -s test_water_polygon.gd

echo "=== Headless: test_water_basin_filter.gd ==="
"$GODOT_BIN" --headless --path . -s test_water_basin_filter.gd

echo "=== Headless: test_map_lighting.gd (--map=XL) ==="
"$GODOT_BIN" --headless --path . --map=XL -s test_map_lighting.gd

echo "=== Headless: test_walkability.gd (--map=XL) ==="
"$GODOT_BIN" --headless --path . --map=XL -s test_walkability.gd

if [[ "${1:-}" == "--with-logs" ]]; then
	echo "=== verify_test_logs.sh ==="
	./verify_test_logs.sh
fi

echo "=== All requested checks passed ==="
