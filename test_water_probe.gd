extends SceneTree

const _MapConfigScript = preload("res://MapConfig.gd")
const _WaterBuilder = preload("res://WaterBuilder.gd")

func _init():
	call_deferred("_begin")

func _begin():
	var map_cfg: Node = _MapConfigScript.new()
	root.add_child(map_cfg)
	var w = load("res://World.tscn").instantiate()
	root.add_child(w)
	await process_frame
	await process_frame
	for _i in range(10):
		await physics_frame

	var cols: int = w._terrain_cols
	var rows: int = w._terrain_rows
	var step: float = w._terrain_step
	var heights: PackedFloat32Array = w._terrain_heights

	var min_list: Array = []
	for j in range(1, rows - 1):
		for i in range(1, cols - 1):
			var idx := j * cols + i
			var h: float = heights[idx]
			var is_local_min := true
			for dj in range(-1, 2):
				for di in range(-1, 2):
					if di == 0 and dj == 0:
						continue
					if heights[(j + dj) * cols + (i + di)] < h:
						is_local_min = false
			if is_local_min:
				min_list.append({"i": i, "j": j, "h": h, "x": float(i) * step, "z": float(j) * step})

	min_list.sort_custom(func(a, b): return a.h < b.h)
	print("TEST_WATER_PROBE: lowest_local_mins (top 15):")
	for k in range(mini(15, min_list.size())):
		var c: Dictionary = min_list[k]
		print("  h=%.2f at (%.0f, %.0f)" % [c.h, c.x, c.z])
	var inland_mins: Array = []
	for c in min_list:
		var i: int = c.i
		var j: int = c.j
		if i < 8 or j < 8 or i >= cols - 8 or j >= rows - 8:
			continue
		inland_mins.append(c)
	inland_mins.sort_custom(func(a, b): return a.h < b.h)
	print("TEST_WATER_PROBE: lowest_inland_mins (top 10):")
	for k in range(mini(10, inland_mins.size())):
		var c: Dictionary = inland_mins[k]
		print("  h=%.2f at (%.0f, %.0f)" % [c.h, c.x, c.z])

	var global_min := INF
	var global_min_at := Vector2.ZERO
	for j in range(rows):
		for i in range(cols):
			var h: float = heights[j * cols + i]
			if h < global_min:
				global_min = h
				global_min_at = Vector2(float(i) * step, float(j) * step)
	print("TEST_WATER_PROBE: global_min=%.2f at (%.0f, %.0f)" % [global_min, global_min_at.x, global_min_at.y])

	for probe in [
		Vector2(520, 680), Vector2(3300, 1750),
	]:
		print("TEST_WATER_PROBE: h=%.2f at (%.0f, %.0f)" % [map_cfg.sample_height(probe.x, probe.y), probe.x, probe.y])

	var params := _WaterBuilder.default_params()
	params.fill_epsilon = 12.0
	params.min_basin_height = 15.0
	params.reject_map_edge = true

	var min_cells: int = params.min_cells
	var visited := PackedByteArray()
	visited.resize(cols * rows)
	var candidates := PackedByteArray()
	candidates.resize(cols * rows)
	for j in range(1, rows - 1):
		for i in range(1, cols - 1):
			var idx := j * cols + i
			var h: float = heights[idx]
			var is_local_min := true
			for dj in range(-1, 2):
				for di in range(-1, 2):
					if di == 0 and dj == 0:
						continue
					if heights[(j + dj) * cols + (i + di)] < h:
						is_local_min = false
			if is_local_min:
				candidates[idx] = 1
	var stage := {"fill": 0, "clip": 0, "donut": 0, "poly": 0}
	var border_margin := 3
	for j in range(rows):
		for i in range(cols):
			if visited[j * cols + i] != 0 or candidates[j * cols + i] == 0:
				continue
			if heights[j * cols + i] < params.min_basin_height:
				continue
			if params.reject_map_edge and (
				i < border_margin or j < border_margin
				or i >= cols - border_margin or j >= rows - border_margin
			):
				continue
			var basin: Dictionary = _WaterBuilder._flood_fill_basin(
				heights, cols, rows, step, i, j, params.fill_epsilon
			)
			if basin.cell_count < min_cells:
				continue
			stage.fill += 1
			var surface_y: float = _WaterBuilder._water_surface_y(
				heights, cols, rows, basin, params.water_depth
			)
			var is_donut := _WaterBuilder._basin_has_interior_high_ground(heights, cols, rows, basin, surface_y)
			if is_donut:
				stage.donut += 1
				print(
					"  basin donut: min_h=%.2f surface=%.2f cells=%d at (%d,%d)"
					% [basin.min_height, surface_y, basin.cell_count, i, j]
				)
				continue
			var clipped: Dictionary = _WaterBuilder._clip_mask_to_submerged(
				heights, cols, rows, basin, surface_y
			)
			clipped = _WaterBuilder._largest_connected_component(
				clipped.mask, cols, rows, clipped.min_i, clipped.max_i, clipped.min_j, clipped.max_j
			)
			print(
				"  basin clip: min_h=%.2f surface=%.2f fill=%d clipped=%d at (%d,%d)"
				% [basin.min_height, surface_y, basin.cell_count, clipped.cell_count, i, j]
			)
			if clipped.cell_count < min_cells:
				continue
			stage.clip += 1
			var lb := {
				"surface_y": surface_y, "min_i": clipped.min_i, "max_i": clipped.max_i,
				"min_j": clipped.min_j, "max_j": clipped.max_j, "mask": clipped.mask,
				"cols": cols, "rows": rows, "step": step,
			}
			if _WaterBuilder.build_polygon_from_basin(lb).size() >= 3:
				stage.poly += 1
	print("TEST_WATER_PROBE: stages fill=%d donut_reject=%d clip_ok=%d poly_ok=%d" % [
		stage.fill, stage.donut, stage.clip, stage.poly
	])

	var basins: Array = _WaterBuilder.detect_lake_basins(
		heights, cols, rows, step, map_cfg.width, map_cfg.height, params
	)
	print("TEST_WATER_PROBE: lakes=%d" % basins.size())
	for bi in range(basins.size()):
		var b: Dictionary = basins[bi]
		print(
			"  lake %d: cells=%d surface_y=%.2f bbox=(%.0f-%.0f, %.0f-%.0f)"
			% [bi, b.cell_count, b.surface_y, b.min_x, b.max_x, b.min_z, b.max_z]
		)

	# Sample valley polygon centers
	for label in ["SW_valley", "NE_valley"]:
		var px: float = 620.0 if label == "SW_valley" else 3180.0
		var pz: float = 1780.0 if label == "SW_valley" else 600.0
		print("TEST_WATER_PROBE: %s sample_height=%.2f" % [label, map_cfg.sample_height(px, pz)])

	quit(0)
