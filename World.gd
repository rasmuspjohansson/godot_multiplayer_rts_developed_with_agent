extends Node2D

const ARMY_CLICK_RADIUS := 80.0

var armies: Array = []
var all_units: Array = []
var game_over := false
var sync_timer := 0.0
var selected_army = null

func _ready():
	if multiplayer.is_server():
		_spawn_armies()

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
			var army_id = "%s_%d" % [pc["name"], i + 1]
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

func _physics_process(delta):
	if multiplayer.is_server() and not game_over:
		sync_timer += delta
		if sync_timer >= 0.05:
			sync_timer = 0.0
			_sync_unit_positions()

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
