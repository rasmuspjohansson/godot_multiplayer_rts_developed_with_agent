extends Control
## Standalone map editor. Run: godot -- --map-editor

enum Tool {
	SELECT,
	HILL,
	RIDGE,
	PLATEAU,
	VALLEY,
	LAKE,
	CAPTURE,
	ARMY,
	DRAGON,
	TREE,
	SPRUCE,
	BUSH,
	STONE,
}

const PICK_DIST := 48.0
const GIZMO_R := 10.0
const CORNERS := ["NW", "SE", "NE", "SW"]
const CP_TYPES := ["Stables", "Blacksmith", "Village", "Archery"]
const DRAGON_COLORS := ["red", "green", "blue"]
const SLOT_COLORS := [
	Color(0.95, 0.25, 0.2),
	Color(0.25, 0.45, 0.95),
	Color(0.2, 0.75, 0.3),
	Color(0.95, 0.6, 0.15),
]

var _world: Node3D
var _gizmos: Node3D
var _status: Label
var _inspector: VBoxContainer
var _name_edit: LineEdit
var _width_spin: SpinBox
var _height_spin: SpinBox
var _open_option: OptionButton
var _tool: int = Tool.SELECT
var _draft_points: Array = []
var _selection: Dictionary = {}
var _dragging := false
var _undo: Array = []
var _rebuild_timer: Timer
var _suppress_inspector := false

var _hill_width := 300.0
var _hill_height := 28.0
var _ridge_width := 400.0
var _ridge_height := 80.0
var _poly_height := 80.0
var _poly_falloff := 80.0
var _valley_depth := 40.0
var _lake_rise := 12.0
var _army_slot := 0
var _army_dir := 0.0
var _army_horse := false
var _army_spear := true
var _army_bow := false
var _cp_type := "Stables"
var _dragon_color := "red"
var _scatter_count := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_rebuild_timer = Timer.new()
	_rebuild_timer.one_shot = true
	_rebuild_timer.wait_time = 0.2
	_rebuild_timer.timeout.connect(_do_rebuild)
	add_child(_rebuild_timer)
	call_deferred("_boot_world")

func _boot_world() -> void:
	var main := get_tree().root.get_node("Main")
	var level: Node = main.get_node("Level")
	for child in level.get_children():
		child.queue_free()
	_world = load("res://World.tscn").instantiate()
	_world.preview_only = true
	level.add_child(_world)
	_gizmos = Node3D.new()
	_gizmos.name = "EditorGizmos"
	_world.add_child(_gizmos)
	_refresh_open_list()
	_push_undo()
	_refresh_gizmos()
	_refresh_inspector()
	_set_status("Editing map '%s'. Middle-drag or WASD to pan, wheel to zoom." % MapConfig.name_)

func _build_ui() -> void:
	var top := _make_panel()
	top.anchor_right = 1.0
	top.offset_bottom = 40.0
	add_child(top)
	var top_row := HBoxContainer.new()
	top_row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	top_row.add_theme_constant_override("separation", 8)
	top.add_child(top_row)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(120, 0)
	_name_edit.text = MapConfig.name_
	_name_edit.placeholder_text = "Map name"
	top_row.add_child(_name_edit)
	_add_btn(top_row, "New", _on_new)
	_add_btn(top_row, "Save", _on_save)
	_open_option = OptionButton.new()
	_open_option.custom_minimum_size = Vector2(100, 0)
	_open_option.item_selected.connect(_on_open_selected)
	top_row.add_child(_open_option)
	_add_btn(top_row, "Open", _on_open_clicked)
	_add_btn(top_row, "Undo", undo)
	top_row.add_child(_labeled_spin("W", 256, 8192, MapConfig.width, func(v): _set_map_size(v, MapConfig.height)))
	top_row.add_child(_labeled_spin("H", 256, 8192, MapConfig.height, func(v): _set_map_size(MapConfig.width, v)))
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_status)

	var left := _make_panel()
	left.anchor_bottom = 1.0
	left.offset_top = 40.0
	left.offset_right = 160.0
	add_child(left)
	var tools := VBoxContainer.new()
	tools.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	tools.offset_left = 6
	tools.offset_top = 6
	tools.offset_right = -6
	tools.offset_bottom = -6
	left.add_child(tools)
	var title := Label.new()
	title.text = "Tools"
	tools.add_child(title)
	var tool_names := [
		["Select", Tool.SELECT],
		["Hill", Tool.HILL],
		["Ridge", Tool.RIDGE],
		["Plateau", Tool.PLATEAU],
		["Valley", Tool.VALLEY],
		["Lake", Tool.LAKE],
		["Capture", Tool.CAPTURE],
		["Army", Tool.ARMY],
		["Dragon", Tool.DRAGON],
		["Tree", Tool.TREE],
		["Spruce", Tool.SPRUCE],
		["Bush", Tool.BUSH],
		["Stone", Tool.STONE],
	]
	for pair in tool_names:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(_set_tool.bind(pair[1], pair[0]))
		tools.add_child(b)

	var right := _make_panel()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	right.offset_left = -240.0
	right.offset_top = 40.0
	add_child(right)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	right.add_child(scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inspector)

func _make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.set_anchors_preset(PRESET_TOP_LEFT)
	return p

func _add_btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)

func _labeled_spin(label: String, mn: float, mx: float, val: float, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = 1
	s.value = val
	s.value_changed.connect(cb)
	if label == "W":
		_width_spin = s
	elif label == "H":
		_height_spin = s
	row.add_child(s)
	return row

func _set_tool(t: int, label: String) -> void:
	_tool = t
	_draft_points.clear()
	_dragging = false
	if t != Tool.SELECT:
		_selection.clear()
		_refresh_gizmos()
	_set_status("Tool: %s. Left click to place. Enter/right-click finishes polygons." % label)
	_refresh_inspector()

func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg

func _unhandled_input(event: InputEvent) -> void:
	if _world == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.ctrl_pressed and k.keycode == KEY_Z:
			undo()
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE:
			_delete_selection()
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			_finish_draft()
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_ESCAPE:
			_draft_points.clear()
			_selection.clear()
			_refresh_gizmos()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not _draft_points.is_empty():
				_finish_draft()
			else:
				_selection.clear()
				_refresh_gizmos()
				_refresh_inspector()
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_down(mb.position)
			else:
				_dragging = false
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventMouseMotion and _dragging and _tool == Tool.SELECT:
		_drag_selection((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()

func _ground_at(screen: Vector2) -> Vector3:
	if _world.has_method("_raycast_ground_at_screen"):
		return _world._raycast_ground_at_screen(screen)
	return Vector3.ZERO

func _on_left_down(screen: Vector2) -> void:
	var hit: Vector3 = _ground_at(screen)
	var xz := Vector2(hit.x, hit.z)
	xz.x = clampf(xz.x, 0.0, MapConfig.width)
	xz.y = clampf(xz.y, 0.0, MapConfig.height)
	match _tool:
		Tool.SELECT:
			_pick_at(xz)
			_dragging = not _selection.is_empty()
			if _dragging:
				_push_undo()
		Tool.HILL:
			_push_undo()
			MapConfig.terrain_features.append({
				"type": "hill", "x": xz.x, "y": xz.y,
				"base_width": _hill_width, "height": _hill_height,
			})
			_schedule_rebuild()
		Tool.RIDGE, Tool.PLATEAU, Tool.VALLEY:
			_draft_points.append({"x": xz.x, "y": xz.y})
			_refresh_gizmos()
			_set_status("Vertex %d. Enter or right-click to finish." % _draft_points.size())
		Tool.LAKE:
			_push_undo()
			MapConfig.lakes.append({"x": xz.x, "y": xz.y, "rise": _lake_rise})
			_schedule_rebuild()
		Tool.CAPTURE:
			_push_undo()
			MapConfig.capture_points.append({
				"id": _unique_cp_id(_cp_type),
				"type": _cp_type,
				"x": xz.x,
				"y": xz.y,
			})
			_refresh_gizmos()
		Tool.ARMY:
			_push_undo()
			_ensure_slot(_army_slot)
			MapConfig.player_starts[_army_slot]["armies"].append({
				"x": xz.x, "y": xz.y, "direction": _army_dir,
				"horse": _army_horse, "spear": _army_spear, "bow": _army_bow,
			})
			_refresh_gizmos()
		Tool.DRAGON:
			_push_undo()
			MapConfig.neutral_dragons.append({"x": xz.x, "y": xz.y, "color": _dragon_color})
			MapConfig.neutral_dragon = {}
			_refresh_gizmos()
		Tool.TREE, Tool.SPRUCE, Tool.BUSH, Tool.STONE:
			_push_undo()
			var kind := "tree"
			match _tool:
				Tool.SPRUCE:
					kind = "spruce"
				Tool.BUSH:
					kind = "bush"
				Tool.STONE:
					kind = "stone"
			MapConfig.props.append({"kind": kind, "x": xz.x, "y": xz.y})
			_schedule_rebuild()

func _finish_draft() -> void:
	if _tool == Tool.RIDGE:
		if _draft_points.size() < 2:
			_set_status("Ridge needs at least 2 points.")
			return
		_push_undo()
		MapConfig.terrain_features.append({
			"type": "spline_ridge",
			"points": _draft_points.duplicate(true),
			"width": _ridge_width,
			"height": _ridge_height,
		})
	elif _tool == Tool.PLATEAU or _tool == Tool.VALLEY:
		if _draft_points.size() < 3:
			_set_status("Polygon needs at least 3 points.")
			return
		_push_undo()
		if _tool == Tool.PLATEAU:
			MapConfig.terrain_features.append({
				"type": "plateau_polygon",
				"points": _draft_points.duplicate(true),
				"height": _poly_height,
				"falloff": _poly_falloff,
			})
		else:
			MapConfig.terrain_features.append({
				"type": "valley_polygon",
				"points": _draft_points.duplicate(true),
				"depth": _valley_depth,
				"falloff": _poly_falloff,
			})
	else:
		return
	_draft_points.clear()
	_schedule_rebuild()

func _pick_at(xz: Vector2) -> void:
	var best := {}
	var best_d := PICK_DIST
	for i in range(MapConfig.terrain_features.size()):
		var f: Dictionary = MapConfig.terrain_features[i]
		var ftype := str(f.get("type", ""))
		if ftype == "hill":
			var d := xz.distance_to(Vector2(float(f.get("x", 0.0)), float(f.get("y", 0.0))))
			if d < best_d:
				best_d = d
				best = {"kind": "feature", "index": i}
		elif f.has("points"):
			var pts: Array = f.get("points", [])
			for vi in range(pts.size()):
				var pt: Dictionary = pts[vi]
				var d2 := xz.distance_to(Vector2(float(pt.get("x", 0.0)), float(pt.get("y", 0.0))))
				if d2 < best_d:
					best_d = d2
					best = {"kind": "feature_vertex", "index": i, "vertex": vi}
	for i in range(MapConfig.lakes.size()):
		var lake: Dictionary = MapConfig.lakes[i]
		var d := xz.distance_to(Vector2(float(lake.get("x", 0.0)), float(lake.get("y", 0.0))))
		if d < best_d:
			best_d = d
			best = {"kind": "lake", "index": i}
	for i in range(MapConfig.capture_points.size()):
		var cp: Dictionary = MapConfig.capture_points[i]
		var d := xz.distance_to(Vector2(float(cp.get("x", 0.0)), float(cp.get("y", 0.0))))
		if d < best_d:
			best_d = d
			best = {"kind": "capture", "index": i}
	for s in range(MapConfig.player_starts.size()):
		var armies: Array = MapConfig.player_starts[s].get("armies", [])
		for ai in range(armies.size()):
			var a: Dictionary = armies[ai]
			var d := xz.distance_to(Vector2(float(a.get("x", 0.0)), float(a.get("y", 0.0))))
			if d < best_d:
				best_d = d
				best = {"kind": "army", "slot": s, "index": ai}
	var dragons: Array = MapConfig.get_neutral_dragons()
	for i in range(dragons.size()):
		var dg: Dictionary = dragons[i]
		var d := xz.distance_to(Vector2(float(dg.get("x", 0.0)), float(dg.get("y", 0.0))))
		if d < best_d:
			best_d = d
			best = {"kind": "dragon", "index": i}
	for i in range(MapConfig.props.size()):
		var p: Dictionary = MapConfig.props[i]
		var d := xz.distance_to(Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))))
		if d < best_d:
			best_d = d
			best = {"kind": "prop", "index": i}
	_selection = best
	_refresh_gizmos()
	_refresh_inspector()

func _drag_selection(screen: Vector2) -> void:
	if _selection.is_empty():
		return
	var hit: Vector3 = _ground_at(screen)
	var x := clampf(hit.x, 0.0, MapConfig.width)
	var y := clampf(hit.z, 0.0, MapConfig.height)
	var kind := str(_selection.get("kind", ""))
	match kind:
		"feature":
			var f: Dictionary = MapConfig.terrain_features[int(_selection.index)]
			f["x"] = x
			f["y"] = y
			MapConfig.terrain_features[int(_selection.index)] = f
			_schedule_rebuild()
		"feature_vertex":
			var fv: Dictionary = MapConfig.terrain_features[int(_selection.index)]
			var pts: Array = fv.get("points", [])
			var vi: int = int(_selection.vertex)
			if vi >= 0 and vi < pts.size():
				pts[vi] = {"x": x, "y": y}
				fv["points"] = pts
				MapConfig.terrain_features[int(_selection.index)] = fv
			_schedule_rebuild()
		"lake":
			var lake: Dictionary = MapConfig.lakes[int(_selection.index)]
			lake["x"] = x
			lake["y"] = y
			MapConfig.lakes[int(_selection.index)] = lake
			_schedule_rebuild()
		"capture":
			var cp: Dictionary = MapConfig.capture_points[int(_selection.index)]
			cp["x"] = x
			cp["y"] = y
			MapConfig.capture_points[int(_selection.index)] = cp
			_refresh_gizmos()
		"army":
			var armies: Array = MapConfig.player_starts[int(_selection.slot)].get("armies", [])
			var a: Dictionary = armies[int(_selection.index)]
			a["x"] = x
			a["y"] = y
			armies[int(_selection.index)] = a
			MapConfig.player_starts[int(_selection.slot)]["armies"] = armies
			_refresh_gizmos()
		"dragon":
			var dg: Dictionary = MapConfig.neutral_dragons[int(_selection.index)]
			dg["x"] = x
			dg["y"] = y
			MapConfig.neutral_dragons[int(_selection.index)] = dg
			_refresh_gizmos()
		"prop":
			var p: Dictionary = MapConfig.props[int(_selection.index)]
			p["x"] = x
			p["y"] = y
			MapConfig.props[int(_selection.index)] = p
			_schedule_rebuild()

func _delete_selection() -> void:
	if _selection.is_empty():
		return
	_push_undo()
	var kind := str(_selection.get("kind", ""))
	var idx: int = int(_selection.get("index", -1))
	match kind:
		"feature", "feature_vertex":
			if idx >= 0 and idx < MapConfig.terrain_features.size():
				MapConfig.terrain_features.remove_at(idx)
			_schedule_rebuild()
		"lake":
			if idx >= 0 and idx < MapConfig.lakes.size():
				MapConfig.lakes.remove_at(idx)
			_schedule_rebuild()
		"capture":
			if idx >= 0 and idx < MapConfig.capture_points.size():
				MapConfig.capture_points.remove_at(idx)
		"army":
			var slot: int = int(_selection.get("slot", 0))
			var armies: Array = MapConfig.player_starts[slot].get("armies", [])
			if idx >= 0 and idx < armies.size():
				armies.remove_at(idx)
			MapConfig.player_starts[slot]["armies"] = armies
		"dragon":
			if idx >= 0 and idx < MapConfig.neutral_dragons.size():
				MapConfig.neutral_dragons.remove_at(idx)
		"prop":
			if idx >= 0 and idx < MapConfig.props.size():
				MapConfig.props.remove_at(idx)
			_schedule_rebuild()
	_selection.clear()
	_refresh_gizmos()
	_refresh_inspector()

func _schedule_rebuild() -> void:
	MapConfig.load_from_dict(MapConfig.to_dict())
	_rebuild_timer.start()
	_refresh_gizmos()

func _do_rebuild() -> void:
	if _world and _world.has_method("rebuild_from_mapconfig"):
		_world.rebuild_from_mapconfig()
	if _gizmos and not _gizmos.is_inside_tree() and _world:
		_gizmos = Node3D.new()
		_gizmos.name = "EditorGizmos"
		_world.add_child(_gizmos)
	_refresh_gizmos()

func _push_undo() -> void:
	_undo.append(JSON.stringify(MapConfig.to_dict()))
	if _undo.size() > 40:
		_undo.pop_front()

func undo() -> void:
	if _undo.size() < 2:
		return
	_undo.pop_back()
	var raw: String = _undo.back()
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_selection.clear()
	_draft_points.clear()
	MapConfig.load_from_dict(parsed)
	_sync_size_spins()
	_do_rebuild()
	_refresh_inspector()

func _on_new() -> void:
	_push_undo()
	MapConfig.map_size = "New"
	MapConfig.load_from_dict(_blank_map())
	if _name_edit:
		_name_edit.text = "New"
	_sync_size_spins()
	_do_rebuild()
	_refresh_inspector()
	_set_status("New blank map.")

func _blank_map() -> Dictionary:
	var starts: Array = []
	for i in range(4):
		starts.append({"slot": i, "corner": CORNERS[i], "armies": []})
	return {
		"name": "New",
		"size": {"width": 1280, "height": 720},
		"terrain": {"type": "hills", "features": []},
		"lighting": {
			"sun_azimuth_deg": 275.0, "sun_elevation_deg": 0.0, "energy": 0.12,
			"color": [1.0, 0.98, 0.95], "shadow_max_distance": null,
		},
		"vegetation": {"count": 0, "forest_clusters": 0},
		"lakes": [],
		"props": [],
		"capture_points": [],
		"player_starts": starts,
		"neutral_dragons": [],
	}

func _on_save() -> void:
	var name_str := _name_edit.text.strip_edges() if _name_edit else MapConfig.name_
	if name_str == "":
		_set_status("Enter a map name before saving.")
		return
	name_str = name_str.replace(" ", "_")
	MapConfig.name_ = name_str
	MapConfig.map_size = name_str
	var data := MapConfig.to_dict()
	data["name"] = name_str
	var text := JSON.stringify(data, "  ")
	var rel := "maps/map_%s.json" % name_str
	var path := "res://%s" % rel
	var ok := _write_text(path, text)
	if not ok:
		DirAccess.make_dir_recursive_absolute("user://maps")
		path = "user://maps/map_%s.json" % name_str
		ok = _write_text(path, text)
	if ok:
		_refresh_open_list()
		_set_status("Saved %s" % path)
		print("TEST_MAP_EDITOR_SAVE: %s" % path)
	else:
		_set_status("Save failed.")

func _write_text(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true

func _refresh_open_list() -> void:
	if _open_option == null:
		return
	_open_option.clear()
	var names := MapConfig.list_maps()
	var sel := 0
	for i in range(names.size()):
		_open_option.add_item(names[i])
		if names[i] == MapConfig.map_size or names[i] == MapConfig.name_:
			sel = i
	if names.size() > 0:
		_open_option.select(sel)

func _on_open_clicked() -> void:
	if _open_option == null or _open_option.item_count == 0:
		return
	_on_open_selected(_open_option.selected)

func _on_open_selected(idx: int) -> void:
	if idx < 0 or idx >= _open_option.item_count:
		return
	var name_str := _open_option.get_item_text(idx)
	_push_undo()
	if not MapConfig.reload(name_str):
		_set_status("Could not open %s" % name_str)
		return
	if _name_edit:
		_name_edit.text = MapConfig.name_
	_sync_size_spins()
	_do_rebuild()
	_refresh_inspector()
	_set_status("Opened %s" % name_str)

func _set_map_size(w: float, h: float) -> void:
	if _suppress_inspector:
		return
	if absf(w - MapConfig.width) < 0.5 and absf(h - MapConfig.height) < 0.5:
		return
	_push_undo()
	MapConfig.width = w
	MapConfig.height = h
	_schedule_rebuild()

func _sync_size_spins() -> void:
	_suppress_inspector = true
	if _width_spin:
		_width_spin.value = MapConfig.width
	if _height_spin:
		_height_spin.value = MapConfig.height
	_suppress_inspector = false

func _ensure_slot(slot: int) -> void:
	while MapConfig.player_starts.size() <= slot:
		var i: int = MapConfig.player_starts.size()
		MapConfig.player_starts.append({
			"slot": i, "corner": CORNERS[mini(i, 3)], "armies": [],
		})
	if not MapConfig.player_starts[slot].has("armies"):
		MapConfig.player_starts[slot]["armies"] = []

func _unique_cp_id(cp_type: String) -> String:
	var used := {}
	for cp in MapConfig.capture_points:
		used[str(cp.get("id", ""))] = true
	if not used.has(cp_type):
		return cp_type
	var n := 2
	while used.has("%s_%d" % [cp_type, n]):
		n += 1
	return "%s_%d" % [cp_type, n]

func _refresh_gizmos() -> void:
	if _gizmos == null:
		return
	for c in _gizmos.get_children():
		c.queue_free()
	for i in range(MapConfig.terrain_features.size()):
		var f: Dictionary = MapConfig.terrain_features[i]
		var ftype := str(f.get("type", ""))
		var selected: bool = str(_selection.get("kind", "")) in ["feature", "feature_vertex"] and int(_selection.get("index", -1)) == i
		if ftype == "hill":
			_add_marker(Vector2(float(f.get("x", 0.0)), float(f.get("y", 0.0))), Color(0.6, 0.4, 0.2), selected, "Hill")
		elif f.has("points"):
			var pts: Array = f.get("points", [])
			var col := Color(0.9, 0.7, 0.2) if ftype == "plateau_polygon" else Color(0.55, 0.3, 0.8)
			if ftype == "spline_ridge":
				col = Color(0.85, 0.45, 0.15)
			_add_polyline(pts, col)
			for pt in pts:
				_add_marker(Vector2(float(pt.get("x", 0.0)), float(pt.get("y", 0.0))), col, selected, ftype)
	for i in range(MapConfig.lakes.size()):
		var lake: Dictionary = MapConfig.lakes[i]
		var sel: bool = str(_selection.get("kind", "")) == "lake" and int(_selection.get("index", -1)) == i
		_add_marker(Vector2(float(lake.get("x", 0.0)), float(lake.get("y", 0.0))), Color(0.2, 0.7, 0.95), sel, "Lake")
	for i in range(MapConfig.capture_points.size()):
		var cp: Dictionary = MapConfig.capture_points[i]
		var sel: bool = str(_selection.get("kind", "")) == "capture" and int(_selection.get("index", -1)) == i
		_add_marker(Vector2(float(cp.get("x", 0.0)), float(cp.get("y", 0.0))), Color(0.95, 0.85, 0.2), sel, str(cp.get("id", "CP")))
	for s in range(MapConfig.player_starts.size()):
		var armies: Array = MapConfig.player_starts[s].get("armies", [])
		var col: Color = SLOT_COLORS[s % SLOT_COLORS.size()]
		for ai in range(armies.size()):
			var a: Dictionary = armies[ai]
			var sel: bool = str(_selection.get("kind", "")) == "army" and int(_selection.get("slot", -1)) == s and int(_selection.get("index", -1)) == ai
			_add_marker(Vector2(float(a.get("x", 0.0)), float(a.get("y", 0.0))), col, sel, "P%d" % s)
	for i in range(MapConfig.get_neutral_dragons().size()):
		var dg: Dictionary = MapConfig.get_neutral_dragons()[i]
		var sel: bool = str(_selection.get("kind", "")) == "dragon" and int(_selection.get("index", -1)) == i
		_add_marker(Vector2(float(dg.get("x", 0.0)), float(dg.get("y", 0.0))), Color(0.9, 0.15, 0.15), sel, "Dragon")
	for i in range(MapConfig.props.size()):
		var p: Dictionary = MapConfig.props[i]
		var sel: bool = str(_selection.get("kind", "")) == "prop" and int(_selection.get("index", -1)) == i
		_add_marker(Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))), Color(0.25, 0.7, 0.3), sel, str(p.get("kind", "prop")))
	if not _draft_points.is_empty():
		_add_polyline(_draft_points, Color.WHITE)
		for pt in _draft_points:
			_add_marker(Vector2(float(pt.get("x", 0.0)), float(pt.get("y", 0.0))), Color.WHITE, false, "")

func _add_marker(xz: Vector2, color: Color, selected: bool, label: String) -> void:
	var gy: float = 8.0
	if _world and _world.has_method("get_ground_height_at"):
		gy = _world.get_ground_height_at(xz.x, xz.y) + 8.0
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = GIZMO_R * (1.6 if selected else 1.0)
	mesh.height = mesh.radius * 2.0
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = Vector3(xz.x, gy, xz.y)
	_gizmos.add_child(mi)
	if label != "":
		var spr := Label3D.new()
		spr.text = label
		spr.font_size = 42
		spr.pixel_size = 0.18
		spr.position = Vector3(0, GIZMO_R + 6.0, 0)
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mi.add_child(spr)

func _add_polyline(pts: Array, color: Color) -> void:
	if pts.size() < 2:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	im.surface_set_color(color)
	for pt in pts:
		var x := float(pt.get("x", 0.0))
		var z := float(pt.get("y", 0.0))
		var gy: float = 10.0
		if _world and _world.has_method("get_ground_height_at"):
			gy = _world.get_ground_height_at(x, z) + 10.0
		im.surface_add_vertex(Vector3(x, gy, z))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mi.material_override = mat
	_gizmos.add_child(mi)

func _refresh_inspector() -> void:
	if _inspector == null:
		return
	for c in _inspector.get_children():
		c.queue_free()
	var head := Label.new()
	head.text = "Inspector"
	_inspector.add_child(head)
	_inspector.add_child(_spin_row("Hill width", 20, 4000, _hill_width, func(v): _hill_width = v))
	_inspector.add_child(_spin_row("Hill height", 1, 800, _hill_height, func(v): _hill_height = v))
	_inspector.add_child(_spin_row("Ridge width", 20, 4000, _ridge_width, func(v): _ridge_width = v))
	_inspector.add_child(_spin_row("Ridge height", 1, 800, _ridge_height, func(v): _ridge_height = v))
	_inspector.add_child(_spin_row("Plateau height", 1, 800, _poly_height, func(v): _poly_height = v))
	_inspector.add_child(_spin_row("Valley depth", 1, 800, _valley_depth, func(v): _valley_depth = v))
	_inspector.add_child(_spin_row("Poly falloff", 1, 800, _poly_falloff, func(v): _poly_falloff = v))
	_inspector.add_child(_spin_row("Lake rise", 1, 400, _lake_rise, func(v): _lake_rise = v))
	_inspector.add_child(_spin_row("Army slot", 0, 3, _army_slot, func(v): _army_slot = int(v)))
	_inspector.add_child(_spin_row("Army facing deg", -180, 180, rad_to_deg(_army_dir), func(v): _army_dir = deg_to_rad(v)))
	_inspector.add_child(_check_row("Horse", _army_horse, func(v): _army_horse = v))
	_inspector.add_child(_check_row("Spear", _army_spear, func(v): _army_spear = v))
	_inspector.add_child(_check_row("Bow", _army_bow, func(v): _army_bow = v))
	_inspector.add_child(_option_row("Capture type", CP_TYPES, CP_TYPES.find(_cp_type), func(i): _cp_type = CP_TYPES[i]))
	_inspector.add_child(_option_row("Dragon color", DRAGON_COLORS, DRAGON_COLORS.find(_dragon_color), func(i): _dragon_color = DRAGON_COLORS[i]))
	_scatter_count = int(MapConfig.get_vegetation().get("count", 0))
	_inspector.add_child(_spin_row("Random trees", 0, 200, _scatter_count, func(v):
		_scatter_count = int(v)
		var veg: Dictionary = MapConfig.vegetation.duplicate()
		veg["count"] = _scatter_count
		MapConfig.vegetation = veg
		_schedule_rebuild()
	))
	if _selection.is_empty():
		var hint := Label.new()
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "Select a marker to edit it. Delete removes it."
		_inspector.add_child(hint)
		return
	var sel_label := Label.new()
	sel_label.text = "Selected: %s" % str(_selection.get("kind", ""))
	_inspector.add_child(sel_label)
	_add_selection_fields()

func _add_selection_fields() -> void:
	var kind := str(_selection.get("kind", ""))
	match kind:
		"feature":
			var f: Dictionary = MapConfig.terrain_features[int(_selection.index)]
			var ftype := str(f.get("type", ""))
			if ftype == "hill":
				_inspector.add_child(_spin_row("base_width", 20, 4000, float(f.get("base_width", 0.0)), func(v):
					_set_feature_key("base_width", v)
				))
				_inspector.add_child(_spin_row("height", 1, 800, float(f.get("height", 0.0)), func(v):
					_set_feature_key("height", v)
				))
			elif ftype == "spline_ridge":
				_inspector.add_child(_spin_row("width", 20, 4000, float(f.get("width", 0.0)), func(v):
					_set_feature_key("width", v)
				))
				_inspector.add_child(_spin_row("height", 1, 800, float(f.get("height", 0.0)), func(v):
					_set_feature_key("height", v)
				))
			elif ftype == "plateau_polygon":
				_inspector.add_child(_spin_row("height", 1, 800, float(f.get("height", 0.0)), func(v):
					_set_feature_key("height", v)
				))
				_inspector.add_child(_spin_row("falloff", 1, 800, float(f.get("falloff", 0.0)), func(v):
					_set_feature_key("falloff", v)
				))
			elif ftype == "valley_polygon":
				_inspector.add_child(_spin_row("depth", 1, 800, float(f.get("depth", 0.0)), func(v):
					_set_feature_key("depth", v)
				))
				_inspector.add_child(_spin_row("falloff", 1, 800, float(f.get("falloff", 0.0)), func(v):
					_set_feature_key("falloff", v)
				))
		"lake":
			var lake: Dictionary = MapConfig.lakes[int(_selection.index)]
			_inspector.add_child(_spin_row("rise", 1, 400, float(lake.get("rise", 0.0)), func(v):
				var d: Dictionary = MapConfig.lakes[int(_selection.index)]
				d["rise"] = v
				MapConfig.lakes[int(_selection.index)] = d
				_schedule_rebuild()
			))
		"army":
			var armies: Array = MapConfig.player_starts[int(_selection.slot)].get("armies", [])
			var a: Dictionary = armies[int(_selection.index)]
			_inspector.add_child(_spin_row("facing deg", -180, 180, rad_to_deg(float(a.get("direction", 0.0))), func(v):
				_set_army_key("direction", deg_to_rad(v))
			))
			_inspector.add_child(_check_row("Horse", bool(a.get("horse", false)), func(v): _set_army_key("horse", v)))
			_inspector.add_child(_check_row("Spear", bool(a.get("spear", false)), func(v): _set_army_key("spear", v)))
			_inspector.add_child(_check_row("Bow", bool(a.get("bow", false)), func(v): _set_army_key("bow", v)))

func _set_feature_key(key: String, value) -> void:
	var f: Dictionary = MapConfig.terrain_features[int(_selection.index)]
	f[key] = value
	MapConfig.terrain_features[int(_selection.index)] = f
	_schedule_rebuild()

func _set_army_key(key: String, value) -> void:
	var armies: Array = MapConfig.player_starts[int(_selection.slot)].get("armies", [])
	var a: Dictionary = armies[int(_selection.index)]
	a[key] = value
	armies[int(_selection.index)] = a
	MapConfig.player_starts[int(_selection.slot)]["armies"] = armies
	_refresh_gizmos()

func _spin_row(label: String, mn: float, mx: float, val: float, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = 1
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(cb)
	row.add_child(s)
	return row

func _check_row(label: String, val: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = val
	c.toggled.connect(cb)
	return c

func _option_row(label: String, items: Array, selected: int, cb: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = label
	box.add_child(l)
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(maxi(selected, 0))
	o.item_selected.connect(cb)
	box.add_child(o)
	return box
