extends SceneTree
## A friendly disc lights the ground, stays fully lit after the army leaves, and does not
## reveal a point far from the circle.
##
## Run: godot --headless --path . -s test_fog_of_war.gd

const FogOfWar := preload("res://sim/FogOfWar.gd")

func _init() -> void:
	call_deferred("_begin")

func _begin() -> void:
	var fog = FogOfWar.new()
	fog.setup(1280.0, 720.0)
	fog.stamp_circle(400.0, 360.0, FogOfWar.SIGHT)
	fog.end_stamp()
	var fails: Array[String] = []
	if not fog.is_explored(400.0, 360.0) or fog.light_at(400.0, 360.0) < 0.9:
		fails.append("centre of the disc is dark")
	if not fog.is_explored(400.0 + FogOfWar.SIGHT * 0.5, 360.0):
		fails.append("point inside the disc is dark")
	if fog.is_explored(400.0 + FogOfWar.SIGHT + 40.0, 360.0):
		fails.append("point outside the disc was revealed")
	fog.stamp_circle(900.0, 360.0, FogOfWar.SIGHT)
	fog.end_stamp()
	if not fog.is_explored(400.0, 360.0) or fog.light_at(400.0, 360.0) < 0.9:
		fails.append("old ground was not kept fully lit")
	if not fog.is_explored(900.0, 360.0) or fog.light_at(900.0, 360.0) < 0.9:
		fails.append("new ground is not lit")
	if fails.is_empty():
		print("TEST_FOG_OF_WAR_OK")
		quit(0)
		return
	for f in fails:
		print("TEST_FOG_OF_WAR_FAIL: %s" % f)
	quit(1)
