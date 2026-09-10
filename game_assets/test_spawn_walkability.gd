extends SceneTree
## Headless: every map start rally point must be on walkable terrain.
## Match-start spawn is off-map (not walkable); armies march onto these markers.

const _MapConfigScript = preload("res://MapConfig.gd")

func _init():
	call_deferred("_begin")

func _begin():
	var map_cfg: Node = _MapConfigScript.new()
	root.add_child(map_cfg)
	var w = load("res://World.tscn").instantiate()
	root.add_child(w)
	for _i in range(12):
		await physics_frame

	var bad: Array = []
	var n := 0
	if map_cfg.start_positions.is_empty():
		for slot in map_cfg.player_starts:
			var sid: int = int(slot.get("slot", -1))
			var armies: Array = slot.get("armies", [])
			if armies.is_empty():
				continue
			var ac: Dictionary = armies[0]
			var x: float = float(ac.get("x", 0.0))
			var z: float = float(ac.get("y", 0.0))
			n += 1
			if w.is_walkable_at(x, z):
				continue
			bad.append("slot=%d fallback (%.1f, %.1f)" % [sid, x, z])
	else:
		for i in range(map_cfg.start_positions.size()):
			var sp = map_cfg.start_positions[i]
			if typeof(sp) != TYPE_DICTIONARY:
				continue
			var x: float = float(sp.get("x", 0.0))
			var z: float = float(sp.get("y", 0.0))
			n += 1
			if w.is_walkable_at(x, z):
				continue
			bad.append("start=%d (%.1f, %.1f)" % [i, x, z])

	if not bad.is_empty():
		print("TEST_SPAWN_WALKABILITY_FAIL: %s" % ", ".join(bad))
		quit(1)
		return

	print("TEST_SPAWN_WALKABILITY_OK: map=%s starts=%d" % [map_cfg.map_size, n])
	quit(0)
