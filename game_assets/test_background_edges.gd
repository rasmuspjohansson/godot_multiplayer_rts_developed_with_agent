extends SceneTree
## Each map edge has an inward-facing backdrop. The back face is culled.

func _init():
	call_deferred("_begin")

func _begin():
	var w: Node = load("res://World.tscn").instantiate()
	root.add_child(w)
	var bg: Node = w.get_node_or_null("Background")
	if bg == null or bg.get_child_count() != 4:
		print("TEST_BACKGROUND_EDGES_FAIL: expected 4 panels")
		quit(1)
		return
	var map_cfg: Node = root.get_node("MapConfig")
	var map_w: float = float(map_cfg.get("width"))
	var map_h: float = float(map_cfg.get("height"))
	var center := Vector3(map_w * 0.5, 0.0, map_h * 0.5)
	var outside := 0
	for child in bg.get_children():
		var panel := child as MeshInstance3D
		if panel == null:
			print("TEST_BACKGROUND_EDGES_FAIL: child is not a mesh")
			quit(1)
			return
		var mat := panel.material_override as StandardMaterial3D
		if mat == null or mat.cull_mode != BaseMaterial3D.CULL_BACK:
			print("TEST_BACKGROUND_EDGES_FAIL: back face is not culled")
			quit(1)
			return
		var normal: Vector3 = panel.global_transform.basis.z
		normal.y = 0.0
		var toward: Vector3 = center - panel.global_position
		toward.y = 0.0
		if normal.normalized().dot(toward.normalized()) < 0.95:
			print("TEST_BACKGROUND_EDGES_FAIL: panel faces away from the map at %s" % panel.global_position)
			quit(1)
			return
		if panel.global_position.x < -0.5 or panel.global_position.x > map_w + 0.5 \
				or panel.global_position.z < -0.5 or panel.global_position.z > map_h + 0.5:
			outside += 1
	if outside != 4:
		print("TEST_BACKGROUND_EDGES_FAIL: panels inside the map: outside=%d" % outside)
		quit(1)
		return
	print("TEST_BACKGROUND_EDGES_OK")
	quit(0)
