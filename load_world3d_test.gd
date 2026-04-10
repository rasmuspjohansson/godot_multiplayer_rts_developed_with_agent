extends SceneTree
func _init():
	var scene = load("res://World.tscn") as PackedScene
	if scene == null:
		print("ERROR: Failed to load World.tscn")
		quit(1)
		return
	var inst = scene.instantiate()
	if inst == null:
		print("ERROR: Failed to instantiate World")
		quit(1)
		return
	print("World loaded and instantiated OK")
	inst.free()
	quit(0)
