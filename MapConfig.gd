extends Node
## Parses res://map.json once at startup and exposes the map description
## (size, terrain, capture points, per-slot player starting positions).
## Every map-dependent constant in World.gd / Army3D.gd resolves through here.

const MAP_JSON_PATH := "res://map.json"

# Built-in fallback values — used only if map.json is missing or unparseable so
# the game (and the test harness) never hangs on a bad config.
const _FALLBACK_WIDTH := 1280.0
const _FALLBACK_HEIGHT := 720.0

var name_: String = "default"
var width: float = _FALLBACK_WIDTH
var height: float = _FALLBACK_HEIGHT
var terrain_type: String = "flat"
var terrain_features: Array = []
var capture_points: Array = []
var player_starts: Array = []
## Precomputed hill parameters used ONLY by World._build_terrain() at startup
## to generate the ground mesh and collision heightmap. Runtime height queries
## must go through World.get_ground_height_at() (physics raycast) so that
## future on-ground objects (rocks, walls, buildings) also count.
## Each entry: {cx, cz, sigma, peak}.
var _hills: Array = []

func _ready() -> void:
	_load()

func _load() -> void:
	var f := FileAccess.open(MAP_JSON_PATH, FileAccess.READ)
	if f == null:
		push_error("MapConfig: %s missing; using fallback defaults" % MAP_JSON_PATH)
		print("TEST_MAP_LOAD_FAIL: %s missing" % MAP_JSON_PATH)
		_apply_fallback_player_starts()
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MapConfig: %s did not parse to a dictionary" % MAP_JSON_PATH)
		print("TEST_MAP_LOAD_FAIL: %s not a dict" % MAP_JSON_PATH)
		_apply_fallback_player_starts()
		return
	name_ = str(parsed.get("name", name_))
	var size = parsed.get("size", {})
	if size is Dictionary:
		width = float(size.get("width", width))
		height = float(size.get("height", height))
	var terrain = parsed.get("terrain", {})
	if terrain is Dictionary:
		terrain_type = str(terrain.get("type", terrain_type))
		terrain_features = terrain.get("features", [])
	capture_points = parsed.get("capture_points", [])
	player_starts = parsed.get("player_starts", [])
	if player_starts.is_empty():
		_apply_fallback_player_starts()
	_precompute_hills()
	print("MapConfig: loaded '%s' (%dx%d, terrain=%s, %d capture_points, %d player_starts, %d hills)" % [
		name_, int(width), int(height), terrain_type, capture_points.size(), player_starts.size(), _hills.size()
	])

func _precompute_hills() -> void:
	_hills.clear()
	for f in terrain_features:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		if str(f.get("type", "")) != "hill":
			continue
		var bw := float(f.get("base_width", 0.0))
		var peak := float(f.get("height", 0.0))
		if bw <= 0.0 or peak == 0.0:
			continue
		# base_width is the full footprint diameter (~1% of peak at edge): sigma = base_width / 6.
		var sigma := bw / 6.0
		_hills.append({
			"cx": float(f.get("x", 0.0)),
			"cz": float(f.get("y", 0.0)),
			"sigma": sigma,
			"peak": peak,
		})

## Analytical max-of-Gaussians ground elevation at (x, z). Used ONLY at terrain
## build time (World._build_terrain) to produce mesh vertices and the collision
## heightmap. Do NOT call this from gameplay code — use World.get_ground_height_at
## instead so later on-ground objects are accounted for.
func sample_height(x: float, z: float) -> float:
	var h := 0.0
	for hill in _hills:
		var dx: float = x - hill.cx
		var dz: float = z - hill.cz
		var s: float = hill.sigma
		var v: float = hill.peak * exp(-(dx * dx + dz * dz) / (2.0 * s * s))
		if v > h:
			h = v
	return h

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
