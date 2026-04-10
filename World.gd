extends Node3D
## Single world: server authority + 3D client (map XZ = 1280×720, ground at y=0).

const _GroupFormation = preload("res://GroupFormation.gd")
const _MarqueeRectOverlay = preload("res://MarqueeRectOverlay.gd")

const ARMIES_PER_PLAYER := 2
const UNITS_PER_ARMY := 10
const MAP_WIDTH := 1280
const MAP_HEIGHT := 720  # used as Z in 3D
const CP_PEACE_SECONDS := 5.0
const CAPTURE_RADIUS_SEEK := 120.0
const DRAFT_COST_PER_EQUIPMENT := 10
const WEST_SPAWN := Vector2(-120.0, float(MAP_HEIGHT) / 2.0)
const EAST_SPAWN := Vector2(float(MAP_WIDTH) + 120.0, float(MAP_HEIGHT) / 2.0)
const WEST_STOP_X := 80.0
const EAST_STOP_X := float(MAP_WIDTH) - 80.0
const NORTH_SPAWN := Vector2(float(MAP_WIDTH) / 2.0, -100.0)
const SOUTH_SPAWN := Vector2(float(MAP_WIDTH) / 2.0, float(MAP_HEIGHT) + 100.0)
const NORTH_STOP_Y := 80.0
const SOUTH_STOP_Y := float(MAP_HEIGHT) - 80.0
const GRID_CELL_SIZE := 125.0
const CP_CAPTURE_RADIUS := 120.0
const CP_RESOURCE_INTERVAL := 2.0
## Zoomed out: bird's-eye; zoomed in: pitch approaches horizontal + look-at near soldier head height.
const CAMERA_PITCH_MAX_DEG := 45.0
const CAMERA_PITCH_MIN_DEG := 8.0
## Added to terrain height at pivot XZ when fully zoomed in (above unit center ~11, toward head).
const LOOK_HEIGHT_ABOVE_GROUND_MAX := 20.0
const CAMERA_MIN_DISTANCE := 200.0
const CAMERA_MAX_DISTANCE := 1200.0
const CAMERA_PAN_SPEED := 400.0
const CAMERA_ZOOM_SPEED := 80.0
const ARMY_CLICK_RADIUS := 80.0
# Client: only snap to server HERE when error exceeds this (real desync only)
const CORRECTION_THRESHOLD := 120.0
# Terrain height sampling: unit origin y = ground_height + UNIT_HALF_HEIGHT (box is 22 tall)
const UNIT_HALF_HEIGHT := 11.0

var _unit_grid: Dictionary = {}  # "cx_cz" -> Array of unit refs
var sync_timer := 0.0
var army_time_at_cp := {}
var army_follow_target := {}
var player_side := {}  # pid -> "west" | "east" | ...
var army_index_per_player := {}
## Server-only capture sim: { id, type, x, y, owner_pid, resource_timer }
var _server_captures: Array = []

var _camera: Camera3D
var _camera_pivot: Node3D
var _camera_distance: float = 500.0
var _look_at: Vector3
var _pan_drag := false
var _last_mouse: Vector2

var armies: Array = []
var all_units: Array = []
var capture_points: Array = []
var top_bar = null
var draft_menu = null
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
var _move_goal_markers_3d: Node3D
var _goal_marker_mesh_by_unit: Dictionary = {}  # String -> MeshInstance3D
const MARQUEE_DRAG_THRESHOLD := 6.0
const RMB_DRAG_CLICK_THRESHOLD := 14.0

func _ready():
	_look_at = Vector3(MAP_WIDTH / 2.0, 0, MAP_HEIGHT / 2.0)
	var ground_collision = get_node_or_null("GroundCollision")
	if ground_collision is StaticBody3D:
		ground_collision.collision_layer = 2
		ground_collision.collision_mask = 0
	# Match setup only when real lobby has registered players (skip standalone tests with empty GameState).
	if multiplayer.is_server() and GameState.players.size() >= 2:
		GameState.reset_match_state()
		_set_player_sides()
		_spawn_armies()
		_spawn_capture_points()
	if not multiplayer.is_server():
		_setup_camera()
		_setup_selection_overlay()
	_setup_topbar()
	_setup_draft_menu()
	_add_play_boundary_line()
	call_deferred("_agent_debug_log_world_ready")

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
	# Default is false; without an active camera the viewport draws no 3D (ground, units, CPs all missing).
	_camera.current = true
	_update_camera_position()
	#region agent log
	GameState.agent_debug_log("H1", "World.gd:_setup_camera", "camera_after_setup", {
		"camera_current": _camera.current,
		"camera_is_current": _camera.is_current(),
		"cam_global_origin": [ _camera.global_position.x, _camera.global_position.y, _camera.global_position.z ]
	})
	#endregion

## 0 = zoomed out (overview), 1 = zoomed in (soldier-like framing).
func _camera_zoom_t() -> float:
	var span := CAMERA_MAX_DISTANCE - CAMERA_MIN_DISTANCE
	if span <= 0.001:
		return 0.0
	return clampf((CAMERA_MAX_DISTANCE - _camera_distance) / span, 0.0, 1.0)

func _camera_pitch_deg_for_zoom() -> float:
	var t := _camera_zoom_t()
	return lerpf(CAMERA_PITCH_MAX_DEG, CAMERA_PITCH_MIN_DEG, t)

func _camera_pivot_y_for_zoom() -> float:
	var gy := get_ground_height_at(_look_at.x, _look_at.z)
	var t := _camera_zoom_t()
	return gy + lerpf(0.0, LOOK_HEIGHT_ABOVE_GROUND_MAX, t)

func _update_camera_position():
	if _camera_pivot == null:
		return
	_camera_pivot.position = Vector3(_look_at.x, _camera_pivot_y_for_zoom(), _look_at.z)
	if _camera:
		var rad := deg_to_rad(_camera_pitch_deg_for_zoom())
		_camera.position = Vector3(0, _camera_distance * sin(rad), _camera_distance * cos(rad))
		_camera.look_at(_camera_pivot.global_position, Vector3.UP)

func _input(event: InputEvent):
	if multiplayer.is_server() or game_over:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_camera_distance = maxf(CAMERA_MIN_DISTANCE, _camera_distance - CAMERA_ZOOM_SPEED)
			_update_camera_position()
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_camera_distance = minf(CAMERA_MAX_DISTANCE, _camera_distance + CAMERA_ZOOM_SPEED)
			_update_camera_position()
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
	elif event is InputEventMouseMotion:
		if _pan_drag:
			var mm := event as InputEventMouseMotion
			var delta := mm.position - _last_mouse
			_last_mouse = mm.position
			_look_at.x -= delta.x * 0.5
			_look_at.z -= delta.y * 0.5
			_look_at.x = clampf(_look_at.x, 0, MAP_WIDTH)
			_look_at.z = clampf(_look_at.z, 0, MAP_HEIGHT)
			_update_camera_position()
			get_viewport().set_input_as_handled()
		else:
			_handle_world3d_mouse_extended(event)
	elif event is InputEventKey and event.pressed:
		_handle_key(event)

func _process(_delta: float):
	if not multiplayer.is_server():
		_update_move_goal_markers_3d()
	if _camera_pivot == null:
		return
	if multiplayer.is_server():
		return
	var pan := Vector3.ZERO
	if Input.is_key_pressed(KEY_A):
		pan.x -= CAMERA_PAN_SPEED
	if Input.is_key_pressed(KEY_D):
		pan.x += CAMERA_PAN_SPEED
	if Input.is_key_pressed(KEY_W):
		pan.z -= CAMERA_PAN_SPEED
	if Input.is_key_pressed(KEY_S):
		pan.z += CAMERA_PAN_SPEED
	if pan != Vector3.ZERO:
		_look_at += pan * get_process_delta_time()
		_look_at.x = clampf(_look_at.x, 0, MAP_WIDTH)
		_look_at.z = clampf(_look_at.z, 0, MAP_HEIGHT)
		_update_camera_position()

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
		var uname: String = str(unit.name)
		seen[uname] = true
		var st: Vector3 = unit.sync_target_position
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
	panel.offset_bottom = 710
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
	var create_btn = Button.new()
	create_btn.name = "CreateArmyBtn"
	create_btn.text = "Create army"
	create_btn.pressed.connect(_on_draft_create_pressed.bind(horse_cb, spear_cb))
	vbox.add_child(create_btn)

func _on_draft_create_pressed(horse_cb: CheckBox, spear_cb: CheckBox):
	var use_horse = horse_cb.button_pressed
	var use_spear = spear_cb.button_pressed
	_request_draft(use_horse, use_spear)

func request_draft_from_mock(use_horse: bool, use_spear: bool):
	_request_draft(use_horse, use_spear)

func _request_draft(use_horse: bool, use_spear: bool):
	rpc_id(1, "request_draft_army", use_horse, use_spear)

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
	army.move_army(target)
	rpc("_client_move_army", aid, target)

@rpc("any_peer", "reliable")
func request_draft_army(use_horse: bool, use_spear: bool):
	if not multiplayer.is_server() or game_over:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	if sender_id not in GameState.players:
		return
	if not GameState.resources.has(sender_id):
		GameState.resources[sender_id] = {"horses": 0, "spears": 0}
	var res = GameState.resources[sender_id]
	var need_horses = DRAFT_COST_PER_EQUIPMENT if use_horse else 0
	var need_spears = DRAFT_COST_PER_EQUIPMENT if use_spear else 0
	if res["horses"] < need_horses or res["spears"] < need_spears:
		print("TEST_DRAFT_FAIL: Player %d insufficient resources (need %d horses, %d spears)" % [sender_id, need_horses, need_spears])
		return
	res["horses"] -= need_horses
	res["spears"] -= need_spears
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
	var equipment = {"horse": use_horse, "spear": use_spear}
	var army = _create_army(aid, pid, pname, spawn_pos, dir, equipment)
	armies.append(army)
	army.move_army(stop_pos)
	var data = _serialize_one_army(army)
	data["stop_x"] = stop_pos.x
	data["stop_y"] = stop_pos.y
	rpc("_client_spawn_drafted_army", data)
	rpc("_client_move_army", aid, stop_pos)
	_sync_capture_state()
	print("TEST_DRAFT_SUCCESS: Army '%s' drafted (horse=%s spear=%s)" % [aid, use_horse, use_spear])

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
func _server_move_group_formation(unit_targets: Array):
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
		var u = get_node_or_null(NodePath(uname))
		if u == null or not (u is CharacterBody3D):
			continue
		if u.get("is_dead"):
			continue
		if u.owner_peer_id != sender:
			continue
		if u.has_method("set_move_target"):
			u.set_move_target(Vector2(tx, ty))
		affected[u.army_id] = true
		assigned += 1
	if assigned > 0:
		print("TEST_GROUP_FORMATION: server assigned=%d sender=%d" % [assigned, sender])
	for aid_str in affected.keys():
		army_follow_target.erase(aid_str)
		var army = _find_army(aid_str)
		if army == null:
			continue
		var alive = army.get_alive_soldiers()
		if alive.is_empty():
			continue
		var cx := 0.0
		var cz := 0.0
		for s in alive:
			var mt: Vector2 = s.move_target
			cx += mt.x
			cz += mt.y
		var gy = get_ground_height_at(cx / float(alive.size()), cz / float(alive.size()))
		army.global_position = Vector3(cx / float(alive.size()), gy, cz / float(alive.size()))

func _set_player_sides():
	var sides = ["west", "east", "north", "south"]
	var player_ids = GameState.players.keys()
	for i in range(player_ids.size()):
		if i < sides.size():
			player_side[player_ids[i]] = sides[i]
	for pid in player_ids:
		army_index_per_player[pid] = ARMIES_PER_PLAYER + 1

func _make_server_unit_3d() -> CharacterBody3D:
	var unit = CharacterBody3D.new()
	unit.collision_layer = 1
	unit.collision_mask = 1
	var box = BoxShape3D.new()
	box.size = Vector3(14, 22, 14)
	var col = CollisionShape3D.new()
	col.shape = box
	unit.add_child(col)
	return unit

func _spawn_armies():
	var player_ids = GameState.players.keys()
	if player_ids.size() < 2:
		print("ERROR: Need at least 2 players to spawn armies")
		return
	var w := float(MAP_WIDTH)
	var h := float(MAP_HEIGHT)
	var west_x := w * 0.156
	var east_x := w - 230.0
	var north_y := 80.0
	var south_y := h - 80.0
	var mid_x := w * 0.5
	var spawn_configs := []
	for p in range(player_ids.size()):
		var pid = player_ids[p]
		var pname = GameState.players[pid]["name"]
		var side = player_side.get(pid, "west")
		var army_list := []
		for i in range(ARMIES_PER_PLAYER):
			var pos: Vector2
			var dir: float
			if side == "west":
				pos = Vector2(west_x, h * (0.25 + (float(i) / max(1, ARMIES_PER_PLAYER)) * 0.5))
				dir = 0.0
			elif side == "east":
				pos = Vector2(east_x, h * (0.25 + (float(i) / max(1, ARMIES_PER_PLAYER)) * 0.5))
				dir = PI
			elif side == "north":
				pos = Vector2(mid_x - 100 + i * 60, north_y)
				dir = PI / 2.0
			else:
				pos = Vector2(mid_x - 100 + i * 60, south_y)
				dir = -PI / 2.0
			army_list.append({"pos": pos, "dir": dir})
		spawn_configs.append({"pid": pid, "name": pname, "armies": army_list})
	for pc in spawn_configs:
		for i in range(pc["armies"].size()):
			var ac = pc["armies"][i]
			var army_id = "P%d_%d" % [pc["pid"], i + 1]
			var army = _create_army(army_id, pc["pid"], pc["name"], ac["pos"], ac["dir"], {})
			armies.append(army)
	print("TEST_007: %d armies spawned (%d per player, %d soldiers each)" % [armies.size(), ARMIES_PER_PLAYER, UNITS_PER_ARMY])
	for a in armies:
		var axz = Vector2(a.global_position.x, a.global_position.z)
		print("  Army '%s' at (%d,%d) dir=%.1f owner=%s" % [a.army_id, int(axz.x), int(axz.y), a.direction, a.owner_name])
	rpc("_client_spawn_armies", _serialize_armies())

func _create_army(aid: String, pid: int, pname: String, pos: Vector2, dir: float, equipment: Dictionary = {}) -> Node3D:
	var use_horse: bool = equipment.get("horse", false)
	var use_spear: bool = equipment.get("spear", false)
	var speed: float = (280.0 if use_horse else 200.0) / 6.0
	var atk: float = 13.0 if use_spear else 10.0
	var atk_range: float = 65.0 if use_spear else 50.0
	var army = Node3D.new()
	army.set_script(preload("res://Army3D.gd"))
	army.army_id = aid
	army.owner_peer_id = pid
	army.owner_name = pname
	var gy_a = get_ground_height_at(pos.x, pos.y)
	army.position = Vector3(pos.x, gy_a, pos.y)
	army.direction = dir
	army.initial_count = UNITS_PER_ARMY
	army.name = "Army_%s" % aid
	army.army_routed.connect(_on_army_routed)
	add_child(army)
	var formation_positions = army.calculate_formation_positions(pos, dir, UNITS_PER_ARMY)
	for idx in range(UNITS_PER_ARMY):
		var unit = _make_server_unit_3d()
		unit.set_script(preload("res://Unit3D.gd"))
		var fpos: Vector2 = formation_positions[idx]
		var uy = get_ground_height_at(fpos.x, fpos.y) + UNIT_HALF_HEIGHT
		unit.name = "Soldier_%s_%d" % [aid, idx]
		unit.owner_peer_id = pid
		unit.owner_name = pname
		unit.army_id = aid
		unit.speed = speed
		unit.attack = atk
		unit.attack_range = atk_range
		unit.position = Vector3(fpos.x, uy, fpos.y)
		unit.unit_died.connect(army.on_soldier_died)
		add_child(unit)
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
		data.append({
			"army_id": army.army_id,
			"pid": army.owner_peer_id,
			"name": army.owner_name,
			"x": army.global_position.x,
			"y": army.global_position.z,
			"dir": army.direction,
			"initial_count": army.initial_count,
			"soldiers": soldier_data
		})
	return data

func _spawn_capture_points():
	var w := float(MAP_WIDTH)
	var h := float(MAP_HEIGHT)
	var cp_configs = [
		{"id": "Stables", "type": "Stables", "pos": Vector2(w * 0.39, h * 0.28)},
		{"id": "Blacksmith", "type": "Blacksmith", "pos": Vector2(w * 0.61, h * 0.69)}
	]
	for cfg in cp_configs:
		_server_captures.append({
			"id": cfg["id"],
			"type": cfg["type"],
			"x": cfg["pos"].x,
			"y": cfg["pos"].y,
			"owner_pid": 0,
			"resource_timer": 0.0
		})
	print("TEST_CAPTURE_SPAWN: %d capture points spawned (Stables, Blacksmith)" % _server_captures.size())
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

func _sync_capture_state():
	var cp_data := []
	for c in _server_captures:
		var owner_name := "---"
		if c["owner_pid"] != 0 and GameState.players.has(c["owner_pid"]):
			owner_name = GameState.players[c["owner_pid"]]["name"]
		cp_data.append({"id": c["id"], "owner_pid": c["owner_pid"], "owner_name": owner_name})
	var res_data := {}
	for pid in GameState.resources.keys():
		res_data[pid] = GameState.resources[pid]
	rpc("_client_update_capture", cp_data, res_data)
	_update_topbar_local(cp_data, res_data)

func _serialize_one_army(army) -> Dictionary:
	var soldier_data := []
	for s in army.soldiers:
		soldier_data.append({
			"name": s.name,
			"x": s.global_position.x,
			"y": s.global_position.z
		})
	var s0 = army.soldiers[0] if army.soldiers.size() > 0 else null
	var speed = s0.speed if s0 else 200.0 / 6.0
	var attack = s0.attack if s0 else 10.0
	var attack_range = s0.attack_range if s0 else 50.0
	return {
		"army_id": army.army_id,
		"pid": army.owner_peer_id,
		"name": army.owner_name,
		"x": army.global_position.x,
		"y": army.global_position.z,
		"dir": army.direction,
		"initial_count": army.initial_count,
		"soldiers": soldier_data,
		"speed": speed,
		"attack": attack,
		"attack_range": attack_range
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
		if c["owner_pid"] != 0:
			c["resource_timer"] = float(c.get("resource_timer", 0.0)) + delta
			if c["resource_timer"] >= CP_RESOURCE_INTERVAL:
				c["resource_timer"] -= CP_RESOURCE_INTERVAL
				var key = "horses" if c["type"] == "Stables" else "spears"
				if not GameState.resources.has(c["owner_pid"]):
					GameState.resources[c["owner_pid"]] = {"horses": 0, "spears": 0}
				GameState.resources[c["owner_pid"]][key] += 1
				var total = GameState.resources[c["owner_pid"]][key]
				print("TEST_RESOURCE: %s '%s' produced 1 %s for pid=%d (total=%d)" % [c["type"], c["id"], key, c["owner_pid"], total])

func _physics_process(delta: float):
	if multiplayer.is_server() and not game_over:
		_server_capture_and_resources(delta)
		_update_unit_grid()
		_update_cp_seek_and_follow(delta)
		sync_timer += delta
		if sync_timer >= 0.05:
			sync_timer = 0.0
			_apply_follow_targets()
			_sync_unit_positions()
			_sync_capture_state()

func _notify_unit_death(unit_name: String):
	rpc("_client_unit_died", unit_name)

func _sync_unit_positions():
	var pos_data := []
	var dead_names := []
	for u in all_units:
		if u and is_instance_valid(u):
			if not u.is_dead:
				var here = u.global_position
				var here_xz = Vector2(here.x, here.z)
				var mt: Vector2 = u.move_target
				var there: Vector2 = mt if u.is_moving else here_xz
				pos_data.append({
					"n": u.name, "x": here.x, "y": here.z, "hp": u.hp,
					"tx": there.x, "ty": there.y
				})
			else:
				dead_names.append(u.name)
	rpc("_receive_positions", pos_data, dead_names)

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
		print("TEST_011: Player '%s' has no armies left (all routed)" % loser_name)
	var players_with_armies := {}
	for a in armies:
		if not a.is_routed:
			players_with_armies[a.owner_peer_id] = a.owner_name
	if players_with_armies.size() == 1:
		game_over = true
		var winner_name = players_with_armies.values()[0]
		print("TEST_011: Last player standing. Winner: %s" % winner_name)
		rpc("_announce_winner", winner_name)
		_announce_winner(winner_name)
	elif players_with_armies.size() == 0:
		game_over = true
		print("TEST_011: Draw (no armies left)")
		rpc("_announce_winner", "")
		_announce_winner("")

func _raycast_ground() -> Vector3:
	return _raycast_ground_at_screen(get_viewport().get_mouse_position())

func _raycast_ground_at_screen(screen: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var from := _camera.project_ray_origin(screen)
	var to := from + _camera.project_ray_normal(screen) * 10000.0
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	return hit.position

func _rect_from_points(a: Vector2, b: Vector2) -> Rect2:
	var p := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var s := (a - b).abs()
	return Rect2(p, s)

func _clear_selection():
	for a in selected_armies:
		if a and is_instance_valid(a):
			a.deselect()
	selected_armies.clear()

func _set_selection(armies: Array):
	_clear_selection()
	for a in armies:
		if a and is_instance_valid(a) and not a.is_routed:
			selected_armies.append(a)
			a.select()

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
	return Vector2(clampf(v.x, 0, MAP_WIDTH), clampf(v.y, 0, MAP_HEIGHT))

func _first_alive_soldier_3d(army) -> Node3D:
	if army == null or not is_instance_valid(army):
		return null
	for s in army.soldiers:
		if s and is_instance_valid(s) and not s.get("is_dead"):
			return s
	return null

## Single RMB click: parallel move so first alive soldier of first selected army lands on click; formation preserved.
func _issue_group_move_first_soldier_anchor_3d(click_xz: Vector2):
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var s0 = _first_alive_soldier_3d(sel[0])
	if s0 == null:
		return
	var p0 := Vector2(s0.global_position.x, s0.global_position.z)
	var d := click_xz - p0
	var marker = "TEST_009_MOVE" if GameState.local_player_name == "A" else "TEST_009_MOVE_B"
	for army in sel:
		var a_xz := Vector2(army.global_position.x, army.global_position.z)
		var target := _clamp_map_v2(a_xz + d)
		print("%s: Anchor move army '%s' to (%d,%d)" % [marker, army.army_id, int(target.x), int(target.y)])
		rpc_id(1, "_server_move_army", army.army_id, target)

func _update_formation_ghosts_3d(line_start: Vector2, line_end: Vector2):
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var pack: Dictionary = _GroupFormation.compute_multi_army_positions(line_start, line_end, sel)
	var units: Array = pack.get("units", [])
	var positions: Array = pack.get("positions", [])
	if units.is_empty():
		return
	if _ghost_root_3d == null:
		_ghost_root_3d = Node3D.new()
		_ghost_root_3d.name = "FormationGhosts3D"
		add_child(_ghost_root_3d)
	for c in _ghost_root_3d.get_children():
		c.queue_free()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.85, 0.45, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for p in positions:
		var gy := get_ground_height_at(p.x, p.y)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(12, 4, 12)
		box.mesh = bm
		box.material_override = mat
		box.position = Vector3(p.x, gy + 2.0, p.y)
		_ghost_root_3d.add_child(box)

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
		p = _clamp_map_v2(p)
		payload.append({"n": str(u.name), "x": p.x, "y": p.y})
	rpc_id(1, "_server_move_group_formation", payload)

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
							var army = _get_army_at(Vector2(hit.x, hit.z), my_id)
							if army:
								_set_selection([army])
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

func get_ground_height_at(x: float, z: float) -> float:
	var space = get_world_3d().direct_space_state
	var from_vec = Vector3(x, 500.0, z)
	var to_vec = Vector3(x, -100.0, z)
	var query = PhysicsRayQueryParameters3D.create(from_vec, to_vec)
	query.collision_mask = 2
	var result = space.intersect_ray(query)
	if result.is_empty():
		return 0.0
	return result["position"].y

func _add_play_boundary_line():
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.2, 1.0)
	var line_height := 0.2
	var line_width := 4.0
	# Left edge
	var box_left = BoxMesh.new()
	box_left.size = Vector3(line_width, line_height, MAP_HEIGHT)
	var left = MeshInstance3D.new()
	left.mesh = box_left
	left.position = Vector3(0.0, 0.1, MAP_HEIGHT / 2.0)
	left.material_override = mat
	add_child(left)
	# Right edge
	var box_right = BoxMesh.new()
	box_right.size = Vector3(line_width, line_height, MAP_HEIGHT)
	var right = MeshInstance3D.new()
	right.mesh = box_right
	right.position = Vector3(MAP_WIDTH, 0.1, MAP_HEIGHT / 2.0)
	right.material_override = mat
	add_child(right)
	# Bottom edge
	var box_bottom = BoxMesh.new()
	box_bottom.size = Vector3(MAP_WIDTH, line_height, line_width)
	var bottom = MeshInstance3D.new()
	bottom.mesh = box_bottom
	bottom.position = Vector3(MAP_WIDTH / 2.0, 0.1, 0.0)
	bottom.material_override = mat
	add_child(bottom)
	# Top edge
	var box_top = BoxMesh.new()
	box_top.size = Vector3(MAP_WIDTH, line_height, line_width)
	var top = MeshInstance3D.new()
	top.mesh = box_top
	top.position = Vector3(MAP_WIDTH / 2.0, 0.1, MAP_HEIGHT)
	top.material_override = mat
	add_child(top)

func _make_client_unit_3d() -> CharacterBody3D:
	var unit = CharacterBody3D.new()
	unit.collision_layer = 1
	unit.collision_mask = 1
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
		var army = Node3D.new()
		army.set_script(preload("res://Army3D.gd"))
		add_child(army)
		army.army_id = ad["army_id"]
		army.owner_peer_id = ad["pid"]
		army.owner_name = ad["name"]
		army.direction = ad["dir"]
		army.name = "Army_%s" % ad["army_id"]
		army.initial_count = ad.get("initial_count", UNITS_PER_ARMY)
		var gy = get_ground_height_at(ad["x"], ad["y"]) + UNIT_HALF_HEIGHT
		army.position = Vector3(ad["x"], gy, ad["y"])
		armies.append(army)
		for sd in ad["soldiers"]:
			var unit = _make_client_unit_3d()
			unit.set_script(preload("res://Unit3D.gd"))
			unit.name = sd["name"]
			unit.owner_peer_id = ad["pid"]
			unit.owner_name = ad["name"]
			unit.army_id = ad["army_id"]
			var uy = get_ground_height_at(sd["x"], sd["y"]) + UNIT_HALF_HEIGHT
			var pos = Vector3(sd["x"], uy, sd["y"])
			unit.sync_target_position = pos
			unit.position = pos
			unit.has_move_goal = true
			add_child(unit)
			army.soldiers.append(unit)
			all_units.append(unit)
	print("TEST_007: Client received %d armies" % armies.size())
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

@rpc("authority", "reliable")
func _client_spawn_capture_points(data: Array):
	for d in data:
		GameState.capture_points[d["id"]] = ""
		var pillar = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(40, 80, 40)
		pillar.mesh = box
		var mat = StandardMaterial3D.new()
		var pid = d.get("owner_pid", 0)
		if pid != 0 and pid in GameState.players:
			var ci = GameState.players[pid].get("color_index", 0)
			if ci >= 0 and ci < GameState.PLAYER_COLORS.size():
				mat.albedo_color = GameState.PLAYER_COLORS[ci]
			else:
				mat.albedo_color = Color(0.5, 0.5, 0.5, 0.8)
		else:
			mat.albedo_color = Color(0.5, 0.5, 0.5, 0.8)
		pillar.material_override = mat
		pillar.position = Vector3(d["x"], 40, d["y"])
		pillar.name = "CP_%s" % d["id"]
		add_child(pillar)
		capture_points.append({"id": d["id"], "node": pillar, "material": mat})
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
			if cp.get("id") == d["id"] and cp.get("material"):
				if pid != 0 and pid in GameState.players:
					var ci = GameState.players[pid].get("color_index", 0)
					if ci >= 0 and ci < GameState.PLAYER_COLORS.size():
						cp["material"].albedo_color = GameState.PLAYER_COLORS[ci]
					else:
						cp["material"].albedo_color = Color(0.5, 0.5, 0.5)
				else:
					cp["material"].albedo_color = Color(0.5, 0.5, 0.5, 0.8)
	for pid_str in res_data.keys():
		GameState.resources[int(pid_str)] = res_data[pid_str]
	_update_topbar_local(cp_data, res_data)

func _update_topbar_local(cp_data: Array, res_data):
	if top_bar == null:
		return
	var my_pid = multiplayer.get_unique_id()
	var stables_count := 0
	var blacksmith_count := 0
	var my_horses := 0
	var my_spears := 0
	for d in cp_data:
		if d.get("owner_pid", 0) == my_pid:
			if d["id"] == "Stables":
				stables_count += 1
			elif d["id"] == "Blacksmith":
				blacksmith_count += 1
	if res_data is Dictionary:
		var res = res_data.get(my_pid, res_data.get(str(my_pid), null))
		if res is Dictionary:
			my_horses = res.get("horses", 0)
			my_spears = res.get("spears", 0)
	var player_name = GameState.local_player_name
	if player_name == "":
		player_name = "Unknown Player"
	var player_color = Color.WHITE
	if GameState.players.has(my_pid) and GameState.players[my_pid].has("color_index"):
		var ci = GameState.players[my_pid]["color_index"]
		if ci >= 0 and ci < GameState.PLAYER_COLORS.size():
			player_color = GameState.PLAYER_COLORS[ci]
	top_bar.update_display(stables_count, blacksmith_count, my_horses, my_spears, player_name, player_color)

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
	var army = Node3D.new()
	army.set_script(preload("res://Army3D.gd"))
	add_child(army)
	army.army_id = ad["army_id"]
	army.owner_peer_id = ad["pid"]
	army.owner_name = ad["name"]
	army.direction = ad["dir"]
	army.name = "Army_%s" % ad["army_id"]
	army.initial_count = ad.get("initial_count", UNITS_PER_ARMY)
	var gy = get_ground_height_at(ad["x"], ad["y"]) + UNIT_HALF_HEIGHT
	army.position = Vector3(ad["x"], gy, ad["y"])
	armies.append(army)
	var speed = ad.get("speed", 200.0 / 6.0)
	var atk = ad.get("attack", 10.0)
	var atk_range = ad.get("attack_range", 50.0)
	for sd in ad["soldiers"]:
		var unit = _make_client_unit_3d()
		unit.set_script(preload("res://Unit3D.gd"))
		unit.name = sd["name"]
		unit.owner_peer_id = ad["pid"]
		unit.owner_name = ad["name"]
		unit.army_id = ad["army_id"]
		unit.speed = speed
		unit.attack = atk
		unit.attack_range = atk_range
		var uy = get_ground_height_at(sd["x"], sd["y"]) + UNIT_HALF_HEIGHT
		var pos = Vector3(sd["x"], uy, sd["y"])
		unit.sync_target_position = pos
		unit.position = pos
		unit.has_move_goal = true
		add_child(unit)
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
			var here_y = get_ground_height_at(pd["x"], pd["y"]) + UNIT_HALF_HEIGHT
			var tx = pd.get("tx", pd["x"])
			var ty = pd.get("ty", pd["y"])
			var there_y = get_ground_height_at(tx, ty) + UNIT_HALF_HEIGHT
			var here = Vector3(pd["x"], here_y, pd["y"])
			var there = Vector3(tx, there_y, ty)
			var err = node.global_position.distance_to(here)
			if err > CORRECTION_THRESHOLD:
				node.global_position = here
			node.set("sync_target_position", there)
			node.set("has_move_goal", true)
			if "sync_target_hp" in node:
				node.set("sync_target_hp", pd["hp"])
				node.set("hp", pd["hp"])
	for dn in dead_names:
		_cleanup_client_unit(str(dn))

@rpc("authority", "reliable")
func _client_unit_died(unit_name: String):
	_cleanup_client_unit(unit_name)

func _cleanup_client_unit(unit_name: String):
	var node = get_node_or_null(NodePath(unit_name))
	if node and node.get("is_dead") != true:
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
	print("TEST_011: Winner announced: %s" % winner_name)
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
