extends SceneTree
## Responsive march: a 50-man army ordered 400 units away keeps its slot indices, aims along
## the shared path from the first tick (no local wheel), and finishes in the destination
## slots. A second order overwrites the path with a detour and checks that march goals stay
## on that polyline instead of cutting across it.
##
## Run: godot --headless --path . -s test_formation_rigidity.gd

const UnitSim := preload("res://sim/UnitSim.gd")
const Formation := preload("res://sim/FormationController.gd")

const N := 50
const START := Vector2(200.0, 360.0)
const DEST := Vector2(600.0, 360.0)
const ARRIVE_TOL := 2.5
const PATH_TOL_SCALE := 1.5
const TICK_CAP := 2000

func _init() -> void:
	call_deferred("_begin")

func _spawn(sim, x: float, z: float, n: int):
	var fc = Formation.new()
	fc.army_id = "A"
	fc.owner_pid = 1
	fc.owner_name = "A"
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

func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _dist_to_path(p: Vector2, path: PackedVector2Array) -> float:
	if path.is_empty():
		return INF
	if path.size() == 1:
		return p.distance_to(path[0])
	var best := INF
	for i in range(path.size() - 1):
		best = minf(best, _dist_to_segment(p, path[i], path[i + 1]))
	return best

func _slot_world(fc, o: Vector2) -> Vector2:
	var cs := cos(fc.dest_direction)
	var sn := sin(fc.dest_direction)
	return Vector2(
		fc.dest.x + o.x * cs - o.y * sn,
		fc.dest.y + o.x * sn + o.y * cs
	)

func _begin() -> void:
	print("TEST_FORMATION_RIGIDITY_BEGIN")
	var fails: Array[String] = []
	_run_straight(fails)
	_run_detour(fails)
	if fails.is_empty():
		print("TEST_FORMATION_RIGIDITY_OK")
		quit(0)
		return
	for f in fails:
		print("TEST_FORMATION_RIGIDITY_FAIL: %s" % f)
	quit(1)

func _run_straight(fails: Array[String]) -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var fc = _spawn(sim, START.x, START.y, N)
	var slots0: PackedInt32Array = fc.slot_index.duplicate()
	var spawn_x: PackedFloat32Array = sim.pos_x.duplicate()
	var spawn_z: PackedFloat32Array = sim.pos_z.duplicate()
	sim.recentre_anchor(fc)
	fc.issue_move(DEST)
	var min_goal := INF
	var moved_ok := true
	var arrived := false
	for t in range(TICK_CAP):
		sim.step(UnitSim.SIM_DT)
		if fc.slot_index != slots0:
			fails.append("straight: slot indices changed at tick %d" % sim.tick)
			return
		if t == 0:
			for id in fc.members:
				var g := Vector2(sim.goal_x[id], sim.goal_z[id])
				min_goal = minf(min_goal, g.distance_to(START))
		if t == 2:
			for id in fc.members:
				var step := Vector2(sim.pos_x[id] - spawn_x[id], sim.pos_z[id] - spawn_z[id])
				var to_goal := Vector2(sim.goal_x[id] - spawn_x[id], sim.goal_z[id] - spawn_z[id])
				if step.length() < 0.4 or to_goal.length() < 1.0 or step.dot(to_goal) <= 0.0:
					moved_ok = false
		if not fc.moving and _arrived(sim, fc):
			arrived = true
			break
	if min_goal < 100.0:
		fails.append("straight: goals stayed near the start (min goal distance %.1f)" % min_goal)
	if not moved_ok:
		fails.append("straight: soldiers did not move toward their goals on the first ticks")
	if not arrived:
		fails.append("straight: did not finish in the destination slots within %d ticks" % TICK_CAP)
	else:
		var err := _arrival_error(sim, fc)
		print("TEST_FORMATION_RIGIDITY: straight arrived_tick=%d slot_err=%.2f min_goal=%.1f" % [sim.tick, err, min_goal])
		if err > ARRIVE_TOL:
			fails.append("straight: arrival error %.2f" % err)

func _run_detour(fails: Array[String]) -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var fc = _spawn(sim, START.x, START.y, N)
	var slots0: PackedInt32Array = fc.slot_index.duplicate()
	sim.recentre_anchor(fc)
	fc.issue_move(DEST)
	var detour := PackedVector2Array([
		Vector2(START.x, 200.0),
		Vector2(DEST.x, 200.0),
		DEST,
	])
	fc.path = detour
	fc.path_i = 0
	fc.slots_dirty = true
	var worst := 0.0
	var shortcut := false
	var arrived := false
	var band: float = fc.spacing * PATH_TOL_SCALE
	for t in range(TICK_CAP):
		sim.step(UnitSim.SIM_DT)
		if fc.slot_index != slots0:
			fails.append("detour: slot indices changed at tick %d" % sim.tick)
			return
		for id in fc.members:
			if not sim.is_alive(id):
				continue
			var goal := Vector2(sim.goal_x[id], sim.goal_z[id])
			var remain: float = sim._march_remaining(fc.path, sim._march_i[id], sim.pos_x[id], sim.pos_z[id])
			if fc.moving and remain > Formation.DEPLOY_DIST and sim._march_deploy[id] == 0:
				worst = maxf(worst, _dist_to_path(goal, detour))
			# Still beside the start: the cursor has to be on the first bend, not a later one.
			if Vector2(sim.pos_x[id], sim.pos_z[id]).distance_to(START) < 80.0 and sim._march_i[id] > 0:
				shortcut = true
		if not fc.moving and _arrived(sim, fc):
			arrived = true
			break
	print("TEST_FORMATION_RIGIDITY: detour arrived_tick=%d worst_goal_off_path=%.2f" % [sim.tick if arrived else -1, worst])
	if worst > band:
		fails.append("detour: march goal %.2f off the shared path (limit %.2f)" % [worst, band])
	if shortcut:
		fails.append("detour: a soldier's path cursor jumped ahead of the first bend")
	if not arrived:
		fails.append("detour: did not finish in the destination slots within %d ticks" % TICK_CAP)

func _arrived(sim, fc) -> bool:
	return _arrival_error(sim, fc) <= ARRIVE_TOL

func _arrival_error(sim, fc) -> float:
	var offs: PackedVector2Array = fc.slot_offsets(N)
	var last: int = offs.size() - 1
	var m := 0.0
	for k in range(fc.members.size()):
		var id: int = fc.members[k]
		if not sim.is_alive(id):
			continue
		var slot := _slot_world(fc, offs[mini(fc.slot_index[k], last)])
		m = maxf(m, Vector2(sim.pos_x[id] - slot.x, sim.pos_z[id] - slot.y).length())
	return m
