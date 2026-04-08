extends Node2D

const _GroupFormation = preload("res://GroupFormation.gd")
const _MarqueeRectOverlay = preload("res://MarqueeRectOverlay.gd")

# Scaling: change these to scale the game (spawn, map, nav)
const ARMIES_PER_PLAYER := 2
const UNITS_PER_ARMY := 10
const MAP_WIDTH := 1280
const MAP_HEIGHT := 720

const ARMY_CLICK_RADIUS := 80.0
const CP_PEACE_SECONDS := 5.0
const CAPTURE_RADIUS_SEEK := 120.0
const DRAFT_COST_PER_EQUIPMENT := 10
const WEST_SPAWN := Vector2(-120.0, MAP_HEIGHT / 2.0)
const EAST_SPAWN := Vector2(float(MAP_WIDTH) + 120.0, MAP_HEIGHT / 2.0)
const WEST_STOP_X := 80.0
const EAST_STOP_X := float(MAP_WIDTH) - 80.0
const NORTH_SPAWN := Vector2(MAP_WIDTH / 2.0, -100.0)
const SOUTH_SPAWN := Vector2(MAP_WIDTH / 2.0, float(MAP_HEIGHT) + 100.0)
const NORTH_STOP_Y := 80.0
const SOUTH_STOP_Y := float(MAP_HEIGHT) - 80.0

# Spatial grid for unit queries (combat/capture); cell size ~100-150 px
const GRID_CELL_SIZE := 125.0
# Client: only snap to server HERE when error exceeds this (real desync only)
const CORRECTION_THRESHOLD := 120.0
var _unit_grid: Dictionary = {}  # key "cx_cy" -> Array of unit refs

var armies: Array = []
var all_units: Array = []
var capture_points: Array = []
var top_bar = null
var draft_menu = null
var game_over := false
var sync_timer := 0.0
var selected_armies: Array = []
var _marquee_start_screen: Vector2 = Vector2.ZERO
var _marquee_end_screen: Vector2 = Vector2.ZERO
var _marquee_active: bool = false
var _marquee_moved: bool = false
var _marquee_overlay: Control
var _rmb_press_screen: Vector2 = Vector2.ZERO
var _rmb_press_world: Vector2 = Vector2.ZERO
var _rmb_drag_active: bool = false
var _ghost_markers_2d: Node2D
const MARQUEE_DRAG_THRESHOLD := 6.0
const RMB_DRAG_CLICK_THRESHOLD := 14.0
var army_time_at_cp := {}
var army_follow_target := {}
var player_side := {}  # pid -> "west" | "east"
var army_index_per_player := {}  # pid -> next army index (3, 4, ...)

func _ready():
	_setup_map_bounds()
	if multiplayer.is_server():
		GameState.reset_match_state()
		_set_player_sides()
		_spawn_armies()
		_spawn_capture_points()
	_setup_topbar()
	_setup_draft_menu()
	if not multiplayer.is_server():
		_setup_selection_overlay()

func _setup_selection_overlay():
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.name = "SelectionMarqueeLayer"
	add_child(layer)
	_marquee_overlay = _MarqueeRectOverlay.new()
	layer.add_child(_marquee_overlay)

func _setup_map_bounds():
	var nav_region = get_node_or_null("NavigationRegion2D")
	if nav_region and nav_region.navigation_polygon:
		var poly = NavigationPolygon.new()
		var w = float(MAP_WIDTH)
		var h = float(MAP_HEIGHT)
		poly.add_outline(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]))
		poly.make_polygons_from_outlines()
		nav_region.navigation_polygon = poly
	var bg = get_node_or_null("Background")
	if bg and bg is ColorRect:
		bg.offset_right = float(MAP_WIDTH)
		bg.offset_bottom = float(MAP_HEIGHT)

func _set_player_sides():
	var sides = ["west", "east", "north", "south"]
	var player_ids = GameState.players.keys()
	for i in range(player_ids.size()):
		if i < sides.size():
			player_side[player_ids[i]] = sides[i]
	for pid in player_ids:
		army_index_per_player[pid] = ARMIES_PER_PLAYER + 1  # next army index after starting armies

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
		print("  Army '%s' at (%d,%d) dir=%.1f owner=%s" % [a.army_id, int(a.global_position.x), int(a.global_position.y), a.direction, a.owner_name])

	rpc("_client_spawn_armies", _serialize_armies())

func _create_army(aid: String, pid: int, pname: String, pos: Vector2, dir: float, equipment: Dictionary = {}) -> Node2D:
	var use_horse: bool = equipment.get("horse", false)
	var use_spear: bool = equipment.get("spear", false)
	var speed: float = (280.0 if use_horse else 200.0) / 6.0
	var attack: float = 13.0 if use_spear else 10.0
	var attack_range: float = 65.0 if use_spear else 50.0

	var army_script = preload("res://Army.gd")
	var army = Node2D.new()
	army.set_script(army_script)
	army.army_id = aid
	army.owner_peer_id = pid
	army.owner_name = pname
	army.global_position = pos
	army.direction = dir
	army.initial_count = UNITS_PER_ARMY
	army.name = "Army_%s" % aid
	army.army_routed.connect(_on_army_routed)
	add_child(army)

	var formation_positions = army.calculate_formation_positions(pos, dir, UNITS_PER_ARMY)
	for idx in range(UNITS_PER_ARMY):
		var unit = preload("res://Unit.tscn").instantiate()
		unit.name = "Soldier_%s_%d" % [aid, idx]
		unit.owner_peer_id = pid
		unit.owner_name = pname
		unit.army_id = aid
		unit.speed = speed
		unit.attack = attack
		unit.attack_range = attack_range
		unit.global_position = formation_positions[idx]
		unit.unit_died.connect(army.on_soldier_died)
		add_child(unit)
		army.soldiers.append(unit)
		all_units.append(unit)

	return army

@rpc("authority", "reliable")
func _client_spawn_armies(data: Array):
	for ad in data:
		var army_script = preload("res://Army.gd")
		var army = Node2D.new()
		army.set_script(army_script)
		army.army_id = ad["army_id"]
		army.owner_peer_id = ad["pid"]
		army.owner_name = ad["name"]
		army.global_position = Vector2(ad["x"], ad["y"])
		army.direction = ad["dir"]
		army.initial_count = ad.get("initial_count", UNITS_PER_ARMY)
		army.name = "Army_%s" % ad["army_id"]
		add_child(army)
		armies.append(army)

		for sd in ad["soldiers"]:
			var unit = preload("res://Unit.tscn").instantiate()
			unit.name = sd["name"]
			unit.owner_peer_id = ad["pid"]
			unit.owner_name = ad["name"]
			unit.army_id = ad["army_id"]
			var pos = Vector2(sd["x"], sd["y"])
			unit.global_position = pos
			unit.sync_target_position = pos
			add_child(unit)
			army.soldiers.append(unit)
			all_units.append(unit)

	print("TEST_007: Client received %d armies" % armies.size())

func _serialize_armies() -> Array:
	var data := []
	for army in armies:
		var soldier_data := []
		for s in army.soldiers:
			soldier_data.append({
				"name": s.name,
				"x": s.global_position.x,
				"y": s.global_position.y
			})
		data.append({
			"army_id": army.army_id,
			"pid": army.owner_peer_id,
			"name": army.owner_name,
			"x": army.global_position.x,
			"y": army.global_position.y,
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
		var cp = preload("res://CapturePoint.tscn").instantiate()
		cp.name = "CP_%s" % cfg["id"]
		cp.cp_id = cfg["id"]
		cp.cp_type = cfg["type"]
		cp.global_position = cfg["pos"]
		cp.get_node("Label").text = cfg["type"]
		cp.ownership_changed.connect(_on_capture_point_changed)
		add_child(cp)
		capture_points.append(cp)
	print("TEST_CAPTURE_SPAWN: %d capture points spawned (Stables, Blacksmith)" % capture_points.size())
	rpc("_client_spawn_capture_points", _serialize_capture_points())

func _serialize_capture_points() -> Array:
	var data := []
	for cp in capture_points:
		data.append({
			"id": cp.cp_id,
			"type": cp.cp_type,
			"x": cp.global_position.x,
			"y": cp.global_position.y,
			"owner_pid": cp.owner_pid
		})
	return data

@rpc("authority", "reliable")
func _client_spawn_capture_points(data: Array):
	for d in data:
		var cp = preload("res://CapturePoint.tscn").instantiate()
		cp.name = "CP_%s" % d["id"]
		cp.cp_id = d["id"]
		cp.cp_type = d["type"]
		cp.global_position = Vector2(d["x"], d["y"])
		cp.owner_pid = d["owner_pid"]
		cp.get_node("Label").text = d["type"]
		add_child(cp)
		capture_points.append(cp)
	print("TEST_CAPTURE_SPAWN: Client received %d capture points" % capture_points.size())

func _on_capture_point_changed(_cp_id: String, _owner_pid: int):
	_sync_capture_state()

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

func _sync_capture_state():
	var cp_data := []
	for cp in capture_points:
		cp_data.append({"id": cp.cp_id, "owner_pid": cp.owner_pid, "owner_name": cp.get_owner_name()})
	var res_data := {}
	for pid in GameState.resources.keys():
		res_data[pid] = GameState.resources[pid]
	rpc("_client_update_capture", cp_data, res_data)
	_update_topbar_local(cp_data, res_data)

@rpc("authority", "unreliable")
func _client_update_capture(cp_data: Array, res_data: Dictionary):
	for d in cp_data:
		for cp in capture_points:
			if cp.cp_id == d["id"]:
				cp.owner_pid = d["owner_pid"]
				break
		GameState.capture_points[d["id"]] = d["owner_name"]
	for pid_str in res_data.keys():
		var pid = int(pid_str)
		GameState.resources[pid] = res_data[pid_str]
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

func _input(event: InputEvent):
	if multiplayer.is_server() or game_over:
		return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_handle_mouse_extended(event)
	elif event is InputEventKey and event.pressed:
		_handle_key(event)

func _world_to_screen_2d(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world

func _screen_to_world_2d(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen

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

func _armies_in_screen_rect(rect: Rect2, my_id: int) -> Array:
	var out := []
	var xf := get_viewport().get_canvas_transform()
	for army in armies:
		if army.owner_peer_id != my_id or army.is_routed:
			continue
		if not army.has_method("get_alive_soldiers"):
			continue
		var any_inside := false
		for s in army.get_alive_soldiers():
			if s == null or not is_instance_valid(s) or s.is_dead:
				continue
			var sp: Vector2 = xf * s.global_position
			if rect.has_point(sp):
				any_inside = true
				break
		if any_inside:
			out.append(army)
	return out

func _clamp_map_v2(v: Vector2) -> Vector2:
	return Vector2(clampf(v.x, 0, MAP_WIDTH), clampf(v.y, 0, MAP_HEIGHT))

func _group_centroid_armies(arr: Array) -> Vector2:
	if arr.is_empty():
		return Vector2.ZERO
	var s := Vector2.ZERO
	for a in arr:
		if a and is_instance_valid(a):
			s += a.global_position
	return s / float(arr.size())

func _issue_group_move_centroid(click_world: Vector2):
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var gc := _group_centroid_armies(sel)
	var marker = "TEST_009_MOVE" if GameState.local_player_name == "A" else "TEST_009_MOVE_B"
	for army in sel:
		var off: Vector2 = army.global_position - gc
		var target := _clamp_map_v2(click_world + off)
		print("%s: Group move army '%s' to (%d,%d)" % [marker, army.army_id, int(target.x), int(target.y)])
		rpc_id(1, "_server_move_army", army.army_id, target)

func _update_formation_ghosts_2d(line_start: Vector2, line_end: Vector2):
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var units: Array = _GroupFormation.collect_soldiers_sorted(sel)
	if units.is_empty():
		return
	var positions: Array = _GroupFormation.compute_line_formation(line_start, line_end, units.size())
	if _ghost_markers_2d == null:
		_ghost_markers_2d = Node2D.new()
		_ghost_markers_2d.name = "FormationGhosts2D"
		add_child(_ghost_markers_2d)
	for c in _ghost_markers_2d.get_children():
		c.queue_free()
	for p in positions:
		var r := ColorRect.new()
		r.size = Vector2(14, 14)
		r.position = p - Vector2(7, 7)
		r.color = Color(0.35, 0.85, 0.45, 0.4)
		_ghost_markers_2d.add_child(r)

func _clear_formation_ghosts_2d():
	if _ghost_markers_2d:
		for c in _ghost_markers_2d.get_children():
			c.queue_free()

func _commit_group_formation_line(line_start: Vector2, line_end: Vector2):
	var sel := _get_selected_non_routed()
	if sel.is_empty():
		return
	var units: Array = _GroupFormation.collect_soldiers_sorted(sel)
	if units.is_empty():
		return
	var positions: Array = _GroupFormation.compute_line_formation(line_start, line_end, units.size())
	var payload: Array = []
	for i in range(units.size()):
		var u = units[i]
		var p: Vector2 = positions[i]
		p = _clamp_map_v2(p)
		payload.append({"n": str(u.name), "x": p.x, "y": p.y})
	rpc_id(1, "_server_move_group_formation", payload)

func _handle_mouse_extended(event: InputEvent):
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
						var picked := _armies_in_screen_rect(r, my_id)
						_set_selection(picked)
					else:
						var world_pos := _screen_to_world_2d(_marquee_start_screen)
						var army = _get_army_at(world_pos, my_id)
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
				_rmb_press_world = get_global_mouse_position()
				_rmb_drag_active = true
				_clear_formation_ghosts_2d()
			else:
				if _rmb_drag_active:
					var world_now := get_global_mouse_position()
					var drag_len := _rmb_press_screen.distance_to(screen_pos)
					if drag_len < RMB_DRAG_CLICK_THRESHOLD:
						_issue_group_move_centroid(world_now)
					else:
						_commit_group_formation_line(_rmb_press_world, world_now)
				_rmb_drag_active = false
				_clear_formation_ghosts_2d()
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
			var world_now := get_global_mouse_position()
			_update_formation_ghosts_2d(_rmb_press_world, world_now)

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

@rpc("authority", "reliable")
func _client_move_army(aid: String, target: Vector2):
	var army = _find_army(aid)
	if army:
		army.move_army(target)

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
		if u == null or not u is CharacterBody2D:
			continue
		if u.get("is_dead"):
			continue
		if u.owner_peer_id != sender:
			continue
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
		var c := Vector2.ZERO
		for s in alive:
			c += s.move_target
		army.global_position = c / float(alive.size())

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

func _serialize_one_army(army) -> Dictionary:
	var soldier_data := []
	for s in army.soldiers:
		soldier_data.append({
			"name": s.name,
			"x": s.global_position.x,
			"y": s.global_position.y
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
		"y": army.global_position.y,
		"dir": army.direction,
		"initial_count": army.initial_count,
		"soldiers": soldier_data,
		"speed": speed,
		"attack": attack,
		"attack_range": attack_range
	}

@rpc("authority", "reliable")
func _client_spawn_drafted_army(army_data: Dictionary):
	var ad = army_data
	var army_script = preload("res://Army.gd")
	var army = Node2D.new()
	army.set_script(army_script)
	army.army_id = ad["army_id"]
	army.owner_peer_id = ad["pid"]
	army.owner_name = ad["name"]
	army.global_position = Vector2(ad["x"], ad["y"])
	army.direction = ad["dir"]
	army.initial_count = ad.get("initial_count", UNITS_PER_ARMY)
	army.name = "Army_%s" % ad["army_id"]
	add_child(army)
	armies.append(army)
	var speed = ad.get("speed", 200.0 / 6.0)
	var attack = ad.get("attack", 10.0)
	var attack_range = ad.get("attack_range", 50.0)
	for sd in ad["soldiers"]:
		var unit = preload("res://Unit.tscn").instantiate()
		unit.name = sd["name"]
		unit.owner_peer_id = ad["pid"]
		unit.owner_name = ad["name"]
		unit.army_id = ad["army_id"]
		unit.speed = speed
		unit.attack = attack
		unit.attack_range = attack_range
		var pos = Vector2(sd["x"], sd["y"])
		unit.global_position = pos
		unit.sync_target_position = pos
		add_child(unit)
		army.soldiers.append(unit)
		all_units.append(unit)
	if ad.has("stop_x") and ad.has("stop_y"):
		army.move_army(Vector2(ad["stop_x"], ad["stop_y"]))
	print("TEST_DRAFT_SUCCESS: Client received drafted army '%s'" % army.army_id)

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

@rpc("authority", "reliable")
func _client_rotate_army(aid: String, new_dir: float):
	var army = _find_army(aid)
	if army:
		army.direction = new_dir
		army.assign_formation_targets()

func _get_army_at(pos: Vector2, peer_id: int):
	var best = null
	var best_dist = ARMY_CLICK_RADIUS
	for army in armies:
		if army.owner_peer_id != peer_id or army.is_routed:
			continue
		var dist = pos.distance_to(army.global_position)
		if dist < best_dist:
			best_dist = dist
			best = army
	return best

func _find_army(aid: String):
	for army in armies:
		if army.army_id == aid:
			return army
	return null

func _get_closest_enemy_army(army) -> Node:
	var best = null
	var best_dist := 1e10
	for a in armies:
		if a.owner_peer_id == army.owner_peer_id or a.is_routed:
			continue
		var d = army.global_position.distance_to(a.global_position)
		if d < best_dist:
			best_dist = d
			best = a
	return best

func _is_army_at_capture_point(army) -> bool:
	for cp in capture_points:
		if army.global_position.distance_to(cp.global_position) <= CAPTURE_RADIUS_SEEK:
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
		var pos = target_army.global_position
		army.move_army(pos)
		rpc("_client_move_army", aid, pos)
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
		var cy = int(floor(p.y / GRID_CELL_SIZE))
		var k = _grid_key(Vector2i(cx, cy))
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
				if center.distance_to(u.global_position) <= radius:
					out.append(u)
	return out

func _physics_process(delta):
	if multiplayer.is_server() and not game_over:
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
				var there = u.move_target if u.is_moving else here
				pos_data.append({
					"n": u.name, "x": here.x, "y": here.y, "hp": u.hp,
					"tx": there.x, "ty": there.y
				})
			else:
				dead_names.append(u.name)
	rpc("_receive_positions", pos_data, dead_names)

@rpc("authority", "unreliable")
func _receive_positions(pos_data: Array, dead_names: Array = []):
	for pd in pos_data:
		var node = get_node_or_null(NodePath(str(pd["n"])))
		if node and not node.is_dead:
			var here = Vector2(pd["x"], pd["y"])
			var there = Vector2(pd.get("tx", pd["x"]), pd.get("ty", pd["y"]))
			var err = node.global_position.distance_to(here)
			if err > CORRECTION_THRESHOLD:
				node.global_position = here
			node.sync_target_position = there
			node.sync_target_hp = pd["hp"]
			node.hp = pd["hp"]
	for dn in dead_names:
		_cleanup_client_unit(str(dn))

@rpc("authority", "reliable")
func _client_unit_died(unit_name: String):
	_cleanup_client_unit(unit_name)

func _cleanup_client_unit(unit_name: String):
	var node = get_node_or_null(NodePath(unit_name))
	if node and not node.is_dead:
		node.is_dead = true
		if node.sprite:
			node.sprite.color = Color.DARK_RED
		print("TEST_UNIT_CLEANUP: client freed unit %s" % unit_name)
		get_tree().create_timer(0.5).timeout.connect(func():
			if is_instance_valid(node):
				node.queue_free()
		)

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
	# Last player with a non-routed army wins
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

@rpc("authority", "reliable")
func _client_army_routed(army_id: String):
	var army = _find_army(army_id)
	if army == null:
		return
	army.is_routed = true
	if army in selected_armies:
		selected_armies.erase(army)
	for s in army.soldiers:
		if s and is_instance_valid(s) and not s.is_dead:
			s.is_dead = true
			if s.sprite:
				s.sprite.color = Color.DARK_RED
			s.queue_free()

@rpc("authority", "reliable")
func _announce_winner(winner_name: String):
	print("TEST_011: Winner announced: %s" % winner_name)
	get_tree().create_timer(1.0).timeout.connect(func():
		var main = get_tree().root.get_node("Main")
		main.load_game_over(winner_name)
	)

func get_my_armies() -> Array:
	var my_id = multiplayer.get_unique_id()
	var result := []
	for army in armies:
		if army.owner_peer_id == my_id and not army.is_routed:
			result.append(army)
	return result
