extends SceneTree
## Two UnitSims fed the same scheduled orders must stay bitwise identical: 2000 soldiers in
## 40 armies on two sides, marched into each other with orders applied at fixed ticks, 600
## ticks, then pos_x / pos_z / flags / hp compared byte for byte. Any Time.*, randomness or
## dictionary-order dependence in the sim shows up here as a diff.
##
## Run: godot --headless --path . -s test_sim_determinism.gd

const UnitSim := preload("res://sim/UnitSim.gd")
const Formation := preload("res://sim/FormationController.gd")

const ARMIES_PER_SIDE := 20
const PER_ARMY := 50
const TICKS := 600
const MAP_W := 1280.0
const MAP_H := 720.0

func _init() -> void:
	call_deferred("_begin")

func _spawn(sim, aid: String, pid: int, x: float, z: float, n: int, t: int, dir: float):
	var fc = Formation.new()
	fc.army_id = aid
	fc.owner_pid = pid
	fc.owner_name = aid
	fc.initial_count = n
	fc.direction = dir
	fc.rows = fc.default_rows_for(n)
	fc.anchor = Vector2(x, z)
	fc.stance = Formation.Stance.AGGRESSIVE
	var idx = sim.add_army(fc)
	var offs: PackedVector2Array = fc.slot_offsets(n)
	for k in range(n):
		var o: Vector2 = offs[k].rotated(dir)
		sim.add_unit(sim.count, x + o.x, z + o.y, pid, idx, t)
	fc.packed_count = n
	fc.anchor_speed = sim.army_min_speed(fc) * Formation.ANCHOR_SPEED_SCALE
	sim._assign_slots(fc)
	return fc

func _build(sim) -> void:
	sim.setup(null, MAP_W, MAP_H, true)
	for k in range(ARMIES_PER_SIDE):
		var z := 60.0 + float(k) * 30.0
		var t := UnitSim.UnitType.SPEARMAN if (k % 3) != 0 else UnitSim.UnitType.BOWMAN
		_spawn(sim, "L%d" % k, 1, 500.0, z, PER_ARMY, t, 0.0)
		_spawn(sim, "R%d" % k, 2, 780.0, z, PER_ARMY, t, PI)

## The "scheduled orders": the same thing World._execute_order does, at fixed ticks.
func _orders_at(sim, tick: int) -> void:
	match tick:
		10:
			for a in sim.armies:
				sim.recentre_anchor(a)
				a.issue_move(Vector2(640.0, a.anchor.y))
		200:
			for k in range(sim.armies.size()):
				var a = sim.armies[k]
				if a.owner_pid == 1:
					sim.recentre_anchor(a)
					a.issue_attack_army(sim.armies[k + 1].index if k + 1 < sim.armies.size() else 0)
		350:
			for a in sim.armies:
				if a.owner_pid == 2 and not a.is_routed:
					sim.recentre_anchor(a)
					a.issue_move(Vector2(a.anchor.x + 40.0, a.anchor.y + 15.0))
		420:
			for ix in sim.repack_requests:
				sim.repack_army(sim.armies[ix])

func _run(sim) -> void:
	for t in range(TICKS):
		_orders_at(sim, sim.tick)
		sim.step(UnitSim.SIM_DT)

func _begin() -> void:
	print("TEST_SIM_DETERMINISM_BEGIN")
	var a = UnitSim.new()
	var b = UnitSim.new()
	_build(a)
	_build(b)
	var t0 := Time.get_ticks_usec()
	_run(a)
	_run(b)
	var ms := float(Time.get_ticks_usec() - t0) * 0.001
	var fails: Array[String] = []
	if a.count != 2 * ARMIES_PER_SIDE * PER_ARMY:
		fails.append("unit count %d" % a.count)
	if a.pos_x.to_byte_array() != b.pos_x.to_byte_array():
		fails.append("pos_x differs")
	if a.pos_z.to_byte_array() != b.pos_z.to_byte_array():
		fails.append("pos_z differs")
	if a.hp.to_byte_array() != b.hp.to_byte_array():
		fails.append("hp differs")
	if a.flags != b.flags:
		fails.append("flags differs")
	if a.target != b.target:
		fails.append("target differs")
	for k in range(a.armies.size()):
		if a.armies[k].anchor != b.armies[k].anchor or a.armies[k].moving != b.armies[k].moving \
				or a.armies[k].slot_index != b.armies[k].slot_index:
			fails.append("army %d state differs" % k)
			break
	# The scenario must actually exercise combat and deaths, or equality proves little.
	var dead := 0
	for i in range(a.count):
		if not a.is_alive(i):
			dead += 1
	if dead == 0 or a.combat_hits == 0 and dead == 0:
		fails.append("scenario produced no deaths (dead=%d)" % dead)
	print("TEST_SIM_DETERMINISM: units=%d ticks=%d dead=%d alive=%d two_runs_ms=%.0f" % [a.count, TICKS, dead, a.alive_count, ms])
	if fails.is_empty():
		print("TEST_SIM_DETERMINISM_OK")
		quit(0)
		return
	for f in fails:
		print("TEST_SIM_DETERMINISM_FAIL: %s" % f)
	quit(1)
