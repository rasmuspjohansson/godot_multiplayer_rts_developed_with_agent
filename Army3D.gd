extends Node3D
## 3D army: same behavior as legacy Army (formation, move, rotate, rout) on XZ map.

signal army_routed(army)

# Map bounds come from `MapConfig` (res://map.json); access as MapConfig.width / MapConfig.height.

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
## "defensive" (stay put / follow move orders) or "aggressive" (server chases closest enemy each tick).
var stance: String = "defensive"

const ROUT_THRESHOLD := 0.3

func _ground_y_at(xz: Vector2) -> float:
	var w = get_parent()
	if w != null and w.has_method("get_ground_height_at"):
		return w.get_ground_height_at(xz.x, xz.y)
	return 0.0

func _clamp_map_xz(v: Vector2) -> Vector2:
	return Vector2(clampf(v.x, 0.0, MapConfig.width), clampf(v.y, 0.0, MapConfig.height))

func get_alive_soldiers() -> Array:
	var alive := []
	for s in soldiers:
		if s and is_instance_valid(s) and not s.get("is_dead"):
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
	var c_xz := Vector2(global_position.x, global_position.z)
	var positions = calculate_formation_positions(c_xz, direction, alive.size())
	for i in range(min(alive.size(), positions.size())):
		if alive[i].has_method("set_move_target"):
			alive[i].set_move_target(positions[i])

func move_army(target: Vector2):
	if is_routed:
		return
	target = _clamp_map_xz(target)
	var gy = _ground_y_at(target)
	var new_p := Vector3(target.x, gy, target.y)
	var d := new_p - global_position
	global_position = new_p
	for s in get_alive_soldiers():
		if s.has_method("set_move_target"):
			var tp: Vector3 = s.global_position + d
			tp.x = clampf(tp.x, 0.0, MapConfig.width)
			tp.z = clampf(tp.z, 0.0, MapConfig.height)
			var g2 = _ground_y_at(Vector2(tp.x, tp.z))
			tp.y = g2 + 11.0
			s.sync_target_position = tp
			s.set_move_target(Vector2(tp.x, tp.z))

func rotate_army(delta_angle: float):
	if is_routed:
		return
	direction += delta_angle
	assign_formation_targets()

func select():
	is_selected = true
	for s in get_alive_soldiers():
		if s.has_method("set_selected"):
			s.set_selected(true)

func deselect():
	is_selected = false
	for s in get_alive_soldiers():
		if s.has_method("set_selected"):
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
	print("TEST_ROUT: Army '%s' routed (%d/%d alive) owner=%s" % [army_id, remaining, initial_count, owner_name])
	for s in get_alive_soldiers():
		s.set("is_dead", true)
		s.queue_free()
	army_routed.emit(self)
