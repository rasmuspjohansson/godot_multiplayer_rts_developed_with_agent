extends SceneTree
## Headless server-side match: World runs as the (offline) authority with two fake players,
## armies are set aggressive and the sim is driven by calling _physics_process directly, so a
## 3-minute match resolves in a few seconds. Asserts that combat resolves (someone routs) and
## that no army ends up idle while enemies remain (the "stuck armies" symptom).

func _init():
	call_deferred("_begin")

func _begin() -> void:
	var gs = root.get_node("GameState")
	gs.players = {
		1: {"name": "A", "color_index": 0, "ready": true},
		2: {"name": "B", "color_index": 1, "ready": true},
	}
	gs.local_player_name = "server"
	gs.is_auto_test = true
	var w = load("res://World.tscn").instantiate()
	root.add_child(w)
	await process_frame
	await process_frame
	if w.armies.size() < 4:
		print("TEST_SERVER_MATCH_FAIL: expected 4 armies, got %d" % w.armies.size())
		quit(1)
		return
	var sim = w._sim
	var dt := 1.0 / 60.0
	# Let everyone settle, then go aggressive (same as the auto-test flow).
	for _i in range(60):
		w._physics_process(dt)
	for a in w.armies:
		a.fc.set_stance(w._Formation.Stance.AGGRESSIVE)
		a.fc.clear_order()
	var start_alive: int = w._alive_unit_count()
	var routed_seen := false
	var stalled_ticks := 0
	var last_alive := start_alive
	var last_change_t := 0.0
	var t := 0.0
	var winner_reached := false
	while t < 240.0:
		w._physics_process(dt)
		t += dt
		var alive: int = w._alive_unit_count()
		if alive != last_alive:
			last_alive = alive
			last_change_t = t
		for a in w.armies:
			if a.is_routed:
				routed_seen = true
		if w.game_over:
			winner_reached = true
			break
		# Armies need ~40 s to march into contact on S; after that, 45 s without a death = stuck.
		if t > 60.0 and t - last_change_t > 45.0:
			stalled_ticks += 1
			break
	var sides := {}
	for a in w.armies:
		if not a.is_routed:
			sides[a.owner_id] = true
	print("TEST_SERVER_MATCH: t=%.1f start_alive=%d alive=%d routed_seen=%s game_over=%s sides_left=%d" % [
		t, start_alive, last_alive, routed_seen, w.game_over, sides.size()
	])
	for a in w.armies:
		var fc = a.fc
		print("  army=%s owner=%s alive=%d routed=%s order=%d tgt_army=%d moving=%s paused=%s anchor=(%.0f,%.0f)" % [
			a.army_id, a.owner_name, sim.army_alive_count(fc), a.is_routed, fc.order_type, fc.order_target_army,
			fc.moving, fc.paused_for_contact, fc.anchor.x, fc.anchor.y
		])
	if stalled_ticks > 0:
		print("TEST_SERVER_MATCH_FAIL: combat stalled for 30 s with %d sides left" % sides.size())
		quit(1)
		return
	if not routed_seen:
		print("TEST_SERVER_MATCH_FAIL: no army routed")
		quit(1)
		return
	if not winner_reached:
		print("TEST_SERVER_MATCH_FAIL: no winner within %.0f s" % t)
		quit(1)
		return
	print("TEST_SERVER_MATCH_OK")
	quit(0)
