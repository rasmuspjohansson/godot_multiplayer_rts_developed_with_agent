extends Control

var winner_name := ""

@onready var winner_label: Label = $VBoxContainer/WinnerLabel
@onready var info_label: Label = $VBoxContainer/InfoLabel

func _ready():
	winner_label.text = "Winner: %s" % winner_name if winner_name else "Draw"
	print("GameOver: Displaying winner '%s'" % (winner_name if winner_name else "Draw"))

	var delay: float = get_tree().root.get_node("Main").LOBBY_RETURN_DELAY_SEC
	info_label.text = "Returning to lobby in %d seconds..." % int(delay)

	if multiplayer.is_server():
		get_tree().create_timer(delay).timeout.connect(_return_to_lobby)
	else:
		info_label.text = "Returning to lobby..."

func _return_to_lobby() -> void:
	get_tree().root.get_node("Main").return_to_lobby_after_match()
