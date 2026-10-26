#!/usr/bin/env bash
# Run all headless unit tests, optionally followed by match log verification.
# Usage:
#   ./run_tests.sh              — headless tests only
#   ./run_tests.sh --with-logs  — also verify logs/*.log (after ./run_test.sh)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
BUNDLED_GODOT="$SCRIPT_DIR/../tools/godot/Godot_v4.6.1-stable_linux.x86_64"
if [[ -z "${GODOT_BIN:-}" ]]; then
	if [[ -x "$BUNDLED_GODOT" ]]; then
		GODOT_BIN="$BUNDLED_GODOT"
	else
		GODOT_BIN="godot"
	fi
fi

FAILED=()

run_test() {
	echo "=== Headless: $1 ==="
	"$GODOT_BIN" --headless --path . -s "$1" || FAILED+=("$1")
}

run_test_map() {
	echo "=== Headless: $2 (--map=$1) ==="
	"$GODOT_BIN" --headless --path . --map="$1" -s "$2" || FAILED+=("$2 (--map=$1)")
}

run_test test_texture_paths.gd
run_test test_world3d_spawn.gd
run_test test_world3d_goal_arrival.gd
run_test test_terrain_feature_types.gd
run_test_map XL test_xl_map_bounds.gd
run_test_map XL test_camera_w_pan_zoom_out.gd
run_test_map XL test_water_lakes.gd
run_test test_water_polygon.gd
run_test test_water_basin_filter.gd
run_test_map XL test_map_lighting.gd
run_test_map XL test_walkability.gd
run_test test_walkability_mask.gd
run_test test_spawn_walkability.gd
run_test_map XL test_vegetation.gd
run_test test_spatial_hash.gd
run_test test_unit_sim.gd
run_test test_move_sync.gd
run_test test_facing_flip.gd
run_test test_sim_determinism.gd
run_test test_formation_rigidity.gd
run_test test_fog_of_war.gd
run_test test_world3d_horse_speed.gd
run_test test_server_match.gd
run_test test_terrain_height_consistency.gd
run_test_map XL test_terrain_tint.gd
run_test test_arrow_trajectory.gd
run_test test_group_formation_drag.gd

if [[ "${1:-}" == "--with-logs" ]]; then
	echo "=== verify_test_logs.sh ==="
	./verify_test_logs.sh || FAILED+=("verify_test_logs.sh")
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
	echo "=== FAILED (${#FAILED[@]}): ${FAILED[*]} ==="
	exit 1
fi
echo "=== All requested checks passed ==="
