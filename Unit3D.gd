extends CharacterBody3D
## 3D unit for World3D (client-only). Textured vertical quad; physics unchanged.

var owner_peer_id: int = 0
var owner_name: String = ""
var army_id: String = ""
var speed: float = 200.0 / 3.0
var sync_target_position: Vector3 = Vector3.ZERO
var sync_target_hp: float = 100.0
var hp: float = 100.0
var is_dead := false

const HALF_HEIGHT := 11.0  # match collision box half-height for terrain sticking
const EQUIPMENT_FOLDER := "spearman"
const TEXTURE_FILE := "spearman.png"
## QuadMesh vertical billboard: only two world-facing directions (left/right on X), no diagonal rotation.
const FACING_ROTATION_NEG_X := 0.0
const FACING_ROTATION_POS_X := PI

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _logged_height_invalid := false
var _last_facing_y: float = 0.0
var _selected := false
var _texture_loaded := false

func _ready():
	# Defer mesh build so CharacterBody3D / collision are fully in the scene tree
	# (avoids get_global_transform errors during the first add_child frame).
	call_deferred("_build_visual_mesh")

func _build_visual_mesh():
	_mesh = MeshInstance3D.new()
	var quad = QuadMesh.new()
	_mesh.mesh = quad
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tex := _load_spearman_texture()
	if tex != null:
		_texture_loaded = true
		_material.albedo_texture = tex
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var aspect := tw / maxf(th, 0.001)
		var h := 22.0
		var w := h * aspect
		quad.size = Vector2(w, h)
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.albedo_color = Color.WHITE
	else:
		print("TEST_3D_TEXTURE_LOAD_FAILED: %s path=%s" % [name, _get_texture_path()])
		var box := BoxMesh.new()
		box.size = Vector3(14, 22, 14)
		_mesh.mesh = box
		_material.albedo_color = _get_fallback_tint()
	_mesh.material_override = _material
	add_child(_mesh)

func _get_color_folder() -> String:
	var ci := 0
	if owner_peer_id in GameState.players:
		ci = GameState.players[owner_peer_id].get("color_index", 0)
	match ci:
		0:
			return "red"
		1:
			return "blue"
		_:
			return "red"

func _get_texture_path() -> String:
	return "res://images/%s/%s/%s" % [_get_color_folder(), EQUIPMENT_FOLDER, TEXTURE_FILE]

func _load_spearman_texture() -> Texture2D:
	var path := _get_texture_path()
	# Prefer Image.load + ImageTexture so PNG works even if import cache differs
	var img := Image.new()
	var err := img.load(path)
	if err == OK:
		return ImageTexture.create_from_image(img)
	# Fallback: imported CompressedTexture2D
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is Texture2D:
			return res as Texture2D
	return null

func _get_fallback_tint() -> Color:
	if owner_peer_id in GameState.players:
		var ci = GameState.players[owner_peer_id].get("color_index", 0)
		if ci >= 0 and ci < GameState.PLAYER_COLORS.size():
			return GameState.PLAYER_COLORS[ci]
	return Color.GRAY

func has_valid_spearman_texture() -> bool:
	return _texture_loaded and _material != null and _material.albedo_texture != null

func _physics_process(delta: float):
	if is_dead:
		return
	if sync_target_position != Vector3.ZERO:
		var to_target := Vector3(sync_target_position.x - global_position.x, 0.0, sync_target_position.z - global_position.z)
		var dist := sqrt(to_target.x * to_target.x + to_target.z * to_target.z)
		if dist > 1.0:
			var dir := to_target / dist
			velocity = dir * speed
		else:
			velocity = Vector3.ZERO
		move_and_slide()
		_stick_to_terrain()
		hp = lerpf(hp, sync_target_hp, clampf(delta * 8.0, 0.0, 1.0))
	else:
		velocity = Vector3.ZERO
		move_and_slide()
		_stick_to_terrain()
	_update_visual_tint()
	_update_facing()

func _update_facing():
	if _mesh == null:
		return
	var dir_xz := Vector2(velocity.x, velocity.z)
	if dir_xz.length() < 0.01 and sync_target_position != Vector3.ZERO:
		dir_xz = Vector2(
			sync_target_position.x - global_position.x,
			sync_target_position.z - global_position.z
		)
	if dir_xz.length() > 0.01:
		# Horizontal component only: two angles. Pure-Z movement keeps previous facing.
		if dir_xz.x > 0.01:
			_last_facing_y = FACING_ROTATION_POS_X
		elif dir_xz.x < -0.01:
			_last_facing_y = FACING_ROTATION_NEG_X
	_mesh.rotation.y = _last_facing_y

func _update_visual_tint():
	if _material == null:
		return
	if not _texture_loaded:
		_material.albedo_color = Color.DARK_RED if is_dead else _get_fallback_tint()
		return
	if is_dead:
		_material.albedo_color = Color(0.45, 0.25, 0.25)
	elif _selected:
		_material.albedo_color = Color(1.35, 1.35, 0.65)
	else:
		_material.albedo_color = Color.WHITE

func _stick_to_terrain():
	var world = get_parent()
	if world != null and world.has_method("get_ground_height_at"):
		var ground_y = world.get_ground_height_at(global_position.x, global_position.z)
		if global_position.y < ground_y and not _logged_height_invalid:
			_logged_height_invalid = true
			print("TEST_3D_UNIT_HEIGHT_INVALID: %s unit_was_below_ground" % name)
		global_position.y = ground_y + HALF_HEIGHT

func set_selected(val: bool):
	_selected = val
	_update_visual_tint()
