extends SceneTree
## Headless: every shipped map has eight chests far from starts, capture points, and lakes.

const MapConfig := preload("res://MapConfig.gd")

func _init() -> void:
	var names: Array[String] = ["S", "L", "XL", "Valleys", "New", "New2", "demo"]
	var fail := 0
	for map_name in names:
		var cfg = MapConfig.new()
		if not cfg.reload(map_name):
			print("TEST_CHESTS_FAIL: %s did not load" % map_name)
			fail += 1
			continue
		if cfg.chests.size() != 8:
			print("TEST_CHESTS_FAIL: %s has %d chests" % [map_name, cfg.chests.size()])
			fail += 1
			continue
		var points: Array = []
		for cp in cfg.capture_points:
			points.append(Vector2(float(cp["x"]), float(cp["y"])))
		for sp in cfg.start_positions:
			points.append(Vector2(float(sp["x"]), float(sp["y"])))
		var chests: Array = []
		for chest in cfg.chests:
			chests.append(Vector2(float(chest["x"]), float(chest["y"])))
		for i in range(chests.size()):
			var p: Vector2 = chests[i]
			for q in points:
				if p.distance_to(q) < 150.0:
					print("TEST_CHESTS_FAIL: %s chest too close to a start or capture point" % map_name)
					fail += 1
			for j in range(i + 1, chests.size()):
				if p.distance_to(chests[j]) < 150.0:
					print("TEST_CHESTS_FAIL: %s chests closer than 150" % map_name)
					fail += 1
			for lake in cfg.lakes:
				if typeof(lake) == TYPE_DICTIONARY and p.distance_to(Vector2(float(lake.get("x", 0.0)), float(lake.get("y", 0.0)))) < 80.0:
					print("TEST_CHESTS_FAIL: %s chest inside a lake" % map_name)
					fail += 1
		var saved: Dictionary = cfg.to_dict()
		if typeof(saved.get("chests", null)) != TYPE_ARRAY or saved["chests"].size() != 8:
			print("TEST_CHESTS_FAIL: %s to_dict dropped chests" % map_name)
			fail += 1
	if fail == 0:
		print("TEST_CHESTS_OK")
		quit(0)
		return
	print("TEST_CHESTS_FAILED: %d" % fail)
	quit(1)
