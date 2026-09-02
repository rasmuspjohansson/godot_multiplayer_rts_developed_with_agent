extends SceneTree
## Headless: every map army spawn must be on walkable terrain.

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
	for slot in map_cfg.player_starts:
		var sid: int = int(slot.get("slot", -1))
		for ac in slot.get("armies", []):
			var x: float = float(ac.get("x", 0.0))
			var z: float = float(ac.get("y", 0.0))
			if w.is_walkable_at(x, z):
				continue
			var kind := "horse" if ac.get("horse", false) else ("spear" if ac.get("spear", false) else "unit")
			bad.append("slot=%d %s (%.1f, %.1f)" % [sid, kind, x, z])

	if not bad.is_empty():
		print("TEST_SPAWN_WALKABILITY_FAIL: %s" % ", ".join(bad))
		quit(1)
		return

	print("TEST_SPAWN_WALKABILITY_OK: map=%s spawns=%d" % [map_cfg.map_size, _spawn_count(map_cfg)])
	quit(0)

func _spawn_count(map_cfg: Node) -> int:
	var n := 0
	for slot in map_cfg.player_starts:
		n += slot.get("armies", []).size()
	return n
