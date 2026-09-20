extends RefCounted
## Shared math for Total War–style line formation (2D map coords: x,y).
## Works on counts and spacings only; armies are laid out by FormationController in the sim.

const _Formation := preload("res://sim/FormationController.gd")
const FORMATION_SPACING := _Formation.MOUNTED_SPACING
const FOOT_FORMATION_SPACING := _Formation.FOOT_SPACING
const MIN_DRAG_LENGTH := 0.01
## Min center distance between last front file of one army and first of the next (~2× foot radius).
const ARMY_BOUNDARY_RADIUS_CLEAR := 9.0

static func spacing_for(has_horse: bool) -> float:
	return FORMATION_SPACING if has_horse else FOOT_FORMATION_SPACING

## Along-drag clearance between adjacent armies' front ranks (after corner placement).
static func boundary_gap(spacing_a: float, spacing_b: float) -> float:
	return maxf(spacing_a, spacing_b) + ARMY_BOUNDARY_RADIUS_CLEAR

## Single source of truth for RMB drag: press = front rank file 1, release = last front file,
## depth behind. Returns world positions plus sim metadata (rows, direction along drag, anchor).
static func drag_layout(
	line_start: Vector2,
	line_end: Vector2,
	soldier_count: int,
	spacing: float = FOOT_FORMATION_SPACING,
) -> Dictionary:
	var positions: Array[Vector2] = []
	if soldier_count <= 0:
		return {
			"positions": positions,
			"rows": 1,
			"cols": 0,
			"direction": 0.0,
			"front_angle": -PI * 0.5,
			"anchor": line_start,
			"front_span": 0.0,
		}
	var delta := line_end - line_start
	var length := delta.length()
	var direction := delta.angle() if length >= MIN_DRAG_LENGTH else 0.0
	var n_wide: int = 1
	var front_span := 0.0
	if length >= MIN_DRAG_LENGTH:
		n_wide = mini(soldier_count, maxi(1, int(floor(length / spacing)) + 1))
		front_span = length
	var rows: int = ceili(float(soldier_count) / float(n_wide))
	for i in range(soldier_count):
		var depth_rank: int = i / n_wide
		var j: int = i % n_wide
		var lx := 0.0
		if n_wide > 1:
			lx = front_span * float(j) / float(n_wide - 1)
		var ly := float(depth_rank) * spacing
		positions.append(line_start + Vector2(lx, ly).rotated(direction))
	return {
		"positions": positions,
		"rows": rows,
		"cols": n_wide,
		"direction": direction,
		"front_angle": direction + PI * 0.5,
		"anchor": line_start,
		"front_span": front_span,
	}

## Drag from line_start (RMB press) to line_end (cursor / release). Delegates to drag_layout.
static func compute_line_formation(
	line_start: Vector2,
	line_end: Vector2,
	soldier_count: int,
	spacing: float = FOOT_FORMATION_SPACING,
) -> Array[Vector2]:
	var layout: Dictionary = drag_layout(line_start, line_end, soldier_count, spacing)
	return layout["positions"]

## Splits the drag segment into one sub-segment per army (in selection order) with a gap between
## them. `spacings` = per-army formation pitch (mounted/foot); gaps scale so bodies do not overlap.
## If the drag is too short to fit K segments every army gets the whole segment.
## Returns an Array of {"start": Vector2, "end": Vector2}.
static func split_segments(
	line_start: Vector2,
	line_end: Vector2,
	army_count: int,
	spacings: Array = [],
) -> Array:
	var out: Array = []
	if army_count <= 0:
		return out
	if army_count == 1:
		out.append({"start": line_start, "end": line_end})
		return out
	var delta := line_end - line_start
	var length := delta.length()
	var forward := Vector2(1, 0)
	if length >= MIN_DRAG_LENGTH:
		forward = delta / length
	var default_sp := FOOT_FORMATION_SPACING
	var gap_total := 0.0
	for i in range(army_count - 1):
		var sa: float = default_sp
		var sb: float = default_sp
		if i < spacings.size():
			sa = float(spacings[i])
		if i + 1 < spacings.size():
			sb = float(spacings[i + 1])
		gap_total += boundary_gap(sa, sb)
	var usable: float = length - gap_total
	if usable <= 1.0:
		for _k in range(army_count):
			out.append({"start": line_start, "end": line_end})
		return out
	var seg_len: float = usable / float(army_count)
	var t_along := 0.0
	for k in range(army_count):
		var sub_start: Vector2 = line_start + forward * t_along
		out.append({"start": sub_start, "end": sub_start + forward * seg_len})
		t_along += seg_len
		if k < army_count - 1:
			var sa: float = default_sp
			var sb: float = default_sp
			if k < spacings.size():
				sa = float(spacings[k])
			if k + 1 < spacings.size():
				sb = float(spacings[k + 1])
			t_along += boundary_gap(sa, sb)
	return out

## Facing of a formation whose first rank lies on the drag segment (front toward +perp).
static func front_angle_for_segment(line_start: Vector2, line_end: Vector2) -> float:
	var delta := line_end - line_start
	if delta.length() < MIN_DRAG_LENGTH:
		return -PI * 0.5
	return delta.angle() + PI * 0.5

## Ghost preview positions — same corner-anchored layout the sim uses after a drag order.
static func preview_positions(line_start: Vector2, line_end: Vector2, counts: Array, mounted: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var spacings: Array = []
	for k in range(counts.size()):
		spacings.append(spacing_for(bool(mounted[k])))
	var segs := split_segments(line_start, line_end, counts.size(), spacings)
	for k in range(counts.size()):
		var seg: Dictionary = segs[k]
		var s: Vector2 = seg["start"]
		var e: Vector2 = seg["end"]
		var sp := spacing_for(bool(mounted[k]))
		var n := int(counts[k])
		var layout: Dictionary = drag_layout(s, e, n, sp)
		for p in layout["positions"]:
			out.append(p)
	return out
