extends Node2D

const PORT = 8910
const MAX_CLIENTS = 4

var is_server := false
var is_client := false
var player_name := ""
var auto_test := false
var _server_host := "localhost"

func _get_server_host(args: Array) -> String:
	for i in range(args.size()):
		var a = args[i]
		if a.begins_with("--host="):
			return a.split("=")[1]
		if a == "--host" and i + 1 < args.size():
			return args[i + 1]
	if OS.has_environment("GODOT_SERVER_HOST"):
		return OS.get_environment("GODOT_SERVER_HOST")
	return "localhost"

func _ready():
	var args = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	print("Args: ", args)
	auto_test = "--auto-test" in args
	for i in range(args.size()):
		var a = args[i]
		if a.begins_with("--events="):
			GameState.test_events = int(a.split("=")[1])
			break
		if a == "--events" and i + 1 < args.size():
			GameState.test_events = int(args[i + 1])
			break
	if OS.has_environment("GODOT_TEST_EVENTS"):
		GameState.test_events = int(OS.get_environment("GODOT_TEST_EVENTS"))
	var proj_path = str(ProjectSettings.globalize_path("res://"))
	if not proj_path.ends_with("/"):
		proj_path += "/"
	var test_events_path = proj_path + ".test_events"
	if FileAccess.file_exists(test_events_path):
		var f = FileAccess.open(test_events_path, FileAccess.READ)
		if f:
			var s = f.get_as_text().strip_edges()
			f.close()
			if s.is_valid_int():
				GameState.test_events = int(s)

	GameState.use_3d = "--3d" in args
	if "--server" in args:
		_start_server()
	elif "--client" in args:
		for a in args:
			if a.begins_with("--name="):
				player_name = a.split("=")[1]
				break
		if player_name == "":
			player_name = "Unknown Player"
		GameState.local_player_name = player_name
		GameState.is_auto_test = auto_test
		_server_host = _get_server_host(args)
		_start_client()
	else:
		print("ERROR: Pass --server or --client")
		get_tree().quit()

func _start_server():
	is_server = true
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		print("ERROR: Failed to create server: ", err)
		get_tree().quit()
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("TEST_001: Dedicated server started on port %d" % PORT)
	_load_lobby()

func _start_client():
	is_client = true
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(_server_host, PORT)
	if err != OK:
		print("ERROR: Failed to connect to server: ", err)
		get_tree().quit()
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	print("Connecting to server as '%s' at %s:%d..." % [player_name, _server_host, PORT])

func _on_connected_to_server():
	var marker = "TEST_002" if player_name == "A" else "TEST_003"
	print("%s: Connected to server (peer_id=%d, name=%s)" % [marker, multiplayer.get_unique_id(), player_name])
	rpc_id(1, "register_player", player_name)
	_load_lobby()
	if auto_test:
		var mock = preload("res://MockPlayer.gd").new()
		mock.name = "MockPlayer"
		add_child(mock)

func _on_connection_failed():
	print("ERROR: Connection to server failed")
	get_tree().quit()

func _on_server_disconnected():
	print("TEST_012: Server disconnected, quitting")
	get_tree().quit()

var _peer_connect_count := 0

func _on_peer_connected(id: int):
	_peer_connect_count += 1
	if _peer_connect_count == 1:
		print("TEST_002: Peer connected (first client): %d" % id)
	else:
		print("TEST_003: Peer connected (client #%d): %d" % [_peer_connect_count, id])

func _on_peer_disconnected(id: int):
	print("TEST_012: Peer disconnected: %d" % id)
	if is_server:
		GameState.players.erase(id)

func _get_first_available_color() -> int:
	var used := []
	for pid in GameState.players:
		var idx = GameState.players[pid].get("color_index", 0)
		if idx >= 0 and idx < GameState.PLAYER_COLORS.size() and idx not in used:
			used.append(idx)
	for i in range(GameState.PLAYER_COLORS.size()):
		if i not in used:
			return i
	return 0

@rpc("any_peer", "reliable")
func register_player(p_name: String):
	var sender_id = multiplayer.get_remote_sender_id()
	var color_index = _get_first_available_color()
	GameState.players[sender_id] = {"name": p_name, "ready": false, "color_index": color_index}
	print("Server: Player '%s' registered (id=%d) color=%d" % [p_name, sender_id, color_index])
	rpc("_sync_players_from_main", GameState.players)

@rpc("any_peer", "reliable")
func set_my_color(color_index: int):
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id not in GameState.players:
		return
	if color_index < 0 or color_index >= GameState.PLAYER_COLORS.size():
		return
	for pid in GameState.players:
		if pid != sender_id and GameState.players[pid].get("color_index", 0) == color_index:
			return
	GameState.players[sender_id]["color_index"] = color_index
	rpc("_sync_players_from_main", GameState.players)

@rpc("any_peer", "reliable")
func update_player_name(p_name: String):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id in GameState.players:
		GameState.players[sender_id]["name"] = p_name
		print("Server: Player name updated to '%s' (id=%d)" % [p_name, sender_id])
		rpc("_sync_players_from_main", GameState.players)

@rpc("authority", "reliable")
func _sync_players_from_main(players: Dictionary):
	GameState.players = players
	var lobby = get_node_or_null("UI/Lobby")
	if lobby and lobby.has_method("_update_ui"):
		lobby._update_ui()

func _clear_scenes():
	for child in $Level.get_children():
		child.queue_free()
	for child in $UI.get_children():
		child.queue_free()

func _load_lobby():
	var lobby = load("res://Lobby.tscn").instantiate()
	$UI.add_child(lobby)

func load_world():
	_clear_scenes()
	var scene_path = "res://World3D.tscn" if not multiplayer.is_server() and GameState.use_3d else "res://World.tscn"
	var world = load(scene_path).instantiate()
	$Level.add_child(world)

func load_game_over(winner_name: String):
	_clear_scenes()
	var go = load("res://GameOver.tscn").instantiate()
	go.winner_name = winner_name
	$UI.add_child(go)
