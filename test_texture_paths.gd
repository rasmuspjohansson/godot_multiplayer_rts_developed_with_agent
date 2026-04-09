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
	print("TEST_TEXTURE_PATHS_OK: red_blue_png_readable")
	quit(0)
