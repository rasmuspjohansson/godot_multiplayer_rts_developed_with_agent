extends SceneTree
## Rigid march: a 50-man army ordered 400 units away wheels onto the new heading, forms up,
## and from then on marches as one block — every rank neighbour stays within 15% of the
## formation pitch, nobody straggles, slot indices never change and the anchor covers the
## ground at the soldiers' speed (no stretching / bunching).
##
## Run: godot --headless --path . -s test_formation_rigidity.gd

const UnitSim := preload("res://sim/UnitSim.gd")
const Formation := preload("res://sim/FormationController.gd")

const N := 50
const START := Vector2(200.0, 360.0)
const DEST := Vector2(600.0, 360.0)
const FORM_UP_MAX_TICKS := 200
const SLOT_TOL := 1.0
const PITCH_TOL := 0.15

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

## Pairs of members that sit next to each other in the same rank (slot k, k+1 on one row).
func _rank_neighbours(fc) -> Array:
	var cols: int = maxi(1, ceili(float(fc.packed_count) / float(maxi(fc.rows, 1))))
	var by_slot := {}
	for m in range(fc.members.size()):
		by_slot[fc.slot_index[m]] = fc.members[m]
	var pairs: Array = []
	for s in by_slot.keys():
		if (int(s) % cols) == cols - 1 or not by_slot.has(int(s) + 1):
			continue
		pairs.append([by_slot[s], by_slot[int(s) + 1]])
	return pairs

func _max_slot_error(sim, fc) -> float:
	var m := 0.0
	for id in fc.members:
		m = maxf(m, Vector2(sim.goal_x[id] - sim.pos_x[id], sim.goal_z[id] - sim.pos_z[id]).length())
	return m

func _begin() -> void:
	print("TEST_FORMATION_RIGIDITY_BEGIN")
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var fc = _spawn(sim, START.x, START.y, N)
	var slots0: PackedInt32Array = fc.slot_index.duplicate()
	var rows0: int = fc.rows
	var pitch: float = fc.spacing
	sim.recentre_anchor(fc)
	fc.issue_move(DEST)
	var pairs := _rank_neighbours(fc)
	var fails: Array[String] = []
	var formed_tick := -1
	var worst_pitch := 0.0
	var worst_slot := 0.0
	var straggle_ticks := 0
	var anchor_at_form := Vector2.ZERO
	var arrived_tick := -1
	for t in range(1200):
		sim.step(UnitSim.SIM_DT)
		if fc.slot_index != slots0:
			fails.append("slot indices changed at tick %d" % sim.tick)
			break
		if fc.rows != rows0 or not is_equal_approx(fc.spacing, pitch):
			fails.append("grid changed at tick %d (rows %d->%d)" % [sim.tick, rows0, fc.rows])
			break
		var slot_err := _max_slot_error(sim, fc)
		if formed_tick < 0:
			if slot_err <= SLOT_TOL:
				formed_tick = sim.tick
				anchor_at_form = fc.anchor
			elif sim.tick > FORM_UP_MAX_TICKS:
				fails.append("block never formed up (slot_err=%.2f after %d ticks)" % [slot_err, sim.tick])
				break
			continue
		# Formed: from here on the block must stay rigid until it arrives.
		worst_slot = maxf(worst_slot, slot_err)
		if sim._army_straggling[fc.index] > 0:
			straggle_ticks += 1
		for p in pairs:
			var d := Vector2(sim.pos_x[p[0]] - sim.pos_x[p[1]], sim.pos_z[p[0]] - sim.pos_z[p[1]]).length()
			worst_pitch = maxf(worst_pitch, absf(d - pitch) / pitch)
		if not fc.moving:
			arrived_tick = sim.tick
			break
	var marched := 0.0
	if formed_tick >= 0 and arrived_tick >= 0:
		marched = fc.anchor.distance_to(anchor_at_form)
		var expected: float = fc.anchor_speed * UnitSim.SIM_DT * float(arrived_tick - formed_tick)
		# The anchor must not have slowed down (cohesion crawl) once the block was formed.
		if marched < expected * 0.98:
			fails.append("anchor crawled: marched %.1f in %d ticks, expected %.1f" % [marched, arrived_tick - formed_tick, expected])
	if arrived_tick < 0 and fails.is_empty():
		fails.append("did not arrive within 1200 ticks")
	if worst_pitch > PITCH_TOL:
		fails.append("rank neighbours drifted %.0f%% off pitch (limit %.0f%%)" % [worst_pitch * 100.0, PITCH_TOL * 100.0])
	if straggle_ticks > 0:
		fails.append("%d ticks with stragglers after forming up" % straggle_ticks)
	if fc.anchor.distance_to(DEST) > 1.0:
		fails.append("anchor ended %.1f from dest" % fc.anchor.distance_to(DEST))
	print("TEST_FORMATION_RIGIDITY: formed_tick=%d arrived_tick=%d marched=%.1f worst_pitch=%.1f%% worst_slot=%.2f straggle_ticks=%d" % [
		formed_tick, arrived_tick, marched, worst_pitch * 100.0, worst_slot, straggle_ticks
	])
	if fails.is_empty():
		print("TEST_FORMATION_RIGIDITY_OK")
		quit(0)
		return
	for f in fails:
		print("TEST_FORMATION_RIGIDITY_FAIL: %s" % f)
	quit(1)
