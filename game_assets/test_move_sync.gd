extends SceneTree
## Server/client move sync on two UnitSims driven by the same scheduled order.
##
## Mirrors the live pipeline (World.gd): both peers apply the MOVE at its exec tick, the
## server confirms the anchor (repath_from on mismatch), the server sends unit snapshots every
## NetSync.CHANGED_RESEND_TICKS and an army sync (anchor/dest/moving) every 10 ticks.
##
##   lockstep  — order applied on the same tick on both peers: positions stay equal to within
##               snapshot quantisation, nobody ever steps backwards, no reversals.
##   late      — the client applies the order 2 ticks late (as a live "late order" would);
##               anchor confirmation + snapshots must pull it back in line, forwards only.
##   offset    — the client's whole army (anchor + soldiers) is knocked 10 units off at tick 200
##               (formed up, mid-march); unit snapshots and army sync must reconverge it without a backward step.
##
## Run: godot --headless --path . -s test_move_sync.gd

const UnitSim := preload("res://sim/UnitSim.gd")
const Formation := preload("res://sim/FormationController.gd")
const NetSync := preload("res://sim/NetSync.gd")

const N := 12
const START := Vector2(220.0, 360.0)
const DEST := Vector2(400.0, 360.0)
const TICKS := 520
const EXEC_TICK := 20
## The offset scenarios knock the client army off once the block has formed up.
const PERTURB_TICK := 200
const ARMY_SYNC_PERIOD := 10
const ANCHOR_CONFIRM_TOLERANCE := 2.0
## Quantisation of a 16-bit snapshot coordinate on a 1280x720 map (~0.02) plus float slack.
const QUANT_EPS := 0.05
## A step counts as backwards when it travels against the soldier's own goal direction by more
## than this. Friendly separation nudges are <= FRIENDLY_PUSH (0.25) per neighbour and happen
## on every peer alike (e.g. while the block wheels onto a new heading); a blended correction
## that walked a soldier backwards would be >= 0.35 * RECONCILE_IGNORE = 0.7.
const BACKWARD_EPS := 0.5

func _init() -> void:
	call_deferred("_begin")

func _spawn(sim, x: float, z: float, n: int):
	var fc = Formation.new()
	fc.army_id = "S1"
	fc.owner_pid = 1
	fc.owner_name = "S1"
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

## World._apply_move_orders for a plain click: re-fit the anchor, keep the grid, issue.
func _apply_move(sim, fc) -> void:
	sim.recentre_anchor(fc)
	fc.issue_move(DEST)

func _apply_snaps(net_s, net_c, server, client) -> void:
	var ids: PackedInt32Array = net_s.select_units(server, server.tick, 10000)
	if ids.is_empty():
		return
	for chunk in net_s.pack_chunks(server, ids, server.tick):
		net_c.apply_snapshot(client, net_c.unpack(chunk))

func _max_slot_error(sim, fc) -> float:
	var m := 0.0
	for id in fc.members:
		if sim.is_alive(id):
			m = maxf(m, Vector2(sim.goal_x[id] - sim.pos_x[id], sim.goal_z[id] - sim.pos_z[id]).length())
	return m

## Positions of every alive soldier: max |server - client|.
func _max_pos_error(server, client) -> float:
	var m := 0.0
	for i in range(server.count):
		if not server.is_alive(i) or not client.is_alive(i):
			continue
		m = maxf(m, Vector2(server.pos_x[i] - client.pos_x[i], server.pos_z[i] - client.pos_z[i]).length())
	return m

## Count client steps that oppose the march: against the block's heading while it moves, and
## against the soldier's own goal direction.
func _backward_steps(client) -> int:
	var n := 0
	for i in range(client.count):
		if not client.is_alive(i):
			continue
		var step := Vector2(client.pos_x[i] - client.prev_x[i], client.pos_z[i] - client.prev_z[i])
		if step.length() < 1e-4:
			continue
		var ai: int = client.army[i]
		var heading := Vector2(client._army_dir_x[ai], client._army_dir_z[ai])
		var to_goal := Vector2(client.goal_x[i] - client.prev_x[i], client.goal_z[i] - client.prev_z[i])
		# Slot ahead of the soldier (the block is formed and marching) but the step went the
		# other way: only a correction can do that. Wheeling onto a new heading legitimately
		# sends soldiers to slots behind them, so a slot behind is judged by the goal check.
		if heading != Vector2.ZERO and to_goal.dot(heading) >= 0.0 and step.dot(heading) < -BACKWARD_EPS:
			n += 1
			continue
		if to_goal.length() <= UnitSim.STEER_DEADZONE:
			continue
		if step.dot(to_goal.normalized()) < -BACKWARD_EPS:
			n += 1
	return n

## Run one scenario. `late_ticks` delays the client's order; `offset` is applied to the client
## army (anchor + soldiers) at PERTURB_TICK.
func _run(late_ticks: int, offset: Vector2) -> Dictionary:
	var server = UnitSim.new()
	server.setup(null, 1280.0, 720.0, true)
	var client = UnitSim.new()
	client.setup(null, 1280.0, 720.0, false)
	var sfc = _spawn(server, START.x, START.y, N)
	var cfc = _spawn(client, START.x, START.y, N)
	var net_s = NetSync.new()
	net_s.setup(1280.0, 720.0)
	var net_c = NetSync.new()
	net_c.setup(1280.0, 720.0)
	var srv_anchor_at_exec := Vector2(INF, INF)
	var my_anchor_at_exec := Vector2(INF, INF)
	var repaths := 0
	var backward := 0
	var formed := false
	var formed_tick := -1
	var peak_err := 0.0
	var err_after_settle := 0.0
	for t in range(TICKS):
		# Scheduled order: both peers apply at EXEC_TICK (client possibly late).
		if server.tick == EXEC_TICK:
			_apply_move(server, sfc)
			srv_anchor_at_exec = sfc.anchor
		if client.tick == EXEC_TICK + late_ticks:
			_apply_move(client, cfc)
			my_anchor_at_exec = cfc.anchor
			# Anchor confirmation (World._check_anchor_confirm): adopt + replay if off.
			if srv_anchor_at_exec.distance_to(my_anchor_at_exec) > ANCHOR_CONFIRM_TOLERANCE:
				cfc.repath_from(srv_anchor_at_exec, float(late_ticks) * UnitSim.SIM_DT)
				repaths += 1
		if t == PERTURB_TICK and offset != Vector2.ZERO:
			cfc.anchor += offset
			for i in range(client.count):
				client.pos_x[i] += offset.x
				client.pos_z[i] += offset.y
				client.prev_x[i] = client.pos_x[i]
				client.prev_z[i] = client.pos_z[i]
		server.step(UnitSim.SIM_DT)
		client.step(UnitSim.SIM_DT)
		if server.tick % NetSync.CHANGED_RESEND_TICKS == 0:
			_apply_snaps(net_s, net_c, server, client)
		if server.tick % ARMY_SYNC_PERIOD == 0:
			cfc.sync_from_server(sfc.anchor, sfc.dest, sfc.moving, sfc.paused_for_contact, 1.0)
		# Backward steps are judged once the block has wheeled onto its heading and formed up
		# (the wheel itself shoves soldiers around, identically on every peer).
		if not formed and cfc.moving and _max_slot_error(client, cfc) <= 1.0:
			formed = true
			formed_tick = client.tick
		if formed:
			backward += _backward_steps(client)
		var e := _max_pos_error(server, client)
		peak_err = maxf(peak_err, e)
		if t == TICKS - 1:
			err_after_settle = e
	return {
		"peak_err": peak_err,
		"final_err": err_after_settle,
		"formed_tick": formed_tick,
		"backward": backward,
		"reversals": client.move_oscillation_peak,
		"tripped": client.move_oscillation,
		"repaths": repaths,
		"snaps": client.snap_count,
		"server_arrived": not sfc.moving,
		"client_arrived": not cfc.moving,
	}

func _report(name: String, r: Dictionary) -> void:
	print("TEST_MOVE_SYNC_%s: peak_err=%.3f final_err=%.3f formed_tick=%d backward=%d reversals=%d repaths=%d snaps=%d arrived=%s/%s" % [
		name, r.peak_err, r.final_err, r.formed_tick, r.backward, r.reversals, r.repaths, r.snaps, r.server_arrived, r.client_arrived
	])

func _begin() -> void:
	print("TEST_MOVE_SYNC_BEGIN")
	var fails: Array[String] = []
	var lockstep := _run(0, Vector2.ZERO)
	var late := _run(2, Vector2.ZERO)
	var behind := _run(0, Vector2(-10.0, 4.0))
	# Client ahead of the server: the correction points against the march, so it may only be
	# applied as a slow-down / slide, never as a backward walk; the rest waits for arrival.
	var ahead := _run(0, Vector2(10.0, -4.0))
	_report("LOCKSTEP", lockstep)
	_report("LATE", late)
	_report("OFFSET_BEHIND", behind)
	_report("OFFSET_AHEAD", ahead)
	if lockstep.peak_err > QUANT_EPS:
		fails.append("lockstep diverged: peak_err=%.3f" % lockstep.peak_err)
	for pair in [["lockstep", lockstep], ["late", late], ["offset_behind", behind], ["offset_ahead", ahead]]:
		var r: Dictionary = pair[1]
		if r.formed_tick < 0 or r.formed_tick > PERTURB_TICK:
			fails.append("%s: block did not form up before the perturbation (formed_tick=%d)" % [pair[0], r.formed_tick])
		if r.backward > 0:
			fails.append("%s: %d backward steps" % [pair[0], r.backward])
		if r.tripped or r.reversals > 0:
			fails.append("%s: %d step reversals" % [pair[0], r.reversals])
		if r.snaps > 0:
			fails.append("%s: %d hard snaps" % [pair[0], r.snaps])
		if not r.server_arrived or not r.client_arrived:
			fails.append("%s: did not arrive (server=%s client=%s)" % [pair[0], r.server_arrived, r.client_arrived])
		# Errors below RECONCILE_IGNORE are by design left alone once the block is parked.
		if r.final_err > UnitSim.RECONCILE_IGNORE:
			fails.append("%s: did not reconverge, final_err=%.3f" % [pair[0], r.final_err])
	if fails.is_empty():
		print("TEST_MOVE_SYNC_OK")
		quit(0)
		return
	for f in fails:
		print("TEST_MOVE_SYNC_FAIL: %s" % f)
	quit(1)
