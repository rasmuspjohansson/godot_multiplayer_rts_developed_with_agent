extends Control

var winner_name := ""

@onready var winner_label: Label = $VBoxContainer/WinnerLabel
@onready var info_label: Label = $VBoxContainer/InfoLabel

func _ready():
	winner_label.text = "Winner: %s" % winner_name
	print("GameOver: Displaying winner '%s'" % winner_name)

	if not multiplayer.is_server():
		info_label.text = "Disconnecting in 3 seconds..."
		get_tree().create_timer(3.0).timeout.connect(_disconnect)
	else:
		info_label.text = "Server: Match complete."

func _disconnect():
	print("TEST_012: Client disconnecting after game over")
	multiplayer.multiplayer_peer.close()
	get_tree().quit()
