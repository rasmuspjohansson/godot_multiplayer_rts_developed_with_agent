extends RefCounted
## Uniform grid over the map built with a counting sort into flat PackedInt32Arrays.
## No Dictionaries or Strings in the hot path: rebuild is O(n), a radius query touches
## only the cells overlapping the circle. Callers read results from `scratch[0..count)`.

var cell_size: float = 16.0
var cols: int = 1
var rows: int = 1
## Exposed for callers that inline the cell walk in their own hot loop.
var _cell_start: PackedInt32Array = PackedInt32Array()
var _cell_items: PackedInt32Array = PackedInt32Array()
var _cell_of: PackedInt32Array = PackedInt32Array()
var _fill: PackedInt32Array = PackedInt32Array()
var _n: int = 0
## Result buffer for the last query (ids); valid entries are [0, last_count).
var scratch: PackedInt32Array = PackedInt32Array()

func setup(map_w: float, map_h: float, p_cell_size: float) -> void:
	cell_size = maxf(p_cell_size, 1.0)
	cols = maxi(1, int(ceil(map_w / cell_size)) + 1)
	rows = maxi(1, int(ceil(map_h / cell_size)) + 1)
	_cell_start.resize(cols * rows + 1)
	_fill.resize(cols * rows)
	scratch.resize(256)

func cell_index(x: float, z: float) -> int:
	var cx: int = clampi(int(x / cell_size), 0, cols - 1)
	var cz: int = clampi(int(z / cell_size), 0, rows - 1)
	return cz * cols + cx

## Rebuild from positions; only ids with alive[i] != 0 are inserted.
func build(xs: PackedFloat32Array, zs: PackedFloat32Array, alive: PackedByteArray, n: int) -> void:
	_n = n
	if _cell_of.size() < n:
		_cell_of.resize(n)
	if _cell_items.size() < n:
		_cell_items.resize(n)
	var ncells: int = cols * rows
	_cell_start.fill(0)
	var inv := 1.0 / cell_size
	var maxc := cols - 1
	var maxr := rows - 1
	var cell_of := _cell_of
	var cell_start := _cell_start
	for i in range(n):
		if alive[i] == 0:
			cell_of[i] = -1
			continue
		var cx: int = int(xs[i] * inv)
		var cz: int = int(zs[i] * inv)
		if cx < 0:
			cx = 0
		elif cx > maxc:
			cx = maxc
		if cz < 0:
			cz = 0
		elif cz > maxr:
			cz = maxr
		var c: int = cz * cols + cx
		cell_of[i] = c
		cell_start[c + 1] += 1
	for c in range(ncells):
		cell_start[c + 1] += cell_start[c]
	_fill.fill(0)
	var fill := _fill
	var items := _cell_items
	for i in range(n):
		var c: int = cell_of[i]
		if c < 0:
			continue
		items[cell_start[c] + fill[c]] = i
		fill[c] += 1

## Ids within `radius` of (x, z) (exact circle test). Returns count; ids in `scratch`.
func query_radius(x: float, z: float, radius: float, xs: PackedFloat32Array, zs: PackedFloat32Array) -> int:
	var r2: float = radius * radius
	var cx0: int = clampi(int((x - radius) / cell_size), 0, cols - 1)
	var cx1: int = clampi(int((x + radius) / cell_size), 0, cols - 1)
	var cz0: int = clampi(int((z - radius) / cell_size), 0, rows - 1)
	var cz1: int = clampi(int((z + radius) / cell_size), 0, rows - 1)
	var count: int = 0
	var cap: int = scratch.size()
	for cz in range(cz0, cz1 + 1):
		var row_base: int = cz * cols
		for cx in range(cx0, cx1 + 1):
			var c: int = row_base + cx
			var a: int = _cell_start[c]
			var b: int = _cell_start[c + 1]
			for k in range(a, b):
				var id: int = _cell_items[k]
				var dx: float = xs[id] - x
				var dz: float = zs[id] - z
				if dx * dx + dz * dz <= r2:
					if count >= cap:
						cap *= 2
						scratch.resize(cap)
					scratch[count] = id
					count += 1
	return count

## Ids in the cells overlapping the radius (no exact distance test; caller filters).
func query_cells(x: float, z: float, radius: float) -> int:
	var cx0: int = clampi(int((x - radius) / cell_size), 0, cols - 1)
	var cx1: int = clampi(int((x + radius) / cell_size), 0, cols - 1)
	var cz0: int = clampi(int((z - radius) / cell_size), 0, rows - 1)
	var cz1: int = clampi(int((z + radius) / cell_size), 0, rows - 1)
	var count: int = 0
	var cap: int = scratch.size()
	for cz in range(cz0, cz1 + 1):
		var row_base: int = cz * cols
		for cx in range(cx0, cx1 + 1):
			var c: int = row_base + cx
			var a: int = _cell_start[c]
			var b: int = _cell_start[c + 1]
			if count + (b - a) > cap:
				cap = maxi(cap * 2, count + (b - a))
				scratch.resize(cap)
			for k in range(a, b):
				scratch[count] = _cell_items[k]
				count += 1
	return count

## Nearest alive id to (x, z) within radius, or -1.
func nearest(x: float, z: float, radius: float, xs: PackedFloat32Array, zs: PackedFloat32Array) -> int:
	var n := query_radius(x, z, radius, xs, zs)
	var best := -1
	var best_d2 := INF
	for k in range(n):
		var id: int = scratch[k]
		var dx: float = xs[id] - x
		var dz: float = zs[id] - z
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = id
	return best
