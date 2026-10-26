extends RefCounted
## Loads a horizontal sprite strip (spritesheet.png + spritesheet.json); used for army portraits.

const _SCRIPT := preload("res://SpritesheetAnim.gd")

static var _cache: Dictionary = {}

var _sheet: Texture2D
var _frame_w: int
var _frame_h: int

static func load_from_folder(folder_path: String):
	if _cache.has(folder_path):
		return _cache[folder_path]
	var anim = _SCRIPT.new()
	if not anim._load(folder_path):
		return null
	_cache[folder_path] = anim
	return anim

func _load(folder_path: String) -> bool:
	var manifest_path := folder_path.path_join("spritesheet.json")
	if not FileAccess.file_exists(manifest_path):
		return false
	var f := FileAccess.open(manifest_path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	_frame_w = int(d.get("frame_width", 256))
	_frame_h = int(d.get("frame_height", 256))

	var png_path := folder_path.path_join("spritesheet.png")
	if not FileAccess.file_exists(png_path):
		return false
	var abs_png: String = ProjectSettings.globalize_path(png_path)
	var img: Image = Image.load_from_file(abs_png)
	if img == null:
		return false
	_sheet = ImageTexture.create_from_image(img)
	return true

func get_frame_width() -> int:
	return _frame_w

func get_frame_height() -> int:
	return _frame_h

func get_frame_texture() -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = _sheet
	at.region = Rect2(0, 0, _frame_w, _frame_h)
	return at
