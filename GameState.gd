extends Node

var players := {}
var local_player_name := ""
var is_auto_test := false

var resources := {}
var capture_points := {}
var last_combat_time: float = -999.0

func reset_match_state():
	resources.clear()
	capture_points.clear()
	last_combat_time = -999.0
	for pid in players.keys():
		resources[pid] = {"horses": 0, "spears": 0}
