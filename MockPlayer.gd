extends Node

enum State {
	WAIT_FOR_LOBBY,
	IN_LOBBY,
	WAIT_FOR_WORLD,
	SELECT_UNIT,
	SEND_MOVE,
	WAIT_FOR_COMBAT,
	DONE
}

var state := State.WAIT_FOR_LOBBY
var timer := 0.0
var my_unit = null

func _ready():
	print("MockPlayer: Automated testing active for '%s'" % GameState.local_player_name)

func _process(delta):
	timer += delta
	match state:
		State.WAIT_FOR_LOBBY:
			_check_lobby()
		State.IN_LOBBY:
			pass
		State.WAIT_FOR_WORLD:
			_check_world()
		State.SELECT_UNIT:
			_do_select()
		State.SEND_MOVE:
			_do_move()
		State.WAIT_FOR_COMBAT:
			pass
		State.DONE:
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
		if child.has_method("get_my_unit"):
			print("MockPlayer: World scene detected")
			state = State.SELECT_UNIT
			timer = 0.0
			get_tree().create_timer(1.0).timeout.connect(_delayed_select.bind(child))
			return

func _delayed_select(world):
	_do_select_in_world(world)

func _do_select():
	pass

func _do_select_in_world(world):
	my_unit = world.get_my_unit()
	if my_unit == null:
		print("MockPlayer: ERROR - Could not find my unit!")
		state = State.DONE
		return

	my_unit.select()
	print("MockPlayer: Selected unit '%s'" % my_unit.owner_name)
	state = State.SEND_MOVE
	timer = 0.0
	get_tree().create_timer(0.5).timeout.connect(_do_move_cmd)

func _do_move_cmd():
	_do_move()

func _do_move():
	if my_unit == null:
		return
	if state != State.SEND_MOVE:
		return

	var target = Vector2(300, 300)
	var marker = "TEST_009_MOVE" if GameState.local_player_name == "A" else "TEST_009_MOVE_B"
	print("%s: MockPlayer issuing move to (%d,%d)" % [marker, int(target.x), int(target.y)])

	my_unit.rpc_id(1, "request_move", target)
	state = State.WAIT_FOR_COMBAT
	timer = 0.0
