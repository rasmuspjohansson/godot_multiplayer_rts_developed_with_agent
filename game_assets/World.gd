extends Node3D
## Single world: server authority + 3D client; map size from MapConfig (S/L/XL).

const _Army3D = preload("res://Army3D.gd")
const _Unit3D = preload("res://Unit3D.gd")
const _GroupFormation = preload("res://GroupFormation.gd")
const _MarqueeRectOverlay = preload("res://MarqueeRectOverlay.gd")
const _ArmyCommandBar = preload("res://ArmyCommandBar.gd")
const _UnitBehaviour = preload("res://UnitBehaviour.gd")
const UNIT_SPRITE_PATHS = preload("res://UnitSpritePaths.gd")
## Per-player unit layers (layer 2 is reserved for ground).
const TEAM_COLLISION_LAYERS: Array[int] = [1, 4, 8, 16]
const NEUTRAL_DRAGON_COLLISION_LAYER := 32
## When true, units pass through each other during movement (no physics blocking).
## Combat still uses distance checks in Unit3D._try_attack(), not collision contact.
## Set false to restore enemy-vs-enemy blocking via per-team collision_mask.
## See game.md "Physics / collision" for layer layout and friendly-blocking notes.
const UNIT_PASS_THROUGH := false

## Default armies per player when map JSON is unavailable (see MapConfig.max_armies_per_player()).
const ARMIES_PER_PLAYER_FALLBACK := 2
const UNITS_PER_ARMY := 10
## Map width/height come from `MapConfig` (maps/map_{S|L|XL}.json). Access via
## `MapConfig.width` / `MapConfig.height` elsewhere in this file.
const CP_PEACE_SECONDS := 5.0
const CAPTURE_RADIUS_SEEK := 120.0
const DRAFT_COST_PER_EQUIPMENT := 10
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
const GRID_CELL_SIZE := 125.0
const CP_CAPTURE_RADIUS := 120.0
const CP_RESOURCE_INTERVAL := 2.0
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
# Client: only snap to server HERE when error exceeds this (real desync only)
const CORRECTION_THRESHOLD := 120.0
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
## Living units per unreliable _receive_positions RPC (round-robin; also MTU cap).
const POSITION_SYNC_BATCH_SIZE := 4
## Capture points per _client_update_capture RPC tick (XL has 11 CPs).
const CAPTURE_SYNC_BATCH_SIZE := 6

var _unit_grid: Dictionary = {}  # "cx_cz" -> Array of unit refs
var sync_timer := 0.0
var _sync_cursor := 0
var _last_sent_cp_owner: Dictionary = {}
var _last_sent_resources: Dictionary = {}
var _capture_hud_sent := false
var army_time_at_cp := {}
var army_follow_target := {}
## Server: mock idle detection — only for armies that received `_server_mock_chase_tick` (not human players)
var _mock_chase_touched: Dictionary = {}
var _mock_stuck_t: Dictionary = {}
var _mock_stuck_last: Dictionary = {}
var player_side := {}  # pid -> "west" | "east" | ... (legacy draft path)
var player_slot := {}  # pid -> int (index into MapConfig.player_starts)
var army_index_per_player := {}
## Server-only capture sim: { id, type, x, y, owner_pid, resource_timer }
var _server_captures: Array = []
var _pending_arrow_damage: Array = []

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
var all_units: Array = []
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
var _goal_marker_mesh_by_unit: Dictionary = {}  # String -> MeshInstance3D
var _show_unit_range: bool = false
var _show_range_cb: CheckBox = null
var _range_markers_3d: Node3D
var _range_marker_mesh_by_unit: Dictionary = {}  # String -> MeshInstance3D
var _sun_azimuth_deg: float = 275.0
var _sun_elevation_deg: float = 0.0
var _sun_energy: float = 0.12
var _sun_light_color: Color = Color(1.0, 0.98, 0.95)
var _lighting_azimuth_value_label: Label = null
var _lighting_elevation_value_label: Label = null
var _lighting_energy_value_label: Label = null
var _lighting_summary_label: Label = null
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
	panel.offset_bottom = 230.0
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
	if value_key == "energy":
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
	row.add_child(value_label)

func _client_unit_scene_visible(u: Node) -> bool:
	if not u.is_visible_in_tree():
		return false
	for c in u.get_children():
		if c is MeshInstance3D and not c.visible:
			return false
	return true

## Client-only: log TEST_ALL_UNITS_* markers for automated detection (both teams visible, overview frustum).
func _log_unit_visibility(phase: String) -> void:
	if multiplayer.is_server() or _camera == null:
		return
	var pname: String = GameState.local_player_name
	var total := 0
	var vis := 0
	for u in all_units:
		if not is_instance_valid(u) or not u.is_inside_tree():
			continue
		if u.get("is_dead"):
			continue
		total += 1
		if _client_unit_scene_visible(u):
			vis += 1
	if total == 0:
		print("TEST_ALL_UNITS_SCENE_VISIBLE_FAIL: client=%s phase=%s visible=0 total=0" % [pname, phase])
	else:
		if vis == total:
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
	for u2 in all_units:
		if not is_instance_valid(u2) or not u2.is_inside_tree():
			continue
		if u2.get("is_dead"):
			continue
		if _camera.is_position_in_frustum(u2.global_position):
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
	call_deferred("_agent_debug_log_world_ready")
	if not multiplayer.is_server():
		call_deferred("_notify_client_world_ready")

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
	print("TEST_TERRAIN_BUILT: %dx%d samples, step=%d, %d hills, %d ridges, %d spline_ridges, %d plateaus, %d plateau_polygons, %d valleys, %d valley_polygons" % [
		cols, rows, int(step), MapConfig._hills.size(), MapConfig._ridges.size(),
		MapConfig._spline_ridges.size(), MapConfig._plateaus.size(), MapConfig._plateau_polygons.size(),
		MapConfig._valleys.size(), MapConfig._valley_polygons.size()
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

func _update_move_goal_markers_3d():
	if _move_goal_markers_3d == null:
		_move_goal_markers_3d = Node3D.new()
		_move_goal_markers_3d.name = "MoveGoalMarkers3D"
		add_child(_move_goal_markers_3d)
	var seen: Dictionary = {}
	for unit in all_units:
		if not is_instance_valid(unit) or not unit.is_inside_tree():
			continue
		if unit.get("is_dead"):
			continue
		if not unit.get("has_move_goal"):
			continue
		if not unit.has_move_goal:
			continue
		var st: Vector3 = unit.sync_target_position
		var dx: float = st.x - unit.global_position.x
		var dz: float = st.z - unit.global_position.z
		if dx * dx + dz * dz <= MOVE_GOAL_MARKER_HIDE_DIST * MOVE_GOAL_MARKER_HIDE_DIST:
			continue
		var uname: String = str(unit.name)
		seen[uname] = true
		var gx := st.x
		var gz := st.z
		var gy := get_ground_height_at(gx, gz) + 0.2
		if not _goal_marker_mesh_by_unit.has(uname):
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 5.0
			cm.bottom_radius = 5.0
			cm.height = 0.25
			mi.mesh = cm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.52, 0.08, 0.7)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = mat
			_move_goal_markers_3d.add_child(mi)
			_goal_marker_mesh_by_unit[uname] = mi
		var mesh_inst: MeshInstance3D = _goal_marker_mesh_by_unit[uname]
		mesh_inst.position = Vector3(gx, gy, gz)
	for k in _goal_marker_mesh_by_unit.keys().duplicate():
		if not seen.has(k):
			var node: MeshInstance3D = _goal_marker_mesh_by_unit[k]
			if is_instance_valid(node):
				node.queue_free()
			_goal_marker_mesh_by_unit.erase(k)

func _on_show_range_toggled(pressed: bool) -> void:
	_show_unit_range = pressed
	if not pressed:
		_clear_range_markers()

func _clear_range_markers() -> void:
	for k in _range_marker_mesh_by_unit.keys().duplicate():
		var node: MeshInstance3D = _range_marker_mesh_by_unit[k]
		if is_instance_valid(node):
			node.queue_free()
		_range_marker_mesh_by_unit.erase(k)

func _range_color_for_unit(unit: Node) -> Color:
	var local_pid := multiplayer.get_unique_id()
	if unit.get("owner_peer_id") == local_pid:
		return Color(0.25, 0.85, 0.35, 0.55)
	if UNIT_SPRITE_PATHS.is_neutral_owner(int(unit.get("owner_peer_id"))):
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

func _update_unit_range_markers_3d() -> void:
	if not _show_unit_range:
		return
	if _range_markers_3d == null:
		_range_markers_3d = Node3D.new()
		_range_markers_3d.name = "UnitRangeMarkers3D"
		add_child(_range_markers_3d)
	var seen: Dictionary = {}
	for unit in all_units:
		if not is_instance_valid(unit) or not unit.is_inside_tree():
			continue
		if unit.get("is_dead"):
			continue
		var uname: String = str(unit.name)
		seen[uname] = true
		var radius: float = float(unit.get("attack_range"))
		var unit_node := unit as Node3D
		if unit_node == null:
			continue
		var pos: Vector3 = unit_node.global_position
		var gy: float = get_ground_height_at(pos.x, pos.z) + 0.18
		if not _range_marker_mesh_by_unit.has(uname):
			var mi := MeshInstance3D.new()
			mi.mesh = _make_range_ring_mesh(radius)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = _range_color_for_unit(unit)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mi.material_override = mat
			_range_markers_3d.add_child(mi)
			_range_marker_mesh_by_unit[uname] = mi
		var mesh_inst: MeshInstance3D = _range_marker_mesh_by_unit[uname]
		mesh_inst.position = Vector3(pos.x, gy, pos.z)
		var mat2: StandardMaterial3D = mesh_inst.material_override as StandardMaterial3D
		if mat2 != null:
			mat2.albedo_color = _range_color_for_unit(unit)
		if absf(radius - _range_ring_radius(mesh_inst.mesh)) > 0.5:
			mesh_inst.mesh = _make_range_ring_mesh(radius)
	for k in _range_marker_mesh_by_unit.keys().duplicate():
		if not seen.has(k):
			var node: MeshInstance3D = _range_marker_mesh_by_unit[k]
			if is_instance_valid(node):
				node.queue_free()
			_range_marker_mesh_by_unit.erase(k)

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
	_request_draft(use_horse, use_spear, use_bow)

func request_draft_from_mock(use_horse: bool, use_spear: bool, use_bow: bool = false):
	_request_draft(use_horse, use_spear, use_bow)

func _request_draft(use_horse: bool, use_spear: bool, use_bow: bool):
	rpc_id(1, "request_draft_army", use_horse, use_spear, use_bow)

@rpc("any_peer", "reliable")
func _server_set_all_armies_aggressive():
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not GameState.players.has(sender):
		return
	var pname := str(GameState.players[sender].get("name", sender))
	var n := 0
	for a in armies:
		if a == null or not is_instance_valid(a) or a.is_routed:
			continue
		if a.owner_peer_id != sender:
			continue
		a.set_stance(_Army3D.Stance.AGGRESSIVE)
		n += 1
	var ids: Array = []
	for a in armies:
		if a and is_instance_valid(a) and not a.is_routed and a.owner_peer_id == sender:
			ids.append(a.army_id)
	rpc("_client_sync_army_stance", ids, _Army3D.Stance.AGGRESSIVE)
	var marker = "TEST_A_AGGRESSIVE" if pname == "A" else "TEST_B_AGGRESSIVE"
	print("%s: Player '%s' set %d armies to aggressive" % [marker, pname, n])

@rpc("authority", "reliable")
func _client_sync_army_stance(army_ids: Array, new_stance: int):
	for aid in army_ids:
		var army = _find_army(str(aid))
		if army and is_instance_valid(army):
			army.set_stance(new_stance)

@rpc("authority", "reliable")
func _client_set_army_stance_for_owner(owner_pid: int, new_stance: String):
	var s := _Army3D.Stance.DEFENSIVE
	match new_stance:
		"aggressive":
			s = _Army3D.Stance.AGGRESSIVE
		"hold":
			s = _Army3D.Stance.HOLD
		"passive":
			s = _Army3D.Stance.PASSIVE
	var ids: Array = []
	for a in armies:
		if a and is_instance_valid(a) and a.owner_peer_id == owner_pid:
			ids.append(a.army_id)
	_client_sync_army_stance(ids, s)

@rpc("any_peer", "reliable")
func _server_armies_set_stance(army_ids: Array, stance: int):
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var synced: Array = []
	for aid in army_ids:
		var army = _find_army(str(aid))
		if army == null or army.owner_peer_id != sender or army.is_routed:
			continue
		army.set_stance(stance)
		synced.append(str(aid))
	if not synced.is_empty():
		rpc("_client_sync_army_stance", synced, stance)

@rpc("any_peer", "reliable")
func _server_army_order_attack(army_id: String, target_army_id: String, target_unit_name: String):
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var army = _find_army(army_id)
	if army == null or army.owner_peer_id != sender or army.is_routed:
		return
	army_follow_target.erase(army_id)
	if target_army_id != "":
		army.issue_attack_army(target_army_id)
		print("TEST_ARMY_ATTACK: %s -> army %s" % [army_id, target_army_id])
	elif target_unit_name != "":
		army.issue_attack_unit(target_unit_name)
		print("TEST_ARMY_ATTACK: %s -> unit %s" % [army_id, target_unit_name])
	rpc("_client_army_order_attack", army_id, target_army_id, target_unit_name)

@rpc("authority", "reliable")
func _client_army_order_attack(army_id: String, target_army_id: String, target_unit_name: String):
	var army = _find_army(army_id)
	if army == null:
		return
	if target_army_id != "":
		army.issue_attack_army(target_army_id)
	elif target_unit_name != "":
		army.issue_attack_unit(target_unit_name)

@rpc("any_peer", "reliable")
func _server_armies_order_attack_move(army_ids: Array, dest_x: float, dest_y: float):
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var dest := Vector2(dest_x, dest_y)
	for aid in army_ids:
		var army = _find_army(str(aid))
		if army == null or army.owner_peer_id != sender or army.is_routed:
			continue
		army_follow_target.erase(str(aid))
		army.issue_attack_move(dest)
		rpc("_client_move_army", str(aid), dest)
	print("TEST_ARMY_ATTACK_MOVE: sender=%d dest=(%d,%d) armies=%d" % [
		sender, int(dest.x), int(dest.y), army_ids.size()
	])

@rpc("any_peer", "reliable")
func _server_move_army(aid: String, target: Vector2):
	if not multiplayer.is_server():
		return
	var army = _find_army(aid)
	if army == null:
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender != army.owner_peer_id:
		return
	var marker = "TEST_009_MOVE" if army.owner_name == "A" else "TEST_009_MOVE_B"
	print("%s: Server moving army '%s' to (%d,%d)" % [marker, aid, int(target.x), int(target.y)])
	army_follow_target.erase(aid)
	army.issue_move(target)
	rpc("_client_move_army", aid, target)

func _army_center_xz_server(army) -> Vector2:
	if army == null or not is_instance_valid(army):
		return Vector2.ZERO
	if army.has_method("get_alive_soldiers"):
		var alive: Array = army.get_alive_soldiers()
		if alive.size() > 0:
			var sx := 0.0
			var sz := 0.0
			for s in alive:
				sx += s.global_position.x
				sz += s.global_position.z
			return Vector2(sx / float(alive.size()), sz / float(alive.size()))
	return Vector2(army.global_position.x, army.global_position.z)

## Average of all enemy army centers (authoritative) — mock clients call this so chase targets match server sim.
func _enemy_blob_center_for_peer(sender_id: int) -> Vector2:
	var sx := 0.0
	var sz := 0.0
	var n := 0
	for a in armies:
		if a == null or not is_instance_valid(a) or a.is_routed:
			continue
		if a.owner_peer_id == sender_id:
			continue
		var c := _army_center_xz_server(a)
		sx += c.x
		sz += c.y
		n += 1
	if n == 0:
		return Vector2.ZERO
	return Vector2(sx / float(n), sz / float(n))

@rpc("any_peer", "reliable")
func _server_mock_chase_tick():
	if not multiplayer.is_server() or game_over:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not GameState.players.has(sender):
		return
	var blob := _enemy_blob_center_for_peer(sender)
	if blob == Vector2.ZERO:
		return
	const MOCK_STOP := 95.0
	var orders := 0
	for a in armies:
		if a == null or not is_instance_valid(a) or a.is_routed:
			continue
		if a.owner_peer_id != sender:
			continue
		var my_c := _army_center_xz_server(a)
		if my_c.distance_to(blob) <= MOCK_STOP:
			continue
		army_follow_target.erase(a.army_id)
		var marker = "TEST_009_MOVE" if a.owner_name == "A" else "TEST_009_MOVE_B"
		print("%s: Server moving army '%s' to (%d,%d)" % [marker, a.army_id, int(blob.x), int(blob.y)])
		a.move_army(blob)
		rpc("_client_move_army", a.army_id, blob)
		_mock_chase_touched[a.army_id] = true
		orders += 1
	if orders > 0:
		var pname: String = str(GameState.players[sender].get("name", sender))
		print("TEST_MOCK_SEEK_ENEMY: server player=%s orders=%d blob=(%.0f,%.0f)" % [pname, orders, blob.x, blob.y])

func _server_mock_stuck_update(delta: float):
	if game_over:
		return
	const NEAR_COMBAT := 78.0
	const STILL_EPS := 11.0
	const STUCK_SEC := 5.0
	for a in armies:
		if a == null or not is_instance_valid(a) or a.is_routed:
			continue
		var aid: String = a.army_id
		if not _mock_chase_touched.get(aid, false):
			continue
		var c := _army_center_xz_server(a)
		var blob := _enemy_blob_center_for_peer(a.owner_peer_id)
		if blob == Vector2.ZERO or c.distance_to(blob) <= NEAR_COMBAT:
			_mock_stuck_t.erase(aid)
			_mock_stuck_last.erase(aid)
			continue
		var last: Vector2 = _mock_stuck_last.get(aid, c)
		if c.distance_to(last) < STILL_EPS:
			_mock_stuck_t[aid] = float(_mock_stuck_t.get(aid, 0.0)) + delta
		else:
			_mock_stuck_t[aid] = 0.0
		_mock_stuck_last[aid] = c
		if float(_mock_stuck_t.get(aid, 0.0)) >= STUCK_SEC:
			_mock_stuck_t[aid] = 0.0
			army_follow_target.erase(aid)
			var marker = "TEST_009_MOVE" if a.owner_name == "A" else "TEST_009_MOVE_B"
			print("%s: Server moving army '%s' to (%d,%d)" % [marker, aid, int(blob.x), int(blob.y)])
			a.move_army(blob)
			rpc("_client_move_army", aid, blob)
			print("TEST_MOCK_IDLE_SEEK_REFRESH: server army=%s blob=(%.0f,%.0f)" % [aid, blob.x, blob.y])

@rpc("any_peer", "reliable")
func request_draft_army(use_horse: bool, use_spear: bool, use_bow: bool = false):
	if not multiplayer.is_server() or game_over:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	if sender_id not in GameState.players:
		return
	if not GameState.resources.has(sender_id):
		GameState.resources[sender_id] = GameState.default_resources()
	var res = GameState.resources[sender_id]
	var need_villagers := DRAFT_COST_PER_EQUIPMENT
	var need_horses = DRAFT_COST_PER_EQUIPMENT if use_horse else 0
	var need_spears = DRAFT_COST_PER_EQUIPMENT if use_spear else 0
	var need_bows = DRAFT_COST_PER_EQUIPMENT if use_bow else 0
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
	var side = player_side.get(pid, "west")
	var spawn_pos: Vector2
	var stop_pos: Vector2
	var dir: float
	if side == "west":
		spawn_pos = WEST_SPAWN
		stop_pos = Vector2(WEST_STOP_X, WEST_SPAWN.y)
		dir = 0.0
	elif side == "east":
		spawn_pos = EAST_SPAWN
		stop_pos = Vector2(EAST_STOP_X, EAST_SPAWN.y)
		dir = PI
	elif side == "north":
		spawn_pos = NORTH_SPAWN
		stop_pos = Vector2(NORTH_SPAWN.x, NORTH_STOP_Y)
		dir = PI / 2.0
	else:
		spawn_pos = SOUTH_SPAWN
		stop_pos = Vector2(SOUTH_SPAWN.x, SOUTH_STOP_Y)
		dir = -PI / 2.0
	var equipment = {"horse": use_horse, "spear": use_spear, "bow": use_bow}
	var army = _create_army(aid, pid, pname, spawn_pos, dir, equipment)
	armies.append(army)
	army.move_army(stop_pos)
	var data = _serialize_one_army(army)
	data["stop_x"] = stop_pos.x
	data["stop_y"] = stop_pos.y
	rpc("_client_spawn_drafted_army", data)
	rpc("_client_move_army", aid, stop_pos)
	_sync_capture_state()
	print("TEST_DRAFT_SUCCESS: Army '%s' drafted (horse=%s spear=%s bow=%s)" % [aid, use_horse, use_spear, use_bow])

@rpc("any_peer", "reliable")
func _server_rotate_army(aid: String, delta_angle: float):
	if not multiplayer.is_server():
		return
	var army = _find_army(aid)
	if army == null:
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender != army.owner_peer_id:
		return
	army.rotate_army(delta_angle)
	rpc("_client_rotate_army", aid, army.direction)

@rpc("any_peer", "reliable")
func _server_move_group_formation(unit_targets: Array, attack_move: bool = false):
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var affected := {}
	var assigned := 0
	for entry in unit_targets:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var uname := str(entry.get("n", ""))
		var tx := float(entry.get("x", 0.0))
		var ty := float(entry.get("y", 0.0))
		var goal := snap_move_goal_xz(Vector2(tx, ty))
		var u = get_node_or_null(NodePath(uname))
		if u == null or not (u is CharacterBody3D):
			continue
		if u.get("is_dead"):
			continue
		if u.owner_peer_id != sender:
			continue
		if u.has_method("set_move_target"):
			u.set_move_target(goal)
		affected[u.army_id] = true
		assigned += 1
	if assigned > 0:
		print("TEST_GROUP_FORMATION: server assigned=%d sender=%d attack_move=%s" % [
			assigned, sender, attack_move
		])
	for aid_str in affected.keys():
		army_follow_target.erase(aid_str)
		var army = _find_army(aid_str)
		if army == null:
			continue
		army.order_type = _Army3D.OrderType.ATTACK_MOVE if attack_move else _Army3D.OrderType.MOVE
		army.order_target_army_id = ""
		army.order_target_unit_name = ""
		var alive = army.get_alive_soldiers()
		if alive.is_empty():
			continue
		var cx := 0.0
		var cz := 0.0
		for s in alive:
			var mt: Vector2 = s.move_target
			cx += mt.x
			cz += mt.y
		army.order_destination = Vector2(cx / float(alive.size()), cz / float(alive.size()))
		var gy = get_ground_height_at(army.order_destination.x, army.order_destination.y)
		army.global_position = Vector3(army.order_destination.x, gy, army.order_destination.y)

func _set_player_sides():
	# Assign each player a map-slot (index into MapConfig.player_starts) by
	# join order. Also populate legacy `player_side` (west/east/...) from the
	# slot's `corner` so the draft-army path keeps working.
	var corner_to_side := {"NW": "west", "SW": "west", "NE": "east", "SE": "east"}
	var player_ids = GameState.players.keys()
	for i in range(player_ids.size()):
		var pid = player_ids[i]
		player_slot[pid] = i
		var start: Dictionary = MapConfig.get_player_start(i)
		var corner := str(start.get("corner", ""))
		player_side[pid] = corner_to_side.get(corner, "west" if i % 2 == 0 else "east")
	for pid in player_ids:
		army_index_per_player[pid] = MapConfig.max_armies_per_player() + 1

func _team_collision_layer_for_peer(peer_id: int) -> int:
	var slot := 0
	if peer_id in GameState.players:
		slot = int(GameState.players[peer_id].get("color_index", 0))
	return TEAM_COLLISION_LAYERS[clampi(slot, 0, TEAM_COLLISION_LAYERS.size() - 1)]

func _enemy_collision_mask_for_peer(peer_id: int) -> int:
	var own_layer := _team_collision_layer_for_peer(peer_id)
	var mask := 0
	for layer in TEAM_COLLISION_LAYERS:
		if layer != own_layer:
			mask |= layer
	return mask

func _configure_unit_collision(unit: CharacterBody3D, peer_id: int) -> void:
	unit.collision_layer = _team_collision_layer_for_peer(peer_id)
	if UNIT_PASS_THROUGH:
		unit.collision_mask = 0
	else:
		unit.collision_mask = _enemy_collision_mask_for_peer(peer_id)

func _make_server_unit_3d(peer_id: int) -> CharacterBody3D:
	var unit = CharacterBody3D.new()
	unit.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_configure_unit_collision(unit, peer_id)
	var box = BoxShape3D.new()
	box.size = Vector3(14, 22, 14)
	var col = CollisionShape3D.new()
	col.shape = box
	unit.add_child(col)
	return unit

func _spawn_armies():
	_mock_chase_touched.clear()
	_mock_stuck_t.clear()
	_mock_stuck_last.clear()
	var player_ids = GameState.players.keys()
	if player_ids.size() < 2:
		print("ERROR: Need at least 2 players to spawn armies")
		return
	# Spawn armies from MapConfig.player_starts[slot].armies.
	# Slot is assigned by join order in `_assign_player_slots()`.
	for p in range(player_ids.size()):
		var pid = player_ids[p]
		var pname = GameState.players[pid]["name"]
		var slot: int = player_slot.get(pid, p)
		var start: Dictionary = MapConfig.get_player_start(slot)
		var start_armies: Array = start.get("armies", [])
		for i in range(start_armies.size()):
			var ac: Dictionary = start_armies[i]
			var pos := Vector2(float(ac.get("x", 0.0)), float(ac.get("y", 0.0)))
			var dir := float(ac.get("direction", 0.0))
			var army_id = "P%d_%d" % [pid, i + 1]
			var equipment = {
				"horse": ac.get("horse", false),
				"spear": ac.get("spear", false),
				"bow": ac.get("bow", false),
			}
			var army = _create_army(army_id, pid, pname, pos, dir, equipment)
			armies.append(army)
	var armies_per_player := MapConfig.max_armies_per_player()
	print("TEST_ARMIES_SPAWNED: %d armies spawned (%d per player, %d soldiers each)" % [armies.size(), armies_per_player, UNITS_PER_ARMY])
	_match_started = true
	_match_elapsed = 0.0
	for a in armies:
		var axz = Vector2(a.global_position.x, a.global_position.z)
		print("  Army '%s' at (%d,%d) dir=%.1f owner=%s" % [a.army_id, int(axz.x), int(axz.y), a.direction, a.owner_name])
	rpc("_client_spawn_armies", _serialize_armies())
	_spawn_map_dragons()

func _spawn_map_dragons() -> void:
	if not multiplayer.is_server():
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
		var unit := _make_dragon_unit_3d()
		unit.set_script(_Unit3D)
		unit.name = "MapDragon_%d" % i
		unit.owner_peer_id = UNIT_SPRITE_PATHS.NEUTRAL_DRAGON_OWNER_ID
		unit.owner_name = "Dragon"
		unit.army_id = "neutral_dragon_%d" % i
		unit.apply_dragon(color)
		var uy: float = get_ground_height_at(pos.x, pos.y) + UNIT_SPRITE_PATHS.DRAGON_HALF_HEIGHT
		unit.position = Vector3(pos.x, uy, pos.y)
		add_child(unit)
		if unit.has_method("initialize_goal_at_current"):
			unit.initialize_goal_at_current()
		all_units.append(unit)
		_map_dragons.append(unit)
		print("TEST_MAP_DRAGON_SPAWN: dragon %d at (%d,%d) aggro=%.0f attack=%.0f" % [
			i, int(pos.x), int(pos.y), UNIT_SPRITE_PATHS.dragon_aggro_radius(), unit.attack_range
		])
		dragon_data.append({
			"index": i,
			"x": pos.x,
			"y": pos.y,
			"color": color,
			"hp": unit.hp,
			"speed": unit.speed,
			"attack": unit.attack,
			"attack_range": unit.attack_range,
			"half_height": unit.half_height,
		})
	if not dragon_data.is_empty():
		rpc("_client_spawn_dragons", dragon_data)

func _make_dragon_unit_3d() -> CharacterBody3D:
	var unit := CharacterBody3D.new()
	unit.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	unit.collision_layer = NEUTRAL_DRAGON_COLLISION_LAYER
	unit.collision_mask = 0 if UNIT_PASS_THROUGH else 0
	var box := BoxShape3D.new()
	box.size = Vector3(40, 66, 40)
	var col := CollisionShape3D.new()
	col.shape = box
	unit.add_child(col)
	return unit

func _unit_half_height(unit: Node) -> float:
	if unit != null and unit.get("half_height") != null:
		return float(unit.half_height)
	return UNIT_HALF_HEIGHT

func _update_map_dragon_ai(delta: float) -> void:
	if _map_dragons.is_empty():
		return
	_dragon_ai_timer += delta
	if _dragon_ai_timer < DRAGON_AI_TICK:
		return
	_dragon_ai_timer = 0.0
	for dragon in _map_dragons:
		if dragon == null or not is_instance_valid(dragon) or dragon.is_dead:
			continue
		_update_one_map_dragon_ai(dragon)

func _update_one_map_dragon_ai(dragon: CharacterBody3D) -> void:
	var center := Vector2(dragon.global_position.x, dragon.global_position.z)
	var aggro := UNIT_SPRITE_PATHS.dragon_aggro_radius()
	var best: CharacterBody3D = null
	var best_dist := aggro + 1.0
	for u in get_units_in_radius(center, aggro):
		if u == dragon or u.get("is_dead"):
			continue
		if UNIT_SPRITE_PATHS.is_neutral_owner(int(u.get("owner_peer_id"))):
			continue
		var uxz := Vector2(u.global_position.x, u.global_position.z)
		var dist := center.distance_to(uxz)
		if dist < best_dist:
			best_dist = dist
			best = u
	if best == null:
		dragon.is_moving = false
		if dragon.has_method("initialize_goal_at_current"):
			dragon.initialize_goal_at_current()
		return
	var target_xz := Vector2(best.global_position.x, best.global_position.z)
	if dragon.has_method("set_move_target"):
		dragon.set_move_target(target_xz)

func _create_army(aid: String, pid: int, pname: String, pos: Vector2, dir: float, equipment: Dictionary = {}) -> Node3D:
	var use_horse: bool = equipment.get("horse", false)
	var use_spear: bool = equipment.get("spear", false)
	var use_bow: bool = equipment.get("bow", false)
	var army = Node3D.new()
	army.set_script(preload("res://Army3D.gd"))
	army.army_id = aid
	army.owner_peer_id = pid
	army.owner_name = pname
	var gy_a = get_ground_height_at(pos.x, pos.y)
	army.position = Vector3(pos.x, gy_a, pos.y)
	army.direction = dir
	army.initial_count = UNITS_PER_ARMY
	army.spacing = _Army3D.MOUNTED_SPACING if use_horse else _Army3D.FOOT_SPACING
	army.name = "Army_%s" % aid
	army.army_routed.connect(_on_army_routed)
	add_child(army)
	var formation_positions = army.calculate_formation_positions(pos, dir, UNITS_PER_ARMY)
	for idx in range(UNITS_PER_ARMY):
		var unit = _make_server_unit_3d(pid)
		unit.set_script(preload("res://Unit3D.gd"))
		var fpos: Vector2 = formation_positions[idx]
		var uy = get_ground_height_at(fpos.x, fpos.y) + UNIT_HALF_HEIGHT
		unit.name = "Soldier_%s_%d" % [aid, idx]
		unit.owner_peer_id = pid
		unit.owner_name = pname
		unit.army_id = aid
		unit.apply_equipment(use_horse, use_spear, use_bow)
		unit.position = Vector3(fpos.x, uy, fpos.y)
		unit.unit_died.connect(army.on_soldier_died)
		add_child(unit)
		if unit.has_method("initialize_goal_at_current"):
			unit.initialize_goal_at_current()
		army.soldiers.append(unit)
		all_units.append(unit)
	return army

func _serialize_armies() -> Array:
	var data := []
	for army in armies:
		var soldier_data := []
		for s in army.soldiers:
			soldier_data.append({
				"name": s.name,
				"x": s.global_position.x,
				"y": s.global_position.z
			})
		var s0 = army.soldiers[0] if army.soldiers.size() > 0 else null
		var use_horse: bool = s0.has_horse if s0 else false
		var use_spear: bool = s0.has_spear if s0 else false
		var use_bow: bool = s0.has_bow if s0 else false
		data.append({
			"army_id": army.army_id,
			"pid": army.owner_peer_id,
			"name": army.owner_name,
			"x": army.global_position.x,
			"y": army.global_position.z,
			"dir": army.direction,
			"initial_count": army.initial_count,
			"spear": use_spear,
			"horse": use_horse,
			"bow": use_bow,
			"soldiers": soldier_data,
			"speed": s0.speed if s0 else _Unit3D.speed_for_equipment(false),
			"attack": s0.attack if s0 else 10.0,
			"attack_range": s0.attack_range if s0 else UNIT_SPRITE_PATHS.MELEE_ATTACK_RANGE,
		})
	return data

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

func _serialize_one_army(army) -> Dictionary:
	var soldier_data := []
	for s in army.soldiers:
		soldier_data.append({
			"name": s.name,
			"x": s.global_position.x,
			"y": s.global_position.z
		})
	var s0 = army.soldiers[0] if army.soldiers.size() > 0 else null
	var use_horse: bool = s0.has_horse if s0 else false
	var use_spear: bool = s0.has_spear if s0 else false
	var use_bow: bool = s0.has_bow if s0 else false
	return {
		"army_id": army.army_id,
		"pid": army.owner_peer_id,
		"name": army.owner_name,
		"x": army.global_position.x,
		"y": army.global_position.z,
		"dir": army.direction,
		"initial_count": army.initial_count,
		"spear": use_spear,
		"horse": use_horse,
		"bow": use_bow,
		"soldiers": soldier_data,
		"speed": s0.speed if s0 else _Unit3D.speed_for_equipment(false),
		"attack": s0.attack if s0 else 10.0,
		"attack_range": s0.attack_range if s0 else UNIT_SPRITE_PATHS.MELEE_ATTACK_RANGE,
	}

func _get_closest_enemy_army(army) -> Node:
	var best = null
	var best_dist := 1e10
	var a_xz = Vector2(army.global_position.x, army.global_position.z)
	for a in armies:
		if a.owner_peer_id == army.owner_peer_id or a.is_routed:
			continue
		var o_xz = Vector2(a.global_position.x, a.global_position.z)
		var d = a_xz.distance_to(o_xz)
		if d < best_dist:
			best_dist = d
			best = a
	return best

func _is_army_at_capture_point(army) -> bool:
	var a_xz = Vector2(army.global_position.x, army.global_position.z)
	for c in _server_captures:
		var cp = Vector2(c["x"], c["y"])
		if a_xz.distance_to(cp) <= CAPTURE_RADIUS_SEEK:
			return true
	return false

func _update_cp_seek_and_follow(delta: float):
	var now = Time.get_ticks_msec() / 1000.0
	if now - GameState.last_combat_time < CP_PEACE_SECONDS:
		for a in armies:
			if a.army_id in army_time_at_cp:
				army_time_at_cp[a.army_id] = 0.0
		return
	for army in armies:
		if army.is_routed:
			continue
		var aid = army.army_id
		if _is_army_at_capture_point(army):
			var t = army_time_at_cp.get(aid, 0.0)
			if t >= 0:
				t += delta
				army_time_at_cp[aid] = t
				if t >= CP_PEACE_SECONDS:
					var enemy = _get_closest_enemy_army(army)
					if enemy:
						army_follow_target[aid] = enemy.army_id
						army_time_at_cp[aid] = -1.0
						print("TEST_SEEK_ENEMY: Army '%s' seeking closest enemy '%s'" % [aid, enemy.army_id])
		else:
			army_time_at_cp[aid] = 0.0

func _apply_follow_targets():
	var to_erase := []
	for aid in army_follow_target.keys():
		var target_id = army_follow_target[aid]
		var army = _find_army(aid)
		var target_army = _find_army(target_id)
		if army == null or target_army == null or target_army.is_routed:
			to_erase.append(aid)
			continue
		var txz = Vector2(target_army.global_position.x, target_army.global_position.z)
		army.move_army(txz)
		rpc("_client_move_army", aid, txz)
	for aid in to_erase:
		army_follow_target.erase(aid)

func _grid_key(cell: Vector2i) -> String:
	return "%d_%d" % [cell.x, cell.y]

func _update_unit_grid():
	_unit_grid.clear()
	for u in all_units:
		if not u or not is_instance_valid(u) or u.is_dead:
			continue
		var p = u.global_position
		var cx = int(floor(p.x / GRID_CELL_SIZE))
		var cz = int(floor(p.z / GRID_CELL_SIZE))
		var k = _grid_key(Vector2i(cx, cz))
		if not _unit_grid.has(k):
			_unit_grid[k] = []
		_unit_grid[k].append(u)

func get_units_in_radius(center: Vector2, radius: float) -> Array:
	var out := []
	var cell_radius = ceili(radius / GRID_CELL_SIZE)
	var cx0 = int(floor(center.x / GRID_CELL_SIZE))
	var cy0 = int(floor(center.y / GRID_CELL_SIZE))
	for dx in range(-cell_radius, cell_radius + 1):
		for dy in range(-cell_radius, cell_radius + 1):
			var k = _grid_key(Vector2i(cx0 + dx, cy0 + dy))
			if not _unit_grid.has(k):
				continue
			for u in _unit_grid[k]:
				if not u or not is_instance_valid(u) or u.is_dead:
					continue
				var uxz = Vector2(u.global_position.x, u.global_position.z)
				if center.distance_to(uxz) <= radius:
					out.append(u)
	return out

func _server_capture_and_resources(delta: float):
	if not multiplayer.is_server():
		return
	for c in _server_captures:
		var nearby_pids := {}
		var center = Vector2(c["x"], c["y"])
		var candidates = get_units_in_radius(center, CP_CAPTURE_RADIUS)
		for u in candidates:
			if u.get("is_dead"):
				continue
			var uxz = Vector2(u.global_position.x, u.global_position.z)
			var dist = uxz.distance_to(center)
			if dist <= CP_CAPTURE_RADIUS:
				nearby_pids[u.owner_peer_id] = true
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
func _update_aggressive_armies(delta: float):
	_aggressive_timer += delta
	if _aggressive_timer < AGGRESSIVE_TICK_INTERVAL:
		return
	_aggressive_timer = 0.0
	for a in armies:
		if a == null or not is_instance_valid(a) or a.is_routed:
			continue
		if a.stance != _Army3D.Stance.AGGRESSIVE:
			continue
		if a.has_player_order():
			continue
		var enemy = _get_closest_enemy_army(a)
		if enemy == null:
			continue
		a.issue_attack_army(enemy.army_id)
		var exz := _army_center_xz_server(enemy)
		exz = Vector2(clampf(exz.x, 0.0, float(MapConfig.width)), clampf(exz.y, 0.0, float(MapConfig.height)))
		army_follow_target.erase(a.army_id)
		var gy := get_ground_height_at(exz.x, exz.y)
		a.global_position = Vector3(exz.x, gy, exz.y)
		var alive: Array = a.get_alive_soldiers()
		var positions: Array = a.calculate_formation_positions(exz, a.direction, alive.size())
		for i in range(alive.size()):
			var p: Vector2 = positions[i]
			p.x = clampf(p.x, 0.0, float(MapConfig.width))
			p.y = clampf(p.y, 0.0, float(MapConfig.height))
			var uy := get_ground_height_at(p.x, p.y) + UNIT_HALF_HEIGHT
			alive[i].sync_target_position = Vector3(p.x, uy, p.y)
			if alive[i].has_method("set_move_target"):
				alive[i].set_move_target(p)
		_apply_army_combat_directives(a)
		rpc("_client_move_army", a.army_id, exz)
		print("TEST_AGGRESSIVE_TICK: army=%s owner=%s target_enemy=%s at=(%d,%d)" % [
			a.army_id, a.owner_name, enemy.army_id, int(exz.x), int(exz.y)
		])

func _resolve_attack_order_xz(army) -> Vector2:
	if army.order_target_army_id != "":
		var enemy = _find_army(army.order_target_army_id)
		if enemy == null or enemy.is_routed:
			army.clear_order()
			return Vector2.ZERO
		return _army_center_xz_server(enemy)
	if army.order_target_unit_name != "":
		var node = get_node_or_null(NodePath(army.order_target_unit_name))
		if node == null or not is_instance_valid(node) or node.get("is_dead"):
			army.clear_order()
			return Vector2.ZERO
		return Vector2(node.global_position.x, node.global_position.z)
	return Vector2.ZERO

func _units_in_army(army_id: String) -> Array:
	var out: Array = []
	for u in all_units:
		if u and is_instance_valid(u) and not u.is_dead and str(u.army_id) == army_id:
			out.append(u)
	return out

func _nearest_unit_name_to(units: Array, pos: Vector2) -> String:
	var best := ""
	var best_dist := 1e10
	for u in units:
		var uxz := Vector2(u.global_position.x, u.global_position.z)
		var d := pos.distance_to(uxz)
		if d < best_dist:
			best_dist = d
			best = str(u.name)
	return best

func _apply_army_combat_directives(army) -> void:
	var cmd_name := ""
	if army.order_type == _Army3D.OrderType.ATTACK:
		if army.order_target_army_id != "":
			var enemies := _units_in_army(army.order_target_army_id)
			for s in army.get_alive_soldiers():
				var spos := Vector2(s.global_position.x, s.global_position.z)
				cmd_name = _nearest_unit_name_to(enemies, spos)
				if s.has_method("set_combat_directives"):
					s.set_combat_directives(cmd_name, army.stance)
			return
		cmd_name = army.order_target_unit_name
	army.apply_combat_directives_to_soldiers(cmd_name)

func _apply_formation_goals_server(army, center: Vector2) -> void:
	center = snap_move_goal_xz(_clamp_map_v2(center))
	var gy := get_ground_height_at(center.x, center.y)
	army.global_position = Vector3(center.x, gy, center.y)
	var alive: Array = army.get_alive_soldiers()
	var positions: Array = army.calculate_formation_positions(center, army.direction, alive.size())
	for i in range(alive.size()):
		var p: Vector2 = snap_move_goal_xz(_clamp_map_v2(positions[i]))
		var uy := get_ground_height_at(p.x, p.y) + _unit_half_height(alive[i])
		alive[i].sync_target_position = Vector3(p.x, uy, p.y)
		if alive[i].has_method("set_move_target"):
			alive[i].set_move_target(p)

func _max_pursuit_for_army(army) -> float:
	var max_p := 40.0
	for s in army.get_alive_soldiers():
		var prof: Dictionary = _UnitBehaviour.profile_for_unit(s)
		max_p = maxf(max_p, float(prof.get("pursuit_distance", 80.0)))
	return max_p

func _update_army_orders(delta: float) -> void:
	for a in armies:
		if a == null or not is_instance_valid(a) or a.is_routed:
			continue
		if a.order_type == _Army3D.OrderType.NONE:
			_apply_army_combat_directives(a)
			continue
		if a.order_type == _Army3D.OrderType.MOVE:
			a.order_destination = Vector2(a.global_position.x, a.global_position.z)
			_apply_army_combat_directives(a)
			continue
		if a.order_type == _Army3D.OrderType.ATTACK_MOVE:
			var dest: Vector2 = a.order_destination
			var acenter := Vector2(a.global_position.x, a.global_position.z)
			var to_dest := dest - acenter
			if to_dest.length() > GOAL_ARRIVAL_DIST:
				var step := minf(to_dest.length(), 50.0 * delta)
				acenter += to_dest.normalized() * step
			else:
				acenter = dest
			_apply_formation_goals_server(a, acenter)
			_apply_army_combat_directives(a)
			continue
		if a.order_type == _Army3D.OrderType.ATTACK:
			var target_xz := _resolve_attack_order_xz(a)
			if target_xz == Vector2.ZERO:
				continue
			var acenter := Vector2(a.global_position.x, a.global_position.z)
			var to_target := target_xz - acenter
			if to_target.length() > 5.0:
				var step := minf(to_target.length(), 50.0 * delta)
				var new_center := acenter + to_target.normalized() * step
				if a.stance != _Army3D.Stance.AGGRESSIVE:
					var pursuit := _max_pursuit_for_army(a)
					if a.stance == _Army3D.Stance.HOLD:
						pursuit *= 0.5
					if new_center.distance_to(a.hold_position) > pursuit:
						var from_hold: Vector2 = new_center - a.hold_position
						if from_hold.length() > 0.01:
							new_center = a.hold_position + from_hold.normalized() * pursuit
						else:
							new_center = a.hold_position
				acenter = new_center
			_apply_formation_goals_server(a, acenter)
			_apply_army_combat_directives(a)

const GOAL_ARRIVAL_DIST := 0.2

func _physics_process(delta: float):
	if preview_only:
		return
	if multiplayer.is_server() and not game_over:
		_process_pending_arrow_damage(delta)
		_check_match_timeout(delta)
		if game_over:
			return
		_server_capture_and_resources(delta)
		_update_unit_grid()
		_update_army_orders(delta)
		_update_aggressive_armies(delta)
		_update_map_dragon_ai(delta)
		sync_timer += delta
		if sync_timer >= 0.05:
			sync_timer = 0.0
			if not _all_clients_world_ready():
				return
			_sync_unit_positions()
			_sync_capture_state()

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
		if a and is_instance_valid(a) and not a.is_routed:
			counts[a.owner_peer_id] = int(counts.get(a.owner_peer_id, 0)) + 1
			names[a.owner_peer_id] = a.owner_name
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

func _notify_unit_death(unit_name: String):
	rpc("_client_unit_died", unit_name)

func _unit_position_payload(u) -> Dictionary:
	var here = u.global_position
	var final_mt: Vector2
	if u.is_moving:
		final_mt = u.move_target
	else:
		final_mt = Vector2(here.x, here.z)
	var steer_mt := final_mt
	if u.is_moving and u.has_method("_current_steer_target_xz"):
		steer_mt = u._current_steer_target_xz()
	return {
		"n": u.name, "x": here.x, "y": here.z, "hp": u.hp,
		"tx": steer_mt.x, "ty": steer_mt.y,
		"fx": final_mt.x, "fy": final_mt.y,
		"ic": u.in_combat,
		"moving": u.is_moving,
	}

func _sync_unit_positions():
	var living := []
	var dead_names := []
	for u in all_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.get("is_dead"):
			dead_names.append(u.name)
		else:
			living.append(u)
	if living.is_empty():
		if not dead_names.is_empty():
			rpc("_receive_positions", [], dead_names)
		return
	if _sync_cursor < 0 or _sync_cursor >= living.size():
		_sync_cursor = 0
	var n := mini(POSITION_SYNC_BATCH_SIZE, living.size())
	var pos_data := []
	var wrapped := false
	for i in range(n):
		var idx := (_sync_cursor + i) % living.size()
		if i > 0 and idx < _sync_cursor:
			wrapped = true
		pos_data.append(_unit_position_payload(living[idx]))
	_sync_cursor = (_sync_cursor + n) % living.size()
	if _sync_cursor == 0:
		wrapped = true
	var dead_batch := dead_names if wrapped else []
	rpc("_receive_positions", pos_data, dead_batch)

func spawn_arrow(from: Vector3, to: Vector3, duration: float, peak: float) -> void:
	if multiplayer.is_server():
		rpc("_client_spawn_arrow", from, to, duration, peak)

@rpc("authority", "call_local", "reliable")
func _client_spawn_arrow(from: Vector3, to: Vector3, duration: float, peak: float) -> void:
	var arrow := Node3D.new()
	arrow.set_script(_ArrowProjectile)
	add_child(arrow)
	arrow.setup(from, to, duration, peak)

func schedule_arrow_damage(target_name: String, dmg: float, attacker_id: int, delay: float) -> void:
	if not multiplayer.is_server():
		return
	_pending_arrow_damage.append({
		"target_name": target_name,
		"dmg": dmg,
		"attacker_id": attacker_id,
		"time_left": delay,
	})

func _process_pending_arrow_damage(delta: float) -> void:
	var i := 0
	while i < _pending_arrow_damage.size():
		var entry: Dictionary = _pending_arrow_damage[i]
		entry["time_left"] = float(entry["time_left"]) - delta
		if float(entry["time_left"]) > 0.0:
			_pending_arrow_damage[i] = entry
			i += 1
			continue
		_pending_arrow_damage.remove_at(i)
		var node = get_node_or_null(NodePath(str(entry["target_name"])))
		if node == null or not is_instance_valid(node):
			continue
		if node.get("is_dead"):
			continue
		if node.has_method("take_damage"):
			node.take_damage(float(entry["dmg"]), int(entry["attacker_id"]))

func _on_army_routed(army):
	if game_over:
		return
	rpc("_client_army_routed", army.army_id)
	var loser_pid = army.owner_peer_id
	var loser_name = army.owner_name
	var all_routed = true
	for a in armies:
		if a.owner_peer_id == loser_pid and not a.is_routed:
			all_routed = false
			break
	if all_routed:
		print("TEST_PLAYER_ELIMINATED: Player '%s' has no armies left (all routed)" % loser_name)
	var players_with_armies := {}
	for a in armies:
		if not a.is_routed:
			players_with_armies[a.owner_peer_id] = a.owner_name
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

func _set_selection(armies: Array):
	_clear_selection()
	for a in armies:
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

func _armies_in_screen_rect_3d(rect: Rect2, my_id: int) -> Array:
	var out := []
	if _camera == null:
		return out
	for army in armies:
		if army.owner_peer_id != my_id or army.is_routed:
			continue
		var any_inside := false
		for s in army.soldiers:
			if s == null or not is_instance_valid(s) or s.get("is_dead"):
				continue
			var sp := _camera.unproject_position(s.global_position)
			if rect.has_point(sp):
				any_inside = true
				break
		if any_inside:
			out.append(army)
	return out

func _clamp_map_v2(v: Vector2) -> Vector2:
	return Vector2(clampf(v.x, 0, MapConfig.width), clampf(v.y, 0, MapConfig.height))

func _first_alive_soldier_3d(army) -> Node3D:
	if army == null or not is_instance_valid(army):
		return null
	for s in army.soldiers:
		if s and is_instance_valid(s) and not s.get("is_dead"):
			return s
	return null

## Single RMB click: shift every selected soldier's goal by the same delta so the anchor's goal lands on click.
## Delta uses the first alive soldier of the first selected army's current goal (not physical position).
func _is_attack_move_mode() -> bool:
	return _army_command_bar != null \
		and _army_command_bar.get_order_mode() == _ArmyCommandBar.OrderMode.ATTACK_MOVE

func _issue_group_move_first_soldier_anchor_3d(click_xz: Vector2):
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var s0 = _first_alive_soldier_3d(sel[0])
	if s0 == null or not s0.has_method("get_goal_xz"):
		return
	var g0: Vector2 = s0.get_goal_xz()
	var click_c := snap_move_goal_xz(_clamp_map_v2(click_xz))
	var delta := click_c - g0
	var marker = "TEST_009_MOVE" if GameState.local_player_name == "A" else "TEST_009_MOVE_B"
	var payload: Array = []
	var n_units := 0
	for army in sel:
		for s in army.soldiers:
			if s == null or not is_instance_valid(s) or s.get("is_dead"):
				continue
			if not s.has_method("get_goal_xz"):
				continue
			var og: Vector2 = s.get_goal_xz()
			var nw := snap_move_goal_xz(_clamp_map_v2(og + delta))
			payload.append({"n": str(s.name), "x": nw.x, "y": nw.y})
			n_units += 1
	if payload.is_empty():
		return
	print("%s: Anchor goal move %d units to click (%d,%d)" % [marker, n_units, int(click_c.x), int(click_c.y)])
	rpc_id(1, "_server_move_group_formation", payload, _is_attack_move_mode())

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

func _update_formation_ghosts_3d(line_start: Vector2, line_end: Vector2):
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var pack: Dictionary = _GroupFormation.compute_multi_army_positions(line_start, line_end, sel)
	var positions: Array = pack.get("positions", [])
	if positions.is_empty():
		return
	if _ghost_root_3d == null:
		_ghost_root_3d = Node3D.new()
		_ghost_root_3d.name = "FormationGhosts3D"
		add_child(_ghost_root_3d)
	var mat := _ensure_ghost_marker_material(true)
	var invalid_mat := _ensure_ghost_marker_material(false)
	var ghosts: Array = _ghost_root_3d.get_children()
	while ghosts.size() < positions.size():
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(12, 4, 12)
		box.mesh = bm
		box.material_override = mat
		_ghost_root_3d.add_child(box)
		ghosts.append(box)
	while ghosts.size() > positions.size():
		var extra: Node = ghosts[ghosts.size() - 1]
		extra.queue_free()
		ghosts.remove_at(ghosts.size() - 1)
	for i in range(positions.size()):
		var p: Vector2 = positions[i]
		var gy := get_ground_height_at(p.x, p.y)
		var box: MeshInstance3D = ghosts[i]
		box.position = Vector3(p.x, gy + 2.0, p.y)
		box.material_override = mat if is_walkable_at(p.x, p.y) else invalid_mat

func _clear_formation_ghosts_3d():
	if _ghost_root_3d:
		for c in _ghost_root_3d.get_children():
			c.queue_free()

func _commit_group_formation_line_3d(line_start: Vector2, line_end: Vector2):
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var pack: Dictionary = _GroupFormation.compute_multi_army_positions(line_start, line_end, sel)
	var units: Array = pack.get("units", [])
	var positions: Array = pack.get("positions", [])
	if units.is_empty():
		return
	var payload: Array = []
	for i in range(units.size()):
		var u = units[i]
		var p: Vector2 = positions[i]
		p = snap_move_goal_xz(_clamp_map_v2(p))
		payload.append({"n": str(u.name), "x": p.x, "y": p.y})
	rpc_id(1, "_server_move_group_formation", payload, _is_attack_move_mode())

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
						_issue_group_move_first_soldier_anchor_3d(world_xz)
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
		if army.owner_peer_id == for_peer_id or army.is_routed:
			continue
		var a_pos = Vector2(army.global_position.x, army.global_position.z)
		var dist = pos_2d.distance_to(a_pos)
		if dist < best_dist:
			best_dist = dist
			best = army
	return best

func _get_attackable_unit_at(pos_2d: Vector2, for_peer_id: int):
	var best = null
	var best_dist := ARMY_CLICK_RADIUS
	for dragon in _map_dragons:
		if dragon == null or not is_instance_valid(dragon) or dragon.get("is_dead"):
			continue
		var dxz := Vector2(dragon.global_position.x, dragon.global_position.z)
		var dist := pos_2d.distance_to(dxz)
		if dist < best_dist:
			best_dist = dist
			best = dragon
	for u in all_units:
		if u == null or not is_instance_valid(u) or u.get("is_dead"):
			continue
		if u.owner_peer_id == for_peer_id:
			continue
		if UNIT_SPRITE_PATHS.is_neutral_owner(int(u.get("owner_peer_id"))):
			continue
		var uxz := Vector2(u.global_position.x, u.global_position.z)
		var dist2 := pos_2d.distance_to(uxz)
		if dist2 < best_dist:
			best_dist = dist2
			best = u
	return best

func _issue_armies_attack_at(pos: Vector2) -> void:
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var my_id := multiplayer.get_unique_id()
	var enemy_army = _get_enemy_army_at(pos, my_id)
	if enemy_army != null:
		for a in sel:
			rpc_id(1, "_server_army_order_attack", a.army_id, enemy_army.army_id, "")
		return
	var unit = _get_attackable_unit_at(pos, my_id)
	if unit != null:
		for a in sel:
			rpc_id(1, "_server_army_order_attack", a.army_id, "", str(unit.name))

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
		if army.owner_peer_id != peer_id or army.is_routed:
			continue
		var a_pos = Vector2(army.global_position.x, army.global_position.z)
		var dist = pos_2d.distance_to(a_pos)
		if dist < best_dist:
			best_dist = dist
			best = army
	return best

func _find_army(aid: String):
	for army in armies:
		if army.army_id == aid:
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

func get_ground_height_at(x: float, z: float) -> float:
	var space = get_world_3d().direct_space_state
	var from_y := _max_terrain_height + 500.0
	var from_vec = Vector3(x, from_y, z)
	var to_vec = Vector3(x, -200.0, z)
	var query = PhysicsRayQueryParameters3D.create(from_vec, to_vec)
	query.collision_mask = 2
	query.hit_back_faces = true
	var result = space.intersect_ray(query)
	if result.is_empty():
		return _terrain_grid_height_at(x, z)
	return result["position"].y

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

func _make_client_unit_3d(peer_id: int) -> CharacterBody3D:
	var unit = CharacterBody3D.new()
	unit.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_configure_unit_collision(unit, peer_id)
	var box = BoxShape3D.new()
	box.size = Vector3(14, 22, 14)
	var col = CollisionShape3D.new()
	col.shape = box
	unit.add_child(col)
	return unit

@rpc("authority", "reliable")
func _client_spawn_armies(data: Array):
	# One frame later: ensures this node and physics/world are fully in the tree
	# (avoids get_global_transform errors during early match setup).
	call_deferred("_client_spawn_armies_impl", data)

func _client_spawn_armies_impl(data: Array):
	for ad in data:
		var use_horse: bool = ad.get("horse", false)
		var use_spear: bool = ad.get("spear", false)
		var use_bow: bool = ad.get("bow", false)
		var army = Node3D.new()
		army.set_script(preload("res://Army3D.gd"))
		add_child(army)
		army.army_id = ad["army_id"]
		army.owner_peer_id = ad["pid"]
		army.owner_name = ad["name"]
		army.direction = ad["dir"]
		army.name = "Army_%s" % ad["army_id"]
		army.initial_count = ad.get("initial_count", UNITS_PER_ARMY)
		army.spacing = _Army3D.MOUNTED_SPACING if use_horse else _Army3D.FOOT_SPACING
		var gy = get_ground_height_at(ad["x"], ad["y"]) + UNIT_HALF_HEIGHT
		army.position = Vector3(ad["x"], gy, ad["y"])
		armies.append(army)
		for sd in ad["soldiers"]:
			var unit = _make_client_unit_3d(ad["pid"])
			unit.set_script(preload("res://Unit3D.gd"))
			unit.name = sd["name"]
			unit.owner_peer_id = ad["pid"]
			unit.owner_name = ad["name"]
			unit.army_id = ad["army_id"]
			if unit.has_method("apply_equipment"):
				unit.apply_equipment(use_horse, use_spear, use_bow)
			if ad.has("speed"):
				unit.speed = float(ad["speed"])
				unit.attack = float(ad.get("attack", unit.attack))
				unit.attack_range = float(ad.get("attack_range", unit.attack_range))
			var uy = get_ground_height_at(sd["x"], sd["y"]) + UNIT_HALF_HEIGHT
			var pos = Vector3(sd["x"], uy, sd["y"])
			unit.sync_target_position = pos
			unit.position = pos
			unit.has_move_goal = false
			add_child(unit)
			if unit.has_method("refresh_visuals"):
				unit.refresh_visuals()
			army.soldiers.append(unit)
			all_units.append(unit)
	print("TEST_ARMIES_SPAWNED: Client received %d armies" % armies.size())
	print("TEST_3D_CLIENT_UNITS_SPAWNED: units=%d armies=%d" % [all_units.size(), armies.size()])
	#region agent log
	var u0pos: Array = []
	if all_units.size() > 0 and is_instance_valid(all_units[0]):
		var u = all_units[0]
		u0pos = [ u.global_position.x, u.global_position.y, u.global_position.z ]
	GameState.agent_debug_log("H3", "World.gd:_client_spawn_armies_impl", "after_army_spawn", {
		"data_armies": data.size(),
		"all_units": all_units.size(),
		"armies": armies.size(),
		"first_unit_pos": u0pos
	})
	#endregion
	call_deferred("_validate_units_height")
	call_deferred("_validate_unit_textures")
	_schedule_visibility_checks()

@rpc("authority", "reliable")
func _client_spawn_dragons(data: Array) -> void:
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		_client_spawn_one_dragon(entry)

func _client_spawn_one_dragon(data: Dictionary) -> void:
	var index := int(data.get("index", _map_dragons.size()))
	for existing in _map_dragons:
		if existing != null and is_instance_valid(existing) and existing.name == "MapDragon_%d" % index:
			return
	var unit := _make_dragon_unit_3d()
	unit.set_script(_Unit3D)
	unit.name = "MapDragon_%d" % index
	unit.owner_peer_id = UNIT_SPRITE_PATHS.NEUTRAL_DRAGON_OWNER_ID
	unit.owner_name = "Dragon"
	unit.army_id = "neutral_dragon_%d" % index
	var color := str(data.get("color", "red"))
	unit.apply_dragon(color)
	unit.hp = float(data.get("hp", unit.hp))
	unit.sync_target_hp = unit.hp
	unit.speed = float(data.get("speed", unit.speed))
	unit.attack = float(data.get("attack", unit.attack))
	unit.attack_range = float(data.get("attack_range", unit.attack_range))
	var hh := float(data.get("half_height", unit.half_height))
	unit.half_height = hh
	var px := float(data.get("x", MapConfig.width * 0.5))
	var pz := float(data.get("y", MapConfig.height * 0.5))
	var uy := get_ground_height_at(px, pz) + hh
	var pos := Vector3(px, uy, pz)
	unit.position = pos
	unit.sync_target_position = pos
	unit.has_move_goal = false
	add_child(unit)
	if unit.has_method("refresh_visuals"):
		unit.refresh_visuals()
	all_units.append(unit)
	_map_dragons.append(unit)
	print("TEST_MAP_DRAGON_SPAWN: client dragon %d at (%d,%d)" % [index, int(px), int(pz)])
	call_deferred("_validate_units_height")

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
func _client_move_army(aid: String, target: Vector2):
	var army = _find_army(aid)
	if army:
		army.move_army(target)

@rpc("authority", "reliable")
func _client_rotate_army(aid: String, new_dir: float):
	var army = _find_army(aid)
	if army:
		army.direction = new_dir
		if army.has_method("assign_formation_targets"):
			army.assign_formation_targets()

@rpc("authority", "reliable")
func _client_spawn_drafted_army(army_data: Dictionary):
	var ad = army_data
	var use_horse: bool = ad.get("horse", false)
	var use_spear: bool = ad.get("spear", false)
	var use_bow: bool = ad.get("bow", false)
	var army = Node3D.new()
	army.set_script(preload("res://Army3D.gd"))
	add_child(army)
	army.army_id = ad["army_id"]
	army.owner_peer_id = ad["pid"]
	army.owner_name = ad["name"]
	army.direction = ad["dir"]
	army.name = "Army_%s" % ad["army_id"]
	army.initial_count = ad.get("initial_count", UNITS_PER_ARMY)
	army.spacing = _Army3D.MOUNTED_SPACING if use_horse else _Army3D.FOOT_SPACING
	var gy = get_ground_height_at(ad["x"], ad["y"]) + UNIT_HALF_HEIGHT
	army.position = Vector3(ad["x"], gy, ad["y"])
	armies.append(army)
	for sd in ad["soldiers"]:
		var unit = _make_client_unit_3d(ad["pid"])
		unit.set_script(preload("res://Unit3D.gd"))
		unit.name = sd["name"]
		unit.owner_peer_id = ad["pid"]
		unit.owner_name = ad["name"]
		unit.army_id = ad["army_id"]
		if unit.has_method("apply_equipment"):
			unit.apply_equipment(use_horse, use_spear, use_bow)
		if ad.has("speed"):
			unit.speed = float(ad["speed"])
			unit.attack = float(ad.get("attack", unit.attack))
			unit.attack_range = float(ad.get("attack_range", unit.attack_range))
		var uy = get_ground_height_at(sd["x"], sd["y"]) + UNIT_HALF_HEIGHT
		var pos = Vector3(sd["x"], uy, sd["y"])
		unit.sync_target_position = pos
		unit.position = pos
		unit.has_move_goal = false
		add_child(unit)
		if unit.has_method("refresh_visuals"):
			unit.refresh_visuals()
		army.soldiers.append(unit)
		all_units.append(unit)
	if ad.has("stop_x") and ad.has("stop_y"):
		army.move_army(Vector2(ad["stop_x"], ad["stop_y"]))
	print("TEST_DRAFT_SUCCESS: Client received drafted army '%s'" % army.army_id)
	call_deferred("_validate_units_height")
	call_deferred("_validate_unit_textures")

func _validate_unit_textures():
	var ok := 0
	var fail := 0
	for unit in all_units:
		if not is_instance_valid(unit) or not unit.is_inside_tree():
			continue
		if unit.has_method("has_valid_spearman_texture") and unit.has_valid_spearman_texture():
			ok += 1
		else:
			fail += 1
			print("TEST_3D_TEXTURE_MISSING: %s" % unit.name)
	if fail == 0:
		print("TEST_3D_TEXTURES_OK: count=%d" % ok)
	else:
		print("TEST_3D_TEXTURES_BAD: ok=%d fail=%d" % [ok, fail])

func _validate_units_height():
	for unit in all_units:
		if not is_instance_valid(unit) or not unit.is_inside_tree():
			continue
		var ground_y = get_ground_height_at(unit.global_position.x, unit.global_position.z)
		if unit.global_position.y < ground_y - 0.5:
			print("TEST_3D_UNIT_HEIGHT_INVALID: %s spawn_below_ground" % unit.name)

@rpc("authority", "unreliable")
func _receive_positions(pos_data: Array, dead_names: Array = []):
	for pd in pos_data:
		var node = get_node_or_null(NodePath(str(pd["n"])))
		if node and is_instance_valid(node):
			if node.get("is_dead"):
				continue
			var hh := _unit_half_height(node)
			var here_y = get_ground_height_at(pd["x"], pd["y"]) + hh
			var tx = pd.get("tx", pd["x"])
			var ty = pd.get("ty", pd["y"])
			var fx = pd.get("fx", tx)
			var fy = pd.get("fy", ty)
			var final_goal_xz := Vector2(float(fx), float(fy))
			var there_y = get_ground_height_at(tx, ty) + hh
			var here = Vector3(pd["x"], here_y, pd["y"])
			var there = Vector3(tx, there_y, ty)
			var err = node.global_position.distance_to(here)
			if node.has_method("apply_network_sync"):
				node.apply_network_sync(
					here,
					there,
					float(pd.get("hp", node.get("hp"))),
					bool(pd.get("ic", false)),
					CORRECTION_THRESHOLD,
					final_goal_xz,
				)
			else:
				if err > CORRECTION_THRESHOLD:
					node.global_position = here
				node.set("sync_target_position", there)
				node.set("has_move_goal", bool(pd.get("moving", false)))
				if "sync_target_hp" in node:
					node.set("sync_target_hp", pd["hp"])
					node.set("hp", pd["hp"])
				if "sync_in_combat" in node:
					node.set("sync_in_combat", bool(pd.get("ic", false)))
	for dn in dead_names:
		var dead_node = get_node_or_null(NodePath(str(dn)))
		if dead_node and dead_node.has_method("is_in_death_sequence") and dead_node.is_in_death_sequence():
			continue
		_cleanup_client_unit(str(dn))

@rpc("authority", "reliable")
func _client_unit_died(unit_name: String):
	_cleanup_client_unit(unit_name)

func _cleanup_client_unit(unit_name: String):
	var node = get_node_or_null(NodePath(unit_name))
	if node == null:
		return
	if node.has_method("is_in_death_sequence") and node.is_in_death_sequence():
		return
	if node.has_method("begin_death"):
		node.begin_death()
		print("TEST_UNIT_CLEANUP: client freed unit %s" % unit_name)
		return
	if node.get("is_dead") != true:
		node.set("is_dead", true)
		print("TEST_UNIT_CLEANUP: client freed unit %s" % unit_name)
		get_tree().create_timer(0.5).timeout.connect(func():
			if is_instance_valid(node):
				node.queue_free()
		)

@rpc("authority", "reliable")
func _client_army_routed(army_id: String):
	var army = _find_army(army_id)
	if army == null:
		return
	army.is_routed = true
	if army in selected_armies:
		selected_armies.erase(army)
	for s in army.soldiers:
		if is_instance_valid(s):
			s.set("is_dead", true)
			s.queue_free()

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
		if army.owner_peer_id == my_id and not army.is_routed:
			result.append(army)
	return result
