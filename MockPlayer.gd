extends Node
## JSON-driven automated player. Parses res://tests.json, filters events whose
## `action.player` matches this client's name, and executes the actions in order.
## Each step emits its event `marker` to the client's log so verify_test_logs.sh can find it.

enum Phase { WAIT_FOR_LOBBY, WAIT_FOR_WORLD, RUN_ACTIONS, DONE }

var _phase: int = Phase.WAIT_FOR_LOBBY
var _actions: Array = []         # Array of { marker, action }
var _cursor: int = 0
var _waiting: bool = false       # timers/async gate
var _world = null
var _lobby = null

# Capture point positions mirror World.gd._spawn_capture_points().
const CP_POSITIONS := {
	"Stables": Vector2(1280.0 * 0.39, 720.0 * 0.28),
	"Blacksmith": Vector2(1280.0 * 0.61, 720.0 * 0.69),
}

func _ready():
	print("MockPlayer: Automated testing active for '%s'" % GameState.local_player_name)
	_load_actions_for_this_player()

func _load_actions_for_this_player() -> void:
	var f := FileAccess.open("res://tests.json", FileAccess.READ)
	if f == null:
		push_error("MockPlayer: tests.json missing")
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("MockPlayer: tests.json did not parse to a dict")
		return
	var events: Array = parsed.get("events", [])
	var me: String = GameState.local_player_name
	for e in events:
		var act = e.get("action", null)
		if act == null:
			continue
		if str(act.get("player", "")) != me:
			continue
		_actions.append({"marker": e.get("marker", ""), "description": e.get("description", ""), "action": act})
	print("MockPlayer[%s]: loaded %d actions from tests.json" % [me, _actions.size()])

func _process(_delta):
	match _phase:
		Phase.WAIT_FOR_LOBBY:
			_check_lobby()
		Phase.WAIT_FOR_WORLD:
			_check_world()
		Phase.RUN_ACTIONS:
			if not _waiting:
				_run_next_action()
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
			_lobby = child
			_phase = Phase.RUN_ACTIONS
			print("MockPlayer: Lobby found; starting action sequence")
			return

func _check_world():
	var main = get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var level = main.get_node_or_null("Level")
	if level == null:
		return
	for child in level.get_children():
		if child.has_method("get_my_armies"):
			_world = child
			print("MockPlayer: World scene detected")
			if _phase == Phase.WAIT_FOR_WORLD:
				_phase = Phase.RUN_ACTIONS
			return

func _run_next_action() -> void:
	if _cursor >= _actions.size():
		_phase = Phase.DONE
		print("MockPlayer[%s]: all scripted actions complete" % GameState.local_player_name)
		return
	var entry: Dictionary = _actions[_cursor]
	var act: Dictionary = entry["action"]
	var t: String = str(act.get("type", ""))
	# Any action beyond press_ready needs the World scene live.
	if t != "press_ready" and _world == null:
		_phase = Phase.WAIT_FOR_WORLD
		_waiting = true
		_check_world()
		if _world != null:
			_phase = Phase.RUN_ACTIONS
			_waiting = false
			# fall through, re-run
		else:
			# poll next frame
			get_tree().create_timer(0.2).timeout.connect(_resume)
			return
	match t:
		"press_ready": _do_press_ready(entry)
		"select_army": _do_select_army(entry)
		"move_army_to_cp": _do_move_army_to_cp(entry)
		"set_all_aggressive": _do_set_all_aggressive(entry)
		_:
			push_warning("MockPlayer: unknown action type '%s'" % t)
			_advance()

func _resume() -> void:
	_waiting = false

func _advance() -> void:
	_cursor += 1

func _do_press_ready(entry: Dictionary) -> void:
	if _lobby == null or not _lobby.has_method("_on_ready_pressed"):
		# Wait a frame and retry.
		_waiting = true
		get_tree().create_timer(0.2).timeout.connect(_resume)
		return
	# The Lobby prints its own ready marker. Small gate then press.
	_waiting = true
	get_tree().create_timer(1.0).timeout.connect(func():
		_lobby._on_ready_pressed()
		print("MockPlayer[%s]: pressed Ready" % GameState.local_player_name)
		_advance()
		# After pressing ready, move into world-wait phase so subsequent actions see _world.
		_phase = Phase.WAIT_FOR_WORLD
		# Resume world-polling each frame; _run_next_action will re-check.
		_waiting = false
	)

func _my_armies() -> Array:
	if _world == null:
		return []
	return _world.get_my_armies()

func _do_select_army(entry: Dictionary) -> void:
	var act: Dictionary = entry["action"]
	var idx: int = int(act.get("army_index", 0))
	var armies := _my_armies()
	if idx >= armies.size():
		# Retry shortly; armies may still be spawning.
		_waiting = true
		get_tree().create_timer(0.3).timeout.connect(_resume)
		return
	# Deselect all first.
	for a in armies:
		if a.is_selected:
			a.deselect()
	armies[idx].select()
	print("%s: MockPlayer[%s] selected army '%s' (index=%d)" % [
		entry.get("marker", ""), GameState.local_player_name, armies[idx].army_id, idx
	])
	_advance()

func _do_move_army_to_cp(entry: Dictionary) -> void:
	var act: Dictionary = entry["action"]
	var idx: int = int(act.get("army_index", 0))
	var cp_id: String = str(act.get("cp_id", ""))
	if not CP_POSITIONS.has(cp_id):
		push_error("MockPlayer: unknown cp_id '%s'" % cp_id)
		_advance()
		return
	var target: Vector2 = CP_POSITIONS[cp_id]
	var armies := _my_armies()
	if idx >= armies.size():
		_waiting = true
		get_tree().create_timer(0.3).timeout.connect(_resume)
		return
	var aid: String = armies[idx].army_id
	_world.rpc_id(1, "_server_move_army", aid, target)
	print("%s: MockPlayer[%s] moving army '%s' to %s at (%d,%d)" % [
		entry.get("marker", ""), GameState.local_player_name, aid, cp_id, int(target.x), int(target.y)
	])
	_advance()

func _do_set_all_aggressive(entry: Dictionary) -> void:
	var act: Dictionary = entry["action"]
	var wait_cp: String = str(act.get("wait_for_controls_cp", ""))
	var me: String = GameState.local_player_name
	if wait_cp != "":
		var owner = GameState.capture_points.get(wait_cp, "")
		if str(owner) != me:
			# Not controlled yet, poll again.
			_waiting = true
			get_tree().create_timer(0.5).timeout.connect(_resume)
			return
	_world.rpc_id(1, "_server_set_all_armies_aggressive")
	print("%s: MockPlayer[%s] requested all-armies aggressive (after controlling %s)" % [
		entry.get("marker", ""), me, wait_cp
	])
	_advance()
