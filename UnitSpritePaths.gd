extends RefCounted
## Paths and loaders for AI-generated sprite sheets and static spearman fallbacks.

const TEAM_COLOR_FOLDERS: Array[String] = ["red", "blue", "green", "orange", "purple"]
const AI_SPRITES_ROOT := "res://AI_generated_sprites"
const STATIC_SPEARMAN_REL := "spearman/spearman.png"
const MELEE_ATTACK_RANGE := 22.0
const SPEAR_ATTACK_RANGE := 30.0
const RANGED_ATTACK_RANGE := 120.0
const DRAGON_SPRITE_WORLD_HEIGHT := 66.0
const DRAGON_HALF_HEIGHT := 33.0
const DRAGON_ATTACK_RANGE := 70.0
const NEUTRAL_DRAGON_OWNER_ID := 0
const DRAGON_FIGHT_ANIM_SPEED := 1.0

static func dragon_aggro_radius() -> float:
	return DRAGON_SPRITE_WORLD_HEIGHT * 2.0

static func color_folder_for_peer(peer_id: int) -> String:
	if peer_id in GameState.players:
		var ci: int = int(GameState.players[peer_id].get("color_index", 1))
		if ci >= 0 and ci < TEAM_COLOR_FOLDERS.size():
			return TEAM_COLOR_FOLDERS[ci]
	return "blue"

static func unit_type_for_equipment(has_horse: bool, has_spear: bool, has_bow: bool = false) -> String:
	if has_horse and has_bow:
		return "bauer_horse_archer"
	if has_bow:
		return "bowman"
	if has_horse:
		return "knight"
	if has_spear:
		return "spearman"
	return "clubman"

static func is_neutral_owner(peer_id: int) -> bool:
	return peer_id == NEUTRAL_DRAGON_OWNER_ID

static func art_faces_right_for_unit(_unit_type: String) -> bool:
	# All Veo-generated sprite clips face right. Legacy static PNG billboards
	# face left and use the mesh UV flip path when spritesheets are unavailable.
	return true

static func default_attack_range_for_equipment(has_horse: bool, has_spear: bool, has_bow: bool = false) -> float:
	var unit_type := unit_type_for_equipment(has_horse, has_spear, has_bow)
	if unit_type in ["bowman", "bauer_horse_archer"]:
		return RANGED_ATTACK_RANGE
	if has_spear:
		return SPEAR_ATTACK_RANGE
	return MELEE_ATTACK_RANGE

static func uses_mounted_spacing(has_horse: bool, _has_spear: bool, _has_bow: bool) -> bool:
	return has_horse

static func ai_sprite_folder(color: String, unit_type: String, action: String) -> String:
	return "%s/%s/%s/%s" % [AI_SPRITES_ROOT, color, unit_type, action]

static func static_spearman_image_path(color: String) -> String:
	return "res://images/%s/%s" % [color, STATIC_SPEARMAN_REL]

static func folder_has_spritesheet(folder_path: String) -> bool:
	var manifest_path := folder_path.path_join("spritesheet.json")
	var png_path := folder_path.path_join("spritesheet.png")
	return FileAccess.file_exists(manifest_path) and FileAccess.file_exists(png_path)

static func spritesheet_duration(folder_path: String, speed_scale: float = 1.0) -> float:
	var manifest_path := folder_path.path_join("spritesheet.json")
	if not FileAccess.file_exists(manifest_path):
		return 1.0
	var f := FileAccess.open(manifest_path, FileAccess.READ)
	if f == null:
		return 1.0
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return 1.0
	var d: Dictionary = parsed
	var frame_count := maxi(1, int(d.get("frame_count", 1)))
	var playback_fps := float(d.get("playback_fps", 8.0))
	if playback_fps <= 0.0:
		playback_fps = 8.0
	if speed_scale <= 0.0:
		speed_scale = 1.0
	return float(frame_count) / (playback_fps * speed_scale)

static func sprite_sound_path(folder_path: String) -> String:
	return folder_path.path_join("sound.ogg")

static func folder_has_sound(folder_path: String) -> bool:
	return FileAccess.file_exists(sprite_sound_path(folder_path))

static func load_sprite_sound(folder_path: String) -> AudioStream:
	var path := sprite_sound_path(folder_path)
	if not FileAccess.file_exists(path):
		return null
	var abs_path := ProjectSettings.globalize_path(path)
	if abs_path.is_empty():
		return null
	return AudioStreamOggVorbis.load_from_file(abs_path)

static func load_static_spearman_texture(color: String) -> Texture2D:
	for try_color in [color, "blue"]:
		var path := static_spearman_image_path(try_color)
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	return null
