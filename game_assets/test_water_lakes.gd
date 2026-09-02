extends SceneTree
## Headless XL: auto-detected lake basins spawn polygon water meshes.

const _MapConfigScript = preload("res://MapConfig.gd")
const _WaterBuilder = preload("res://WaterBuilder.gd")

func _init():
	call_deferred("_begin")

func _begin():
	var map_cfg: Node = _MapConfigScript.new()
	root.add_child(map_cfg)
	var w: Node3D = load("res://World.tscn").instantiate()
	root.add_child(w)
	await process_frame
	await process_frame
	for _i in range(10):
		await physics_frame

	if map_cfg.map_size != "XL":
		print("TEST_WATER_SKIP: map=%s (run with --map=XL)" % map_cfg.map_size)
		quit(0)
		return

	var water_root := w.get_node_or_null("Water")
	if water_root == null:
		print("TEST_WATER_FAIL: missing Water node")
		quit(1)
		return

	var basins: Array = _WaterBuilder.detect_valley_polygon_lakes(
		w._terrain_heights,
		w._terrain_cols,
		w._terrain_rows,
		w._terrain_step,
		map_cfg.width,
		map_cfg.height,
		map_cfg.get_valley_polygons(),
		{"min_cells": 12, "water_depth": 10.0}
	)

	var lake_count: int = water_root.get_child_count()
	if lake_count < 3:
		print("TEST_WATER_FAIL: expected at least 3 lakes count=%d" % lake_count)
		quit(1)
		return

	if lake_count > 3:
		print("TEST_WATER_FAIL: expected exactly 3 lakes on XL count=%d" % lake_count)
		quit(1)
		return

	if lake_count != basins.size():
		print("TEST_WATER_FAIL: lake meshes=%d basins=%d" % [lake_count, basins.size()])
		quit(1)
		return

	for i in range(lake_count):
		var lake := water_root.get_child(i)
		if not lake is MeshInstance3D:
			print("TEST_WATER_FAIL: child %d is not MeshInstance3D" % i)
			quit(1)
			return
		var mi: MeshInstance3D = lake
		if mi.mesh == null:
			print("TEST_WATER_FAIL: lake %d has no mesh" % i)
			quit(1)
			return
		if not mi.mesh is ArrayMesh:
			print("TEST_WATER_FAIL: lake %d mesh is not ArrayMesh" % i)
			quit(1)
			return
		var mat := mi.material_override
		if mat == null or not mat is StandardMaterial3D:
			print("TEST_WATER_FAIL: lake %d missing StandardMaterial3D" % i)
			quit(1)
			return
		var std: StandardMaterial3D = mat
		if std.albedo_texture == null:
			print("TEST_WATER_FAIL: lake %d missing albedo texture" % i)
			quit(1)
			return

		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			print("TEST_WATER_FAIL: lake %d has no vertices" % i)
			quit(1)
			return
		var expected_y: float = vertices[0].y
		for v in vertices:
			if absf(v.y - expected_y) > 0.01:
				print("TEST_WATER_FAIL: lake %d non-flat surface y=%.3f expected=%.3f" % [i, v.y, expected_y])
				quit(1)
				return

		var footprint: float = _WaterBuilder.mesh_footprint_area(mi.mesh)
		var basin: Dictionary = basins[i]
		var aabb_area: float = (basin.max_x - basin.min_x) * (basin.max_z - basin.min_z)
		if footprint >= aabb_area * 0.85:
			print(
				"TEST_WATER_FAIL: lake %d footprint %.1f not tighter than AABB %.1f"
				% [i, footprint, aabb_area]
			)
			quit(1)
			return

	print("TEST_WATER_OK: lakes=%d" % lake_count)
	quit(0)
