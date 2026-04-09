extends SceneTree
## Headless: instantiate World3D and run client spawn path (no multiplayer).

func _init():
	call_deferred("_begin")

func _begin():
	var w = load("res://World3D.tscn").instantiate()
	root.add_child(w)
	call_deferred("_spawn_step2", w)

func _spawn_step2(w: Node):
	var data: Array = [{
		"army_id": "T_spawn_test",
		"pid": 1,
		"name": "Test",
		"x": 400.0,
		"y": 300.0,
		"dir": 0.0,
		"initial_count": 2,
		"soldiers": [
			{"name": "Soldier_T_spawn_test_0", "x": 400.0, "y": 300.0},
			{"name": "Soldier_T_spawn_test_1", "x": 430.0, "y": 300.0}
		]
	}]
	w._client_spawn_armies_impl(data)
	var n: int = w.all_units.size()
	if n != 2:
		print("TEST_WORLD3D_SPAWN_FAIL: expected 2 units, got %d" % n)
		quit(1)
		return
	print("TEST_WORLD3D_SPAWN_OK: units=%d" % n)
	quit(0)
