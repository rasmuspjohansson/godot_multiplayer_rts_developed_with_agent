extends CharacterBody3D
## 3D unit for World3D (client-only). Position (x, 0, z); moves toward sync_target_position with physics.

var owner_peer_id: int = 0
var owner_name: String = ""
var army_id: String = ""
var speed: float = 200.0
var sync_target_position: Vector3 = Vector3.ZERO
var sync_target_hp: float = 100.0
var hp: float = 100.0
var is_dead := false

const HALF_HEIGHT := 11.0  # match collision box half-height for terrain sticking

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _logged_height_invalid := false

func _ready():
	# CharacterBody3D has no gravity_scale; we only set velocity in XZ and _stick_to_terrain sets y
	var box = BoxMesh.new()
	box.size = Vector3(14, 22, 14)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_material = StandardMaterial3D.new()
	_material.albedo_color = _get_player_color()
	_mesh.material_override = _material
	add_child(_mesh)

func _get_player_color() -> Color:
	if owner_peer_id in GameState.players:
		var ci = GameState.players[owner_peer_id].get("color_index", 0)
		if ci >= 0 and ci < GameState.PLAYER_COLORS.size():
			return GameState.PLAYER_COLORS[ci]
	return Color.GRAY

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
	if _material:
		_material.albedo_color = Color.DARK_RED if is_dead else _get_player_color()

func _stick_to_terrain():
	var world = get_parent()
	if world != null and world.has_method("get_ground_height_at"):
		var ground_y = world.get_ground_height_at(global_position.x, global_position.z)
		if global_position.y < ground_y and not _logged_height_invalid:
			_logged_height_invalid = true
			print("TEST_3D_UNIT_HEIGHT_INVALID: %s unit_was_below_ground" % name)
		global_position.y = ground_y + HALF_HEIGHT

func set_selected(val: bool):
	if _material:
		_material.albedo_color = Color.YELLOW if val else _get_player_color()
