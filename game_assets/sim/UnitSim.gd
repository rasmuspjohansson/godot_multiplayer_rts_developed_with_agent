extends RefCounted
## Data-oriented unit simulation. Units are integer ids into parallel Packed arrays; there are
## no nodes or physics bodies. Runs at a fixed SIM_DT on the server (authoritative: applies
## damage, emits deaths) and on every client (movement prediction from the same orders).

const SpatialHash := preload("res://sim/SpatialHash.gd")
const Formation := preload("res://sim/FormationController.gd")
const ArrowTrajectory := preload("res://ArrowTrajectory.gd")

enum UnitType { CLUBMAN, SPEARMAN, KNIGHT, BOWMAN, HORSE_ARCHER, DRAGON, ARMORED_SWORDSMAN, ARMORED_BOWMAN, KNIGHT_LONG_SPEAR, SWORDSMAN_SHIELD, ARMOURED_SWORDSMAN_SHIELD, MOUNTED_KNIGHT_SHIELD, MOUNTED_LANCE_KNIGHT, ARMOURED_PIKE, DRAGON_2 }

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
## Marching soldiers track their slot to this precision: the slot advances one anchor step
## (~0.55 units for foot) per tick, so the parked deadzone would make them stutter every
## other tick.
const MARCH_DEADZONE := 0.05
const CATCH_UP_DIST := 12.0
const COMBAT_SCAN_PHASES := 4
const STUCK_SECONDS := 1.2
const STUCK_MIN_GOAL_DIST := 30.0
const MAX_UNIT_PATHS_PER_TICK := 8
const UNIT_PATH_WAYPOINT_REACH := 4.0
const RADIUS_FOOT := 4.5
const RADIUS_HORSE := 6.5
const RADIUS_DRAGON := 54.0
const SEPARATION_QUERY_PAD := 7.0
## Separation is order-first: units remember up to CONTACT_SLOTS neighbours, slide along
## them while steering, and a weak push eases leftover overlap. Overlap is allowed, jumps
## are not.
const CONTACT_SLOTS := 4
## A neighbour becomes a contact this far before its overlap limit, and is dropped once it
## is CONTACT_DROP_MARGIN beyond that again (no flicker at the boundary).
const CONTACT_PAD := 4.0
const CONTACT_DROP_MARGIN := 1.0
## Fraction of the summed radii two units may close to before sliding / pushing kicks in.
const FRIENDLY_OVERLAP_OK := 0.6
const ENEMY_OVERLAP_OK := 0.85
## Per tick, fraction of the remaining overlap a push removes.
const FRIENDLY_PUSH := 0.15
const ENEMY_PUSH := 0.3
## Per tick, a push never moves a unit farther than this fraction of its own walk step.
const PUSH_STEP_FRAC := 0.35
## Head-on contact: sidestep this fraction of the walk step so neither unit freezes.
const SIDESTEP_FRAC := 0.3
const BASE_HP := 100.0
const KNIGHT_HP := 200.0
const MELEE_ATTACK_RANGE := 22.0
const SPEAR_ATTACK_RANGE := 30.0
const RANGED_ATTACK_RANGE := 120.0
## Reach past the body stays 52 (the old 70 − 18) after the body grew to 3×.
const DRAGON_ATTACK_RANGE := 106.0
const MELEE_PURSUIT := 80.0
const MELEE_ACQUIRE_RADIUS := 50.0
const ENEMY_NEAR_MARGIN := 40.0
const ENEMY_NEAR_PERIOD := 10
const RANGED_PURSUIT := 40.0
const CAVALRY_PURSUIT := 100.0
## Once a ranged army is walking away from melee, keep going until every soldier is this far
## past the attacker's weapon reach, so the block does not step straight back into the swing.
const MELEE_FLEE_CLEAR := 12.0
const NEUTRAL_OWNER := 0
const MAP_MARGIN := 200.0
## Fail if a living unit reverses its step direction more than this many times
## inside MOVE_OSC_WINDOW_SEC (snapshot-vs-slot rubber-band).
const MOVE_OSC_WINDOW_SEC := 2.0
const MOVE_OSC_MAX_REVERSALS := 4
const MOVE_OSC_MIN_DISP := 1.5
## Position history kept for reconciliation: a snapshot stamped with server tick T is
## compared against where *this* sim had the unit at tick T, not where it is now, so the
## one-way latency never shows up as a backward error on marching units.
const HIST_TICKS := 32
## Client: after a snapshot reports a unit F_IN_COMBAT, keep following the server for this
## many ticks instead of steering it back to its slot (damage/targets are server-owned, so a
## fight the client did not predict must not turn into a slot-vs-correction tug of war).
const SERVER_COMBAT_HOLD_TICKS := 16

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
## Terrain samples, same triangle split as the ground mesh. Empty until World calls set_height_grid.
var _hg := PackedFloat32Array()
## Distance travelled last tick divided by SIM_DT. The knight charge reads this, because the
## attack is resolved before this tick's step is applied.
var _travel_speed := PackedFloat32Array()
var _charge_cd := PackedFloat32Array()
## Ordered speed, eased toward the slope max. Not reduced by pushes.
var _cruise := PackedFloat32Array()
var _hg_cols: int = 0
var _hg_rows: int = 0
var _hg_inv: float = 1.0

static var _rules_loaded := false
static var _unit_stats: Dictionary = {}
static var _spear_vs_horse_attack := 1.0
static var _knight_vs_unmounted_attack := 2.0
static var _knight_charge_attack := 30.0
static var _knight_charge_cooldown := 2.0
static var _knight_charge_min_speed_ratio := 1.1
static var _height_attack := 1.0
static var _slope_speed_at_45 := 0.25
static var _max_slope_deg := 45.0
static var _range_height_bonus_max := 0.5
static var _max_height_bonus_height := 20.0

## Per-step outputs, cleared at the start of each step().
var died_ids := PackedInt32Array()
var routed_armies := PackedInt32Array()
## Flat: [from_x, from_z, to_x, to_z, duration, peak] per arrow.
var arrows := PackedFloat32Array()
var combat_hits: int = 0
var alive_count: int = 0
## Server: armies whose living count dropped below REPACK_FRACTION of their grid while idle.
## World turns these into a scheduled repack order so both peers compact on the same tick.
var repack_requests := PackedInt32Array()
## Diagnostics: hard snaps applied by reconcile (client), units flagged moving without
## displacement, and medium (blended) corrections. All should sit at/near 0 in a healthy run
## (see TEST_SIM_CLIENT).
var snap_count: int = 0
var walk_in_place_count: int = 0
var corr_count: int = 0
var _hist_x: Array = []
var _hist_z: Array = []
var _hist_tick := PackedInt32Array()
## Client: sim tick until which the server's "in combat" report overrides local steering.
var _srv_combat_until := PackedInt32Array()
## Set when any living unit reverses its step more than MOVE_OSC_MAX_REVERSALS times
## in MOVE_OSC_WINDOW_SEC. Peak is the worst window seen this sim.
var move_oscillation := false
var move_oscillation_id := -1
var move_oscillation_count := 0
var move_oscillation_peak := 0
var _last_disp_x := PackedFloat32Array()
var _last_disp_z := PackedFloat32Array()
var _disp_seen := PackedByteArray()
## Per tick: 1 when separation shoved the unit farther than MOVE_OSC_MIN_DISP (crowd
## jostling is identical on every peer and is not a sync reversal).
var _pushed := PackedByteArray()
## CONTACT_SLOTS unit ids per unit (-1 = empty): neighbours it is close to overlapping.
var _contacts := PackedInt32Array()
## Diagnostics for the last oscillation trip (see World TEST_MOVE_OSCILLATION_FAIL).
var move_oscillation_info: String = ""
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
## Soldiers farther than CATCH_UP_DIST from their slot last tick (cohesion input).
var _army_straggling := PackedInt32Array()
var _army_moving := PackedByteArray()
## Unit heading of each marching army (0 when parked); reference for direction-safe blends.
var _army_dir_x := PackedFloat32Array()
var _army_dir_z := PackedFloat32Array()
var _army_offensive := PackedByteArray()
var _army_attack_order := PackedByteArray()
var _army_enemy_near := PackedByteArray()
## Ranged army walking away from non-ranged attackers. Set at the end of _step_units and
## applied on the next _step_formations. Direction is the summed away-vector, normalised.
var _army_melee_flee := PackedByteArray()
var _army_was_fleeing := PackedByteArray()
var _army_flee_x := PackedFloat32Array()
var _army_flee_z := PackedFloat32Array()
var _army_flee_acc_x := PackedFloat32Array()
var _army_flee_acc_z := PackedFloat32Array()
var _army_flee_want := PackedByteArray()
var _army_flee_near := PackedByteArray()
## Per-soldier index into the army path. Only moves forward, and restarts when march_seq changes.
var _march_i := PackedInt32Array()
## 1 once a soldier has entered the last stretch, so a wide slot cannot pull them back onto the path.
var _march_deploy := PackedByteArray()
var _army_march_seen := PackedInt32Array()
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

## -1 when the checked boxes are not exactly one recipe. Shield only matches the recipes that include it.
static func unit_type_for_loadout(horse: bool, spear: bool, bow: bool, armour: bool = false, sword: bool = false, long_spear: bool = false, shield: bool = false) -> int:
	var bits := 0
	if horse:
		bits |= 1
	if spear:
		bits |= 2
	if bow:
		bits |= 4
	if armour:
		bits |= 8
	if sword:
		bits |= 16
	if long_spear:
		bits |= 32
	if shield:
		bits |= 64
	match bits:
		0:
			return UnitType.CLUBMAN
		2:
			return UnitType.SPEARMAN
		1:
			return UnitType.KNIGHT
		4:
			return UnitType.BOWMAN
		5:
			return UnitType.HORSE_ARCHER
		24:
			return UnitType.ARMORED_SWORDSMAN
		12:
			return UnitType.ARMORED_BOWMAN
		33:
			return UnitType.KNIGHT_LONG_SPEAR
		80:
			return UnitType.SWORDSMAN_SHIELD
		88:
			return UnitType.ARMOURED_SWORDSMAN_SHIELD
		81:
			return UnitType.MOUNTED_KNIGHT_SHIELD
		40:
			return UnitType.ARMOURED_PIKE
		105:
			return UnitType.MOUNTED_LANCE_KNIGHT
		_:
			return -1

static func unit_type_for_equipment(horse: bool, spear: bool, bow: bool) -> int:
	return unit_type_for_loadout(horse, spear, bow)

static func unit_type_name(t: int) -> String:
	match t:
		UnitType.SPEARMAN: return "spearman"
		UnitType.KNIGHT: return "knight"
		UnitType.BOWMAN: return "bowman"
		UnitType.HORSE_ARCHER: return "bauer_horse_archer"
		UnitType.DRAGON: return "dragon"
		UnitType.ARMORED_SWORDSMAN: return "armored_swordsman"
		UnitType.ARMORED_BOWMAN: return "bowman_with_armour"
		UnitType.KNIGHT_LONG_SPEAR: return "knight_with_long_spear"
		UnitType.SWORDSMAN_SHIELD: return "swordsman_with_shield_and_sword"
		UnitType.ARMOURED_SWORDSMAN_SHIELD: return "armoured_swordsman_with_shield_and_sword"
		UnitType.MOUNTED_KNIGHT_SHIELD: return "mounted_knight_with_shield_and_sword"
		UnitType.MOUNTED_LANCE_KNIGHT: return "mounted_knight_with_armour_shield_and_lance"
		UnitType.ARMOURED_PIKE: return "armoured_soldier_with_long_pike"
		UnitType.DRAGON_2: return "dragon_2"
		_: return "clubman"

static func speed_for_type(t: int) -> float:
	return float(stats_for_type(t).speed)

static func stats_for_type(t: int) -> Dictionary:
	_ensure_rules()
	var name := unit_type_name(t)
	if not _unit_stats.has(name):
		push_error("UnitSim: units.json has no entry for '%s'" % name)
		return {}
	return _unit_stats[name]

static func _ensure_rules() -> void:
	if _rules_loaded:
		return
	_rules_loaded = true
	var units: Variant = _read_json("res://units.json")
	var bonuses: Variant = _read_json("res://bonuses.json")
	if typeof(units) != TYPE_DICTIONARY or typeof(bonuses) != TYPE_DICTIONARY:
		push_error("UnitSim: units.json and bonuses.json must be JSON objects")
		return
	_unit_stats = units
	_spear_vs_horse_attack = float(bonuses.get("spear_vs_horse_attack", 0))
	_knight_vs_unmounted_attack = float(bonuses.get("knight_vs_unmounted_attack", 0))
	_knight_charge_attack = float(bonuses.get("knight_charge_attack", 0))
	_knight_charge_cooldown = float(bonuses.get("knight_charge_cooldown", 0))
	_knight_charge_min_speed_ratio = float(bonuses.get("knight_charge_min_speed_ratio", 1))
	_height_attack = float(bonuses.get("height_attack", 0))
	_slope_speed_at_45 = float(bonuses.get("slope_speed_at_45_deg", 0))
	_max_slope_deg = maxf(float(bonuses.get("max_slope_deg", 45)), 0.001)
	_range_height_bonus_max = float(bonuses.get("range_height_bonus_max", 0))
	_max_height_bonus_height = maxf(float(bonuses.get("max_height_bonus_height", 1)), 0.001)
	Formation.speed_ramp_seconds = maxf(float(bonuses.get("speed_ramp_seconds", 2)), 0.0)
	Formation.double_time_speed = float(bonuses.get("double_time_speed", 5))
	Formation.double_time_tired_max = maxf(float(bonuses.get("double_time_tired_max", 8)), 1.0)
	Formation.double_time_tired_seconds = maxf(float(bonuses.get("double_time_tired_seconds", 5)), 0.001)
	for key in ["spear_vs_horse_attack", "knight_vs_unmounted_attack", "knight_charge_attack", "knight_charge_cooldown", "knight_charge_min_speed_ratio", "height_attack", "speed_ramp_seconds", "double_time_speed", "double_time_tired_max", "double_time_tired_seconds", "slope_speed_at_45_deg", "max_slope_deg", "range_height_bonus_max", "max_height_bonus_height"]:
		if not bonuses.has(key):
			push_error("UnitSim: bonuses.json missing '%s'" % key)

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("UnitSim: required file missing: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("UnitSim: failed to parse %s" % path)
	return parsed

## Copy of the terrain grid. Soldiers and the formation anchor both read it; no per-unit Callable.
func set_height_grid(heights: PackedFloat32Array, cols: int, rows: int, step: float) -> void:
	_hg = heights
	_hg_cols = cols
	_hg_rows = rows
	_hg_inv = 1.0 / maxf(step, 0.001)
	var cb := Callable()
	if cols >= 2 and rows >= 2:
		cb = Callable(self, "slope_between")
	for fc in armies:
		fc.slope_scale = cb

func height_at(x: float, z: float) -> float:
	if _hg_cols < 2 or _hg_rows < 2:
		return 0.0
	return _height_inline(_hg, _hg_cols, _hg_rows, _hg_inv, x, z)

static func _height_inline(hg: PackedFloat32Array, cols: int, rows: int, inv_step: float, x: float, z: float) -> float:
	var gx: float = clampf(x * inv_step, 0.0, float(cols - 1))
	var gz: float = clampf(z * inv_step, 0.0, float(rows - 1))
	var i0: int = int(gx)
	var j0: int = int(gz)
	var i1: int = mini(i0 + 1, cols - 1)
	var j1: int = mini(j0 + 1, rows - 1)
	var tx: float = gx - float(i0)
	var tz: float = gz - float(j0)
	var r0: int = j0 * cols
	var r1: int = j1 * cols
	var h00: float = hg[r0 + i0]
	var h10: float = hg[r0 + i1]
	var h01: float = hg[r1 + i0]
	var h11: float = hg[r1 + i1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)

## Speed scale for a step. Uphill 45° is 1 - slope_speed_at_45_deg, downhill is the reverse.
static func slope_speed_multiplier(dh: float, run: float) -> float:
	_ensure_rules()
	if run <= 0.0001:
		return 1.0
	var slope_deg := rad_to_deg(atan2(dh, run))
	return 1.0 - _slope_speed_at_45 * clampf(slope_deg / _max_slope_deg, -1.0, 1.0)

## Step length after easing cruise toward base speed × slope × catch-up. Zeros cruise when dist_cap is 0.
func _cruise_step(i: int, dir_x: float, dir_z: float, dist_cap: float, base_speed: float, catch: float, dt: float, hg: PackedFloat32Array, hg_cols: int, hg_rows: int, hg_inv: float, has_hg: bool, slope_at_45: float, slope_deg_max: float) -> float:
	if dist_cap <= 0.0:
		_cruise[i] = 0.0
		return 0.0
	var mult := 1.0
	if has_hg:
		var probe := minf(dist_cap, maxf(base_speed * dt, 0.05))
		var h0 := _height_inline(hg, hg_cols, hg_rows, hg_inv, pos_x[i], pos_z[i])
		var h1 := _height_inline(hg, hg_cols, hg_rows, hg_inv, pos_x[i] + dir_x * probe, pos_z[i] + dir_z * probe)
		mult = 1.0 - slope_at_45 * clampf(rad_to_deg(atan2(h1 - h0, probe)) / slope_deg_max, -1.0, 1.0)
		if mult < 0.05:
			mult = 0.05
	var target := base_speed * mult * catch
	var ai: int = army[i]
	if ai >= 0 and ai < armies.size():
		var fc = armies[ai]
		if fc.double_time and fc.tiredness > -Formation.double_time_tired_max:
			target += Formation.double_time_speed
	_cruise[i] = Formation.approach_cruise(_cruise[i], target, dt)
	return minf(dist_cap, _cruise[i] * dt)

func slope_between(from: Vector2, to: Vector2) -> float:
	var dx := to.x - from.x
	var dz := to.y - from.y
	var run := sqrt(dx * dx + dz * dz)
	if run <= 0.0001 or _hg_cols < 2:
		return 1.0
	return slope_speed_multiplier(height_at(to.x, to.y) - height_at(from.x, from.y), run)

static func range_mult_for_gap(gap: float) -> float:
	_ensure_rules()
	return 1.0 + _range_height_bonus_max * clampf(gap / _max_height_bonus_height, -1.0, 1.0)

## Weapon reach from shooter to a target point. Positive gap (shooter higher) lengthens it.
func ranged_reach(x0: float, z0: float, x1: float, z1: float, base_range: float) -> float:
	return base_range * range_mult_for_gap(height_at(x0, z0) - height_at(x1, z1))

## Reach along a direction, sampling the ground twice because the landing point depends on the distance.
func ranged_reach_along(x: float, z: float, angle: float, base_range: float) -> float:
	var dist := base_range
	var h0 := height_at(x, z)
	var c := cos(angle)
	var s := sin(angle)
	for _step in 2:
		dist = base_range * range_mult_for_gap(h0 - height_at(x + c * dist, z + s * dist))
	return dist

func _max_ranged_reach(base_range: float) -> float:
	if _hg_cols < 2:
		return base_range
	_ensure_rules()
	return base_range * (1.0 + _range_height_bonus_max)

static func pursuit_for_type(t: int) -> float:
	match t:
		UnitType.BOWMAN, UnitType.HORSE_ARCHER: return RANGED_PURSUIT
		UnitType.KNIGHT: return CAVALRY_PURSUIT
		_: return MELEE_PURSUIT

func add_army(fc) -> int:
	fc.index = armies.size()
	fc._pathfinder = _find_path
	if _hg_cols >= 2 and _hg_rows >= 2:
		fc.slope_scale = Callable(self, "slope_between")
	armies.append(fc)
	_army_alive.resize(armies.size())
	_army_fighting.resize(armies.size())
	_army_straggling.resize(armies.size())
	_army_moving.resize(armies.size())
	_army_dir_x.resize(armies.size())
	_army_dir_z.resize(armies.size())
	_army_offensive.resize(armies.size())
	_army_attack_order.resize(armies.size())
	_army_enemy_near.resize(armies.size())
	_army_enemy_near[fc.index] = 1
	_army_melee_flee.resize(armies.size())
	_army_was_fleeing.resize(armies.size())
	_army_flee_x.resize(armies.size())
	_army_flee_z.resize(armies.size())
	_army_flee_acc_x.resize(armies.size())
	_army_flee_acc_z.resize(armies.size())
	_army_flee_want.resize(armies.size())
	_army_flee_near.resize(armies.size())
	_army_march_seen.resize(armies.size())
	return fc.index

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
	_srv_combat_until.resize(n)
	_last_disp_x.resize(n)
	_last_disp_z.resize(n)
	_disp_seen.resize(n)
	_pushed.resize(n)
	_contacts.resize(n * CONTACT_SLOTS)
	_march_i.resize(n)
	_march_deploy.resize(n)
	_travel_speed.resize(n)
	_charge_cd.resize(n)
	_cruise.resize(n)
	while _reversal_ticks.size() < n:
		_reversal_ticks.append([])
	for i in range(old, n):
		flags[i] = 0
		target[i] = -1
		army[i] = -1
		for s in range(CONTACT_SLOTS):
			_contacts[i * CONTACT_SLOTS + s] = -1

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
	# front, not its rank axis, so an army marching west does not idle facing right.
	var face_right := true
	if army_idx >= 0 and army_idx < armies.size():
		face_right = cos(armies[army_idx].front_angle()) >= 0.0
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
		fc.slot_index.append(fc.members.size() - 1)
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

## Re-centre the anchor so the *existing* slot grid best fits the living soldiers (least
## squares over their fixed slots). Rows, pitch and slot indices are untouched: a new order
## never rebuilds the grid, so soldiers keep their neighbours (see repack_army for the only
## place the grid is compacted).
func recentre_anchor(fc) -> void:
	var offs: PackedVector2Array = fc.slot_offsets(maxi(fc.packed_count, 1))
	var cs := cos(fc.direction)
	var sn := sin(fc.direction)
	var sx := 0.0
	var sz := 0.0
	var n := 0
	for k in range(fc.members.size()):
		var id: int = fc.members[k]
		if (flags[id] & F_ALIVE) == 0:
			continue
		var o: Vector2 = offs[mini(fc.slot_index[k], offs.size() - 1)]
		sx += pos_x[id] - (o.x * cs - o.y * sn)
		sz += pos_z[id] - (o.x * sn + o.y * cs)
		n += 1
	if n > 0:
		fc.anchor = Vector2(sx / float(n), sz / float(n))
	fc.anchor_speed = army_min_speed(fc) * Formation.ANCHOR_SPEED_SCALE
	fc.slots_dirty = true

## Compact the grid onto the living soldiers: k-th living member takes slot k and the grid
## shrinks to the living count. Only ever run from a scheduled order while the army is idle
## so every peer changes slots on the same tick.
func repack_army(fc) -> void:
	var k := 0
	for m in range(fc.members.size()):
		if (flags[fc.members[m]] & F_ALIVE) == 0:
			continue
		fc.slot_index[m] = k
		k += 1
	if k > 0:
		fc.packed_count = k
	fc.repack_pending = false
	fc.slots_dirty = true
	recentre_anchor(fc)

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

## Client reconciliation. `(sx, sz)` is the authoritative position and `(rx, rz)` the local
## position it is compared against (this sim's position at the same tick when known, else the
## current one); the error is applied to the *current* position. Small errors are ignored,
## medium ones stored and blended direction-safely in _step_units, large ones snapped.
func apply_correction(id: int, sx: float, sz: float, ignore_below: float, snap_above: float, rx: float = INF, rz: float = INF) -> void:
	if not is_alive(id):
		return
	if rx == INF:
		rx = pos_x[id]
		rz = pos_z[id]
	var dx := sx - rx
	var dz := sz - rz
	var d2 := dx * dx + dz * dz
	if d2 < ignore_below * ignore_below:
		corr_x[id] = 0.0
		corr_z[id] = 0.0
		return
	if d2 > snap_above * snap_above:
		snap_count += 1
		pos_x[id] += dx
		pos_z[id] += dz
		prev_x[id] = pos_x[id]
		prev_z[id] = pos_z[id]
		corr_x[id] = 0.0
		corr_z[id] = 0.0
		return
	corr_count += 1
	corr_x[id] = dx
	corr_z[id] = dz

const RECONCILE_IGNORE := 2.0
const RECONCILE_SNAP := 60.0

## Client: apply one authoritative snapshot record (position, hp fraction, server flags).
## `snap_tick` is the server tick the record was taken at (-1 = unknown -> compare with now).
func reconcile(id: int, sx: float, sz: float, hp_frac: float, server_flags: int, snap_tick: int = -1) -> void:
	if id < 0 or id >= count:
		return
	if (server_flags & F_ALIVE) == 0:
		kill_unit(id)
		return
	if not is_alive(id):
		return
	hp[id] = clampf(hp_frac, 0.0, 1.0) * max_hp[id]
	if (server_flags & F_IN_COMBAT) != 0:
		_srv_combat_until[id] = tick + SERVER_COMBAT_HOLD_TICKS
	else:
		_srv_combat_until[id] = 0
	var rx := INF
	var rz := INF
	var ignore := RECONCILE_IGNORE
	if snap_tick > tick:
		# We have not simulated that tick yet: the server unit may legitimately be up to
		# speed * lag ahead of us, so widen the dead band by that much.
		ignore += speed[id] * SIM_DT * float(snap_tick - tick)
	elif snap_tick >= 0 and tick - snap_tick < HIST_TICKS and not _hist_tick.is_empty():
		var slot: int = snap_tick % HIST_TICKS
		if _hist_tick[slot] == snap_tick:
			var hx: PackedFloat32Array = _hist_x[slot]
			if id < hx.size():
				rx = hx[id]
				rz = (_hist_z[slot] as PackedFloat32Array)[id]
	apply_correction(id, sx, sz, ignore, RECONCILE_SNAP, rx, rz)

func _record_history() -> void:
	if _hist_tick.is_empty():
		_hist_tick.resize(HIST_TICKS)
		_hist_tick.fill(-1)
		_hist_x.resize(HIST_TICKS)
		_hist_z.resize(HIST_TICKS)
	var slot: int = tick % HIST_TICKS
	_hist_tick[slot] = tick
	_hist_x[slot] = pos_x.duplicate()
	_hist_z[slot] = pos_z.duplicate()

func step(dt: float) -> void:
	tick += 1
	time += dt
	died_ids.clear()
	routed_armies.clear()
	repack_requests.clear()
	arrows.clear()
	combat_hits = 0
	prev_x = pos_x.duplicate()
	prev_z = pos_z.duplicate()
	_step_formations(dt)
	hash.build(pos_x, pos_z, flags, count)
	for ai in range(armies.size()):
		if (tick + ai) % ENEMY_NEAR_PERIOD == 0:
			_update_enemy_near(armies[ai])
	_step_units(dt)
	_step_pending_arrows(dt)
	_step_deaths()
	_record_history()
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
		_pushed.resize(count)
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
		if (flags[i] & F_IN_COMBAT) != 0 or _srv_combat_until[i] > tick or _pushed[i] != 0:
			_disp_seen[i] = 0
			_pushed[i] = 0
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
			var ai: int = army[i]
			var a_moving := false
			var a_order := -1
			if ai >= 0 and ai < armies.size():
				a_moving = armies[ai].moving
				a_order = armies[ai].order_type
			move_oscillation_info = "step=(%.2f,%.2f) goal_dist=%.1f corr=(%.2f,%.2f) has_path=%d army=%d moving=%s order=%d" % [
				dx, dz, Vector2(goal_x[i] - pos_x[i], goal_z[i] - pos_z[i]).length(),
				corr_x[i], corr_z[i], _has_path[i], ai, a_moving, a_order
			]

func _step_formations(dt: float) -> void:
	for ix in range(armies.size()):
		var a = armies[ix]
		_army_moving[ix] = 1 if a.moving else 0
		_army_attack_order[ix] = 1 if a.order_type == Formation.OrderType.ATTACK else 0
		_army_offensive[ix] = 1 if (
			a.order_type == Formation.OrderType.ATTACK
			or a.order_type == Formation.OrderType.ATTACK_MOVE
			or a.stance == Formation.Stance.AGGRESSIVE
		) else 0
		var fleeing := ix < _army_melee_flee.size() and _army_melee_flee[ix] != 0
		var was_fleeing := ix < _army_was_fleeing.size() and _army_was_fleeing[ix] != 0
		a.melee_fleeing = fleeing
		if a.is_routed or a.members.is_empty():
			a.melee_fleeing = false
			if ix < _army_was_fleeing.size():
				_army_was_fleeing[ix] = 0
			continue
		var alive: int = _army_alive[a.index]
		var fighting: int = _army_fighting[a.index]
		var contact := 0.0 if alive == 0 else float(fighting) / float(alive)
		# The order is kept. Fleeing only steps the anchor off the path; when contact breaks
		# the same destination is pathed again from where the army now stands.
		if was_fleeing and not fleeing:
			if a.order_type == Formation.OrderType.MOVE or a.order_type == Formation.OrderType.ATTACK_MOVE:
				a.rebuild_current_path()
			elif a.order_type == Formation.OrderType.ATTACK:
				a._target_eval_t = Formation.TARGET_REEVAL_SEC
		if a.order_type == Formation.OrderType.ATTACK and not fleeing:
			var tgt := _attack_order_target_xz(a)
			if tgt.x == INF:
				a.clear_order()
			else:
				var pursuit := MELEE_PURSUIT
				if not a.members.is_empty():
					pursuit = pursuit_for_type(utype[a.members[0]])
				a.update_attack_destination(dt, tgt, pursuit, contact)
		# Cohesion crawl holds the block for stragglers. A player move does not wait:
		# everyone walks the shared path at their own speed.
		var cohesion := 1.0
		var player_march: bool = a.order_type == Formation.OrderType.MOVE or a.order_type == Formation.OrderType.ATTACK_MOVE
		if not player_march and alive > 0 and float(_army_straggling[ix]) > float(alive) * Formation.COHESION_STRAGGLER_FRACTION:
			cohesion = Formation.COHESION_CRAWL_SPEED
		# Client: glide the anchor toward the server's (see FormationController.sync_from_server).
		# Direction-safe like the unit blend: a correction pointing against the march is never
		# applied as a backward slide; the block holds instead and the debt is paid off by the
		# anchor steps it does not take.
		if a.anchor_corr != Vector2.ZERO:
			var ac: Vector2 = a.anchor_corr
			var blend: Vector2 = ac * 0.35
			if a.moving and a.path_i < a.path.size():
				var to: Vector2 = a.path[a.path_i] - a.anchor
				if to.length_squared() > 1e-6:
					var dir: Vector2 = to.normalized()
					var along: float = ac.dot(dir)
					if along < 0.0:
						cohesion = 0.0
						ac += dir * minf(-along, a.anchor_speed * dt)
						blend -= dir * blend.dot(dir)
			a.anchor += blend
			ac -= blend
			if ac.length_squared() < 0.0025:
				ac = Vector2.ZERO
			a.anchor_corr = ac
			a.slots_dirty = true
		var moved: bool
		if fleeing:
			moved = _retreat_anchor(a, dt, _army_flee_x[ix], _army_flee_z[ix])
		else:
			moved = a.advance_anchor(dt, contact, cohesion)
		if ix < _army_was_fleeing.size():
			_army_was_fleeing[ix] = 1 if fleeing else 0
		_army_moving[ix] = 1 if a.moving or fleeing else 0
		_army_dir_x[ix] = 0.0
		_army_dir_z[ix] = 0.0
		if fleeing:
			_army_dir_x[ix] = _army_flee_x[ix]
			_army_dir_z[ix] = _army_flee_z[ix]
		elif a.moving and a.path_i < a.path.size():
			var hd: Vector2 = a.path[a.path_i] - a.anchor
			if hd.length_squared() > 1e-6:
				hd = hd.normalized()
				_army_dir_x[ix] = hd.x
				_army_dir_z[ix] = hd.y
		# Grid compaction is never done here: it is requested and applied later as a scheduled
		# order (same tick on every peer) and only while the army is idle.
		if not a.moving and not a.repack_pending and alive > 0 \
				and alive < int(float(a.packed_count) * Formation.REPACK_FRACTION):
			repack_requests.append(ix)
		# Attack slots follow the anchor. A player march refreshes path goals every tick,
		# because each soldier's cursor advances on its own.
		var marching: bool = player_march and a.moving and not a.path.is_empty() and not fleeing
		if a.slots_dirty or moved or marching:
			_assign_slots(a)
			a.slots_dirty = false
		_step_double_time(a, dt, moved)

## Walk the anchor directly away from melee attackers. The player's order is left in place.
func _retreat_anchor(a, dt: float, dir_x: float, dir_z: float) -> bool:
	var len2 := dir_x * dir_x + dir_z * dir_z
	if len2 < 1e-6:
		a.cruise_speed = Formation.approach_cruise(a.cruise_speed, 0.0, dt)
		return false
	var inv: float = 1.0 / sqrt(len2)
	dir_x *= inv
	dir_z *= inv
	var target: float = a.anchor_speed
	if a.double_time and a.tiredness > -Formation.double_time_tired_max:
		target += Formation.double_time_speed
	if a.slope_scale.is_valid():
		var probe: float = maxf(a.anchor_speed * dt, 0.05)
		var mult: float = float(a.slope_scale.call(a.anchor, a.anchor + Vector2(dir_x, dir_z) * probe))
		if mult < 0.05:
			mult = 0.05
		target *= mult
	a.cruise_speed = Formation.approach_cruise(a.cruise_speed, target, dt)
	var step: float = a.cruise_speed * dt
	var nx: float = a.anchor.x + dir_x * step
	var nz: float = a.anchor.y + dir_z * step
	if not is_walkable(nx, nz):
		if is_walkable(nx, a.anchor.y):
			nz = a.anchor.y
		elif is_walkable(a.anchor.x, nz):
			nx = a.anchor.x
		else:
			return false
	if absf(nx - a.anchor.x) < 1e-6 and absf(nz - a.anchor.y) < 1e-6:
		return false
	var delta := Vector2(nx - a.anchor.x, nz - a.anchor.y)
	a.anchor = Vector2(nx, nz)
	a.hold_position += delta
	a.slots_dirty = true
	return true

## Double time tires the army only while the anchor actually moved. Standing still rests,
## including when the order is still on. At -max the order turns itself off.
func _step_double_time(a, dt: float, moved: bool) -> void:
	var cap: float = Formation.double_time_tired_max
	var rate: float = cap / Formation.double_time_tired_seconds
	if a.double_time and moved:
		a.tiredness = maxf(-cap, a.tiredness - rate * dt)
		if a.tiredness <= -cap:
			a.double_time = false
	elif a.tiredness < 0.0:
		a.tiredness = minf(0.0, a.tiredness + rate * dt)

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
	var members: PackedInt32Array = a.members
	var slots: PackedInt32Array = a.slot_index
	var last: int = offs.size() - 1
	var marching: bool = not a.melee_fleeing and (a.order_type == Formation.OrderType.MOVE or a.order_type == Formation.OrderType.ATTACK_MOVE) and a.moving and not a.path.is_empty()
	if marching and a.index >= 0 and a.index < _army_march_seen.size() and _army_march_seen[a.index] != a.march_seq:
		_army_march_seen[a.index] = a.march_seq
		for id in members:
			if id >= 0 and id < _march_i.size():
				_march_i[id] = 0
				_march_deploy[id] = 0
	var dir: float = a.direction
	var anchor: Vector2 = a.anchor
	var cs := cos(dir)
	var sn := sin(dir)
	var fcs := cos(a.dest_direction)
	var fsn := sin(a.dest_direction)
	for k in range(members.size()):
		var id: int = members[k]
		if (flags[id] & F_ALIVE) == 0:
			continue
		var o: Vector2 = offs[mini(slots[k], last)]
		var gx: float
		var gz: float
		if marching:
			var along := _march_goal(a, id, o)
			var fx: float = a.dest.x + o.x * fcs - o.y * fsn
			var fz: float = a.dest.y + o.x * fsn + o.y * fcs
			var remain := _march_remaining(a.path, _march_i[id], pos_x[id], pos_z[id])
			var deployed := id < _march_deploy.size() and _march_deploy[id] != 0
			if not deployed and remain <= Formation.deploy_distance(a.anchor_speed):
				_march_deploy[id] = 1
				deployed = true
			if deployed:
				# Last stretch: the goal becomes the destination slot and stays there.
				gx = fx
				gz = fz
			else:
				gx = along.x
				gz = along.y
		else:
			gx = anchor.x + o.x * cs - o.y * sn
			gz = anchor.y + o.x * sn + o.y * cs
		if not is_walkable(gx, gz):
			var s := snap_walkable(Vector2(gx, gz))
			gx = s.x
			gz = s.y
		if absf(gx - goal_x[id]) > 0.01 or absf(gz - goal_z[id]) > 0.01:
			goal_x[id] = gx
			goal_z[id] = gz
			_on_goal_changed(id)

## Point on the shared path for this soldier: the waypoint their cursor is on, plus a rank
## offset no wider than one spacing. The cursor only advances.
func _march_goal(a, id: int, slot: Vector2) -> Vector2:
	var path: PackedVector2Array = a.path
	var cursor: int = 0
	if id >= 0 and id < _march_i.size():
		cursor = clampi(_march_i[id], 0, path.size() - 1)
	# Wide enough for the one-spacing column to pass a bend, and narrow enough that a
	# soldier on the far side of a lake cannot skip onto the next leg.
	var reach := maxf(Formation.WAYPOINT_REACH, a.spacing * 2.0)
	var px := pos_x[id]
	var pz := pos_z[id]
	while cursor < path.size() - 1:
		var wp: Vector2 = path[cursor]
		var nxt: Vector2 = path[cursor + 1]
		var rel := Vector2(px - wp.x, pz - wp.y)
		if rel.length() <= reach:
			cursor += 1
			continue
		var ab := nxt - wp
		var len2 := ab.length_squared()
		if len2 < 1e-6:
			break
		var t := rel.dot(ab) / len2
		if t <= 0.0:
			break
		var closest := wp + ab * clampf(t, 0.0, 1.0)
		if Vector2(px, pz).distance_to(closest) > reach:
			break
		cursor += 1
	if id >= 0 and id < _march_i.size():
		_march_i[id] = cursor
	var tangent := Vector2.ZERO
	if cursor < path.size() - 1:
		tangent = path[cursor + 1] - path[cursor]
	elif cursor > 0:
		tangent = path[cursor] - path[cursor - 1]
	if tangent.length_squared() < 1e-6:
		# One waypoint (open ground): the order's travel direction, which is the front.
		tangent = Vector2.from_angle(a.dest_direction - PI * 0.5)
	else:
		tangent = tangent.normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	var pitch: float = a.spacing
	var lateral := clampf(slot.x, -pitch, pitch)
	var stagger := clampf(slot.y, -pitch, pitch) * 0.5
	return path[cursor] - tangent * stagger + normal * lateral

func _march_remaining(path: PackedVector2Array, cursor: int, px: float, pz: float) -> float:
	if path.is_empty():
		return 0.0
	var i := clampi(cursor, 0, path.size() - 1)
	var wp: Vector2 = path[i]
	var remain := Vector2(wp.x - px, wp.y - pz).length()
	while i < path.size() - 1:
		remain += path[i].distance_to(path[i + 1])
		i += 1
	return remain

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
	_army_straggling.fill(0)
	_army_flee_acc_x.fill(0.0)
	_army_flee_acc_z.fill(0.0)
	_army_flee_want.fill(0)
	_army_flee_near.fill(0)
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
	var a_strag := _army_straggling
	var srv_hold := _srv_combat_until
	var pushed := _pushed
	var push_track2 := MOVE_OSC_MIN_DISP * MOVE_OSC_MIN_DISP * 0.25
	var contacts := _contacts
	var cd2 := PackedFloat32Array()
	cd2.resize(CONTACT_SLOTS)
	var catch_up_d2 := CATCH_UP_DIST * CATCH_UP_DIST
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
	var hg := _hg
	var hg_cols := _hg_cols
	var hg_rows := _hg_rows
	var hg_inv := _hg_inv
	var has_hg := hg_cols >= 2 and hg_rows >= 2
	_ensure_rules()
	var slope_at_45 := _slope_speed_at_45
	var slope_deg_max := _max_slope_deg
	var mw := map_w
	var mh := map_h
	var tk := tick
	var a_moving := _army_moving
	var a_dir_x := _army_dir_x
	var a_dir_z := _army_dir_z
	var a_off := _army_offensive
	var a_atk := _army_attack_order
	var a_near := _army_enemy_near
	for i in range(count):
		var f: int = flg_arr[i]
		if (f & F_ALIVE) == 0:
			continue
		if _charge_cd[i] > 0.0:
			_charge_cd[i] = maxf(0.0, _charge_cd[i] - dt)
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
		var ranged := (f & F_RANGED) != 0
		if t >= 0:
			if (flg_arr[t] & F_ALIVE) == 0:
				t = -1
			elif not ranged:
				var tdx: float = px_arr[t] - x
				var tdz: float = pz_arr[t] - z
				if tdx * tdx + tdz * tdz > acq * acq * 1.21:
					t = -1
		if enemy_near and (i % COMBAT_SCAN_PHASES) == phase:
			if t < 0 or attack_order:
				# Wide scans (ranged, or melee acquisition radius) cover many cells; do them
				# half as often and use the cheap weapon-range scan in between.
				# Ranged search uses the longest downhill reach; the check below drops anyone
				# the slope does not actually let them shoot.
				var wide: bool = ((tk >> 2) & 1) == (i & 1)
				var fc = armies[ai] if ai >= 0 else null
				if ranged:
					if wide:
						t = _scan_target(i, fc, _max_ranged_reach(rng))
				else:
					t = _scan_target(i, fc, acq if wide else rng)
		if ranged and t >= 0 and (flg_arr[t] & F_ALIVE) != 0:
			var keep := ranged_reach(x, z, px_arr[t], pz_arr[t], rng)
			var kdx: float = px_arr[t] - x
			var kdz: float = pz_arr[t] - z
			if kdx * kdx + kdz * kdz > keep * keep * 1.21:
				t = -1
		tgt_arr[i] = t
		var in_combat := t >= 0
		# A ranged soldier inside a non-ranged enemy's weapon reach cannot shoot. The army
		# keeps walking away until everyone is clear of that reach (see MELEE_FLEE_CLEAR).
		var melee_id := -1
		var in_swing := false
		if ranged:
			melee_id = _nearest_melee_attacker(i)
			if melee_id >= 0:
				var mdx0: float = x - px_arr[melee_id]
				var mdz0: float = z - pz_arr[melee_id]
				var md2 := mdx0 * mdx0 + mdz0 * mdz0
				var mreach: float = rng_arr[melee_id]
				in_swing = md2 <= mreach * mreach
				var keep_flee := in_swing or (ai >= 0 and _army_melee_flee[ai] != 0)
				if not keep_flee:
					melee_id = -1
				elif ai >= 0:
					_army_flee_near[ai] = 1
					if in_swing:
						_army_flee_want[ai] = 1
					var md := sqrt(md2)
					if md > 0.001:
						_army_flee_acc_x[ai] += mdx0 / md
						_army_flee_acc_z[ai] += mdz0 / md
					else:
						_army_flee_acc_x[ai] += 1.0 if (i & 1) == 0 else -1.0
		if in_combat:
			f |= F_IN_COMBAT
			if ai >= 0:
				a_fight[ai] += 1
		else:
			f &= ~F_IN_COMBAT
			# Idle fast path: standing in its slot with no target, no pending correction and a
			# parked formation. Only every 4th tick runs the full separation/steering pass so
			# neighbours can still push it; the rest of the time it costs a handful of ops.
			# A ranged soldier in a melee swing still has to walk away, so this path is skipped.
			if not in_swing and ((tk + i) & 3) != 0 and not army_moving and has_path[i] == 0:
				var idx: float = gx_arr[i] - x
				var idz: float = gz_arr[i] - z
				if idx * idx + idz * idz <= STEER_DEADZONE * STEER_DEADZONE and cx_arr[i] == 0.0 and cz_arr[i] == 0.0:
					f &= ~F_MOVING
					_cruise[i] = 0.0
					if f != flg_arr[i]:
						dirty[i] = tk
						flg_arr[i] = f
					continue
		var spd: float = spd_arr[i]
		var step_len := spd * dt

		# --- attack on cooldown ---
		var at: float = atk_t[i] - dt
		if in_swing and at < 0.0:
			at = 0.0
		if in_combat and at <= 0.0 and not in_swing:
			var tdx2: float = px_arr[t] - x
			var tdz2: float = pz_arr[t] - z
			var reach2 := rng * rng
			if (f & F_RANGED) != 0:
				var rr := ranged_reach(x, z, px_arr[t], pz_arr[t], rng)
				reach2 = rr * rr
			if tdx2 * tdx2 + tdz2 * tdz2 <= reach2:
				at = 1.0
				_perform_attack(i, t)
		atk_t[i] = at

		# --- steering: melee closes on its target unless a normal MOVE is in progress ---
		# Ranged soldiers already in a melee swing walk straight away when their slot does not.
		var nx := x
		var nz := z
		var flee_steer := false
		var adx := 0.0
		var adz := 0.0
		if in_swing and melee_id >= 0:
			adx = x - px_arr[melee_id]
			adz = z - pz_arr[melee_id]
			var gdx: float = gx_arr[i] - x
			var gdz: float = gz_arr[i] - z
			flee_steer = gdx * adx + gdz * adz <= 0.0
		if flee_steer:
			var ad2 := adx * adx + adz * adz
			if ad2 < 0.0001:
				adx = 1.0 if (i & 1) == 0 else -1.0
				adz = 0.0
				ad2 = 1.0
			var inv_ad := 1.0 / sqrt(ad2)
			var stp_f := _cruise_step(i, adx * inv_ad, adz * inv_ad, 10000.0, spd, 1.0, dt, hg, hg_cols, hg_rows, hg_inv, has_hg, slope_at_45, slope_deg_max)
			nx = x + adx * inv_ad * stp_f
			nz = z + adz * inv_ad * stp_f
			if adx > 0.05 * step_len:
				f |= F_FACING_RIGHT
			elif adx < -0.05 * step_len:
				f &= ~F_FACING_RIGHT
			stuck_arr[i] = 0.0
		elif in_combat and (f & F_RANGED) == 0 and (offensive or not army_moving):
			var tdx3: float = px_arr[t] - x
			var tdz3: float = pz_arr[t] - z
			var td := sqrt(tdx3 * tdx3 + tdz3 * tdz3)
			var reach := rng * 0.85
			if td > reach:
				var inv_td := 1.0 / td
				var stp2 := _cruise_step(i, tdx3 * inv_td, tdz3 * inv_td, td - reach, spd, 1.0, dt, hg, hg_cols, hg_rows, hg_inv, has_hg, slope_at_45, slope_deg_max)
				nx = x + tdx3 * inv_td * stp2
				nz = z + tdz3 * inv_td * stp2
			else:
				_cruise[i] = 0.0
			if tdx3 > 0.5:
				f |= F_FACING_RIGHT
			elif tdx3 < -0.5:
				f &= ~F_FACING_RIGHT
			stuck_arr[i] = 0.0
		elif srv_hold[i] > tk:
			# Server reports this soldier fighting while we predict it idle/marching: follow
			# the server (corrections + separation only) instead of pulling it back to its slot.
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
			var dead: float = MARCH_DEADZONE if army_moving else STEER_DEADZONE
			if d2s > dead * dead:
				var d := sqrt(d2s)
				var catch := 1.0
				if army_moving:
					# The anchor eases up the same way, so a soldier in its slot matches it.
					# One behind the slot aims at CATCH_UP_SPEED and still eases there.
					# Beyond CATCH_UP_DIST it counts as a straggler and slows the block.
					catch = Formation.CATCH_UP_SPEED
					if far2 > catch_up_d2 and ai >= 0:
						a_strag[ai] += 1
				var inv_d := 1.0 / d
				var stp := _cruise_step(i, dx * inv_d, dz * inv_d, d, spd, catch, dt, hg, hg_cols, hg_rows, hg_inv, has_hg, slope_at_45, slope_deg_max)
				nx = x + dx * inv_d * stp
				nz = z + dz * inv_d * stp
			else:
				_cruise[i] = 0.0
			if d2s > dead * dead:
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

		# --- network correction blend (clients), direction-safe ---
		# The part of the correction that opposes the march is dropped: a correction may
		# speed a soldier up, slow it down or slide it sideways, but it can never walk it
		# backwards through its slot (the old rubber-band). "Backwards" is measured against
		# the block's heading while the army marches and against the soldier's own steering
		# step (so a soldier closing on its slot is not yanked away from it again either).
		var cx: float = cx_arr[i]
		var cz: float = cz_arr[i]
		if cx != 0.0 or cz != 0.0:
			var bx := cx * 0.35
			var bz := cz * 0.35
			var hx := 0.0
			var hz := 0.0
			if army_moving and ai >= 0:
				hx = a_dir_x[ai]
				hz = a_dir_z[ai]
			var has_heading := hx != 0.0 or hz != 0.0
			if has_heading:
				var ah := bx * hx + bz * hz
				if ah < 0.0:
					bx -= hx * ah
					bz -= hz * ah
			var sx0 := nx - x
			var sz0 := nz - z
			var s2 := sx0 * sx0 + sz0 * sz0
			if s2 > 1e-6:
				var along := (bx * sx0 + bz * sz0) / s2
				if along < 0.0:
					bx -= sx0 * along
					bz -= sz0 * along
					if has_heading:
						var ah2 := bx * hx + bz * hz
						if ah2 < 0.0:
							bx -= hx * ah2
							bz -= hz * ah2
			nx += bx
			nz += bz
			cx *= 0.65
			cz *= 0.65
			if absf(cx) < 0.05 and absf(cz) < 0.05:
				cx = 0.0
				cz = 0.0
			cx_arr[i] = cx
			cz_arr[i] = cz

		# --- contacts (hash cell walk inlined; this is the hottest loop) ---
		# The neighbour scan runs on alternate ticks (10 Hz) and keeps the CONTACT_SLOTS
		# nearest units that are close to their overlap limit; on the other ticks the list
		# is only pruned. A marching soldier ignores its own army (slots are spaced).
		var r: float = rad_arr[i]
		var my_owner: int = own_arr[i]
		var my_neutral := (f & F_NEUTRAL) != 0
		var cbase: int = i * CONTACT_SLOTS
		if ((tk + i) & 1) == 0:
			var qr := r + SEPARATION_QUERY_PAD + CONTACT_PAD
			if r >= RADIUS_DRAGON:
				qr = r + RADIUS_HORSE + 1.0 + CONTACT_PAD
			for s in range(CONTACT_SLOTS):
				contacts[cbase + s] = -1
				cd2[s] = INF
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
						if army_moving and army_arr[j] == ai:
							continue
						var ddx: float = x - px_arr[j]
						var ddz: float = z - pz_arr[j]
						var d2 := ddx * ddx + ddz * ddz
						if d2 >= qr2:
							continue
						var tol := FRIENDLY_OVERLAP_OK
						if own_arr[j] != my_owner and not (my_neutral and (flg_arr[j] & F_NEUTRAL) != 0):
							tol = ENEMY_OVERLAP_OK
						var lim: float = (r + rad_arr[j]) * tol + CONTACT_PAD
						if d2 >= lim * lim:
							continue
						var worst := 0
						var wd2: float = cd2[0]
						for s in range(1, CONTACT_SLOTS):
							if cd2[s] > wd2:
								wd2 = cd2[s]
								worst = s
						if d2 < wd2:
							contacts[cbase + worst] = j
							cd2[worst] = d2
		else:
			for s in range(CONTACT_SLOTS):
				var j: int = contacts[cbase + s]
				if j < 0:
					continue
				if (flg_arr[j] & F_ALIVE) == 0:
					contacts[cbase + s] = -1
					continue
				var tol := FRIENDLY_OVERLAP_OK
				if own_arr[j] != my_owner and not (my_neutral and (flg_arr[j] & F_NEUTRAL) != 0):
					tol = ENEMY_OVERLAP_OK
				var drop: float = (r + rad_arr[j]) * tol + CONTACT_PAD + CONTACT_DROP_MARGIN
				var ddx: float = x - px_arr[j]
				var ddz: float = z - pz_arr[j]
				if ddx * ddx + ddz * ddz > drop * drop:
					contacts[cbase + s] = -1

		# --- slide: never step deeper into a contact than its overlap limit ---
		# Only the inward part past the limit is removed, so the unit slides around. If that
		# leaves almost nothing (head-on), it sidesteps to the left of the contact normal; the
		# other unit sees the opposite normal, so the two pass each other.
		var sx := nx - x
		var sz := nz - z
		var s_len2 := sx * sx + sz * sz
		if s_len2 > 1e-8:
			var side := sqrt(s_len2) * SIDESTEP_FRAC
			for s in range(CONTACT_SLOTS):
				var j: int = contacts[cbase + s]
				if j < 0:
					continue
				var ox: float = x - px_arr[j]
				var oz: float = z - pz_arr[j]
				var od := sqrt(ox * ox + oz * oz)
				if od < 0.01:
					continue
				var ux := ox / od
				var uz := oz / od
				var inward := -(sx * ux + sz * uz)
				if inward <= 0.0:
					continue
				var tol := FRIENDLY_OVERLAP_OK
				if own_arr[j] != my_owner and not (my_neutral and (flg_arr[j] & F_NEUTRAL) != 0):
					tol = ENEMY_OVERLAP_OK
				var allowed := maxf(0.0, od - (r + rad_arr[j]) * tol)
				if inward <= allowed:
					continue
				var cut := inward - allowed
				sx += ux * cut
				sz += uz * cut
				if sx * sx + sz * sz < side * side:
					sx -= uz * side
					sz += ux * side
			nx = x + sx
			nz = z + sz

		# --- weak push: ease overlap left past the limit, never against the order ---
		var ppx := 0.0
		var ppz := 0.0
		for s in range(CONTACT_SLOTS):
			var j: int = contacts[cbase + s]
			if j < 0:
				continue
			var ddx: float = nx - px_arr[j]
			var ddz: float = nz - pz_arr[j]
			var d2 := ddx * ddx + ddz * ddz
			var w := FRIENDLY_PUSH
			var tol := FRIENDLY_OVERLAP_OK
			if own_arr[j] != my_owner and not (my_neutral and (flg_arr[j] & F_NEUTRAL) != 0):
				w = ENEMY_PUSH
				tol = ENEMY_OVERLAP_OK
			var lim: float = (r + rad_arr[j]) * tol
			if d2 >= lim * lim:
				continue
			var dd := sqrt(d2)
			if dd < 0.01:
				# Coincident: deterministic nudge by id parity.
				ddx = 0.01 if (i & 1) == 0 else -0.01
				ddz = 0.01 if (j & 1) == 0 else -0.01
				dd = 0.0141
			var sc := (lim - dd) * w / dd
			ppx += ddx * sc
			ppz += ddz * sc
		if ppx != 0.0 or ppz != 0.0:
			sx = nx - x
			sz = nz - z
			s_len2 = sx * sx + sz * sz
			if s_len2 > 1e-8:
				var along := (ppx * sx + ppz * sz) / s_len2
				if along < 0.0:
					ppx -= sx * along
					ppz -= sz * along
			if army_moving and ai >= 0:
				var hx: float = a_dir_x[ai]
				var hz: float = a_dir_z[ai]
				var ah := ppx * hx + ppz * hz
				if ah < 0.0:
					ppx -= hx * ah
					ppz -= hz * ah
			var pl2 := ppx * ppx + ppz * ppz
			var cap := step_len * PUSH_STEP_FRAC
			if pl2 > cap * cap:
				var k2 := cap / sqrt(pl2)
				ppx *= k2
				ppz *= k2
			if pl2 > push_track2:
				pushed[i] = 1
			nx += ppx
			nz += ppz

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
		_travel_speed[i] = sqrt(mdx * mdx + mdz * mdz) / dt
		var min_disp := maxf(_cruise[i] * dt * 0.15, 0.01)
		if mdx * mdx + mdz * mdz > min_disp * min_disp:
			f |= F_MOVING
			dirty[i] = tk
		else:
			f &= ~F_MOVING
		if f != flg_arr[i]:
			dirty[i] = tk
			flg_arr[i] = f
	for ai in range(_army_melee_flee.size()):
		var flee := _army_flee_want[ai] != 0 or (_army_melee_flee[ai] != 0 and _army_flee_near[ai] != 0)
		_army_melee_flee[ai] = 1 if flee else 0
		if not flee:
			_army_flee_x[ai] = 0.0
			_army_flee_z[ai] = 0.0
			continue
		var fx: float = _army_flee_acc_x[ai]
		var fz: float = _army_flee_acc_z[ai]
		var fl := sqrt(fx * fx + fz * fz)
		if fl > 0.001:
			_army_flee_x[ai] = fx / fl
			_army_flee_z[ai] = fz / fl
		else:
			_army_flee_x[ai] = 0.0
			_army_flee_z[ai] = 0.0

## Nearest hostile non-ranged unit that can reach `i`, including the flee clear gap.
## -1 when nobody is that close. Tie goes to the lower id.
func _nearest_melee_attacker(i: int) -> int:
	var x: float = pos_x[i]
	var z: float = pos_z[i]
	var my_owner: int = owner_pid[i]
	var my_neutral: bool = (flags[i] & F_NEUTRAL) != 0
	var rad := DRAGON_ATTACK_RANGE + MELEE_FLEE_CLEAR
	var px := pos_x
	var pz := pos_z
	var own := owner_pid
	var flg := flags
	var rngs := attack_range
	var cell_start: PackedInt32Array = hash._cell_start
	var cell_items: PackedInt32Array = hash._cell_items
	var hcols: int = hash.cols
	var inv_cell: float = 1.0 / hash.cell_size
	var cx0: int = maxi(int((x - rad) * inv_cell), 0)
	var cx1: int = mini(int((x + rad) * inv_cell), hcols - 1)
	var cz0: int = maxi(int((z - rad) * inv_cell), 0)
	var cz1: int = mini(int((z + rad) * inv_cell), hash.rows - 1)
	var best := -1
	var best_d2 := INF
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
				if (jf & F_ALIVE) == 0 or (jf & F_RANGED) != 0:
					continue
				if my_neutral and (jf & F_NEUTRAL) != 0:
					continue
				var dx: float = px[j] - x
				var dz: float = pz[j] - z
				var d2 := dx * dx + dz * dz
				var reach: float = rngs[j] + MELEE_FLEE_CLEAR
				if d2 > reach * reach:
					continue
				if d2 < best_d2 or (d2 == best_d2 and (best < 0 or j < best)):
					best_d2 = d2
					best = j
	return best

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
		var rch: float = attack_range[id]
		if (f & F_RANGED) != 0:
			rch = _max_ranged_reach(rch)
		reach = maxf(reach, rch)
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
	_ensure_rules()
	var atk := attack[i]
	var knight_like := utype[i] == UnitType.KNIGHT or utype[i] == UnitType.KNIGHT_LONG_SPEAR or utype[i] == UnitType.MOUNTED_KNIGHT_SHIELD or utype[i] == UnitType.MOUNTED_LANCE_KNIGHT
	var spear_like := utype[i] == UnitType.SPEARMAN or utype[i] == UnitType.KNIGHT_LONG_SPEAR or utype[i] == UnitType.ARMOURED_PIKE or utype[i] == UnitType.MOUNTED_LANCE_KNIGHT
	if spear_like and (flags[t] & F_HORSE) != 0:
		atk += _spear_vs_horse_attack
	if knight_like and (flags[t] & F_HORSE) == 0 and utype[t] != UnitType.SPEARMAN:
		atk += _knight_vs_unmounted_attack
	if knight_like and _charge_cd[i] <= 0.0 and _travel_speed[i] >= speed[i] * _knight_charge_min_speed_ratio:
		atk += _knight_charge_attack
		_charge_cd[i] = _knight_charge_cooldown
	if height_at(pos_x[i], pos_z[i]) - height_at(pos_x[t], pos_z[t]) > 0.0:
		atk += _height_attack
	var dmg := maxf(1.0, atk - defense[t]) * damage_multiplier
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
