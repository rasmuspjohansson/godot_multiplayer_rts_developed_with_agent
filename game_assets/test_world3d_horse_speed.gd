extends SceneTree
## Headless: client spawn applies mounted speed for horse armies.

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
		"initial_count": 1,
		"horse": true,
		"spear": false,
		"speed": EXPECTED_HORSE_SPEED,
		"attack": 10.0,
		"soldiers": [
			{"name": "Soldier_T_horse_speed_0", "x": 400.0, "y": 300.0},
		]
	}]
	w._client_spawn_armies_impl(data)
	if w.all_units.is_empty():
		print("TEST_WORLD3D_HORSE_SPEED_FAIL: no units spawned")
		quit(1)
		return
	var unit = w.all_units[0]
	if not unit.get("has_horse"):
		print("TEST_WORLD3D_HORSE_SPEED_FAIL: has_horse false")
		quit(1)
		return
	if absf(float(unit.speed) - EXPECTED_HORSE_SPEED) > 0.001:
		print("TEST_WORLD3D_HORSE_SPEED_FAIL: speed=%.4f expected=%.4f" % [unit.speed, EXPECTED_HORSE_SPEED])
		quit(1)
		return
	print("TEST_WORLD3D_HORSE_SPEED_OK")
	quit(0)
