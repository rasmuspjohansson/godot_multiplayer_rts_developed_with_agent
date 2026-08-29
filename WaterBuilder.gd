class_name WaterBuilder
## Auto-detect terrain basins and build flat polygon water meshes for lakes.

const DEFAULT_DEPTH_THRESHOLD := 12.0
const DEFAULT_FILL_EPSILON := 8.0
const DEFAULT_MIN_CELLS := 100
const DEFAULT_WATER_DEPTH := 6.0
const MAX_ASPECT_RATIO := 8.0
const UV_REPEAT_UNITS := 280.0
const POLYGON_MARGIN_FACTOR := 0.05
const SMOOTH_ITERATIONS := 2
const SURFACE_CLIP_EPSILON := 0.05
const INTERIOR_HIGH_EPSILON := 0.5

const DEFAULT_MIN_BASIN_HEIGHT := 12.0

static func default_params() -> Dictionary:
	return {
		"depth_threshold": DEFAULT_DEPTH_THRESHOLD,
		"fill_epsilon": DEFAULT_FILL_EPSILON,
		"min_cells": DEFAULT_MIN_CELLS,
		"water_depth": DEFAULT_WATER_DEPTH,
		"min_basin_height": DEFAULT_MIN_BASIN_HEIGHT,
		"reject_map_edge": false,
	}

static func detect_lake_basins(
	heights: PackedFloat32Array,
	cols: int,
	rows: int,
	step: float,
	map_w: float,
	map_h: float,
	params: Dictionary = {}
) -> Array:
	if heights.is_empty() or cols < 3 or rows < 3:
		return []
	var fill_epsilon: float = params.get("fill_epsilon", DEFAULT_FILL_EPSILON)
	var min_cells: int = params.get("min_cells", DEFAULT_MIN_CELLS)
	var water_depth: float = params.get("water_depth", DEFAULT_WATER_DEPTH)
	var min_basin_height: float = params.get("min_basin_height", DEFAULT_MIN_BASIN_HEIGHT)
	var reject_map_edge: bool = params.get("reject_map_edge", false)
	var visited := PackedByteArray()
	visited.resize(cols * rows)
	var candidates := PackedByteArray()
	candidates.resize(cols * rows)
	for j in range(1, rows - 1):
		for i in range(1, cols - 1):
			var idx := j * cols + i
			var h: float = heights[idx]
			var is_local_min := true
			for dj in range(-1, 2):
				for di in range(-1, 2):
					if di == 0 and dj == 0:
						continue
					var nh: float = heights[(j + dj) * cols + (i + di)]
					if nh < h:
						is_local_min = false
			if is_local_min:
				candidates[idx] = 1
	var lakes: Array = []
	var border_margin := 3
	var seeds: Array = []
	for j in range(rows):
		for i in range(cols):
			var idx := j * cols + i
			if candidates[idx] == 0:
				continue
			if heights[idx] < min_basin_height:
				continue
			if reject_map_edge and (
				i < border_margin or j < border_margin
				or i >= cols - border_margin or j >= rows - border_margin
			):
				continue
			seeds.append({"i": i, "j": j, "h": heights[idx]})
	seeds.sort_custom(func(a, b): return a.h < b.h)
	for seed in seeds:
		var i: int = seed.i
		var j: int = seed.j
		var start_idx := j * cols + i
		if visited[start_idx] != 0:
			continue
			var basin := _flood_fill_basin(
				heights, cols, rows, step, i, j, fill_epsilon,
				params.get("max_fill_cells", 0)
			)
			if basin.cell_count < min_cells:
				continue
			if basin.min_height < min_basin_height:
				continue
			if reject_map_edge and (
				basin.min_i == 0 or basin.max_i == cols - 1
				or basin.min_j == 0 or basin.max_j == rows - 1
			):
				continue
			var min_x: float = float(basin.min_i) * step
			var max_x: float = float(basin.max_i + 1) * step
			var min_z: float = float(basin.min_j) * step
			var max_z: float = float(basin.max_j + 1) * step
			if basin.min_i == 0:
				min_x = 0.0
			if basin.max_i >= cols - 1:
				max_x = map_w
			if basin.min_j == 0:
				min_z = 0.0
			if basin.max_j >= rows - 1:
				max_z = map_h
			var width: float = max_x - min_x
			var depth: float = max_z - min_z
			if width < step or depth < step:
				continue
			var aspect: float = maxf(width, depth) / maxf(minf(width, depth), 1.0)
			if aspect > MAX_ASPECT_RATIO:
				continue
			var surface_y := _water_surface_y(
				heights, cols, rows, basin, water_depth
			)
			if _basin_has_interior_high_ground(heights, cols, rows, basin, surface_y):
				continue
			var clipped := _clip_mask_to_submerged(
				heights, cols, rows, basin, surface_y
			)
			clipped = _largest_connected_component(
				clipped.mask,
				cols,
				rows,
				clipped.min_i,
				clipped.max_i,
				clipped.min_j,
				clipped.max_j
			)
			if clipped.cell_count < min_cells:
				continue
			var clip_min_x: float = float(clipped.min_i) * step
			var clip_max_x: float = float(clipped.max_i + 1) * step
			var clip_min_z: float = float(clipped.min_j) * step
			var clip_max_z: float = float(clipped.max_j + 1) * step
			if clipped.min_i == 0:
				clip_min_x = 0.0
			if clipped.max_i >= cols - 1:
				clip_max_x = map_w
			if clipped.min_j == 0:
				clip_min_z = 0.0
			if clipped.max_j >= rows - 1:
				clip_max_z = map_h
			var lake_basin := {
				"min_x": clip_min_x,
				"max_x": clip_max_x,
				"min_z": clip_min_z,
				"max_z": clip_max_z,
				"surface_y": surface_y,
				"cell_count": clipped.cell_count,
				"min_i": clipped.min_i,
				"max_i": clipped.max_i,
				"min_j": clipped.min_j,
				"max_j": clipped.max_j,
				"mask": clipped.mask,
				"cols": cols,
				"rows": rows,
				"step": step,
			}
			if build_polygon_from_basin(lake_basin).size() < 3:
				continue
			lakes.append(lake_basin)
			_mark_mask_visited(visited, clipped.mask, cols, rows)
	return lakes

static func _mark_mask_visited(
	visited: PackedByteArray,
	mask: PackedByteArray,
	cols: int,
	rows: int
) -> void:
	for idx in range(cols * rows):
		if mask[idx] != 0:
			visited[idx] = 1

static func detect_valley_polygon_lakes(
	heights: PackedFloat32Array,
	cols: int,
	rows: int,
	step: float,
	map_w: float,
	map_h: float,
	valley_polygons: Array,
	params: Dictionary = {}
) -> Array:
	if heights.is_empty() or cols < 3 or rows < 3 or valley_polygons.is_empty():
		return []
	var min_cells: int = params.get("min_cells", DEFAULT_MIN_CELLS)
	var water_depth: float = params.get("water_depth", DEFAULT_WATER_DEPTH)
	var lakes: Array = []
	for valley in valley_polygons:
		if typeof(valley) != TYPE_DICTIONARY:
			continue
		var points: PackedVector2Array = valley.get("points", PackedVector2Array())
		if points.size() < 3:
			continue
		var poly_min_x := INF
		var poly_max_x := -INF
		var poly_min_z := INF
		var poly_max_z := -INF
		for pt in points:
			poly_min_x = minf(poly_min_x, pt.x)
			poly_max_x = maxf(poly_max_x, pt.x)
			poly_min_z = minf(poly_min_z, pt.y)
			poly_max_z = maxf(poly_max_z, pt.y)
		var grid_min_i := clampi(int(floor(poly_min_x / step)), 0, cols - 1)
		var grid_max_i := clampi(int(ceil(poly_max_x / step)), 0, cols - 1)
		var grid_min_j := clampi(int(floor(poly_min_z / step)), 0, rows - 1)
		var grid_max_j := clampi(int(ceil(poly_max_z / step)), 0, rows - 1)
		var interior_min := INF
		for j in range(grid_min_j, grid_max_j + 1):
			for i in range(grid_min_i, grid_max_i + 1):
				var wx := float(i) * step
				var wz := float(j) * step
				if not Geometry2D.is_point_in_polygon(Vector2(wx, wz), points):
					continue
				interior_min = minf(interior_min, heights[j * cols + i])
		if interior_min == INF:
			continue
		var spill := INF
		for j in range(grid_min_j, grid_max_j + 1):
			for i in range(grid_min_i, grid_max_i + 1):
				var wx := float(i) * step
				var wz := float(j) * step
				if not Geometry2D.is_point_in_polygon(Vector2(wx, wz), points):
					continue
				for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var ni: int = i + dir.x
					var nj: int = j + dir.y
					if ni < 0 or nj < 0 or ni >= cols or nj >= rows:
						continue
					var nwx := float(ni) * step
					var nwz := float(nj) * step
					if Geometry2D.is_point_in_polygon(Vector2(nwx, nwz), points):
						continue
					spill = minf(spill, heights[nj * cols + ni])
		var surface_y: float
		if spill != INF and spill > interior_min + 0.5:
			surface_y = spill - 0.05
		else:
			surface_y = interior_min + water_depth
		surface_y = maxf(surface_y, interior_min + 0.05)
		var mask := PackedByteArray()
		mask.resize(cols * rows)
		var cell_count := 0
		var out_min_i: int = cols
		var out_max_i: int = 0
		var out_min_j: int = rows
		var out_max_j: int = 0
		for j in range(grid_min_j, grid_max_j + 1):
			for i in range(grid_min_i, grid_max_i + 1):
				var wx := float(i) * step
				var wz := float(j) * step
				if not Geometry2D.is_point_in_polygon(Vector2(wx, wz), points):
					continue
				var idx := j * cols + i
				if heights[idx] >= surface_y - SURFACE_CLIP_EPSILON:
					continue
				mask[idx] = 1
				cell_count += 1
				out_min_i = mini(out_min_i, i)
				out_max_i = maxi(out_max_i, i)
				out_min_j = mini(out_min_j, j)
				out_max_j = maxi(out_max_j, j)
		if cell_count < min_cells:
			continue
		var clip_min_x: float = float(out_min_i) * step
		var clip_max_x: float = float(out_max_i + 1) * step
		var clip_min_z: float = float(out_min_j) * step
		var clip_max_z: float = float(out_max_j + 1) * step
		if out_min_i == 0:
			clip_min_x = 0.0
		if out_max_i >= cols - 1:
			clip_max_x = map_w
		if out_min_j == 0:
			clip_min_z = 0.0
		if out_max_j >= rows - 1:
			clip_max_z = map_h
		var lake_basin := {
			"min_x": clip_min_x,
			"max_x": clip_max_x,
			"min_z": clip_min_z,
			"max_z": clip_max_z,
			"surface_y": surface_y,
			"cell_count": cell_count,
			"min_i": out_min_i,
			"max_i": out_max_i,
			"min_j": out_min_j,
			"max_j": out_max_j,
			"mask": mask,
			"cols": cols,
			"rows": rows,
			"step": step,
		}
		if build_polygon_from_basin(lake_basin).size() < 3:
			continue
		lakes.append(lake_basin)
	return lakes

static func build_polygon_from_basin(basin: Dictionary) -> PackedVector2Array:
	var step: float = basin.get("step", 20.0)
	var margin: float = step * POLYGON_MARGIN_FACTOR
	var base_poly := _mask_to_boundary_polygon(
		basin.mask,
		basin.cols,
		basin.rows,
		basin.min_i,
		basin.max_i,
		basin.min_j,
		basin.max_j,
		step
	)
	var smoothed := _chaikin_smooth(base_poly, SMOOTH_ITERATIONS)
	return _polygon_for_mesh(smoothed, margin)

static func polygon_area(polygon: PackedVector2Array) -> float:
	var n: int = polygon.size()
	if n < 3:
		return 0.0
	var area := 0.0
	for i in range(n):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5

static func _water_surface_y(
	heights: PackedFloat32Array,
	cols: int,
	rows: int,
	basin: Dictionary,
	water_depth: float
) -> float:
	var min_height: float = basin.min_height
	var spill := INF
	var mask: PackedByteArray = basin.mask
	for j in range(basin.min_j, basin.max_j + 1):
		for i in range(basin.min_i, basin.max_i + 1):
			var idx := j * cols + i
			if mask[idx] == 0:
				continue
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = i + dir.x
				var nj: int = j + dir.y
				if ni < 0 or nj < 0 or ni >= cols or nj >= rows:
					continue
				var nidx := nj * cols + ni
				if mask[nidx] == 0:
					spill = minf(spill, heights[nidx])
	var target: float = min_height + water_depth
	var touches_border: bool = (
		basin.min_i == 0 or basin.max_i >= cols - 1
		or basin.min_j == 0 or basin.max_j >= rows - 1
	)
	if touches_border:
		return target
	if spill != INF and spill > min_height + 1.0:
		target = minf(target, spill - 0.05)
	return maxf(target, min_height + 0.05)

static func _basin_has_interior_high_ground(
	heights: PackedFloat32Array,
	cols: int,
	rows: int,
	basin: Dictionary,
	surface_y: float
) -> bool:
	var min_i: int = basin.min_i
	var max_i: int = basin.max_i
	var min_j: int = basin.min_j
	var max_j: int = basin.max_j
	var mask: PackedByteArray = basin.mask
	var checked := PackedByteArray()
	checked.resize(cols * rows)
	for j in range(min_j, max_j + 1):
		for i in range(min_i, max_i + 1):
			var idx := j * cols + i
			if mask[idx] != 0:
				continue
			if heights[idx] <= surface_y + INTERIOR_HIGH_EPSILON:
				continue
			if checked[idx] != 0:
				continue
			var touches_edge := false
			var queue: Array = [Vector2i(i, j)]
			checked[idx] = 1
			while not queue.is_empty():
				var p: Vector2i = queue.pop_front()
				if p.x <= min_i or p.x >= max_i or p.y <= min_j or p.y >= max_j:
					touches_edge = true
				for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var ni: int = p.x + dir.x
					var nj: int = p.y + dir.y
					if ni < min_i or nj < min_j or ni > max_i or nj > max_j:
						continue
					var nidx := nj * cols + ni
					if mask[nidx] != 0:
						continue
					if heights[nidx] <= surface_y + INTERIOR_HIGH_EPSILON:
						continue
					if checked[nidx] != 0:
						continue
					checked[nidx] = 1
					queue.append(Vector2i(ni, nj))
			if not touches_edge:
				return true
	return false

static func _clip_mask_to_submerged(
	heights: PackedFloat32Array,
	cols: int,
	rows: int,
	basin: Dictionary,
	surface_y: float
) -> Dictionary:
	var old_mask: PackedByteArray = basin.mask
	var mask := PackedByteArray()
	mask.resize(cols * rows)
	var min_i: int = basin.max_i
	var max_i: int = basin.min_i
	var min_j: int = basin.max_j
	var max_j: int = basin.min_j
	var min_height := INF
	var cell_count := 0
	for j in range(basin.min_j, basin.max_j + 1):
		for i in range(basin.min_i, basin.max_i + 1):
			var idx := j * cols + i
			if old_mask[idx] == 0:
				continue
			if heights[idx] >= surface_y - SURFACE_CLIP_EPSILON:
				continue
			mask[idx] = 1
			cell_count += 1
			min_height = minf(min_height, heights[idx])
			min_i = mini(min_i, i)
			max_i = maxi(max_i, i)
			min_j = mini(min_j, j)
			max_j = maxi(max_j, j)
	if cell_count == 0:
		return {
			"min_i": basin.min_i,
			"max_i": basin.max_i,
			"min_j": basin.min_j,
			"max_j": basin.max_j,
			"min_height": basin.min_height,
			"cell_count": 0,
			"mask": mask,
		}
	return {
		"min_i": min_i,
		"max_i": max_i,
		"min_j": min_j,
		"max_j": max_j,
		"min_height": min_height,
		"cell_count": cell_count,
		"mask": mask,
	}

static func _largest_connected_component(
	mask: PackedByteArray,
	cols: int,
	rows: int,
	min_i: int,
	max_i: int,
	min_j: int,
	max_j: int
) -> Dictionary:
	var best_count := 0
	var best_cells: Array = []
	for j in range(min_j, max_j + 1):
		for i in range(min_i, max_i + 1):
			var start_idx := j * cols + i
			if mask[start_idx] == 0:
				continue
			var visited_local := PackedByteArray()
			visited_local.resize(cols * rows)
			var queue: Array = [Vector2i(i, j)]
			visited_local[start_idx] = 1
			var component: Array = []
			while not queue.is_empty():
				var p: Vector2i = queue.pop_front()
				component.append(p)
				for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var ni: int = p.x + dir.x
					var nj: int = p.y + dir.y
					if ni < min_i or nj < min_j or ni > max_i or nj > max_j:
						continue
					var nidx := nj * cols + ni
					if mask[nidx] == 0 or visited_local[nidx] != 0:
						continue
					visited_local[nidx] = 1
					queue.append(Vector2i(ni, nj))
			if component.size() > best_count:
				best_count = component.size()
				best_cells = component
	if best_cells.is_empty():
		return {
			"min_i": min_i,
			"max_i": max_i,
			"min_j": min_j,
			"max_j": max_j,
			"cell_count": 0,
			"mask": mask,
		}
	var out_mask := PackedByteArray()
	out_mask.resize(cols * rows)
	var out_min_i: int = max_i
	var out_max_i: int = min_i
	var out_min_j: int = max_j
	var out_max_j: int = min_j
	for p in best_cells:
		var pi: Vector2i = p
		out_mask[pi.y * cols + pi.x] = 1
		out_min_i = mini(out_min_i, pi.x)
		out_max_i = maxi(out_max_i, pi.x)
		out_min_j = mini(out_min_j, pi.y)
		out_max_j = maxi(out_max_j, pi.y)
	return {
		"min_i": out_min_i,
		"max_i": out_max_i,
		"min_j": out_min_j,
		"max_j": out_max_j,
		"cell_count": best_count,
		"mask": out_mask,
	}

static func _flood_fill_basin(
	heights: PackedFloat32Array,
	cols: int,
	rows: int,
	step: float,
	start_i: int,
	start_j: int,
	fill_epsilon: float,
	max_cells: int = 0
) -> Dictionary:
	var queue: Array = [Vector2i(start_i, start_j)]
	var fill_visited := PackedByteArray()
	fill_visited.resize(cols * rows)
	fill_visited[start_j * cols + start_i] = 1
	var mask := PackedByteArray()
	mask.resize(cols * rows)
	var min_i := start_i
	var max_i := start_i
	var min_j := start_j
	var max_j := start_j
	var min_height := heights[start_j * cols + start_i]
	var cell_count := 0
	var height_limit := min_height + fill_epsilon
	while not queue.is_empty():
		if max_cells > 0 and cell_count >= max_cells:
			break
		var p: Vector2i = queue.pop_front()
		var i := p.x
		var j := p.y
		var h: float = heights[j * cols + i]
		if h > height_limit:
			continue
		cell_count += 1
		mask[j * cols + i] = 1
		min_height = minf(min_height, h)
		height_limit = min_height + fill_epsilon
		min_i = mini(min_i, i)
		max_i = maxi(max_i, i)
		min_j = mini(min_j, j)
		max_j = maxi(max_j, j)
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni: int = i + dir.x
			var nj: int = j + dir.y
			if ni < 0 or nj < 0 or ni >= cols or nj >= rows:
				continue
			# Map-edge cells are zero-height; blocking them prevents one rim from merging distant basins.
			if ni == 0 or nj == 0 or ni == cols - 1 or nj == rows - 1:
				continue
			var nidx := nj * cols + ni
			if fill_visited[nidx] != 0:
				continue
			if heights[nidx] > height_limit:
				continue
			fill_visited[nidx] = 1
			queue.append(Vector2i(ni, nj))
	return {
		"min_i": min_i,
		"max_i": max_i,
		"min_j": min_j,
		"max_j": max_j,
		"min_height": min_height,
		"cell_count": cell_count,
		"mask": mask,
	}

static func _mask_cell_wet(mask: PackedByteArray, cols: int, rows: int, i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= cols or j >= rows:
		return false
	return mask[j * cols + i] != 0

static func _chain_edge(next_from: Dictionary, a: Vector2i, b: Vector2i) -> void:
	next_from[a] = b

static func _mask_to_boundary_polygon(
	mask: PackedByteArray,
	cols: int,
	rows: int,
	min_i: int,
	max_i: int,
	min_j: int,
	max_j: int,
	step: float
) -> PackedVector2Array:
	var next_from: Dictionary = {}
	for j in range(min_j, max_j + 1):
		for i in range(min_i, max_i + 1):
			if not _mask_cell_wet(mask, cols, rows, i, j):
				continue
			if not _mask_cell_wet(mask, cols, rows, i, j - 1):
				_chain_edge(next_from, Vector2i(i, j), Vector2i(i + 1, j))
			if not _mask_cell_wet(mask, cols, rows, i + 1, j):
				_chain_edge(next_from, Vector2i(i + 1, j), Vector2i(i + 1, j + 1))
			if not _mask_cell_wet(mask, cols, rows, i, j + 1):
				_chain_edge(next_from, Vector2i(i + 1, j + 1), Vector2i(i, j + 1))
			if not _mask_cell_wet(mask, cols, rows, i - 1, j):
				_chain_edge(next_from, Vector2i(i, j + 1), Vector2i(i, j))
	if next_from.is_empty():
		return PackedVector2Array()
	var start: Vector2i = next_from.keys()[0]
	var loop := PackedVector2Array()
	var current: Vector2i = start
	var guard := 0
	var max_guard: int = (max_i - min_i + max_j - min_j + 4) * 8 + 8
	while guard < max_guard:
		loop.append(Vector2(float(current.x) * step, float(current.y) * step))
		if not next_from.has(current):
			break
		var nxt: Vector2i = next_from[current]
		if nxt == start and loop.size() > 2:
			break
		current = nxt
		guard += 1
	return loop

static func _chaikin_smooth(polygon: PackedVector2Array, iterations: int) -> PackedVector2Array:
	if polygon.size() < 3 or iterations <= 0:
		return polygon
	var result: PackedVector2Array = polygon
	for _iter in range(iterations):
		var n: int = result.size()
		var next := PackedVector2Array()
		next.resize(n * 2)
		var out_idx := 0
		for i in range(n):
			var p0: Vector2 = result[i]
			var p1: Vector2 = result[(i + 1) % n]
			next[out_idx] = p0 * 0.75 + p1 * 0.25
			out_idx += 1
			next[out_idx] = p0 * 0.25 + p1 * 0.75
			out_idx += 1
		result = next
	return result

static func _expand_polygon(polygon: PackedVector2Array, margin: float) -> PackedVector2Array:
	var n: int = polygon.size()
	if n < 3 or margin <= 0.0:
		return polygon
	var result := PackedVector2Array()
	result.resize(n)
	for i in range(n):
		var prev: Vector2 = polygon[(i - 1 + n) % n]
		var curr: Vector2 = polygon[i]
		var next: Vector2 = polygon[(i + 1) % n]
		var e1: Vector2 = (curr - prev).normalized()
		var e2: Vector2 = (next - curr).normalized()
		var n1 := Vector2(e1.y, -e1.x)
		var n2 := Vector2(e2.y, -e2.x)
		var bisector: Vector2 = n1 + n2
		if bisector.length_squared() < 0.0001:
			bisector = n1
		else:
			bisector = bisector.normalized()
		var dot: float = n1.dot(bisector)
		var scale: float = margin / maxf(dot, 0.15)
		result[i] = curr + bisector * minf(scale, margin * 3.0)
	return result

static func _polygon_for_mesh(base: PackedVector2Array, margin: float) -> PackedVector2Array:
	if base.size() < 3:
		return base
	for m in [margin, margin * 0.25, 0.0]:
		var poly: PackedVector2Array = _expand_polygon(base, m) if m > 0.0 else base
		if Geometry2D.triangulate_polygon(poly).size() >= 3:
			return poly
	return base

static func _build_flat_mesh(polygon: PackedVector2Array, surface_y: float) -> ArrayMesh:
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	if indices.size() < 3:
		return null
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for idx in indices:
		var p: Vector2 = polygon[idx]
		vertices.append(Vector3(p.x, surface_y, p.y))
		uvs.append(Vector2(p.x / UV_REPEAT_UNITS, p.y / UV_REPEAT_UNITS))
		normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func make_lake_mesh(basin: Dictionary, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var polygon: PackedVector2Array = build_polygon_from_basin(basin)
	var mesh: ArrayMesh = _build_flat_mesh(polygon, basin.surface_y)
	if mesh == null:
		push_warning("WaterBuilder: failed to triangulate lake polygon; skipping")
		return mesh_instance
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance

static func make_water_material(water_texture: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if water_texture != null:
		mat.albedo_texture = water_texture
	mat.albedo_color = Color(0.85, 0.95, 1.0)
	mat.roughness = 0.35
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.render_priority = 1
	return mat

static func mesh_footprint_area(mesh: ArrayMesh) -> float:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0.0
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var area := 0.0
	for i in range(0, vertices.size(), 3):
		if i + 2 >= vertices.size():
			break
		var a: Vector3 = vertices[i]
		var b: Vector3 = vertices[i + 1]
		var c: Vector3 = vertices[i + 2]
		area += absf(
			(b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
		) * 0.5
	return area
