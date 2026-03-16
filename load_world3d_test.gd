extends SceneTree
func _init():
	var scene = load("res://World3D.tscn") as PackedScene
	if scene == null:
		print("ERROR: Failed to load World3D.tscn")
		quit(1)
		return
	var inst = scene.instantiate()
	if inst == null:
		print("ERROR: Failed to instantiate World3D")
		quit(1)
		return
	print("World3D loaded and instantiated OK")
	inst.free()
	quit(0)
