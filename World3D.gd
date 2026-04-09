extends Node3D
## 3D world scene: camera control (C2), map/raycast (C3), 3D units (C4).
## Same logical size as 2D: x/z = 1280x720, ground at y=0.

const _GroupFormation = preload("res://GroupFormation.gd")
const _MarqueeRectOverlay = preload("res://MarqueeRectOverlay.gd")

const MAP_WIDTH := 1280
const MAP_HEIGHT := 720  # used as Z in 3D
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
	_setup_camera()
	_setup_topbar()
	_setup_draft_menu()
	_add_play_boundary_line()
	_setup_selection_overlay()
	call_deferred("_agent_debug_log_world3d_ready")

func _agent_debug_log_world3d_ready() -> void:
	#region agent log
	var vc: Camera3D = get_viewport().get_camera_3d()
	GameState.agent_debug_log("H5", "World3D.gd:_agent_debug_log_world3d_ready", "viewport_camera", {
		"viewport_cam_null": vc == null,
		"viewport_cam_path": str(vc.get_path()) if vc else "",
		"viewport_cam_is_current": vc.is_current() if vc else false,
		"_camera_matches_viewport": (vc == _camera) if vc and _camera else false
	})
	GameState.agent_debug_log("H4", "World3D.gd:_agent_debug_log_world3d_ready", "world_root_visibility", {
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
	GameState.agent_debug_log("H1", "World3D.gd:_setup_camera", "camera_after_setup", {
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
	if game_over:
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
	_update_move_goal_markers_3d()
	if _camera_pivot == null:
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
	rpc_id(1, "request_draft_army", horse_cb.button_pressed, spear_cb.button_pressed)

func request_draft_from_mock(use_horse: bool, use_spear: bool):
	rpc_id(1, "request_draft_army", use_horse, use_spear)

@rpc("any_peer", "reliable")
func _server_move_army(_aid: String, _target: Vector2):
	pass  # server only; client sends, server World.gd handles

@rpc("any_peer", "reliable")
func request_draft_army(_use_horse: bool, _use_spear: bool):
	pass  # server only

@rpc("any_peer", "reliable")
func _server_rotate_army(_aid: String, _delta_angle: float):
	pass  # server only

@rpc("any_peer", "reliable")
func _server_move_group_formation(_unit_targets: Array):
	pass  # server only; real logic in World.gd

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
	GameState.agent_debug_log("H3", "World3D.gd:_client_spawn_armies_impl", "after_army_spawn", {
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
	GameState.agent_debug_log("H3", "World3D.gd:_client_spawn_capture_points", "after_cp_spawn", {
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
