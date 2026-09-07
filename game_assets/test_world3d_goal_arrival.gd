extends SceneTree
## Headless: spawn an army into the World sim, issue a formation move through the same
## order-application path the network echo uses, and wait until every soldier reaches its slot.
## Also asserts the anti-regression properties for the old bugs: distance-to-goal never jumps
## back once the anchor has arrived (no A->B->A teleport) and the moving flag always comes
## with real displacement (no walking-in-place).

const UnitSim := preload("res://sim/UnitSim.gd")

func _init():
	call_deferred("_begin")

func _begin():
	_run_goal_test()

func _run_goal_test() -> void:
	var tree := self
	var w = load("res://World.tscn").instantiate()
	root.add_child(w)
	await tree.process_frame
	await tree.process_frame
	var data: Array = [{
		"army_id": "T_goal_test",
		"pid": 1,
		"name": "Test",
		"x": 415.0,
		"y": 300.0,
		"dir": 0.0,
		"count": 12,
		"first_id": 0,
		"type": 1,
		"spear": true,
	}]
	w._client_spawn_armies_impl(data)
	w._local_sim_enabled = true
	await tree.process_frame
	if w.armies.is_empty():
		print("TEST_WORLD3D_GOALS_FAIL: no army")
		quit(1)
		return
	var army = w.armies[0]
	var sim = w._sim
	var click := Vector2(620.0, 340.0)
	var T: Vector2 = w._clamp_map_v2(click)
	w._apply_move_orders([army.army_id], PackedFloat32Array([T.x, T.y]), PackedFloat32Array([-999.0]), PackedFloat32Array(), false)
	var last_goal_dist := PackedFloat32Array()
	last_goal_dist.resize(sim.count)
	last_goal_dist.fill(INF)
	var backjumps := 0
	var walk_in_place := 0
	var last_tick: int = sim.tick
	for _i in range(1800):
		await tree.physics_frame
		if sim.tick == last_tick:
			continue
		last_tick = sim.tick
		var ok := true
		for id in army.fc.members:
			if not sim.is_alive(id):
				continue
			var d := Vector2(sim.goal_x[id] - sim.pos_x[id], sim.goal_z[id] - sim.pos_z[id]).length()
			if not army.fc.moving and d > last_goal_dist[id] + sim.speed[id] * UnitSim.SIM_DT * 2.0 + 0.5:
				backjumps += 1
			last_goal_dist[id] = d
			var disp := Vector2(sim.pos_x[id] - sim.prev_x[id], sim.pos_z[id] - sim.prev_z[id]).length()
			if (sim.flags[id] & UnitSim.F_MOVING) != 0 and disp < 0.01:
				walk_in_place += 1
			if d > 3.0:
				ok = false
		if ok and not army.fc.moving:
			if backjumps > 0 or walk_in_place > 0:
				print("TEST_WORLD3D_GOALS_FAIL: backjumps=%d walk_in_place=%d" % [backjumps, walk_in_place])
				quit(1)
				return
			var c: Vector2 = sim.army_centroid(army.fc)
			print("TEST_WORLD3D_GOALS_REACHED: centroid=(%.1f,%.1f) target=(%.1f,%.1f)" % [c.x, c.y, T.x, T.y])
			quit(0)
			return
	print("TEST_WORLD3D_GOALS_FAIL: timeout (moving=%s anchor=%s)" % [army.fc.moving, army.fc.anchor])
	quit(1)
