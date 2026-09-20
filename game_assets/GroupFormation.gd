extends RefCounted
## Shared math for Total War–style line formation (2D map coords: x,y).
## Works on counts and spacings only; armies are laid out by FormationController in the sim.

const _Formation := preload("res://sim/FormationController.gd")
const FORMATION_SPACING := _Formation.MOUNTED_SPACING
const FOOT_FORMATION_SPACING := _Formation.FOOT_SPACING
## Along-drag gap between adjacent armies' segments so two formations do not share one goal point.
const ARMY_SEGMENT_GAP := FORMATION_SPACING * 0.5

static func spacing_for(has_horse: bool) -> float:
	return FORMATION_SPACING if has_horse else FOOT_FORMATION_SPACING

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

## Splits the drag segment into one sub-segment per army (in selection order) with a gap between
## them. If the drag is too short to fit K segments every army gets the whole segment.
## Returns an Array of {"start": Vector2, "end": Vector2}.
static func split_segments(line_start: Vector2, line_end: Vector2, army_count: int) -> Array:
	var out: Array = []
	if army_count <= 0:
		return out
	if army_count == 1:
		out.append({"start": line_start, "end": line_end})
		return out
	var delta := line_end - line_start
	var length := delta.length()
	var forward := Vector2(1, 0)
	if length >= 0.01:
		forward = delta / length
	var usable: float = length - float(army_count - 1) * ARMY_SEGMENT_GAP
	if usable <= 1.0:
		for _k in range(army_count):
			out.append({"start": line_start, "end": line_end})
		return out
	var seg_len: float = usable / float(army_count)
	for k in range(army_count):
		var t0: float = float(k) * (seg_len + ARMY_SEGMENT_GAP)
		var sub_start: Vector2 = line_start + forward * t0
		out.append({"start": sub_start, "end": sub_start + forward * seg_len})
	return out

## Facing of a formation whose first rank lies on the drag segment (front toward +perp).
static func front_angle_for_segment(line_start: Vector2, line_end: Vector2) -> float:
	var delta := line_end - line_start
	if delta.length() < 0.01:
		return -PI * 0.5
	return delta.angle() + PI * 0.5

## Ghost preview positions for the given per-army (count, has_horse) pairs. Each army gets
## exactly the grid the sim will march in: fixed pitch, ranks from
## FormationController.rows_for_width(count, segment length), centred on its segment and
## rotated so the first rank lies on the drag line (what you preview is what you get).
static func preview_positions(line_start: Vector2, line_end: Vector2, counts: Array, mounted: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var segs := split_segments(line_start, line_end, counts.size())
	var line_dir := _Formation.line_direction_for_front(front_angle_for_segment(line_start, line_end))
	for k in range(counts.size()):
		var seg: Dictionary = segs[k]
		var s: Vector2 = seg["start"]
		var e: Vector2 = seg["end"]
		var sp := spacing_for(bool(mounted[k]))
		var n := int(counts[k])
		var rows := _Formation.rows_for_width(n, s.distance_to(e), sp)
		var mid := (s + e) * 0.5
		for o in _Formation.grid_offsets(n, rows, sp):
			out.append(mid + o.rotated(line_dir))
	return out
