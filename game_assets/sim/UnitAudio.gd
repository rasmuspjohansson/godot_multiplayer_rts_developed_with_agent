extends Node3D
## Pooled positional audio for thousands of units: at most POOL_SIZE AudioStreamPlayer3D nodes,
## each parked at the centroid of a cluster (one army) of walking or fighting units. Deaths play
## a one-shot from a separate small pool. Replaces one AudioStreamPlayer3D per unit.

const UNIT_SPRITE_PATHS := preload("res://UnitSpritePaths.gd")

const POOL_SIZE := 16
const DEATH_POOL_SIZE := 6
const SFX_MAX_DISTANCE := 2400.0
const SFX_UNIT_SIZE := 100.0
const RETARGET_SEC := 0.5
const MAX_DEATH_SOUNDS_PER_TICK := 2

var sim: RefCounted = null
var ground_height_fn: Callable = Callable()

var _players: Array[AudioStreamPlayer3D] = []
var _player_army: PackedInt32Array = PackedInt32Array()
var _player_state: PackedInt32Array = PackedInt32Array()
var _death_players: Array[AudioStreamPlayer3D] = []
var _death_next := 0
var _streams: Dictionary = {}
var _accum := 0.0

func _ready() -> void:
	for i in range(POOL_SIZE):
		_players.append(_make_player("ClusterAudio_%d" % i))
	_player_army.resize(POOL_SIZE)
	_player_army.fill(-1)
	_player_state.resize(POOL_SIZE)
	_player_state.fill(-1)
	for i in range(DEATH_POOL_SIZE):
		_death_players.append(_make_player("DeathAudio_%d" % i))

func _make_player(p_name: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = p_name
	p.unit_size = SFX_UNIT_SIZE
	p.max_distance = SFX_MAX_DISTANCE
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.bus = AudioSettings.get_sfx_bus_name()
	if AudioServer.get_bus_index(p.bus) < 0:
		p.bus = &"Master"
	add_child(p)
	return p

func _stream(color: String, unit_type: String, action: String) -> AudioStream:
	var key := color + "/" + unit_type + "/" + action
	if _streams.has(key):
		return _streams[key]
	var s: AudioStream = UNIT_SPRITE_PATHS.load_sprite_sound(UNIT_SPRITE_PATHS.ai_sprite_folder(color, unit_type, action))
	if s == null and color != "blue":
		s = UNIT_SPRITE_PATHS.load_sprite_sound(UNIT_SPRITE_PATHS.ai_sprite_folder("blue", unit_type, action))
	_streams[key] = s
	return s

func _color_for(pid: int) -> String:
	if UNIT_SPRITE_PATHS.is_neutral_owner(pid):
		return "red"
	return UNIT_SPRITE_PATHS.color_folder_for_peer(pid)

## Called once per sim tick; re-clusters every RETARGET_SEC.
func tick() -> void:
	if sim == null:
		return
	_accum += sim.SIM_DT
	if _accum < RETARGET_SEC:
		return
	_accum = 0.0
	# Score armies: fighting armies first, then moving ones; each gets one player.
	var candidates: Array = []
	for fc in sim.armies:
		if fc.is_routed or fc.members.is_empty():
			continue
		var fighting := 0
		var moving := 0
		var sx := 0.0
		var sz := 0.0
		var n := 0
		var t := -1
		for id in fc.members:
			var f: int = sim.flags[id]
			if (f & sim.F_ALIVE) == 0:
				continue
			n += 1
			sx += sim.pos_x[id]
			sz += sim.pos_z[id]
			t = sim.utype[id]
			if (f & sim.F_IN_COMBAT) != 0:
				fighting += 1
			elif (f & sim.F_MOVING) != 0:
				moving += 1
		if n == 0:
			continue
		var state := -1
		if fighting * 3 >= n:
			state = 2
		elif moving * 2 >= n:
			state = 1
		if state < 0:
			continue
		candidates.append({
			"army": fc.index, "state": state, "score": (fighting * 3 + moving) * (2 if state == 2 else 1),
			"x": sx / float(n), "z": sz / float(n), "type": t, "pid": fc.owner_pid,
		})
	candidates.sort_custom(func(a, b): return a["score"] > b["score"])
	var wanted: Array = candidates.slice(0, POOL_SIZE)
	# Keep players already assigned to a wanted army/state; free the rest.
	var assigned := {}
	for i in range(POOL_SIZE):
		var a := _player_army[i]
		var keep := false
		for c in wanted:
			if int(c["army"]) == a and int(c["state"]) == _player_state[i]:
				keep = true
				_place(_players[i], c)
				assigned[a] = true
				break
		if not keep:
			_player_army[i] = -1
			_player_state[i] = -1
			_players[i].stop()
	for c in wanted:
		var a := int(c["army"])
		if assigned.has(a):
			continue
		for i in range(POOL_SIZE):
			if _player_army[i] >= 0:
				continue
			var action := "attack" if int(c["state"]) == 2 else "move"
			var s := _stream(_color_for(int(c["pid"])), sim.unit_type_name(int(c["type"])), action)
			_player_army[i] = a
			_player_state[i] = int(c["state"])
			_place(_players[i], c)
			if s != null:
				_players[i].stream = s
				_players[i].play()
			break

func _place(p: AudioStreamPlayer3D, c: Dictionary) -> void:
	var x: float = c["x"]
	var z: float = c["z"]
	var y := 0.0
	if ground_height_fn.is_valid():
		y = ground_height_fn.call(x, z)
	p.position = Vector3(x, y + 10.0, z)

## Play a few death one-shots at the positions of units that just died.
func on_deaths(ids: PackedInt32Array) -> void:
	if sim == null:
		return
	var played := 0
	for id in ids:
		if played >= MAX_DEATH_SOUNDS_PER_TICK:
			break
		if id < 0 or id >= sim.count:
			continue
		var s := _stream(_color_for(sim.owner_pid[id]), sim.unit_type_name(sim.utype[id]), "die")
		if s == null:
			continue
		var p := _death_players[_death_next]
		_death_next = (_death_next + 1) % DEATH_POOL_SIZE
		var x: float = sim.pos_x[id]
		var z: float = sim.pos_z[id]
		var y: float = ground_height_fn.call(x, z) if ground_height_fn.is_valid() else 0.0
		p.position = Vector3(x, y + 10.0, z)
		p.stream = s
		p.play()
		played += 1
