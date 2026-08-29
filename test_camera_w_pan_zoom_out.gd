extends SceneTree
## Headless XL: hold W until north map edge reaches viewport (max + mid zoom).

const _MapConfigScript = preload("res://MapConfig.gd")
const NORTH_EDGE_TOLERANCE := 40.0
const MIN_PAN_DELTA := 50.0
const W_HOLD_FRAMES := 600
const LIMIT_FRAMES := 60
const MID_ZOOM_T := 0.3

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
		print("TEST_CAMERA_W_PAN_SKIP: map=%s (run with --map=XL)" % map_cfg.map_size)
		quit(0)
		return

	if w._camera == null:
		w._setup_camera()

	var center := Vector2(map_cfg.width * 0.5, map_cfg.height * 0.5)
	var max_dist: float = w._camera_max_distance()
	var min_dist: float = w.CAMERA_MIN_DISTANCE
	var span: float = max_dist - min_dist

	if not _run_w_pan_case(w, center, max_dist, "TEST_CAMERA_W_PAN"):
		quit(1)
		return

	var mid_dist: float = max_dist - MID_ZOOM_T * span
	if not _run_w_pan_case(w, center, mid_dist, "TEST_CAMERA_W_PAN_MID"):
		quit(1)
		return

	quit(0)

func _run_w_pan_case(w: Node3D, center: Vector2, camera_distance: float, prefix: String) -> bool:
	w._look_at_xz = center
	w._camera_distance = camera_distance
	w._camera_smoothing_initialized = false
	w._update_camera_position(0.0)

	var pan_speed: float = w._camera_pan_speed()
	var delta := 1.0 / 60.0
	var start_z: float = w._look_at_xz.y

	for _i in range(W_HOLD_FRAMES):
		w._look_at_xz.y -= pan_speed * delta
		w._look_at_xz = w._clamp_look_at_xz(w._look_at_xz)
		w._update_camera_position(delta)

	var moved: float = start_z - w._look_at_xz.y
	if moved < MIN_PAN_DELTA:
		print(
			"%s_FAIL: W pan moved only %.1f from center z=%.1f to z=%.1f dist=%.1f"
			% [prefix, moved, start_z, w._look_at_xz.y, camera_distance]
		)
		return false

	w._update_camera_position(0.0)
	var bounds: Vector4 = w._visible_ground_xz_bounds(w._look_at_xz)
	if bounds == Vector4.ZERO:
		print(
			"%s_FAIL: no visible ground samples after W pan pivot_z=%.1f dist=%.1f"
			% [prefix, w._look_at_xz.y, camera_distance]
		)
		return false

	var visible_min_z: float = bounds.z
	if visible_min_z > NORTH_EDGE_TOLERANCE:
		print(
			"%s_FAIL: north edge not reached visible_min_z=%.1f (limit=%.1f) pivot_z=%.1f dist=%.1f"
			% [prefix, visible_min_z, NORTH_EDGE_TOLERANCE, w._look_at_xz.y, camera_distance]
		)
		return false

	var at_limit_z: float = w._look_at_xz.y
	for _j in range(LIMIT_FRAMES):
		w._look_at_xz.y -= pan_speed * delta
		w._look_at_xz = w._clamp_look_at_xz(w._look_at_xz)
		w._update_camera_position(delta)

	if absf(w._look_at_xz.y - at_limit_z) > 1.0:
		print(
			"%s_FAIL: still moving after limit z=%.1f -> %.1f dist=%.1f"
			% [prefix, at_limit_z, w._look_at_xz.y, camera_distance]
		)
		return false

	print(
		"%s_OK: moved=%.1f pivot_z=%.1f visible_min_z=%.1f dist=%.1f zoom_t=%.2f"
		% [prefix, moved, w._look_at_xz.y, visible_min_z, camera_distance, w._camera_zoom_t()]
	)
	return true
