extends CharacterBody3D
## 3D unit: server sim + client visuals (billboard / fallback box).

const SPRITESHEET_ANIM := preload("res://SpritesheetAnim.gd")
const UNIT_SPRITE_PATHS := preload("res://UnitSpritePaths.gd")
const UNIT_BEHAVIOUR := preload("res://UnitBehaviour.gd")
const _ArrowTrajectory := preload("res://ArrowTrajectory.gd")

signal unit_died(peer_id: int)

var owner_peer_id: int = 0
var owner_name: String = ""
var army_id: String = ""
var has_spear: bool = false
var has_horse: bool = false
var has_bow: bool = false
var unit_type: String = ""
var sprite_color: String = ""
var half_height: float = 11.0
var speed: float = 100.0 * 2.0 / 3.0 / 6.0
var attack: float = 10.0
var defense: float = 2.0
var attack_range: float = UNIT_SPRITE_PATHS.MELEE_ATTACK_RANGE

const BASE_HP := 100.0
const KNIGHT_HP := 200.0

static func speed_for_equipment(horse: bool) -> float:
	return (140.0 if horse else 100.0 * 2.0 / 3.0) / 6.0

func apply_equipment(horse: bool, spear: bool, bow: bool = false) -> void:
	has_horse = horse
	has_spear = spear
	has_bow = bow
	unit_type = ""
	speed = speed_for_equipment(horse)
	if bow:
		attack = 12.0
	elif spear:
		attack = 13.0
	else:
		attack = 10.0
	attack_range = UNIT_SPRITE_PATHS.default_attack_range_for_equipment(horse, spear, bow)
	attack_cooldown = 1.0
	fight_anim_speed = SPRITE_ANIM_SPEED
	var max_hp := KNIGHT_HP if horse else BASE_HP
	hp = max_hp
	sync_target_hp = max_hp

func apply_dragon(color: String = "red") -> void:
	has_horse = false
	has_spear = false
	has_bow = false
	unit_type = "dragon"
	sprite_color = color
	half_height = UNIT_SPRITE_PATHS.DRAGON_HALF_HEIGHT
	speed = 90.0 / 6.0
	attack = 28.0
	defense = 10.0
	attack_range = UNIT_SPRITE_PATHS.DRAGON_ATTACK_RANGE
	hp = 300.0
	sync_target_hp = 300.0
	fight_anim_speed = UNIT_SPRITE_PATHS.DRAGON_FIGHT_ANIM_SPEED
	attack_cooldown = 1.0

func get_unit_type() -> String:
	if unit_type != "":
		return unit_type
	return UNIT_SPRITE_PATHS.unit_type_for_equipment(has_horse, has_spear, has_bow)

func is_dragon() -> bool:
	return get_unit_type() == "dragon"

func world_sprite_height() -> float:
	if is_dragon():
		return UNIT_SPRITE_PATHS.DRAGON_SPRITE_WORLD_HEIGHT
	if has_horse:
		return HORSE_SPRITE_WORLD_HEIGHT
	return SPRITE_WORLD_HEIGHT

## Server: move goal in map XZ (same as legacy Unit move_target Vector2).
var move_target: Vector2 = Vector2.ZERO
var _path_waypoints: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var is_moving := false
var attack_timer: float = 0.0
var attack_cooldown: float = 1.0
var in_combat: bool = false
var sync_in_combat: bool = false
var fight_anim_speed: float = SPRITE_ANIM_SPEED

var sync_target_position: Vector3 = Vector3.ZERO
var has_move_goal: bool = false
var sync_target_hp: float = 100.0
var hp: float = 100.0
var is_dead := false
## Server combat: preferred target node name from army ATTACK order.
var commanded_target_name: String = ""
## Mirrors parent army stance (Army3D.Stance).
var army_stance: int = 1

const HALF_HEIGHT := 11.0
const GOAL_ARRIVAL_DIST := 0.2
const GOAL_RELEASE_DIST := 1.5
const GOAL_CHANGE_DIST := 0.5
const GOAL_FACING_MIN_DIST := 1.0
const MAP_MARGIN := 200.0

func _clamp_map_xz(v: Vector2) -> Vector2:
	return Vector2(clampf(v.x, 0.0, MapConfig.width), clampf(v.y, 0.0, MapConfig.height))

const EQUIPMENT_FOLDER := "spearman"
const TEXTURE_FILE := "spearman.png"
const FACING_ROTATION_NEG_X := 0.0
const FACING_ROTATION_POS_X := PI
const SPRITE_WORLD_HEIGHT := 22.0
const HORSE_SPRITE_WORLD_HEIGHT := 28.0
const SPRITE_FRAME_PX := 256.0
const SPRITE_PIXEL_SIZE := SPRITE_WORLD_HEIGHT / SPRITE_FRAME_PX
const SPRITE_ANIM_SPEED := 2.0 / 9.0
## Match World camera span (200–1200) with headroom so zoomed-out units stay audible.
const SFX_MAX_DISTANCE := 2400.0
const SFX_UNIT_SIZE := 100.0

enum AnimState { IDLE, WALKING, FIGHT, DIE }

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _sprite: Sprite3D
var _logged_height_invalid := false
var _last_facing_y: float = 0.0
## Sprite facing for the billboarded quad. The spearman PNG is authored facing
## left, so we flip the mesh's X scale only when this is true. Updated whenever
## the soldier has non-zero horizontal motion; persists while idle.
var _facing_right: bool = false
var _selected := false
var _texture_loaded := false
var _logged_position_invalid := false
var _uses_spritesheets := false
var _anim_walking = null
var _anim_fight = null
var _anim_idle = null
var _anim_die = null
var _static_spearman_tex: Texture2D = null
var _sound_walking: AudioStream = null
var _sound_fight: AudioStream = null
var _sound_idle: AudioStream = null
var _sound_die: AudioStream = null
var _audio_player: AudioStreamPlayer3D = null
var _current_sound_state: AnimState = AnimState.IDLE
var _current_art_faces_right := false
var _anim_state: AnimState = AnimState.IDLE
var _dying := false
var _death_free_scheduled := false
## Feet row from idle/walk frame 0; fight/die use clip-specific anchors so poses don't lift.
var _anchor_feet_y_px: int = 0
var _anchor_fight_feet_y_px: int = 0
var _anchor_die_feet_y_px: int = 0
## Per-clip display scale from sheet max character height vs walk reference (constant for whole clip).
var _scale_walk: float = 1.0
var _scale_fight: float = 1.0
var _scale_idle: float = 1.0
var _scale_die: float = 1.0
const CLIP_DISPLAY_SCALE_MIN := 0.25
const CLIP_DISPLAY_SCALE_MAX := 4.0
var _goal_settled := false
var _settled_goal: Vector3 = Vector3.ZERO

func _ready():
	if multiplayer.is_server():
		return
	call_deferred("_build_visual_mesh")

func refresh_visuals() -> void:
	if multiplayer.is_server():
		return
	call_deferred("_build_visual_mesh")

func _ground_y() -> float:
	var w = get_parent()
	if w != null and w.has_method("get_ground_height_at"):
		return w.get_ground_height_at(global_position.x, global_position.z)
	return 0.0

func set_move_target(xz: Vector2) -> void:
	xz = _clamp_map_xz(xz)
	if multiplayer.is_server():
		_assign_path_to_goal(Vector2(global_position.x, global_position.z), xz)

func _assign_path_to_goal(from_xz: Vector2, to_xz: Vector2) -> bool:
	var w = get_parent()
	if w != null and w.has_method("prepare_unit_move_target"):
		var path: PackedVector2Array = w.prepare_unit_move_target(from_xz, to_xz)
		if path.is_empty():
			return false
		_set_path_waypoints(path)
		return true
	_set_path_waypoints(PackedVector2Array([to_xz]))
	return true

func _set_path_waypoints(path: PackedVector2Array) -> void:
	if path.is_empty():
		return
	_path_waypoints = path
	_path_index = 0
	move_target = path[path.size() - 1]
	is_moving = true
	_goal_settled = false
	_settled_goal = Vector3.ZERO
	if not multiplayer.is_server():
		var gy = _ground_y_at(move_target.x, move_target.y)
		sync_target_position = Vector3(move_target.x, gy + half_height, move_target.y)
		has_move_goal = true

func _current_steer_target_xz() -> Vector2:
	if _path_waypoints.is_empty():
		return move_target
	return _path_waypoints[mini(_path_index, _path_waypoints.size() - 1)]

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
	_path_waypoints.clear()
	_path_index = 0
	is_moving = false

func _ground_y_at(x: float, z: float) -> float:
	var w = get_parent()
	if w != null and w.has_method("get_ground_height_at"):
		return w.get_ground_height_at(x, z)
	return 0.0

func set_selected(val: bool):
	_selected = val
	_update_visual_tint()

func set_combat_directives(cmd_target: String, stance: int) -> void:
	commanded_target_name = cmd_target
	army_stance = stance

func _clear_visual_mesh() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		_sprite.position = Vector3.ZERO
		_sprite.queue_free()
		_sprite = null
	if _mesh != null and is_instance_valid(_mesh):
		_mesh.queue_free()
		_mesh = null
	_material = null
	_uses_spritesheets = false
	_texture_loaded = false
	_anim_walking = null
	_anim_fight = null
	_anim_idle = null
	_anim_die = null
	_static_spearman_tex = null
	_sound_walking = null
	_sound_fight = null
	_sound_idle = null
	_sound_die = null
	if _audio_player != null and is_instance_valid(_audio_player):
		_audio_player.stop()
		_audio_player.queue_free()
	_audio_player = null
	_current_sound_state = AnimState.IDLE
	_current_art_faces_right = false
	_anim_state = AnimState.IDLE
	_anchor_feet_y_px = 0
	_anchor_fight_feet_y_px = 0
	_anchor_die_feet_y_px = 0
	_scale_walk = 1.0
	_scale_fight = 1.0
	_scale_idle = 1.0
	_scale_die = 1.0
	_goal_settled = false
	_settled_goal = Vector3.ZERO
	set_process(false)

func _build_visual_mesh():
	_clear_visual_mesh()
	if _try_load_spritesheets():
		_texture_loaded = true
		_uses_spritesheets = true
		_compute_clip_display_scales()
		var px_size := _scaled_sprite_pixel_size(AnimState.IDLE)
		_sprite = Sprite3D.new()
		_sprite.texture = _idle_frame_texture()
		_current_art_faces_right = _unit_art_faces_right()
		_sprite.pixel_size = px_size
		_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		add_child(_sprite)
		var idle_feet := int(SPRITE_FRAME_PX) - 1
		if _anim_idle != null:
			idle_feet = _anim_idle.get_feet_y_px(0)
		elif _anim_walking != null:
			idle_feet = _anim_walking.get_feet_y_px(0)
		_anchor_feet_y_px = idle_feet
		if _anim_fight != null:
			_anchor_fight_feet_y_px = _anim_fight.get_feet_y_px(0)
		else:
			_anchor_fight_feet_y_px = idle_feet
		if _anim_die != null:
			_anchor_die_feet_y_px = _anim_die.get_feet_y_px(0)
		else:
			_anchor_die_feet_y_px = idle_feet
		_update_sprite_feet_offset(idle_feet, px_size)
		_audio_player = AudioStreamPlayer3D.new()
		_audio_player.name = "SpriteAudio"
		_audio_player.unit_size = SFX_UNIT_SIZE
		_audio_player.max_distance = SFX_MAX_DISTANCE
		_audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_audio_player.bus = AudioSettings.get_sfx_bus_name()
		if AudioServer.get_bus_index(_audio_player.bus) < 0:
			push_warning("Unit3D: SFX bus missing for %s; using Master" % name)
			_audio_player.bus = &"Master"
		add_child(_audio_player)
		_play_anim_sound(_anim_state)
		set_process(true)
		return

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
		var h := SPRITE_WORLD_HEIGHT
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

func _sprite_pixel_size() -> float:
	return world_sprite_height() / SPRITE_FRAME_PX

func _clip_display_scale(anim, ref_h: int) -> float:
	if anim == null or ref_h <= 0:
		return 1.0
	var sheet_max_h: int = anim.get_max_character_height_px()
	if sheet_max_h <= 0:
		return 1.0
	return clampf(float(ref_h) / float(sheet_max_h), CLIP_DISPLAY_SCALE_MIN, CLIP_DISPLAY_SCALE_MAX)

func _reference_character_height_px() -> int:
	if _anim_walking != null:
		return _anim_walking.get_max_character_height_px()
	if _anim_idle != null:
		return _anim_idle.get_max_character_height_px()
	return int(SPRITE_FRAME_PX)

func _compute_clip_display_scales() -> void:
	var ref_h := _reference_character_height_px()
	_scale_walk = _clip_display_scale(_anim_walking, ref_h)
	_scale_fight = _clip_display_scale(_anim_fight, ref_h)
	_scale_idle = _clip_display_scale(_anim_idle, ref_h)
	_scale_die = _clip_display_scale(_anim_die, ref_h)

func _scale_for_state(state: AnimState) -> float:
	match state:
		AnimState.WALKING:
			return _scale_walk
		AnimState.FIGHT:
			return _scale_fight
		AnimState.IDLE:
			return _scale_idle
		AnimState.DIE:
			return _scale_die
	return 1.0

func _scaled_sprite_pixel_size(state: AnimState) -> float:
	return _sprite_pixel_size() * _scale_for_state(state)

func _update_sprite_feet_offset(feet_y_px: int, pixel_size: float) -> void:
	if _sprite == null:
		return
	var frame_center_px := SPRITE_FRAME_PX * 0.5
	# Image Y grows downward; Sprite3D +Y is up. Align opaque feet row to -HALF_HEIGHT.
	_sprite.position.y = -half_height - (frame_center_px - float(feet_y_px)) * pixel_size

func _idle_frame_texture() -> Texture2D:
	if _anim_idle != null:
		_anim_idle.reset()
		return _anim_idle.get_frame_texture()
	if _anim_walking != null:
		_anim_walking.reset()
		return _anim_walking.get_frame_texture()
	return _static_spearman_tex

func _static_frame_texture() -> Texture2D:
	return _static_spearman_tex

func _unit_art_faces_right() -> bool:
	return UNIT_SPRITE_PATHS.art_faces_right_for_unit(get_unit_type())

func _try_load_spritesheets() -> bool:
	var color := _get_color_folder()
	var u_type := get_unit_type()
	_static_spearman_tex = UNIT_SPRITE_PATHS.load_static_spearman_texture(color)

	var move_path := UNIT_SPRITE_PATHS.ai_sprite_folder(color, u_type, "move")
	var attack_path := UNIT_SPRITE_PATHS.ai_sprite_folder(color, u_type, "attack")
	var idle_path := UNIT_SPRITE_PATHS.ai_sprite_folder(color, u_type, "idle")
	var die_path := UNIT_SPRITE_PATHS.ai_sprite_folder(color, u_type, "die")

	if UNIT_SPRITE_PATHS.folder_has_spritesheet(move_path):
		_anim_walking = SPRITESHEET_ANIM.try_load_folder(move_path)
		_sound_walking = UNIT_SPRITE_PATHS.load_sprite_sound(move_path)
	if UNIT_SPRITE_PATHS.folder_has_spritesheet(attack_path):
		_anim_fight = SPRITESHEET_ANIM.try_load_folder(attack_path)
		_sound_fight = UNIT_SPRITE_PATHS.load_sprite_sound(attack_path)
	if UNIT_SPRITE_PATHS.folder_has_spritesheet(idle_path):
		_anim_idle = SPRITESHEET_ANIM.try_load_folder(idle_path)
		_sound_idle = UNIT_SPRITE_PATHS.load_sprite_sound(idle_path)
	if UNIT_SPRITE_PATHS.folder_has_spritesheet(die_path):
		_anim_die = SPRITESHEET_ANIM.try_load_folder(die_path)
		_sound_die = UNIT_SPRITE_PATHS.load_sprite_sound(die_path)

	return _anim_walking != null or _anim_fight != null or _anim_idle != null or _anim_die != null

func _get_color_folder() -> String:
	if sprite_color != "":
		return sprite_color
	return UNIT_SPRITE_PATHS.color_folder_for_peer(owner_peer_id)

func _get_texture_path() -> String:
	var color := _get_color_folder()
	var path := UNIT_SPRITE_PATHS.static_spearman_image_path(color)
	if FileAccess.file_exists(path):
		return path
	return UNIT_SPRITE_PATHS.static_spearman_image_path("blue")

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
	if is_dragon():
		return Color(0.85, 0.25, 0.2)
	if owner_peer_id in GameState.players:
		var ci = GameState.players[owner_peer_id].get("color_index", 0)
		if ci >= 0 and ci < GameState.PLAYER_COLORS.size():
			return GameState.PLAYER_COLORS[ci]
	return Color.GRAY

func has_valid_spearman_texture() -> bool:
	if _uses_spritesheets:
		return _texture_loaded and _sprite != null and _sprite.texture != null
	return _texture_loaded and _material != null and _material.albedo_texture != null

func is_in_death_sequence() -> bool:
	return is_dead or _dying

func begin_death() -> void:
	if _death_free_scheduled:
		return
	is_dead = true
	velocity = Vector3.ZERO
	has_move_goal = false
	_apply_ground_height()
	if _audio_player != null:
		_audio_player.stop()
	if _uses_spritesheets and _anim_die != null:
		_dying = true
		_anim_state = AnimState.DIE
		_anim_die.reset()
		_play_anim_sound(AnimState.DIE)
		_death_free_scheduled = true
		var dur := maxf(_anim_die.get_duration(SPRITE_ANIM_SPEED), 0.5)
		get_tree().create_timer(dur).timeout.connect(func():
			if is_instance_valid(self):
				queue_free()
		)
	else:
		_death_free_scheduled = true
		get_tree().create_timer(0.5).timeout.connect(func():
			if is_instance_valid(self):
				queue_free()
		)

func _process(delta: float) -> void:
	if multiplayer.is_server() or not _uses_spritesheets or _sprite == null:
		return
	var state := _pick_anim_state()
	_apply_anim_state(state, delta)
	_update_facing()

func _distance_to_final_goal_xz() -> float:
	return Vector2(
		global_position.x - move_target.x,
		global_position.z - move_target.y
	).length()

func _distance_to_steer_target_xz() -> float:
	var steer := _current_steer_target_xz()
	return Vector2(
		global_position.x - steer.x,
		global_position.z - steer.y
	).length()

func _distance_to_sync_goal_xz() -> float:
	return _distance_to_final_goal_xz()

func _refresh_move_goal_state() -> void:
	var dist := _distance_to_final_goal_xz()
	if _goal_settled:
		if Vector2(move_target.x, move_target.y).distance_to(Vector2(_settled_goal.x, _settled_goal.z)) > GOAL_CHANGE_DIST:
			_goal_settled = false
			_settled_goal = Vector3.ZERO
		elif dist > GOAL_RELEASE_DIST:
			_goal_settled = false
			_settled_goal = Vector3.ZERO
	elif dist <= GOAL_ARRIVAL_DIST:
		_goal_settled = true
		var gy := _ground_y_at(move_target.x, move_target.y)
		_settled_goal = Vector3(move_target.x, gy + half_height, move_target.y)
		velocity = Vector3.ZERO
		is_moving = false
		_path_waypoints.clear()
		_path_index = 0
	has_move_goal = not _goal_settled

func _sync_path_index_to_steer_hint(steer_xz: Vector2) -> void:
	if _path_waypoints.is_empty():
		return
	var best_i := _path_index
	var best_d := INF
	for i in range(_path_index, _path_waypoints.size()):
		var d: float = steer_xz.distance_to(_path_waypoints[i])
		if d < best_d:
			best_d = d
			best_i = i
	if best_i > _path_index:
		_path_index = best_i

func apply_network_sync(
	here: Vector3,
	there: Vector3,
	_hp_val: float,
	in_combat_val: bool,
	correction_threshold: float,
	final_goal_xz: Vector2 = Vector2(-1.0, -1.0),
) -> void:
	if global_position.distance_to(here) > correction_threshold:
		global_position = here
	var final_xz := final_goal_xz
	if final_xz.x < 0.0:
		final_xz = Vector2(there.x, there.z)
	var goal_changed := final_xz.distance_to(move_target) > GOAL_CHANGE_DIST
	if goal_changed:
		_goal_settled = false
		_settled_goal = Vector3.ZERO
		_assign_path_to_goal(Vector2(global_position.x, global_position.z), final_xz)
	else:
		_sync_path_index_to_steer_hint(Vector2(there.x, there.z))
	var gy := _ground_y_at(final_xz.x, final_xz.y)
	sync_target_position = Vector3(final_xz.x, gy + half_height, final_xz.y)
	sync_target_hp = _hp_val
	hp = _hp_val
	sync_in_combat = in_combat_val
	_refresh_move_goal_state()

func _pick_anim_state() -> AnimState:
	if _dying or is_dead:
		return AnimState.DIE
	if sync_in_combat:
		return AnimState.FIGHT
	if _is_moving():
		return AnimState.WALKING
	return AnimState.IDLE

func _fight_advance(delta: float):
	if _anim_fight == null:
		return null
	return _anim_fight.advance(delta, true, fight_anim_speed)

func _is_moving() -> bool:
	if _goal_settled or not has_move_goal:
		return false
	return _distance_to_steer_target_xz() > GOAL_ARRIVAL_DIST or _distance_to_final_goal_xz() > GOAL_ARRIVAL_DIST

func _apply_anim_state(state: AnimState, delta: float) -> void:
	if state != _anim_state:
		_anim_state = state
		_play_anim_sound(state)
		match state:
			AnimState.WALKING:
				if _anim_walking != null:
					_anim_walking.reset()
			AnimState.FIGHT:
				if _anim_fight != null:
					_anim_fight.reset()
			AnimState.IDLE:
				# Temporary: hold frame 0 only. Loop advance() + idle SFX when clips are better.
				if _anim_idle != null:
					_anim_idle.reset()
				elif _anim_walking != null:
					_anim_walking.reset()
			AnimState.DIE:
				if _anim_die != null:
					_anim_die.reset()
	var tex: Texture2D = null
	var art_faces_right := _unit_art_faces_right()
	var faces_right := false
	var feet_y_px := int(SPRITE_FRAME_PX) - 1
	match state:
		AnimState.DIE:
			if _anim_die != null:
				tex = _anim_die.advance(delta, false, SPRITE_ANIM_SPEED)
				feet_y_px = _anchor_die_feet_y_px if _anchor_die_feet_y_px > 0 else int(SPRITE_FRAME_PX) - 1
				faces_right = art_faces_right
			else:
				tex = _static_frame_texture()
				faces_right = false
		AnimState.FIGHT:
			if _anim_fight != null:
				tex = _fight_advance(delta)
				feet_y_px = _anchor_fight_feet_y_px if _anchor_fight_feet_y_px > 0 else _anim_fight.get_feet_y_px(0)
				faces_right = art_faces_right
			else:
				tex = _static_frame_texture()
				faces_right = false
		AnimState.WALKING:
			if _anim_walking != null:
				tex = _anim_walking.advance(delta, true, SPRITE_ANIM_SPEED)
				feet_y_px = _anim_walking.get_feet_y_px()
				faces_right = art_faces_right
			else:
				tex = _static_frame_texture()
				faces_right = false
		AnimState.IDLE:
			if _anim_idle != null:
				tex = _anim_idle.get_frame_texture()
				feet_y_px = _anim_idle.get_feet_y_px(0)
				faces_right = art_faces_right
			else:
				tex = _static_frame_texture()
				faces_right = false
	if tex != null:
		var px_size := _scaled_sprite_pixel_size(state)
		_sprite.texture = tex
		_sprite.pixel_size = px_size
		_update_sprite_feet_offset(feet_y_px, px_size)
		_current_art_faces_right = faces_right

func _stream_for_anim_state(state: AnimState) -> AudioStream:
	match state:
		AnimState.WALKING:
			return _sound_walking
		AnimState.FIGHT:
			return _sound_fight
		AnimState.IDLE:
			# Temporary: no idle SFX until we have a dedicated ambient idle sound.
			return null
		AnimState.DIE:
			return _sound_die
	return null

func _should_loop_anim_sound(state: AnimState) -> bool:
	# Idle omitted until we have a better idle loop sound (see _stream_for_anim_state).
	return state == AnimState.WALKING or state == AnimState.FIGHT

func _play_anim_sound(state: AnimState) -> void:
	if _audio_player == null:
		return
	if state == _current_sound_state and _audio_player.playing:
		return
	_current_sound_state = state
	var base_stream := _stream_for_anim_state(state)
	if base_stream == null:
		_audio_player.stop()
		_audio_player.stream = null
		return
	var stream := base_stream.duplicate()
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = _should_loop_anim_sound(state)
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = _should_loop_anim_sound(state)
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if _should_loop_anim_sound(state) else AudioStreamWAV.LOOP_DISABLED
	_audio_player.stop()
	_audio_player.stream = stream
	_audio_player.play()

func _physics_process(delta: float):
	if is_dead and not _dying:
		return
	if multiplayer.is_server():
		_server_process(delta)
	else:
		_client_physics(delta)

func _server_process(delta: float):
	if is_moving:
		var prev_x := global_position.x
		var prev_z := global_position.z
		var cur := Vector2(global_position.x, global_position.z)
		var steer_target := _current_steer_target_xz()
		var dist := cur.distance_to(steer_target)
		if dist <= GOAL_ARRIVAL_DIST:
			if _path_waypoints.size() > 0 and _path_index < _path_waypoints.size() - 1:
				_path_index += 1
			else:
				global_position.x = move_target.x
				global_position.z = move_target.y
				velocity = Vector3.ZERO
				is_moving = false
				_path_waypoints.clear()
				_path_index = 0
		else:
			var dir_xz := (steer_target - cur).normalized()
			velocity = Vector3(dir_xz.x * speed, 0.0, dir_xz.y * speed)
			move_and_slide()
			var w = get_parent()
			if w != null and w.has_method("is_walkable_at") \
					and not w.is_walkable_at(global_position.x, global_position.z):
				global_position.x = prev_x
				global_position.z = prev_z
				velocity = Vector3.ZERO
	_apply_ground_height()

	if global_position.x < -MAP_MARGIN or global_position.x > MapConfig.width + MAP_MARGIN \
			or global_position.z < -MAP_MARGIN or global_position.z > MapConfig.height + MAP_MARGIN:
		if not _logged_position_invalid:
			_logged_position_invalid = true
			print("TEST_SERVER_UNIT_POSITION_INVALID: %s out_of_bounds" % name)

	attack_timer -= delta
	_update_combat_state()
	if attack_timer <= 0.0:
		_try_attack()

func _hostiles_in_attack_range() -> Array:
	var world = get_parent()
	if world == null:
		return []
	var center := Vector2(global_position.x, global_position.z)
	var candidates: Array
	if world.has_method("get_units_in_radius"):
		candidates = world.get_units_in_radius(center, attack_range)
	else:
		return []
	var hostiles: Array = []
	for child in candidates:
		if child == self:
			continue
		if not (child is CharacterBody3D):
			continue
		if child.get("is_dead"):
			continue
		if child.owner_peer_id == owner_peer_id:
			continue
		if UNIT_SPRITE_PATHS.is_neutral_owner(owner_peer_id) \
				and UNIT_SPRITE_PATHS.is_neutral_owner(int(child.get("owner_peer_id"))):
			continue
		var oth := child as CharacterBody3D
		var dist := Vector2(global_position.x, global_position.z).distance_to(
			Vector2(oth.global_position.x, oth.global_position.z)
		)
		if dist <= attack_range:
			hostiles.append(child)
	return hostiles

func _update_combat_state() -> void:
	if is_dead:
		in_combat = false
		return
	in_combat = not _hostiles_in_attack_range().is_empty()

func _can_attack_this_tick() -> bool:
	var prof: Dictionary = UNIT_BEHAVIOUR.profile_for_unit(self)
	if prof.get("attack_while_moving", false):
		return true
	return not is_moving

func _pick_attack_target(hostiles: Array):
	if hostiles.is_empty():
		return null
	if commanded_target_name != "":
		for h in hostiles:
			if str(h.name) == commanded_target_name:
				return h
		return null
	if army_stance == 3:
		return null
	if not UNIT_BEHAVIOUR.stance_allows_auto_engage(army_stance):
		return null
	var best = null
	var best_dist := 1e10
	var center := Vector2(global_position.x, global_position.z)
	for h in hostiles:
		var hxz := Vector2(h.global_position.x, h.global_position.z)
		var d := center.distance_to(hxz)
		if d < best_dist:
			best_dist = d
			best = h
	return best

func _try_attack():
	if not _can_attack_this_tick():
		return
	var hostiles := _hostiles_in_attack_range()
	var child = _pick_attack_target(hostiles)
	if child == null:
		return
	var dmg = max(1.0, attack - float(child.get("defense")))
	var oth := child as CharacterBody3D
	var dist := Vector2(global_position.x, global_position.z).distance_to(
		Vector2(oth.global_position.x, oth.global_position.z)
	)
	GameState.last_combat_time = Time.get_ticks_msec() / 1000.0
	print("TEST_010_COMBAT: %s(%s) attacking %s(%s) dist=%.1f dmg=%.1f" % [
		owner_name, army_id, child.get("owner_name"), child.get("army_id"), dist, dmg
	])
	if has_bow:
		var world = get_parent()
		if world != null:
			var endpoints: Dictionary = _ArrowTrajectory.arrow_endpoints(global_position, oth.global_position)
			if world.has_method("spawn_arrow"):
				world.spawn_arrow(
					endpoints["from"],
					endpoints["to"],
					endpoints["duration"],
					endpoints["peak"],
				)
			if world.has_method("schedule_arrow_damage"):
				world.schedule_arrow_damage(str(child.name), dmg, owner_peer_id, endpoints["duration"])
	elif child.has_method("take_damage"):
		child.take_damage(dmg, owner_peer_id)
	attack_timer = attack_cooldown

func _client_physics(delta: float):
	if _dying:
		velocity = Vector3.ZERO
		_apply_ground_height()
		_update_visual_tint()
		_update_facing()
		return
	if has_move_goal and is_moving:
		var cur := Vector2(global_position.x, global_position.z)
		var steer_target := _current_steer_target_xz()
		var dist := cur.distance_to(steer_target)
		if dist <= GOAL_ARRIVAL_DIST:
			if _path_waypoints.size() > 0 and _path_index < _path_waypoints.size() - 1:
				_path_index += 1
			elif _distance_to_final_goal_xz() <= GOAL_ARRIVAL_DIST:
				velocity = Vector3.ZERO
				global_position.x = move_target.x
				global_position.z = move_target.y
				is_moving = false
				_path_waypoints.clear()
				_path_index = 0
			else:
				velocity = Vector3.ZERO
		else:
			var dir := Vector3(
				steer_target.x - global_position.x,
				0.0,
				steer_target.y - global_position.z
			) / dist
			velocity = dir * speed
		_refresh_move_goal_state()
		move_and_slide()
		hp = lerpf(hp, sync_target_hp, clampf(delta * 8.0, 0.0, 1.0))
	else:
		velocity = Vector3.ZERO
		move_and_slide()
	_apply_ground_height()
	_update_visual_tint()
	if not _uses_spritesheets:
		_update_facing()

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
	if _uses_spritesheets and _sprite != null:
		if not _is_moving():
			_sprite.flip_h = (not _facing_right) if _current_art_faces_right else _facing_right
			return
		var dir_xz := Vector2(velocity.x, velocity.z)
		if dir_xz.length() < 0.01:
			var steer := _current_steer_target_xz()
			var to_goal := Vector2(
				steer.x - global_position.x,
				steer.y - global_position.z
			)
			if to_goal.length() > GOAL_FACING_MIN_DIST:
				dir_xz = to_goal
		if dir_xz.length() >= 0.01:
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
		_sprite.flip_h = (not _facing_right) if _current_art_faces_right else _facing_right
		return
	if _mesh == null:
		return
	var dir_xz := Vector2(velocity.x, velocity.z)
	if dir_xz.length() < 0.01 and has_move_goal:
		var steer := _current_steer_target_xz()
		dir_xz = Vector2(
			steer.x - global_position.x,
			steer.y - global_position.z
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
	if _uses_spritesheets and _sprite != null:
		if _selected:
			_sprite.modulate = Color(1.35, 1.35, 0.65)
		else:
			_sprite.modulate = Color.WHITE
		return
	if _material == null:
		return
	if not _texture_loaded:
		_material.albedo_color = Color.DARK_RED if is_dead else _get_fallback_tint()
		return
	if is_dead and not _uses_spritesheets:
		_material.albedo_color = Color(0.45, 0.25, 0.25)
	elif _selected:
		_material.albedo_color = Color(1.35, 1.35, 0.65)
	else:
		_material.albedo_color = Color.WHITE

func _apply_ground_height() -> void:
	var ground_y := _ground_y_at(global_position.x, global_position.z)
	if global_position.y < ground_y - 0.01 and not _logged_height_invalid:
		_logged_height_invalid = true
		print("TEST_3D_UNIT_HEIGHT_INVALID: %s unit_was_below_ground" % name)
	global_position.y = ground_y + half_height
	velocity.y = 0.0
