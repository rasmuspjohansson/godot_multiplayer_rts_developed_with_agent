extends SceneTree
## Headless check: PNGs used by Unit3D exist and load as ImageTexture (same path logic as spearman art).

func _init():
	var paths := [
		"res://images/red/spearman/spearman.png",
		"res://images/blue/spearman/spearman.png",
	]
	for p in paths:
		var img := Image.new()
		if img.load(p) != OK:
			print("TEST_TEXTURE_PATH_FAIL: Image.load failed path=%s" % p)
			quit(1)
			return
		var tex := ImageTexture.create_from_image(img)
		if tex == null or tex.get_width() < 4 or tex.get_height() < 4:
			print("TEST_TEXTURE_PATH_FAIL: bad ImageTexture path=%s" % p)
			quit(1)
			return

	for folder in [
		"res://sprites/blue/spearman/walking",
		"res://sprites/blue/horseman/galloping",
	]:
		var manifest_path: String = folder.path_join("spritesheet.json")
		var f := FileAccess.open(manifest_path, FileAccess.READ)
		if f == null:
			print("TEST_TEXTURE_PATH_FAIL: missing spritesheet manifest path=%s" % manifest_path)
			quit(1)
			return
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			print("TEST_TEXTURE_PATH_FAIL: invalid spritesheet JSON path=%s" % manifest_path)
			quit(1)
			return
		var png_path: String = folder.path_join("spritesheet.png")
		var abs_png: String = ProjectSettings.globalize_path(png_path)
		var sheet_img: Image = Image.load_from_file(abs_png)
		if sheet_img == null or sheet_img.get_width() < 4 or sheet_img.get_height() < 4:
			print("TEST_TEXTURE_PATH_FAIL: bad spritesheet PNG path=%s" % png_path)
			quit(1)
			return

	print("TEST_TEXTURE_PATHS_OK: red_blue_png_readable")
	quit(0)
