extends SceneTree
## Headless XL: peak height probe + far-corner ground raycast must succeed.

const _MapConfigScript = preload("res://MapConfig.gd")
const PEAK_X := 1100.0
const PEAK_Z := 950.0
const PEAK_EXPECTED := 560.0
const PEAK_TOLERANCE := 1.0

func _init():
	call_deferred("_begin")

func _begin():
	var map_cfg: Node = _MapConfigScript.new()
	root.add_child(map_cfg)
	root.get_viewport().size = Vector2i(1280, 720)
	var w = load("res://World.tscn").instantiate()
	root.add_child(w)
	await process_frame
	await process_frame
	for _i in range(10):
		await physics_frame

	if map_cfg.map_size != "XL":
		print("TEST_XL_MAP_BOUNDS_SKIP: map=%s (run with --map=XL)" % map_cfg.map_size)
		quit(0)
		return

	if w._camera == null:
		w._setup_camera()

	var peak_h: float = w.get_ground_height_at(PEAK_X, PEAK_Z)
	if absf(peak_h - PEAK_EXPECTED) > PEAK_TOLERANCE:
		print(
			"TEST_XL_MAP_BOUNDS_FAIL: peak at (%.0f,%.0f) height=%.1f expected=%.1f"
			% [PEAK_X, PEAK_Z, peak_h, PEAK_EXPECTED]
		)
		quit(1)
		return

	# Camera-like ray from NW overview toward SE map corner (long ray, tests grid march).
	var from := Vector3(600.0, 1200.0, 600.0)
	var corner := Vector3(map_cfg.width, 0.0, map_cfg.height)
	var dir: Vector3 = (corner - from).normalized()
	var ray_len: float = float(w._ground_ray_length())
	var to: Vector3 = from + dir * ray_len
	var hit: Vector3 = w._raycast_terrain_grid_along_ray(from, to)
	if hit == Vector3.ZERO:
		print("TEST_XL_MAP_BOUNDS_FAIL: far-corner raycast returned ZERO")
		quit(1)
		return

	var max_dist: float = w._camera_max_distance()
	var far_plane: float = w._camera_far()
	if max_dist < 1200.0:
		print("TEST_XL_MAP_BOUNDS_FAIL: camera max distance too small (%.1f)" % max_dist)
		quit(1)
		return
	if far_plane < 8000.0:
		print("TEST_XL_MAP_BOUNDS_FAIL: camera far plane too small (%.1f)" % far_plane)
		quit(1)
		return

	# Terrain-following camera at Mountain A peak (zoomed in).
	w._look_at_xz = Vector2(PEAK_X, PEAK_Z)
	w._camera_distance = w.CAMERA_MIN_DISTANCE
	w._camera_smoothing_initialized = false
	w._update_camera_position(0.0)
	var pivot_y: float = w._camera_pivot.global_position.y
	var expected_focus: float = peak_h + w.CAMERA_EYE_HEIGHT_MIN
	if absf(pivot_y - expected_focus) > 2.0:
		print(
			"TEST_XL_MAP_BOUNDS_FAIL: pivot_y=%.1f expected=%.1f (terrain-relative focus)"
			% [pivot_y, expected_focus]
		)
		quit(1)
		return
	var cam: Vector3 = Vector3(w._camera.global_position)
	var ground_cam: float = w.get_ground_height_at(cam.x, cam.z)
	if cam.y < ground_cam + w.CAMERA_CLEARANCE_MIN - 1.0:
		print(
			"TEST_XL_MAP_BOUNDS_FAIL: camera below terrain clearance y=%.1f min=%.1f"
			% [cam.y, ground_cam + w.CAMERA_CLEARANCE_MIN]
		)
		quit(1)
		return

	# Zoomed out: camera should sit higher above local terrain.
	var cam_in_y: float = cam.y
	w._camera_distance = w._camera_max_distance()
	w._camera_smoothing_initialized = false
	w._update_camera_position(0.0)
	var cam_out: Vector3 = Vector3(w._camera.global_position)
	if cam_out.y <= cam_in_y:
		print(
			"TEST_XL_MAP_BOUNDS_FAIL: zoomed-out camera y=%.1f not above zoomed-in y=%.1f"
			% [cam_out.y, cam_in_y]
		)
		quit(1)
		return

	# Slope-aware look: Village on north-facing uphill (ground rises toward north).
	const SLOPE_X := 960.0
	const SLOPE_Z := 1080.0
	w._look_at_xz = Vector2(SLOPE_X, SLOPE_Z)
	w._camera_distance = w.CAMERA_MIN_DISTANCE
	w._camera_smoothing_initialized = false
	w._update_camera_position(0.0)
	var focus_ground: float = w.get_ground_height_at(SLOPE_X, SLOPE_Z)
	var ahead_xz: Vector2 = w._camera_look_ahead_xz()
	var ahead_ground: float = w.get_ground_height_at(ahead_xz.x, ahead_xz.y)
	if ahead_ground <= focus_ground + 1.0:
		print(
			"TEST_XL_MAP_BOUNDS_FAIL: expected uphill north focus=%.1f ahead=%.1f"
			% [focus_ground, ahead_ground]
		)
		quit(1)
		return
	var focus_pt: Vector3 = Vector3(w._camera_pivot.global_position)
	var cam_pos2: Vector3 = Vector3(w._camera.global_position)
	var forward: Vector3 = -w._camera.global_transform.basis.z
	if forward.y <= 0.0:
		print(
			"TEST_XL_MAP_BOUNDS_FAIL: camera not looking uphill forward_y=%.3f focus_y=%.1f"
			% [forward.y, focus_pt.y]
		)
		quit(1)
		return
	var ahead_look_y: float = ahead_ground + w.CAMERA_EYE_HEIGHT_MIN
	if ahead_look_y <= focus_pt.y:
		print(
			"TEST_XL_MAP_BOUNDS_FAIL: look-ahead target y=%.1f not above focus y=%.1f"
			% [ahead_look_y, focus_pt.y]
		)
		quit(1)
		return

	# Angled ground pick: click on Mountain A peak should resolve near peak XZ.
	w._look_at_xz = Vector2(PEAK_X, PEAK_Z)
	w._camera_distance = w.CAMERA_MIN_DISTANCE
	w._camera_smoothing_initialized = false
	w._update_camera_position(0.0)
	var peak_world: Vector3 = Vector3(PEAK_X, peak_h, PEAK_Z)
	var screen_peak: Vector2 = w._camera.unproject_position(peak_world)
	var pick: Vector3 = w._raycast_ground_at_screen(screen_peak)
	if pick == Vector3.ZERO:
		print("TEST_XL_MAP_BOUNDS_FAIL: peak ground pick returned ZERO screen=%s cam=%s" % [screen_peak, w._camera.global_position])
		quit(1)
		return
	var pick_xz := Vector2(pick.x, pick.z)
	var peak_xz := Vector2(PEAK_X, PEAK_Z)
	if pick_xz.distance_to(peak_xz) > 30.0:
		print(
			"TEST_XL_MAP_BOUNDS_FAIL: peak pick offset=%.1f at (%.0f,%.0f) expected (%.0f,%.0f)"
			% [pick_xz.distance_to(peak_xz), pick.x, pick.z, PEAK_X, PEAK_Z]
		)
		quit(1)
		return

	# North approach slope: angled pick must stay on near side, not jump to backslope (south of peak).
	const SLOPE_CLICK_X := 1100.0
	const SLOPE_CLICK_Z := 1010.0
	w._look_at_xz = Vector2(SLOPE_CLICK_X, SLOPE_CLICK_Z)
	w._camera_smoothing_initialized = false
	w._update_camera_position(0.0)
	var slope_h: float = w.get_ground_height_at(SLOPE_CLICK_X, SLOPE_CLICK_Z)
	var slope_world := Vector3(SLOPE_CLICK_X, slope_h, SLOPE_CLICK_Z)
	var screen_slope: Vector2 = w._camera.unproject_position(slope_world)
	var slope_pick: Vector3 = w._raycast_ground_at_screen(screen_slope)
	if slope_pick == Vector3.ZERO:
		print("TEST_XL_MAP_BOUNDS_FAIL: north slope pick returned ZERO")
		quit(1)
		return
	var slope_pick_xz := Vector2(slope_pick.x, slope_pick.z)
	var slope_click_xz := Vector2(SLOPE_CLICK_X, SLOPE_CLICK_Z)
	if slope_pick_xz.distance_to(slope_click_xz) > 40.0:
		print(
			"TEST_XL_MAP_BOUNDS_FAIL: north slope pick offset=%.1f at (%.0f,%.0f) expected (%.0f,%.0f)"
			% [slope_pick_xz.distance_to(slope_click_xz), slope_pick.x, slope_pick.z, SLOPE_CLICK_X, SLOPE_CLICK_Z]
		)
		quit(1)
		return
	if slope_pick.z < PEAK_Z - 20.0:
		print(
			"TEST_XL_MAP_BOUNDS_FAIL: north slope pick on backslope z=%.0f (peak z=%.0f)"
			% [slope_pick.z, PEAK_Z]
		)
		quit(1)
		return

	print(
		"TEST_XL_MAP_BOUNDS_OK: peak=%.1f hit=(%.0f,%.0f,%.0f) max_zoom=%.0f far=%.0f"
		% [peak_h, hit.x, hit.y, hit.z, max_dist, far_plane]
	)
	quit(0)
