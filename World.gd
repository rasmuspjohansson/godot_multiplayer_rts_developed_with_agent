extends Node2D

const ARMY_CLICK_RADIUS := 80.0
const CP_PEACE_SECONDS := 5.0
const CAPTURE_RADIUS_SEEK := 120.0

var armies: Array = []
var all_units: Array = []
var capture_points: Array = []
var top_bar = null
var game_over := false
var sync_timer := 0.0
var selected_army = null
var army_time_at_cp := {}
var army_follow_target := {}

func _ready():
	if multiplayer.is_server():
		GameState.reset_match_state()
		_spawn_armies()
		_spawn_capture_points()
	_setup_topbar()

func _spawn_armies():
	var player_ids = GameState.players.keys()
	if player_ids.size() < 2:
		print("ERROR: Need 2 players to spawn armies")
		return

	var spawn_configs = [
		{"pid": player_ids[0], "name": GameState.players[player_ids[0]]["name"], "armies": [
			{"pos": Vector2(200, 250), "dir": 0.0},
			{"pos": Vector2(200, 450), "dir": 0.0}
		]},
		{"pid": player_ids[1], "name": GameState.players[player_ids[1]]["name"], "armies": [
			{"pos": Vector2(1050, 250), "dir": PI},
			{"pos": Vector2(1050, 450), "dir": PI}
		]}
	]

	for pc in spawn_configs:
		for i in range(pc["armies"].size()):
			var ac = pc["armies"][i]
			var army_id = "P%d_%d" % [pc["pid"], i + 1]
			var army = _create_army(army_id, pc["pid"], pc["name"], ac["pos"], ac["dir"])
			armies.append(army)

	print("TEST_007: %d armies spawned (2 per player, 10 soldiers each)" % armies.size())
	for a in armies:
		print("  Army '%s' at (%d,%d) dir=%.1f owner=%s" % [a.army_id, int(a.global_position.x), int(a.global_position.y), a.direction, a.owner_name])

	rpc("_client_spawn_armies", _serialize_armies())

func _create_army(aid: String, pid: int, pname: String, pos: Vector2, dir: float) -> Node2D:
	var army_script = preload("res://Army.gd")
	var army = Node2D.new()
	army.set_script(army_script)
	army.army_id = aid
	army.owner_peer_id = pid
	army.owner_name = pname
	army.global_position = pos
	army.direction = dir
	army.name = "Army_%s" % aid
	army.army_routed.connect(_on_army_routed)
	add_child(army)

	var formation_positions = army.calculate_formation_positions(pos, dir, army.initial_count)
	for idx in range(army.initial_count):
		var unit = preload("res://Unit.tscn").instantiate()
		unit.name = "Soldier_%s_%d" % [aid, idx]
		unit.owner_peer_id = pid
		unit.owner_name = pname
		unit.army_id = aid
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
		army.name = "Army_%s" % ad["army_id"]
		add_child(army)
		armies.append(army)

		for sd in ad["soldiers"]:
			var unit = preload("res://Unit.tscn").instantiate()
			unit.name = sd["name"]
			unit.owner_peer_id = ad["pid"]
			unit.owner_name = ad["name"]
			unit.army_id = ad["army_id"]
			unit.global_position = Vector2(sd["x"], sd["y"])
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
			"soldiers": soldier_data
		})
	return data

func _spawn_capture_points():
	var cp_configs = [
		{"id": "Stables", "type": "Stables", "pos": Vector2(500, 200)},
		{"id": "Blacksmith", "type": "Blacksmith", "pos": Vector2(780, 500)}
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

func _unhandled_input(event):
	if multiplayer.is_server() or game_over:
		return

	if event is InputEventMouseButton and event.pressed:
		_handle_mouse(event)
	elif event is InputEventKey and event.pressed:
		_handle_key(event)

func _handle_mouse(event: InputEventMouseButton):
	var mouse_pos = get_global_mouse_position()
	var my_id = multiplayer.get_unique_id()

	if event.button_index == MOUSE_BUTTON_LEFT:
		var army = _get_army_at(mouse_pos, my_id)
		if army:
			print("INPUT: LEFT click at (%d,%d) - selecting army '%s'" % [int(mouse_pos.x), int(mouse_pos.y), army.army_id])
			if selected_army:
				selected_army.deselect()
			selected_army = army
			selected_army.select()
		else:
			print("INPUT: LEFT click at (%d,%d) - no own army nearby" % [int(mouse_pos.x), int(mouse_pos.y)])

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if selected_army and not selected_army.is_routed:
			var target = mouse_pos
			var marker = "TEST_009_MOVE" if GameState.local_player_name == "A" else "TEST_009_MOVE_B"
			print("INPUT: RIGHT click at (%d,%d) - moving army '%s' to target" % [int(target.x), int(target.y), selected_army.army_id])
			print("%s: Moving army '%s' to (%d,%d)" % [marker, selected_army.army_id, int(target.x), int(target.y)])
			rpc_id(1, "_server_move_army", selected_army.army_id, target)
		else:
			print("INPUT: RIGHT click at (%d,%d) - ignored (no army selected or army routed)" % [int(mouse_pos.x), int(mouse_pos.y)])

func _handle_key(event: InputEventKey):
	if selected_army == null or selected_army.is_routed:
		print("INPUT: KEY pressed but no army selected or army routed")
		return
	var rotate_amount = deg_to_rad(15.0)
	if event.keycode == KEY_LEFT or event.keycode == KEY_Q:
		print("INPUT: KEY_LEFT/Q - rotating army '%s' by -15 deg" % selected_army.army_id)
		rpc_id(1, "_server_rotate_army", selected_army.army_id, -rotate_amount)
	elif event.keycode == KEY_RIGHT or event.keycode == KEY_E:
		print("INPUT: KEY_RIGHT/E - rotating army '%s' by +15 deg" % selected_army.army_id)
		rpc_id(1, "_server_rotate_army", selected_army.army_id, rotate_amount)

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

func _physics_process(delta):
	if multiplayer.is_server() and not game_over:
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
				pos_data.append({"n": u.name, "x": u.global_position.x, "y": u.global_position.y, "hp": u.hp})
			else:
				dead_names.append(u.name)
	rpc("_receive_positions", pos_data, dead_names)

@rpc("authority", "unreliable")
func _receive_positions(pos_data: Array, dead_names: Array = []):
	for pd in pos_data:
		var node = get_node_or_null(NodePath(str(pd["n"])))
		if node and not node.is_dead:
			node.global_position = Vector2(pd["x"], pd["y"])
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
		game_over = true
		var winner_name := ""
		for a in armies:
			if a.owner_peer_id != loser_pid:
				winner_name = a.owner_name
				break
		print("TEST_011: Both armies of '%s' routed. Winner: %s" % [loser_name, winner_name])
		rpc("_announce_winner", winner_name)
		_announce_winner(winner_name)

@rpc("authority", "reliable")
func _client_army_routed(army_id: String):
	var army = _find_army(army_id)
	if army == null:
		return
	army.is_routed = true
	if selected_army == army:
		selected_army = null
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
