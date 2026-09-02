extends Control

@onready var player_list: VBoxContainer = $VBoxContainer/PlayerList
@onready var ready_button: Button = $VBoxContainer/ReadyButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var name_edit: LineEdit = $VBoxContainer/NameEdit
@onready var color_box_container: HBoxContainer = $VBoxContainer/ColorBoxContainer

var local_ready := false
var color_boxes: Array = []
var _map_option: OptionButton
var _updating_map_ui := false

func _ready():
	if name_edit:
		name_edit.text = GameState.local_player_name if GameState.local_player_name else "Unknown Player"
	_build_map_picker()
	_build_color_boxes()
	ready_button.pressed.connect(_on_ready_pressed)
	_update_ui()

	if multiplayer.is_server():
		if GameState.selected_map == "":
			GameState.selected_map = MapConfig.map_size
		print("Lobby: Server waiting for players...")
		broadcast_selected_map()
	else:
		rpc_id(1, "request_selected_map")

func _on_ready_pressed():
	if name_edit:
		GameState.local_player_name = name_edit.text.strip_edges() if name_edit.text.strip_edges() else "Unknown Player"
	local_ready = !local_ready
	ready_button.text = "Not Ready" if local_ready else "Ready"
	var my_id = multiplayer.get_unique_id()
	var pname = GameState.local_player_name

	if multiplayer.is_server():
		_receive_ready.call(local_ready, pname)
	else:
		rpc_id(1, "_receive_ready", local_ready, pname)
		var marker = "TEST_A_READY" if GameState.local_player_name == "A" else "TEST_B_READY"
		if local_ready:
			print("%s: %s pressed ready" % [marker, GameState.local_player_name])

@rpc("any_peer", "reliable")
func _receive_ready(is_ready: bool, pname: String = ""):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	if sender_id in GameState.players:
		if pname != "":
			GameState.players[sender_id]["name"] = pname
		GameState.players[sender_id]["ready"] = is_ready
		var name_str = GameState.players[sender_id]["name"]
		var marker = "TEST_A_READY" if name_str == "A" else "TEST_B_READY"
		print("%s: Server received ready=%s from '%s' (id=%d)" % [marker, is_ready, name_str, sender_id])
		rpc("_sync_players", GameState.players)
		_check_all_ready()

@rpc("authority", "reliable")
func _sync_players(players: Dictionary):
	GameState.players = players
	_update_ui()

func _build_color_boxes():
	for child in color_box_container.get_children():
		child.queue_free()
	color_boxes.clear()
	for i in range(GameState.PLAYER_COLORS.size()):
		var box = ColorRect.new()
		box.custom_minimum_size = Vector2(32, 32)
		box.color = GameState.PLAYER_COLORS[i]
		box.set_meta("color_index", i)
		box.gui_input.connect(_on_color_box_gui_input.bind(i))
		color_box_container.add_child(box)
		color_boxes.append(box)

func _on_color_box_gui_input(event: InputEvent, index: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_color_box_clicked(index)

func _on_color_box_clicked(index: int):
	if multiplayer.is_server():
		return
	get_tree().root.get_node("Main").rpc_id(1, "set_my_color", index)

func _update_ui():
	for child in player_list.get_children():
		child.queue_free()

	var my_id = multiplayer.get_unique_id()
	var my_color_index = GameState.players.get(my_id, {}).get("color_index", 0)
	for i in range(color_boxes.size()):
		var box = color_boxes[i]
		if not is_instance_valid(box):
			continue
		var taken_by_other = false
		for pid in GameState.players:
			if pid != my_id and GameState.players[pid].get("color_index", 0) == i:
				taken_by_other = true
				break
		if taken_by_other:
			box.modulate = Color(0.4, 0.4, 0.4)
		elif i == my_color_index:
			box.modulate = Color(1.2, 1.2, 1.2)
		else:
			box.modulate = Color.WHITE

	for id in GameState.players:
		var info = GameState.players[id]
		var lbl = Label.new()
		var ready_str = "[READY]" if info.get("ready", false) else "[NOT READY]"
		lbl.text = "%s %s" % [info.get("name", "???"), ready_str]
		player_list.add_child(lbl)

	if multiplayer.is_server():
		status_label.text = "Server - %d player(s) connected" % GameState.players.size()
	else:
		status_label.text = "Waiting for all players to ready up..."

func _check_all_ready():
	if GameState.players.size() < 2:
		return
	for id in GameState.players:
		if not GameState.players[id].get("ready", false):
			return
	print("TEST_GAME_START: All players ready, starting match!")
	rpc("_start_match")
	_start_match()

func _build_map_picker() -> void:
	var box: VBoxContainer = $VBoxContainer
	var map_label := Label.new()
	map_label.text = "Map:"
	var ready_idx := ready_button.get_index()
	box.add_child(map_label)
	box.move_child(map_label, ready_idx)
	_map_option = OptionButton.new()
	_map_option.item_selected.connect(_on_map_item_selected)
	box.add_child(_map_option)
	box.move_child(_map_option, ready_idx + 1)
	_refill_map_option()

func _refill_map_option() -> void:
	if _map_option == null:
		return
	_updating_map_ui = true
	_map_option.clear()
	var names := MapConfig.list_maps()
	var current := GameState.selected_map if GameState.selected_map != "" else MapConfig.map_size
	var sel := 0
	for i in range(names.size()):
		_map_option.add_item(names[i])
		if names[i] == current:
			sel = i
	if names.size() > 0:
		_map_option.select(sel)
	_updating_map_ui = false

func _on_map_item_selected(idx: int) -> void:
	if _updating_map_ui or _map_option == null:
		return
	var name_str := _map_option.get_item_text(idx)
	if multiplayer.is_server():
		_apply_selected_map(name_str)
	else:
		rpc_id(1, "set_selected_map", name_str)

@rpc("any_peer", "reliable")
func request_selected_map() -> void:
	if not multiplayer.is_server():
		return
	var sid := multiplayer.get_remote_sender_id()
	rpc_id(sid, "_sync_selected_map", GameState.selected_map)

@rpc("any_peer", "reliable")
func set_selected_map(name_str: String) -> void:
	if not multiplayer.is_server():
		return
	_apply_selected_map(name_str)

func _apply_selected_map(name_str: String) -> void:
	var names := MapConfig.list_maps()
	var allowed := false
	for n in names:
		if n == name_str:
			allowed = true
			break
	if not allowed:
		return
	GameState.selected_map = name_str
	for pid in GameState.players:
		GameState.players[pid]["ready"] = false
	print("TEST_MAP_SELECTED: %s" % name_str)
	broadcast_selected_map()
	rpc("_sync_players", GameState.players)
	_update_ui()

func broadcast_selected_map() -> void:
	if not multiplayer.is_server():
		return
	rpc("_sync_selected_map", GameState.selected_map)

@rpc("authority", "call_local", "reliable")
func _sync_selected_map(name_str: String) -> void:
	GameState.selected_map = name_str
	local_ready = false
	if ready_button:
		ready_button.text = "Ready"
	_refill_map_option()

@rpc("authority", "reliable")
func _start_match():
	print("TEST_GAME_START: Match starting, loading World scene")
	var map_name := GameState.selected_map if GameState.selected_map != "" else MapConfig.map_size
	MapConfig.reload(map_name)
	var main = get_tree().root.get_node("Main")
	main.load_world()
