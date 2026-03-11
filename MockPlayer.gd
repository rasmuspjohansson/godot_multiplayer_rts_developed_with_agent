extends Node

enum State {
	WAIT_FOR_LOBBY,
	IN_LOBBY,
	WAIT_FOR_WORLD,
	SELECT_ARMY_1,
	MOVE_ARMY_1,
	SELECT_ARMY_2,
	MOVE_ARMY_2,
	WAIT_FOR_COMBAT,
	DONE
}

var state := State.WAIT_FOR_LOBBY
var timer := 0.0
var world = null
var my_armies: Array = []

func _ready():
	print("MockPlayer: Automated testing active for '%s'" % GameState.local_player_name)

func _process(delta):
	timer += delta
	match state:
		State.WAIT_FOR_LOBBY:
			_check_lobby()
		State.WAIT_FOR_WORLD:
			_check_world()
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
			state = State.SELECT_ARMY_1
			timer = 0.0
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

	state = State.WAIT_FOR_COMBAT
