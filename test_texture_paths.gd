extends SceneTree
## Headless check: static spearman PNGs and AI-generated sprite sheets load correctly.

func _init():
	var paths := [
		"res://images/red/spearman/spearman.png",
		"res://images/blue/spearman/spearman.png",
		"res://images/green/spearman/spearman.png",
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

	var purple_path := "res://images/purple/spearman/spearman.png"
	var blue_path := "res://images/blue/spearman/spearman.png"
	if FileAccess.file_exists(purple_path):
		var purple_img := Image.new()
		if purple_img.load(purple_path) != OK:
			print("TEST_TEXTURE_PATH_FAIL: purple spearman load failed")
			quit(1)
			return
	else:
		var blue_img := Image.new()
		if blue_img.load(blue_path) != OK:
			print("TEST_TEXTURE_PATH_FAIL: blue spearman fallback load failed")
			quit(1)
			return

	for folder in [
		"res://AI_generated_sprites/green/spearman/move",
		"res://AI_generated_sprites/red/knight/move",
	]:
		var manifest_path: String = folder.path_join("spritesheet.json")
		if not FileAccess.file_exists(manifest_path):
			print("TEST_TEXTURE_PATH_FAIL: missing spritesheet manifest path=%s" % manifest_path)
			quit(1)
			return
		var f := FileAccess.open(manifest_path, FileAccess.READ)
		if f == null:
			print("TEST_TEXTURE_PATH_FAIL: cannot open manifest path=%s" % manifest_path)
			quit(1)
			return
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			print("TEST_TEXTURE_PATH_FAIL: invalid spritesheet JSON path=%s" % manifest_path)
			quit(1)
			return
		var png_path: String = folder.path_join("spritesheet.png")
		if not FileAccess.file_exists(png_path):
			print("TEST_TEXTURE_PATH_FAIL: missing spritesheet PNG path=%s" % png_path)
			quit(1)
			return

	print("TEST_TEXTURE_PATHS_OK: red_blue_png_readable")
	quit(0)
