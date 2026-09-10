extends Node3D
## Single world: server authority + 3D client; map size from MapConfig (S/L/XL).

const _Army3D = preload("res://Army3D.gd")
const _GroupFormation = preload("res://GroupFormation.gd")
const _MarqueeRectOverlay = preload("res://MarqueeRectOverlay.gd")
const _ArmyCommandBar = preload("res://ArmyCommandBar.gd")
const UNIT_SPRITE_PATHS = preload("res://UnitSpritePaths.gd")
## Data-oriented simulation core (see documentation.md "Architecture").
const _UnitSim = preload("res://sim/UnitSim.gd")
const _Formation = preload("res://sim/FormationController.gd")
const _NetSync = preload("res://sim/NetSync.gd")
const _UnitRenderer = preload("res://sim/UnitRenderer.gd")
const _UnitAudio = preload("res://sim/UnitAudio.gd")

## Army size is a per-army parameter: map JSON `soldiers`, draft UI spin box, stress flag.
const DEFAULT_SOLDIERS_PER_ARMY := 10
const MIN_SOLDIERS_PER_ARMY := 10
const MAX_SOLDIERS_PER_ARMY := 200
const STRESS_SOLDIERS_PER_ARMY := 50
## Default armies per player when map JSON is unavailable (see MapConfig.max_armies_per_player()).
const ARMIES_PER_PLAYER_FALLBACK := 2
const OFFMAP_SPAWN_MARGIN := 120.0
## Map width/height come from `MapConfig` (maps/map_{S|L|XL}.json). Access via
## `MapConfig.width` / `MapConfig.height` elsewhere in this file.
const DRAFT_COST_PER_EQUIPMENT := 10
const MAX_ARROWS_PER_TICK := 40
const MAX_GHOST_MARKERS := 400

var _sim = null            # UnitSim
var _net = null            # NetSync
var _unit_renderer = null  # UnitRenderer (clients only)
var _unit_audio = null     # UnitAudio (clients only)
var _sim_accum := 0.0
var _order_seq := 0
var _next_unit_id := 0
var _snapshot_bytes_sent := 0
var _army_by_id: Dictionary = {}
var _click_marker: MeshInstance3D = null
var _click_marker_t := 0.0
## Headless tests without a multiplayer peer set this so the local sim still steps.
var _local_sim_enabled := false
## Off-map spawn/stop lanes for the legacy draft-army path. Recomputed from
## MapConfig in `_init_offmap_lanes()` so they scale with map size.
var WEST_SPAWN: Vector2 = Vector2.ZERO
var EAST_SPAWN: Vector2 = Vector2.ZERO
var WEST_STOP_X: float = 80.0
var EAST_STOP_X: float = 0.0
var NORTH_SPAWN: Vector2 = Vector2.ZERO
var SOUTH_SPAWN: Vector2 = Vector2.ZERO
var NORTH_STOP_Y: float = 80.0
var SOUTH_STOP_Y: float = 0.0
const CP_CAPTURE_RADIUS := 120.0
const CP_RESOURCE_INTERVAL := 6.0
# Terrain height sampling: unit origin y = ground_height + UNIT_HALF_HEIGHT (box is 22 tall)
const UNIT_HALF_HEIGHT := 11.0
## Zoomed out: bird's-eye; zoomed in: pitch approaches horizontal + look-at near soldier head height.
const CAMERA_PITCH_MAX_DEG := 45.0
const CAMERA_PITCH_MIN_DEG := 8.0
const CAMERA_EYE_HEIGHT_MIN := UNIT_HALF_HEIGHT + 4.0
const CAMERA_EYE_HEIGHT_MAX := 0.0
const CAMERA_CLEARANCE_MIN := 18.0
const CAMERA_CLEARANCE_MAX := 100.0
const CAMERA_GROUND_SMOOTH_SPEED := 800.0
const CAMERA_PITCH_SMOOTH_SPEED := 900.0
const CAMERA_SLOPE_LOOK_AHEAD := 50.0
const CAMERA_PAN_EDGE_PADDING := 30.0
const CAMERA_MIN_DISTANCE := 200.0 / 3.0
const CAMERA_MAX_DISTANCE := 1200.0
const CAMERA_PAN_SPEED := 400.0
const CAMERA_ZOOM_SPEED := 80.0
const ARMY_CLICK_RADIUS := 80.0
const MOVE_GOAL_MARKER_HIDE_DIST := 1.0
const BG_MUSIC_PATH := "res://sound/Glade_of_Sun_and_Water.mp3"
const GROUND_TEXTURE_PATH := "res://images/background/ground_grass.png"
const STEEP_HILLS_TEXTURE_PATH := "res://images/background/steep_hills.png"
const GROUND_WALKABLE_SHADER := preload("res://shaders/ground_walkable.gdshader")
const WalkabilityGrid = preload("res://WalkabilityGrid.gd")
const _VegetationBuilder = preload("res://VegetationBuilder.gd")
const _ArrowProjectile = preload("res://ArrowProjectile.gd")
const LAKES_WATER_TEXTURE_PATH := "res://images/background/lakes_water.png"
const _WaterBuilder = preload("res://WaterBuilder.gd")
const CP_STABLES_TEXTURE_PATH := "res://images/background/stable.png"
const CP_BLACKSMITH_TEXTURE_PATH := "res://images/background/blacksmith2.png"
const CP_VILLAGE_TEXTURE_PATH := "res://images/capture_points/village/village.png"
const CP_ARCHERY_TEXTURE_PATH := "res://images/capture_points/archery/archery.png"
const CP_RESOURCE_BY_TYPE := {
	"Stables": "horses",
	"Blacksmith": "spears",
	"Village": "villagers",
	"Archery": "bows",
}
## Capture point billboard height in world units.
const CP_SPRITE_WORLD_HEIGHT := 80.0
## Capture points per _client_update_capture RPC tick (XL has 11 CPs).
const CAPTURE_SYNC_BATCH_SIZE := 6

var sync_timer := 0.0
var _last_sent_cp_owner: Dictionary = {}
var _last_sent_resources: Dictionary = {}
var _capture_hud_sent := false
var player_side := {}  # pid -> "west" | "east" | ... (legacy draft path)
var player_slot := {}  # pid -> int (index into MapConfig.start_positions)
var army_index_per_player := {}
## Server-only capture sim: { id, type, x, y, owner_pid, resource_timer }
var _server_captures: Array = []

var _camera: Camera3D
var _camera_pivot: Node3D
var _camera_distance: float = 500.0
var _look_at_xz: Vector2 = Vector2.ZERO
var _smoothed_ground_y: float = 0.0
var _smoothed_ahead_ground_y: float = 0.0
var _smoothed_pitch_deg: float = CAMERA_PITCH_MAX_DEG
var _camera_smoothing_initialized: bool = false
var _pan_bounds_cache_pivot: Vector2 = Vector2(INF, INF)
var _pan_bounds_cache_dist: float = -1.0
var _pan_bounds_cache_result: Vector4 = Vector4.ZERO
var _pan_drag := false
var _last_mouse: Vector2

var armies: Array = []
var _map_dragons: Array = []
var _dragon_ai_timer: float = 0.0
const DRAGON_AI_TICK := 0.5
var capture_points: Array = []
var top_bar = null
var draft_menu = null
var _army_command_bar: Control = null
var game_over := false
var selected_armies: Array = []
var _marquee_start_screen: Vector2 = Vector2.ZERO
var _marquee_end_screen: Vector2 = Vector2.ZERO
var _marquee_active: bool = false
var _marquee_moved: bool = false
var _marquee_overlay: Control
var _rmb_press_screen: Vector2 = Vector2.ZERO
var _rmb_press_ground: Vector2 = Vector2.ZERO
var _rmb_drag_active: bool = false
var _ghost_root_3d: Node3D
var _ghost_marker_mat: StandardMaterial3D
var _ghost_marker_invalid_mat: StandardMaterial3D
var _move_goal_markers_3d: Node3D
var _move_goal_slot_mat: StandardMaterial3D
var _move_goal_ring_mesh: ArrayMesh
var _pending_client_orders: Array = []
var _move_osc_logged := false
var _show_unit_range: bool = false
var _show_range_cb: CheckBox = null
var _draft_size_spin: SpinBox = null
var _range_markers_3d: Node3D
var _sun_azimuth_deg: float = 275.0
var _sun_elevation_deg: float = 0.0
var _sun_energy: float = 0.12
var _sun_light_color: Color = Color(1.0, 0.98, 0.95)
var _lighting_azimuth_value_label: Label = null
var _lighting_elevation_value_label: Label = null
var _lighting_energy_value_label: Label = null
var _lighting_summary_label: Label = null
var _anim_speed_value_label: Label = null
const MARQUEE_DRAG_THRESHOLD := 6.0
const RMB_DRAG_CLICK_THRESHOLD := 14.0
## Terrain height grid built in `_build_terrain()`; used as fallback when physics raycast misses.
var _terrain_heights: PackedFloat32Array = PackedFloat32Array()
var _terrain_cols: int = 0
var _terrain_rows: int = 0
var _terrain_step: float = _TERRAIN_STEP
var _max_terrain_height: float = 0.0
var _water_basins: Array = []
var _walkability: WalkabilityGrid = null
## When true, World is a map-editor preview: terrain only, local camera, no match/UI/RPCs.
var preview_only := false

func _map_diagonal() -> float:
	return sqrt(MapConfig.width * MapConfig.width + MapConfig.height * MapConfig.height)

func _camera_max_distance() -> float:
	return maxf(CAMERA_MAX_DISTANCE, _map_diagonal() * 0.45)

func _camera_far() -> float:
	return maxf(8000.0, _map_diagonal() + _max_terrain_height + _camera_max_distance() * 2.0)

func _camera_pan_speed() -> float:
	return CAMERA_PAN_SPEED * (MapConfig.width / 1280.0)

func _ground_ray_length() -> float:
	return _map_diagonal() + _max_terrain_height + 2000.0

func _recompute_max_terrain_height() -> void:
	_max_terrain_height = 0.0
	for h in _terrain_heights:
		if h > _max_terrain_height:
			_max_terrain_height = h

func _sun_orbit_position(
	azimuth_deg: float,
	elevation_deg: float,
	center: Vector3,
	radius: float
) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	var cos_el := cos(el)
	return center + Vector3(
		sin(az) * cos_el * radius,
		sin(el) * radius,
		-cos(az) * cos_el * radius
	)

func _lighting_shadow_max_distance(lighting: Dictionary) -> float:
	var configured: float = float(lighting.get("shadow_max_distance", -1.0))
	if configured >= 0.0:
		return configured
	return maxf(800.0, _map_diagonal() * 0.35 + _max_terrain_height * 1.5)

func _configure_map_lighting() -> void:
	var cfg := MapConfig.get_lighting()
	_sun_azimuth_deg = cfg.sun_azimuth_deg
	_sun_elevation_deg = cfg.sun_elevation_deg
	_sun_energy = cfg.energy
	var color_arr: Array = cfg.color
	_sun_light_color = Color(
		float(color_arr[0]),
		float(color_arr[1]),
		float(color_arr[2])
	)
	_apply_sun_lighting()
	var shadow_dist := _lighting_shadow_max_distance(cfg)
	print(
		"TEST_LIGHTING_OK: az=%.1f el=%.1f energy=%.2f shadow=%.1f max_h=%.1f"
		% [_sun_azimuth_deg, _sun_elevation_deg, _sun_energy, shadow_dist, _max_terrain_height]
	)

func _apply_sun_lighting() -> void:
	var light := get_node_or_null("DirectionalLight3D")
	if light == null:
		return
	var cfg := MapConfig.get_lighting()
	var center := Vector3(
		MapConfig.width * 0.5,
		_max_terrain_height * 0.5,
		MapConfig.height * 0.5
	)
	var orbit_radius := maxf(
		_map_diagonal() * 0.35,
		_max_terrain_height * 2.5 + 300.0
	)
	light.global_position = _sun_orbit_position(
		_sun_azimuth_deg, _sun_elevation_deg, center, orbit_radius
	)
	light.look_at(center, Vector3.UP)
	light.light_color = _sun_light_color
	light.light_energy = _sun_energy
	light.directional_shadow_max_distance = _lighting_shadow_max_distance(cfg)
	_update_lighting_tuning_display()

func _update_lighting_tuning_display() -> void:
	if _lighting_azimuth_value_label != null:
		_lighting_azimuth_value_label.text = "%.0f" % _sun_azimuth_deg
	if _lighting_elevation_value_label != null:
		_lighting_elevation_value_label.text = "%.0f" % _sun_elevation_deg
	if _lighting_energy_value_label != null:
		_lighting_energy_value_label.text = "%.2f" % _sun_energy
	if _anim_speed_value_label != null and _unit_renderer != null:
		_anim_speed_value_label.text = "%.2f" % _unit_renderer.anim_speed()
	if _lighting_summary_label != null:
		_lighting_summary_label.text = (
			'"sun_azimuth_deg": %.1f, "sun_elevation_deg": %.1f, "energy": %.2f'
			% [_sun_azimuth_deg, _sun_elevation_deg, _sun_energy]
		)

func _on_lighting_azimuth_changed(value: float) -> void:
	_sun_azimuth_deg = value
	_apply_sun_lighting()

func _on_lighting_elevation_changed(value: float) -> void:
	_sun_elevation_deg = value
	_apply_sun_lighting()

func _on_lighting_energy_changed(value: float) -> void:
	_sun_energy = value
	_apply_sun_lighting()

func _on_anim_speed_changed(value: float) -> void:
	if _unit_renderer != null:
		_unit_renderer.set_anim_speed(value)
	if _anim_speed_value_label != null:
		_anim_speed_value_label.text = "%.2f" % value

func _setup_lighting_tuning_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LightingTuningLayer"
	layer.layer = 50
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -300.0
	panel.offset_top = 40.0
	panel.offset_right = -10.0
	panel.offset_bottom = 310.0
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Sun lighting"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	_add_lighting_slider_row(vbox, "Azimuth", 0.0, 360.0, 1.0, _sun_azimuth_deg, _on_lighting_azimuth_changed, "azimuth")
	_add_lighting_slider_row(vbox, "Elevation", 0.0, 90.0, 1.0, _sun_elevation_deg, _on_lighting_elevation_changed, "elevation")
	_add_lighting_slider_row(vbox, "Energy", 0.0, 2.0, 0.01, _sun_energy, _on_lighting_energy_changed, "energy")
	if not multiplayer.is_server():
		var anim_title := Label.new()
		anim_title.text = "Sprite anim"
		anim_title.add_theme_font_size_override("font_size", 14)
		vbox.add_child(anim_title)
		var initial_speed := _UnitRenderer.ANIM_SPEED_DEFAULT
		if _unit_renderer != null:
			initial_speed = _unit_renderer.anim_speed()
		_add_lighting_slider_row(
			vbox,
			"Speed",
			_UnitRenderer.ANIM_SPEED_MIN,
			_UnitRenderer.ANIM_SPEED_MAX,
			0.05,
			initial_speed,
			_on_anim_speed_changed,
			"anim_speed"
		)

	var hint := Label.new()
	hint.text = "Copy for map JSON:"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(hint)

	_lighting_summary_label = Label.new()
	_lighting_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lighting_summary_label.add_theme_font_size_override("font_size", 11)
	_lighting_summary_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.7))
	vbox.add_child(_lighting_summary_label)
	_update_lighting_tuning_display()

func _add_lighting_slider_row(
	parent: Control,
	label_text: String,
	min_v: float,
	max_v: float,
	step: float,
	initial: float,
	changed_cb: Callable,
	value_key: String
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(70.0, 0.0)
	name_label.add_theme_font_size_override("font_size", 12)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = initial
	slider.value_changed.connect(changed_cb)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(44.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 12)
	if value_key == "energy" or value_key == "anim_speed":
		value_label.text = "%.2f" % initial
	else:
		value_label.text = "%.0f" % initial
	match value_key:
		"azimuth":
			_lighting_azimuth_value_label = value_label
		"elevation":
			_lighting_elevation_value_label = value_label
		"energy":
			_lighting_energy_value_label = value_label
		"anim_speed":
			_anim_speed_value_label = value_label
	row.add_child(value_label)

## Client-only: log TEST_ALL_UNITS_* markers for automated detection (both teams visible, overview frustum).
## Units are GPU instances now, so "scene visible" means the renderer group for the unit is visible
## and the unit is alive; the frustum check uses sim positions.
func _log_unit_visibility(phase: String) -> void:
	if multiplayer.is_server() or _camera == null or _sim == null:
		return
	var pname: String = GameState.local_player_name
	var total := 0
	var vis := 0
	var renderer_visible: bool = _unit_renderer != null and _unit_renderer.is_visible_in_tree()
	for i in range(_sim.count):
		if not _sim.is_alive(i):
			continue
		total += 1
		if renderer_visible:
			vis += 1
	if total == 0:
		print("TEST_ALL_UNITS_SCENE_VISIBLE_FAIL: client=%s phase=%s visible=0 total=0" % [pname, phase])
	elif vis == total:
		print("TEST_ALL_UNITS_SCENE_VISIBLE: client=%s phase=%s visible=%d total=%d" % [pname, phase, vis, total])
	else:
		print("TEST_ALL_UNITS_SCENE_VISIBLE_FAIL: client=%s phase=%s visible=%d total=%d" % [pname, phase, vis, total])
	var saved_look := _look_at_xz
	var saved_dist := _camera_distance
	_look_at_xz = Vector2(MapConfig.width / 2.0, MapConfig.height / 2.0)
	_camera_distance = _camera_max_distance()
	_camera_smoothing_initialized = false
	_update_camera_position(0.0)
	var in_frustum := 0
	for i in range(_sim.count):
		if not _sim.is_alive(i):
			continue
		var x: float = _sim.pos_x[i]
		var z: float = _sim.pos_z[i]
		if _camera.is_position_in_frustum(Vector3(x, get_ground_height_at(x, z) + UNIT_HALF_HEIGHT, z)):
			in_frustum += 1
	if total > 0 and in_frustum == total:
		print("TEST_ALL_UNITS_IN_FRUSTUM: client=%s phase=%s ok=true visible=%d total=%d" % [pname, phase, in_frustum, total])
	else:
		print("TEST_ALL_UNITS_IN_FRUSTUM_FAIL: client=%s phase=%s in_frustum=%d total_alive=%d" % [pname, phase, in_frustum, total])
	_look_at_xz = saved_look
	_camera_distance = saved_dist
	_camera_smoothing_initialized = false
	_update_camera_position(0.0)

func _schedule_visibility_checks() -> void:
	if multiplayer.is_server():
		return
	get_tree().create_timer(0.2).timeout.connect(_on_visibility_spawn_timeout)
	get_tree().create_timer(25.0).timeout.connect(_on_visibility_mid_timeout)

func _on_visibility_spawn_timeout() -> void:
	_log_unit_visibility("spawn")

func _on_visibility_mid_timeout() -> void:
	if game_over:
		return
	_log_unit_visibility("mid_match")

func _ready():
	_init_offmap_lanes()
	_look_at_xz = Vector2(MapConfig.width / 2.0, MapConfig.height / 2.0)
	var ground_collision = get_node_or_null("GroundCollision")
	if ground_collision is StaticBody3D:
		ground_collision.collision_layer = 2
		ground_collision.collision_mask = 0
	_build_terrain()
	add_water()
	_build_walkability()
	_build_vegetation()
	_build_background()
	if preview_only:
		_setup_camera()
		_add_play_boundary_line()
		return
	_setup_sim()
	# Match setup only when real lobby has registered players (skip standalone tests with empty GameState).
	if multiplayer.is_server() and GameState.players.size() >= 2:
		GameState.reset_match_state()
		_set_player_sides()
		_spawn_armies()
		_spawn_capture_points()
	if not multiplayer.is_server():
		_setup_camera()
		_setup_selection_overlay()
		_setup_background_music()
	_setup_topbar()
	_setup_draft_menu()
	_setup_lighting_tuning_panel()
	if not multiplayer.is_server():
		_setup_army_command_bar()
	_add_play_boundary_line()
	_setup_perf_monitor()
	call_deferred("_agent_debug_log_world_ready")
	if not multiplayer.is_server():
		call_deferred("_notify_client_world_ready")

var _perf_monitor: Node = null

func _setup_perf_monitor() -> void:
	if not _multiplayer_active():
		return
	_perf_monitor = preload("res://PerfMonitor.gd").new()
	_perf_monitor.name = "PerfMonitor"
	_perf_monitor.set_unit_count_callback(_alive_unit_count)
	_perf_monitor.set_extra_stats_callback(_sim_health_stats)
	add_child(_perf_monitor)

## Anti-regression counters for the two old bugs: hard position snaps (A->B->A teleports) and
## units animated as walking without displacement. Reset after every report.
func _sim_health_stats() -> String:
	if _sim == null:
		return ""
	var s := "snaps=%d walk_in_place=%d" % [_sim.snap_count, _sim.walk_in_place_count]
	if not multiplayer.is_server():
		print("TEST_SIM_CLIENT %s units=%d" % [s, _sim.alive_count])
		if _sim.move_oscillation and not _move_osc_logged:
			_move_osc_logged = true
			print("TEST_MOVE_OSCILLATION_FAIL: unit=%d reversals=%d window=2.0s" % [
				_sim.move_oscillation_id, _sim.move_oscillation_count
			])
	_sim.snap_count = 0
	_sim.walk_in_place_count = 0
	return s

func _alive_unit_count() -> int:
	if _sim == null:
		return 0
	var n := 0
	for i in range(_sim.count):
		if _sim.is_alive(i):
			n += 1
	return n

## Simulation core shared by server and clients. The server is authoritative (damage, deaths,
## routs); clients run the same movement sim from the same order stream and get corrected by
## packed snapshots. Units are ids into the sim arrays; there are no unit nodes anywhere.
func _setup_sim() -> void:
	_sim = _UnitSim.new()
	_sim.setup(_walkability, float(MapConfig.width), float(MapConfig.height), multiplayer.is_server())
	_net = _NetSync.new()
	_net.setup(float(MapConfig.width), float(MapConfig.height))
	if not multiplayer.is_server():
		_unit_renderer = _UnitRenderer.new()
		_unit_renderer.name = "UnitRenderer"
		_unit_renderer.sim = _sim
		_unit_renderer.set_tick_dt(_UnitSim.SIM_DT)
		if not _terrain_heights.is_empty():
			_unit_renderer.set_height_grid(_terrain_heights, _terrain_cols, _terrain_rows, _terrain_step)
		add_child(_unit_renderer)
		_unit_audio = _UnitAudio.new()
		_unit_audio.name = "UnitAudio"
		_unit_audio.sim = _sim
		_unit_audio.ground_height_fn = get_ground_height_at
		add_child(_unit_audio)

## Fixed-step sim driven from _physics_process on both peers.
func _step_sim(delta: float) -> void:
	if _sim == null:
		return
	_sim_accum += delta
	var steps := 0
	while _sim_accum >= _UnitSim.SIM_DT and steps < 4:
		_sim_accum -= _UnitSim.SIM_DT
		var t0 := Time.get_ticks_usec()
		_sim.step(_UnitSim.SIM_DT)
		if _perf_monitor != null:
			_perf_monitor.record_sim_step_ms(float(Time.get_ticks_usec() - t0) / 1000.0)
		_after_sim_tick()
		steps += 1
	if _sim_accum > _UnitSim.SIM_DT * 4.0:
		_sim_accum = 0.0

func _after_sim_tick() -> void:
	if _sim.combat_hits > 0:
		GameState.last_combat_time = Time.get_ticks_msec() / 1000.0
	if multiplayer.is_server():
		_server_after_tick()
	else:
		_client_after_tick()

func _notify_client_world_ready() -> void:
	if multiplayer.is_server():
		return
	rpc_id(1, "_receive_client_world_ready")

@rpc("any_peer", "reliable")
func _receive_client_world_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_clients_world_ready[peer_id] = true
	print("TEST_CLIENT_WORLD_READY: peer %d finished loading World" % peer_id)

func _all_clients_world_ready() -> bool:
	for peer_id in multiplayer.get_peers():
		if not _clients_world_ready.get(peer_id, false):
			return false
	return true

func _init_offmap_lanes() -> void:
	var w: float = MapConfig.width
	var h: float = MapConfig.height
	WEST_SPAWN = Vector2(-120.0, h / 2.0)
	EAST_SPAWN = Vector2(w + 120.0, h / 2.0)
	WEST_STOP_X = 80.0
	EAST_STOP_X = w - 80.0
	NORTH_SPAWN = Vector2(w / 2.0, -100.0)
	SOUTH_SPAWN = Vector2(w / 2.0, h + 100.0)
	NORTH_STOP_Y = 80.0
	SOUTH_STOP_Y = h - 80.0

## Build the ground mesh (visible) and collision (physics) from MapConfig.
## This is the ONLY place `MapConfig.sample_height` is called. Every runtime
## height query goes through `get_ground_height_at()` which raycasts against
## collision layer 2, so later objects placed on top of the ground will
## automatically count without touching any call sites.
const _TERRAIN_STEP := 20.0
const _TERRAIN_FLOOR_H := 5.0
const _TERRAIN_TINT_RADIUS := 4
const _TERRAIN_FLAT_SPAN := 4.0
const _TERRAIN_VALLEY_TINT := Color(0.90, 0.95, 0.86)
const _TERRAIN_PEAK_TINT := Color(1.10, 1.06, 0.92)

func _terrain_height_stats(heights: PackedFloat32Array) -> Dictionary:
	var max_h := 0.0
	var sorted: Array = []
	sorted.resize(heights.size())
	for k in range(heights.size()):
		var hv: float = heights[k]
		max_h = maxf(max_h, hv)
		sorted[k] = hv
	sorted.sort()
	var n: int = sorted.size()
	var p50: float = sorted[mini(n / 2, n - 1)] if n > 0 else 0.0
	var p90: float = sorted[mini(int(n * 0.90), n - 1)] if n > 0 else 0.0
	return {"max_h": max_h, "p50": p50, "p90": p90}

func _terrain_local_height_range(
	heights: PackedFloat32Array,
	cols: int,
	rows: int,
	i: int,
	j: int,
	radius: int
) -> Vector2:
	var local_min := INF
	var local_max := -INF
	for dj in range(-radius, radius + 1):
		for di in range(-radius, radius + 1):
			var ni: int = clampi(i + di, 0, cols - 1)
			var nj: int = clampi(j + dj, 0, rows - 1)
			var hv: float = heights[nj * cols + ni]
			local_min = minf(local_min, hv)
			local_max = maxf(local_max, hv)
	return Vector2(local_min, local_max)

func _terrain_vertex_tint_t(
	y: float,
	heights: PackedFloat32Array,
	cols: int,
	rows: int,
	i: int,
	j: int,
	max_h: float,
	p50: float,
	p90: float
) -> float:
	var local_range: Vector2 = _terrain_local_height_range(
		heights, cols, rows, i, j, _TERRAIN_TINT_RADIUS
	)
	var local_min: float = local_range.x
	var span: float = local_range.y - local_min
	var t_local: float = clampf((y - local_min) / maxf(span, 1.0), 0.0, 1.0)
	var t_global: float = clampf((y - p50) / maxf(p90 - p50, 1.0), 0.0, 1.0)
	var t_absolute: float = 0.0
	if max_h > _TERRAIN_FLOOR_H:
		t_absolute = clampf((y - _TERRAIN_FLOOR_H) / (max_h - _TERRAIN_FLOOR_H), 0.0, 1.0)
	var t: float = t_local
	if span < _TERRAIN_FLAT_SPAN:
		t = maxf(t_global, t_absolute * 0.5)
	else:
		t = maxf(t_local, t_global * 0.25)
	return maxf(t, t_absolute)

func _build_terrain() -> void:
	var w: float = MapConfig.width
	var h: float = MapConfig.height
	var step: float = _TERRAIN_STEP
	var cols: int = int(ceil(w / step)) + 1
	var rows: int = int(ceil(h / step)) + 1
	# Sample heights into a flat row-major buffer (one float per grid point).
	var heights := PackedFloat32Array()
	heights.resize(cols * rows)
	for j in range(rows):
		var z := float(j) * step
		for i in range(cols):
			var x := float(i) * step
			heights[j * cols + i] = MapConfig.sample_height(x, z)
	_terrain_heights = heights
	_terrain_cols = cols
	_terrain_rows = rows
	_terrain_step = step
	if _unit_renderer != null:
		_unit_renderer.set_height_grid(heights, cols, rows, step)
	# Build the visual ArrayMesh.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize(cols * rows)
	norms.resize(cols * rows)
	uvs.resize(cols * rows)
	for j in range(rows):
		for i in range(cols):
			var x := float(i) * step
			var z := float(j) * step
			var y := heights[j * cols + i]
			verts[j * cols + i] = Vector3(x, y, z)
			uvs[j * cols + i] = Vector2(float(i) / float(maxi(cols - 1, 1)), float(j) / float(maxi(rows - 1, 1)))
			# Finite-difference normal (cheap; forward/backward at edges).
			var i0: int = max(i - 1, 0)
			var i1: int = min(i + 1, cols - 1)
			var j0: int = max(j - 1, 0)
			var j1: int = min(j + 1, rows - 1)
			var dhdx: float = (heights[j * cols + i1] - heights[j * cols + i0]) / max(float(i1 - i0) * step, 1.0)
			var dhdz: float = (heights[j1 * cols + i] - heights[j0 * cols + i]) / max(float(j1 - j0) * step, 1.0)
			norms[j * cols + i] = Vector3(-dhdx, 1.0, -dhdz).normalized()
	var height_stats: Dictionary = _terrain_height_stats(heights)
	var max_h: float = height_stats.max_h
	var p50: float = height_stats.p50
	var p90: float = height_stats.p90
	var colors := PackedColorArray()
	colors.resize(cols * rows)
	for j in range(rows):
		for i in range(cols):
			var y: float = heights[j * cols + i]
			var t: float = _terrain_vertex_tint_t(
				y, heights, cols, rows, i, j, max_h, p50, p90
			)
			colors[j * cols + i] = _TERRAIN_VALLEY_TINT.lerp(_TERRAIN_PEAK_TINT, t)
			colors[j * cols + i].a = 1.0
	for j in range(rows - 1):
		for i in range(cols - 1):
			var a: int = j * cols + i
			var b: int = j * cols + (i + 1)
			var c: int = (j + 1) * cols + i
			var d: int = (j + 1) * cols + (i + 1)
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ground := get_node_or_null("Ground")
	if ground is MeshInstance3D:
		# ArrayMesh vertices are in world-space, so drop the translation the
		# placeholder PlaneMesh used.
		ground.transform = Transform3D.IDENTITY
		ground.mesh = array_mesh
		ground.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Clear any stale scene-level override so the mesh's own surface
		# material is used.
		ground.set_surface_override_material(0, null)
	# Build collision from the same mesh surface as the visual ground.
	var terrain_shape: Shape3D = array_mesh.create_trimesh_shape()
	var gc := get_node_or_null("GroundCollision")
	if gc is StaticBody3D:
		gc.transform = Transform3D.IDENTITY
		var shape_node := gc.get_node_or_null("CollisionShape3D")
		if shape_node is CollisionShape3D:
			shape_node.shape = terrain_shape
			shape_node.transform = Transform3D.IDENTITY
	_recompute_max_terrain_height()
	_configure_map_lighting()
	print("TEST_TERRAIN_BUILT: %dx%d samples, step=%d, %d hills, %d ridges, %d spline_ridges, %d plateaus, %d plateau_polygons, %d valleys, %d craters, %d valley_polygons" % [
		cols, rows, int(step), MapConfig._hills.size(), MapConfig._ridges.size(),
		MapConfig._spline_ridges.size(), MapConfig._plateaus.size(), MapConfig._plateau_polygons.size(),
		MapConfig._valleys.size(), MapConfig._craters.size(), MapConfig._valley_polygons.size()
	])

func _load_ground_texture() -> Texture2D:
	return _load_image_texture(GROUND_TEXTURE_PATH)

func _load_steep_hills_texture() -> Texture2D:
	return _load_image_texture(STEEP_HILLS_TEXTURE_PATH)

func _build_walkability() -> void:
	if _terrain_heights.is_empty():
		return
	var cfg := MapConfig.get_walkability()
	_walkability = WalkabilityGrid.new()
	_walkability.build(
		_terrain_heights,
		_terrain_cols,
		_terrain_rows,
		_terrain_step,
		_water_basins,
		cfg.max_slope_deg
	)
	_apply_ground_walkability_visual()
	print(
		"TEST_WALKABILITY_BUILT: walkable=%d/%d slope_max=%.0f lakes=%d"
		% [
			_walkability.walkable_count(),
			_terrain_cols * _terrain_rows,
			cfg.max_slope_deg,
			_water_basins.size(),
		]
	)

func _build_vegetation() -> void:
	if _walkability == null:
		return
	var foliage := get_node_or_null("Foliage")
	if foliage == null:
		foliage = Node3D.new()
		foliage.name = "Foliage"
		add_child(foliage)
	else:
		for child in foliage.get_children():
			child.queue_free()
	var builder := _VegetationBuilder.new()
	var anchors: Array = builder.build(self, MapConfig)
	for anchor in anchors:
		foliage.add_child(anchor)
	print("TEST_VEGETATION_BUILT: count=%d map=%s" % [anchors.size(), MapConfig.name_])

func _apply_ground_walkability_visual() -> void:
	var ground := get_node_or_null("Ground")
	if ground == null or not ground is MeshInstance3D or _walkability == null:
		return
	var mesh: Mesh = ground.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var arrays: Array = mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for j in range(_terrain_rows):
		for i in range(_terrain_cols):
			var idx: int = j * _terrain_cols + i
			if idx >= colors.size():
				continue
			colors[idx].a = 1.0 if _walkability.is_walkable_cell(i, j) else 0.0
	arrays[Mesh.ARRAY_COLOR] = colors
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_WALKABLE_SHADER
	var grass_tex := _load_ground_texture()
	var steep_tex := _load_steep_hills_texture()
	if grass_tex != null:
		mat.set_shader_parameter("grass_tex", grass_tex)
	if steep_tex != null:
		mat.set_shader_parameter("steep_tex", steep_tex)
	array_mesh.surface_set_material(0, mat)
	ground.mesh = array_mesh
	ground.set_surface_override_material(0, null)

func is_walkable_at(x: float, z: float) -> bool:
	if _walkability == null:
		return true
	return _walkability.is_walkable_world(x, z)

func snap_move_goal_xz(xz: Vector2) -> Vector2:
	xz = _clamp_map_v2(xz)
	if _walkability == null:
		return xz
	return _walkability.nearest_walkable(xz.x, xz.y)

func find_unit_path(from_xz: Vector2, to_xz: Vector2) -> PackedVector2Array:
	if _walkability == null:
		return PackedVector2Array([to_xz])
	return _walkability.find_path(from_xz, to_xz)

func prepare_unit_move_target(from_xz: Vector2, to_xz: Vector2) -> PackedVector2Array:
	to_xz = snap_move_goal_xz(to_xz)
	if _walkability == null:
		return PackedVector2Array([to_xz])
	if not _walkability.is_walkable_world(to_xz.x, to_xz.y):
		return PackedVector2Array()
	var found := _walkability.find_path(from_xz, to_xz)
	if found.is_empty():
		return PackedVector2Array()
	return found

func rebuild_from_mapconfig() -> void:
	_init_offmap_lanes()
	var bg := get_node_or_null("Background")
	if bg:
		bg.name = "BackgroundOld"
		bg.queue_free()
	var bounds := get_node_or_null("PlayBoundary")
	if bounds:
		bounds.name = "PlayBoundaryOld"
		bounds.queue_free()
	_build_terrain()
	add_water()
	_build_walkability()
	_build_vegetation()
	_build_background()
	_add_play_boundary_line()
	if _camera != null:
		_camera.far = _camera_far()
		_invalidate_pan_bounds_cache()
		_look_at_xz = _clamp_look_at_xz(_look_at_xz)

func add_water() -> void:
	var water_root := get_node_or_null("Water")
	if water_root == null:
		water_root = Node3D.new()
		water_root.name = "Water"
		add_child(water_root)
	for child in water_root.get_children():
		child.queue_free()
	if _terrain_heights.is_empty():
		print("TEST_WATER_BUILT: lakes=0 cells=0")
		_water_basins = []
		return
	var params: Dictionary = _WaterBuilder.default_params()
	var basins: Array = []
	var authored: Array = MapConfig.get_lakes()
	if not authored.is_empty():
		basins = _WaterBuilder.detect_lakes_from_seeds(
			_terrain_heights,
			_terrain_cols,
			_terrain_rows,
			_terrain_step,
			MapConfig.width,
			MapConfig.height,
			authored
		)
	elif MapConfig.map_size == "XL":
		params.min_cells = 12
		params.water_depth = 10.0
		basins = _WaterBuilder.detect_valley_polygon_lakes(
			_terrain_heights,
			_terrain_cols,
			_terrain_rows,
			_terrain_step,
			MapConfig.width,
			MapConfig.height,
			MapConfig.get_valley_polygons(),
			params
		)
	else:
		basins = _WaterBuilder.detect_lake_basins(
			_terrain_heights,
			_terrain_cols,
			_terrain_rows,
			_terrain_step,
			MapConfig.width,
			MapConfig.height,
			params
		)
	_water_basins = basins
	var water_tex := _load_image_texture(LAKES_WATER_TEXTURE_PATH)
	var total_cells := 0
	for basin in basins:
		var mat: StandardMaterial3D = _WaterBuilder.make_water_material(water_tex)
		var lake_mesh: MeshInstance3D = _WaterBuilder.make_lake_mesh(basin, mat)
		if lake_mesh.mesh == null:
			continue
		water_root.add_child(lake_mesh)
		total_cells += basin.cell_count
	print("TEST_WATER_BUILT: lakes=%d cells=%d" % [basins.size(), total_cells])

func _build_background() -> void:
	# Painted horizon backdrop along the z=0 map edge (the side furthest from
	# the camera). The quad stands vertically, bottom flush with the ground,
	# width = MapConfig.width + 2*MARGIN so it slightly overshoots the west/east
	# corners, height proportional to the source image aspect.
	var path := "res://images/background/background.png"
	var tex: Texture2D = null
	var img := Image.new()
	if img.load(path) == OK:
		tex = ImageTexture.create_from_image(img)
	elif ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is Texture2D:
			tex = res as Texture2D
	if tex == null:
		push_warning("Background image not found at %s" % path)
		return
	var old_bg := get_node_or_null("Background")
	if old_bg:
		old_bg.name = "BackgroundOld"
		old_bg.queue_free()
	var src_w: float = float(tex.get_width())
	var src_h: float = float(tex.get_height())
	if src_w <= 0.0 or src_h <= 0.0:
		push_warning("Background image has invalid dimensions")
		return
	const MARGIN: float = 20.0
	var panel_w: float = MapConfig.width + 2.0 * MARGIN
	var panel_h: float = panel_w * (src_h / src_w)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var quad := QuadMesh.new()
	quad.size = Vector2(panel_w, panel_h)
	var bg := MeshInstance3D.new()
	bg.name = "Background"
	bg.mesh = quad
	bg.material_override = mat
	# Sit one unit behind the map edge so we never z-fight with the ground
	# mesh; centered on X, lifted so the bottom edge touches y=0.
	bg.position = Vector3(MapConfig.width * 0.5, panel_h * 0.5, -1.0)
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bg)
	print("TEST_BACKGROUND_BUILT: w=%.1f h=%.1f at z=-1" % [panel_w, panel_h])

func _agent_debug_log_world_ready() -> void:
	#region agent log
	var vc: Camera3D = get_viewport().get_camera_3d()
	GameState.agent_debug_log("H5", "World.gd:_agent_debug_log_world_ready", "viewport_camera", {
		"viewport_cam_null": vc == null,
		"viewport_cam_path": str(vc.get_path()) if vc else "",
		"viewport_cam_is_current": vc.is_current() if vc else false,
		"_camera_matches_viewport": (vc == _camera) if vc and _camera else false
	})
	GameState.agent_debug_log("H4", "World.gd:_agent_debug_log_world_ready", "world_root_visibility", {
		"world_visible": visible,
		"world_in_tree": is_inside_tree()
	})
	#endregion

func _setup_selection_overlay():
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.name = "SelectionMarqueeLayer"
	add_child(layer)
	_marquee_overlay = _MarqueeRectOverlay.new()
	layer.add_child(_marquee_overlay)

func _setup_background_music() -> void:
	if get_node_or_null("BackgroundMusic") != null:
		return
	var stream: AudioStream = load(BG_MUSIC_PATH)
	if stream == null:
		push_warning("World: background music missing at %s" % BG_MUSIC_PATH)
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	var player := AudioStreamPlayer.new()
	player.name = "BackgroundMusic"
	player.stream = stream
	player.bus = AudioSettings.get_music_bus_name()
	if AudioServer.get_bus_index(player.bus) < 0:
		push_warning("World: Music bus missing; background music will use Master")
		player.bus = &"Master"
	add_child(player)
	player.play()

func _setup_camera():
	_camera = get_node_or_null("Camera3D")
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		add_child(_camera)
	# Pivot: position at look-at; camera is child, offset by distance
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "CameraPivot"
	add_child(_camera_pivot)
	_camera.reparent(_camera_pivot)
	# Closer views: reduce clipping through nearby geometry
	_camera.near = 0.35
	_camera.far = _camera_far()
	# Default is false; without an active camera the viewport draws no 3D (ground, units, CPs all missing).
	_camera.current = true
	_camera_smoothing_initialized = false
	_update_camera_position(0.0)
	#region agent log
	GameState.agent_debug_log("H1", "World.gd:_setup_camera", "camera_after_setup", {
		"camera_current": _camera.current,
		"camera_is_current": _camera.is_current(),
		"cam_global_origin": [ _camera.global_position.x, _camera.global_position.y, _camera.global_position.z ]
	})
	#endregion

## 0 = zoomed out (overview), 1 = zoomed in (soldier-like framing).
func _camera_zoom_t() -> float:
	var max_dist := _camera_max_distance()
	var span := max_dist - CAMERA_MIN_DISTANCE
	if span <= 0.001:
		return 0.0
	return clampf((max_dist - _camera_distance) / span, 0.0, 1.0)

func _target_pitch_deg_for_zoom() -> float:
	var t := _camera_zoom_t()
	return lerpf(CAMERA_PITCH_MAX_DEG, CAMERA_PITCH_MIN_DEG, t)

func _terrain_focus_y(zoom_t: float, ground_y: float) -> float:
	var eye := lerpf(CAMERA_EYE_HEIGHT_MAX, CAMERA_EYE_HEIGHT_MIN, zoom_t)
	return ground_y + eye

func _terrain_camera_clearance(zoom_t: float) -> float:
	return lerpf(CAMERA_CLEARANCE_MAX, CAMERA_CLEARANCE_MIN, zoom_t)

func _look_ahead_xz_unclamped(base: Vector2) -> Vector2:
	return base + Vector2(0.0, -CAMERA_SLOPE_LOOK_AHEAD)

func _viewport_ground_sample_screens() -> Array:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var points: Array = []
	var cols := 3
	var rows := 3
	for row in range(rows):
		for col in range(cols):
			points.append(
				Vector2(
					vp_size.x * float(col) / float(cols - 1),
					vp_size.y * float(row) / float(rows - 1)
				)
			)
	return points

func _invalidate_pan_bounds_cache() -> void:
	_pan_bounds_cache_pivot = Vector2(INF, INF)
	_pan_bounds_cache_dist = -1.0

## Apply camera pose for ground sampling (matches _update_camera_position when at current pivot).
func _apply_camera_pose_for_extents(look_xz: Vector2) -> void:
	if _camera_pivot == null or _camera == null:
		return
	var ahead_xz := _look_ahead_xz_unclamped(look_xz)
	var zoom_t := _camera_zoom_t()
	var ground_y: float
	var ahead_ground: float
	if look_xz.is_equal_approx(_look_at_xz) and _camera_smoothing_initialized:
		ground_y = _smoothed_ground_y
		ahead_ground = _smoothed_ahead_ground_y
	else:
		ground_y = get_ground_height_at(look_xz.x, look_xz.y)
		ahead_ground = get_ground_height_at(ahead_xz.x, ahead_xz.y)
	var focus_y := _terrain_focus_y(zoom_t, ground_y)
	var focus := Vector3(look_xz.x, focus_y, look_xz.y)
	_camera_pivot.position = focus
	var rad := deg_to_rad(_smoothed_pitch_deg)
	var offset := Vector3(0.0, _camera_distance * sin(rad), _camera_distance * cos(rad))
	var cam_pos := focus + offset
	var ground_cam := get_ground_height_at(cam_pos.x, cam_pos.z)
	var min_cam_y := ground_cam + _terrain_camera_clearance(zoom_t)
	if cam_pos.y < min_cam_y:
		cam_pos.y = min_cam_y
	_camera.global_position = cam_pos
	var look_target_xz := look_xz.lerp(ahead_xz, zoom_t)
	var look_ground := lerpf(ground_y, ahead_ground, zoom_t)
	var look_y := _terrain_focus_y(zoom_t, look_ground)
	_camera.look_at(Vector3(look_target_xz.x, look_y, look_target_xz.y), Vector3.UP)

func _raycast_ground_along_camera_ray(from: Vector3, dir: Vector3) -> Vector3:
	dir = dir.normalized()
	var ray_len := _ground_ray_length()
	var to := from + dir * ray_len
	var best := Vector3.ZERO
	var best_t := INF
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2
	query.hit_back_faces = true
	var phys_hit := space_state.intersect_ray(query)
	if not phys_hit.is_empty():
		var pp: Vector3 = phys_hit.position
		if _terrain_in_map_bounds(pp.x, pp.z):
			best = pp
			best_t = _ray_param_from(from, dir, pp)
	for crossing in _terrain_grid_crossings_along_ray(from, to):
		var pt: Vector3 = crossing
		if not _terrain_in_map_bounds(pt.x, pt.z):
			continue
		var t := _ray_param_from(from, dir, pt)
		if t < best_t:
			best_t = t
			best = pt
	return best

func _ground_hit_at_screen_for_pose(screen: Vector2, look_xz: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	_apply_camera_pose_for_extents(look_xz)
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	return _raycast_ground_along_camera_ray(from, dir)

func _raycast_ground_at_screen_with_current_pose(screen: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	return _raycast_ground_along_camera_ray(from, dir)

## Visible ground AABB from viewport samples: (min_x, max_x, min_z, max_z).
func _visible_ground_xz_bounds(look_xz: Vector2) -> Vector4:
	if _camera == null:
		return Vector4.ZERO
	if look_xz.is_equal_approx(_pan_bounds_cache_pivot) and is_equal_approx(_camera_distance, _pan_bounds_cache_dist):
		return _pan_bounds_cache_result
	_apply_camera_pose_for_extents(look_xz)
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for sp in _viewport_ground_sample_screens():
		var screen: Vector2 = sp
		var hit: Vector3 = _raycast_ground_at_screen_with_current_pose(screen)
		if hit == Vector3.ZERO:
			continue
		min_x = minf(min_x, hit.x)
		max_x = maxf(max_x, hit.x)
		min_z = minf(min_z, hit.z)
		max_z = maxf(max_z, hit.z)
	if min_z == INF and max_z == -INF and min_x == INF and max_x == -INF:
		_pan_bounds_cache_pivot = look_xz
		_pan_bounds_cache_dist = _camera_distance
		_pan_bounds_cache_result = Vector4.ZERO
		return Vector4.ZERO
	var result := Vector4(min_x, max_x, min_z, max_z)
	_pan_bounds_cache_pivot = look_xz
	_pan_bounds_cache_dist = _camera_distance
	_pan_bounds_cache_result = result
	return result

func _clamp_look_at_xz(v: Vector2) -> Vector2:
	var zoom_t := _camera_zoom_t()
	if zoom_t > 0.85:
		return Vector2(
			clampf(v.x, 0.0, MapConfig.width),
			clampf(v.y, 0.0, MapConfig.height)
		)
	_invalidate_pan_bounds_cache()
	var pad := CAMERA_PAN_EDGE_PADDING if zoom_t < 0.05 else CAMERA_PAN_EDGE_PADDING * maxf(zoom_t, 0.35)
	var recover_y := maxf(40.0, _camera_pan_speed() / 60.0)
	for _i in range(3):
		var b := _visible_ground_xz_bounds(v)
		if b == Vector4.ZERO:
			if zoom_t < 0.05:
				v.y += recover_y
			continue
		var delta := Vector2.ZERO
		if b.z < pad:
			delta.y -= b.z - pad
		if b.w > MapConfig.height - pad:
			delta.y -= b.w - (MapConfig.height - pad)
		if b.x < pad:
			delta.x -= b.x - pad
		if b.y > MapConfig.width - pad:
			delta.x -= b.y - (MapConfig.width - pad)
		if delta.length_squared() < 0.01:
			break
		v += delta
		_invalidate_pan_bounds_cache()
	return v

func _ray_hit_plane_y(from: Vector3, dir: Vector3, plane_y: float) -> Variant:
	if absf(dir.y) < 0.0001:
		return null
	var t := (plane_y - from.y) / dir.y
	if t < 0.0:
		return null
	return from + dir * t

## Ground footprint beyond pivot: (west, east, north, south) in map X/Z units.
func _camera_ground_view_extents_raw(look_xz: Vector2) -> Vector4:
	var b := _visible_ground_xz_bounds(look_xz)
	if b == Vector4.ZERO:
		return Vector4.ZERO
	var pad := CAMERA_PAN_EDGE_PADDING
	return Vector4(
		look_xz.x - b.x + pad,
		b.y - look_xz.x + pad,
		look_xz.y - b.z + pad,
		b.w - look_xz.y + pad
	)

func _camera_ground_view_extents_for(look_xz: Vector2) -> Vector4:
	var raw := _camera_ground_view_extents_raw(look_xz)
	var margin_t := 1.0 - _camera_zoom_t()
	return Vector4(raw.x * margin_t, raw.y * margin_t, raw.z * margin_t, raw.w * margin_t)

func _camera_look_ahead_xz() -> Vector2:
	return _clamp_look_at_xz(_look_ahead_xz_unclamped(_look_at_xz))

func _update_camera_position(delta: float = 0.0) -> void:
	if _camera_pivot == null or _camera == null:
		return
	var ahead_xz := _look_ahead_xz_unclamped(_look_at_xz)
	var target_ground := get_ground_height_at(_look_at_xz.x, _look_at_xz.y)
	var target_ahead_ground := get_ground_height_at(ahead_xz.x, ahead_xz.y)
	var target_pitch := _target_pitch_deg_for_zoom()
	if not _camera_smoothing_initialized or delta <= 0.0:
		_smoothed_ground_y = target_ground
		_smoothed_ahead_ground_y = target_ahead_ground
		_smoothed_pitch_deg = target_pitch
		_camera_smoothing_initialized = true
	else:
		_smoothed_ground_y = move_toward(_smoothed_ground_y, target_ground, CAMERA_GROUND_SMOOTH_SPEED * delta)
		_smoothed_ahead_ground_y = move_toward(
			_smoothed_ahead_ground_y, target_ahead_ground, CAMERA_GROUND_SMOOTH_SPEED * delta
		)
		_smoothed_pitch_deg = move_toward(_smoothed_pitch_deg, target_pitch, CAMERA_PITCH_SMOOTH_SPEED * delta)
	ahead_xz = _look_ahead_xz_unclamped(_look_at_xz)
	var zoom_t := _camera_zoom_t()
	var focus_y := _terrain_focus_y(zoom_t, _smoothed_ground_y)
	var focus := Vector3(_look_at_xz.x, focus_y, _look_at_xz.y)
	_camera_pivot.position = focus
	var rad := deg_to_rad(_smoothed_pitch_deg)
	var offset := Vector3(0.0, _camera_distance * sin(rad), _camera_distance * cos(rad))
	var cam_pos := focus + offset
	var ground_cam := get_ground_height_at(cam_pos.x, cam_pos.z)
	var min_cam_y := ground_cam + _terrain_camera_clearance(zoom_t)
	if cam_pos.y < min_cam_y:
		cam_pos.y = min_cam_y
	_camera.global_position = cam_pos
	var look_xz := _look_at_xz.lerp(ahead_xz, zoom_t)
	var look_ground := lerpf(_smoothed_ground_y, _smoothed_ahead_ground_y, zoom_t)
	var look_y := _terrain_focus_y(zoom_t, look_ground)
	var look_target := Vector3(look_xz.x, look_y, look_xz.y)
	_camera.look_at(look_target, Vector3.UP)

func _unhandled_input(event: InputEvent):
	if preview_only:
		_preview_camera_input(event)
		return
	if multiplayer.is_server() or game_over:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_camera_distance = maxf(CAMERA_MIN_DISTANCE, _camera_distance - CAMERA_ZOOM_SPEED)
			_invalidate_pan_bounds_cache()
			_look_at_xz = _clamp_look_at_xz(_look_at_xz)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_camera_distance = minf(_camera_max_distance(), _camera_distance + CAMERA_ZOOM_SPEED)
			_invalidate_pan_bounds_cache()
			_look_at_xz = _clamp_look_at_xz(_look_at_xz)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_drag = mb.pressed
			if mb.pressed:
				_last_mouse = mb.position
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_handle_world3d_mouse_extended(event)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _pan_drag:
			var mm := event as InputEventMouseMotion
			var delta := mm.position - _last_mouse
			_last_mouse = mm.position
			var pan_scale := _camera_distance / 600.0
			_look_at_xz.x -= delta.x * 0.5 * pan_scale
			_look_at_xz.y -= delta.y * 0.5 * pan_scale
			_invalidate_pan_bounds_cache()
			_look_at_xz = _clamp_look_at_xz(_look_at_xz)
			get_viewport().set_input_as_handled()
		else:
			_handle_world3d_mouse_extended(event)
	elif event is InputEventKey and event.pressed:
		_handle_key(event)

func _multiplayer_active() -> bool:
	var peer = multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _preview_camera_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_camera_distance = maxf(CAMERA_MIN_DISTANCE, _camera_distance - CAMERA_ZOOM_SPEED)
			_invalidate_pan_bounds_cache()
			_look_at_xz = _clamp_look_at_xz(_look_at_xz)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_camera_distance = minf(_camera_max_distance(), _camera_distance + CAMERA_ZOOM_SPEED)
			_invalidate_pan_bounds_cache()
			_look_at_xz = _clamp_look_at_xz(_look_at_xz)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_drag = mb.pressed
			if mb.pressed:
				_last_mouse = mb.position
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventMouseMotion and _pan_drag:
		var mm := event as InputEventMouseMotion
		var delta := mm.position - _last_mouse
		_last_mouse = mm.position
		var pan_scale := _camera_distance / 600.0
		_look_at_xz.x -= delta.x * 0.5 * pan_scale
		_look_at_xz.y -= delta.y * 0.5 * pan_scale
		_invalidate_pan_bounds_cache()
		_look_at_xz = _clamp_look_at_xz(_look_at_xz)
		get_viewport().set_input_as_handled()

func _process(delta: float):
	if preview_only:
		_preview_camera_process(delta)
		return
	if not _multiplayer_active():
		return
	if not multiplayer.is_server():
		_update_move_goal_markers_3d()
		_update_unit_range_markers_3d()
		_update_click_marker(delta)
	if _camera_pivot == null:
		return
	if multiplayer.is_server():
		return
	var pan_speed := _camera_pan_speed()
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		pan.x -= pan_speed
	if Input.is_key_pressed(KEY_D):
		pan.x += pan_speed
	if Input.is_key_pressed(KEY_W):
		pan.y -= pan_speed
	if Input.is_key_pressed(KEY_S):
		pan.y += pan_speed
	if pan != Vector2.ZERO:
		_look_at_xz += pan * delta
		_invalidate_pan_bounds_cache()
		_look_at_xz = _clamp_look_at_xz(_look_at_xz)
	_update_camera_position(delta)

func _preview_camera_process(delta: float) -> void:
	if _camera_pivot == null:
		return
	var pan_speed := _camera_pan_speed()
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		pan.x -= pan_speed
	if Input.is_key_pressed(KEY_D):
		pan.x += pan_speed
	if Input.is_key_pressed(KEY_W):
		pan.y -= pan_speed
	if Input.is_key_pressed(KEY_S):
		pan.y += pan_speed
	if pan != Vector2.ZERO:
		_look_at_xz += pan * delta
		_invalidate_pan_bounds_cache()
		_look_at_xz = _clamp_look_at_xz(_look_at_xz)
	_update_camera_position(delta)

## Move-goal markers: one range-style ring per soldier slot at the local player's final dest.
func _update_move_goal_markers_3d():
	if _move_goal_markers_3d == null:
		_move_goal_markers_3d = Node3D.new()
		_move_goal_markers_3d.name = "MoveGoalMarkers3D"
		add_child(_move_goal_markers_3d)
	if _move_goal_slot_mat == null:
		_move_goal_slot_mat = StandardMaterial3D.new()
		_move_goal_slot_mat.albedo_color = Color(0.35, 0.85, 0.45, 0.4)
		_move_goal_slot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_move_goal_slot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_move_goal_slot_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_move_goal_slot_mat.no_depth_test = true
	if _move_goal_ring_mesh == null:
		_move_goal_ring_mesh = _make_range_ring_mesh(6.0)
	var used := 0
	var pool: Array = _move_goal_markers_3d.get_children()
	var my_id := multiplayer.get_unique_id()
	for a in armies:
		if used >= MAX_GHOST_MARKERS:
			break
		if a == null or not is_instance_valid(a) or a.fc == null or a.is_routed:
			continue
		if a.owner_id != my_id:
			continue
		var fc = a.fc
		if not fc.moving:
			continue
		var d: Vector2 = fc.dest
		if d.distance_to(fc.anchor) <= MOVE_GOAL_MARKER_HIDE_DIST:
			continue
		var n_alive: int = _sim.army_alive_count(fc) if _sim != null else fc.members.size()
		if n_alive <= 0:
			continue
		var offs: PackedVector2Array = fc.slot_offsets(maxi(fc.packed_count, 1))
		var cs := cos(fc.direction)
		var sn := sin(fc.direction)
		for k in range(n_alive):
			if used >= MAX_GHOST_MARKERS:
				break
			var o: Vector2 = offs[mini(k, offs.size() - 1)]
			var gx: float = d.x + o.x * cs - o.y * sn
			var gz: float = d.y + o.x * sn + o.y * cs
			var snapped := snap_move_goal_xz(Vector2(gx, gz))
			var mi: MeshInstance3D
			if used < pool.size():
				mi = pool[used]
			else:
				mi = MeshInstance3D.new()
				mi.material_override = _move_goal_slot_mat
				_move_goal_markers_3d.add_child(mi)
				pool.append(mi)
			if mi.mesh != _move_goal_ring_mesh:
				mi.mesh = _move_goal_ring_mesh
			mi.visible = true
			mi.position = Vector3(snapped.x, get_ground_height_at(snapped.x, snapped.y) + 0.25, snapped.y)
			used += 1
	for i in range(used, pool.size()):
		pool[i].visible = false

func _on_show_range_toggled(pressed: bool) -> void:
	_show_unit_range = pressed
	if not pressed:
		_clear_range_markers()

func _clear_range_markers() -> void:
	if _range_markers_3d == null:
		return
	for c in _range_markers_3d.get_children():
		c.visible = false

func _range_color_for_owner(owner_pid: int) -> Color:
	var local_pid := multiplayer.get_unique_id()
	if owner_pid == local_pid:
		return Color(0.25, 0.85, 0.35, 0.55)
	if UNIT_SPRITE_PATHS.is_neutral_owner(owner_pid):
		return Color(1.0, 0.55, 0.1, 0.55)
	return Color(0.9, 0.25, 0.25, 0.55)

func _make_range_ring_mesh(radius: float) -> ArrayMesh:
	var segments := 64
	var line_width := 1.4
	var inner_r := maxf(0.5, radius - line_width * 0.5)
	var outer_r := radius + line_width * 0.5
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		var base := verts.size()
		verts.append_array([
			Vector3(c0.x * inner_r, 0.0, c0.y * inner_r),
			Vector3(c0.x * outer_r, 0.0, c0.y * outer_r),
			Vector3(c1.x * outer_r, 0.0, c1.y * outer_r),
			Vector3(c1.x * inner_r, 0.0, c1.y * inner_r),
		])
		uvs.append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Range rings: one ring per selected army (attack range + formation half width), pooled.
func _update_unit_range_markers_3d() -> void:
	if not _show_unit_range or _sim == null:
		return
	if _range_markers_3d == null:
		_range_markers_3d = Node3D.new()
		_range_markers_3d.name = "UnitRangeMarkers3D"
		add_child(_range_markers_3d)
	var pool: Array = _range_markers_3d.get_children()
	var used := 0
	for a in selected_armies:
		if a == null or not is_instance_valid(a) or a.fc == null or a.is_routed:
			continue
		var fc = a.fc
		var rng := 0.0
		for id in fc.members:
			if _sim.is_alive(id):
				rng = _sim.attack_range[id]
				break
		if rng <= 0.0:
			continue
		var radius: float = rng + fc.half_width()
		var mi: MeshInstance3D
		if used < pool.size():
			mi = pool[used]
		else:
			mi = MeshInstance3D.new()
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = mat
			_range_markers_3d.add_child(mi)
			pool.append(mi)
		mi.visible = true
		if mi.mesh == null or absf(radius - _range_ring_radius(mi.mesh)) > 0.5:
			mi.mesh = _make_range_ring_mesh(radius)
		var mat2: StandardMaterial3D = mi.material_override as StandardMaterial3D
		if mat2 != null:
			mat2.albedo_color = _range_color_for_owner(a.owner_id)
		var c: Vector2 = _sim.army_centroid(fc)
		mi.position = Vector3(c.x, get_ground_height_at(c.x, c.y) + 0.18, c.y)
		used += 1
	for i in range(used, pool.size()):
		pool[i].visible = false

func _range_ring_radius(mesh: Mesh) -> float:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0.0
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return 0.0
	var max_r := 0.0
	for v in verts:
		max_r = maxf(max_r, Vector2(v.x, v.z).length())
	return max_r

func _setup_topbar():
	var tb_script = preload("res://TopBar.gd")
	top_bar = CanvasLayer.new()
	top_bar.set_script(tb_script)
	top_bar.name = "TopBar"
	top_bar.layer = 10
	add_child(top_bar)

func _setup_draft_menu():
	draft_menu = CanvasLayer.new()
	draft_menu.name = "DraftMenu"
	draft_menu.layer = 12
	add_child(draft_menu)
	var panel = PanelContainer.new()
	panel.offset_left = 10
	panel.offset_top = 590
	panel.offset_right = 220
	panel.offset_bottom = 760
	draft_menu.add_child(panel)
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	var horse_cb = CheckBox.new()
	horse_cb.name = "HorseCheck"
	horse_cb.text = "Horse"
	vbox.add_child(horse_cb)
	var spear_cb = CheckBox.new()
	spear_cb.name = "SpearCheck"
	spear_cb.text = "Spear"
	vbox.add_child(spear_cb)
	var bow_cb = CheckBox.new()
	bow_cb.name = "BowCheck"
	bow_cb.text = "Bow"
	vbox.add_child(bow_cb)
	_show_range_cb = CheckBox.new()
	_show_range_cb.name = "ShowRangeCheck"
	_show_range_cb.text = "Show range"
	_show_range_cb.toggled.connect(_on_show_range_toggled)
	vbox.add_child(_show_range_cb)
	var size_row := HBoxContainer.new()
	var size_label := Label.new()
	size_label.text = "Soldiers"
	size_row.add_child(size_label)
	_draft_size_spin = SpinBox.new()
	_draft_size_spin.name = "SoldierCount"
	_draft_size_spin.min_value = MIN_SOLDIERS_PER_ARMY
	_draft_size_spin.max_value = MAX_SOLDIERS_PER_ARMY
	_draft_size_spin.step = 10
	_draft_size_spin.value = DEFAULT_SOLDIERS_PER_ARMY
	size_row.add_child(_draft_size_spin)
	vbox.add_child(size_row)
	var create_btn = Button.new()
	create_btn.name = "CreateArmyBtn"
	create_btn.text = "Create army"
	create_btn.pressed.connect(_on_draft_create_pressed.bind(horse_cb, spear_cb, bow_cb))
	vbox.add_child(create_btn)

func _setup_army_command_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 45
	layer.name = "ArmyCommandLayer"
	add_child(layer)
	_army_command_bar = _ArmyCommandBar.new()
	_army_command_bar.name = "ArmyCommandBar"
	_army_command_bar.offset_left = 10
	_army_command_bar.offset_top = 400
	_army_command_bar.offset_right = 520
	_army_command_bar.offset_bottom = 480
	layer.add_child(_army_command_bar)
	_army_command_bar.stance_pressed.connect(_on_command_bar_stance)

func _on_draft_create_pressed(horse_cb: CheckBox, spear_cb: CheckBox, bow_cb: CheckBox):
	var use_horse = horse_cb.button_pressed
	var use_spear = spear_cb.button_pressed
	var use_bow = bow_cb.button_pressed
	var count := DEFAULT_SOLDIERS_PER_ARMY
	if _draft_size_spin != null:
		count = int(_draft_size_spin.value)
	_request_draft(use_horse, use_spear, use_bow, count)

func _request_draft(use_horse: bool, use_spear: bool, use_bow: bool, soldier_count: int = DEFAULT_SOLDIERS_PER_ARMY):
	rpc_id(1, "request_draft_army", use_horse, use_spear, use_bow, soldier_count)

## ---------------------------------------------------------------------------------------------
## Orders: formation-level, tiny and reliable. Client -> server request, server validates
## ownership, stamps (order_seq, sim_tick), applies to its sim and echoes reliably to every
## peer (including the sender). Clients apply on echo; both sims then run the same movement.
## ---------------------------------------------------------------------------------------------

func _stamp_order() -> int:
	_order_seq += 1
	return _order_seq

func _owned_live_armies(sender: int, army_ids: Array) -> Array:
	var out: Array = []
	for aid in army_ids:
		var army = _find_army(str(aid))
		if army == null or army.owner_id != sender or army.is_routed:
			continue
		out.append(army)
	return out

## Shared by server and clients: apply a batch of MOVE / ATTACK_MOVE orders to the sim.
## `dests` = [x0, z0, x1, z1, ...], `facings` front angle per army (< -100 keeps travel
## direction), `widths` desired line width per army (<= 0 keeps the current rows).
func _apply_move_orders(army_ids: Array, dests: PackedFloat32Array, facings: PackedFloat32Array, widths: PackedFloat32Array, attack_move: bool) -> int:
	var n := 0
	for k in range(army_ids.size()):
		var army = _find_army(str(army_ids[k]))
		if army == null or army.fc == null or army.is_routed:
			continue
		var fc = army.fc
		var dest := snap_move_goal_xz(_clamp_map_v2(Vector2(dests[k * 2], dests[k * 2 + 1])))
		var facing: float = facings[k] if k < facings.size() else -999.0
		var width: float = widths[k] if k < widths.size() else 0.0
		_sim.recentre_anchor(fc)
		if width > 0.0:
			fc.fit_rows_to_width(_sim.army_alive_count(fc), width)
		var line_dir := -999.0
		if facing > -100.0:
			line_dir = _Formation.line_direction_for_front(facing)
		fc.issue_move(dest, line_dir, attack_move)
		n += 1
	return n

func _apply_attack_order(army_ids: Array, target_army_id: String, target_unit: int) -> int:
	var n := 0
	var target_army = _find_army(target_army_id) if target_army_id != "" else null
	for aid in army_ids:
		var army = _find_army(str(aid))
		if army == null or army.fc == null or army.is_routed:
			continue
		_sim.recentre_anchor(army.fc)
		if target_army != null and target_army.fc != null and not target_army.is_routed:
			army.fc.issue_attack_army(target_army.fc.index)
			n += 1
		elif target_unit >= 0 and _sim.is_alive(target_unit):
			army.fc.issue_attack_unit(target_unit)
			n += 1
	return n

@rpc("any_peer", "reliable")
func _server_set_all_armies_aggressive():
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not GameState.players.has(sender):
		return
	var pname := str(GameState.players[sender].get("name", sender))
	var ids: Array = []
	for a in armies:
		if a == null or not is_instance_valid(a) or a.is_routed or a.owner_id != sender:
			continue
		a.fc.set_stance(_Formation.Stance.AGGRESSIVE)
		a.fc.clear_order()
		ids.append(a.army_id)
	rpc("_client_sync_army_stance", ids, _Formation.Stance.AGGRESSIVE)
	var marker = "TEST_A_AGGRESSIVE" if pname == "A" else "TEST_B_AGGRESSIVE"
	print("%s: Player '%s' set %d armies to aggressive" % [marker, pname, ids.size()])

@rpc("authority", "reliable")
func _client_sync_army_stance(army_ids: Array, new_stance: int):
	for aid in army_ids:
		var army = _find_army(str(aid))
		if army != null and army.fc != null:
			army.fc.set_stance(new_stance)
			if new_stance == _Formation.Stance.AGGRESSIVE:
				army.fc.clear_order()

@rpc("any_peer", "reliable")
func _server_armies_set_stance(army_ids: Array, stance: int):
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var synced: Array = []
	for army in _owned_live_armies(sender, army_ids):
		army.fc.set_stance(stance)
		if stance == _Formation.Stance.AGGRESSIVE:
			army.fc.clear_order()
		synced.append(army.army_id)
	if not synced.is_empty():
		rpc("_client_sync_army_stance", synced, stance)

@rpc("any_peer", "reliable")
func _server_armies_order_attack(army_ids: Array, target_army_id: String, target_unit: int):
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var owned := _owned_live_armies(sender, army_ids)
	if owned.is_empty():
		return
	var ids: Array = []
	for a in owned:
		ids.append(a.army_id)
	if _apply_attack_order(ids, target_army_id, target_unit) == 0:
		return
	var seq := _stamp_order()
	rpc("_client_order_attack", seq, _sim.tick, ids, target_army_id, target_unit)
	if target_army_id != "":
		print("TEST_ARMY_ATTACK: %s -> army %s" % [",".join(ids), target_army_id])
	else:
		print("TEST_ARMY_ATTACK: %s -> unit %d" % [",".join(ids), target_unit])

@rpc("any_peer", "reliable")
func _server_armies_order_attack_move(army_ids: Array, dest_x: float, dest_y: float):
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var owned := _owned_live_armies(sender, army_ids)
	if owned.is_empty():
		return
	var ids: Array = []
	var dests := PackedFloat32Array()
	for a in owned:
		ids.append(a.army_id)
		dests.append(dest_x)
		dests.append(dest_y)
	_server_broadcast_move(ids, dests, PackedFloat32Array(), PackedFloat32Array(), true)
	print("TEST_ARMY_ATTACK_MOVE: sender=%d dest=(%d,%d) armies=%d" % [sender, int(dest_x), int(dest_y), ids.size()])

## MockPlayer / simple move: one army to a point, facing the travel direction.
@rpc("any_peer", "reliable")
func _server_move_army(aid: String, target: Vector2):
	if not multiplayer.is_server():
		return
	var army = _find_army(aid)
	if army == null or army.is_routed:
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender != army.owner_id:
		return
	var marker = "TEST_009_MOVE" if army.owner_name == "A" else "TEST_009_MOVE_B"
	print("%s: Server moving army '%s' to (%d,%d)" % [marker, aid, int(target.x), int(target.y)])
	_server_broadcast_move([aid], PackedFloat32Array([target.x, target.y]), PackedFloat32Array(), PackedFloat32Array(), false)

## Formation orders from click / drag: per-army destination, facing and line width.
@rpc("any_peer", "reliable")
func _server_order_move(army_ids: Array, dests: PackedFloat32Array, facings: PackedFloat32Array, widths: PackedFloat32Array, attack_move: bool):
	if not multiplayer.is_server():
		return
	if dests.size() < army_ids.size() * 2:
		return
	var sender := multiplayer.get_remote_sender_id()
	var ids: Array = []
	var d2 := PackedFloat32Array()
	var f2 := PackedFloat32Array()
	var w2 := PackedFloat32Array()
	for k in range(army_ids.size()):
		var army = _find_army(str(army_ids[k]))
		if army == null or army.owner_id != sender or army.is_routed:
			continue
		ids.append(army.army_id)
		d2.append(dests[k * 2])
		d2.append(dests[k * 2 + 1])
		f2.append(facings[k] if k < facings.size() else -999.0)
		w2.append(widths[k] if k < widths.size() else 0.0)
	if ids.is_empty():
		return
	_server_broadcast_move(ids, d2, f2, w2, attack_move)
	print("TEST_GROUP_FORMATION: server armies=%d sender=%d attack_move=%s" % [ids.size(), sender, attack_move])

func _server_broadcast_move(ids: Array, dests: PackedFloat32Array, facings: PackedFloat32Array, widths: PackedFloat32Array, attack_move: bool) -> void:
	if _apply_move_orders(ids, dests, facings, widths, attack_move) == 0:
		return
	var seq := _stamp_order()
	rpc("_client_order_move", seq, _sim.tick, ids, dests, facings, widths, attack_move)

@rpc("authority", "reliable")
func _client_order_move(_seq: int, _tick: int, army_ids: Array, dests: PackedFloat32Array, facings: PackedFloat32Array, widths: PackedFloat32Array, attack_move: bool):
	_apply_move_orders(army_ids, dests, facings, widths, attack_move)
	_queue_unresolved_client_move(army_ids, dests, facings, widths, attack_move)

@rpc("authority", "reliable")
func _client_order_attack(_seq: int, _tick: int, army_ids: Array, target_army_id: String, target_unit: int):
	_apply_attack_order(army_ids, target_army_id, target_unit)
	_queue_unresolved_client_attack(army_ids, target_army_id, target_unit)

@rpc("any_peer", "reliable")
func _server_rotate_army(aid: String, delta_angle: float):
	if not multiplayer.is_server():
		return
	var army = _find_army(aid)
	if army == null or army.fc == null:
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender != army.owner_id:
		return
	army.fc.rotate(delta_angle)
	rpc("_client_rotate_army", aid, army.fc.direction)

@rpc("authority", "reliable")
func _client_rotate_army(aid: String, new_line_dir: float):
	var army = _find_army(aid)
	if army != null and army.fc != null:
		army.fc.direction = new_line_dir
		army.fc.slots_dirty = true

@rpc("any_peer", "reliable")
func request_draft_army(use_horse: bool, use_spear: bool, use_bow: bool = false, soldier_count: int = DEFAULT_SOLDIERS_PER_ARMY):
	if not multiplayer.is_server() or game_over:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	if sender_id not in GameState.players:
		return
	soldier_count = clampi(soldier_count, MIN_SOLDIERS_PER_ARMY, MAX_SOLDIERS_PER_ARMY)
	if not GameState.resources.has(sender_id):
		GameState.resources[sender_id] = GameState.default_resources()
	var res = GameState.resources[sender_id]
	# Cost scales with size: DRAFT_COST_PER_EQUIPMENT covers DEFAULT_SOLDIERS_PER_ARMY soldiers.
	var cost_units: int = ceili(float(DRAFT_COST_PER_EQUIPMENT) * float(soldier_count) / float(DEFAULT_SOLDIERS_PER_ARMY))
	var need_villagers := cost_units
	var need_horses = cost_units if use_horse else 0
	var need_spears = cost_units if use_spear else 0
	var need_bows = cost_units if use_bow else 0
	if res.get("villagers", 0) < need_villagers \
			or res.get("horses", 0) < need_horses \
			or res.get("spears", 0) < need_spears \
			or res.get("bows", 0) < need_bows:
		print("TEST_DRAFT_FAIL: Player %d insufficient resources (need vill=%d horse=%d spear=%d bow=%d)" % [
			sender_id, need_villagers, need_horses, need_spears, need_bows
		])
		return
	res["villagers"] -= need_villagers
	res["horses"] -= need_horses
	res["spears"] -= need_spears
	res["bows"] -= need_bows
	var pid = sender_id
	var pname = GameState.players[pid]["name"]
	var idx = army_index_per_player.get(pid, 3)
	army_index_per_player[pid] = idx + 1
	var aid = "P%d_%d" % [pid, idx]
	var slot: int = int(player_slot.get(pid, 0))
	var dest: Vector2 = MapConfig.get_start_position(slot)
	var edge: Dictionary = _offmap_spawn_for(dest)
	var spawn_pos: Vector2 = edge.get("spawn", WEST_SPAWN)
	var dir: float = float(edge.get("dir", 0.0))
	var side: String = _nearest_edge_side(dest)
	var stop_pos: Vector2 = _onmap_entry_for(spawn_pos, side)
	var equipment = {"horse": use_horse, "spear": use_spear, "bow": use_bow, "soldiers": soldier_count}
	var army = _create_army(aid, pid, pname, spawn_pos, dir, equipment)
	armies.append(army)
	var data = _serialize_one_army(army)
	data["stop_x"] = stop_pos.x
	data["stop_y"] = stop_pos.y
	data["stop_dir"] = dir
	rpc("_client_spawn_drafted_army", data)
	_server_broadcast_move([aid], PackedFloat32Array([stop_pos.x, stop_pos.y]), PackedFloat32Array([dir]), PackedFloat32Array(), false)
	_sync_capture_state()
	print("TEST_DRAFT_SUCCESS: Army '%s' drafted (horse=%s spear=%s bow=%s soldiers=%d)" % [aid, use_horse, use_spear, use_bow, soldier_count])

func _set_player_sides():
	# Assign each player a start-position index by join order. Draft still uses
	# west/east/north/south from the nearest map edge of that start marker.
	var player_ids = GameState.players.keys()
	for i in range(player_ids.size()):
		var pid = player_ids[i]
		player_slot[pid] = i
		var dest: Vector2 = MapConfig.get_start_position(i)
		player_side[pid] = _nearest_edge_side(dest)
	for pid in player_ids:
		army_index_per_player[pid] = MapConfig.max_armies_per_player() + 1

func _nearest_edge_side(dest: Vector2) -> String:
	var w: float = MapConfig.width
	var h: float = MapConfig.height
	var d_w: float = dest.x
	var d_e: float = w - dest.x
	var d_n: float = dest.y
	var d_s: float = h - dest.y
	if d_w <= d_e and d_w <= d_n and d_w <= d_s:
		return "west"
	if d_e <= d_n and d_e <= d_s:
		return "east"
	if d_n <= d_s:
		return "north"
	return "south"

func _offmap_spawn_for(dest: Vector2) -> Dictionary:
	var w: float = MapConfig.width
	var h: float = MapConfig.height
	var m := OFFMAP_SPAWN_MARGIN
	var side := _nearest_edge_side(dest)
	match side:
		"west":
			return {"spawn": Vector2(-m, clampf(dest.y, 0.0, h)), "dir": 0.0}
		"east":
			return {"spawn": Vector2(w + m, clampf(dest.y, 0.0, h)), "dir": PI}
		"north":
			return {"spawn": Vector2(clampf(dest.x, 0.0, w), -m), "dir": PI / 2.0}
		_:
			return {"spawn": Vector2(clampf(dest.x, 0.0, w), h + m), "dir": -PI / 2.0}

func _onmap_entry_for(spawn: Vector2, side: String) -> Vector2:
	match side:
		"west":
			return Vector2(WEST_STOP_X, spawn.y)
		"east":
			return Vector2(EAST_STOP_X, spawn.y)
		"north":
			return Vector2(spawn.x, NORTH_STOP_Y)
		_:
			return Vector2(spawn.x, SOUTH_STOP_Y)

func _default_start_armies() -> Array:
	return [
		{"spear": true},
		{"horse": true},
	]

func _soldiers_for_army_cfg(ac: Dictionary) -> int:
	return clampi(int(ac.get("soldiers", DEFAULT_SOLDIERS_PER_ARMY)), MIN_SOLDIERS_PER_ARMY, MAX_SOLDIERS_PER_ARMY)

func _spawn_armies():
	var player_ids = GameState.players.keys()
	if player_ids.size() < 2:
		print("ERROR: Need at least 2 players to spawn armies")
		return
	var max_p: int = MapConfig.max_players()
	var total_soldiers := 0
	var march_ids: Array = []
	var march_dests := PackedFloat32Array()
	var march_dirs := PackedFloat32Array()
	for p in range(mini(player_ids.size(), max_p)):
		var pid = player_ids[p]
		var pname = GameState.players[pid]["name"]
		var slot: int = player_slot.get(pid, p)
		var dest: Vector2 = MapConfig.get_start_position(slot)
		var edge: Dictionary = _offmap_spawn_for(dest)
		var spawn_pos: Vector2 = edge.get("spawn", Vector2.ZERO)
		var dir: float = float(edge.get("dir", 0.0))
		var perp := Vector2(-sin(dir), cos(dir))
		var start: Dictionary = MapConfig.get_player_start(slot)
		var start_armies: Array = start.get("armies", [])
		if start_armies.is_empty():
			start_armies = _default_start_armies()
		var n_armies: int = start_armies.size()
		for i in range(n_armies):
			var ac: Dictionary = start_armies[i]
			var spread: float = (float(i) - float(n_armies - 1) * 0.5) * 80.0
			var spawn_i: Vector2 = spawn_pos + perp * spread
			var dest_i: Vector2 = dest + perp * spread
			var army_id = "P%d_%d" % [pid, i + 1]
			var equipment = {
				"horse": ac.get("horse", false),
				"spear": ac.get("spear", false),
				"bow": ac.get("bow", false),
				"soldiers": _soldiers_for_army_cfg(ac),
			}
			var army = _create_army(army_id, pid, pname, spawn_i, dir, equipment)
			armies.append(army)
			total_soldiers += army.soldier_count()
			march_ids.append(army_id)
			march_dests.append(dest_i.x)
			march_dests.append(dest_i.y)
			march_dirs.append(dir)
		total_soldiers += _spawn_stress_armies(pid, pname, start_armies, dest, dir, perp)
	var armies_per_player := MapConfig.max_armies_per_player()
	print("TEST_ARMIES_SPAWNED: %d armies spawned (%d per player, %d soldiers total)" % [armies.size(), armies_per_player, total_soldiers])
	_match_started = true
	_match_elapsed = 0.0
	for a in armies:
		var axz: Vector2 = a.anchor()
		print("  Army '%s' at (%d,%d) dir=%.1f owner=%s soldiers=%d" % [a.army_id, int(axz.x), int(axz.y), a.direction, a.owner_name, a.soldier_count()])
	rpc("_client_spawn_armies", _serialize_armies_with_march(march_ids, march_dests, march_dirs))
	if not march_ids.is_empty():
		_server_broadcast_move(march_ids, march_dests, march_dirs, PackedFloat32Array(), false)
	_spawn_map_dragons()

## `--stress-units=N`: top up each player with extra armies laid out in a grid around
## that player's start marker until N soldiers exist. Returns the number of soldiers added.
func _spawn_stress_armies(pid: int, pname: String, start_armies: Array, dest: Vector2, dir: float, perp: Vector2) -> int:
	var want: int = GameState.stress_units_per_player
	if want <= 0:
		return 0
	var have := 0
	for ac in start_armies:
		have += _soldiers_for_army_cfg(ac)
	var per_army := STRESS_SOLDIERS_PER_ARMY
	var extra_armies: int = ceili(float(want - have) / float(per_army))
	if extra_armies <= 0:
		return 0
	var back := Vector2(-cos(dir), -sin(dir))
	var per_row: int = maxi(1, int(sqrt(float(extra_armies))))
	var pitch := 140.0
	var equipment_cycle: Array = [
		{"spear": true}, {}, {"bow": true}, {"horse": true},
	]
	var added := 0
	for k in range(extra_armies):
		var row: int = k / per_row
		var col: int = k % per_row
		var offset: Vector2 = perp * (float(col - per_row / 2) * pitch) + back * float(row + 1) * pitch
		var pos := _clamp_map_v2(snap_move_goal_xz(dest + offset))
		var eq: Dictionary = equipment_cycle[k % equipment_cycle.size()]
		var army_id := "P%d_S%d" % [pid, k + 1]
		var army = _create_army(army_id, pid, pname, pos, dir, {
			"horse": eq.get("horse", false),
			"spear": eq.get("spear", false),
			"bow": eq.get("bow", false),
			"soldiers": per_army,
		})
		armies.append(army)
		added += army.soldier_count()
	print("TEST_STRESS_SPAWN: pid=%d extra_armies=%d target_units=%d" % [pid, extra_armies, want])
	return added

## Neutral dragons are one-unit armies owned by NEUTRAL_DRAGON_OWNER_ID with a simple aggro AI.
func _spawn_map_dragons() -> void:
	if not multiplayer.is_server():
		return
	# Auto-test is player-vs-player; the S-map dragon sits on the path between
	# Stables and Blacksmith and stalls combat past the 120s match cap.
	if GameState.is_auto_test:
		return
	var cfgs: Array = MapConfig.get_neutral_dragons()
	if cfgs.is_empty():
		return
	var dragon_data: Array = []
	for i in range(cfgs.size()):
		var cfg: Dictionary = cfgs[i]
		if cfg.is_empty():
			continue
		var pos := Vector2(float(cfg.get("x", MapConfig.width * 0.5)), float(cfg.get("y", MapConfig.height * 0.5)))
		var color := str(cfg.get("color", "red"))
		var aid := "neutral_dragon_%d" % i
		var army = _create_army(aid, UNIT_SPRITE_PATHS.NEUTRAL_DRAGON_OWNER_ID, "Dragon", pos, 0.0, {"dragon": true, "soldiers": 1, "color": color})
		armies.append(army)
		_map_dragons.append(army)
		print("TEST_MAP_DRAGON_SPAWN: dragon %d at (%d,%d) aggro=%.0f attack=%.0f" % [
			i, int(pos.x), int(pos.y), UNIT_SPRITE_PATHS.dragon_aggro_radius(), _UnitSim.DRAGON_ATTACK_RANGE
		])
		var d := _serialize_one_army(army)
		d["index"] = i
		d["color"] = color
		dragon_data.append(d)
	if not dragon_data.is_empty():
		rpc("_client_spawn_dragons", dragon_data)

func _update_map_dragon_ai(delta: float) -> void:
	if _map_dragons.is_empty():
		return
	_dragon_ai_timer += delta
	if _dragon_ai_timer < DRAGON_AI_TICK:
		return
	_dragon_ai_timer = 0.0
	for army in _map_dragons:
		if army == null or not is_instance_valid(army) or army.is_routed or army.fc == null:
			continue
		if _sim.army_alive_count(army.fc) == 0:
			continue
		_update_one_map_dragon_ai(army)

func _update_one_map_dragon_ai(army) -> void:
	var fc = army.fc
	var center: Vector2 = _sim.army_centroid(fc)
	var aggro := UNIT_SPRITE_PATHS.dragon_aggro_radius()
	var best: int = _sim.nearest_unit(center, aggro, UNIT_SPRITE_PATHS.NEUTRAL_DRAGON_OWNER_ID, true)
	if best < 0:
		if fc.order_type != _Formation.OrderType.NONE:
			fc.clear_order()
			rpc("_client_order_clear", army.army_id)
		return
	if fc.order_type == _Formation.OrderType.ATTACK and fc.order_target_unit == best:
		return
	_sim.recentre_anchor(fc)
	fc.set_stance(_Formation.Stance.AGGRESSIVE)
	fc.issue_attack_unit(best)
	rpc("_client_order_attack", _stamp_order(), _sim.tick, [army.army_id], "", best)

@rpc("authority", "reliable")
func _client_order_clear(aid: String) -> void:
	var army = _find_army(aid)
	if army != null and army.fc != null:
		army.fc.clear_order()
		return
	if multiplayer.is_server():
		return
	_pending_client_orders.append({"kind": "clear", "aid": aid})

func _queue_unresolved_client_move(army_ids: Array, dests: PackedFloat32Array, facings: PackedFloat32Array, widths: PackedFloat32Array, attack_move: bool) -> void:
	if multiplayer.is_server():
		return
	for aid in army_ids:
		if _find_army(str(aid)) == null:
			_pending_client_orders.append({
				"kind": "move",
				"ids": army_ids.duplicate(),
				"dests": dests.duplicate(),
				"facings": facings.duplicate(),
				"widths": widths.duplicate(),
				"attack_move": attack_move,
			})
			return

func _queue_unresolved_client_attack(army_ids: Array, target_army_id: String, target_unit: int) -> void:
	if multiplayer.is_server():
		return
	for aid in army_ids:
		if _find_army(str(aid)) == null:
			_pending_client_orders.append({
				"kind": "attack",
				"ids": army_ids.duplicate(),
				"target_army_id": target_army_id,
				"target_unit": target_unit,
			})
			return

func _flush_pending_client_orders() -> void:
	if _pending_client_orders.is_empty():
		return
	var pending: Array = _pending_client_orders
	_pending_client_orders = []
	for o in pending:
		var kind := str(o.get("kind", ""))
		if kind == "move":
			_apply_move_orders(o["ids"], o["dests"], o["facings"], o["widths"], bool(o.get("attack_move", false)))
			_queue_unresolved_client_move(o["ids"], o["dests"], o["facings"], o["widths"], bool(o.get("attack_move", false)))
		elif kind == "attack":
			_apply_attack_order(o["ids"], str(o.get("target_army_id", "")), int(o.get("target_unit", -1)))
			_queue_unresolved_client_attack(o["ids"], str(o.get("target_army_id", "")), int(o.get("target_unit", -1)))
		elif kind == "clear":
			var army = _find_army(str(o.get("aid", "")))
			if army != null and army.fc != null:
				army.fc.clear_order()
			elif not multiplayer.is_server():
				_pending_client_orders.append(o)

func _apply_spawn_march(ad: Dictionary, fc) -> void:
	if not ad.has("stop_x") or not ad.has("stop_y"):
		return
	var dest := snap_move_goal_xz(_clamp_map_v2(Vector2(float(ad.get("stop_x", 0.0)), float(ad.get("stop_y", 0.0)))))
	var facing: float = float(ad.get("stop_dir", ad.get("dir", -999.0)))
	var line_dir := -999.0
	if facing > -100.0:
		line_dir = _Formation.line_direction_for_front(facing)
	fc.issue_move(dest, line_dir, false)

## Server: create an army (FormationController in the sim + thin Army3D handle) with `soldiers`
## units at `pos` facing `dir` (front angle). Unit ids are allocated sequentially by the server.
func _create_army(aid: String, pid: int, pname: String, pos: Vector2, dir: float, equipment: Dictionary = {}) -> Node:
	var use_horse: bool = equipment.get("horse", false)
	var use_spear: bool = equipment.get("spear", false)
	var use_bow: bool = equipment.get("bow", false)
	var is_dragon: bool = equipment.get("dragon", false)
	var n: int = clampi(int(equipment.get("soldiers", DEFAULT_SOLDIERS_PER_ARMY)), 1, MAX_SOLDIERS_PER_ARMY)
	var utype: int = _UnitSim.UnitType.DRAGON if is_dragon else _UnitSim.unit_type_for_equipment(use_horse, use_spear, use_bow)
	var fc = _make_formation(aid, pid, pname, pos, dir, n, use_horse, use_spear, use_bow)
	var first_id := _next_unit_id
	_next_unit_id += n
	_sim.spawn_army_units(fc, first_id, n, utype)
	return _make_army_handle(aid, pid, pname, fc)

func _make_formation(aid: String, pid: int, pname: String, pos: Vector2, front_dir: float, n: int, use_horse: bool, use_spear: bool, use_bow: bool):
	var fc = _Formation.new()
	fc.army_id = aid
	fc.owner_pid = pid
	fc.owner_name = pname
	fc.is_npc = UNIT_SPRITE_PATHS.is_neutral_owner(pid)
	fc.initial_count = n
	fc.has_horse = use_horse
	fc.has_spear = use_spear
	fc.has_bow = use_bow
	fc.spacing = _Formation.MOUNTED_SPACING if use_horse else _Formation.FOOT_SPACING
	fc.rows = fc.default_rows_for(n)
	fc.direction = _Formation.line_direction_for_front(front_dir)
	fc.anchor = _clamp_map_v2(pos)
	fc.hold_position = fc.anchor
	_sim.add_army(fc)
	return fc

func _make_army_handle(aid: String, pid: int, pname: String, fc, color: String = "") -> Node:
	var army = _Army3D.new()
	army.setup(aid, pid, pname, fc)
	army.selection_changed.connect(_on_army_selection_changed)
	add_child(army)
	if _unit_renderer != null:
		if color.is_empty():
			color = "red" if fc.is_npc else UNIT_SPRITE_PATHS.color_folder_for_peer(pid)
		for id in fc.members:
			_unit_renderer.add_unit(id, color, _UnitSim.unit_type_name(_sim.utype[id]))
	return army

func _on_army_selection_changed(army, selected: bool) -> void:
	if _unit_renderer != null and army.fc != null:
		_unit_renderer.set_selected_ids(army.fc.members, selected)

func _serialize_armies() -> Array:
	var data := []
	for army in armies:
		data.append(_serialize_one_army(army))
	return data

func _serialize_armies_with_march(march_ids: Array, march_dests: PackedFloat32Array, march_dirs: PackedFloat32Array) -> Array:
	var data: Array = _serialize_armies()
	var dest_by_id := {}
	for k in range(march_ids.size()):
		dest_by_id[str(march_ids[k])] = k
	for payload in data:
		if typeof(payload) != TYPE_DICTIONARY:
			continue
		var k = dest_by_id.get(str(payload.get("army_id", "")), -1)
		if k < 0 or k * 2 + 1 >= march_dests.size():
			continue
		payload["stop_x"] = march_dests[k * 2]
		payload["stop_y"] = march_dests[k * 2 + 1]
		if k < march_dirs.size():
			payload["stop_dir"] = march_dirs[k]
	return data

## Compact spawn payload: ids are contiguous from `first_id`; positions as packed arrays.
func _serialize_one_army(army) -> Dictionary:
	var fc = army.fc
	var pp: Dictionary = _sim.army_positions(fc)
	var first_id: int = fc.members[0] if fc.members.size() > 0 else 0
	var utype: int = _sim.utype[first_id] if fc.members.size() > 0 else _UnitSim.UnitType.CLUBMAN
	return {
		"army_id": army.army_id,
		"pid": army.owner_id,
		"name": army.owner_name,
		"x": fc.anchor.x,
		"y": fc.anchor.y,
		"dir": fc.front_angle(),
		"count": fc.members.size(),
		"first_id": first_id,
		"type": utype,
		"spear": fc.has_spear,
		"horse": fc.has_horse,
		"bow": fc.has_bow,
		"stance": fc.stance,
		"xs": pp["xs"],
		"zs": pp["zs"],
	}

func _spawn_capture_points():
	for cfg in MapConfig.capture_points:
		_server_captures.append({
			"id": str(cfg.get("id", "")),
			"type": str(cfg.get("type", "")),
			"x": float(cfg.get("x", 0.0)),
			"y": float(cfg.get("y", 0.0)),
			"owner_pid": 0,
			"resource_timer": 0.0
		})
	var ids := []
	for c in _server_captures:
		ids.append(c["id"])
	print("TEST_CAPTURE_SPAWN: %d capture points spawned (%s)" % [_server_captures.size(), ", ".join(ids)])
	rpc("_client_spawn_capture_points", _serialize_capture_points())

func _serialize_capture_points() -> Array:
	var data := []
	for c in _server_captures:
		data.append({
			"id": c["id"],
			"type": c["type"],
			"x": c["x"],
			"y": c["y"],
			"owner_pid": c["owner_pid"]
		})
	return data

func _resource_dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for pid in a.keys():
		if not b.has(pid):
			return false
		var ra = a[pid]
		var rb = b[pid]
		if not (ra is Dictionary) or not (rb is Dictionary):
			return false
		if int(ra.get("horses", 0)) != int(rb.get("horses", 0)) \
				or int(ra.get("spears", 0)) != int(rb.get("spears", 0)) \
				or int(ra.get("bows", 0)) != int(rb.get("bows", 0)) \
				or int(ra.get("villagers", 0)) != int(rb.get("villagers", 0)):
			return false
	return true

func _sync_capture_state():
	var cp_data := []
	var dirty_cps := []
	for c in _server_captures:
		var owner_name := "---"
		if c["owner_pid"] != 0 and GameState.players.has(c["owner_pid"]):
			owner_name = GameState.players[c["owner_pid"]]["name"]
		var entry := {
			"id": c["id"],
			"type": c["type"],
			"owner_pid": c["owner_pid"],
			"owner_name": owner_name,
		}
		cp_data.append(entry)
		var prev_owner = _last_sent_cp_owner.get(c["id"], null)
		if prev_owner == null or int(prev_owner) != int(c["owner_pid"]):
			dirty_cps.append(entry)
	var res_data := {}
	for pid in GameState.resources.keys():
		res_data[pid] = GameState.resources[pid]
	var res_changed := not _resource_dicts_equal(res_data, _last_sent_resources)
	if _capture_hud_sent and dirty_cps.is_empty() and not res_changed:
		return
	var to_send: Array = cp_data if not _capture_hud_sent else dirty_cps
	var batch_count := int(ceil(float(to_send.size()) / float(CAPTURE_SYNC_BATCH_SIZE)))
	if batch_count == 0:
		batch_count = 1
	for b in range(batch_count):
		var start := b * CAPTURE_SYNC_BATCH_SIZE
		var batch = to_send.slice(start, start + CAPTURE_SYNC_BATCH_SIZE)
		var res_batch := res_data if b == batch_count - 1 else {}
		rpc("_client_update_capture", batch, res_batch)
	_update_topbar_local(cp_data, res_data)
	_last_sent_cp_owner.clear()
	for d in cp_data:
		_last_sent_cp_owner[d["id"]] = d["owner_pid"]
	_last_sent_resources = res_data.duplicate(true)
	_capture_hud_sent = true

func _get_closest_enemy_army(army) -> Node:
	var best = null
	var best_dist := 1e10
	var a_xz: Vector2 = _sim.army_centroid(army.fc)
	for a in armies:
		if a.owner_id == army.owner_id or a.is_routed or a.fc == null:
			continue
		if UNIT_SPRITE_PATHS.is_neutral_owner(a.owner_id) and UNIT_SPRITE_PATHS.is_neutral_owner(army.owner_id):
			continue
		var d = a_xz.distance_to(_sim.army_centroid(a.fc))
		if d < best_dist:
			best_dist = d
			best = a
	return best

## Living unit ids within `radius` of `center` (spatial hash; valid after the first sim tick).
func get_units_in_radius(center: Vector2, radius: float) -> PackedInt32Array:
	if _sim == null:
		return PackedInt32Array()
	return _sim.units_in_radius(center, radius)

func _server_capture_and_resources(delta: float):
	if not multiplayer.is_server() or _sim == null:
		return
	for c in _server_captures:
		var nearby_pids := {}
		var center = Vector2(c["x"], c["y"])
		for id in _sim.units_in_radius(center, CP_CAPTURE_RADIUS):
			var pid: int = _sim.owner_pid[id]
			if UNIT_SPRITE_PATHS.is_neutral_owner(pid):
				continue
			nearby_pids[pid] = true
		if nearby_pids.size() == 1:
			var new_owner = nearby_pids.keys()[0]
			if new_owner != c["owner_pid"]:
				var old_owner = c["owner_pid"]
				c["owner_pid"] = new_owner
				var owner_name = GameState.players[new_owner]["name"] if GameState.players.has(new_owner) else str(new_owner)
				if old_owner == 0:
					print("TEST_CAPTURE: %s '%s' captured by %s (pid=%d)" % [c["type"], c["id"], owner_name, new_owner])
				else:
					print("TEST_CAPTURE: %s '%s' taken over by %s (pid=%d)" % [c["type"], c["id"], owner_name, new_owner])
				# Player-specific control markers (match tests.json events).
				if owner_name == "A" and c["id"] == "Stables":
					print("TEST_A_CONTROLS_STABLES: Player A controls Stables")
				elif owner_name == "B" and c["id"] == "Blacksmith":
					print("TEST_B_CONTROLS_BLACKSMITH: Player B controls Blacksmith")
				elif owner_name == "A" and c["id"] == "Blacksmith":
					print("TEST_A_CONTROLS_BLACKSMITH: Player A controls Blacksmith")
				elif owner_name == "B" and c["id"] == "Stables":
					print("TEST_B_CONTROLS_STABLES: Player B controls Stables")
		if c["owner_pid"] != 0:
			c["resource_timer"] = float(c.get("resource_timer", 0.0)) + delta
			if c["resource_timer"] >= CP_RESOURCE_INTERVAL:
				c["resource_timer"] -= CP_RESOURCE_INTERVAL
				var cp_type: String = str(c["type"])
				var key: String = CP_RESOURCE_BY_TYPE.get(cp_type, "")
				if key.is_empty():
					continue
				if not GameState.resources.has(c["owner_pid"]):
					GameState.resources[c["owner_pid"]] = GameState.default_resources()
				GameState.resources[c["owner_pid"]][key] += 1
				var total = GameState.resources[c["owner_pid"]][key]
				print("TEST_RESOURCE: %s '%s' produced 1 %s for pid=%d (total=%d)" % [c["type"], c["id"], key, c["owner_pid"], total])

var _aggressive_timer: float = 0.0
const AGGRESSIVE_TICK_INTERVAL := 1.0
## Hard cap on a single automated match; if exceeded the server declares a timeout
## game-over so the test never hangs forever.
const MATCH_TIMEOUT_SECONDS := 120.0
var _match_elapsed: float = 0.0
var _match_started: bool = false
var _clients_world_ready: Dictionary = {}

## Server: aggressive stance with no explicit order — chase closest enemy periodically.
## Server: aggressive stance with no explicit order — engage the closest enemy army periodically.
func _update_aggressive_armies(delta: float):
	_aggressive_timer += delta
	if _aggressive_timer < AGGRESSIVE_TICK_INTERVAL:
		return
	_aggressive_timer = 0.0
	for a in armies:
		if a == null or not is_instance_valid(a) or a.is_routed or a.fc == null:
			continue
		if UNIT_SPRITE_PATHS.is_neutral_owner(a.owner_id):
			continue
		var fc = a.fc
		if fc.stance != _Formation.Stance.AGGRESSIVE:
			continue
		if fc.has_player_order():
			# Stay locked while closing or fighting. If they have fallen out of
			# contact, pick the closest enemy again so swapped blobs re-engage.
			var now := Time.get_ticks_msec() / 1000.0
			if fc.order_type != _Formation.OrderType.ATTACK or GameState.last_combat_time < 0.0 or (now - GameState.last_combat_time) < 4.0:
				continue
		var enemy = _get_closest_enemy_army(a)
		if enemy == null or enemy.fc == null:
			continue
		if fc.order_type == _Formation.OrderType.ATTACK and fc.order_target_army == enemy.fc.index:
			continue
		_apply_attack_order([a.army_id], enemy.army_id, -1)
		rpc("_client_order_attack", _stamp_order(), _sim.tick, [a.army_id], enemy.army_id, -1)
		var exz: Vector2 = _sim.army_centroid(enemy.fc)
		print("TEST_AGGRESSIVE_TICK: army=%s owner=%s target_enemy=%s at=(%d,%d)" % [
			a.army_id, a.owner_name, enemy.army_id, int(exz.x), int(exz.y)
		])

func _physics_process(delta: float):
	if preview_only or _sim == null:
		return
	var t0 := Time.get_ticks_usec()
	if multiplayer.is_server():
		if game_over:
			return
		_check_match_timeout(delta)
		if game_over:
			return
		_server_capture_and_resources(delta)
		_update_aggressive_armies(delta)
		_update_map_dragon_ai(delta)
		_step_sim(delta)
		sync_timer += delta
		if sync_timer >= 0.5:
			sync_timer = 0.0
			_sync_capture_state()
	else:
		if not _multiplayer_active() and not _local_sim_enabled:
			return
		_step_sim(delta)
	if _perf_monitor != null:
		_perf_monitor.record_physics_ms(float(Time.get_ticks_usec() - t0) / 1000.0)

## Server: after every sim tick send batched events (reliable) and prioritised snapshots.
func _server_after_tick() -> void:
	if not _all_clients_world_ready():
		_sim.died_ids.clear()
		_sim.routed_armies.clear()
		return
	if _sim.died_ids.size() > 0:
		rpc("_client_units_died", _sim.died_ids.duplicate())
	for ai in _sim.routed_armies:
		var fc = _sim.armies[ai]
		var army = _find_army(fc.army_id)
		if army != null:
			_on_army_routed(army)
	if _sim.arrows.size() > 0:
		rpc("_client_arrows", _sim.arrows.duplicate())
	_sim.died_ids.clear()
	_sim.routed_armies.clear()
	var budget: int = _net.budget_for(_sim.alive_count)
	var ids: PackedInt32Array = _net.select_units(_sim, _sim.tick, budget)
	if ids.is_empty():
		return
	for chunk in _net.pack_chunks(_sim, ids, _sim.tick):
		rpc("_client_snapshot", chunk)
		_snapshot_bytes_sent += chunk.size()

func _client_after_tick() -> void:
	if _sim.died_ids.size() > 0:
		# Local (non-authoritative) sims never kill units; this only fires for reconciled deaths.
		_sim.died_ids.clear()
	_sim.routed_armies.clear()
	if _sim.move_oscillation and not _move_osc_logged:
		_move_osc_logged = true
		print("TEST_MOVE_OSCILLATION_FAIL: unit=%d reversals=%d window=2.0s" % [
			_sim.move_oscillation_id, _sim.move_oscillation_count
		])
	if _unit_renderer != null:
		_unit_renderer.write_tick()
	if _unit_audio != null:
		_unit_audio.tick()

## Snapshot: packed unit records (see sim/NetSync.gd). Stale records are dropped per unit.
@rpc("authority", "unreliable_ordered")
func _client_snapshot(bytes: PackedByteArray) -> void:
	if _sim == null or _net == null:
		return
	var snap: Dictionary = _net.unpack(bytes)
	if snap.is_empty():
		return
	_net.apply_snapshot(_sim, snap)
	if _sim.died_ids.size() > 0:
		_sim.died_ids.clear()

@rpc("authority", "reliable")
func _client_units_died(ids: PackedInt32Array) -> void:
	if _sim == null:
		return
	_sim.kill_units(ids)
	_sim.died_ids.clear()
	if _unit_audio != null:
		_unit_audio.on_deaths(ids)

## Batched arrows for this tick: [from_x, from_z, to_x, to_z, duration, peak, ...] (map coords).
@rpc("authority", "unreliable")
func _client_arrows(data: PackedFloat32Array) -> void:
	var n := int(data.size() / 6)
	var shown := mini(n, MAX_ARROWS_PER_TICK)
	for k in range(shown):
		var o := k * 6
		var arrow := Node3D.new()
		arrow.set_script(_ArrowProjectile)
		add_child(arrow)
		var from := Vector3(data[o], get_ground_height_at(data[o], data[o + 1]) + UNIT_HALF_HEIGHT, data[o + 1])
		var to := Vector3(data[o + 2], get_ground_height_at(data[o + 2], data[o + 3]) + UNIT_HALF_HEIGHT, data[o + 3])
		arrow.setup(from, to, data[o + 4], data[o + 5])

func _check_match_timeout(delta: float) -> void:
	if not _match_started or game_over:
		return
	# The timeout is a safety net for automated tests only; in human play we
	# want the match to continue until someone actually wins (no draw).
	if not GameState.is_auto_test:
		return
	_match_elapsed += delta
	if _match_elapsed < MATCH_TIMEOUT_SECONDS:
		return
	game_over = true
	print("TEST_GAME_OVER_TIMEOUT: match exceeded %.0f seconds, forcing game over" % MATCH_TIMEOUT_SECONDS)
	# Pick whichever side has more non-routed armies as the winner; tie → draw.
	var counts := {}
	var names := {}
	for a in armies:
		if a and is_instance_valid(a) and not a.is_routed and not UNIT_SPRITE_PATHS.is_neutral_owner(a.owner_id):
			counts[a.owner_id] = int(counts.get(a.owner_id, 0)) + 1
			names[a.owner_id] = a.owner_name
	var winner_pid := 0
	var winner_count := -1
	var tied := false
	for pid in counts.keys():
		var c: int = counts[pid]
		if c > winner_count:
			winner_count = c
			winner_pid = pid
			tied = false
		elif c == winner_count:
			tied = true
	var winner_name := ""
	if winner_pid != 0 and not tied:
		winner_name = str(names[winner_pid])
	print("TEST_GAME_OVER: Timeout reached. Winner: %s" % (winner_name if winner_name != "" else "(draw)"))
	rpc("_announce_winner", winner_name)
	_announce_winner(winner_name)

func _on_army_routed(army):
	if game_over:
		return
	rpc("_client_army_routed", army.army_id)
	if army in selected_armies:
		selected_armies.erase(army)
	var loser_pid = army.owner_id
	var loser_name = army.owner_name
	if UNIT_SPRITE_PATHS.is_neutral_owner(loser_pid):
		print("TEST_MAP_DRAGON_DEAD: %s" % army.army_id)
		return
	var all_routed = true
	for a in armies:
		if a.owner_id == loser_pid and not a.is_routed:
			all_routed = false
			break
	if all_routed:
		print("TEST_PLAYER_ELIMINATED: Player '%s' has no armies left (all routed)" % loser_name)
	var players_with_armies := {}
	for a in armies:
		if not a.is_routed and not UNIT_SPRITE_PATHS.is_neutral_owner(a.owner_id):
			players_with_armies[a.owner_id] = a.owner_name
	if players_with_armies.size() == 1:
		game_over = true
		var winner_name = players_with_armies.values()[0]
		print("TEST_GAME_OVER: Last player standing. Winner: %s" % winner_name)
		rpc("_announce_winner", winner_name)
		_announce_winner(winner_name)
	elif players_with_armies.size() == 0:
		game_over = true
		print("TEST_GAME_OVER: Draw (no armies left)")
		rpc("_announce_winner", "")
		_announce_winner("")

func _raycast_ground() -> Vector3:
	return _raycast_ground_at_screen(get_viewport().get_mouse_position())

func _terrain_in_map_bounds(x: float, z: float) -> bool:
	return x >= 0.0 and z >= 0.0 and x <= MapConfig.width and z <= MapConfig.height

func _ray_param_from(from: Vector3, dir: Vector3, pt: Vector3) -> float:
	return (pt - from).dot(dir)

## Terrain pick: closest hit along the camera ray. Grid crossings are preferred over a later
## trimesh hit — shallow rays can skim peak trimesh and strike the backslope instead.
func _raycast_ground_at_screen(screen: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	return _raycast_ground_along_camera_ray(from, dir)

## Collect every ray/terrain Y-crossing along the camera ray (not just the first).
func _terrain_grid_crossings_along_ray(from: Vector3, to: Vector3) -> Array:
	var out: Array = []
	if _terrain_heights.is_empty():
		return out
	var dir := to - from
	var ray_len := dir.length()
	if ray_len < 0.001:
		return out
	dir /= ray_len
	var step := maxf(_terrain_step * 0.25, 2.0)
	var max_steps := mini(ceili(ray_len / step) + 4, 2048)
	var traveled := 0.0
	var prev := from
	var prev_in_bounds := _terrain_in_map_bounds(prev.x, prev.z)
	var steps := 0
	while traveled <= ray_len and steps < max_steps:
		steps += 1
		var seg_end := minf(traveled + step, ray_len)
		var p := from + dir * seg_end
		var in_bounds := _terrain_in_map_bounds(p.x, p.z)
		if prev_in_bounds and in_bounds:
			var gy := _terrain_grid_height_at(p.x, p.z)
			var prev_gy := _terrain_grid_height_at(prev.x, prev.z)
			if prev.y >= prev_gy - 0.01 and p.y <= gy + 0.05:
				var above0 := prev.y - prev_gy
				var above1 := p.y - gy
				var denom := above0 - above1
				var frac := 0.5
				if absf(denom) > 0.0001:
					frac = clampf(above0 / denom, 0.0, 1.0)
				var hit := prev.lerp(p, frac)
				hit.y = _terrain_grid_height_at(hit.x, hit.z)
				out.append(hit)
		prev = p
		prev_in_bounds = in_bounds
		traveled = seg_end
	return out

## First crossing only; used by tests and legacy callers.
func _raycast_terrain_grid_along_ray(from: Vector3, to: Vector3) -> Vector3:
	var crossings := _terrain_grid_crossings_along_ray(from, to)
	if crossings.is_empty():
		return Vector3.ZERO
	return crossings[0]

func _rect_from_points(a: Vector2, b: Vector2) -> Rect2:
	var p := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var s := (a - b).abs()
	return Rect2(p, s)

func _clear_selection():
	for a in selected_armies:
		if a and is_instance_valid(a):
			a.deselect()
	selected_armies.clear()
	if _army_command_bar != null:
		_army_command_bar.set_visible_bar(false)

func _set_selection(new_armies: Array):
	_clear_selection()
	for a in new_armies:
		if a and is_instance_valid(a) and not a.is_routed:
			selected_armies.append(a)
			a.select()
	if _army_command_bar != null:
		_army_command_bar.set_visible_bar(selected_armies.size() > 0)

func _get_selected_non_routed() -> Array:
	var out := []
	for a in selected_armies:
		if a and is_instance_valid(a) and not a.is_routed:
			out.append(a)
	return out

## Marquee: an army is picked when any living soldier projects inside the screen rect.
func _armies_in_screen_rect_3d(rect: Rect2, my_id: int) -> Array:
	var out := []
	if _camera == null or _sim == null:
		return out
	for army in armies:
		if army.owner_id != my_id or army.is_routed or army.fc == null:
			continue
		var any_inside := false
		for id in army.fc.members:
			if not _sim.is_alive(id):
				continue
			var x: float = _sim.pos_x[id]
			var z: float = _sim.pos_z[id]
			var sp := _camera.unproject_position(Vector3(x, get_ground_height_at(x, z) + UNIT_HALF_HEIGHT, z))
			if rect.has_point(sp):
				any_inside = true
				break
		if any_inside:
			out.append(army)
	return out

func _clamp_map_v2(v: Vector2) -> Vector2:
	return Vector2(clampf(v.x, 0, MapConfig.width), clampf(v.y, 0, MapConfig.height))

func _is_attack_move_mode() -> bool:
	return _army_command_bar != null \
		and _army_command_bar.get_order_mode() == _ArmyCommandBar.OrderMode.ATTACK_MOVE

## Single RMB click: the selected group's centroid goes to the click; each army keeps its
## offset from that centroid. Facing follows travel direction. Instant local click marker.
func _issue_group_move_click(click_xz: Vector2):
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var click_c := snap_move_goal_xz(_clamp_map_v2(click_xz))
	var centroid := Vector2.ZERO
	var centres: Array = []
	for a in sel:
		var c: Vector2 = _sim.army_centroid(a.fc)
		centres.append(c)
		centroid += c
	centroid /= float(sel.size())
	var ids: Array = []
	var dests := PackedFloat32Array()
	var facings := PackedFloat32Array()
	for k in range(sel.size()):
		var d: Vector2 = _clamp_map_v2(click_c + (centres[k] - centroid))
		ids.append(sel[k].army_id)
		dests.append(d.x)
		dests.append(d.y)
		facings.append(-999.0)
	var marker = "TEST_009_MOVE" if GameState.local_player_name == "A" else "TEST_009_MOVE_B"
	print("%s: Group move %d armies to click (%d,%d)" % [marker, ids.size(), int(click_c.x), int(click_c.y)])
	_show_click_marker(click_c)
	rpc_id(1, "_server_order_move", ids, dests, facings, PackedFloat32Array(), _is_attack_move_mode())

func _show_click_marker(p: Vector2) -> void:
	if _click_marker == null:
		_click_marker = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 6.0
		cm.bottom_radius = 6.0
		cm.height = 0.3
		_click_marker.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 1.0, 0.4, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_click_marker.material_override = mat
		add_child(_click_marker)
	_click_marker.position = Vector3(p.x, get_ground_height_at(p.x, p.y) + 0.3, p.y)
	_click_marker.visible = true
	_click_marker_t = 0.6

func _update_click_marker(delta: float) -> void:
	if _click_marker == null or not _click_marker.visible:
		return
	_click_marker_t -= delta
	if _click_marker_t <= 0.0:
		_click_marker.visible = false

func _ensure_ghost_marker_material(valid: bool = true) -> StandardMaterial3D:
	if valid:
		if _ghost_marker_mat == null:
			_ghost_marker_mat = StandardMaterial3D.new()
			_ghost_marker_mat.albedo_color = Color(0.35, 0.85, 0.45, 0.35)
			_ghost_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_ghost_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_ghost_marker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return _ghost_marker_mat
	if _ghost_marker_invalid_mat == null:
		_ghost_marker_invalid_mat = StandardMaterial3D.new()
		_ghost_marker_invalid_mat.albedo_color = Color(0.85, 0.25, 0.25, 0.45)
		_ghost_marker_invalid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_marker_invalid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ghost_marker_invalid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _ghost_marker_invalid_mat

func _selection_counts_and_mounts(sel: Array) -> Dictionary:
	var counts: Array = []
	var mounted: Array = []
	for a in sel:
		counts.append(_sim.army_alive_count(a.fc))
		mounted.append(a.has_horse)
	return {"counts": counts, "mounted": mounted}

func _update_formation_ghosts_3d(line_start: Vector2, line_end: Vector2):
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var cm := _selection_counts_and_mounts(sel)
	var positions: Array[Vector2] = _GroupFormation.preview_positions(line_start, line_end, cm["counts"], cm["mounted"])
	if positions.is_empty():
		return
	if _ghost_root_3d == null:
		_ghost_root_3d = Node3D.new()
		_ghost_root_3d.name = "FormationGhosts3D"
		add_child(_ghost_root_3d)
	var mat := _ensure_ghost_marker_material(true)
	var invalid_mat := _ensure_ghost_marker_material(false)
	var ghosts: Array = _ghost_root_3d.get_children()
	var shown: int = mini(positions.size(), MAX_GHOST_MARKERS)
	while ghosts.size() < shown:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(12, 4, 12)
		box.mesh = bm
		box.material_override = mat
		_ghost_root_3d.add_child(box)
		ghosts.append(box)
	for i in range(ghosts.size()):
		var box: MeshInstance3D = ghosts[i]
		if i >= shown:
			box.visible = false
			continue
		var p: Vector2 = positions[i]
		box.visible = true
		box.position = Vector3(p.x, get_ground_height_at(p.x, p.y) + 2.0, p.y)
		box.material_override = mat if is_walkable_at(p.x, p.y) else invalid_mat

func _clear_formation_ghosts_3d():
	if _ghost_root_3d:
		for c in _ghost_root_3d.get_children():
			c.visible = false

## RMB drag: each selected army gets its own sub-segment of the drag line; the formation is
## centred on the segment, as wide as the segment allows, facing away from the drag rear.
func _commit_group_formation_line_3d(line_start: Vector2, line_end: Vector2):
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var segs: Array = _GroupFormation.split_segments(line_start, line_end, sel.size())
	var ids: Array = []
	var dests := PackedFloat32Array()
	var facings := PackedFloat32Array()
	var widths := PackedFloat32Array()
	var front := _GroupFormation.front_angle_for_segment(line_start, line_end)
	for k in range(sel.size()):
		var seg: Dictionary = segs[k]
		var s: Vector2 = seg["start"]
		var e: Vector2 = seg["end"]
		var mid := _clamp_map_v2((s + e) * 0.5)
		ids.append(sel[k].army_id)
		dests.append(mid.x)
		dests.append(mid.y)
		facings.append(front)
		widths.append(s.distance_to(e))
	_show_click_marker((line_start + line_end) * 0.5)
	rpc_id(1, "_server_order_move", ids, dests, facings, widths, _is_attack_move_mode())

func _handle_world3d_mouse_extended(event: InputEvent):
	var my_id := multiplayer.get_unique_id()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var screen_pos := mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_marquee_start_screen = screen_pos
				_marquee_end_screen = screen_pos
				_marquee_active = true
				_marquee_moved = false
				if _marquee_overlay:
					_marquee_overlay.set_marquee_rect(Rect2(), false)
			else:
				if _marquee_active:
					if _marquee_moved:
						var r := _rect_from_points(_marquee_start_screen, _marquee_end_screen)
						var picked := _armies_in_screen_rect_3d(r, my_id)
						_set_selection(picked)
					else:
						var hit := _raycast_ground_at_screen(_marquee_start_screen)
						if hit != Vector3.ZERO:
							var click_xz := Vector2(hit.x, hit.z)
							if _army_command_bar != null \
									and _army_command_bar.get_order_mode() == _ArmyCommandBar.OrderMode.ATTACK \
									and not _get_selected_non_routed().is_empty():
								_issue_armies_attack_at(click_xz)
							else:
								var army = _get_army_at(click_xz, my_id)
								if army:
									_set_selection([army])
								else:
									_clear_selection()
						else:
							_clear_selection()
				_marquee_active = false
				if _marquee_overlay:
					_marquee_overlay.set_marquee_rect(Rect2(), false)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_rmb_press_screen = screen_pos
				var gh := _raycast_ground_at_screen(screen_pos)
				_rmb_press_ground = Vector2(gh.x, gh.z) if gh != Vector3.ZERO else Vector2.ZERO
				_rmb_drag_active = gh != Vector3.ZERO
				_clear_formation_ghosts_3d()
			else:
				if _rmb_drag_active:
					var gh2 := _raycast_ground_at_screen(screen_pos)
					var world_xz := Vector2(gh2.x, gh2.z) if gh2 != Vector3.ZERO else _rmb_press_ground
					var drag_len := _rmb_press_screen.distance_to(screen_pos)
					if drag_len < RMB_DRAG_CLICK_THRESHOLD:
						_issue_group_move_click(world_xz)
					else:
						_commit_group_formation_line_3d(_rmb_press_ground, world_xz)
				_rmb_drag_active = false
				_clear_formation_ghosts_3d()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var screen_pos := mm.position
		if _marquee_active:
			_marquee_end_screen = screen_pos
			if _marquee_start_screen.distance_to(_marquee_end_screen) >= MARQUEE_DRAG_THRESHOLD:
				_marquee_moved = true
				if _marquee_overlay:
					_marquee_overlay.set_marquee_rect(_rect_from_points(_marquee_start_screen, _marquee_end_screen), true)
		if _rmb_drag_active:
			var gh := _raycast_ground_at_screen(screen_pos)
			if gh != Vector3.ZERO:
				var cur := Vector2(gh.x, gh.z)
				_update_formation_ghosts_3d(_rmb_press_ground, cur)

func _handle_key(event: InputEventKey):
	if event is InputEventKey and event.pressed and not event.echo:
		if _army_command_bar != null:
			if event.keycode == KEY_M:
				_army_command_bar._set_order_mode(_ArmyCommandBar.OrderMode.MOVE)
			elif event.keycode == KEY_A:
				_army_command_bar._set_order_mode(_ArmyCommandBar.OrderMode.ATTACK)
			elif event.keycode == KEY_G:
				_army_command_bar._set_order_mode(_ArmyCommandBar.OrderMode.ATTACK_MOVE)
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var rotate_amount := deg_to_rad(15.0)
	if event.keycode == KEY_LEFT or event.keycode == KEY_Q:
		for army in sel:
			rpc_id(1, "_server_rotate_army", army.army_id, -rotate_amount)
	elif event.keycode == KEY_RIGHT or event.keycode == KEY_E:
		for army in sel:
			rpc_id(1, "_server_rotate_army", army.army_id, rotate_amount)

func _on_command_bar_stance(stance: int) -> void:
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var ids: Array = []
	for a in sel:
		ids.append(a.army_id)
	rpc_id(1, "_server_armies_set_stance", ids, stance)

func _get_enemy_army_at(pos_2d: Vector2, for_peer_id: int):
	var best = null
	var best_dist = ARMY_CLICK_RADIUS
	for army in armies:
		if army.owner_id == for_peer_id or army.is_routed or army.fc == null:
			continue
		if _sim.army_alive_count(army.fc) == 0:
			continue
		var dist = pos_2d.distance_to(_sim.army_centroid(army.fc))
		if dist < best_dist:
			best_dist = dist
			best = army
	return best

## Nearest hostile unit id near the click (dragons included), or -1.
func _get_attackable_unit_at(pos_2d: Vector2, for_peer_id: int) -> int:
	return _sim.nearest_unit(pos_2d, ARMY_CLICK_RADIUS, for_peer_id, false)

func _issue_armies_attack_at(pos: Vector2) -> void:
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var my_id := multiplayer.get_unique_id()
	var ids: Array = []
	for a in sel:
		ids.append(a.army_id)
	var enemy_army = _get_enemy_army_at(pos, my_id)
	if enemy_army != null:
		_show_click_marker(pos)
		rpc_id(1, "_server_armies_order_attack", ids, enemy_army.army_id, -1)
		return
	var unit := _get_attackable_unit_at(pos, my_id)
	if unit >= 0:
		_show_click_marker(pos)
		rpc_id(1, "_server_armies_order_attack", ids, "", unit)

func _issue_armies_attack_move_3d(dest: Vector2) -> void:
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var ids: Array = []
	for a in sel:
		ids.append(a.army_id)
	var dest_c := _clamp_map_v2(dest)
	rpc_id(1, "_server_armies_order_attack_move", ids, dest_c.x, dest_c.y)

func _get_army_at(pos_2d: Vector2, peer_id: int):
	var best = null
	var best_dist = ARMY_CLICK_RADIUS
	for army in armies:
		if army.owner_id != peer_id or army.is_routed or army.fc == null:
			continue
		# Distance to the nearest soldier, so wide formations are clickable anywhere.
		var d := 1e10
		for id in army.fc.members:
			if not _sim.is_alive(id):
				continue
			var dx: float = _sim.pos_x[id] - pos_2d.x
			var dz: float = _sim.pos_z[id] - pos_2d.y
			d = minf(d, sqrt(dx * dx + dz * dz))
		if d < best_dist:
			best_dist = d
			best = army
	return best

func _find_army(aid: String):
	var a = _army_by_id.get(aid, null)
	if a != null and is_instance_valid(a):
		return a
	for army in armies:
		if army.army_id == aid:
			_army_by_id[aid] = army
			return army
	return null

func _terrain_grid_height_at(x: float, z: float) -> float:
	if _terrain_heights.is_empty() or _terrain_cols < 2 or _terrain_rows < 2:
		return 0.0
	var gx: float = clampf(x / _terrain_step, 0.0, float(_terrain_cols - 1))
	var gz: float = clampf(z / _terrain_step, 0.0, float(_terrain_rows - 1))
	var i0: int = int(floor(gx))
	var j0: int = int(floor(gz))
	var i1: int = mini(i0 + 1, _terrain_cols - 1)
	var j1: int = mini(j0 + 1, _terrain_rows - 1)
	var tx: float = gx - float(i0)
	var tz: float = gz - float(j0)
	var h00: float = _terrain_heights[j0 * _terrain_cols + i0]
	var h10: float = _terrain_heights[j0 * _terrain_cols + i1]
	var h01: float = _terrain_heights[j1 * _terrain_cols + i0]
	var h11: float = _terrain_heights[j1 * _terrain_cols + i1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

## Bilinear lookup in the terrain height grid (the same samples the ground mesh was built
## from). This is called per unit per tick, so it must never hit the physics server.
func get_ground_height_at(x: float, z: float) -> float:
	return _terrain_grid_height_at(x, z)

func _add_play_boundary_line():
	var existing := get_node_or_null("PlayBoundary")
	if existing:
		existing.queue_free()
	var root := Node3D.new()
	root.name = "PlayBoundary"
	add_child(root)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.2, 1.0)
	var line_height := 0.2
	var line_width := 4.0
	# Left edge
	var box_left = BoxMesh.new()
	box_left.size = Vector3(line_width, line_height, MapConfig.height)
	var left = MeshInstance3D.new()
	left.mesh = box_left
	left.position = Vector3(0.0, 0.1, MapConfig.height / 2.0)
	left.material_override = mat
	root.add_child(left)
	# Right edge
	var box_right = BoxMesh.new()
	box_right.size = Vector3(line_width, line_height, MapConfig.height)
	var right = MeshInstance3D.new()
	right.mesh = box_right
	right.position = Vector3(MapConfig.width, 0.1, MapConfig.height / 2.0)
	right.material_override = mat
	root.add_child(right)
	# Bottom edge
	var box_bottom = BoxMesh.new()
	box_bottom.size = Vector3(MapConfig.width, line_height, line_width)
	var bottom = MeshInstance3D.new()
	bottom.mesh = box_bottom
	bottom.position = Vector3(MapConfig.width / 2.0, 0.1, 0.0)
	bottom.material_override = mat
	root.add_child(bottom)
	# Top edge
	var box_top = BoxMesh.new()
	box_top.size = Vector3(MapConfig.width, line_height, line_width)
	var top = MeshInstance3D.new()
	top.mesh = box_top
	top.position = Vector3(MapConfig.width / 2.0, 0.1, MapConfig.height)
	top.material_override = mat
	root.add_child(top)

@rpc("authority", "reliable")
func _client_spawn_armies(data: Array):
	# One frame later: ensures this node and the renderer are fully in the tree.
	call_deferred("_client_spawn_armies_impl", data)

## Client (and headless tests): build armies + units in the local sim from the compact payload
## produced by `_serialize_one_army`. Ids come from the server so snapshots address the same units.
func _client_spawn_armies_impl(data: Array):
	for ad in data:
		if typeof(ad) != TYPE_DICTIONARY:
			continue
		_client_spawn_one_army(ad, "")
	_flush_pending_client_orders()
	print("TEST_ARMIES_SPAWNED: Client received %d armies" % armies.size())
	print("TEST_3D_CLIENT_UNITS_SPAWNED: units=%d armies=%d" % [_alive_unit_count(), armies.size()])
	_schedule_visibility_checks()

func _client_spawn_one_army(ad: Dictionary, color: String) -> Node:
	var aid := str(ad.get("army_id", ""))
	if aid.is_empty() or _find_army(aid) != null:
		return null
	var pid := int(ad.get("pid", 0))
	var pname := str(ad.get("name", ""))
	var use_horse: bool = ad.get("horse", false)
	var use_spear: bool = ad.get("spear", false)
	var use_bow: bool = ad.get("bow", false)
	var n := int(ad.get("count", 0))
	var xs: PackedFloat32Array = ad.get("xs", PackedFloat32Array())
	var zs: PackedFloat32Array = ad.get("zs", PackedFloat32Array())
	if n <= 0:
		n = xs.size()
	var first_id := int(ad.get("first_id", _next_unit_id))
	var utype := int(ad.get("type", _UnitSim.unit_type_for_equipment(use_horse, use_spear, use_bow)))
	var pos := Vector2(float(ad.get("x", 0.0)), float(ad.get("y", 0.0)))
	var fc = _make_formation(aid, pid, pname, pos, float(ad.get("dir", 0.0)), n, use_horse, use_spear, use_bow)
	fc.stance = int(ad.get("stance", fc.stance))
	_sim.spawn_army_units(fc, first_id, n, utype, xs, zs)
	_next_unit_id = maxi(_next_unit_id, first_id + n)
	_apply_spawn_march(ad, fc)
	var army = _make_army_handle(aid, pid, pname, fc, color)
	armies.append(army)
	_flush_pending_client_orders()
	return army

@rpc("authority", "reliable")
func _client_spawn_dragons(data: Array) -> void:
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var army = _client_spawn_one_army(entry, str(entry.get("color", "red")))
		if army != null:
			_map_dragons.append(army)
			var pos := Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
			print("TEST_MAP_DRAGON_SPAWN: client dragon %d at (%d,%d)" % [int(entry.get("index", 0)), int(pos.x), int(pos.y)])

func _load_image_texture(path: String) -> Texture2D:
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is Texture2D:
			return res as Texture2D
	push_warning("Texture not found at %s" % path)
	return null

func _capture_point_texture(cp_type: String) -> Texture2D:
	match cp_type:
		"Blacksmith":
			return _load_image_texture(CP_BLACKSMITH_TEXTURE_PATH)
		"Village":
			return _load_image_texture(CP_VILLAGE_TEXTURE_PATH)
		"Archery":
			return _load_image_texture(CP_ARCHERY_TEXTURE_PATH)
		_:
			return _load_image_texture(CP_STABLES_TEXTURE_PATH)

func _capture_point_modulate(owner_pid: int) -> Color:
	if owner_pid != 0 and owner_pid in GameState.players:
		var ci = GameState.players[owner_pid].get("color_index", 0)
		if ci >= 0 and ci < GameState.PLAYER_COLORS.size():
			return GameState.PLAYER_COLORS[ci]
	return Color(1.0, 1.0, 1.0, 1.0)

func _create_capture_point_sprite(d: Dictionary) -> Node3D:
	var anchor := Node3D.new()
	var gx := float(d["x"])
	var gz := float(d["y"])
	anchor.position = Vector3(gx, get_ground_height_at(gx, gz), gz)
	anchor.name = "CP_%s" % d["id"]
	var tex := _capture_point_texture(str(d.get("type", d["id"])))
	if tex == null:
		push_error("Capture point '%s' missing texture" % d["id"])
		return null
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	var tex_h := float(tex.get_height())
	var pixel_size := CP_SPRITE_WORLD_HEIGHT / tex_h
	sprite.pixel_size = pixel_size
	sprite.modulate = _capture_point_modulate(int(d.get("owner_pid", 0)))
	# Sprite3D origin is center; lift so opaque base sits on terrain.
	sprite.position.y = tex_h * pixel_size * 0.5
	anchor.add_child(sprite)
	return anchor

@rpc("authority", "reliable")
func _client_spawn_capture_points(data: Array):
	for d in data:
		GameState.capture_points[d["id"]] = ""
		var anchor := _create_capture_point_sprite(d)
		if anchor == null:
			continue
		add_child(anchor)
		capture_points.append({
			"id": d["id"],
			"type": d.get("type", d["id"]),
			"owner_pid": int(d.get("owner_pid", 0)),
			"node": anchor,
			"sprite": anchor.get_node("Sprite"),
		})
	print("TEST_CAPTURE_SPAWN: Client received %d capture points" % data.size())
	#region agent log
	GameState.agent_debug_log("H3", "World.gd:_client_spawn_capture_points", "after_cp_spawn", {
		"rpc_data_size": data.size(),
		"capture_points_nodes": capture_points.size()
	})
	#endregion

@rpc("authority", "unreliable")
func _client_update_capture(cp_data: Array, res_data: Dictionary):
	for d in cp_data:
		GameState.capture_points[d["id"]] = d.get("owner_name", "")
		var pid = d.get("owner_pid", 0)
		for cp in capture_points:
			if cp.get("id") == d["id"]:
				cp["owner_pid"] = pid
				var sprite: Sprite3D = cp.get("sprite", null)
				if sprite != null:
					sprite.modulate = _capture_point_modulate(pid)
	if res_data.is_empty():
		return
	for pid_str in res_data.keys():
		GameState.resources[int(pid_str)] = res_data[pid_str]
	_update_topbar_local(_capture_points_data_for_topbar(), res_data)

func _capture_points_data_for_topbar() -> Array:
	var out: Array = []
	for cp in capture_points:
		out.append({
			"id": cp["id"],
			"type": cp.get("type", cp["id"]),
			"owner_pid": cp.get("owner_pid", 0),
		})
	return out

func _count_owned_cps_by_type(cp_data: Array, owner_pid: int) -> Dictionary:
	var counts := {"Stables": 0, "Blacksmith": 0, "Village": 0, "Archery": 0}
	for d in cp_data:
		if d.get("owner_pid", 0) != owner_pid:
			continue
		var cp_type: String = str(d.get("type", d.get("id", "")))
		if counts.has(cp_type):
			counts[cp_type] += 1
	return counts

func _update_topbar_local(cp_data: Array, res_data):
	if top_bar == null:
		return
	var my_pid = multiplayer.get_unique_id()
	var cp_counts := _count_owned_cps_by_type(cp_data, my_pid)
	var my_horses := 0
	var my_spears := 0
	var my_bows := 0
	var my_villagers := 0
	if res_data is Dictionary:
		var res = res_data.get(my_pid, res_data.get(str(my_pid), null))
		if res is Dictionary:
			my_horses = res.get("horses", 0)
			my_spears = res.get("spears", 0)
			my_bows = res.get("bows", 0)
			my_villagers = res.get("villagers", 0)
	var player_name = GameState.local_player_name
	if player_name == "":
		player_name = "Unknown Player"
	var player_color = Color.WHITE
	if GameState.players.has(my_pid) and GameState.players[my_pid].has("color_index"):
		var ci = GameState.players[my_pid]["color_index"]
		if ci >= 0 and ci < GameState.PLAYER_COLORS.size():
			player_color = GameState.PLAYER_COLORS[ci]
	top_bar.update_display(
		cp_counts["Stables"],
		cp_counts["Blacksmith"],
		cp_counts["Village"],
		cp_counts["Archery"],
		my_horses,
		my_spears,
		my_bows,
		my_villagers,
		player_name,
		player_color,
	)

@rpc("authority", "reliable")
func _client_spawn_drafted_army(army_data: Dictionary):
	var army = _client_spawn_one_army(army_data, "")
	if army == null:
		return
	print("TEST_DRAFT_SUCCESS: Client received drafted army '%s' (soldiers=%d)" % [army.army_id, army.soldier_count()])

@rpc("authority", "reliable")
func _client_army_routed(army_id: String):
	var army = _find_army(army_id)
	if army == null or army.fc == null:
		return
	if army in selected_armies:
		selected_armies.erase(army)
		army.deselect()
	_sim.rout_army(army.fc)
	_sim.died_ids.clear()
	_sim.routed_armies.clear()

@rpc("authority", "reliable")
func _announce_winner(winner_name: String):
	print("TEST_GAME_OVER: Winner announced: %s" % winner_name)
	get_tree().create_timer(1.0).timeout.connect(func():
		get_tree().root.get_node("Main").load_game_over(winner_name)
	)

func get_my_armies() -> Array:
	var my_id = multiplayer.get_unique_id()
	var result := []
	for army in armies:
		if army.owner_id == my_id and not army.is_routed:
			result.append(army)
	return result
