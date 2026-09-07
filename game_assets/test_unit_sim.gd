extends SceneTree
## Headless UnitSim checks (no World, no walkability): formation move arrives, moving flag
## implies displacement, distance-to-goal never jumps back (no teleport), combat kills and
## routs, positions stay finite and on-map, NetSync snapshots round-trip, and a 2000-unit tick
## fits the budget.

const UnitSim := preload("res://sim/UnitSim.gd")
const Formation := preload("res://sim/FormationController.gd")
const NetSync := preload("res://sim/NetSync.gd")

var _fail := 0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		print("TEST_UNIT_SIM_FAIL: %s" % msg)

func _spawn_army(sim, aid: String, pid: int, x: float, z: float, n: int, t: int, dir: float):
	var fc = Formation.new()
	fc.army_id = aid
	fc.owner_pid = pid
	fc.owner_name = aid
	fc.initial_count = n
	fc.direction = dir
	fc.rows = fc.default_rows_for(n)
	fc.anchor = Vector2(x, z)
	var idx = sim.add_army(fc)
	var offs: PackedVector2Array = fc.slot_offsets(n)
	for k in range(n):
		var o: Vector2 = offs[k].rotated(dir)
		sim.add_unit(sim.count, x + o.x, z + o.y, pid, idx, t)
	fc.packed_count = n
	fc.anchor_speed = sim.army_min_speed(fc) * Formation.ANCHOR_SPEED_SCALE
	sim._assign_slots(fc)
	return fc

func _init():
	_test_move_and_flags()
	_test_combat_and_rout()
	_test_snapshot_roundtrip()
	_test_budget()
	if _fail == 0:
		print("TEST_UNIT_SIM_OK")
		quit(0)
	else:
		print("TEST_UNIT_SIM_FAILED: %d" % _fail)
		quit(1)

func _test_move_and_flags() -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var a = _spawn_army(sim, "A1", 1, 200.0, 300.0, 40, UnitSim.UnitType.SPEARMAN, 0.0)
	sim.recentre_anchor(a)
	a.issue_move(Vector2(500.0, 320.0))
	var last_goal_dist := PackedFloat32Array()
	last_goal_dist.resize(sim.count)
	last_goal_dist.fill(INF)
	var backjumps := 0
	var walk_without_move := 0
	var arrived_tick := -1
	for step in range(20 * 90):
		sim.step(UnitSim.SIM_DT)
		var all_close := true
		for i in range(sim.count):
			var d := Vector2(sim.goal_x[i] - sim.pos_x[i], sim.goal_z[i] - sim.pos_z[i]).length()
			# A unit should never get more than one tick of travel further from its goal
			# unless the goal itself moved (goal moves with the anchor, so compare when static).
			if not a.moving and d > last_goal_dist[i] + sim.speed[i] * UnitSim.SIM_DT * 2.0 + 0.5:
				backjumps += 1
			last_goal_dist[i] = d
			var disp := Vector2(sim.pos_x[i] - sim.prev_x[i], sim.pos_z[i] - sim.prev_z[i]).length()
			if (sim.flags[i] & UnitSim.F_MOVING) != 0 and disp < 0.01:
				walk_without_move += 1
			if d > 2.0:
				all_close = false
			_check(is_finite(sim.pos_x[i]) and is_finite(sim.pos_z[i]), "non-finite position")
			_check(sim.pos_x[i] >= 0.0 and sim.pos_x[i] <= 1280.0, "off-map x")
		if all_close and not a.moving and arrived_tick < 0:
			arrived_tick = step
			break
	_check(arrived_tick > 0, "formation never arrived (moving=%s anchor=%s)" % [a.moving, a.anchor])
	_check(backjumps == 0, "distance-to-goal jumped back %d times" % backjumps)
	_check(walk_without_move == 0, "moving flag without displacement %d times" % walk_without_move)
	_check(a.order_type == Formation.OrderType.NONE, "MOVE order not cleared on arrival")
	print("TEST_UNIT_SIM_MOVE: arrived_tick=%d backjumps=%d anchor=(%.1f,%.1f)" % [
		arrived_tick, backjumps, a.anchor.x, a.anchor.y
	])

func _test_combat_and_rout() -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	sim.damage_multiplier = 4.0
	var a = _spawn_army(sim, "A1", 1, 300.0, 300.0, 20, UnitSim.UnitType.KNIGHT, 0.0)
	var b = _spawn_army(sim, "B1", 2, 380.0, 300.0, 10, UnitSim.UnitType.CLUBMAN, PI)
	a.set_stance(Formation.Stance.AGGRESSIVE)
	sim.recentre_anchor(a)
	a.issue_attack_army(b.index)
	var died_total := 0
	var routed := false
	for step in range(20 * 120):
		sim.step(UnitSim.SIM_DT)
		died_total += sim.died_ids.size()
		if sim.routed_armies.size() > 0:
			routed = true
			break
	_check(died_total > 0, "no deaths in combat")
	_check(routed, "weaker army never routed")
	_check(b.is_routed, "B not flagged routed")
	_check(a.order_type == Formation.OrderType.NONE or sim._attack_order_target_xz(a).x == INF, "attack order still targets dead army")
	print("TEST_UNIT_SIM_COMBAT: died=%d routed=%s a_alive=%d" % [died_total, routed, sim.army_alive_count(a)])

func _test_budget() -> void:
	var sim = UnitSim.new()
	sim.setup(null, 3840.0, 2160.0, true)
	var armies := []
	for k in range(10):
		armies.append(_spawn_army(sim, "A%d" % k, 1, 400.0 + float(k % 5) * 250.0, 400.0 + float(k / 5) * 250.0, 100, UnitSim.UnitType.SPEARMAN, 0.0))
	for k in range(10):
		armies.append(_spawn_army(sim, "B%d" % k, 2, 2400.0 + float(k % 5) * 250.0, 1400.0 + float(k / 5) * 250.0, 100, UnitSim.UnitType.CLUBMAN, PI))
	for k in range(20):
		var fc = armies[k]
		sim.recentre_anchor(fc)
		fc.set_stance(Formation.Stance.AGGRESSIVE)
		fc.issue_move(Vector2(1900.0 + float(k % 5) * 40.0, 1100.0 + float(k / 5) * 40.0))
	var worst := 0.0
	var total := 0.0
	var steps := 200
	for s in range(steps):
		var t0 := Time.get_ticks_usec()
		sim.step(UnitSim.SIM_DT)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		total += ms
	print("TEST_UNIT_SIM_BUDGET: units=%d avg_ms=%.2f max_ms=%.2f alive=%d" % [sim.count, total / float(steps), worst, sim.alive_count])
	_check(total / float(steps) < 40.0, "2000-unit tick too slow: %.2f ms" % (total / float(steps)))

## NetSync: pack a snapshot on a "server" sim, unpack it and apply it to a "client" sim whose
## units were displaced; the client must land within the quantisation error, stale ticks must be
## ignored and every chunk must respect the MTU budget.
func _test_snapshot_roundtrip() -> void:
	var server = UnitSim.new()
	server.setup(null, 1280.0, 720.0, true)
	var client = UnitSim.new()
	client.setup(null, 1280.0, 720.0, false)
	_spawn_army(server, "S1", 1, 300.0, 300.0, 400, UnitSim.UnitType.SPEARMAN, 0.0)
	_spawn_army(client, "S1", 1, 300.0, 300.0, 400, UnitSim.UnitType.SPEARMAN, 0.0)
	for i in range(server.count):
		server.pos_x[i] += 100.0
		server.hp[i] = 37.0
		server.dirty_tick[i] = 5
	server.tick = 5
	var net_s = NetSync.new()
	net_s.setup(1280.0, 720.0)
	var net_c = NetSync.new()
	net_c.setup(1280.0, 720.0)
	var ids: PackedInt32Array = net_s.select_units(server, 5, 10000)
	_check(ids.size() == server.count, "select_units picks every dirty unit (got %d)" % ids.size())
	var chunks: Array = net_s.pack_chunks(server, ids, 5)
	_check(chunks.size() >= 3, "400 units need several chunks (got %d)" % chunks.size())
	var applied := 0
	for c in chunks:
		_check(c.size() <= NetSync.MAX_CHUNK_BYTES, "chunk within MTU budget (%d bytes)" % c.size())
		applied += net_c.apply_snapshot(client, net_c.unpack(c))
	_check(applied == server.count, "all records applied (%d)" % applied)
	var q: float = 1280.0 / 65535.0
	var worst := 0.0
	for i in range(client.count):
		# 100 units of error is above the snap threshold, so the client position is authoritative now.
		worst = maxf(worst, absf(client.pos_x[i] - server.pos_x[i]))
		_check(absf(client.hp[i] - 37.0) <= 1.0, "hp percent round-trips (unit %d hp=%.1f)" % [i, client.hp[i]])
	_check(worst <= q + 0.01, "quantised position error %.4f <= %.4f" % [worst, q])
	# A stale snapshot (older tick) must not move anything.
	for i in range(server.count):
		server.pos_x[i] -= 50.0
	var stale: Array = net_s.pack_chunks(server, ids, 4)
	var stale_applied := 0
	for c in stale:
		stale_applied += net_c.apply_snapshot(client, net_c.unpack(c))
	_check(stale_applied == 0, "stale tick ignored (applied %d)" % stale_applied)
	# Garbage must be rejected, not crash.
	_check(net_c.unpack(PackedByteArray([1, 2, 3])).is_empty(), "malformed snapshot rejected")
	print("TEST_UNIT_SIM_SNAPSHOT: chunks=%d applied=%d worst_err=%.4f" % [chunks.size(), applied, worst])
