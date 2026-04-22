extends CharacterBody3D
## 3D unit: server sim + client visuals (billboard / fallback box).

signal unit_died(peer_id: int)

var owner_peer_id: int = 0
var owner_name: String = ""
var army_id: String = ""
var speed: float = 200.0 / 6.0
var attack: float = 10.0
var defense: float = 2.0
var attack_range: float = 50.0

## Server: move goal in map XZ (same as legacy Unit move_target Vector2).
var move_target: Vector2 = Vector2.ZERO
var is_moving := false
var attack_timer: float = 0.0

var sync_target_position: Vector3 = Vector3.ZERO
var has_move_goal: bool = false
var sync_target_hp: float = 100.0
var hp: float = 100.0
var is_dead := false

const HALF_HEIGHT := 11.0
const MAP_MARGIN := 200.0
const MAP_WIDTH_F := 1280.0
const MAP_HEIGHT_F := 720.0

const EQUIPMENT_FOLDER := "spearman"
const TEXTURE_FILE := "spearman.png"
const FACING_ROTATION_NEG_X := 0.0
const FACING_ROTATION_POS_X := PI

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _logged_height_invalid := false
var _last_facing_y: float = 0.0
## Sprite facing for the billboarded quad. The spearman PNG is authored facing
## left, so we flip the mesh's X scale only when this is true. Updated whenever
## the soldier has non-zero horizontal motion; persists while idle.
var _facing_right: bool = false
var _selected := false
var _texture_loaded := false
var _logged_position_invalid := false

func _ready():
	if multiplayer.is_server():
		return
	call_deferred("_build_visual_mesh")

func _ground_y() -> float:
	var w = get_parent()
	if w != null and w.has_method("get_ground_height_at"):
		return w.get_ground_height_at(global_position.x, global_position.z)
	return 0.0

func set_move_target(xz: Vector2):
	xz.x = clampf(xz.x, 0.0, MAP_WIDTH_F)
	xz.y = clampf(xz.y, 0.0, MAP_HEIGHT_F)
	move_target = xz
	is_moving = true
	if not multiplayer.is_server():
		var gy = _ground_y_at(xz.x, xz.y)
		sync_target_position = Vector3(xz.x, gy + HALF_HEIGHT, xz.y)
		has_move_goal = true

## Map XZ goal for anchor moves: server uses move_target while moving, else current position.
## Client uses sync_target while has_move_goal, else current position.
func get_goal_xz() -> Vector2:
	if multiplayer.is_server():
		if is_moving:
			return move_target
		return Vector2(global_position.x, global_position.z)
	if has_move_goal:
		return Vector2(sync_target_position.x, sync_target_position.z)
	return Vector2(global_position.x, global_position.z)

## Server: after spawn, goal equals position so anchor delta uses a defined baseline.
func initialize_goal_at_current():
	if not multiplayer.is_server():
		return
	move_target = Vector2(global_position.x, global_position.z)
	is_moving = false

func _ground_y_at(x: float, z: float) -> float:
	var w = get_parent()
	if w != null and w.has_method("get_ground_height_at"):
		return w.get_ground_height_at(x, z)
	return 0.0

func set_selected(val: bool):
	_selected = val
	_update_visual_tint()

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
		_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
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
		_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
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
	var img := Image.new()
	var err := img.load(path)
	if err == OK:
		return ImageTexture.create_from_image(img)
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
	if multiplayer.is_server():
		_server_process(delta)
	else:
		_client_physics(delta)

func _server_process(delta: float):
	if is_moving:
		var cur := Vector2(global_position.x, global_position.z)
		var dist := cur.distance_to(move_target)
		if dist <= 0.4:
			var gy := _ground_y_at(move_target.x, move_target.y)
			global_position = Vector3(move_target.x, gy + HALF_HEIGHT, move_target.y)
			velocity = Vector3.ZERO
			is_moving = false
		else:
			var dir_xz := (move_target - cur).normalized()
			velocity = Vector3(dir_xz.x * speed, 0.0, dir_xz.y * speed)
			move_and_slide()
			var gy2 := _ground_y_at(global_position.x, global_position.z)
			global_position.y = gy2 + HALF_HEIGHT

	if global_position.x < -MAP_MARGIN or global_position.x > MAP_WIDTH_F + MAP_MARGIN \
			or global_position.z < -MAP_MARGIN or global_position.z > MAP_HEIGHT_F + MAP_MARGIN:
		if not _logged_position_invalid:
			_logged_position_invalid = true
			print("TEST_SERVER_UNIT_POSITION_INVALID: %s out_of_bounds" % name)

	attack_timer -= delta
	if attack_timer <= 0.0:
		_try_attack()

func _client_physics(delta: float):
	if has_move_goal:
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

func _try_attack():
	var world = get_parent()
	if world == null:
		return
	var center := Vector2(global_position.x, global_position.z)
	var candidates: Array
	if world.has_method("get_units_in_radius"):
		candidates = world.get_units_in_radius(center, attack_range)
	else:
		candidates = []
	for child in candidates:
		if child == self:
			continue
		if not (child is CharacterBody3D):
			continue
		if child.get("is_dead"):
			continue
		if child.owner_peer_id == owner_peer_id:
			continue
		var oth := child as CharacterBody3D
		var dist := Vector2(global_position.x, global_position.z).distance_to(Vector2(oth.global_position.x, oth.global_position.z))
		if dist <= attack_range:
			var dmg = max(1.0, attack - float(child.get("defense")))
			GameState.last_combat_time = Time.get_ticks_msec() / 1000.0
			print("TEST_010_COMBAT: %s(%s) attacking %s(%s) dist=%.1f dmg=%.1f" % [owner_name, army_id, child.get("owner_name"), child.get("army_id"), dist, dmg])
			if child.has_method("take_damage"):
				child.take_damage(dmg, owner_peer_id)
			attack_timer = 1.0
			return

func take_damage(dmg: float, _attacker_id: int):
	if is_dead:
		return
	hp -= dmg
	if hp <= 0.0:
		is_dead = true
		print("Combat: soldier '%s' in %s died" % [name, army_id])
		unit_died.emit(owner_peer_id)
		var world = get_parent()
		if world and world.has_method("_notify_unit_death"):
			world._notify_unit_death(name)
		print("TEST_UNIT_CLEANUP: unit %s queued for removal" % name)
		get_tree().create_timer(0.5).timeout.connect(func(): queue_free())

func _update_facing():
	if _mesh == null:
		return
	var dir_xz := Vector2(velocity.x, velocity.z)
	if dir_xz.length() < 0.01 and has_move_goal:
		dir_xz = Vector2(
			sync_target_position.x - global_position.x,
			sync_target_position.z - global_position.z
		)
	# Update the persistent facing only when horizontal motion is meaningful;
	# idle soldiers keep whichever direction they last faced.
	var prev_facing := _facing_right
	if dir_xz.x > 0.01:
		_facing_right = true
	elif dir_xz.x < -0.01:
		_facing_right = false
	if _facing_right != prev_facing:
		print("TEST_FACING_FLIP: unit=%s owner=%s army=%s to=%s velocity=(%.1f,%.1f)" % [
			name, owner_name, army_id,
			"right" if _facing_right else "left",
			velocity.x, velocity.z
		])
	if _texture_loaded and _material != null and _material.billboard_mode == BaseMaterial3D.BILLBOARD_FIXED_Y:
		# The billboard shader overrides node transform every frame, so we can't
		# mirror the sprite via `_mesh.scale.x`. Flip UVs on the material
		# instead — this is respected because it changes which texels are
		# sampled, not how the quad is oriented.
		_mesh.rotation = Vector3.ZERO
		_mesh.scale.x = 1.0
		if _facing_right:
			_material.uv1_scale = Vector3(-1.0, 1.0, 1.0)
			_material.uv1_offset = Vector3(1.0, 0.0, 0.0)
		else:
			_material.uv1_scale = Vector3(1.0, 1.0, 1.0)
			_material.uv1_offset = Vector3(0.0, 0.0, 0.0)
		return
	# Non-textured fallback (box mesh): derive yaw from the same state so the
	# placeholder cube faces the same way the sprite would.
	_last_facing_y = FACING_ROTATION_POS_X if _facing_right else FACING_ROTATION_NEG_X
	_mesh.rotation.y = _last_facing_y
	_mesh.scale.x = 1.0

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
