extends SceneTree
## Stones start at 1, one stone builds one section, the front of the ridge is steeper
## than the back, melee opens a section in 5 seconds, and bows do not.

const _WallBuilder = preload("res://WallBuilder.gd")

func _init() -> void:
	call_deferred("_begin")

func _fail(msg: String) -> void:
	print("TEST_WALLS_FAIL: %s" % msg)
	quit(1)

func _begin() -> void:
	var gs = root.get_node("GameState")
	var stock: Dictionary = gs.default_resources()
	if int(stock.get("stones", -1)) != 1:
		_fail("expected 1 starting stone, got %s" % str(stock.get("stones")))
		return
	if int(stock.get("villagers", -1)) != 10:
		_fail("villagers should stay at 10")
		return
	if not gs.RESOURCE_KEYS.has("stones"):
		_fail("stones missing from RESOURCE_KEYS")
		return
	var section := _WallBuilder.section_length(1792.0, 524.0)
	var one: Dictionary = _WallBuilder.plan(Vector2.ZERO, Vector2(0, 400), 1, section)
	if int(one.count) != 1 or not is_equal_approx(float(one.end.y), section):
		_fail("one stone should build one section, got %s" % str(one))
		return
	var several: Dictionary = _WallBuilder.plan(Vector2.ZERO, Vector2(0, section * 2.2), 5, section)
	if int(several.count) != 2:
		_fail("drag should stop at whole sections, got %s" % str(several.count))
		return
	var crest := _WallBuilder.profile_height(0.0)
	if not is_equal_approx(_WallBuilder.profile_height(_WallBuilder.FLAT_HALF - 1.0), crest):
		_fail("flat top should hold full height across the palisade")
		return
	var front_slope := (crest - _WallBuilder.profile_height(_WallBuilder.FLAT_HALF + 10.0)) / 10.0
	var back_slope := (crest - _WallBuilder.profile_height(-(_WallBuilder.FLAT_HALF + 20.0))) / 20.0
	if front_slope <= back_slope:
		_fail("front slope %.3f should exceed back %.3f" % [front_slope, back_slope])
		return

	var w = load("res://World.tscn").instantiate()
	root.add_child(w)
	await process_frame
	await process_frame
	for _i in range(8):
		await physics_frame
	if w._walkability == null or w._sim == null:
		_fail("world not ready")
		return
	var step: float = w._terrain_step
	var spot := Vector2(-1, -1)
	for j in range(6, w._terrain_rows - 10):
		for i in range(6, w._terrain_cols - 10):
			var x := float(i) * step
			var z := float(j) * step
			if not _flat_enough(w, x, z):
				continue
			spot = Vector2(x, z)
			break
		if spot.x >= 0.0:
			break
	if spot.x < 0.0:
		_fail("no open ground for a wall")
		return

	var start := spot
	var end := spot + Vector2(0.0, section)
	var mid := start.lerp(end, 0.5)
	var crest_before: float = w._terrain_grid_height_at(mid.x, mid.y)
	var front_at := Vector2(mid.x - (_WallBuilder.FLAT_HALF + 10.0), mid.y)
	var back_at := Vector2(mid.x + (_WallBuilder.FLAT_HALF + 30.0), mid.y)
	var foot_at := Vector2(mid.x - (_WallBuilder.FLAT_HALF + _WallBuilder.STEEP_WIDTH + 8.0), mid.y)
	var front_before: float = w._terrain_grid_height_at(front_at.x, front_at.y)
	var back_before: float = w._terrain_grid_height_at(back_at.x, back_at.y)
	var foot_before: float = w._terrain_grid_height_at(foot_at.x, foot_at.y)
	w._apply_built_wall(1, 1, start, end)
	var crest_y: float = w._terrain_grid_height_at(mid.x, mid.y)
	var crest_h: float = crest_y - crest_before
	var front_h: float = w._terrain_grid_height_at(front_at.x, front_at.y) - front_before
	var back_h: float = w._terrain_grid_height_at(back_at.x, back_at.y) - back_before
	if crest_h < 8.0:
		_fail("crest rise %.2f" % crest_h)
		return
	var side: float = w._terrain_grid_height_at(mid.x + 12.0, mid.y)
	var other: float = w._terrain_grid_height_at(mid.x - 12.0, mid.y)
	var along: float = w._terrain_grid_height_at(mid.x, mid.y + 16.0)
	if absf(side - crest_y) > 0.05 or absf(other - crest_y) > 0.05 or absf(along - crest_y) > 0.05:
		_fail("crest is not flat under the palisade side=%.2f other=%.2f along=%.2f crest=%.2f" % [side, other, along, crest_y])
		return
	var palisade_y: float = w._walls[0].sections[0].node.position.y
	if absf(palisade_y - crest_y) > 0.05:
		_fail("palisade base %.2f does not meet the crest %.2f" % [palisade_y, crest_y])
		return
	if (crest_h - front_h) / 10.0 <= (crest_h - back_h) / 30.0:
		_fail("stamped front is not steeper than the back")
		return
	if w._terrain_grid_height_at(foot_at.x, foot_at.y) > foot_before + 1.0:
		_fail("ridge base should be past the palisade and back at ground level")
		return
	if w.is_walkable_at(mid.x, mid.y):
		_fail("palisade did not block the crest")
		return
	if not w.is_walkable_at(mid.x + _WallBuilder.FLAT_HALF + 40.0, mid.y):
		_fail("gentle side should stay walkable")
		return

	w._sim.add_unit(0, mid.x - 18.0, mid.y, 2, -1, 0)
	for _n in range(50):
		w._advance_wall_sections(0.1)
	if w._walls.is_empty() or w._walls[0].sections[0].alive:
		_fail("melee unit did not remove the section in 5 seconds")
		return
	if not is_equal_approx(w._terrain_grid_height_at(mid.x, mid.y), crest_y):
		_fail("ridge was removed with the palisade")
		return
	if not w.is_walkable_at(mid.x, mid.y):
		_fail("opened section is still blocked")
		return

	var start2 := spot + Vector2(140.0, 0.0)
	var end2 := start2 + Vector2(0.0, section)
	var mid2 := start2.lerp(end2, 0.5)
	if not w.is_walkable_at(mid2.x, mid2.y):
		_fail("no room for the bow test wall")
		return
	w._apply_built_wall(2, 1, start2, end2)
	w._sim.add_unit(1, mid2.x - 18.0, mid2.y, 2, -1, 3)
	for _n2 in range(50):
		w._advance_wall_sections(0.1)
	var bow_held := false
	for wall in w._walls:
		if int(wall.id) == 2 and wall.sections[0].alive:
			bow_held = true
	if not bow_held:
		_fail("a bowman removed a palisade")
		return
	print("TEST_WALLS_OK")
	quit(0)

func _flat_enough(w, x: float, z: float) -> bool:
	if not w.is_walkable_at(x, z):
		return false
	if not w.is_walkable_at(x, z + 70.0):
		return false
	if not w.is_walkable_at(x - 20.0, z + 30.0):
		return false
	if not w.is_walkable_at(x + 40.0, z + 30.0):
		return false
	if not w.is_walkable_at(x + 140.0, z + 30.0):
		return false
	var h: float = w._terrain_grid_height_at(x, z)
	for p in [Vector2(0, 70), Vector2(-20, 30), Vector2(40, 30), Vector2(140, 30)]:
		if absf(w._terrain_grid_height_at(x + p.x, z + p.y) - h) > 3.0:
			return false
	return true
