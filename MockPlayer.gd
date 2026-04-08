extends Node

const _GroupFormation = preload("res://GroupFormation.gd")

enum State {
	WAIT_FOR_LOBBY,
	IN_LOBBY,
	WAIT_FOR_WORLD,
	SELECT_ARMY_1,
	MOVE_ARMY_1,
	SELECT_ARMY_2,
	MOVE_ARMY_2,
	GROUP_FORMATION_TEST,
	WAIT_FOR_COMBAT,
	DONE,
	# Events 2
	E2_P1_MOVE_1_STABLES,
	E2_P1_MOVE_2_BLACKSMITH,
	E2_P1_MOVE_1_BLACKSMITH,
	E2_P1_TRY_DRAFT,
	E2_P1_WAIT_RESOURCES,
	E2_P1_DRAFT,
	E2_P1_MOVE_DRAFTED_STABLES,
	E2_P1_SEND_ALL_BLACKSMITH,
	E2_P2_WAIT,
	E2_P2_MOVE_STABLES,
	E2_P2_SEND_ALL_BLACKSMITH
}

var state := State.WAIT_FOR_LOBBY
var timer := 0.0
var world = null
var my_armies: Array = []

func _ready():
	print("MockPlayer: Automated testing active for '%s' (events=%d)" % [GameState.local_player_name, GameState.test_events])

func _process(delta):
	timer += delta
	match state:
		State.WAIT_FOR_LOBBY:
			_check_lobby()
		State.WAIT_FOR_WORLD:
			_check_world()
		State.E2_P1_WAIT_RESOURCES:
			_e2_p1_wait_resources()
		State.E2_P2_WAIT:
			_e2_p2_wait()
		_:
			pass

func _check_lobby():
	var main = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var ui = main.get_node_or_null("UI")
	if ui == null:
		return
	for child in ui.get_children():
		if child is Control and child.has_method("_on_ready_pressed"):
			state = State.IN_LOBBY
			timer = 0.0
			print("MockPlayer: Lobby found, will press ready in 1s")
			get_tree().create_timer(1.0).timeout.connect(_press_ready.bind(child))
			return

func _press_ready(lobby):
	if lobby and lobby.has_method("_on_ready_pressed"):
		lobby._on_ready_pressed()
		print("MockPlayer: Pressed ready")
		state = State.WAIT_FOR_WORLD
		timer = 0.0

func _check_world():
	var main = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var level = main.get_node_or_null("Level")
	if level == null:
		return
	for child in level.get_children():
		if child.has_method("get_my_armies"):
			world = child
			print("MockPlayer: World scene detected")
			timer = 0.0
			if GameState.test_events == 2:
				if GameState.local_player_name == "A":
					state = State.E2_P1_MOVE_1_STABLES
					get_tree().create_timer(1.5).timeout.connect(_e2_p1_start)
				else:
					state = State.E2_P2_WAIT
					timer = 0.0
			else:
				state = State.SELECT_ARMY_1
				get_tree().create_timer(1.5).timeout.connect(_do_select_army_1)
			return

func _do_select_army_1():
	my_armies = world.get_my_armies()
	if my_armies.size() == 0:
		print("MockPlayer: ERROR - no armies found!")
		state = State.DONE
		return

	my_armies[0].select()
	print("MockPlayer: Selected army '%s'" % my_armies[0].army_id)
	state = State.MOVE_ARMY_1
	get_tree().create_timer(0.5).timeout.connect(_do_move_army_1)

func _do_move_army_1():
	if my_armies.size() == 0 or my_armies[0].is_routed:
		state = State.DONE
		return

	var target = Vector2(520, 220) if GameState.local_player_name == "A" else Vector2(530, 230)
	var marker = "TEST_009_MOVE" if GameState.local_player_name == "A" else "TEST_009_MOVE_B"
	print("%s: MockPlayer moving army '%s' to (%d,%d)" % [marker, my_armies[0].army_id, int(target.x), int(target.y)])
	world.rpc_id(1, "_server_move_army", my_armies[0].army_id, target)

	state = State.SELECT_ARMY_2
	get_tree().create_timer(0.5).timeout.connect(_do_select_army_2)

func _do_select_army_2():
	my_armies = world.get_my_armies()
	if my_armies.size() < 2:
		print("MockPlayer: Only %d armies available, skipping second" % my_armies.size())
		state = State.WAIT_FOR_COMBAT
		return

	my_armies[0].deselect()
	my_armies[1].select()
	print("MockPlayer: Selected army '%s'" % my_armies[1].army_id)
	state = State.MOVE_ARMY_2
	get_tree().create_timer(0.5).timeout.connect(_do_move_army_2)

func _do_move_army_2():
	my_armies = world.get_my_armies()
	if my_armies.size() < 2 or my_armies[1].is_routed:
		state = State.WAIT_FOR_COMBAT
		return

	var target = Vector2(760, 480) if GameState.local_player_name == "A" else Vector2(770, 490)
	var marker = "TEST_009_MOVE" if GameState.local_player_name == "A" else "TEST_009_MOVE_B"
	print("%s: MockPlayer moving army '%s' to (%d,%d)" % [marker, my_armies[1].army_id, int(target.x), int(target.y)])
	world.rpc_id(1, "_server_move_army", my_armies[1].army_id, target)

	state = State.GROUP_FORMATION_TEST
	get_tree().create_timer(0.5).timeout.connect(_test_group_formation)

func _test_group_formation():
	## Exercises `_server_move_group_formation` (merged line layout); see events.md step 9c.
	my_armies = world.get_my_armies()
	if my_armies.size() < 2:
		state = State.WAIT_FOR_COMBAT
		return
	var units: Array = _GroupFormation.collect_soldiers_sorted([my_armies[0], my_armies[1]])
	if units.is_empty():
		state = State.WAIT_FOR_COMBAT
		return
	var line_start := Vector2(400, 200)
	var line_end := Vector2(520, 300)
	var positions: Array = _GroupFormation.compute_line_formation(line_start, line_end, units.size())
	var payload: Array = []
	for i in range(units.size()):
		var p: Vector2 = positions[i]
		p.x = clampf(p.x, 0, 1280)
		p.y = clampf(p.y, 0, 720)
		payload.append({"n": str(units[i].name), "x": p.x, "y": p.y})
	print("TEST_GROUP_FORMATION: client units=%d" % payload.size())
	world.rpc_id(1, "_server_move_group_formation", payload)
	state = State.WAIT_FOR_COMBAT

# --- Events 2: P1 (A) ---
func _e2_p1_start():
	my_armies = world.get_my_armies()
	if my_armies.size() < 2:
		state = State.DONE
		return
	my_armies[0].select()
	print("TEST_009_MOVE: MockPlayer moving army '%s' to Stables (520,220)" % my_armies[0].army_id)
	world.rpc_id(1, "_server_move_army", my_armies[0].army_id, Vector2(520, 220))
	state = State.E2_P1_MOVE_2_BLACKSMITH
	get_tree().create_timer(2.0).timeout.connect(_e2_p1_move_2_blacksmith)

func _e2_p1_move_2_blacksmith():
	my_armies = world.get_my_armies()
	if my_armies.size() < 2:
		state = State.DONE
		return
	my_armies[0].deselect()
	my_armies[1].select()
	print("TEST_009_MOVE: MockPlayer moving army '%s' to Blacksmith (760,480)" % my_armies[1].army_id)
	world.rpc_id(1, "_server_move_army", my_armies[1].army_id, Vector2(760, 480))
	state = State.E2_P1_MOVE_1_BLACKSMITH
	get_tree().create_timer(4.0).timeout.connect(_e2_p1_move_1_blacksmith)

func _e2_p1_move_1_blacksmith():
	my_armies = world.get_my_armies()
	if my_armies.size() < 2:
		state = State.DONE
		return
	my_armies[1].deselect()
	my_armies[0].select()
	world.rpc_id(1, "_server_move_army", my_armies[0].army_id, Vector2(760, 480))
	state = State.E2_P1_TRY_DRAFT
	get_tree().create_timer(2.0).timeout.connect(_e2_p1_try_draft)

func _e2_p1_try_draft():
	world.request_draft_from_mock(true, true)
	print("MockPlayer: Requested draft (horse+spear) - expect TEST_DRAFT_FAIL")
	state = State.E2_P1_WAIT_RESOURCES
	timer = 0.0

func _e2_p1_wait_resources():
	var my_id = multiplayer.get_unique_id()
	var res = GameState.resources.get(my_id, GameState.resources.get(str(my_id), {}))
	if res is Dictionary:
		var h = res.get("horses", 0)
		var s = res.get("spears", 0)
		if h >= 10 and s >= 10:
			state = State.E2_P1_DRAFT
			get_tree().create_timer(0.5).timeout.connect(_e2_p1_draft)

func _e2_p1_draft():
	world.request_draft_from_mock(true, true)
	print("MockPlayer: Requested draft (horse+spear) - expect TEST_DRAFT_SUCCESS")
	state = State.E2_P1_MOVE_DRAFTED_STABLES
	get_tree().create_timer(8.0).timeout.connect(_e2_p1_move_drafted_stables)

func _e2_p1_move_drafted_stables():
	my_armies = world.get_my_armies()
	if my_armies.size() < 3:
		state = State.E2_P1_SEND_ALL_BLACKSMITH
		get_tree().create_timer(5.0).timeout.connect(_e2_p1_send_all_blacksmith)
		return
	my_armies[2].select()
	print("MockPlayer: Moving drafted army '%s' to Stables" % my_armies[2].army_id)
	world.rpc_id(1, "_server_move_army", my_armies[2].army_id, Vector2(520, 220))
	state = State.E2_P1_SEND_ALL_BLACKSMITH
	get_tree().create_timer(25.0).timeout.connect(_e2_p1_send_all_blacksmith)

func _e2_p1_send_all_blacksmith():
	my_armies = world.get_my_armies()
	var target = Vector2(760, 480)
	for a in my_armies:
		if a and is_instance_valid(a) and not a.is_routed:
			world.rpc_id(1, "_server_move_army", a.army_id, target)
	state = State.DONE

# --- Events 2: P2 (B) ---
func _e2_p2_wait():
	if timer < 22.0:
		return
	state = State.E2_P2_MOVE_STABLES
	get_tree().create_timer(0.5).timeout.connect(_e2_p2_move_stables)

func _e2_p2_move_stables():
	my_armies = world.get_my_armies()
	if my_armies.size() == 0:
		state = State.E2_P2_SEND_ALL_BLACKSMITH
		get_tree().create_timer(35.0).timeout.connect(_e2_p2_send_all_blacksmith)
		return
	my_armies[0].select()
	print("TEST_009_MOVE_B: MockPlayer moving army '%s' to Stables (530,230)" % my_armies[0].army_id)
	world.rpc_id(1, "_server_move_army", my_armies[0].army_id, Vector2(530, 230))
	state = State.E2_P2_SEND_ALL_BLACKSMITH
	get_tree().create_timer(45.0).timeout.connect(_e2_p2_send_all_blacksmith)

func _e2_p2_send_all_blacksmith():
	my_armies = world.get_my_armies()
	var target = Vector2(770, 490)
	for a in my_armies:
		if a and is_instance_valid(a) and not a.is_routed:
			world.rpc_id(1, "_server_move_army", a.army_id, target)
	state = State.DONE
