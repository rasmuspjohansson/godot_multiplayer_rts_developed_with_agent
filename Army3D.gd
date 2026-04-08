extends Node3D
## 3D representation of an army for World3D (client-only).
## Same interface as Army (army_id, owner_peer_id, select, deselect, is_routed, move_army).

var army_id: String = ""
var owner_peer_id: int = 0
var owner_name: String = ""
var direction: float = 0.0
var soldiers: Array = []
var is_routed := false
var is_selected := false

func get_alive_soldiers() -> Array:
	var alive := []
	for s in soldiers:
		if s and is_instance_valid(s) and not s.get("is_dead"):
			alive.append(s)
	return alive

func move_army(target: Vector2):
	if is_routed:
		return
	# In 3D we use (target.x, 0, target.y)
	global_position = Vector3(target.x, 0, target.y)
	for s in soldiers:
		if is_instance_valid(s):
			s.sync_target_position = Vector3(target.x, 0, target.y)

func select():
	is_selected = true
	for s in soldiers:
		if is_instance_valid(s) and s.has_method("set_selected"):
			s.set_selected(true)
	print("TEST_008_SELECT: Army '%s' selected" % army_id)

func deselect():
	is_selected = false
	for s in soldiers:
		if is_instance_valid(s) and s.has_method("set_selected"):
			s.set_selected(false)
