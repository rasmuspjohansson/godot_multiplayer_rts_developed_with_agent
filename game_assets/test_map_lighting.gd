extends SceneTree
## Headless XL: per-map directional light scales with terrain height; ground uses lit shading.

const _MapConfigScript = preload("res://MapConfig.gd")

func _init():
	call_deferred("_begin")

func _begin():
	var map_cfg: Node = _MapConfigScript.new()
	root.add_child(map_cfg)
	var w = load("res://World.tscn").instantiate()
	root.add_child(w)
	await process_frame
	await process_frame
	for _i in range(10):
		await physics_frame

	if map_cfg.map_size != "XL":
		print("TEST_LIGHTING_SKIP: map=%s (run with --map=XL)" % map_cfg.map_size)
		quit(0)
		return

	var light: DirectionalLight3D = w.get_node_or_null("DirectionalLight3D")
	if light == null:
		print("TEST_LIGHTING_FAIL: missing DirectionalLight3D")
		quit(1)
		return

	var cfg: Dictionary = map_cfg.get_lighting()
	if light.directional_shadow_max_distance <= 800.0:
		print(
			"TEST_LIGHTING_FAIL: shadow_max_distance=%.1f (expected > 800 on XL)"
			% light.directional_shadow_max_distance
		)
		quit(1)
		return

	if light.light_energy > 0.6:
		print("TEST_LIGHTING_FAIL: energy=%.2f (expected <= 0.6)" % light.light_energy)
		quit(1)
		return

	if not is_equal_approx(light.light_energy, float(cfg.energy)):
		print(
			"TEST_LIGHTING_FAIL: energy %.2f != map JSON %.2f"
			% [light.light_energy, float(cfg.energy)]
		)
		quit(1)
		return

	var ground: Node = w.get_node_or_null("Ground")
	if ground == null or not ground is MeshInstance3D:
		print("TEST_LIGHTING_FAIL: missing Ground MeshInstance3D")
		quit(1)
		return

	var mesh: Mesh = ground.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		print("TEST_LIGHTING_FAIL: ground has no mesh surface")
		quit(1)
		return

	var mat: Material = mesh.surface_get_material(0)
	if mat == null or not (mat is StandardMaterial3D or mat is ShaderMaterial):
		print("TEST_LIGHTING_FAIL: missing ground material")
		quit(1)
		return

	print(
		"TEST_LIGHTING_OK: energy=%.2f shadow=%.1f max_h=%.1f"
		% [light.light_energy, light.directional_shadow_max_distance, w._max_terrain_height]
	)
	quit(0)
