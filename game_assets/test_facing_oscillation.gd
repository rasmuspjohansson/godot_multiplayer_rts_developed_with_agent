extends SceneTree
## Move oscillation: a living unit must not reverse its step direction more than
## UnitSim.MOVE_OSC_MAX_REVERSALS times in MOVE_OSC_WINDOW_SEC.
##
## Two scenarios:
##   lockstep — same order, same ticks, periodic snapshots (healthy prediction).
##   mismatch — same order, but each snapshot is 10 units ahead on X. That is the
##              client/server position fight: local slots pull one way, reconcile
##              pulls the other, soldiers walk back and forth.
##
## Run: godot --headless --path . -s test_facing_oscillation.gd

const UnitSim := preload("res://sim/UnitSim.gd")
const Formation := preload("res://sim/FormationController.gd")
const NetSync := preload("res://sim/NetSync.gd")

func _init() -> void:
	call_deferred("_begin")

func _spawn(sim, aid: String, x: float, z: float, n: int):
	var fc = Formation.new()
	fc.army_id = aid
	fc.owner_pid = 1
	fc.owner_name = aid
	fc.initial_count = n
	fc.direction = 0.0
	fc.rows = fc.default_rows_for(n)
	fc.anchor = Vector2(x, z)
	var idx = sim.add_army(fc)
	var offs: PackedVector2Array = fc.slot_offsets(n)
	for k in range(n):
		var o: Vector2 = offs[k]
		sim.add_unit(sim.count, x + o.x, z + o.y, 1, idx, UnitSim.UnitType.SPEARMAN)
	fc.packed_count = n
	fc.anchor_speed = sim.army_min_speed(fc) * Formation.ANCHOR_SPEED_SCALE
	sim._assign_slots(fc)
	return fc

func _issue_east(sim, fc) -> void:
	sim.recentre_anchor(fc)
	fc.issue_move(Vector2(900.0, 360.0))

func _apply_snaps(net_s, net_c, server, client) -> void:
	var ids: PackedInt32Array = net_s.select_units(server, server.tick, 10000)
	if ids.is_empty():
		return
	for chunk in net_s.pack_chunks(server, ids, server.tick):
		net_c.apply_snapshot(client, net_c.unpack(chunk))

func _run_lockstep(ticks: int) -> Dictionary:
	var server = UnitSim.new()
	server.setup(null, 1280.0, 720.0, true)
	var client = UnitSim.new()
	client.setup(null, 1280.0, 720.0, false)
	var sfc = _spawn(server, "S1", 220.0, 360.0, 12)
	var cfc = _spawn(client, "S1", 220.0, 360.0, 12)
	_issue_east(server, sfc)
	_issue_east(client, cfc)
	var net_s = NetSync.new()
	net_s.setup(1280.0, 720.0)
	var net_c = NetSync.new()
	net_c.setup(1280.0, 720.0)
	for t in range(ticks):
		server.step(UnitSim.SIM_DT)
		client.step(UnitSim.SIM_DT)
		if t % NetSync.CHANGED_RESEND_TICKS == 0:
			_apply_snaps(net_s, net_c, server, client)
	return {
		"peak": client.move_oscillation_peak,
		"tripped": client.move_oscillation,
		"id": client.move_oscillation_id,
		"count": client.move_oscillation_count,
	}

## Same move, lockstep ticks, but every snapshot is 10 units ahead on X — enough
## to beat RECONCILE_IGNORE and pull each soldier through its slot.
func _run_mismatch(ticks: int) -> Dictionary:
	var server = UnitSim.new()
	server.setup(null, 1280.0, 720.0, true)
	var client = UnitSim.new()
	client.setup(null, 1280.0, 720.0, false)
	var sfc = _spawn(server, "S1", 220.0, 360.0, 12)
	var cfc = _spawn(client, "S1", 220.0, 360.0, 12)
	_issue_east(server, sfc)
	_issue_east(client, cfc)
	for t in range(ticks):
		server.step(UnitSim.SIM_DT)
		client.step(UnitSim.SIM_DT)
		if t % NetSync.CHANGED_RESEND_TICKS == 0:
			for i in range(client.count):
				if not client.is_alive(i):
					continue
				client.reconcile(
					i,
					server.pos_x[i] + 10.0,
					server.pos_z[i],
					client.hp[i] / maxf(client.max_hp[i], 1.0),
					server.flags[i]
				)
	return {
		"peak": client.move_oscillation_peak,
		"tripped": client.move_oscillation,
		"id": client.move_oscillation_id,
		"count": client.move_oscillation_count,
	}

func _begin() -> void:
	print("TEST_MOVE_OSCILLATION_BEGIN")
	var ticks := 400
	var lockstep: Dictionary = _run_lockstep(ticks)
	var mismatch: Dictionary = _run_mismatch(ticks)
	print("TEST_MOVE_OSCILLATION_LOCKSTEP: peak=%d tripped=%s" % [lockstep.peak, lockstep.tripped])
	print("TEST_MOVE_OSCILLATION_MISMATCH: peak=%d tripped=%s unit=%d reversals=%d" % [
		mismatch.peak, mismatch.tripped, mismatch.id, mismatch.count
	])
	if lockstep.tripped:
		print("TEST_MOVE_OSCILLATION_FAIL: lockstep reversed (unit=%d reversals=%d)" % [
			lockstep.id, lockstep.count
		])
		quit(1)
		return
	if mismatch.tripped:
		print("TEST_MOVE_OSCILLATION_FAIL: unit=%d reversals=%d window=2.0s" % [
			mismatch.id, mismatch.count
		])
		quit(1)
		return
	print("TEST_MOVE_OSCILLATION_OK: lockstep_peak=%d mismatch_peak=%d" % [lockstep.peak, mismatch.peak])
	quit(0)
