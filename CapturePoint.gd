extends Node2D

signal ownership_changed(cp_id: String, owner_pid: int)

const CAPTURE_RADIUS := 120.0
const RESOURCE_INTERVAL := 2.0

var cp_id: String = ""
var cp_type: String = ""
var owner_pid: int = 0
var resource_timer: float = 0.0

var _circle: Polygon2D = null
var _last_owner_pid := -999

func _ready():
	_circle = get_node_or_null("Circle")
	_update_owner_visual()

func _process(_delta):
	if _last_owner_pid != owner_pid:
		_last_owner_pid = owner_pid
		_update_owner_visual()

func _update_owner_visual():
	if _circle == null:
		return
	if owner_pid == 0:
		_circle.color = Color(0.5, 0.5, 0.5, 0.3)
	else:
		if GameState.players.has(owner_pid):
			var ci = GameState.players[owner_pid].get("color_index", 0)
			if ci >= 0 and ci < GameState.PLAYER_COLORS.size():
				var c = GameState.PLAYER_COLORS[ci]
				_circle.color = Color(c.r, c.g, c.b, 0.5)
			else:
				_circle.color = Color(0.5, 0.5, 0.5, 0.3)
		else:
			_circle.color = Color(0.5, 0.5, 0.5, 0.3)

func _physics_process(delta):
	if not multiplayer.is_server():
		return
	_check_capture()
	if owner_pid != 0:
		resource_timer += delta
		if resource_timer >= RESOURCE_INTERVAL:
			resource_timer -= RESOURCE_INTERVAL
			_produce_resource()

func _check_capture():
	var world = get_parent()
	if world == null:
		return
	var nearby_pids := {}
	for child in world.get_children():
		if not child is CharacterBody2D:
			continue
		if child.is_dead:
			continue
		var dist = global_position.distance_to(child.global_position)
		if dist <= CAPTURE_RADIUS:
			nearby_pids[child.owner_peer_id] = true

	if nearby_pids.size() == 1:
		var new_owner = nearby_pids.keys()[0]
		if new_owner != owner_pid:
			var old_owner = owner_pid
			owner_pid = new_owner
			var owner_name = _get_player_name(owner_pid)
			if old_owner == 0:
				print("TEST_CAPTURE: %s '%s' captured by %s (pid=%d)" % [cp_type, cp_id, owner_name, owner_pid])
			else:
				print("TEST_CAPTURE: %s '%s' taken over by %s (pid=%d)" % [cp_type, cp_id, owner_name, owner_pid])
			ownership_changed.emit(cp_id, owner_pid)

func _produce_resource():
	if owner_pid == 0:
		return
	var key := "horses" if cp_type == "Stables" else "spears"
	if not GameState.resources.has(owner_pid):
		GameState.resources[owner_pid] = {"horses": 0, "spears": 0}
	GameState.resources[owner_pid][key] += 1
	var total = GameState.resources[owner_pid][key]
	print("TEST_RESOURCE: %s '%s' produced 1 %s for pid=%d (total=%d)" % [cp_type, cp_id, key, owner_pid, total])

func _get_player_name(pid: int) -> String:
	if GameState.players.has(pid):
		return GameState.players[pid]["name"]
	return str(pid)

func get_owner_name() -> String:
	if owner_pid == 0:
		return "---"
	return _get_player_name(owner_pid)
