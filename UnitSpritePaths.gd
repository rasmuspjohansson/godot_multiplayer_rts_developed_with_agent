extends RefCounted
## Paths and loaders for AI-generated sprite sheets and static spearman fallbacks.

const TEAM_COLOR_FOLDERS: Array[String] = ["red", "blue", "green", "orange", "purple"]
const AI_SPRITES_ROOT := "res://AI_generated_sprites"
const STATIC_SPEARMAN_REL := "spearman/spearman.png"

static func color_folder_for_peer(peer_id: int) -> String:
	if peer_id in GameState.players:
		var ci: int = int(GameState.players[peer_id].get("color_index", 1))
		if ci >= 0 and ci < TEAM_COLOR_FOLDERS.size():
			return TEAM_COLOR_FOLDERS[ci]
	return "blue"

static func unit_type_for_equipment(has_horse: bool, has_spear: bool) -> String:
	if has_horse:
		return "knight"
	if has_spear:
		return "spearman"
	return "clubman"

static func ai_sprite_folder(color: String, unit_type: String, action: String) -> String:
	return "%s/%s/%s/%s" % [AI_SPRITES_ROOT, color, unit_type, action]

static func static_spearman_image_path(color: String) -> String:
	return "res://images/%s/%s" % [color, STATIC_SPEARMAN_REL]

static func folder_has_spritesheet(folder_path: String) -> bool:
	var manifest_path := folder_path.path_join("spritesheet.json")
	var png_path := folder_path.path_join("spritesheet.png")
	return FileAccess.file_exists(manifest_path) and FileAccess.file_exists(png_path)

static func load_static_spearman_texture(color: String) -> Texture2D:
	for try_color in [color, "blue"]:
		var path := static_spearman_image_path(try_color)
		var img := Image.new()
		if img.load(path) == OK:
			return ImageTexture.create_from_image(img)
	return null
