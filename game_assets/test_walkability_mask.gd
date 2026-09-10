extends SceneTree
## Lake masks are full-map (global i,j). Walkability must not treat them as
## bbox-local, or the steep texture appears offset from the water.

const _WalkabilityGrid = preload("res://WalkabilityGrid.gd")

func _init():
	call_deferred("_begin")

func _begin():
	var cols := 40
	var rows := 30
	var step := 20.0
	var heights := PackedFloat32Array()
	heights.resize(cols * rows)
	for idx in range(heights.size()):
		heights[idx] = 5.0
	var wet_i := 12
	var wet_j := 8
	var mask := PackedByteArray()
	mask.resize(cols * rows)
	mask[wet_j * cols + wet_i] = 1
	var basin := {
		"min_i": wet_i,
		"max_i": wet_i,
		"min_j": wet_j,
		"max_j": wet_j,
		"mask": mask,
		"cols": cols,
		"rows": rows,
		"step": step,
	}
	var grid = _WalkabilityGrid.new()
	grid.build(heights, cols, rows, step, [basin], 89.0)
	if grid.is_walkable_cell(wet_i, wet_j):
		print("TEST_WALKABILITY_MASK_FAIL: lake cell still walkable")
		quit(1)
		return
	var ghost_i: int = wet_i + wet_i
	var ghost_j: int = wet_j + wet_j
	if not grid.is_walkable_cell(ghost_i, ghost_j):
		print(
			"TEST_WALKABILITY_MASK_FAIL: offset cell (%d,%d) blocked (bbox-local mask bug)"
			% [ghost_i, ghost_j]
		)
		quit(1)
		return
	print("TEST_WALKABILITY_MASK_OK")
	quit(0)
