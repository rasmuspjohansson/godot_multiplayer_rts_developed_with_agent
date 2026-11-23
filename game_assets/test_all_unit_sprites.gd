extends SceneTree
## Both players start with 1000 of every resource, each orders every formation,
## and every unit type (including both dragons) is drawn from its own sprite sheet.

## horse, spear, bow, armour, sword, long_spear, shield, unit type enum value
const RECIPES: Array = [
	[false, false, false, false, false, false, false, 0],
	[false, true, false, false, false, false, false, 1],
	[true, false, false, false, false, false, false, 2],
	[false, false, true, false, false, false, false, 3],
	[true, false, true, false, false, false, false, 4],
	[false, false, false, true, true, false, false, 6],
	[false, false, true, true, false, false, false, 7],
	[true, false, false, false, false, true, false, 8],
	[false, false, false, false, true, false, true, 9],
	[false, false, false, true, true, false, true, 10],
	[true, false, false, false, true, false, true, 11],
	[false, false, false, true, false, true, false, 13],
	[true, false, false, true, false, true, true, 12],
	[false, true, false, false, false, false, true, 15],
	[false, true, false, true, false, false, false, 16],
	[false, true, false, true, false, false, true, 17],
	[false, false, false, false, false, true, false, 18],
	[false, false, false, false, false, true, true, 19],
	[false, false, false, true, false, true, true, 20],
	[false, false, true, false, false, false, true, 21],
	[false, false, true, true, false, false, true, 22],
	[true, false, true, true, false, false, false, 23],
	[true, false, false, true, true, false, false, 24],
	[true, false, false, true, true, false, true, 25],
	[true, false, false, false, false, true, true, 26],
	[true, false, false, true, false, true, false, 27],
]

var _UnitSim
var _UnitRenderer
var _Paths

func _init() -> void:
	call_deferred("_begin")

func _gs():
	return root.get_node("/root/GameState")

func _begin() -> void:
	_UnitSim = load("res://sim/UnitSim.gd")
	_UnitRenderer = load("res://sim/UnitRenderer.gd")
	_Paths = load("res://UnitSpritePaths.gd")
	var gs = _gs()
	gs.players.clear()
	gs.starting_resource_amount = 1000
	gs.players[1] = {"name": "A", "ready": true, "color_index": 0}
	gs.players[2] = {"name": "B", "ready": true, "color_index": 1}
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(18922, 4)
	if err != OK:
		_fail("could not open the test server (%d)" % err)
		return
	root.multiplayer.multiplayer_peer = peer
	var world = load("res://World.tscn").instantiate()
	root.add_child(world)
	if not world.multiplayer.is_server():
		_fail("world did not start as the server")
		return
	for pid in [1, 2]:
		var stock: Dictionary = gs.resources.get(pid, {})
		for key in gs.RESOURCE_KEYS:
			if int(stock.get(key, 0)) != 1000:
				_fail("player %d started with %s=%s, expected 1000" % [pid, key, str(stock.get(key, 0))])
				return
	var renderer = _UnitRenderer.new()
	renderer.name = "UnitRenderer"
	renderer.sim = world._sim
	world.add_child(renderer)
	world._unit_renderer = renderer
	var drafted: Array = []
	for pid in [1, 2]:
		var color: String = _Paths.color_folder_for_peer(pid)
		for recipe in RECIPES:
			var before: int = world.armies.size()
			var expect_name: String = _UnitSim.unit_type_name(recipe[7])
			world.request_draft_army(recipe[0], recipe[1], recipe[2], 10, recipe[3], recipe[4], recipe[5], recipe[6], pid)
			if world.armies.size() != before + 1:
				_fail("player %d draft did not spawn %s" % [pid, expect_name])
				return
			var army = world.armies[before]
			var uid: int = army.fc.members[0]
			if int(world._sim.utype[uid]) != int(recipe[7]):
				_fail("drafted %s but spawned type %s" % [expect_name, _UnitSim.unit_type_name(world._sim.utype[uid])])
				return
			drafted.append({"color": color, "type": expect_name, "army": army})
		var villagers_left := 1000 - RECIPES.size() * 10
		if int(gs.resources[pid].get("villagers", 0)) != villagers_left:
			_fail("player %d villagers left=%s after ordering every formation, expected %d" % [pid, str(gs.resources[pid].get("villagers", 0)), villagers_left])
			return
	var dragon = world._create_army("neutral_dragon", 0, "Dragon", Vector2(300, 300), 0.0, {"dragon": true, "soldiers": 1})
	var dragon_2 = world._create_army("neutral_dragon_2", 0, "Dragon2", Vector2(420, 300), 0.0, {"unit": "dragon_2", "soldiers": 1})
	if dragon == null or dragon_2 == null:
		_fail("dragon spawn failed")
		return
	world.armies.append(dragon)
	world.armies.append(dragon_2)
	var seen := {}
	for i in range(world._sim.count):
		if world._sim.is_alive(i):
			seen[int(world._sim.utype[i])] = true
	for t in range(_UnitSim.UnitType.size()):
		if not seen.has(t):
			_fail("unit type %s was never spawned" % _UnitSim.unit_type_name(t))
			return
	for color in _Paths.TEAM_COLOR_FOLDERS:
		for t in range(_UnitSim.UnitType.size()):
			if not _sheet_ok(renderer, color, _UnitSim.unit_type_name(t)):
				return
	for entry in drafted:
		var key := "%s/%s" % [entry["color"], entry["type"]]
		if not renderer._group_by_key.has(key):
			_fail("renderer has no group for %s" % key)
			return
		var sheet = renderer._group_by_key[key].mat.get_shader_parameter("sheet")
		if sheet == null or not (sheet is Texture2D) or (sheet as Texture2D).get_width() < 8:
			_fail("renderer sheet for %s is missing" % key)
			return
	print("TEST_ALL_UNIT_SPRITES_OK: players=2 start=1000 formations=%d types=%d" % [drafted.size(), seen.size()])
	root.multiplayer.multiplayer_peer = null
	peer.close()
	quit(0)

func _sheet_ok(renderer, color: String, unit_type: String) -> bool:
	var spear_idle: Image = null
	for action in _UnitRenderer.ROWS:
		var folder: String = _Paths.ai_sprite_folder(color, unit_type, action)
		var expect := "res://AI_generated_sprites/%s/%s/%s" % [color, unit_type, action]
		if folder != expect:
			_fail("%s/%s/%s resolved to %s" % [color, unit_type, action, folder])
			return false
		var clip: Dictionary = renderer._load_clip(color, unit_type, action)
		if clip.is_empty():
			_fail("%s/%s/%s did not load" % [color, unit_type, action])
			return false
		var img: Image = clip["image"]
		var used := img.get_used_rect()
		if used.size.x < 8 or used.size.y < 8:
			_fail("%s/%s/%s sprite is invisible" % [color, unit_type, action])
			return false
		if unit_type != "spearman":
			if action == "idle":
				var spear_clip: Dictionary = renderer._load_clip(color, "spearman", "idle")
				spear_idle = spear_clip.get("image", null)
			var spear: Dictionary = renderer._load_clip(color, "spearman", action)
			if not spear.is_empty() and _same_image(img, spear["image"]):
				_fail("%s/%s/%s is the spearman fallback sheet" % [color, unit_type, action])
				return false
	var info: Dictionary = renderer._stacked_sheet(color, unit_type)
	var tex: Texture2D = info.get("texture", null)
	if tex == null or tex.get_width() < 8 or tex.get_height() < 8:
		_fail("%s/%s stacked sheet is invisible" % [color, unit_type])
		return false
	var stacked := tex.get_image()
	var row_h := int(stacked.get_height() / 4)
	for r in range(4):
		var row := stacked.get_region(Rect2i(0, r * row_h, stacked.get_width(), row_h))
		var row_used := row.get_used_rect()
		if row_used.size.x < 8 or row_used.size.y < 8:
			_fail("%s/%s row %s is invisible" % [color, unit_type, _UnitRenderer.ROWS[r]])
			return false
	if unit_type != "spearman" and spear_idle != null:
		var idle_row := stacked.get_region(Rect2i(0, 0, mini(spear_idle.get_width(), stacked.get_width()), mini(spear_idle.get_height(), row_h)))
		var spear_region := spear_idle.get_region(Rect2i(0, 0, idle_row.get_width(), idle_row.get_height()))
		if _same_image(idle_row, spear_region):
			_fail("%s/%s stacked idle row is the spearman sheet" % [color, unit_type])
			return false
	return true

func _same_image(a: Image, b: Image) -> bool:
	if a == null or b == null:
		return false
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return false
	var step := 48
	for y in range(0, a.get_height(), step):
		for x in range(0, a.get_width(), step):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				return false
	return true

func _fail(message: String) -> void:
	print("TEST_ALL_UNIT_SPRITES_FAIL: %s" % message)
	quit(1)
