extends RefCounted
## Paths and loaders for AI-generated sprite sheets and static spearman fallbacks.

const UnitSim := preload("res://sim/UnitSim.gd")
const TEAM_COLOR_FOLDERS: Array[String] = ["red", "blue", "green", "orange", "purple"]
const AI_SPRITES_ROOT := "res://AI_generated_sprites"
const STATIC_SPEARMAN_REL := "spearman/spearman.png"
const DRAGON_SPRITE_WORLD_HEIGHT := 66.0
const DRAGON_ATTACK_RANGE := 106.0
const NEUTRAL_DRAGON_OWNER_ID := 0

static func dragon_aggro_radius() -> float:
	return DRAGON_SPRITE_WORLD_HEIGHT * 2.0

static func color_folder_for_peer(peer_id: int) -> String:
	if peer_id in GameState.players:
		var ci: int = int(GameState.players[peer_id].get("color_index", 1))
		if ci >= 0 and ci < TEAM_COLOR_FOLDERS.size():
			return TEAM_COLOR_FOLDERS[ci]
	return "blue"

static func unit_type_for_equipment(has_horse: bool, has_spear: bool, has_bow: bool = false) -> String:
	var t := UnitSim.unit_type_for_equipment(has_horse, has_spear, has_bow)
	return UnitSim.unit_type_name(t) if t >= 0 else "clubman"

static func is_neutral_owner(peer_id: int) -> bool:
	return peer_id == NEUTRAL_DRAGON_OWNER_ID

static func ai_sprite_folder(color: String, unit_type: String, action: String) -> String:
	var primary := "%s/%s/%s/%s" % [AI_SPRITES_ROOT, color, unit_type, action]
	if FileAccess.file_exists(primary.path_join("spritesheet.png")):
		return primary
	var forge := "%s/blue_agent_sprite_forge/%s/%s" % [AI_SPRITES_ROOT, unit_type, action]
	if FileAccess.file_exists(forge.path_join("spritesheet.png")):
		return forge
	return primary

static func static_spearman_image_path(color: String) -> String:
	return "res://images/%s/%s" % [color, STATIC_SPEARMAN_REL]

static func sprite_sound_path(folder_path: String) -> String:
	return folder_path.path_join("sound.ogg")

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
