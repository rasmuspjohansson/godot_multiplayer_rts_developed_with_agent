extends SceneTree
## Headless XL: ~30 vegetation sprites on walkable terrain; all three kinds present.

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

	if map_cfg.map_size != "XL":
		print("TEST_VEGETATION_SKIP: map=%s (run with --map=XL)" % map_cfg.map_size)
		quit(0)
		return

	var foliage: Node = w.get_node_or_null("Foliage")
	if foliage == null:
		print("TEST_VEGETATION_FAIL: missing Foliage node")
		quit(1)
		return

	var count := foliage.get_child_count()
	var expected: int = int(map_cfg.get_vegetation().get("count", 30))
	if count < expected - 3 or count > expected:
		print("TEST_VEGETATION_FAIL: expected ~%d vegetation got %d" % [expected, count])
		quit(1)
		return

	var has_tree := false
	var has_spruce := false
	var has_bush := false
	var has_stone := false
	for child in foliage.get_children():
		var name_str := str(child.name)
		if name_str.begins_with("Veg_tree_"):
			has_tree = true
		elif name_str.begins_with("Veg_spruce_"):
			has_spruce = true
		elif name_str.begins_with("Veg_bush_"):
			has_bush = true
		elif name_str.begins_with("Veg_stone_"):
			has_stone = true
		var pos: Vector3 = child.position
		if not w.is_walkable_at(pos.x, pos.z):
			print("TEST_VEGETATION_FAIL: %s on unwalkable (%.0f, %.0f)" % [name_str, pos.x, pos.z])
			quit(1)
			return

	if not has_tree or not has_spruce or not has_bush or not has_stone:
		print(
			"TEST_VEGETATION_FAIL: missing kinds tree=%s spruce=%s bush=%s stone=%s"
			% [has_tree, has_spruce, has_bush, has_stone]
		)
		quit(1)
		return

	print(
		"TEST_VEGETATION_OK: count=%d tree=%s spruce=%s bush=%s stone=%s"
		% [count, has_tree, has_spruce, has_bush, has_stone]
	)
	quit(0)
