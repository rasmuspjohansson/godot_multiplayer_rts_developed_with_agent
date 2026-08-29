extends RefCounted
## Terrain walkability grid + AStarGrid2D pathfinding (water + steep slopes).

const _WaterBuilder = preload("res://WaterBuilder.gd")

var _walkable: PackedByteArray = PackedByteArray()
var _cols: int = 0
var _rows: int = 0
var _step: float = 20.0
var _astar: AStarGrid2D

func build(
	heights: PackedFloat32Array,
	cols: int,
	rows: int,
	step: float,
	water_basins: Array,
	max_slope_deg: float
) -> void:
	_cols = cols
	_rows = rows
	_step = step
	_walkable.resize(cols * rows)
	for idx in range(_walkable.size()):
		_walkable[idx] = 1
	for j in range(rows):
		for i in range(cols):
			if _max_slope_at(heights, cols, rows, i, j, step) > max_slope_deg:
				_walkable[j * cols + i] = 0
	for basin in water_basins:
		_apply_water_basin(basin)
		_apply_water_basin_polygon(basin)
	_build_astar()

func walkable_count() -> int:
	var n := 0
	for b in _walkable:
		if b != 0:
			n += 1
	return n

func is_walkable_cell(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= _cols or j >= _rows:
		return false
	return _walkable[j * _cols + i] != 0

func is_walkable_world(x: float, z: float) -> bool:
	var cell := world_to_cell(x, z)
	return is_walkable_cell(cell.x, cell.y)

func world_to_cell(x: float, z: float) -> Vector2i:
	var i := clampi(int(round(x / _step)), 0, _cols - 1)
	var j := clampi(int(round(z / _step)), 0, _rows - 1)
	return Vector2i(i, j)

func cell_center_world(i: int, j: int) -> Vector2:
	return Vector2(float(i) * _step, float(j) * _step)

func nearest_walkable(x: float, z: float, max_radius_cells: int = 12) -> Vector2:
	if is_walkable_world(x, z):
		return Vector2(x, z)
	var center := world_to_cell(x, z)
	for radius in range(1, max_radius_cells + 1):
		for dj in range(-radius, radius + 1):
			for di in range(-radius, radius + 1):
				if maxi(absi(di), absi(dj)) != radius:
					continue
				var i := center.x + di
				var j := center.y + dj
				if is_walkable_cell(i, j):
					return cell_center_world(i, j)
	return Vector2(x, z)

func has_clear_line(from_xz: Vector2, to_xz: Vector2) -> bool:
	var a := world_to_cell(from_xz.x, from_xz.y)
	var b := world_to_cell(to_xz.x, to_xz.y)
	var cells := _grid_line_cells(a, b)
	for cell in cells:
		if not is_walkable_cell(cell.x, cell.y):
			return false
	return true

func find_path(from_xz: Vector2, to_xz: Vector2) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array()
	var from_cell := world_to_cell(from_xz.x, from_xz.y)
	var to_cell := world_to_cell(to_xz.x, to_xz.y)
	if not is_walkable_cell(from_cell.x, from_cell.y):
		var snapped_from := nearest_walkable(from_xz.x, from_xz.y)
		from_cell = world_to_cell(snapped_from.x, snapped_from.y)
	if not is_walkable_cell(to_cell.x, to_cell.y):
		var snapped_to := nearest_walkable(to_xz.x, to_xz.y)
		to_cell = world_to_cell(snapped_to.x, snapped_to.y)
	if not is_walkable_cell(from_cell.x, from_cell.y) or not is_walkable_cell(to_cell.x, to_cell.y):
		return PackedVector2Array()
	if from_cell == to_cell:
		return PackedVector2Array([to_xz])
	if has_clear_line(from_xz, to_xz):
		return PackedVector2Array([to_xz])
	var id_path: Array = _astar.get_id_path(from_cell, to_cell)
	if id_path.is_empty():
		return PackedVector2Array()
	var out := PackedVector2Array()
	for id_var in id_path:
		var id: Vector2i = id_var
		out.append(cell_center_world(id.x, id.y))
	if out.size() > 0:
		out[out.size() - 1] = cell_center_world(to_cell.x, to_cell.y)
	return out

func _max_slope_at(
	heights: PackedFloat32Array,
	cols: int,
	rows: int,
	i: int,
	j: int,
	step: float
) -> float:
	var h: float = heights[j * cols + i]
	var max_slope := 0.0
	for dj in range(-1, 2):
		for di in range(-1, 2):
			if di == 0 and dj == 0:
				continue
			var ni: int = clampi(i + di, 0, cols - 1)
			var nj: int = clampi(j + dj, 0, rows - 1)
			var dh: float = absf(heights[nj * cols + ni] - h)
			var dist: float = step * (sqrt(2.0) if di != 0 and dj != 0 else 1.0)
			max_slope = maxf(max_slope, rad_to_deg(atan(dh / maxf(dist, 0.001))))
	return max_slope

func _apply_water_basin(basin: Dictionary) -> void:
	var mask: PackedByteArray = basin.get("mask", PackedByteArray())
	if mask.is_empty():
		return
	var basin_cols: int = int(basin.get("cols", 0))
	var basin_rows: int = int(basin.get("rows", 0))
	var min_i: int = int(basin.get("min_i", 0))
	var min_j: int = int(basin.get("min_j", 0))
	for local_j in range(basin_rows):
		for local_i in range(basin_cols):
			if mask[local_j * basin_cols + local_i] == 0:
				continue
			var gi: int = min_i + local_i
			var gj: int = min_j + local_j
			if gi >= 0 and gj >= 0 and gi < _cols and gj < _rows:
				_walkable[gj * _cols + gi] = 0

func _apply_water_basin_polygon(basin: Dictionary) -> void:
	var poly: PackedVector2Array = _WaterBuilder.build_polygon_from_basin(basin)
	if poly.size() < 3:
		return
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p in poly:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	var i0: int = clampi(int(floor(min_x / _step)), 0, _cols - 1)
	var i1: int = clampi(int(ceil(max_x / _step)), 0, _cols - 1)
	var j0: int = clampi(int(floor(min_z / _step)), 0, _rows - 1)
	var j1: int = clampi(int(ceil(max_z / _step)), 0, _rows - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var pt := Vector2(float(i) * _step, float(j) * _step)
			if Geometry2D.is_point_in_polygon(pt, poly):
				_walkable[j * _cols + i] = 0

func _build_astar() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, _cols, _rows)
	_astar.cell_size = Vector2(_step, _step)
	_astar.offset = Vector2.ZERO
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.update()
	for j in range(_rows):
		for i in range(_cols):
			if not is_walkable_cell(i, j):
				_astar.set_point_solid(Vector2i(i, j), true)

func _grid_line_cells(a: Vector2i, b: Vector2i) -> Array:
	var cells: Array = []
	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		cells.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return cells
