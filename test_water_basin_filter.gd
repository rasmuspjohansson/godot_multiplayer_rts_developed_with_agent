extends SceneTree
## Headless: reject donut basins and clip water to submerged cells only.

const _WaterBuilder = preload("res://WaterBuilder.gd")

func _init():
	call_deferred("_begin")

func _begin():
	var cols := 7
	var rows := 7
	var step := 20.0
	var heights := PackedFloat32Array()
	heights.resize(cols * rows)
	for j in range(rows):
		for i in range(cols):
			heights[j * cols + i] = 5.0

	# Ring wet cells around a dry peak (height 50) at center (3,3).
	var ring_cells: Array = [
		Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
		Vector2i(2, 3), Vector2i(4, 3),
		Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4),
	]
	var mask := PackedByteArray()
	mask.resize(cols * rows)
	for p in ring_cells:
		mask[p.y * cols + p.x] = 1
	heights[3 * cols + 3] = 50.0

	var basin := {
		"min_i": 2,
		"max_i": 4,
		"min_j": 2,
		"max_j": 4,
		"min_height": 5.0,
		"cell_count": ring_cells.size(),
		"mask": mask,
	}
	var surface_y := 11.0

	if not _WaterBuilder._basin_has_interior_high_ground(heights, cols, rows, basin, surface_y):
		print("TEST_WATER_BASIN_FILTER_FAIL: expected donut basin rejection")
		quit(1)
		return

	# Low bowl: all wet cells below surface.
	var bowl_mask := PackedByteArray()
	bowl_mask.resize(cols * rows)
	for j in range(2, 5):
		for i in range(2, 5):
			bowl_mask[j * cols + i] = 1
			heights[j * cols + i] = 2.0
	var bowl := {
		"min_i": 2,
		"max_i": 4,
		"min_j": 2,
		"max_j": 4,
		"min_height": 2.0,
		"cell_count": 9,
		"mask": bowl_mask,
	}
	var bowl_surface := 8.0
	if _WaterBuilder._basin_has_interior_high_ground(heights, cols, rows, bowl, bowl_surface):
		print("TEST_WATER_BASIN_FILTER_FAIL: rejected valid bowl basin")
		quit(1)
		return

	# Clip: slope cell above surface should be removed.
	var slope_mask := bowl_mask.duplicate()
	heights[3 * cols + 3] = 10.0
	var clipped: Dictionary = _WaterBuilder._clip_mask_to_submerged(
		heights, cols, rows, bowl, bowl_surface
	)
	if clipped.cell_count >= 9:
		print("TEST_WATER_BASIN_FILTER_FAIL: clip did not remove above-surface cell")
		quit(1)
		return
	if clipped.cell_count < 8:
		print("TEST_WATER_BASIN_FILTER_FAIL: clip removed too many cells count=%d" % clipped.cell_count)
		quit(1)
		return

	print("TEST_WATER_BASIN_FILTER_OK")
	quit(0)
