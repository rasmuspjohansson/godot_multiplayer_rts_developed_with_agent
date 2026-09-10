extends RefCounted
## Data-oriented unit simulation. Units are integer ids into parallel Packed arrays; there are
## no nodes or physics bodies. Runs at a fixed SIM_DT on the server (authoritative: applies
## damage, emits deaths) and on every client (movement prediction from the same orders).

const SpatialHash := preload("res://sim/SpatialHash.gd")
const Formation := preload("res://sim/FormationController.gd")
const ArrowTrajectory := preload("res://ArrowTrajectory.gd")

enum UnitType { CLUBMAN, SPEARMAN, KNIGHT, BOWMAN, HORSE_ARCHER, DRAGON }

const SIM_DT := 0.05
const F_ALIVE := 1
const F_MOVING := 2
const F_IN_COMBAT := 4
const F_FACING_RIGHT := 8
const F_RANGED := 16
const F_HORSE := 32
const F_NEUTRAL := 64

const CELL_SIZE := 20.0
const STEER_DEADZONE := 0.6
const CATCH_UP_DIST := 12.0
const COMBAT_SCAN_PHASES := 4
const STUCK_SECONDS := 1.2
const STUCK_MIN_GOAL_DIST := 30.0
const MAX_UNIT_PATHS_PER_TICK := 8
const UNIT_PATH_WAYPOINT_REACH := 4.0
const RADIUS_FOOT := 4.5
const RADIUS_HORSE := 6.5
const RADIUS_DRAGON := 18.0
const SEPARATION_QUERY_PAD := 7.0
const FRIENDLY_PUSH := 0.25
const ENEMY_PUSH := 0.5
const MAX_PUSH_PER_TICK := 2.5
const BASE_HP := 100.0
const KNIGHT_HP := 200.0
const MELEE_ATTACK_RANGE := 22.0
const SPEAR_ATTACK_RANGE := 30.0
const RANGED_ATTACK_RANGE := 120.0
const DRAGON_ATTACK_RANGE := 70.0
const MELEE_PURSUIT := 80.0
const MELEE_ACQUIRE_RADIUS := 50.0
const ENEMY_NEAR_MARGIN := 40.0
const ENEMY_NEAR_PERIOD := 10
const RANGED_PURSUIT := 40.0
const CAVALRY_PURSUIT := 100.0
const NEUTRAL_OWNER := 0
const MAP_MARGIN := 200.0
## Fail if a living unit reverses its step direction more than this many times
## inside MOVE_OSC_WINDOW_SEC (snapshot-vs-slot rubber-band).
const MOVE_OSC_WINDOW_SEC := 2.0
const MOVE_OSC_MAX_REVERSALS := 4
const MOVE_OSC_MIN_DISP := 1.5

var count: int = 0
var pos_x := PackedFloat32Array()
var pos_z := PackedFloat32Array()
var prev_x := PackedFloat32Array()
var prev_z := PackedFloat32Array()
var goal_x := PackedFloat32Array()
var goal_z := PackedFloat32Array()
var speed := PackedFloat32Array()
var radius := PackedFloat32Array()
var hp := PackedFloat32Array()
var max_hp := PackedFloat32Array()
var attack := PackedFloat32Array()
var defense := PackedFloat32Array()
var attack_range := PackedFloat32Array()
var attack_timer := PackedFloat32Array()
var half_height := PackedFloat32Array()
var stuck_t := PackedFloat32Array()
var corr_x := PackedFloat32Array()
var corr_z := PackedFloat32Array()
var owner_pid := PackedInt32Array()
var army := PackedInt32Array()
var utype := PackedInt32Array()
var target := PackedInt32Array()
var flags := PackedByteArray()
## Sim tick at which this unit last changed (for snapshot prioritisation).
var dirty_tick := PackedInt32Array()

var armies: Array = []
var tick: int = 0
var time: float = 0.0
var is_authority := false
var damage_multiplier := 1.0
var walkability = null
var map_w: float = 1280.0
var map_h: float = 720.0
var hash := SpatialHash.new()

## Per-step outputs, cleared at the start of each step().
var died_ids := PackedInt32Array()
var routed_armies := PackedInt32Array()
## Flat: [from_x, from_z, to_x, to_z, duration, peak] per arrow.
var arrows := PackedFloat32Array()
var combat_hits: int = 0
var alive_count: int = 0
## Diagnostics: hard snaps applied by reconcile (client) and units flagged moving without
## displacement (should both stay 0 in a healthy run; see TEST_SIM_CLIENT).
var snap_count: int = 0
var walk_in_place_count: int = 0
## Set when any living unit reverses its step more than MOVE_OSC_MAX_REVERSALS times
## in MOVE_OSC_WINDOW_SEC. Peak is the worst window seen this sim.
var move_oscillation := false
var move_oscillation_id := -1
var move_oscillation_count := 0
var move_oscillation_peak := 0
var _last_disp_x := PackedFloat32Array()
var _last_disp_z := PackedFloat32Array()
var _disp_seen := PackedByteArray()
## Per-unit list of sim ticks when step direction reversed.
var _reversal_ticks: Array = []

var _unit_path_pts: Dictionary = {}
var _unit_path_i: Dictionary = {}
var _has_path := PackedByteArray()
var _wk_bytes := PackedByteArray()
var _wk_cols: int = 0
var _wk_rows: int = 0
var _wk_inv_step: float = 1.0
var _pend_target := PackedInt32Array()
var _pend_dmg := PackedFloat32Array()
var _pend_time := PackedFloat32Array()
var _army_alive := PackedInt32Array()
var _army_fighting := PackedInt32Array()
var _army_moving := PackedByteArray()
var _army_offensive := PackedByteArray()
var _army_attack_order := PackedByteArray()
var _army_enemy_near := PackedByteArray()
var _scratch_alive: PackedInt32Array = PackedInt32Array()

func setup(p_walkability, p_map_w: float, p_map_h: float, authority: bool) -> void:
	walkability = p_walkability
	map_w = p_map_w
	map_h = p_map_h
	is_authority = authority
	hash.setup(map_w, map_h, CELL_SIZE)
	_wk_cols = 0
	if walkability != null and walkability.has_method("grid_data"):
		var gd: Dictionary = walkability.grid_data()
		_wk_bytes = gd.bytes
		_wk_cols = int(gd.cols)
		_wk_rows = int(gd.rows)
		_wk_inv_step = 1.0 / float(gd.step)

static func unit_type_for_equipment(horse: bool, spear: bool, bow: bool) -> int:
	if horse and bow:
		return UnitType.HORSE_ARCHER
	if bow:
		return UnitType.BOWMAN
	if horse:
		return UnitType.KNIGHT
	if spear:
		return UnitType.SPEARMAN
	return UnitType.CLUBMAN

static func unit_type_name(t: int) -> String:
	match t:
		UnitType.SPEARMAN: return "spearman"
		UnitType.KNIGHT: return "knight"
		UnitType.BOWMAN: return "bowman"
		UnitType.HORSE_ARCHER: return "bauer_horse_archer"
		UnitType.DRAGON: return "dragon"
		_: return "clubman"

static func speed_for_type(t: int) -> float:
	match t:
		UnitType.KNIGHT, UnitType.HORSE_ARCHER: return 140.0 / 6.0
		UnitType.DRAGON: return 90.0 / 6.0
		_: return 100.0 * 2.0 / 3.0 / 6.0

static func stats_for_type(t: int) -> Dictionary:
	match t:
		UnitType.DRAGON:
			return {"hp": 300.0, "attack": 28.0, "defense": 10.0, "range": DRAGON_ATTACK_RANGE,
				"radius": RADIUS_DRAGON, "half_height": 33.0, "ranged": false, "horse": false}
		UnitType.KNIGHT:
			return {"hp": KNIGHT_HP, "attack": 10.0, "defense": 2.0, "range": MELEE_ATTACK_RANGE,
				"radius": RADIUS_HORSE, "half_height": 14.0, "ranged": false, "horse": true}
		UnitType.HORSE_ARCHER:
			return {"hp": KNIGHT_HP, "attack": 12.0, "defense": 2.0, "range": RANGED_ATTACK_RANGE,
				"radius": RADIUS_HORSE, "half_height": 14.0, "ranged": true, "horse": true}
		UnitType.BOWMAN:
			return {"hp": BASE_HP, "attack": 12.0, "defense": 2.0, "range": RANGED_ATTACK_RANGE,
				"radius": RADIUS_FOOT, "half_height": 11.0, "ranged": true, "horse": false}
		UnitType.SPEARMAN:
			return {"hp": BASE_HP, "attack": 13.0, "defense": 2.0, "range": SPEAR_ATTACK_RANGE,
				"radius": RADIUS_FOOT, "half_height": 11.0, "ranged": false, "horse": false}
		_:
			return {"hp": BASE_HP, "attack": 10.0, "defense": 2.0, "range": MELEE_ATTACK_RANGE,
				"radius": RADIUS_FOOT, "half_height": 11.0, "ranged": false, "horse": false}

static func pursuit_for_type(t: int) -> float:
	match t:
		UnitType.BOWMAN, UnitType.HORSE_ARCHER: return RANGED_PURSUIT
		UnitType.KNIGHT: return CAVALRY_PURSUIT
		_: return MELEE_PURSUIT

func add_army(fc) -> int:
	fc.index = armies.size()
	fc._pathfinder = _find_path
	armies.append(fc)
	_army_alive.resize(armies.size())
	_army_fighting.resize(armies.size())
	_army_moving.resize(armies.size())
	_army_offensive.resize(armies.size())
	_army_attack_order.resize(armies.size())
	_army_enemy_near.resize(armies.size())
	_army_enemy_near[fc.index] = 1
	return fc.index

func army_by_id(aid: String):
	for a in armies:
		if a.army_id == aid:
			return a
	return null

func ensure_capacity(n: int) -> void:
	if n <= count:
		return
	var old := count
	count = n
	for arr in [pos_x, pos_z, prev_x, prev_z, goal_x, goal_z, speed, radius, hp, max_hp, attack,
			defense, attack_range, attack_timer, half_height, stuck_t, corr_x, corr_z]:
		arr.resize(n)
	owner_pid.resize(n)
	army.resize(n)
	utype.resize(n)
	target.resize(n)
	flags.resize(n)
	dirty_tick.resize(n)
	_has_path.resize(n)
	_last_disp_x.resize(n)
	_last_disp_z.resize(n)
	_disp_seen.resize(n)
	while _reversal_ticks.size() < n:
		_reversal_ticks.append([])
	for i in range(old, n):
		flags[i] = 0
		target[i] = -1
		army[i] = -1

## Register unit `id` (server picks ids sequentially; clients replay the same ids).
func add_unit(id: int, x: float, z: float, p_owner: int, army_idx: int, p_type: int) -> void:
	ensure_capacity(id + 1)
	var st := stats_for_type(p_type)
	pos_x[id] = x
	pos_z[id] = z
	prev_x[id] = x
	prev_z[id] = z
	goal_x[id] = x
	goal_z[id] = z
	speed[id] = speed_for_type(p_type)
	radius[id] = float(st.radius)
	hp[id] = float(st.hp)
	max_hp[id] = float(st.hp)
	attack[id] = float(st.attack)
	defense[id] = float(st.defense)
	attack_range[id] = float(st.range)
	attack_timer[id] = 0.0
	half_height[id] = float(st.half_height)
	stuck_t[id] = 0.0
	corr_x[id] = 0.0
	corr_z[id] = 0.0
	owner_pid[id] = p_owner
	army[id] = army_idx
	utype[id] = p_type
	target[id] = -1
	var f := F_ALIVE
	# Art faces right; F_FACING_RIGHT means "looking toward +X". Inherit the army's
	# formation facing so east-side armies do not idle looking the wrong way.
	var face_right := true
	if army_idx >= 0 and army_idx < armies.size():
		face_right = cos(armies[army_idx].direction) >= 0.0
	if face_right:
		f |= F_FACING_RIGHT
	if bool(st.ranged):
		f |= F_RANGED
	if bool(st.horse):
		f |= F_HORSE
	if p_owner == NEUTRAL_OWNER:
		f |= F_NEUTRAL
	flags[id] = f
	dirty_tick[id] = tick
	if army_idx >= 0 and army_idx < armies.size():
		var fc = armies[army_idx]
		_army_alive[army_idx] += 1
		fc.members.append(id)
		if fc.packed_count < fc.members.size():
			fc.packed_count = fc.members.size()

## Spawns `n` soldiers of `p_type` for `fc` around its anchor in formation slots, using ids
## first_id..first_id+n-1. If `xs`/`zs` are given (client replaying a server payload) those
## positions are used instead of computing slots.
func spawn_army_units(fc, first_id: int, n: int, p_type: int, xs: PackedFloat32Array = PackedFloat32Array(), zs: PackedFloat32Array = PackedFloat32Array()) -> void:
	if fc.index < 0:
		add_army(fc)
	var idx: int = fc.index
	var explicit := xs.size() >= n and zs.size() >= n
	var offs: PackedVector2Array = fc.slot_offsets(n)
	for k in range(n):
		var p: Vector2
		if explicit:
			p = Vector2(xs[k], zs[k])
		else:
			p = snap_walkable(fc.anchor + offs[k].rotated(fc.direction))
		add_unit(first_id + k, p.x, p.y, fc.owner_pid, idx, p_type)
	fc.packed_count = fc.members.size()
	fc.anchor_speed = army_min_speed(fc) * Formation.ANCHOR_SPEED_SCALE
	fc.slots_dirty = true
	_assign_slots(fc)

## Sim-side stats for a whole army used by UI/spawn payloads.
func army_positions(fc) -> Dictionary:
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	xs.resize(fc.members.size())
	zs.resize(fc.members.size())
	for k in range(fc.members.size()):
		var id: int = fc.members[k]
		xs[k] = pos_x[id]
		zs[k] = pos_z[id]
	return {"xs": xs, "zs": zs}

## Ids of living units within `radius` of `center` (uses the spatial hash built last tick).
func units_in_radius(center: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if count == 0:
		return out
	var n := hash.query_radius(center.x, center.y, radius, pos_x, pos_z)
	var r2 := radius * radius
	for k in range(n):
		var id: int = hash.scratch[k]
		if (flags[id] & F_ALIVE) == 0:
			continue
		var dx := pos_x[id] - center.x
		var dz := pos_z[id] - center.y
		if dx * dx + dz * dz <= r2:
			out.append(id)
	return out

## Nearest living unit to `p` within `radius` satisfying owner filter (-1 = any, else != owner).
func nearest_unit(p: Vector2, radius: float, exclude_owner: int = -1, skip_neutral: bool = false) -> int:
	var best := -1
	var best_d2 := radius * radius
	for id in units_in_radius(p, radius):
		if exclude_owner >= 0 and owner_pid[id] == exclude_owner:
			continue
		if skip_neutral and (flags[id] & F_NEUTRAL) != 0:
			continue
		var dx := pos_x[id] - p.x
		var dz := pos_z[id] - p.y
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = id
	return best

func is_alive(id: int) -> bool:
	return id >= 0 and id < count and (flags[id] & F_ALIVE) != 0

func is_hostile(a: int, b: int) -> bool:
	if owner_pid[a] == owner_pid[b]:
		return false
	if (flags[a] & F_NEUTRAL) != 0 and (flags[b] & F_NEUTRAL) != 0:
		return false
	return true

func army_centroid(fc) -> Vector2:
	var sx := 0.0
	var sz := 0.0
	var n := 0
	for id in fc.members:
		if (flags[id] & F_ALIVE) == 0:
			continue
		sx += pos_x[id]
		sz += pos_z[id]
		n += 1
	if n == 0:
		return fc.anchor
	return Vector2(sx / float(n), sz / float(n))

func army_alive_count(fc) -> int:
	var n := 0
	for id in fc.members:
		if (flags[id] & F_ALIVE) != 0:
			n += 1
	return n

func army_min_speed(fc) -> float:
	var s := INF
	for id in fc.members:
		if (flags[id] & F_ALIVE) != 0:
			s = minf(s, speed[id])
	return s if s < INF else speed_for_type(UnitType.CLUBMAN)

## Re-centre the anchor on the living soldiers (used when a new order starts).
func recentre_anchor(fc) -> void:
	fc.anchor = army_centroid(fc)
	fc.anchor_speed = army_min_speed(fc) * Formation.ANCHOR_SPEED_SCALE
	var alive := army_alive_count(fc)
	fc.packed_count = alive
	fc._offset_cache.clear()
	fc.slots_dirty = true

func _find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if walkability == null:
		return PackedVector2Array([to])
	return walkability.find_path(from, to)

func is_walkable(x: float, z: float) -> bool:
	if x < 0.0 or z < 0.0 or x > map_w or z > map_h:
		return false
	if walkability == null:
		return true
	return walkability.is_walkable_world(x, z)

func snap_walkable(p: Vector2) -> Vector2:
	p.x = clampf(p.x, 0.0, map_w)
	p.y = clampf(p.y, 0.0, map_h)
	if walkability == null or walkability.is_walkable_world(p.x, p.y):
		return p
	return walkability.nearest_walkable(p.x, p.y)

## Server: kill immediately (rout, cleanup). Client: apply authoritative death event.
func kill_unit(id: int) -> void:
	if not is_alive(id):
		return
	flags[id] &= ~(F_ALIVE | F_MOVING | F_IN_COMBAT)
	hp[id] = 0.0
	target[id] = -1
	died_ids.append(id)
	dirty_tick[id] = tick
	_unit_path_pts.erase(id)
	_unit_path_i.erase(id)
	_has_path[id] = 0

func kill_units(ids: PackedInt32Array) -> void:
	for id in ids:
		kill_unit(id)

func rout_army(fc) -> void:
	if fc.is_routed:
		return
	fc.is_routed = true
	fc.clear_order()
	for id in fc.members:
		kill_unit(id)
	routed_armies.append(fc.index)

## Client reconciliation: pull toward the authoritative position. Small errors are ignored,
## medium ones blended over the next ticks, large ones snapped.
func apply_correction(id: int, sx: float, sz: float, ignore_below: float, snap_above: float) -> void:
	if not is_alive(id):
		return
	var dx := sx - pos_x[id]
	var dz := sz - pos_z[id]
	var d2 := dx * dx + dz * dz
	if d2 < ignore_below * ignore_below:
		corr_x[id] = 0.0
		corr_z[id] = 0.0
		return
	if d2 > snap_above * snap_above:
		snap_count += 1
		pos_x[id] = sx
		pos_z[id] = sz
		prev_x[id] = sx
		prev_z[id] = sz
		corr_x[id] = 0.0
		corr_z[id] = 0.0
		return
	# While the formation is marching, local slots are the dest. Blending a
	# snapshot through those slots pulls soldiers backward then they walk
	# forward again (the rubber-band). Keep hard snaps; skip the blend.
	var ai: int = army[id]
	if ai >= 0 and ai < armies.size() and armies[ai].moving:
		corr_x[id] = 0.0
		corr_z[id] = 0.0
		return
	corr_x[id] = dx
	corr_z[id] = dz

const RECONCILE_IGNORE := 2.0
const RECONCILE_SNAP := 60.0

## Client: apply one authoritative snapshot record (position, hp fraction, server flags).
func reconcile(id: int, sx: float, sz: float, hp_frac: float, server_flags: int) -> void:
	if id < 0 or id >= count:
		return
	if (server_flags & F_ALIVE) == 0:
		kill_unit(id)
		return
	if not is_alive(id):
		return
	hp[id] = clampf(hp_frac, 0.0, 1.0) * max_hp[id]
	apply_correction(id, sx, sz, RECONCILE_IGNORE, RECONCILE_SNAP)

func step(dt: float) -> void:
	tick += 1
	time += dt
	died_ids.clear()
	routed_armies.clear()
	arrows.clear()
	combat_hits = 0
	prev_x = pos_x.duplicate()
	prev_z = pos_z.duplicate()
	_step_formations(dt)
	hash.build(pos_x, pos_z, flags, count)
	for a in armies:
		if (tick + a.index) % ENEMY_NEAR_PERIOD == 0:
			_update_enemy_near(a)
	_step_units(dt)
	_step_pending_arrows(dt)
	_step_deaths()
	_track_move_oscillation()

func max_move_reversals_in_window() -> int:
	var m := 0
	for hist in _reversal_ticks:
		m = maxi(m, hist.size())
	return m

func _ensure_move_track() -> void:
	if _last_disp_x.size() < count:
		_last_disp_x.resize(count)
		_last_disp_z.resize(count)
		_disp_seen.resize(count)
	while _reversal_ticks.size() < count:
		_reversal_ticks.append([])

## Count step-direction reversals per living unit in a sliding 2s window.
## Combat is skipped (closing on a target can legitimately reverse). A reversal
## is two consecutive steps whose dots are negative and both longer than
## MOVE_OSC_MIN_DISP — separation jitter is below that; snapshot rubber-band is not.
func _track_move_oscillation() -> void:
	_ensure_move_track()
	var window := int(round(MOVE_OSC_WINDOW_SEC / SIM_DT))
	var cut: int = tick - window
	var min2 := MOVE_OSC_MIN_DISP * MOVE_OSC_MIN_DISP
	for i in range(count):
		if (flags[i] & F_ALIVE) == 0:
			continue
		if (flags[i] & F_IN_COMBAT) != 0:
			_disp_seen[i] = 0
			continue
		var dx: float = pos_x[i] - prev_x[i]
		var dz: float = pos_z[i] - prev_z[i]
		var d2: float = dx * dx + dz * dz
		if d2 < min2:
			continue
		if _disp_seen[i] == 0:
			_last_disp_x[i] = dx
			_last_disp_z[i] = dz
			_disp_seen[i] = 1
			continue
		var dot: float = dx * _last_disp_x[i] + dz * _last_disp_z[i]
		_last_disp_x[i] = dx
		_last_disp_z[i] = dz
		if dot < 0.0:
			_reversal_ticks[i].append(tick)
		var hist: Array = _reversal_ticks[i]
		if hist.is_empty():
			continue
		var start := 0
		while start < hist.size() and int(hist[start]) <= cut:
			start += 1
		if start > 0:
			hist = hist.slice(start)
			_reversal_ticks[i] = hist
		var n: int = hist.size()
		if n > move_oscillation_peak:
			move_oscillation_peak = n
		if n > MOVE_OSC_MAX_REVERSALS:
			move_oscillation = true
			move_oscillation_id = i
			move_oscillation_count = n

func _step_formations(dt: float) -> void:
	for a in armies:
		var ix: int = a.index
		_army_moving[ix] = 1 if a.moving else 0
		_army_attack_order[ix] = 1 if a.order_type == Formation.OrderType.ATTACK else 0
		_army_offensive[ix] = 1 if (
			a.order_type == Formation.OrderType.ATTACK
			or a.order_type == Formation.OrderType.ATTACK_MOVE
			or a.stance == Formation.Stance.AGGRESSIVE
		) else 0
		if a.is_routed or a.members.is_empty():
			continue
		var alive: int = _army_alive[a.index]
		var fighting: int = _army_fighting[a.index]
		var contact := 0.0 if alive == 0 else float(fighting) / float(alive)
		if a.order_type == Formation.OrderType.ATTACK:
			var tgt := _attack_order_target_xz(a)
			if tgt.x == INF:
				a.clear_order()
			else:
				var pursuit := MELEE_PURSUIT
				if not a.members.is_empty():
					pursuit = pursuit_for_type(utype[a.members[0]])
				a.update_attack_destination(dt, tgt, pursuit, contact)
		var moved: bool = a.advance_anchor(dt, contact)
		_army_moving[ix] = 1 if a.moving else 0
		if alive < int(float(a.packed_count) * Formation.REPACK_FRACTION) and alive > 0:
			a.packed_count = alive
			a.slots_dirty = true
		# Slots follow the anchor; while marching they only need refreshing every other tick.
		if a.slots_dirty or (moved and ((tick + a.index) & 1) == 0):
			_assign_slots(a)
			a.slots_dirty = false

func _attack_order_target_xz(a) -> Vector2:
	if a.order_target_unit >= 0:
		if is_alive(a.order_target_unit):
			return Vector2(pos_x[a.order_target_unit], pos_z[a.order_target_unit])
		return Vector2(INF, INF)
	if a.order_target_army >= 0 and a.order_target_army < armies.size():
		var t = armies[a.order_target_army]
		if t.is_routed or _army_alive[t.index] == 0:
			return Vector2(INF, INF)
		return army_centroid(t)
	return Vector2(INF, INF)

func _assign_slots(a) -> void:
	var n: int = maxi(a.packed_count, 1)
	var offs: PackedVector2Array = a.slot_offsets(n)
	var k := 0
	var dir: float = a.direction
	var anchor: Vector2 = a.anchor
	var cs := cos(dir)
	var sn := sin(dir)
	for id in a.members:
		if (flags[id] & F_ALIVE) == 0:
			continue
		var o: Vector2 = offs[mini(k, offs.size() - 1)]
		var gx: float = anchor.x + o.x * cs - o.y * sn
		var gz: float = anchor.y + o.x * sn + o.y * cs
		if not is_walkable(gx, gz):
			var s := snap_walkable(Vector2(gx, gz))
			gx = s.x
			gz = s.y
		if absf(gx - goal_x[id]) > 0.01 or absf(gz - goal_z[id]) > 0.01:
			goal_x[id] = gx
			goal_z[id] = gz
			_on_goal_changed(id)
		k += 1

func _on_goal_changed(id: int) -> void:
	if _has_path[id] != 0:
		var pts: PackedVector2Array = _unit_path_pts[id]
		var last: Vector2 = pts[pts.size() - 1]
		if last.distance_to(Vector2(goal_x[id], goal_z[id])) > 10.0:
			_unit_path_pts.erase(id)
			_unit_path_i.erase(id)
			_has_path[id] = 0

func _step_units(dt: float) -> void:
	_army_alive.fill(0)
	_army_fighting.fill(0)
	alive_count = 0
	var paths_this_tick := 0
	var phase := tick % COMBAT_SCAN_PHASES
	var px_arr := pos_x
	var pz_arr := pos_z
	var prx_arr := prev_x
	var prz_arr := prev_z
	var gx_arr := goal_x
	var gz_arr := goal_z
	var spd_arr := speed
	var rad_arr := radius
	var own_arr := owner_pid
	var flg_arr := flags
	var tgt_arr := target
	var rng_arr := attack_range
	var atk_t := attack_timer
	var army_arr := army
	var stuck_arr := stuck_t
	var cx_arr := corr_x
	var cz_arr := corr_z
	var dirty := dirty_tick
	var has_path := _has_path
	var a_alive := _army_alive
	var a_fight := _army_fighting
	var cell_start: PackedInt32Array = hash._cell_start
	var cell_items: PackedInt32Array = hash._cell_items
	var hcols: int = hash.cols
	var hrows: int = hash.rows
	var inv_cell: float = 1.0 / hash.cell_size
	var wk := _wk_bytes
	var wk_cols := _wk_cols
	var wk_rows := _wk_rows
	var wk_inv := _wk_inv_step
	var has_wk := wk_cols > 0
	var mw := map_w
	var mh := map_h
	var tk := tick
	var a_moving := _army_moving
	var a_off := _army_offensive
	var a_atk := _army_attack_order
	var a_near := _army_enemy_near
	for i in range(count):
		var f: int = flg_arr[i]
		if (f & F_ALIVE) == 0:
			continue
		alive_count += 1
		var ai: int = army_arr[i]
		var offensive := false
		var army_moving := false
		var attack_order := false
		var enemy_near := true
		if ai >= 0:
			a_alive[ai] += 1
			offensive = a_off[ai] != 0
			army_moving = a_moving[ai] != 0
			attack_order = a_atk[ai] != 0
			enemy_near = a_near[ai] != 0
		var x: float = px_arr[i]
		var z: float = pz_arr[i]

		# --- combat target (time-sliced scan; cheap validation every tick) ---
		var t: int = tgt_arr[i]
		var rng: float = rng_arr[i]
		# Melee units on the offensive (attack order / aggressive) acquire targets well beyond
		# their weapon reach and walk in; otherwise two formations can sit 20 units apart
		# with nobody in range and the fight stalls.
		var acq: float = rng
		if offensive and (f & F_RANGED) == 0:
			acq = maxf(rng, MELEE_ACQUIRE_RADIUS)
		if t >= 0:
			if (flg_arr[t] & F_ALIVE) == 0:
				t = -1
			else:
				var tdx: float = px_arr[t] - x
				var tdz: float = pz_arr[t] - z
				if tdx * tdx + tdz * tdz > acq * acq * 1.21:
					t = -1
		if enemy_near and (i % COMBAT_SCAN_PHASES) == phase:
			if t < 0 or attack_order:
				# Wide scans (ranged, or melee acquisition radius) cover many cells; do them
				# half as often and use the cheap weapon-range scan in between.
				var wide: bool = ((tk >> 2) & 1) == (i & 1)
				var fc = armies[ai] if ai >= 0 else null
				if (f & F_RANGED) != 0:
					if wide:
						t = _scan_target(i, fc, rng)
				else:
					t = _scan_target(i, fc, acq if wide else rng)
		tgt_arr[i] = t
		var in_combat := t >= 0
		if in_combat:
			f |= F_IN_COMBAT
			if ai >= 0:
				a_fight[ai] += 1
		else:
			f &= ~F_IN_COMBAT
			# Idle fast path: standing in its slot with no target, no pending correction and a
			# parked formation. Only every 4th tick runs the full separation/steering pass so
			# neighbours can still push it; the rest of the time it costs a handful of ops.
			if ((tk + i) & 3) != 0 and not army_moving and has_path[i] == 0:
				var idx: float = gx_arr[i] - x
				var idz: float = gz_arr[i] - z
				if idx * idx + idz * idz <= STEER_DEADZONE * STEER_DEADZONE and cx_arr[i] == 0.0 and cz_arr[i] == 0.0:
					f &= ~F_MOVING
					if f != flg_arr[i]:
						dirty[i] = tk
						flg_arr[i] = f
					continue
		var spd: float = spd_arr[i]
		var step_len := spd * dt

		# --- attack on cooldown ---
		var at: float = atk_t[i] - dt
		if in_combat and at <= 0.0:
			var tdx2: float = px_arr[t] - x
			var tdz2: float = pz_arr[t] - z
			if tdx2 * tdx2 + tdz2 * tdz2 <= rng * rng:
				at = 1.0
				_perform_attack(i, t)
		atk_t[i] = at

		# --- steering: melee closes on its target unless a normal MOVE is in progress ---
		var nx := x
		var nz := z
		if in_combat and (f & F_RANGED) == 0 and (offensive or not army_moving):
			var tdx3: float = px_arr[t] - x
			var tdz3: float = pz_arr[t] - z
			var td := sqrt(tdx3 * tdx3 + tdz3 * tdz3)
			var reach := rng * 0.85
			if td > reach:
				var stp2 := minf(td - reach, step_len)
				nx = x + tdx3 / td * stp2
				nz = z + tdz3 / td * stp2
			if tdx3 > 0.5:
				f |= F_FACING_RIGHT
			elif tdx3 < -0.5:
				f &= ~F_FACING_RIGHT
			stuck_arr[i] = 0.0
		else:
			var gx: float = gx_arr[i]
			var gz: float = gz_arr[i]
			var fdx := gx - x
			var fdz := gz - z
			var far2 := fdx * fdx + fdz * fdz
			if has_path[i] != 0:
				var pts: PackedVector2Array = _unit_path_pts[i]
				var wi: int = _unit_path_i[i]
				while wi < pts.size():
					var wp: Vector2 = pts[wi]
					var wdx := wp.x - x
					var wdz := wp.y - z
					if wdx * wdx + wdz * wdz > UNIT_PATH_WAYPOINT_REACH * UNIT_PATH_WAYPOINT_REACH:
						break
					wi += 1
				if wi >= pts.size():
					_unit_path_pts.erase(i)
					_unit_path_i.erase(i)
					has_path[i] = 0
				else:
					_unit_path_i[i] = wi
					gx = pts[wi].x
					gz = pts[wi].y
			var dx := gx - x
			var dz := gz - z
			var d2s := dx * dx + dz * dz
			if d2s > STEER_DEADZONE * STEER_DEADZONE:
				var d := sqrt(d2s)
				var stp := step_len
				if far2 > CATCH_UP_DIST * CATCH_UP_DIST and army_moving:
					stp *= Formation.CATCH_UP_SPEED
				if stp > d:
					stp = d
				var inv := stp / d
				nx = x + dx * inv
				nz = z + dz * inv
				if dx > 0.05 * step_len:
					f |= F_FACING_RIGHT
				elif dx < -0.05 * step_len:
					f &= ~F_FACING_RIGHT
			# Stuck detection -> individual A* toward the slot (throttled).
			if far2 > STUCK_MIN_GOAL_DIST * STUCK_MIN_GOAL_DIST:
				var ldx := x - prx_arr[i]
				var ldz := z - prz_arr[i]
				var thr := step_len * 0.2
				if ldx * ldx + ldz * ldz < thr * thr:
					var st: float = stuck_arr[i] + dt
					if st >= STUCK_SECONDS and paths_this_tick < MAX_UNIT_PATHS_PER_TICK and has_path[i] == 0:
						st = 0.0
						paths_this_tick += 1
						var p := _find_path(Vector2(x, z), Vector2(gx_arr[i], gz_arr[i]))
						if p.size() > 1:
							_unit_path_pts[i] = p
							_unit_path_i[i] = 0
							has_path[i] = 1
					stuck_arr[i] = st
				else:
					stuck_arr[i] = 0.0
			else:
				stuck_arr[i] = 0.0

		# --- network correction blend (clients) ---
		var cx: float = cx_arr[i]
		var cz: float = cz_arr[i]
		if cx != 0.0 or cz != 0.0:
			nx += cx * 0.35
			nz += cz * 0.35
			cx *= 0.65
			cz *= 0.65
			if absf(cx) < 0.05 and absf(cz) < 0.05:
				cx = 0.0
				cz = 0.0
			cx_arr[i] = cx
			cz_arr[i] = cz

		# --- soft separation (hash cell walk inlined; this is the hottest loop) ---
		# Each unit resolves overlaps on alternate ticks (10 Hz); pushes are small per tick
		# so this halves the cost without visible change.
		if ((tk + i) & 1) == 0:
			var r: float = rad_arr[i]
			var qr := r + SEPARATION_QUERY_PAD
			if r >= RADIUS_DRAGON:
				qr = r + RADIUS_HORSE + 1.0
			var my_owner: int = own_arr[i]
			var my_neutral := (f & F_NEUTRAL) != 0
			var px := 0.0
			var pz := 0.0
			var cx0: int = int((x - qr) * inv_cell)
			var cx1: int = int((x + qr) * inv_cell)
			var cz0: int = int((z - qr) * inv_cell)
			var cz1: int = int((z + qr) * inv_cell)
			if cx0 < 0:
				cx0 = 0
			if cz0 < 0:
				cz0 = 0
			if cx1 > hcols - 1:
				cx1 = hcols - 1
			if cz1 > hrows - 1:
				cz1 = hrows - 1
			var qr2 := qr * qr
			for czz in range(cz0, cz1 + 1):
				var row_base: int = czz * hcols
				for cxx in range(cx0, cx1 + 1):
					var c: int = row_base + cxx
					var kb: int = cell_start[c + 1]
					for k in range(cell_start[c], kb):
						var j: int = cell_items[k]
						if j == i:
							continue
						var ddx: float = x - px_arr[j]
						var ddz: float = z - pz_arr[j]
						var d2 := ddx * ddx + ddz * ddz
						if d2 >= qr2:
							continue
						var min_d: float = r + rad_arr[j]
						if d2 >= min_d * min_d:
							continue
						var dd := sqrt(d2)
						var w := FRIENDLY_PUSH
						if own_arr[j] != my_owner and not (my_neutral and (flg_arr[j] & F_NEUTRAL) != 0):
							w = ENEMY_PUSH
						if dd < 0.01:
							# Coincident: deterministic nudge by id parity.
							ddx = 0.01 if (i & 1) == 0 else -0.01
							ddz = 0.01 if (j & 1) == 0 else -0.01
							dd = 0.0141
						var s := (min_d - dd) * w / dd
						px += ddx * s
						pz += ddz * s
			if px != 0.0 or pz != 0.0:
				var pl2 := px * px + pz * pz
				if pl2 > MAX_PUSH_PER_TICK * MAX_PUSH_PER_TICK:
					var sc := MAX_PUSH_PER_TICK / sqrt(pl2)
					px *= sc
					pz *= sc
				nx += px
				nz += pz

		# --- walkability slide (try full, then x-only, then z-only) ---
		if nx != x or nz != z:
			var ok := nx >= 0.0 and nz >= 0.0 and nx <= mw and nz <= mh
			if ok and has_wk:
				ok = wk[int(nz * wk_inv + 0.5) * wk_cols + int(nx * wk_inv + 0.5)] != 0
			if not ok:
				if nx >= 0.0 and nx <= mw and (not has_wk or wk[int(z * wk_inv + 0.5) * wk_cols + int(nx * wk_inv + 0.5)] != 0):
					nz = z
				elif nz >= 0.0 and nz <= mh and (not has_wk or wk[int(nz * wk_inv + 0.5) * wk_cols + int(x * wk_inv + 0.5)] != 0):
					nx = x
				else:
					nx = x
					nz = z
			px_arr[i] = nx
			pz_arr[i] = nz
		var mdx := nx - x
		var mdz := nz - z
		var min_disp := step_len * 0.15
		if mdx * mdx + mdz * mdz > min_disp * min_disp:
			f |= F_MOVING
			dirty[i] = tk
		else:
			f &= ~F_MOVING
		if f != flg_arr[i]:
			dirty[i] = tk
			flg_arr[i] = f

func _scan_target(i: int, fc, acq: float = -1.0) -> int:
	var stance: int = Formation.Stance.DEFENSIVE
	var order_army := -1
	var order_unit := -1
	if fc != null:
		stance = fc.stance
		if fc.order_type == Formation.OrderType.ATTACK:
			order_army = fc.order_target_army
			order_unit = fc.order_target_unit
	var has_order := order_army >= 0 or order_unit >= 0
	var passive := stance == Formation.Stance.PASSIVE
	if passive and not has_order:
		return -1
	var x: float = pos_x[i]
	var z: float = pos_z[i]
	var rng: float = attack_range[i] if acq <= 0.0 else acq
	var rng2 := rng * rng
	var my_owner: int = owner_pid[i]
	var my_neutral: bool = (flags[i] & F_NEUTRAL) != 0
	var px := pos_x
	var pz := pos_z
	var own := owner_pid
	var flg := flags
	var arm := army
	var cell_start: PackedInt32Array = hash._cell_start
	var cell_items: PackedInt32Array = hash._cell_items
	var hcols: int = hash.cols
	var inv_cell: float = 1.0 / hash.cell_size
	var cx0: int = maxi(int((x - rng) * inv_cell), 0)
	var cx1: int = mini(int((x + rng) * inv_cell), hcols - 1)
	var cz0: int = maxi(int((z - rng) * inv_cell), 0)
	var cz1: int = mini(int((z + rng) * inv_cell), hash.rows - 1)
	var best := -1
	var best_d2 := INF
	var best_pref := -1
	for czz in range(cz0, cz1 + 1):
		var row_base: int = czz * hcols
		for cxx in range(cx0, cx1 + 1):
			var c: int = row_base + cxx
			var kb: int = cell_start[c + 1]
			for k in range(cell_start[c], kb):
				var j: int = cell_items[k]
				if j == i or own[j] == my_owner:
					continue
				var jf: int = flg[j]
				if (jf & F_ALIVE) == 0 or (my_neutral and (jf & F_NEUTRAL) != 0):
					continue
				var pref := 0
				if j == order_unit:
					pref = 2
				elif order_army >= 0 and arm[j] == order_army:
					pref = 1
				if passive and pref == 0:
					continue
				var dx: float = px[j] - x
				var dz: float = pz[j] - z
				var d2 := dx * dx + dz * dz
				if d2 > rng2:
					continue
				if pref > best_pref or (pref == best_pref and d2 < best_d2):
					best_pref = pref
					best_d2 = d2
					best = j
	return best

## Army-level broad phase (0.5 s round-robin): is any hostile within reach of any member?
## Units of armies with no hostile nearby skip their per-unit target scans entirely.
func _update_enemy_near(a) -> void:
	var ix: int = a.index
	var minx := INF
	var minz := INF
	var maxx := -INF
	var maxz := -INF
	var reach := MELEE_ACQUIRE_RADIUS
	var my_owner: int = a.owner_pid
	var my_neutral := false
	for id in a.members:
		var f: int = flags[id]
		if (f & F_ALIVE) == 0:
			continue
		var x: float = pos_x[id]
		var z: float = pos_z[id]
		minx = minf(minx, x)
		maxx = maxf(maxx, x)
		minz = minf(minz, z)
		maxz = maxf(maxz, z)
		reach = maxf(reach, attack_range[id])
		my_neutral = (f & F_NEUTRAL) != 0
	if minx == INF:
		_army_enemy_near[ix] = 0
		return
	var cx := (minx + maxx) * 0.5
	var cz := (minz + maxz) * 0.5
	var ext := Vector2(maxx - minx, maxz - minz).length() * 0.5
	var r: float = ext + reach + ENEMY_NEAR_MARGIN
	var r2 := r * r
	var cell_start: PackedInt32Array = hash._cell_start
	var cell_items: PackedInt32Array = hash._cell_items
	var hcols: int = hash.cols
	var inv_cell: float = 1.0 / hash.cell_size
	var cx0: int = maxi(int((cx - r) * inv_cell), 0)
	var cx1: int = mini(int((cx + r) * inv_cell), hcols - 1)
	var cz0: int = maxi(int((cz - r) * inv_cell), 0)
	var cz1: int = mini(int((cz + r) * inv_cell), hash.rows - 1)
	var own := owner_pid
	var flg := flags
	var px := pos_x
	var pz := pos_z
	for czz in range(cz0, cz1 + 1):
		var row_base: int = czz * hcols
		for cxx in range(cx0, cx1 + 1):
			var c: int = row_base + cxx
			var kb: int = cell_start[c + 1]
			for k in range(cell_start[c], kb):
				var j: int = cell_items[k]
				if own[j] == my_owner:
					continue
				var jf: int = flg[j]
				if (jf & F_ALIVE) == 0 or (my_neutral and (jf & F_NEUTRAL) != 0):
					continue
				var dx: float = px[j] - cx
				var dz: float = pz[j] - cz
				if dx * dx + dz * dz <= r2:
					_army_enemy_near[ix] = 1
					return
	_army_enemy_near[ix] = 0

func _perform_attack(i: int, t: int) -> void:
	combat_hits += 1
	if not is_authority:
		return
	var dmg := maxf(1.0, attack[i] - defense[t]) * damage_multiplier
	if (flags[i] & F_RANGED) != 0:
		var dx: float = pos_x[t] - pos_x[i]
		var dz: float = pos_z[t] - pos_z[i]
		var dist := sqrt(dx * dx + dz * dz)
		var dur := ArrowTrajectory.flight_duration(dist)
		arrows.append(pos_x[i])
		arrows.append(pos_z[i])
		arrows.append(pos_x[t])
		arrows.append(pos_z[t])
		arrows.append(dur)
		arrows.append(ArrowTrajectory.peak_height(dist))
		_pend_target.append(t)
		_pend_dmg.append(dmg)
		_pend_time.append(dur)
	else:
		hp[t] -= dmg
		dirty_tick[t] = tick

func _step_pending_arrows(dt: float) -> void:
	var k := 0
	while k < _pend_target.size():
		_pend_time[k] -= dt
		if _pend_time[k] > 0.0:
			k += 1
			continue
		var t: int = _pend_target[k]
		if is_alive(t):
			hp[t] -= _pend_dmg[k]
			dirty_tick[t] = tick
		_pend_target.remove_at(k)
		_pend_dmg.remove_at(k)
		_pend_time.remove_at(k)

func _step_deaths() -> void:
	if not is_authority:
		return
	var any_died := false
	for i in range(count):
		if (flags[i] & F_ALIVE) != 0 and hp[i] <= 0.0:
			kill_unit(i)
			any_died = true
	if not any_died:
		return
	for a in armies:
		if a.is_routed or a.initial_count <= 0 or a.is_npc:
			continue
		var alive := army_alive_count(a)
		if alive == 0 or float(alive) / float(a.initial_count) < Formation.ROUT_THRESHOLD:
			rout_army(a)
