extends SceneTree
## Order-first separation: units slide past each other and never jump.
## - crossing: two friendly armies march through each other; no soldier moves farther in one
##   tick than a catch-up step plus a capped push, and both armies finish in their slots.
## - stacked: two friendly armies parked on the same spot settle without jostling.
## - head_on: two lone soldiers swap places along the same line and both arrive.
##
## Run: godot --headless --path . -s test_separation_smooth.gd

const UnitSim := preload("res://sim/UnitSim.gd")
const Formation := preload("res://sim/FormationController.gd")

const TICK_CAP := 3000
const ARRIVE_TOL := 3.0
const EPS := 0.05

var _next_army := 0

func _init() -> void:
	call_deferred("_begin")

func _spawn(sim, x: float, z: float, n: int, pid: int = 1):
	var fc = Formation.new()
	_next_army += 1
	fc.army_id = "A%d" % _next_army
	fc.owner_pid = pid
	fc.owner_name = fc.army_id
	fc.initial_count = n
	fc.direction = 0.0
	fc.rows = fc.default_rows_for(n)
	fc.anchor = Vector2(x, z)
	var idx = sim.add_army(fc)
	var offs: PackedVector2Array = fc.slot_offsets(n)
	for k in range(n):
		var o: Vector2 = offs[k]
		sim.add_unit(sim.count, x + o.x, z + o.y, pid, idx, UnitSim.UnitType.SPEARMAN)
	fc.packed_count = n
	fc.anchor_speed = sim.army_min_speed(fc) * Formation.ANCHOR_SPEED_SCALE
	sim._assign_slots(fc)
	return fc

func _max_step_ratio(sim) -> float:
	var m := 0.0
	for i in range(sim.count):
		if not sim.is_alive(i):
			continue
		var d := Vector2(sim.pos_x[i] - sim.prev_x[i], sim.pos_z[i] - sim.prev_z[i]).length()
		m = maxf(m, d / (sim.speed[i] * UnitSim.SIM_DT))
	return m

func _slot_error(sim, fc) -> float:
	var m := 0.0
	for id in fc.members:
		if sim.is_alive(id):
			m = maxf(m, Vector2(sim.goal_x[id] - sim.pos_x[id], sim.goal_z[id] - sim.pos_z[id]).length())
	return m

func _begin() -> void:
	var fails: Array[String] = []
	_run_crossing(fails)
	_run_stacked(fails)
	_run_head_on(fails)
	if fails.is_empty():
		print("TEST_SEPARATION_SMOOTH_OK")
		quit(0)
		return
	for f in fails:
		print("TEST_SEPARATION_SMOOTH_FAIL: %s" % f)
	quit(1)

func _run_crossing(fails: Array[String]) -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var a = _spawn(sim, 200.0, 360.0, 40)
	var b = _spawn(sim, 450.0, 120.0, 40)
	sim.recentre_anchor(a)
	a.issue_move(Vector2(700.0, 360.0))
	sim.recentre_anchor(b)
	b.issue_move(Vector2(450.0, 600.0))
	var limit := Formation.CATCH_UP_SPEED + UnitSim.PUSH_STEP_FRAC + UnitSim.SIDESTEP_FRAC + EPS
	var worst := 0.0
	var done_tick := -1
	for t in range(TICK_CAP):
		sim.step(UnitSim.SIM_DT)
		worst = maxf(worst, _max_step_ratio(sim))
		if not a.moving and not b.moving and _slot_error(sim, a) <= ARRIVE_TOL and _slot_error(sim, b) <= ARRIVE_TOL:
			done_tick = sim.tick
			break
	print("TEST_SEPARATION_SMOOTH: crossing worst_step=%.2fx done_tick=%d" % [worst, done_tick])
	if worst > limit:
		fails.append("crossing: a soldier moved %.2fx its walk step in one tick (limit %.2fx)" % [worst, limit])
	if done_tick < 0:
		fails.append("crossing: armies did not finish in their slots within %d ticks" % TICK_CAP)

func _run_stacked(fails: Array[String]) -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	_spawn(sim, 400.0, 360.0, 30)
	_spawn(sim, 404.0, 362.0, 30)
	var worst := 0.0
	var settled_path := 0.0
	var settle_from := 200
	var ticks := 600
	for t in range(ticks):
		sim.step(UnitSim.SIM_DT)
		worst = maxf(worst, _max_step_ratio(sim))
		if t >= settle_from:
			for i in range(sim.count):
				settled_path += Vector2(sim.pos_x[i] - sim.prev_x[i], sim.pos_z[i] - sim.prev_z[i]).length()
	var walk: float = sim.speed[0] * UnitSim.SIM_DT
	# Average speed per soldier once settled, as a fraction of walking speed.
	var jostle: float = settled_path / float(sim.count * (ticks - settle_from)) / walk
	print("TEST_SEPARATION_SMOOTH: stacked worst_step=%.2fx settled_jostle=%.3f" % [worst, jostle])
	if worst > 1.0 + UnitSim.PUSH_STEP_FRAC + UnitSim.SIDESTEP_FRAC + EPS:
		fails.append("stacked: a soldier moved %.2fx its walk step in one tick" % worst)
	if jostle > 0.05:
		fails.append("stacked: parked soldiers keep jostling (%.3f of walk speed)" % jostle)

func _run_head_on(fails: Array[String]) -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var a = _spawn(sim, 300.0, 360.0, 1)
	var b = _spawn(sim, 340.0, 360.0, 1)
	sim.recentre_anchor(a)
	a.issue_move(Vector2(340.0, 360.0))
	sim.recentre_anchor(b)
	b.issue_move(Vector2(300.0, 360.0))
	var done_tick := -1
	for t in range(TICK_CAP):
		sim.step(UnitSim.SIM_DT)
		if not a.moving and not b.moving and _slot_error(sim, a) <= ARRIVE_TOL and _slot_error(sim, b) <= ARRIVE_TOL:
			done_tick = sim.tick
			break
	print("TEST_SEPARATION_SMOOTH: head_on done_tick=%d" % done_tick)
	if done_tick < 0:
		fails.append("head_on: soldiers did not swap places within %d ticks" % TICK_CAP)
