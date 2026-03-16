extends Node

const PLAYER_COLORS: Array = [
	Color.RED,
	Color.BLUE,
	Color.GREEN,
	Color.ORANGE,
	Color.PURPLE
]

var players := {}
var local_player_name := ""
var is_auto_test := false
var test_events: int = 1
var use_3d := false

var resources := {}
var capture_points := {}
var last_combat_time: float = -999.0

func reset_match_state():
	resources.clear()
	capture_points.clear()
	last_combat_time = -999.0
	for pid in players.keys():
		resources[pid] = {"horses": 0, "spears": 0}
