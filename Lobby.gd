extends Control

@onready var player_list: VBoxContainer = $VBoxContainer/PlayerList
@onready var ready_button: Button = $VBoxContainer/ReadyButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var name_edit: LineEdit = $VBoxContainer/NameEdit
@onready var color_box_container: HBoxContainer = $VBoxContainer/ColorBoxContainer

var local_ready := false
var color_boxes: Array = []

func _ready():
	if name_edit:
		name_edit.text = GameState.local_player_name if GameState.local_player_name else "Unknown Player"
	_build_color_boxes()
	ready_button.pressed.connect(_on_ready_pressed)
	_update_ui()

	if multiplayer.is_server():
		print("Lobby: Server waiting for players...")

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
		var marker = "TEST_004" if GameState.local_player_name == "A" else "TEST_005"
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
		var marker = "TEST_004" if name_str == "A" else "TEST_005"
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
	print("TEST_006: All players ready, starting match!")
	rpc("_start_match")
	_start_match()

@rpc("authority", "reliable")
func _start_match():
	print("TEST_006: Match starting, loading World scene")
	var main = get_tree().root.get_node("Main")
	main.load_world()
