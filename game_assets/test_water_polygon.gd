extends SceneTree
## Headless: mask boundary polygon build, Chaikin smooth, and triangulation.

const _WaterBuilder = preload("res://WaterBuilder.gd")

func _init():
	call_deferred("_begin")

func _begin():
	var cols := 5
	var rows := 5
	var step := 20.0
	var mask := PackedByteArray()
	mask.resize(cols * rows)
	# 3x3 block minus SE corner — concave L-like basin with room for margin.
	for j in range(3):
		for i in range(3):
			if i == 2 and j == 2:
				continue
			mask[j * cols + i] = 1

	var basin := {
		"min_i": 0,
		"max_i": 2,
		"min_j": 0,
		"max_j": 2,
		"mask": mask,
		"cols": cols,
		"rows": rows,
		"step": step,
		"surface_y": 1.0,
	}

	var raw_poly: PackedVector2Array = _WaterBuilder._mask_to_boundary_polygon(
		mask, cols, rows, 0, 2, 0, 2, step
	)
	if raw_poly.size() < 3:
		print("TEST_WATER_POLYGON_FAIL: raw boundary too small count=%d" % raw_poly.size())
		quit(1)
		return

	var final_poly: PackedVector2Array = _WaterBuilder.build_polygon_from_basin(basin)
	if final_poly.size() < 3:
		print("TEST_WATER_POLYGON_FAIL: final polygon too small")
		quit(1)
		return

	if final_poly.size() <= raw_poly.size():
		print(
			"TEST_WATER_POLYGON_FAIL: smoothing did not increase vertices raw=%d final=%d"
			% [raw_poly.size(), final_poly.size()]
		)
		quit(1)
		return

	var raw_area: float = _WaterBuilder.polygon_area(raw_poly)
	var final_area: float = _WaterBuilder.polygon_area(final_poly)
	var padded_rect_area: float = (5.0 * step) * (5.0 * step)

	if final_area > padded_rect_area:
		print(
			"TEST_WATER_POLYGON_FAIL: final area %.1f exceeds padded rect %.1f"
			% [final_area, padded_rect_area]
		)
		quit(1)
		return

	if final_area > raw_area * 1.5:
		print(
			"TEST_WATER_POLYGON_FAIL: final area %.1f too large vs raw %.1f"
			% [final_area, raw_area]
		)
		quit(1)
		return

	var mesh: ArrayMesh = _WaterBuilder._build_flat_mesh(final_poly, basin.surface_y)
	if mesh == null:
		print("TEST_WATER_POLYGON_FAIL: triangulation failed")
		quit(1)
		return

	print("TEST_WATER_POLYGON_OK")
	quit(0)
