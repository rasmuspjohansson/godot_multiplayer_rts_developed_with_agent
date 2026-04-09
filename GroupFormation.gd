extends RefCounted
## Shared math for Total War–style line formation (2D map coords: x,y).

const FORMATION_SPACING := 30.0
## Along-drag gap between adjacent armies' segments so two formations do not share one goal point.
const ARMY_SEGMENT_GAP := FORMATION_SPACING * 0.5

## Drag from line_start (RMB press) to line_end (cursor / release). The first rank is laid **on that segment**:
## soldiers are spread evenly from line_start to line_end (index 0 at press, last in-row at the far end).
## How many fit on one row is limited by segment length vs `FORMATION_SPACING`; overflow forms deeper ranks along -perp.
static func compute_line_formation(line_start: Vector2, line_end: Vector2, soldier_count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if soldier_count <= 0:
		return out
	var delta := line_end - line_start
	var length := delta.length()
	var forward := Vector2(1, 0)
	if length >= 0.01:
		forward = delta / length
	var perp := Vector2(-forward.y, forward.x)
	# Max soldiers on one row along [line_start, line_end] with at least FORMATION_SPACING between neighbours.
	var n_wide: int = mini(soldier_count, maxi(1, int(floor(length / FORMATION_SPACING)) + 1))
	for i in range(soldier_count):
		var depth_rank: int = i / n_wide
		var j: int = i % n_wide
		var along_t := 0.0
		if n_wide > 1:
			along_t = length * float(j) / float(n_wide - 1)
		var base := line_start + forward * along_t
		var depth_off := -perp * (float(depth_rank) * FORMATION_SPACING)
		out.append(base + depth_off)
	return out

## Merge soldiers from armies (alive), stable by army_id then name.
static func collect_soldiers_sorted(armies: Array) -> Array:
	var units := []
	for army in armies:
		if army == null or not is_instance_valid(army):
			continue
		if army.is_routed:
			continue
		if not army.has_method("get_alive_soldiers"):
			continue
		for s in army.get_alive_soldiers():
			if s and is_instance_valid(s) and not s.is_dead:
				units.append(s)
	units.sort_custom(func(a, b):
		if str(a.army_id) != str(b.army_id):
			return str(a.army_id) < str(b.army_id)
		return str(a.name) < str(b.name)
	)
	return units

## Alive soldiers in one army, stable by unit name.
static func collect_soldiers_sorted_one_army(army) -> Array:
	var units: Array = []
	if army == null or not is_instance_valid(army):
		return units
	if army.is_routed:
		return units
	if not army.has_method("get_alive_soldiers"):
		return units
	for s in army.get_alive_soldiers():
		if s and is_instance_valid(s) and not s.is_dead:
			units.append(s)
	units.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return units

## RMB drag split across armies in order (first selected → first chord slice). Each army gets its own
## `compute_line_formation` on a sub-segment; returns parallel `units` and `positions` for RPC/ghosts.
## If the drag is too short to gap K segments, falls back to one merged formation (same as legacy).
static func compute_multi_army_positions(line_start: Vector2, line_end: Vector2, armies: Array) -> Dictionary:
	var out_units: Array = []
	var out_positions: Array = []
	var active: Array = []
	for a in armies:
		if a == null or not is_instance_valid(a):
			continue
		if collect_soldiers_sorted_one_army(a).size() > 0:
			active.append(a)
	var K: int = active.size()
	if K == 0:
		return {"units": out_units, "positions": out_positions}
	if K == 1:
		var u1: Array = collect_soldiers_sorted_one_army(active[0])
		out_positions = compute_line_formation(line_start, line_end, u1.size())
		return {"units": u1, "positions": out_positions}
	var delta := line_end - line_start
	var length := delta.length()
	var forward := Vector2(1, 0)
	if length >= 0.01:
		forward = delta / length
	var gap: float = ARMY_SEGMENT_GAP
	var usable: float = length - float(K - 1) * gap
	# Not enough room to place K blocks without overlap — legacy single line.
	if usable <= 1.0:
		var merged: Array = collect_soldiers_sorted(active)
		out_positions = compute_line_formation(line_start, line_end, merged.size())
		return {"units": merged, "positions": out_positions}
	var seg_len: float = usable / float(K)
	for k in range(K):
		var army = active[k]
		var u: Array = collect_soldiers_sorted_one_army(army)
		if u.is_empty():
			continue
		var t0: float = float(k) * (seg_len + gap)
		var sub_start: Vector2 = line_start + forward * t0
		var sub_end: Vector2 = sub_start + forward * seg_len
		var pos_chunk: Array[Vector2] = compute_line_formation(sub_start, sub_end, u.size())
		for s in u:
			out_units.append(s)
		for p in pos_chunk:
			out_positions.append(p)
	return {"units": out_units, "positions": out_positions}
