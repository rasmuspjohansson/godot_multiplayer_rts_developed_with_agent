extends RefCounted
## Procedural decorative vegetation (trees, spruce, bushes) — visual only.

const TREE_TEXTURE_PATH := "res://images/background/tree.png"
const SPRUCE_TEXTURE_PATH := "res://images/background/tree_spruce.png"
const BUSH_TEXTURE_PATH := "res://images/background/bush.png"
const STONE_TEXTURE_PATH := "res://images/background/stone.png"

const TREE_WORLD_HEIGHT := 48.0
const SPRUCE_WORLD_HEIGHT := 52.0
const BUSH_WORLD_HEIGHT := 16.0
const STONE_WORLD_HEIGHT := 14.0

const MIN_SPACING := 35.0
const MIN_EXCLUSION := 100.0
const CLUSTER_RADIUS_MIN := 60.0
const CLUSTER_RADIUS_MAX := 120.0
const MAP_MARGIN := 40.0
const MAX_CENTER_ATTEMPTS := 80
const CLUSTER_SIZE_MIN := 4
const CLUSTER_SIZE_MAX := 7

static var _texture_cache: Dictionary = {}

func build(world: Node, map_cfg: Node) -> Array:
	var cfg: Dictionary = map_cfg.get_vegetation()
	var target_count: int = int(cfg.get("count", 30))
	var forest_clusters: int = int(cfg.get("forest_clusters", 5))
	if target_count <= 0:
		return []

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(map_cfg.name_))

	var exclusions := _collect_exclusions(map_cfg)
	var placed: Array = []
	var anchors: Array = []

	for _cluster_i in range(forest_clusters):
		if placed.size() >= target_count:
			break
		var center := _pick_center(world, map_cfg, rng, exclusions, placed)
		if center.x < 0.0:
			continue
		var cluster_count := rng.randi_range(CLUSTER_SIZE_MIN, CLUSTER_SIZE_MAX)
		for _j in range(cluster_count):
			if placed.size() >= target_count:
				break
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(CLUSTER_RADIUS_MIN, CLUSTER_RADIUS_MAX)
			var x := center.x + cos(angle) * radius
			var z := center.y + sin(angle) * radius
			var kind := _pick_forest_kind(rng)
			if _try_place(world, map_cfg, x, z, exclusions, placed):
				placed.append(Vector2(x, z))
				anchors.append(_make_anchor(world, x, z, kind, placed.size()))

	var single_attempts := 0
	while placed.size() < target_count and single_attempts < 800:
		single_attempts += 1
		var x := rng.randf_range(MAP_MARGIN, map_cfg.width - MAP_MARGIN)
		var z := rng.randf_range(MAP_MARGIN, map_cfg.height - MAP_MARGIN)
		var kind := _pick_kind(rng)
		if _try_place(world, map_cfg, x, z, exclusions, placed):
			placed.append(Vector2(x, z))
			anchors.append(_make_anchor(world, x, z, kind, placed.size()))

	return anchors

func _collect_exclusions(map_cfg: Node) -> Array:
	var out: Array = []
	for cp in map_cfg.capture_points:
		if typeof(cp) != TYPE_DICTIONARY:
			continue
		out.append(Vector2(float(cp.get("x", 0.0)), float(cp.get("y", 0.0))))
	for start in map_cfg.player_starts:
		if typeof(start) != TYPE_DICTIONARY:
			continue
		for ac in start.get("armies", []):
			if typeof(ac) != TYPE_DICTIONARY:
				continue
			out.append(Vector2(float(ac.get("x", 0.0)), float(ac.get("y", 0.0))))
	return out

func _pick_center(
	world: Node,
	map_cfg: Node,
	rng: RandomNumberGenerator,
	exclusions: Array,
	placed: Array,
) -> Vector2:
	for _attempt in range(MAX_CENTER_ATTEMPTS):
		var x := rng.randf_range(MAP_MARGIN, map_cfg.width - MAP_MARGIN)
		var z := rng.randf_range(MAP_MARGIN, map_cfg.height - MAP_MARGIN)
		if _is_valid_spot(world, map_cfg, x, z, exclusions, placed):
			return Vector2(x, z)
	return Vector2(-1.0, -1.0)

func _try_place(
	world: Node,
	map_cfg: Node,
	x: float,
	z: float,
	exclusions: Array,
	placed: Array,
) -> bool:
	if not _is_valid_spot(world, map_cfg, x, z, exclusions, placed):
		return false
	return true

func _is_valid_spot(
	world: Node,
	map_cfg: Node,
	x: float,
	z: float,
	exclusions: Array,
	placed: Array,
) -> bool:
	if x < MAP_MARGIN or z < MAP_MARGIN or x > map_cfg.width - MAP_MARGIN or z > map_cfg.height - MAP_MARGIN:
		return false
	if not world.has_method("is_walkable_at") or not world.is_walkable_at(x, z):
		return false
	var pt := Vector2(x, z)
	for e in exclusions:
		if pt.distance_to(e) < MIN_EXCLUSION:
			return false
	for p in placed:
		if pt.distance_to(p) < MIN_SPACING:
			return false
	return true

func _pick_forest_kind(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	if roll < 0.45:
		return "tree"
	if roll < 0.80:
		return "spruce"
	return "bush"

func _pick_kind(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	if roll < 0.30:
		return "tree"
	if roll < 0.55:
		return "spruce"
	if roll < 0.78:
		return "bush"
	return "stone"

func _make_anchor(world: Node, x: float, z: float, kind: String, index: int) -> Node3D:
	var tex := _load_texture(kind)
	var world_h := _world_height_for_kind(kind)
	var anchor := Node3D.new()
	anchor.name = "Veg_%s_%d" % [kind, index]
	var gy: float = 0.0
	if world.has_method("get_ground_height_at"):
		gy = world.get_ground_height_at(x, z)
	anchor.position = Vector3(x, gy, z)
	if tex == null:
		return anchor
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	var tex_h := float(tex.get_height())
	var pixel_size := world_h / maxf(tex_h, 1.0)
	sprite.pixel_size = pixel_size
	sprite.position.y = tex_h * pixel_size * 0.5
	anchor.add_child(sprite)
	return anchor

func _world_height_for_kind(kind: String) -> float:
	match kind:
		"spruce":
			return SPRUCE_WORLD_HEIGHT
		"bush":
			return BUSH_WORLD_HEIGHT
		"stone":
			return STONE_WORLD_HEIGHT
		_:
			return TREE_WORLD_HEIGHT

func _texture_path_for_kind(kind: String) -> String:
	match kind:
		"spruce":
			return SPRUCE_TEXTURE_PATH
		"bush":
			return BUSH_TEXTURE_PATH
		"stone":
			return STONE_TEXTURE_PATH
		_:
			return TREE_TEXTURE_PATH

func _load_texture(kind: String) -> Texture2D:
	var path := _texture_path_for_kind(kind)
	if _texture_cache.has(path):
		return _texture_cache[path]
	var img := Image.new()
	if img.load(path) == OK:
		var tex := ImageTexture.create_from_image(img)
		_texture_cache[path] = tex
		return tex
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is Texture2D:
			_texture_cache[path] = res
			return res as Texture2D
	return null
