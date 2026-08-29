extends SceneTree
## Headless: MapConfig terrain feature types produce expected heights.

const _MapConfigScript = preload("res://MapConfig.gd")

func _init():
	call_deferred("_begin")

func _begin():
	var map_cfg: Node = _MapConfigScript.new()
	map_cfg.terrain_features = [
		{"type": "hill", "x": 200.0, "y": 200.0, "base_width": 120.0, "height": 40.0},
		{"type": "ridge", "x1": 400.0, "y1": 100.0, "x2": 400.0, "y2": 300.0, "width": 60.0, "height": 30.0},
		{
			"type": "spline_ridge",
			"points": [
				{"x": 600.0, "y": 100.0},
				{"x": 700.0, "y": 200.0},
				{"x": 600.0, "y": 300.0},
			],
			"width": 60.0,
			"height": 35.0,
		},
		{"type": "plateau", "x": 950.0, "y": 500.0, "radius": 40.0, "falloff": 30.0, "height": 50.0},
		{"type": "valley", "x": 200.0, "y": 200.0, "base_width": 120.0, "depth": 15.0},
		{
			"type": "valley_polygon",
			"depth": 25.0,
			"falloff": 30.0,
			"points": [
				{"x": 600.0, "y": 180.0},
				{"x": 680.0, "y": 220.0},
				{"x": 660.0, "y": 300.0},
				{"x": 580.0, "y": 320.0},
				{"x": 520.0, "y": 260.0},
			],
		},
		{
			"type": "plateau_polygon",
			"height": 45.0,
			"falloff": 25.0,
			"points": [
				{"x": 1180.0, "y": 180.0},
				{"x": 1240.0, "y": 210.0},
				{"x": 1240.0, "y": 270.0},
				{"x": 1180.0, "y": 300.0},
				{"x": 1120.0, "y": 270.0},
				{"x": 1120.0, "y": 210.0},
			],
		},
	]
	map_cfg._precompute_terrain_features()

	var valley_poly_depth: float = map_cfg.sample_height(600.0, 250.0)
	if valley_poly_depth > 5.0:
		print("TEST_TERRAIN_FEATURES_FAIL: valley_polygon did not carve depth=%.3f" % valley_poly_depth)
		quit(1)
		return

	var plateau_poly_h: float = map_cfg.sample_height(1180.0, 240.0)
	if plateau_poly_h < 40.0:
		print("TEST_TERRAIN_FEATURES_FAIL: plateau_polygon center height=%.3f" % plateau_poly_h)
		quit(1)
		return

	var hill_h: float = map_cfg.sample_height(200.0, 200.0)
	if hill_h <= 20.0:
		print("TEST_TERRAIN_FEATURES_FAIL: hill center height=%.3f" % hill_h)
		quit(1)
		return

	var ridge_h: float = map_cfg.sample_height(400.0, 200.0)
	if ridge_h <= 10.0:
		print("TEST_TERRAIN_FEATURES_FAIL: ridge spine height=%.3f" % ridge_h)
		quit(1)
		return

	var spline_h: float = map_cfg.sample_height(700.0, 200.0)
	if spline_h <= 10.0:
		print("TEST_TERRAIN_FEATURES_FAIL: spline_ridge height=%.3f" % spline_h)
		quit(1)
		return

	var plateau_h: float = map_cfg.sample_height(950.0, 500.0)
	if plateau_h < 45.0:
		print("TEST_TERRAIN_FEATURES_FAIL: plateau center height=%.3f" % plateau_h)
		quit(1)
		return

	var without_valley_cfg: Node = _MapConfigScript.new()
	without_valley_cfg.terrain_features = [
		{"type": "hill", "x": 200.0, "y": 200.0, "base_width": 120.0, "height": 40.0},
	]
	without_valley_cfg._precompute_terrain_features()
	var baseline: float = without_valley_cfg.sample_height(200.0, 200.0)
	if hill_h >= baseline - 5.0:
		print(
			"TEST_TERRAIN_FEATURES_FAIL: valley did not carve hill center baseline=%.3f carved=%.3f"
			% [baseline, hill_h]
		)
		quit(1)
		return

	for j in range(0, 11):
		for i in range(0, 11):
			var px: float = float(i) * 100.0
			var pz: float = float(j) * 40.0
			if map_cfg.sample_height(px, pz) < 0.0:
				print("TEST_TERRAIN_FEATURES_FAIL: negative height at (%.1f, %.1f)" % [px, pz])
				quit(1)
				return

	print("TEST_TERRAIN_FEATURES_OK")
	quit(0)
