extends SceneTree
## Headless XL: free_view_camera turns, tilts and moves relative to the view direction,
## stays inside the map and above the terrain, and the default camera still faces north.

const _MapConfigScript = preload("res://MapConfig.gd")
const DIR_TOLERANCE := 0.05
const FRAMES := 60
const DT := 1.0 / 60.0

var _fails: Array = []

func _init():
	call_deferred("_begin")

func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails.append(msg)

func _view_dir_xz(w: Node3D) -> Vector2:
	var f: Vector3 = -w._camera.global_transform.basis.z
	return Vector2(f.x, f.z).normalized()

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
	if w._camera == null:
		w._setup_camera()

	var center := Vector2(map_cfg.width * 0.5, map_cfg.height * 0.5)
	w._look_at_xz = center
	w._camera_distance = 500.0
	w._camera_smoothing_initialized = false
	w._update_camera_position(0.0)
	var dir: Vector2 = _view_dir_xz(w)
	_check(dir.distance_to(Vector2(0, -1)) < DIR_TOLERANCE, "default camera does not face north: %s" % dir)

	w.set_free_view_camera(true, false)
	w._look_at_xz = center
	w.rotate_free_view(PI / 2.0)
	w._update_camera_position(0.0)
	dir = _view_dir_xz(w)
	_check(dir.distance_to(Vector2(-1, 0)) < DIR_TOLERANCE, "yaw 90 should face west, got %s" % dir)
	_check(w.camera_forward_xz().distance_to(Vector2(-1, 0)) < DIR_TOLERANCE, "forward_xz at yaw 90 = %s" % w.camera_forward_xz())

	var start: Vector2 = w._look_at_xz
	for _i in range(FRAMES):
		w._look_at_xz += w.free_view_pan_vector(1.0, 0.0) * DT
		w._look_at_xz = w._clamp_look_at_xz(w._look_at_xz)
		w._update_camera_position(DT)
	var moved: Vector2 = w._look_at_xz - start
	_check(moved.x < -50.0 and absf(moved.y) < 1.0, "W at yaw 90 should move west, moved %s" % moved)

	start = w._look_at_xz
	for _i in range(FRAMES):
		w._look_at_xz += w.free_view_pan_vector(0.0, 1.0) * DT
		w._look_at_xz = w._clamp_look_at_xz(w._look_at_xz)
		w._update_camera_position(DT)
	moved = w._look_at_xz - start
	_check(moved.y < -50.0 and absf(moved.x) < 1.0, "D at yaw 90 should strafe north, moved %s" % moved)

	w._update_camera_position(0.0)
	var vp: Vector2 = root.get_viewport().get_visible_rect().size
	var hit: Vector3 = w._raycast_ground_at_screen_with_current_pose(vp * 0.5)
	_check(hit != Vector3.ZERO, "screen centre ray misses the ground")
	if hit != Vector3.ZERO:
		var off := Vector2(hit.x, hit.z).distance_to(w._look_at_xz)
		_check(off < w._camera_distance * 0.5, "screen centre hits %.0f away from the look-at point" % off)

	for _i in range(FRAMES * 20):
		w._look_at_xz += w.free_view_pan_vector(1.0, 0.0) * DT
		w._look_at_xz = w._clamp_look_at_xz(w._look_at_xz)
	_check(w._look_at_xz.x >= 0.0 and w._look_at_xz.x <= map_cfg.width, "look-at left the map: %s" % w._look_at_xz)

	w.rotate_free_view(0.0, 1000.0)
	_check(is_equal_approx(w._free_pitch_deg, w.FREE_VIEW_PITCH_MAX_DEG), "pitch not clamped to max: %.1f" % w._free_pitch_deg)
	w.rotate_free_view(0.0, -1000.0)
	_check(is_equal_approx(w._free_pitch_deg, w.FREE_VIEW_PITCH_MIN_DEG), "pitch not clamped to min: %.1f" % w._free_pitch_deg)
	w._camera_distance = w.CAMERA_MIN_DISTANCE
	for yaw_step in range(8):
		w.rotate_free_view(PI / 4.0)
		w._look_at_xz = center
		w._update_camera_position(0.0)
		var cp: Vector3 = w._camera.global_position
		var ground: float = w.get_ground_height_at(cp.x, cp.z)
		_check(cp.y > ground + 1.0, "camera below terrain at yaw step %d: y=%.1f ground=%.1f" % [yaw_step, cp.y, ground])

	w.set_free_view_camera(true, false)
	w.rotate_free_view(PI)
	w._update_camera_position(0.0)
	var right: Vector3 = w._camera.global_transform.basis.x
	_check(right.x < 0.0, "yaw 180: camera right should point to -X (sprite flip), got %s" % right)

	w.set_free_view_camera(false, false)
	w._update_camera_position(0.0)
	dir = _view_dir_xz(w)
	_check(dir.distance_to(Vector2(0, -1)) < DIR_TOLERANCE, "turning free view off should face north again: %s" % dir)

	if not _fails.is_empty():
		print("TEST_FREE_VIEW_CAMERA_FAIL: %s" % "; ".join(_fails))
		quit(1)
		return
	print("TEST_FREE_VIEW_CAMERA_OK: map=%s" % map_cfg.map_size)
	quit(0)
