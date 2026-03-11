extends Node2D

const CLICK_RADIUS := 30.0

var units := {}
var game_over := false
var sync_timer := 0.0
var selected_unit = null

func _ready():
	if multiplayer.is_server():
		_spawn_units()

func _spawn_units():
	var spawn_positions = [Vector2(100, 100), Vector2(500, 500)]
	var player_ids = GameState.players.keys()

	for i in range(min(player_ids.size(), spawn_positions.size())):
		var pid = player_ids[i]
		var pname = GameState.players[pid]["name"]
		var pos = spawn_positions[i]

		var unit = preload("res://Unit.tscn").instantiate()
		unit.name = "Unit_%s" % pname
		unit.owner_peer_id = pid
		unit.owner_name = pname
		unit.global_position = pos
		unit.unit_died.connect(_on_unit_died)
		add_child(unit)
		units[pid] = unit

	print("TEST_007: Units spawned - %d units at positions" % units.size())
	for pid in units:
		var u = units[pid]
		print("  Unit '%s' at (%d,%d) owned by peer %d" % [u.owner_name, int(u.global_position.x), int(u.global_position.y), pid])

	rpc("_client_spawn_units", _serialize_units())

@rpc("authority", "reliable")
func _client_spawn_units(data: Array):
	for info in data:
		var unit = preload("res://Unit.tscn").instantiate()
		unit.name = info["name"]
		unit.owner_peer_id = info["peer_id"]
		unit.owner_name = info["player_name"]
		unit.global_position = Vector2(info["x"], info["y"])
		add_child(unit)
		units[info["peer_id"]] = unit
	print("TEST_007: Client received %d units" % units.size())

func _serialize_units() -> Array:
	var data := []
	for pid in units:
		var u = units[pid]
		data.append({
			"name": u.name,
			"peer_id": u.owner_peer_id,
			"player_name": u.owner_name,
			"x": u.global_position.x,
			"y": u.global_position.y
		})
	return data

func _unhandled_input(event):
	if multiplayer.is_server() or game_over:
		return
	if not event is InputEventMouseButton or not event.pressed:
		return

	var mouse_pos = get_global_mouse_position()
	var my_id = multiplayer.get_unique_id()
	var hit = _get_unit_at(mouse_pos)
	var hit_name = hit.owner_name if hit else "none"
	var btn = "LEFT" if event.button_index == MOUSE_BUTTON_LEFT else "RIGHT" if event.button_index == MOUSE_BUTTON_RIGHT else "OTHER"
	print("INPUT: %s click at (%d,%d) hit_unit=%s my_id=%d" % [btn, int(mouse_pos.x), int(mouse_pos.y), hit_name, my_id])

	if event.button_index == MOUSE_BUTTON_LEFT:
		if hit and hit.owner_peer_id == my_id and not hit.is_dead:
			if selected_unit:
				selected_unit.deselect()
			selected_unit = hit
			selected_unit.select()
		else:
			print("INPUT: Left-click did not select (hit=%s, mine=%s)" % [hit_name, hit.owner_peer_id == my_id if hit else false])

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if selected_unit and not selected_unit.is_dead:
			var target = mouse_pos
			var marker = "TEST_009_MOVE" if GameState.local_player_name == "A" else "TEST_009_MOVE_B"
			print("%s: Player issuing move to (%d,%d)" % [marker, int(target.x), int(target.y)])
			selected_unit.rpc_id(1, "request_move", target)
		else:
			print("INPUT: Right-click ignored (no unit selected)")

func _get_unit_at(pos: Vector2):
	var best = null
	var best_dist = CLICK_RADIUS
	for pid in units:
		var u = units[pid]
		if u and not u.is_dead:
			var dist = pos.distance_to(u.global_position)
			if dist < best_dist:
				best_dist = dist
				best = u
	return best

func _physics_process(delta):
	if multiplayer.is_server() and not game_over:
		sync_timer += delta
		if sync_timer >= 0.05:
			sync_timer = 0.0
			_sync_unit_positions()

func _sync_unit_positions():
	var pos_data := {}
	for pid in units:
		var u = units[pid]
		if u and not u.is_dead:
			pos_data[pid] = {"x": u.global_position.x, "y": u.global_position.y, "hp": u.hp}
	rpc("_receive_positions", pos_data)

@rpc("authority", "unreliable")
func _receive_positions(pos_data: Dictionary):
	for pid in pos_data:
		if pid in units and units[pid] and not units[pid].is_dead:
			units[pid].global_position = Vector2(pos_data[pid]["x"], pos_data[pid]["y"])
			units[pid].hp = pos_data[pid]["hp"]

func _on_unit_died(peer_id: int):
	if game_over:
		return
	game_over = true

	var winner_name := ""
	for pid in units:
		if not units[pid].is_dead:
			winner_name = units[pid].owner_name
			break

	print("TEST_011: Game over! Winner: %s" % winner_name)
	rpc("_announce_winner", winner_name)
	_announce_winner(winner_name)

@rpc("authority", "reliable")
func _announce_winner(winner_name: String):
	print("TEST_011: Winner announced: %s" % winner_name)
	get_tree().create_timer(1.0).timeout.connect(func():
		var main = get_tree().root.get_node("Main")
		main.load_game_over(winner_name)
	)

func get_unit_for_peer(peer_id: int):
	return units.get(peer_id, null)

func get_my_unit():
	var my_id = multiplayer.get_unique_id()
	return units.get(my_id, null)
