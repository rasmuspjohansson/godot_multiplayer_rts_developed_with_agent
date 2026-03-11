extends Node2D

signal army_routed(army)

var army_id: String = ""
var owner_peer_id: int = 0
var owner_name: String = ""
var direction: float = 0.0
var rows: int = 2
var cols: int = 5
var spacing: float = 30.0
var initial_count: int = 10
var soldiers: Array = []
var is_routed := false
var is_selected := false

const ROUT_THRESHOLD := 0.3

func get_alive_soldiers() -> Array:
	var alive := []
	for s in soldiers:
		if s and is_instance_valid(s) and not s.is_dead:
			alive.append(s)
	return alive

func get_alive_count() -> int:
	return get_alive_soldiers().size()

func calculate_formation_positions(center: Vector2, dir: float, count: int) -> Array:
	var positions := []
	if count == 0:
		return positions
	var r = rows
	var c = ceili(float(count) / float(r))
	if c == 0:
		c = 1
	var idx := 0
	for row in range(r):
		for col in range(c):
			if idx >= count:
				break
			var local_x = (col - (c - 1) / 2.0) * spacing
			var local_y = (row - (r - 1) / 2.0) * spacing
			var offset = Vector2(local_x, local_y).rotated(dir)
			positions.append(center + offset)
			idx += 1
	return positions

func assign_formation_targets():
	if is_routed:
		return
	var alive = get_alive_soldiers()
	var positions = calculate_formation_positions(global_position, direction, alive.size())
	for i in range(min(alive.size(), positions.size())):
		alive[i].set_move_target(positions[i])

func move_army(target: Vector2):
	if is_routed:
		return
	global_position = target
	assign_formation_targets()

func rotate_army(delta_angle: float):
	if is_routed:
		return
	direction += delta_angle
	assign_formation_targets()

func select():
	is_selected = true
	for s in get_alive_soldiers():
		s.set_selected(true)
	print("TEST_008_SELECT: Army '%s' selected" % army_id)

func deselect():
	is_selected = false
	for s in get_alive_soldiers():
		s.set_selected(false)

func on_soldier_died(_peer_id: int):
	if is_routed:
		return

	var alive = get_alive_count()
	print("Army %s: soldier died, %d/%d alive" % [army_id, alive, initial_count])

	if alive > 0 and float(alive) / float(initial_count) >= ROUT_THRESHOLD:
		repack_formation()
	else:
		_do_rout()

func repack_formation():
	assign_formation_targets()

func _do_rout():
	is_routed = true
	var remaining = get_alive_count()
	print("TEST_ROUT: Army '%s' routed (%d/%d alive)" % [army_id, remaining, initial_count])

	for s in get_alive_soldiers():
		s.is_dead = true
		s.queue_free()

	army_routed.emit(self)
