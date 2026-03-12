extends Node2D

const PORT = 8910
const MAX_CLIENTS = 4

var is_server := false
var is_client := false
var player_name := ""
var auto_test := false

func _ready():
	var args = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	print("Args: ", args)
	auto_test = "--auto-test" in args

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
	var err = peer.create_client("localhost", PORT)
	if err != OK:
		print("ERROR: Failed to connect to server: ", err)
		get_tree().quit()
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	print("Connecting to server as '%s'..." % player_name)

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

@rpc("any_peer", "reliable")
func register_player(p_name: String):
	var sender_id = multiplayer.get_remote_sender_id()
	GameState.players[sender_id] = {"name": p_name, "ready": false}
	print("Server: Player '%s' registered (id=%d)" % [p_name, sender_id])

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
	var world = load("res://World.tscn").instantiate()
	$Level.add_child(world)

func load_game_over(winner_name: String):
	_clear_scenes()
	var go = load("res://GameOver.tscn").instantiate()
	go.winner_name = winner_name
	$UI.add_child(go)
