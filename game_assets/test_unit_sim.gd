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
	_test_speed_ramp()
	_test_double_time()
	_test_spear_vs_horse()
	_test_knight_bonuses()
	_test_height_rules()
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

func _test_speed_ramp() -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var army = _spawn_army(sim, "R", 1, 200.0, 300.0, 1, UnitSim.UnitType.KNIGHT, 0.0)
	var id: int = army.members[0]
	var top: float = sim.speed[id]
	# Parked army, goal set by hand, so the target is the flat max and not the march catch-up.
	army.clear_order()
	army.slots_dirty = false
	sim.goal_x[id] = 900.0
	sim.goal_z[id] = 300.0
	sim.step(UnitSim.SIM_DT)
	var first: float = sim._cruise[id]
	_check(first < top * 0.2, "first step should be well under full speed (%.2f)" % first)
	for _i in range(39):
		sim.step(UnitSim.SIM_DT)
	var built: float = sim._cruise[id]
	_check(built > top * 0.9 and built < top * 1.05, "about 95%% of flat speed after 2s (%.2f vs %.2f)" % [built, top])
	sim._cruise[id] = top * 1.25
	sim.step(UnitSim.SIM_DT)
	var carried: float = sim._cruise[id]
	_check(carried > top * 1.1, "downhill speed carries onto flat ground (%.2f)" % carried)
	for _i in range(39):
		sim.step(UnitSim.SIM_DT)
	_check(sim._cruise[id] < top * 1.05, "carried speed eases back to flat in about 2s (%.2f)" % sim._cruise[id])
	sim.goal_x[id] = sim.pos_x[id]
	sim.goal_z[id] = sim.pos_z[id]
	sim._cruise[id] = top
	sim.step(UnitSim.SIM_DT)
	_check(sim._cruise[id] == 0.0, "reaching the goal zeros cruise")
	sim.goal_x[id] = 900.0
	sim.goal_z[id] = 320.0
	sim.step(UnitSim.SIM_DT)
	_check(sim._cruise[id] < top * 0.2, "the next move starts from a standstill")
	print("TEST_UNIT_SIM_RAMP: first=%.2f built=%.2f carried=%.2f" % [first, built, carried])

func _test_double_time() -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var army = _spawn_army(sim, "D", 1, 200.0, 300.0, 8, UnitSim.UnitType.KNIGHT, 0.0)
	var top: float = sim.speed[army.members[0]]
	sim.recentre_anchor(army)
	army.issue_move(Vector2(900.0, 300.0))
	army.double_time = true
	var ticks := int(round(5.0 / UnitSim.SIM_DT))
	for _i in range(ticks):
		sim.step(UnitSim.SIM_DT)
	_check(is_equal_approx(army.tiredness, -8.0), "moving in double time reaches -8 in 5s (%.2f)" % army.tiredness)
	_check(not army.double_time, "double time turns off at -8")
	var boosted: float = army.cruise_speed
	_check(boosted > top, "double time raised the march above flat speed (%.2f vs %.2f)" % [boosted, top])
	army.clear_order()
	for _i in range(ticks):
		sim.step(UnitSim.SIM_DT)
	_check(is_equal_approx(army.tiredness, 0.0), "standing still rests back to 0 (%.2f)" % army.tiredness)
	army.double_time = true
	army.tiredness = -4.0
	for _i in range(ticks):
		sim.step(UnitSim.SIM_DT)
	_check(is_equal_approx(army.tiredness, 0.0), "double time while standing still still rests (%.2f)" % army.tiredness)
	print("TEST_UNIT_SIM_DOUBLE: tired_after_move=-8.0 cruise=%.2f rested=%.1f" % [boosted, army.tiredness])

func _test_spear_vs_horse() -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var spear = _spawn_army(sim, "S", 1, 100.0, 100.0, 1, UnitSim.UnitType.SPEARMAN, 0.0)
	var knight = _spawn_army(sim, "K", 2, 200.0, 100.0, 1, UnitSim.UnitType.KNIGHT, PI)
	var horse = _spawn_army(sim, "H", 2, 300.0, 100.0, 1, UnitSim.UnitType.HORSE_ARCHER, PI)
	var club = _spawn_army(sim, "C", 2, 400.0, 100.0, 1, UnitSim.UnitType.CLUBMAN, PI)
	var club_atk = _spawn_army(sim, "C2", 1, 500.0, 100.0, 1, UnitSim.UnitType.CLUBMAN, 0.0)
	var sid: int = spear.members[0]
	var kid: int = knight.members[0]
	var hid: int = horse.members[0]
	var cid: int = club.members[0]
	var aid: int = club_atk.members[0]
	var spear_knight := _hit_damage(sim, sid, kid)
	var spear_horse := _hit_damage(sim, sid, hid)
	var spear_club := _hit_damage(sim, sid, cid)
	var club_knight := _hit_damage(sim, aid, kid)
	_check(is_equal_approx(spear_knight, 14.0 - sim.defense[kid]), "spear vs knight should be attack 14")
	_check(is_equal_approx(spear_horse, 14.0 - sim.defense[hid]), "spear vs horse archer should be attack 14")
	_check(is_equal_approx(spear_club, 13.0 - sim.defense[cid]), "spear vs clubman stays attack 13")
	_check(is_equal_approx(club_knight, sim.attack[aid] - sim.defense[kid]), "clubman vs knight has no spear bonus")
	print("TEST_UNIT_SIM_SPEAR: knight=%.1f horse=%.1f club=%.1f clubman=%.1f" % [
		spear_knight, spear_horse, spear_club, club_knight
	])

func _test_knight_bonuses() -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var knight = _spawn_army(sim, "K", 1, 100.0, 100.0, 1, UnitSim.UnitType.KNIGHT, 0.0)
	var club = _spawn_army(sim, "C", 2, 140.0, 100.0, 1, UnitSim.UnitType.CLUBMAN, PI)
	var spear = _spawn_army(sim, "S", 2, 180.0, 100.0, 1, UnitSim.UnitType.SPEARMAN, PI)
	var horse = _spawn_army(sim, "H", 2, 220.0, 100.0, 1, UnitSim.UnitType.HORSE_ARCHER, PI)
	var kid: int = knight.members[0]
	var cid: int = club.members[0]
	var sid: int = spear.members[0]
	var hid: int = horse.members[0]
	_check(is_equal_approx(sim.attack[cid], 8.0), "clubman attack should be 8")
	_check(is_equal_approx(UnitSim.stats_for_type(UnitSim.UnitType.BOWMAN).attack, 6.0), "bowman attack should be 6")
	var foot := _hit_damage(sim, kid, cid)
	_check(is_equal_approx(foot, 12.0 - sim.defense[cid]), "knight vs clubman is +2 and no charge when standing")
	sim._travel_speed[kid] = sim.speed[kid]
	var flat := _hit_damage(sim, kid, cid)
	_check(is_equal_approx(flat, foot), "flat-ground speed is not fast enough to charge")
	sim._charge_cd[kid] = 0.0
	sim._travel_speed[kid] = sim.speed[kid] * 1.1
	var charged := _hit_damage(sim, kid, cid)
	_check(is_equal_approx(charged, 42.0 - sim.defense[cid]), "fast knight vs clubman is +2 and +30")
	var cooled := _hit_damage(sim, kid, cid)
	_check(is_equal_approx(cooled, foot), "charge does not repeat inside the cooldown")
	sim._charge_cd[kid] = 0.0
	var vs_spear := _hit_damage(sim, kid, sid)
	_check(is_equal_approx(vs_spear, 40.0 - sim.defense[sid]), "charge vs spearman has no +2")
	sim._charge_cd[kid] = 0.0
	var vs_horse := _hit_damage(sim, kid, hid)
	_check(is_equal_approx(vs_horse, 40.0 - sim.defense[hid]), "charge vs horse archer has no +2")
	print("TEST_UNIT_SIM_KNIGHT: foot=%.1f flat=%.1f charge=%.1f cooled=%.1f spear=%.1f horse=%.1f" % [
		foot, flat, charged, cooled, vs_spear, vs_horse
	])

func _test_height_rules() -> void:
	_check(is_equal_approx(UnitSim.speed_for_type(UnitSim.UnitType.SPEARMAN), 100.0 * 2.0 / 3.0 / 6.0), "foot speed drifted from units.json")
	_check(is_equal_approx(UnitSim.speed_for_type(UnitSim.UnitType.KNIGHT), 140.0 / 6.0), "horse speed drifted from units.json")
	_check(is_equal_approx(UnitSim.slope_speed_multiplier(0.0, 10.0), 1.0), "flat slope should be 1")
	_check(is_equal_approx(UnitSim.slope_speed_multiplier(1.0, 1.0), 0.75), "45° uphill should be 0.75")
	_check(is_equal_approx(UnitSim.slope_speed_multiplier(-1.0, 1.0), 1.25), "45° downhill should be 1.25")
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var step := 20.0
	var cols := 3
	var rows := 2
	var heights := PackedFloat32Array()
	heights.resize(cols * rows)
	# (0,0)=20, (20,0)=10, (40,0)=0, second row all 40.
	heights[0] = 20.0
	heights[1] = 10.0
	heights[2] = 0.0
	heights[3] = 40.0
	heights[4] = 40.0
	heights[5] = 40.0
	sim.set_height_grid(heights, cols, rows, step)
	var base := 120.0
	_check(is_equal_approx(sim.ranged_reach(0.0, 0.0, 0.0, 0.0, base), base), "flat bow range")
	_check(is_equal_approx(sim.ranged_reach(0.0, 0.0, 20.0, 0.0, base), base * 1.25), "half-gap downhill bow range")
	_check(is_equal_approx(sim.ranged_reach(0.0, 0.0, 40.0, 0.0, base), base * 1.5), "capped downhill bow range")
	_check(is_equal_approx(sim.ranged_reach(0.0, 0.0, 0.0, 20.0, base), base * 0.5), "capped uphill bow range")
	var high = _spawn_army(sim, "H1", 1, 0.0, 0.0, 1, UnitSim.UnitType.SPEARMAN, 0.0)
	var low_knight = _spawn_army(sim, "K1", 2, 40.0, 0.0, 1, UnitSim.UnitType.KNIGHT, PI)
	var low_club = _spawn_army(sim, "C1", 2, 40.0, 0.0, 1, UnitSim.UnitType.CLUBMAN, PI)
	var hid: int = high.members[0]
	var kid: int = low_knight.members[0]
	var cid: int = low_club.members[0]
	sim.pos_x[hid] = 0.0
	sim.pos_z[hid] = 0.0
	sim.pos_x[kid] = 40.0
	sim.pos_z[kid] = 0.0
	sim.pos_x[cid] = 40.0
	sim.pos_z[cid] = 0.0
	var spear_knight := _hit_damage(sim, hid, kid)
	var spear_club := _hit_damage(sim, hid, cid)
	_check(is_equal_approx(spear_knight, 15.0 - sim.defense[kid]), "spear on high ground vs knight is attack 15")
	_check(is_equal_approx(spear_club, 14.0 - sim.defense[cid]), "high ground vs clubman is +1 attack only")
	var uphill := _hit_damage(sim, cid, hid)
	_check(is_equal_approx(uphill, sim.attack[cid] - sim.defense[hid]), "attacking uphill has no height bonus")
	sim.pos_x[cid] = 0.0
	sim.pos_z[cid] = 0.0
	var flat := _hit_damage(sim, hid, cid)
	_check(is_equal_approx(flat, 13.0 - sim.defense[cid]), "equal height has no height bonus")
	print("TEST_UNIT_SIM_HEIGHT: spear_knight=%.1f spear_club=%.1f uphill=%.1f flat=%.1f" % [
		spear_knight, spear_club, uphill, flat
	])

func _hit_damage(sim, attacker: int, target: int) -> float:
	var before: float = sim.hp[target]
	sim._perform_attack(attacker, target)
	return before - sim.hp[target]

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
