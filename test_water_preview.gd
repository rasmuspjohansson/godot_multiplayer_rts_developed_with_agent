extends SceneTree
## Visual XL water preview — opens a window; pan/zoom with WASD + mouse wheel.

const _MapConfigScript = preload("res://MapConfig.gd")

func _init():
	call_deferred("_begin")

func _begin():
	var map_cfg: Node = _MapConfigScript.new()
	root.add_child(map_cfg)
	root.get_viewport().size = Vector2i(1280, 720)
	var w: Node3D = load("res://World.tscn").instantiate()
	root.add_child(w)
	await process_frame
	await process_frame
	for _i in range(10):
		await physics_frame

	if map_cfg.map_size != "XL":
		print("WATER_PREVIEW_SKIP: map=%s (use --map=XL)" % map_cfg.map_size)
		quit(0)
		return

	if w._camera == null:
		w._setup_camera()

	var water_root := w.get_node_or_null("Water")
	if water_root == null or water_root.get_child_count() == 0:
		print("WATER_PREVIEW_FAIL: no lakes")
		quit(1)
		return

	var lake: MeshInstance3D = water_root.get_child(0)
	var lake_pos: Vector3 = lake.global_position
	var basin_size := Vector2.ZERO
	if lake.mesh is PlaneMesh:
		basin_size = (lake.mesh as PlaneMesh).size

	w._look_at_xz = Vector2(lake_pos.x, lake_pos.z)
	w._camera_distance = maxf(basin_size.x, basin_size.y) * 0.55
	w._camera_distance = clampf(w._camera_distance, 350.0, 1200.0)
	w._camera_smoothing_initialized = false
	w._update_camera_position(0.0)

	var bed_y: float = w.get_ground_height_at(lake_pos.x, lake_pos.z)
	print(
		"WATER_PREVIEW_OK: lakes=%d lake_y=%.2f bed_y=%.2f depth=%.2f size=(%.0f,%.0f) — close window to exit"
		% [
			water_root.get_child_count(),
			lake_pos.y,
			bed_y,
			lake_pos.y - bed_y,
			basin_size.x,
			basin_size.y,
		]
	)
