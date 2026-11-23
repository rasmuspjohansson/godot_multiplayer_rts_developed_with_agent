extends RefCounted
## Asymmetric ridge plus palisade sections. One stone pays for one section.
## The front is the left side of the directed line from the first click to the second.

const PALISADE_WORLD_HEIGHT := 18.0
const PEAK := 12.0
## Wide enough that every height sample beside the palisade is still on the flat top.
## The terrain grid is 20 units, so a narrower crest gets interpolated into a slope.
const FLAT_HALF := 24.0
const RAMP_WIDTH := 60.0
const STEEP_WIDTH := 20.0
## Full height continues past the palisade ends, then the base slopes down beyond that.
const END_MARGIN := 22.0
const END_EXTENT := 30.0
const BLOCK_RADIUS := 15.0
const BREAK_SECONDS := 5.0
const MELEE_REACH_CAP := 30.0

static func section_length(tex_w: float, tex_h: float) -> float:
	if tex_h <= 1.0:
		return 60.0
	return PALISADE_WORLD_HEIGHT * tex_w / tex_h

static func left_normal(dir: Vector2) -> Vector2:
	return Vector2(-dir.y, dir.x)

## Height added at a signed distance from the crest. Positive is the steep front.
static func profile_height(signed: float) -> float:
	if signed >= -FLAT_HALF and signed <= FLAT_HALF:
		return PEAK
	if signed < -FLAT_HALF:
		var back: float = -signed - FLAT_HALF
		if back >= RAMP_WIDTH:
			return 0.0
		return PEAK * (1.0 - back / RAMP_WIDTH)
	var front: float = signed - FLAT_HALF
	if front >= STEEP_WIDTH:
		return 0.0
	return PEAK * (1.0 - front / STEEP_WIDTH)

static func reach() -> float:
	return FLAT_HALF + maxf(RAMP_WIDTH, STEEP_WIDTH) + END_MARGIN + END_EXTENT

## 1 on the flat top, falling to 0 at the foot of each slope.
static func lateral_factor(signed: float) -> float:
	if PEAK <= 0.0:
		return 0.0
	return profile_height(signed) / PEAK

## 1 along the palisade and a margin past each end, then down to 0.
static func along_factor(along: float, length: float) -> float:
	if along >= -END_MARGIN and along <= length + END_MARGIN:
		return 1.0
	var past: float = (-along - END_MARGIN) if along < 0.0 else (along - length - END_MARGIN)
	if past >= END_EXTENT:
		return 0.0
	return 1.0 - past / END_EXTENT

static func _frame(point: Vector2, start: Vector2, end: Vector2) -> Dictionary:
	var seg: Vector2 = end - start
	var len_sq: float = seg.length_squared()
	if len_sq < 1.0:
		return {"ok": false}
	var length: float = sqrt(len_sq)
	var dir: Vector2 = seg / length
	var rel: Vector2 = point - start
	var along: float = rel.dot(dir)
	var signed: float = rel.dot(left_normal(dir))
	return {"ok": true, "length": length, "along": along, "signed": signed}

## How much to add so the crest is the level `crest_y` and the slopes meet `ground_y`.
static func added_height(point: Vector2, start: Vector2, end: Vector2, ground_y: float, crest_y: float) -> float:
	var frame: Dictionary = _frame(point, start, end)
	if not frame.ok:
		return 0.0
	var shape: float = lateral_factor(float(frame.signed)) * along_factor(float(frame.along), float(frame.length))
	if shape <= 0.0:
		return 0.0
	var target: float = lerpf(ground_y, crest_y, shape)
	return maxf(0.0, target - ground_y)

## Whole sections from start toward aim, never more than the stone stock.
static func plan(start: Vector2, aim: Vector2, stones: int, section_len: float) -> Dictionary:
	var delta: Vector2 = aim - start
	var dist: float = delta.length()
	if stones < 1 or section_len <= 1.0 or dist < 5.0:
		return {"ok": false, "count": 0, "start": start, "end": start}
	var count: int = int(floor(dist / section_len + 0.001))
	if count < 1:
		count = 1
	count = mini(count, stones)
	var end: Vector2 = start + delta / dist * section_len * float(count)
	return {"ok": true, "count": count, "start": start, "end": end}

static func section_lips(start: Vector2, end: Vector2, index: int, section_len: float) -> Dictionary:
	var seg: Vector2 = end - start
	var length: float = seg.length()
	if length < 0.001:
		return {"a": start, "b": start, "lip_a": start, "lip_b": start, "mid": start, "front": Vector2.RIGHT}
	var dir: Vector2 = seg / length
	var front: Vector2 = left_normal(dir)
	var a: Vector2 = start + dir * section_len * float(index)
	var b: Vector2 = start + dir * section_len * float(index + 1)
	if b.distance_to(start) > length:
		b = end
	# The palisade stands on the flat crest, on the line the player drew.
	# The ridge base spreads past that line on both sides.
	var lip_a: Vector2 = a
	var lip_b: Vector2 = b
	return {
		"a": a,
		"b": b,
		"lip_a": lip_a,
		"lip_b": lip_b,
		"mid": (lip_a + lip_b) * 0.5,
		"front": front,
	}

static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)

static func cells_near_segment(
	a: Vector2,
	b: Vector2,
	cols: int,
	rows: int,
	step: float,
	radius: float
) -> Array:
	var cells: Array = []
	if step <= 0.0:
		return cells
	var min_x: float = minf(a.x, b.x) - radius
	var max_x: float = maxf(a.x, b.x) + radius
	var min_z: float = minf(a.y, b.y) - radius
	var max_z: float = maxf(a.y, b.y) + radius
	var i0: int = clampi(int(floor(min_x / step)), 0, cols - 1)
	var i1: int = clampi(int(ceil(max_x / step)), 0, cols - 1)
	var j0: int = clampi(int(floor(min_z / step)), 0, rows - 1)
	var j1: int = clampi(int(ceil(max_z / step)), 0, rows - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var center := Vector2(float(i) * step, float(j) * step)
			if distance_to_segment(center, a, b) <= radius:
				cells.append(Vector2i(i, j))
	return cells
