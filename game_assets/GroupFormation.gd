extends RefCounted
## Shared math for Total War–style line formation (2D map coords: x,y).

const FORMATION_SPACING := 15.0
const FOOT_FORMATION_SPACING := 10.0
## Along-drag gap between adjacent armies' segments so two formations do not share one goal point.
const ARMY_SEGMENT_GAP := FORMATION_SPACING * 0.5

static func _spacing_for_army(army) -> float:
	if army == null or not is_instance_valid(army):
		return FOOT_FORMATION_SPACING
	var soldiers: Array = []
	if army.has_method("get_alive_soldiers"):
		soldiers = army.get_alive_soldiers()
	elif army.get("soldiers") is Array:
		soldiers = army.soldiers
	for s in soldiers:
		if s and is_instance_valid(s) and s.get("has_horse"):
			return FORMATION_SPACING
	return FOOT_FORMATION_SPACING

## Drag from line_start (RMB press) to line_end (cursor / release). The first rank is laid **on that segment**:
## soldiers are spread evenly from line_start to line_end (index 0 at press, last in-row at the far end).
## How many fit on one row is limited by segment length vs spacing; overflow forms deeper ranks along -perp.
static func compute_line_formation(
	line_start: Vector2,
	line_end: Vector2,
	soldier_count: int,
	spacing: float = FOOT_FORMATION_SPACING,
) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if soldier_count <= 0:
		return out
	var delta := line_end - line_start
	var length := delta.length()
	var forward := Vector2(1, 0)
	if length >= 0.01:
		forward = delta / length
	var perp := Vector2(-forward.y, forward.x)
	var n_wide: int = mini(soldier_count, maxi(1, int(floor(length / spacing)) + 1))
	for i in range(soldier_count):
		var depth_rank: int = i / n_wide
		var j: int = i % n_wide
		var along_t := 0.0
		if n_wide > 1:
			along_t = length * float(j) / float(n_wide - 1)
		var base := line_start + forward * along_t
		var depth_off := -perp * (float(depth_rank) * spacing)
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
		var sp1 := _spacing_for_army(active[0])
		out_positions = compute_line_formation(line_start, line_end, u1.size(), sp1)
		return {"units": u1, "positions": out_positions}
	var delta := line_end - line_start
	var length := delta.length()
	var forward := Vector2(1, 0)
	if length >= 0.01:
		forward = delta / length
	var gap: float = ARMY_SEGMENT_GAP
	var usable: float = length - float(K - 1) * gap
	if usable <= 1.0:
		var merged: Array = collect_soldiers_sorted(active)
		var merged_spacing := FOOT_FORMATION_SPACING
		for a in active:
			if _spacing_for_army(a) > merged_spacing:
				merged_spacing = _spacing_for_army(a)
		out_positions = compute_line_formation(line_start, line_end, merged.size(), merged_spacing)
		return {"units": merged, "positions": out_positions}
	var seg_len: float = usable / float(K)
	for k in range(K):
		var army = active[k]
		var u: Array = collect_soldiers_sorted_one_army(army)
		if u.is_empty():
			continue
		var army_spacing := _spacing_for_army(army)
		var t0: float = float(k) * (seg_len + gap)
		var sub_start: Vector2 = line_start + forward * t0
		var sub_end: Vector2 = sub_start + forward * seg_len
		var pos_chunk: Array[Vector2] = compute_line_formation(sub_start, sub_end, u.size(), army_spacing)
		for s in u:
			out_units.append(s)
		for p in pos_chunk:
			out_positions.append(p)
	return {"units": out_units, "positions": out_positions}
