extends SceneTree
## Corner-anchored RMB drag layout (GroupFormation + leading grid metadata).
## Run: godot --headless --path . -s test_group_formation_drag.gd

const GroupFormation := preload("res://GroupFormation.gd")
const Formation := preload("res://sim/FormationController.gd")

const EPS := 0.05

func _init() -> void:
	call_deferred("_begin")

func _check(ok: bool, msg: String, fails: Array[String]) -> void:
	if not ok:
		fails.append(msg)

func _begin() -> void:
	print("TEST_GROUP_FORMATION_DRAG_BEGIN")
	var fails: Array[String] = []
	var start := Vector2(100.0, 200.0)
	var end := Vector2(200.0, 200.0)
	var n := 20
	var sp := Formation.FOOT_SPACING
	var layout: Dictionary = GroupFormation.drag_layout(start, end, n, sp)
	var pos: Array = layout["positions"]
	_check(pos.size() == n, "expected %d positions got %d" % [n, pos.size()], fails)
	if pos.size() >= 1:
		_check(start.distance_to(pos[0]) < EPS, "first slot should be at press", fails)
	var n_wide: int = layout["cols"]
	if n_wide > 1:
		var last_front_idx: int = n_wide - 1
		_check(end.distance_to(pos[last_front_idx]) < EPS, "last front file should be at release", fails)
	# Zero-length drag: single file depth stack at start
	var stack: Dictionary = GroupFormation.drag_layout(start, start, 5, sp)
	var stack_pos: Array = stack["positions"]
	_check(stack["cols"] == 1, "zero drag should be one file wide", fails)
	for p in stack_pos:
		_check(start.distance_to(p) < sp * 4.5 + EPS, "depth stack should stay near press", fails)
	var d0: float = stack_pos[0].distance_to(stack_pos[mini(1, stack_pos.size() - 1)])
	if stack_pos.size() > 1:
		_check(d0 >= sp * 0.9, "depth ranks should be separated", fails)
	# Two-army sub-segments
	var segs: Array = GroupFormation.split_segments(start, end, 2, [sp, sp])
	_check(segs.size() == 2, "expected two segments", fails)
	if segs.size() == 2:
		var s0: Vector2 = segs[0]["start"]
		var e0: Vector2 = segs[0]["end"]
		var s1: Vector2 = segs[1]["start"]
		var e1: Vector2 = segs[1]["end"]
		var l0: Dictionary = GroupFormation.drag_layout(s0, e0, 10, sp)
		var l1: Dictionary = GroupFormation.drag_layout(s1, e1, 10, sp)
		_check(s0.distance_to(l0["positions"][0]) < EPS, "army0 file1 at its segment start", fails)
		_check(s1.distance_to(l1["positions"][0]) < EPS, "army1 file1 at its segment start", fails)
		var min_gap: float = GroupFormation.boundary_gap(sp, sp)
		_check(e0.distance_to(s1) >= min_gap - EPS, "segment gap along drag", fails)
	# Leading grid matches layout world positions when anchor = start
	var fc := Formation.new()
	fc.set_drag_layout(true, 100.0, int(layout["cols"]))
	fc.set_rows(int(layout["rows"]))
	var offs: PackedVector2Array = fc.slot_offsets(n)
	fc.direction = layout["direction"]
	fc.anchor = start
	for i in range(mini(n, offs.size())):
		var w: Vector2 = fc.anchor + offs[i].rotated(fc.direction)
		_check(w.distance_to(pos[i]) < EPS, "leading offset mismatch slot %d" % i, fails)
	if fails.is_empty():
		print("TEST_GROUP_FORMATION_DRAG_PASS")
		quit(0)
	else:
		for f in fails:
			print("TEST_GROUP_FORMATION_DRAG_FAIL: ", f)
		quit(1)
