extends RefCounted
## Loads a horizontal sprite strip (spritesheet.png + spritesheet.json) and advances frames.

const _SCRIPT := preload("res://SpritesheetAnim.gd")

static var _cache: Dictionary = {}

var _sheet: Texture2D
var _frame_w: int
var _frame_h: int
var _frame_count: int
var _playback_fps: float
var _frame_index: int = 0
var _accum: float = 0.0
var _finished: bool = false

static func load_from_folder(folder_path: String):
	if _cache.has(folder_path):
		return _cache[folder_path]
	var anim = _SCRIPT.new()
	if not anim._load(folder_path):
		return null
	_cache[folder_path] = anim
	return anim

static func clear_cache() -> void:
	_cache.clear()

func _load(folder_path: String) -> bool:
	var manifest_path := folder_path.path_join("spritesheet.json")
	var f := FileAccess.open(manifest_path, FileAccess.READ)
	if f == null:
		push_error("SpritesheetAnim: cannot open manifest: %s" % manifest_path)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SpritesheetAnim: invalid JSON: %s" % manifest_path)
		return false
	var d: Dictionary = parsed
	_frame_w = int(d.get("frame_width", 256))
	_frame_h = int(d.get("frame_height", 256))
	_frame_count = maxi(1, int(d.get("frame_count", 1)))
	_playback_fps = float(d.get("playback_fps", 8.0))
	if _playback_fps <= 0.0:
		_playback_fps = 8.0

	var png_path := folder_path.path_join("spritesheet.png")
	if not FileAccess.file_exists(png_path):
		push_error("SpritesheetAnim: missing texture: %s" % png_path)
		return false
	var abs_png: String = ProjectSettings.globalize_path(png_path)
	var img: Image = Image.load_from_file(abs_png)
	if img == null:
		push_error("SpritesheetAnim: cannot decode PNG: %s" % png_path)
		return false
	_sheet = ImageTexture.create_from_image(img)
	reset()
	return true

func reset() -> void:
	_frame_index = 0
	_accum = 0.0
	_finished = false

func is_finished() -> bool:
	return _finished

func get_frame_count() -> int:
	return _frame_count

func get_frame_width() -> int:
	return _frame_w

func get_frame_height() -> int:
	return _frame_h

func get_playback_fps() -> float:
	return _playback_fps

func get_duration(speed_scale: float = 1.0) -> float:
	return float(_frame_count) / (_playback_fps * speed_scale)

func get_frame_texture() -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = _sheet
	at.region = Rect2(_frame_index * _frame_w, 0, _frame_w, _frame_h)
	return at

func advance(delta: float, loop: bool, speed_scale: float = 1.0) -> AtlasTexture:
	if _sheet == null:
		return null
	if _finished and not loop:
		return get_frame_texture()
	if _frame_count <= 1:
		return get_frame_texture()
	_accum += delta * speed_scale
	var dt: float = 1.0 / _playback_fps
	while _accum >= dt:
		_accum -= dt
		if _frame_index >= _frame_count - 1:
			if loop:
				_frame_index = 0
			else:
				_frame_index = _frame_count - 1
				_finished = true
				break
		else:
			_frame_index += 1
	return get_frame_texture()
