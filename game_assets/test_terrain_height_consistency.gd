extends SceneTree
## Headless: raycast ground height must match mesh/collision grid at terrain sample points.

const _MapConfigScript = preload("res://MapConfig.gd")
const TERRAIN_STEP := 20.0
const MAX_DELTA := 0.5

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

	var cols: int = int(ceil(map_cfg.width / TERRAIN_STEP)) + 1
	var rows: int = int(ceil(map_cfg.height / TERRAIN_STEP)) + 1
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for j in range(rows):
		var pz: float = float(j) * TERRAIN_STEP
		for i in range(cols):
			var px: float = float(i) * TERRAIN_STEP
			var sampled: float = map_cfg.sample_height(px, pz)
			var raycast: float = w.get_ground_height_at(px, pz)
			var delta := absf(raycast - sampled)
			if delta > worst:
				worst = delta
				worst_at = Vector2(px, pz)
			if delta > MAX_DELTA:
				print(
					"TEST_TERRAIN_HEIGHT_FAIL: at=(%.1f,%.1f) sample=%.3f raycast=%.3f delta=%.3f"
					% [px, pz, sampled, raycast, delta]
				)
				quit(1)
				return

	print("TEST_TERRAIN_HEIGHT_OK: worst_delta=%.3f at=(%.1f,%.1f)" % [worst, worst_at.x, worst_at.y])
	quit(0)
