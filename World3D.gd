extends Node3D
## 3D world scene: camera control (C2), map/raycast (C3), 3D units (C4).
## Same logical size as 2D: x/z = 1280x720, ground at y=0.

const MAP_WIDTH := 1280
const MAP_HEIGHT := 720  # used as Z in 3D
const CAMERA_PITCH_DEG := 45.0
const CAMERA_MIN_DISTANCE := 200.0
const CAMERA_MAX_DISTANCE := 1200.0
const CAMERA_PAN_SPEED := 400.0
const CAMERA_ZOOM_SPEED := 80.0
const ARMY_CLICK_RADIUS := 80.0
# Client: only snap to server HERE when error exceeds this (real desync only)
const CORRECTION_THRESHOLD := 120.0

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
var selected_army = null

func _ready():
	_look_at = Vector3(MAP_WIDTH / 2.0, 0, MAP_HEIGHT / 2.0)
	_setup_camera()
	_setup_topbar()
	_setup_draft_menu()

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
	_camera_pivot.position = _look_at
	_camera.reparent(_camera_pivot)
	var rad = deg_to_rad(CAMERA_PITCH_DEG)
	_camera.position = Vector3(0, _camera_distance * sin(rad), _camera_distance * cos(rad))
	_camera.look_at(_camera_pivot.position, Vector3.UP)
	_update_camera_position()

func _update_camera_position():
	if _camera_pivot == null:
		return
	_camera_pivot.position = _look_at
	if _camera:
		var rad = deg_to_rad(CAMERA_PITCH_DEG)
		_camera.position = Vector3(0, _camera_distance * sin(rad), _camera_distance * cos(rad))
		_camera.look_at(_camera_pivot.global_position, Vector3.UP)

func _input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_pan_drag = event.pressed
			if event.pressed:
				_last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(CAMERA_MIN_DISTANCE, _camera_distance - CAMERA_ZOOM_SPEED)
			_update_camera_position()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(CAMERA_MAX_DISTANCE, _camera_distance + CAMERA_ZOOM_SPEED)
			_update_camera_position()
	elif event is InputEventMouseMotion and _pan_drag:
		var delta = event.position - _last_mouse
		_last_mouse = event.position
		_look_at.x -= delta.x * 0.5
		_look_at.z -= delta.y * 0.5
		_look_at.x = clampf(_look_at.x, 0, MAP_WIDTH)
		_look_at.z = clampf(_look_at.z, 0, MAP_HEIGHT)
		_update_camera_position()

func _process(_delta: float):
	if _camera_pivot == null:
		return
	var pan = Vector3.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= CAMERA_PAN_SPEED
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += CAMERA_PAN_SPEED
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.z -= CAMERA_PAN_SPEED
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.z += CAMERA_PAN_SPEED
	if pan != Vector3.ZERO:
		_look_at += pan * get_process_delta_time()
		_look_at.x = clampf(_look_at.x, 0, MAP_WIDTH)
		_look_at.z = clampf(_look_at.z, 0, MAP_HEIGHT)
		_update_camera_position()

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

func _raycast_ground() -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var viewport = get_viewport()
	var cam = _camera
	var from = cam.global_position
	var to = from + cam.project_ray_normal(get_viewport().get_mouse_position()) * 10000.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var hit = space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	return hit.position

func _unhandled_input(event: InputEvent):
	if game_over:
		return
	if event is InputEventMouseButton and event.pressed:
		_handle_mouse(event)
	elif event is InputEventKey and event.pressed:
		_handle_key(event)

func _handle_mouse(event: InputEventMouseButton):
	var hit = _raycast_ground()
	var my_id = multiplayer.get_unique_id()
	if event.button_index == MOUSE_BUTTON_LEFT:
		var army = _get_army_at(Vector2(hit.x, hit.z), my_id)
		if army:
			if selected_army:
				selected_army.deselect()
			selected_army = army
			selected_army.select()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if selected_army and not selected_army.is_routed:
			var target = Vector2(hit.x, hit.z)
			var marker = "TEST_009_MOVE" if GameState.local_player_name == "A" else "TEST_009_MOVE_B"
			print("%s: Moving army '%s' to (%d,%d)" % [marker, selected_army.army_id, int(target.x), int(target.y)])
			rpc_id(1, "_server_move_army", selected_army.army_id, target)

func _handle_key(event: InputEventKey):
	if selected_army == null or selected_army.is_routed:
		return
	var rotate_amount = deg_to_rad(15.0)
	if event.keycode == KEY_LEFT or event.keycode == KEY_Q:
		rpc_id(1, "_server_rotate_army", selected_army.army_id, -rotate_amount)
	elif event.keycode == KEY_RIGHT or event.keycode == KEY_E:
		rpc_id(1, "_server_rotate_army", selected_army.army_id, rotate_amount)

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

@rpc("authority", "reliable")
func _client_spawn_armies(data: Array):
	for ad in data:
		var army = Node3D.new()
		army.set_script(preload("res://Army3D.gd"))
		army.army_id = ad["army_id"]
		army.owner_peer_id = ad["pid"]
		army.owner_name = ad["name"]
		army.global_position = Vector3(ad["x"], 0, ad["y"])
		army.direction = ad["dir"]
		army.name = "Army_%s" % ad["army_id"]
		add_child(army)
		armies.append(army)
		for sd in ad["soldiers"]:
			var unit = Node3D.new()
			unit.set_script(preload("res://Unit3D.gd"))
			unit.name = sd["name"]
			unit.owner_peer_id = ad["pid"]
			unit.owner_name = ad["name"]
			unit.army_id = ad["army_id"]
			var pos = Vector3(sd["x"], 0, sd["y"])
			unit.global_position = pos
			unit.sync_target_position = pos
			add_child(unit)
			army.soldiers.append(unit)
			all_units.append(unit)
	print("TEST_007: Client received %d armies" % armies.size())

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
	army.army_id = ad["army_id"]
	army.owner_peer_id = ad["pid"]
	army.owner_name = ad["name"]
	army.global_position = Vector3(ad["x"], 0, ad["y"])
	army.direction = ad["dir"]
	army.name = "Army_%s" % ad["army_id"]
	add_child(army)
	armies.append(army)
	for sd in ad["soldiers"]:
		var unit = Node3D.new()
		unit.set_script(preload("res://Unit3D.gd"))
		unit.name = sd["name"]
		unit.owner_peer_id = ad["pid"]
		unit.owner_name = ad["name"]
		unit.army_id = ad["army_id"]
		var pos = Vector3(sd["x"], 0, sd["y"])
		unit.global_position = pos
		unit.sync_target_position = pos
		add_child(unit)
		army.soldiers.append(unit)
		all_units.append(unit)
	if ad.has("stop_x") and ad.has("stop_y"):
		army.move_army(Vector2(ad["stop_x"], ad["stop_y"]))
	print("TEST_DRAFT_SUCCESS: Client received drafted army '%s'" % army.army_id)

@rpc("authority", "unreliable")
func _receive_positions(pos_data: Array, dead_names: Array = []):
	for pd in pos_data:
		var node = get_node_or_null(NodePath(str(pd["n"])))
		if node and is_instance_valid(node):
			if node.get("is_dead"):
				continue
			var here = Vector3(pd["x"], 0, pd["y"])
			var there = Vector3(pd.get("tx", pd["x"]), 0, pd.get("ty", pd["y"]))
			var err = node.global_position.distance_to(here)
			if err > CORRECTION_THRESHOLD:
				node.global_position = here
			node.set("sync_target_position", there)
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
	if selected_army == army:
		selected_army = null
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
