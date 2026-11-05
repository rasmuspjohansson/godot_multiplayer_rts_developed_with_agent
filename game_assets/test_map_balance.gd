extends SceneTree
## Headless: capture points are fair for every start rally point (run with --map=Valleys).
## Every start has its own Village close by, and for each capture-point type the walking
## distance (in-game A* path) from each start to its nearest point of that type is about
## the same.

const _MapConfigScript = preload("res://MapConfig.gd")

const OWN_VILLAGE_MAX_DIST := 600.0
const MAX_SPREAD := 0.10

func _init():
	call_deferred("_begin")

func _path_length(w: Node, from_xz: Vector2, to_xz: Vector2) -> float:
	var path: PackedVector2Array = w.find_unit_path(from_xz, to_xz)
	if path.is_empty():
		return INF
	var total := 0.0
	var prev := from_xz
	for p in path:
		total += prev.distance_to(p)
		prev = p
	return total

func _begin():
	var map_cfg: Node = _MapConfigScript.new()
	root.add_child(map_cfg)
	var w = load("res://World.tscn").instantiate()
	root.add_child(w)
	for _i in range(12):
		await physics_frame

	var starts: Array = []
	for sp in map_cfg.start_positions:
		starts.append(Vector2(float(sp.get("x", 0.0)), float(sp.get("y", 0.0))))
	var by_type: Dictionary = {}
	for cp in map_cfg.capture_points:
		var t := str(cp.get("type", ""))
		if not by_type.has(t):
			by_type[t] = []
		by_type[t].append({"id": str(cp.get("id", "")), "xz": Vector2(float(cp.get("x", 0.0)), float(cp.get("y", 0.0)))})

	var bad: Array = []
	if starts.size() < 2:
		bad.append("need at least 2 start positions, got %d" % starts.size())
	if not by_type.has("Village"):
		bad.append("no Village capture points")

	var report: Array = []
	for t in by_type:
		var nearest: Array = []
		var nearest_ids: Array = []
		for s in starts:
			var best := INF
			var best_id := ""
			for cp in by_type[t]:
				var d := _path_length(w, s, cp["xz"])
				if d < best:
					best = d
					best_id = cp["id"]
			nearest.append(best)
			nearest_ids.append(best_id)
		var lo: float = nearest.min()
		var hi: float = nearest.max()
		if hi == INF:
			bad.append("%s: unreachable from some start" % t)
			continue
		var spread := (hi - lo) / hi
		report.append("%s=%.0f..%.0f(%.0f%%)" % [t, lo, hi, spread * 100.0])
		if spread > MAX_SPREAD:
			bad.append("%s: nearest walking distances %s differ by %.0f%%" % [t, str(nearest), spread * 100.0])
		if t == "Village":
			for k in range(starts.size()):
				if nearest[k] > OWN_VILLAGE_MAX_DIST:
					bad.append("start %d: nearest Village is %.0f away" % [k, nearest[k]])
				for m in range(k):
					if nearest_ids[m] == nearest_ids[k]:
						bad.append("starts %d and %d share Village %s" % [m, k, nearest_ids[k]])

	if not bad.is_empty():
		print("TEST_MAP_BALANCE_FAIL: map=%s %s" % [map_cfg.map_size, "; ".join(bad)])
		quit(1)
		return
	print("TEST_MAP_BALANCE_OK: map=%s starts=%d %s" % [map_cfg.map_size, starts.size(), " ".join(report)])
	quit(0)
