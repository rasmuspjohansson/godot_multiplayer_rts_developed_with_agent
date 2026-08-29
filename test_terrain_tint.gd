extends SceneTree
## Headless: terrain vertex tint highlights local peaks and the global summit.

func _init():
	call_deferred("_begin")

func _brightness(c: Color) -> float:
	return c.r + c.g + c.b

func _nearest_vertex_brightness(
	verts: PackedVector3Array,
	colors: PackedColorArray,
	target_x: float,
	target_z: float
) -> float:
	var best_dist_sq := INF
	var best_brightness := 0.0
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		var dist_sq: float = (v.x - target_x) * (v.x - target_x) + (v.z - target_z) * (v.z - target_z)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_brightness = _brightness(colors[i])
	return best_brightness

func _begin():
	var w = load("res://World.tscn").instantiate()
	root.add_child(w)
	await process_frame
	await process_frame
	for _i in range(10):
		await physics_frame

	var ground: Node = w.get_node_or_null("Ground")
	if ground == null or not ground is MeshInstance3D:
		print("TEST_TERRAIN_TINT_FAIL: missing Ground MeshInstance3D")
		quit(1)
		return

	var mesh: Mesh = ground.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		print("TEST_TERRAIN_TINT_FAIL: ground has no mesh surface")
		quit(1)
		return

	var arrays: Array = mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if colors.is_empty() or verts.is_empty():
		print("TEST_TERRAIN_TINT_FAIL: missing vertex colors or vertices")
		quit(1)
		return

	var mat: Material = mesh.surface_get_material(0)
	if mat == null or not mat is StandardMaterial3D:
		print("TEST_TERRAIN_TINT_FAIL: missing StandardMaterial3D")
		quit(1)
		return
	var std: StandardMaterial3D = mat
	if not std.vertex_color_use_as_albedo:
		print("TEST_TERRAIN_TINT_FAIL: vertex_color_use_as_albedo not enabled")
		quit(1)
		return

	var low_y := INF
	var high_y := -INF
	var low_brightness := 0.0
	var summit_brightness := 0.0
	var max_brightness := 0.0
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		var bright: float = _brightness(colors[i])
		max_brightness = maxf(max_brightness, bright)
		if v.y < low_y:
			low_y = v.y
			low_brightness = bright
		if v.y > high_y:
			high_y = v.y
			summit_brightness = bright

	if high_y <= low_y + 1.0:
		print("TEST_TERRAIN_TINT_SKIP: flat terrain")
		quit(0)
		return

	if summit_brightness <= low_brightness:
		print(
			"TEST_TERRAIN_TINT_FAIL: peak brightness %.3f not above valley %.3f"
			% [summit_brightness, low_brightness]
		)
		quit(1)
		return

	if summit_brightness + 0.001 < max_brightness:
		print(
			"TEST_TERRAIN_TINT_FAIL: global summit brightness %.3f below max %.3f"
			% [summit_brightness, max_brightness]
		)
		quit(1)
		return

	var hill_top_brightness: float = 0.0
	var hill_base_brightness: float = INF
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		var bright: float = _brightness(colors[i])
		if v.x >= 600.0 and v.x <= 900.0 and v.z >= 820.0 and v.z <= 980.0:
			hill_top_brightness = maxf(hill_top_brightness, bright)
		if v.x >= 600.0 and v.x <= 900.0 and v.z >= 1180.0 and v.z <= 1400.0:
			hill_base_brightness = minf(hill_base_brightness, bright)
	if hill_base_brightness == INF:
		hill_base_brightness = _nearest_vertex_brightness(verts, colors, 750.0, 1300.0)
	if hill_top_brightness <= hill_base_brightness + 0.05:
		print(
			"TEST_TERRAIN_TINT_FAIL: local hill top %.3f not above base %.3f"
			% [hill_top_brightness, hill_base_brightness]
		)
		quit(1)
		return

	print(
		"TEST_TERRAIN_TINT_OK: y=%.1f-%.1f summit=%.3f hill=%.3f-%.3f"
		% [low_y, high_y, summit_brightness, hill_base_brightness, hill_top_brightness]
	)
	quit(0)
