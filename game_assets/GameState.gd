extends Node

const PLAYER_COLORS: Array = [
	Color.RED,
	Color.BLUE,
	Color.GREEN,
	Color.ORANGE,
	Color.PURPLE
]

const STARTING_RESOURCES := {
	"horses": 10,
	"spears": 10,
	"bows": 10,
	"villagers": 10,
}

var players := {}
var local_player_name := ""
var is_auto_test := false

var resources := {}
var capture_points := {}
var last_combat_time: float = -999.0
## Lobby-selected map name (`S`, `XL`, custom editor maps). CLI `--map=` is the default.
var selected_map := ""

static func default_resources() -> Dictionary:
	return STARTING_RESOURCES.duplicate()

func reset_match_state():
	resources.clear()
	capture_points.clear()
	last_combat_time = -999.0
	for pid in players.keys():
		resources[pid] = default_resources()

#region agent log
const _AGENT_DEBUG_LOG := "/home/rasmus/projects/godot/.cursor/debug-7aa3b9.log"

func agent_debug_log(hypothesis_id: String, location: String, message: String, data: Dictionary = {}) -> void:
	var f: FileAccess = FileAccess.open(_AGENT_DEBUG_LOG, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(_AGENT_DEBUG_LOG, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var payload := {
		"sessionId": "7aa3b9",
		"timestamp": Time.get_ticks_msec(),
		"hypothesisId": hypothesis_id,
		"location": location,
		"message": message,
		"data": data
	}
	f.store_line(JSON.stringify(payload))
	f.close()
#endregion
