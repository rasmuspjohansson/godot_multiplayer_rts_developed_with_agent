extends SceneTree
## Sprite facing: a unit walking right must set F_FACING_RIGHT, walking left must clear it, and
## the facing must persist while idle. The renderer mirrors the (right-facing) sheet only when
## that flag is clear, so this is the sim half of the billboard flip.
##
## Run: godot --headless --path . -s test_facing_flip.gd

const UnitSim := preload("res://sim/UnitSim.gd")
const Formation := preload("res://sim/FormationController.gd")

func _init() -> void:
	call_deferred("_begin")

func _spawn(sim, x: float) -> RefCounted:
	var fc = Formation.new()
	fc.army_id = "F1"
	fc.owner_pid = 1
	fc.initial_count = 1
	fc.rows = 1
	fc.anchor = Vector2(x, 360.0)
	sim.add_army(fc)
	sim.spawn_army_units(fc, 0, 1, UnitSim.UnitType.SPEARMAN)
	return fc

func _run_until_settled(sim, fc, max_ticks: int) -> void:
	for _i in range(max_ticks):
		sim.step(UnitSim.SIM_DT)
		if not fc.moving and (sim.flags[0] & UnitSim.F_MOVING) == 0:
			return

func _begin() -> void:
	var sim = UnitSim.new()
	sim.setup(null, 1280.0, 720.0, true)
	var fc = _spawn(sim, 500.0)
	print("TEST_FACING_FLIP_BEGIN")

	sim.recentre_anchor(fc)
	fc.issue_move(Vector2(700.0, 360.0))
	for _i in range(5):
		sim.step(UnitSim.SIM_DT)
	var right_ok: bool = (sim.flags[0] & UnitSim.F_FACING_RIGHT) != 0 and (sim.flags[0] & UnitSim.F_MOVING) != 0
	print("TEST_FACING_FLIP_STEP: after_move_right facing_right=%s pass=%s" % [(sim.flags[0] & UnitSim.F_FACING_RIGHT) != 0, right_ok])
	_run_until_settled(sim, fc, 20 * 30)

	sim.recentre_anchor(fc)
	fc.issue_move(Vector2(300.0, 360.0))
	for _i in range(5):
		sim.step(UnitSim.SIM_DT)
	var left_ok: bool = (sim.flags[0] & UnitSim.F_FACING_RIGHT) == 0 and (sim.flags[0] & UnitSim.F_MOVING) != 0
	print("TEST_FACING_FLIP_STEP: after_move_left facing_right=%s pass=%s" % [(sim.flags[0] & UnitSim.F_FACING_RIGHT) != 0, left_ok])
	_run_until_settled(sim, fc, 20 * 40)

	var prev: bool = (sim.flags[0] & UnitSim.F_FACING_RIGHT) != 0
	for _i in range(20):
		sim.step(UnitSim.SIM_DT)
	var idle_ok: bool = ((sim.flags[0] & UnitSim.F_FACING_RIGHT) != 0) == prev and (sim.flags[0] & UnitSim.F_MOVING) == 0
	print("TEST_FACING_FLIP_STEP: after_idle facing_right=%s pass=%s" % [(sim.flags[0] & UnitSim.F_FACING_RIGHT) != 0, idle_ok])

	sim.recentre_anchor(fc)
	fc.issue_move(Vector2(700.0, 360.0))
	for _i in range(5):
		sim.step(UnitSim.SIM_DT)
	var right_again_ok: bool = (sim.flags[0] & UnitSim.F_FACING_RIGHT) != 0
	print("TEST_FACING_FLIP_STEP: after_move_right_again facing_right=%s pass=%s" % [(sim.flags[0] & UnitSim.F_FACING_RIGHT) != 0, right_again_ok])

	if right_ok and left_ok and idle_ok and right_again_ok:
		print("TEST_FACING_FLIP_OK")
		quit(0)
	else:
		print("TEST_FACING_FLIP_FAIL right=%s left=%s idle=%s right_again=%s" % [right_ok, left_ok, idle_ok, right_again_ok])
		quit(1)
