extends SceneTree
## Headless: client spawn applies mounted speed for horse armies (sim speed table).

const UnitSim := preload("res://sim/UnitSim.gd")
const EXPECTED_HORSE_SPEED := 140.0 / 6.0

func _init():
	call_deferred("_begin")

func _begin():
	var w = load("res://World.tscn").instantiate()
	root.add_child(w)
	await process_frame
	var data: Array = [{
		"army_id": "T_horse_speed",
		"pid": 1,
		"name": "Test",
		"x": 400.0,
		"y": 300.0,
		"dir": 0.0,
		"count": 1,
		"first_id": 0,
		"horse": true,
		"spear": false,
	}]
	w._client_spawn_armies_impl(data)
	var sim = w._sim
	if sim.count == 0 or not sim.is_alive(0):
		print("TEST_WORLD3D_HORSE_SPEED_FAIL: no units spawned")
		quit(1)
		return
	if (sim.flags[0] & UnitSim.F_HORSE) == 0 or sim.utype[0] != UnitSim.UnitType.KNIGHT:
		print("TEST_WORLD3D_HORSE_SPEED_FAIL: unit not mounted (type=%d)" % sim.utype[0])
		quit(1)
		return
	if absf(float(sim.speed[0]) - EXPECTED_HORSE_SPEED) > 0.001:
		print("TEST_WORLD3D_HORSE_SPEED_FAIL: speed=%.4f expected=%.4f" % [sim.speed[0], EXPECTED_HORSE_SPEED])
		quit(1)
		return
	if not w.armies[0].has_horse:
		print("TEST_WORLD3D_HORSE_SPEED_FAIL: army handle has_horse false")
		quit(1)
		return
	print("TEST_WORLD3D_HORSE_SPEED_OK")
	quit(0)
