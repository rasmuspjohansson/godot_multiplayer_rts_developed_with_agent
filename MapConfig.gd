extends Node
## Parses map JSON once at startup and exposes the map description
## (size, terrain, capture points, per-slot player starting positions).
## Every map-dependent constant in World.gd / Army3D.gd resolves through here.
##
## Map file is selected via --map=S|L|XL (default S) → res://maps/map_{size}.json

const MAPS_DIR := "res://maps"
const DEFAULT_MAP_SIZE := "S"
const VALID_MAP_SIZES := ["S", "L", "XL"]

# Built-in fallback values — used only if map JSON is missing or unparseable so
# the game (and the test harness) never hangs on a bad config.
const _FALLBACK_WIDTH := 1280.0
const _FALLBACK_HEIGHT := 720.0

var map_size: String = DEFAULT_MAP_SIZE
var name_: String = "S"
var width: float = _FALLBACK_WIDTH
var height: float = _FALLBACK_HEIGHT
var terrain_type: String = "flat"
var terrain_features: Array = []
var capture_points: Array = []
var player_starts: Array = []
var neutral_dragon: Dictionary = {}
var neutral_dragons: Array = []
var lighting: Dictionary = {}
var walkability: Dictionary = {}
## Precomputed hill parameters used ONLY by World._build_terrain() at startup
## to generate the ground mesh and collision heightmap. Runtime height queries
## must go through World.get_ground_height_at() (physics raycast) so that
## future on-ground objects (rocks, walls, buildings) also count.
## Each hill entry: {cx, cz, sigma, peak}.
var _hills: Array = []
## Each ridge entry: {x1, z1, x2, z2, sigma, peak}.
var _ridges: Array = []
## Each spline_ridge entry: {points: PackedVector2Array, sigma, peak}.
var _spline_ridges: Array = []
## Each plateau entry: {cx, cz, radius, sigma, peak}.
var _plateaus: Array = []
## Each valley entry: {cx, cz, sigma, depth}.
var _valleys: Array = []
## Each valley_polygon entry: {points, depth, rim, sigma}.
var _valley_polygons: Array = []
## Each plateau_polygon entry: {points, peak, sigma}.
var _plateau_polygons: Array = []

const _SPLINE_RIDGE_SAMPLES := 20

func _ready() -> void:
	_load()

func _parse_map_size_from_args() -> String:
	var args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in range(args.size()):
		var a := str(args[i])
		if a.begins_with("--map="):
			return a.split("=")[1].strip_edges().to_upper()
		if a == "--map" and i + 1 < args.size():
			return str(args[i + 1]).strip_edges().to_upper()
	return DEFAULT_MAP_SIZE

func _map_json_path(size: String) -> String:
	return "%s/map_%s.json" % [MAPS_DIR, size]

func _load() -> void:
	map_size = _parse_map_size_from_args()
	if map_size not in VALID_MAP_SIZES:
		push_warning("MapConfig: unknown --map=%s; using %s" % [map_size, DEFAULT_MAP_SIZE])
		map_size = DEFAULT_MAP_SIZE
	var path := _map_json_path(map_size)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MapConfig: %s missing; using fallback defaults" % path)
		print("TEST_MAP_LOAD_FAIL: %s missing" % path)
		_apply_fallback_player_starts()
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MapConfig: %s did not parse to a dictionary" % path)
		print("TEST_MAP_LOAD_FAIL: %s not a dict" % path)
		_apply_fallback_player_starts()
		return
	name_ = str(parsed.get("name", map_size))
	var size_dict = parsed.get("size", {})
	if size_dict is Dictionary:
		width = float(size_dict.get("width", width))
		height = float(size_dict.get("height", height))
	var terrain = parsed.get("terrain", {})
	if terrain is Dictionary:
		terrain_type = str(terrain.get("type", terrain_type))
		terrain_features = terrain.get("features", [])
	capture_points = parsed.get("capture_points", [])
	neutral_dragons = parsed.get("neutral_dragons", [])
	neutral_dragon = parsed.get("neutral_dragon", {})
	if neutral_dragons.is_empty() and not neutral_dragon.is_empty():
		neutral_dragons = [neutral_dragon.duplicate()]
	player_starts = parsed.get("player_starts", [])
	if player_starts.is_empty():
		_apply_fallback_player_starts()
	var lighting_raw = parsed.get("lighting", {})
	if lighting_raw is Dictionary:
		lighting = lighting_raw
	else:
		lighting = {}
	var walkability_raw = parsed.get("walkability", {})
	if walkability_raw is Dictionary:
		walkability = walkability_raw
	else:
		walkability = {}
	_precompute_terrain_features()
	print("MapConfig: loaded '%s' from %s (%dx%d, terrain=%s, %d capture_points, %d player_starts, %d hills, %d ridges, %d spline_ridges, %d plateaus, %d plateau_polygons, %d valleys, %d valley_polygons, %d dragons)" % [
		name_, path, int(width), int(height), terrain_type, capture_points.size(), player_starts.size(), _hills.size(),
		_ridges.size(), _spline_ridges.size(), _plateaus.size(), _plateau_polygons.size(), _valleys.size(),
		_valley_polygons.size(), get_neutral_dragons().size()
	])

func get_neutral_dragons() -> Array:
	if not neutral_dragons.is_empty():
		return neutral_dragons
	if not neutral_dragon.is_empty():
		return [neutral_dragon]
	return []

func get_valley_polygons() -> Array:
	return _valley_polygons.duplicate(true)

func get_lighting() -> Dictionary:
	var color_raw = lighting.get("color", [1.0, 0.98, 0.95])
	var color_arr: Array = color_raw if color_raw is Array else [1.0, 0.98, 0.95]
	var shadow_raw = lighting.get("shadow_max_distance", null)
	var shadow_max_distance: float = -1.0
	if shadow_raw != null:
		shadow_max_distance = float(shadow_raw)
	return {
		"sun_azimuth_deg": float(lighting.get("sun_azimuth_deg", 275.0)),
		"sun_elevation_deg": float(lighting.get("sun_elevation_deg", 0.0)),
		"energy": float(lighting.get("energy", 0.12)),
		"color": [
			float(color_arr[0]) if color_arr.size() > 0 else 1.0,
			float(color_arr[1]) if color_arr.size() > 1 else 0.98,
			float(color_arr[2]) if color_arr.size() > 2 else 0.95,
		],
		"shadow_max_distance": shadow_max_distance,
	}

func get_walkability() -> Dictionary:
	return {
		"max_slope_deg": float(walkability.get("max_slope_deg", 45.0)),
	}

func max_armies_per_player() -> int:
	var max_count := 1
	for start in player_starts:
		if typeof(start) != TYPE_DICTIONARY:
			continue
		var armies: Array = start.get("armies", [])
		max_count = maxi(max_count, armies.size())
	return max_count

func _precompute_terrain_features() -> void:
	_hills.clear()
	_ridges.clear()
	_spline_ridges.clear()
	_plateaus.clear()
	_valleys.clear()
	_valley_polygons.clear()
	_plateau_polygons.clear()
	for f in terrain_features:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var ftype := str(f.get("type", ""))
		if ftype == "hill":
			var bw := float(f.get("base_width", 0.0))
			var peak := float(f.get("height", 0.0))
			if bw <= 0.0 or peak == 0.0:
				continue
			var sigma := bw / 6.0
			_hills.append({
				"cx": float(f.get("x", 0.0)),
				"cz": float(f.get("y", 0.0)),
				"sigma": sigma,
				"peak": peak,
			})
		elif ftype == "ridge":
			var width := float(f.get("width", 0.0))
			var rpeak := float(f.get("height", 0.0))
			if width <= 0.0 or rpeak == 0.0:
				continue
			_ridges.append({
				"x1": float(f.get("x1", 0.0)),
				"z1": float(f.get("y1", 0.0)),
				"x2": float(f.get("x2", 0.0)),
				"z2": float(f.get("y2", 0.0)),
				"sigma": width / 6.0,
				"peak": rpeak,
			})
		elif ftype == "spline_ridge":
			var points_raw = f.get("points", [])
			if typeof(points_raw) != TYPE_ARRAY or points_raw.size() < 2:
				continue
			var width := float(f.get("width", 0.0))
			var sr_peak := float(f.get("height", 0.0))
			if width <= 0.0 or sr_peak == 0.0:
				continue
			var points := PackedVector2Array()
			for pt in points_raw:
				if typeof(pt) != TYPE_DICTIONARY:
					continue
				points.append(Vector2(float(pt.get("x", 0.0)), float(pt.get("y", 0.0))))
			if points.size() < 2:
				continue
			_spline_ridges.append({
				"points": points,
				"sigma": width / 6.0,
				"peak": sr_peak,
			})
		elif ftype == "plateau":
			var radius := float(f.get("radius", 0.0))
			var falloff := float(f.get("falloff", 0.0))
			var p_peak := float(f.get("height", 0.0))
			if radius <= 0.0 or falloff <= 0.0 or p_peak == 0.0:
				continue
			_plateaus.append({
				"cx": float(f.get("x", 0.0)),
				"cz": float(f.get("y", 0.0)),
				"radius": radius,
				"sigma": falloff / 6.0,
				"peak": p_peak,
			})
		elif ftype == "valley":
			var vbw := float(f.get("base_width", 0.0))
			var depth := float(f.get("depth", 0.0))
			if vbw <= 0.0 or depth <= 0.0:
				continue
			_valleys.append({
				"cx": float(f.get("x", 0.0)),
				"cz": float(f.get("y", 0.0)),
				"sigma": vbw / 6.0,
				"depth": depth,
			})
		elif ftype == "valley_polygon":
			var points := _parse_feature_points(f)
			var vdepth := float(f.get("depth", 0.0))
			var vfalloff := float(f.get("falloff", 0.0))
			if points.size() < 3 or vdepth <= 0.0 or vfalloff <= 0.0:
				continue
			_valley_polygons.append({
				"points": points,
				"depth": vdepth,
				"rim": vfalloff,
				"sigma": vfalloff / 6.0,
			})
		elif ftype == "plateau_polygon":
			var pp_points := _parse_feature_points(f)
			var pp_height := float(f.get("height", 0.0))
			var pp_falloff := float(f.get("falloff", 0.0))
			if pp_points.size() < 3 or pp_height <= 0.0 or pp_falloff <= 0.0:
				continue
			_plateau_polygons.append({
				"points": pp_points,
				"peak": pp_height,
				"sigma": pp_falloff / 6.0,
			})

func _parse_feature_points(feature: Dictionary) -> PackedVector2Array:
	var points_raw = feature.get("points", [])
	if typeof(points_raw) != TYPE_ARRAY:
		return PackedVector2Array()
	var points := PackedVector2Array()
	for pt in points_raw:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		points.append(Vector2(float(pt.get("x", 0.0)), float(pt.get("y", 0.0))))
	return points

func _distance_to_polygon_edge(p: Vector2, polygon: PackedVector2Array) -> float:
	var min_dist_sq := INF
	var count: int = polygon.size()
	if count < 2:
		return INF
	for i in range(count):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % count]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
		min_dist_sq = minf(min_dist_sq, p.distance_squared_to(closest))
	return sqrt(min_dist_sq)

func _gaussian_falloff(dist_sq: float, sigma: float, peak: float) -> float:
	var s: float = sigma
	return peak * exp(-dist_sq / (2.0 * s * s))

func _radial_height_at(x: float, z: float, cx: float, cz: float, sigma: float, peak: float) -> float:
	var dx: float = x - cx
	var dz: float = z - cz
	return _gaussian_falloff(dx * dx + dz * dz, sigma, peak)

func _hill_height_at(x: float, z: float, hill: Dictionary) -> float:
	return _radial_height_at(x, z, hill.cx, hill.cz, hill.sigma, hill.peak)

func _valley_depth_at(x: float, z: float, valley: Dictionary) -> float:
	return _radial_height_at(x, z, valley.cx, valley.cz, valley.sigma, valley.depth)

func _polygon_valley_depth_at(x: float, z: float, valley: Dictionary) -> float:
	var p := Vector2(x, z)
	var polygon: PackedVector2Array = valley.points
	var edge_dist: float = _distance_to_polygon_edge(p, polygon)
	if Geometry2D.is_point_in_polygon(p, polygon):
		return valley.depth * smoothstep(0.0, valley.rim, edge_dist)
	return 0.0

func _plateau_height_at(x: float, z: float, plateau: Dictionary) -> float:
	var dx: float = x - plateau.cx
	var dz: float = z - plateau.cz
	var dist: float = sqrt(dx * dx + dz * dz)
	var rim_dist: float = maxf(0.0, dist - plateau.radius)
	return _gaussian_falloff(rim_dist * rim_dist, plateau.sigma, plateau.peak)

func _polygon_plateau_height_at(x: float, z: float, plateau: Dictionary) -> float:
	var p := Vector2(x, z)
	var polygon: PackedVector2Array = plateau.points
	if Geometry2D.is_point_in_polygon(p, polygon):
		return plateau.peak
	var edge_dist: float = _distance_to_polygon_edge(p, polygon)
	return plateau.peak * exp(-(edge_dist * edge_dist) / (2.0 * plateau.sigma * plateau.sigma))

func _ridge_height_at(x: float, z: float, ridge: Dictionary) -> float:
	var ax: float = ridge.x1
	var az: float = ridge.z1
	var bx: float = ridge.x2
	var bz: float = ridge.z2
	var abx: float = bx - ax
	var abz: float = bz - az
	var ab_len_sq: float = abx * abx + abz * abz
	if ab_len_sq < 0.001:
		return 0.0
	var apx: float = x - ax
	var apz: float = z - az
	var t: float = clampf((apx * abx + apz * abz) / ab_len_sq, 0.0, 1.0)
	var cx: float = ax + abx * t
	var cz: float = az + abz * t
	var dx: float = x - cx
	var dz: float = z - cz
	return _gaussian_falloff(dx * dx + dz * dz, ridge.sigma, ridge.peak)

func _catmull_rom_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func _spline_ridge_height_at(x: float, z: float, ridge: Dictionary) -> float:
	var points: PackedVector2Array = ridge.points
	if points.size() < 2:
		return 0.0
	var min_dist_sq := INF
	var count: int = points.size()
	for seg in range(count - 1):
		var p0: Vector2 = points[mini(maxi(seg - 1, 0), count - 1)]
		var p1: Vector2 = points[seg]
		var p2: Vector2 = points[seg + 1]
		var p3: Vector2 = points[mini(seg + 2, count - 1)]
		for step in range(_SPLINE_RIDGE_SAMPLES + 1):
			var t: float = float(step) / float(_SPLINE_RIDGE_SAMPLES)
			var sp: Vector2 = _catmull_rom_point(p0, p1, p2, p3, t)
			var dx: float = x - sp.x
			var dz: float = z - sp.y
			var dist_sq: float = dx * dx + dz * dz
			if dist_sq < min_dist_sq:
				min_dist_sq = dist_sq
	return _gaussian_falloff(min_dist_sq, ridge.sigma, ridge.peak)

## Analytical max-of-Gaussians ground elevation at (x, z). Used ONLY at terrain
## build time (World._build_terrain) to produce mesh vertices and the collision
## heightmap. Do NOT call this from gameplay code — use World.get_ground_height_at
## instead so later on-ground objects are accounted for.
func sample_height(x: float, z: float) -> float:
	var positive := 0.0
	for hill in _hills:
		positive = maxf(positive, _hill_height_at(x, z, hill))
	for ridge in _ridges:
		positive = maxf(positive, _ridge_height_at(x, z, ridge))
	for spline_ridge in _spline_ridges:
		positive = maxf(positive, _spline_ridge_height_at(x, z, spline_ridge))
	for plateau in _plateaus:
		positive = maxf(positive, _plateau_height_at(x, z, plateau))
	for plateau in _plateau_polygons:
		positive = maxf(positive, _polygon_plateau_height_at(x, z, plateau))
	var carve := 0.0
	for valley in _valleys:
		carve = maxf(carve, _valley_depth_at(x, z, valley))
	for valley in _valley_polygons:
		carve = maxf(carve, _polygon_valley_depth_at(x, z, valley))
	return maxf(5.0, positive - carve)

func _apply_fallback_player_starts() -> void:
	# Four corners matching today's hardcoded spawn layout.
	var w := width
	var h := height
	player_starts = [
		{"slot": 0, "corner": "NW", "armies": [
			{"x": w * 0.156, "y": h * 0.25, "direction": 0.0},
			{"x": w * 0.156, "y": h * 0.75, "direction": 0.0}
		]},
		{"slot": 1, "corner": "SE", "armies": [
			{"x": w - 230.0, "y": h * 0.75, "direction": PI},
			{"x": w - 230.0, "y": h * 0.25, "direction": PI}
		]},
		{"slot": 2, "corner": "NE", "armies": [
			{"x": w - 230.0, "y": h * 0.25, "direction": PI},
			{"x": w - 230.0, "y": h * 0.75, "direction": PI}
		]},
		{"slot": 3, "corner": "SW", "armies": [
			{"x": w * 0.156, "y": h * 0.75, "direction": 0.0},
			{"x": w * 0.156, "y": h * 0.25, "direction": 0.0}
		]}
	]

## Returns the player_starts entry for `slot`, or the slot-0 entry as a
## defensive fallback if `slot` is out of range.
func get_player_start(slot: int) -> Dictionary:
	if slot >= 0 and slot < player_starts.size():
		return player_starts[slot]
	if player_starts.size() > 0:
		return player_starts[0]
	return {"slot": 0, "corner": "NW", "armies": []}
