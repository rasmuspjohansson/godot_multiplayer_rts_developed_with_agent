extends SceneTree
## Headless XL: walkability grid marks water and steep slopes; paths route around lakes.

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

	if map_cfg.map_size != "XL":
		print("TEST_WALKABILITY_SKIP: map=%s (run with --map=XL)" % map_cfg.map_size)
		quit(0)
		return

	if w._walkability == null:
		print("TEST_WALKABILITY_FAIL: missing walkability grid")
		quit(1)
		return

	var water_blocked := false
	for basin in w._water_basins:
		var mask: PackedByteArray = basin.get("mask", PackedByteArray())
		var basin_cols: int = int(basin.get("cols", 0))
		var min_i: int = int(basin.get("min_i", 0))
		var max_i: int = int(basin.get("max_i", basin_cols - 1))
		var min_j: int = int(basin.get("min_j", 0))
		var max_j: int = int(basin.get("max_j", int(basin.get("rows", 0)) - 1))
		for j in range(min_j, max_j + 1):
			for i in range(min_i, max_i + 1):
				if mask[j * basin_cols + i] == 0:
					continue
				if not w._walkability.is_walkable_cell(i, j):
					water_blocked = true
					break
			if water_blocked:
				break
		if water_blocked:
			break
	if not water_blocked:
		print("TEST_WALKABILITY_FAIL: lake cells still walkable")
		quit(1)
		return

	var polygon_blocked := false
	for basin in w._water_basins:
		var poly: PackedVector2Array = _WaterBuilder.build_polygon_from_basin(basin)
		if poly.size() < 3:
			continue
		var cx := 0.0
		var cz := 0.0
		for p in poly:
			cx += p.x
			cz += p.y
		cx /= float(poly.size())
		cz /= float(poly.size())
		var center := Vector2(cx, cz)
		if not Geometry2D.is_point_in_polygon(center, poly):
			continue
		if not w.is_walkable_at(center.x, center.y):
			polygon_blocked = true
			break
	if not polygon_blocked:
		print("TEST_WALKABILITY_FAIL: lake polygon interior still walkable")
		quit(1)
		return

	var steep_found := false
	for j in range(w._terrain_rows):
		for i in range(w._terrain_cols):
			if w._walkability.is_walkable_cell(i, j):
				continue
			var in_water := false
			for basin in w._water_basins:
				var mask: PackedByteArray = basin.get("mask", PackedByteArray())
				var basin_cols: int = int(basin.get("cols", 0))
				if i >= 0 and j >= 0 and i < basin_cols and j < int(basin.get("rows", 0)):
					if mask[j * basin_cols + i] != 0:
						in_water = true
						break
			if not in_water:
				steep_found = true
				break
		if steep_found:
			break
	if not steep_found:
		print("TEST_WALKABILITY_FAIL: no steep-slope blocked cells")
		quit(1)
		return

	var path: PackedVector2Array = w.find_unit_path(Vector2(400.0, 700.0), Vector2(3400.0, 700.0))
	if path.size() < 3:
		print("TEST_WALKABILITY_FAIL: expected routed path length >= 3 got %d" % path.size())
		quit(1)
		return
	for pt in path:
		if not w.is_walkable_at(pt.x, pt.y):
			print("TEST_WALKABILITY_FAIL: path crosses unwalkable (%.0f, %.0f)" % [pt.x, pt.y])
			quit(1)
			return

	var ground: Node = w.get_node_or_null("Ground")
	if ground == null or not ground is MeshInstance3D:
		print("TEST_WALKABILITY_FAIL: missing Ground")
		quit(1)
		return
	var mesh: Mesh = ground.mesh
	var mat: Material = mesh.surface_get_material(0)
	if mat == null or not mat is ShaderMaterial:
		print("TEST_WALKABILITY_FAIL: ground missing ShaderMaterial")
		quit(1)
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var blocked_alpha := false
	for c in colors:
		if c.a < 0.5:
			blocked_alpha = true
			break
	if not blocked_alpha:
		print("TEST_WALKABILITY_FAIL: no blocked vertex alpha on ground")
		quit(1)
		return

	print(
		"TEST_WALKABILITY_OK: lakes=%d path=%d blocked_cells=%d"
		% [
			w._water_basins.size(),
			path.size(),
			w._terrain_cols * w._terrain_rows - w._walkability.walkable_count(),
		]
	)
	quit(0)
