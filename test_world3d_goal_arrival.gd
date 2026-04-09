extends SceneTree
## Headless: spawn World3D units, issue anchor-equivalent move_army, wait until all reach sync_target.

func _init():
	call_deferred("_begin")

func _begin():
	_run_goal_test()

func _run_goal_test() -> void:
	var tree := self
	var w = load("res://World3D.tscn").instantiate()
	root.add_child(w)
	await tree.process_frame
	await tree.process_frame
	var data: Array = [{
		"army_id": "T_goal_test",
		"pid": 1,
		"name": "Test",
		"x": 400.0,
		"y": 300.0,
		"dir": 0.0,
		"initial_count": 2,
		"soldiers": [
			{"name": "Soldier_T_goal_test_0", "x": 400.0, "y": 300.0},
			{"name": "Soldier_T_goal_test_1", "x": 430.0, "y": 300.0}
		]
	}]
	w._client_spawn_armies_impl(data)
	await tree.process_frame
	if w.armies.is_empty():
		print("TEST_WORLD3D_GOALS_FAIL: no army")
		quit(1)
		return
	var army = w.armies[0]
	var s0 = w._first_alive_soldier_3d(army)
	if s0 == null:
		print("TEST_WORLD3D_GOALS_FAIL: no soldier")
		quit(1)
		return
	var p0 := Vector2(s0.global_position.x, s0.global_position.z)
	var click := Vector2(520.0, 340.0)
	var d := click - p0
	var a_xz := Vector2(army.global_position.x, army.global_position.z)
	var T: Vector2 = w._clamp_map_v2(a_xz + d)
	army.move_army(T)
	for _i in range(600):
		await tree.process_frame
		var ok := true
		for u in w.all_units:
			if not is_instance_valid(u):
				continue
			var dx: float = u.global_position.x - u.sync_target_position.x
			var dz: float = u.global_position.z - u.sync_target_position.z
			if dx * dx + dz * dz > 9.0:
				ok = false
				break
		if ok:
			print("TEST_WORLD3D_GOALS_REACHED")
			quit(0)
			return
	print("TEST_WORLD3D_GOALS_FAIL: timeout")
	quit(1)
