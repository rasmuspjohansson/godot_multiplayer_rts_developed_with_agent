extends SceneTree
## Headless: instantiate World (3D) and run the client spawn path (no multiplayer).
## Units live in the sim (ids), so we count living sim units.

func _init():
	call_deferred("_begin")

func _begin():
	var w = load("res://World.tscn").instantiate()
	root.add_child(w)
	call_deferred("_spawn_step2", w)

func _spawn_step2(w: Node):
	var data: Array = [{
		"army_id": "T_spawn_test",
		"pid": 1,
		"name": "Test",
		"x": 415.0,
		"y": 300.0,
		"dir": 0.0,
		"count": 2,
		"first_id": 0,
		"type": 1,
		"spear": true,
		"xs": PackedFloat32Array([400.0, 430.0]),
		"zs": PackedFloat32Array([300.0, 300.0]),
	}]
	w._client_spawn_armies_impl(data)
	var n: int = 0
	for i in range(w._sim.count):
		if w._sim.is_alive(i):
			n += 1
	if n != 2 or w.armies.size() != 1:
		print("TEST_WORLD3D_SPAWN_FAIL: expected 2 units in 1 army, got %d units / %d armies" % [n, w.armies.size()])
		quit(1)
		return
	var army = w.armies[0]
	if army.army_id != "T_spawn_test" or army.soldier_count() != 2 or not army.has_spear:
		print("TEST_WORLD3D_SPAWN_FAIL: army handle mismatch")
		quit(1)
		return
	print("TEST_WORLD3D_SPAWN_OK: units=%d" % n)
	quit(0)
