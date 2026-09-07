extends RefCounted
## One army = one formation. Owns the order, the single A* path for the whole army and the
## anchor that travels along it; soldiers (ids into UnitSim) steer toward anchor + slot offset.
## Runs identically on server and clients from the same order stream.

enum Stance { AGGRESSIVE, DEFENSIVE, HOLD, PASSIVE }
enum OrderType { NONE, MOVE, ATTACK, ATTACK_MOVE }

const FOOT_SPACING := 10.0
const MOUNTED_SPACING := 15.0
const ROUT_THRESHOLD := 0.3
## Anchor speed relative to the slowest soldier; soldiers catch up at CATCH_UP_SPEED.
const ANCHOR_SPEED_SCALE := 0.9
const CATCH_UP_SPEED := 1.35
## Anchor slows to a press while this fraction of soldiers is fighting (formation holds the line).
const CONTACT_PAUSE_FRACTION := 0.35
const CONTACT_RESUME_FRACTION := 0.15
const CONTACT_PRESS_SPEED := 0.25
const TARGET_REEVAL_SEC := 0.5
const DEST_CHANGE_MIN := 20.0
const IDLE_CLOSE_MIN := 4.0
const WAYPOINT_REACH := 6.0
## Slot repack happens when the alive count falls below this fraction of the packed count.
const REPACK_FRACTION := 0.8

var index: int = -1
var army_id: String = ""
var owner_pid: int = 0
var owner_name: String = ""
var is_npc: bool = false
var members: PackedInt32Array = PackedInt32Array()
var initial_count: int = 0
var is_routed: bool = false

var direction: float = 0.0
var rows: int = 2
var spacing: float = FOOT_SPACING
var stance: int = Stance.DEFENSIVE

var order_type: int = OrderType.NONE
var order_seq: int = 0
var order_dest: Vector2 = Vector2.ZERO
var order_target_army: int = -1
var order_target_unit: int = -1
var hold_position: Vector2 = Vector2.ZERO

var anchor: Vector2 = Vector2.ZERO
var dest: Vector2 = Vector2.ZERO
var path: PackedVector2Array = PackedVector2Array()
var path_i: int = 0
var moving: bool = false
var paused_for_contact: bool = false
var anchor_speed: float = 10.0
var slots_dirty: bool = true
var packed_count: int = 0
var _target_eval_t: float = TARGET_REEVAL_SEC
var _offset_cache: Dictionary = {}
var has_horse: bool = false
var has_spear: bool = false
var has_bow: bool = false

func default_rows_for(count: int) -> int:
	return clampi(ceili(float(count) / 12.0), 2, 6)

## Slot offsets (local space, +x along the line, +y toward the rear) for `count` soldiers.
func slot_offsets(count: int) -> PackedVector2Array:
	if _offset_cache.has(count):
		return _offset_cache[count]
	var out := PackedVector2Array()
	if count > 0:
		var r: int = maxi(1, rows)
		var c: int = maxi(1, ceili(float(count) / float(r)))
		var idx := 0
		for row in range(r):
			for col in range(c):
				if idx >= count:
					break
				out.append(Vector2(
					(float(col) - float(c - 1) * 0.5) * spacing,
					(float(row) - float(r - 1) * 0.5) * spacing
				))
				idx += 1
	_offset_cache[count] = out
	return out

func set_rows(r: int) -> void:
	r = clampi(r, 1, 12)
	if r == rows:
		return
	rows = r
	_offset_cache.clear()
	slots_dirty = true

func set_spacing(s: float) -> void:
	if is_equal_approx(s, spacing):
		return
	spacing = s
	_offset_cache.clear()
	slots_dirty = true

func slot_world(offset: Vector2) -> Vector2:
	return anchor + offset.rotated(direction)

func half_width() -> float:
	var c: int = maxi(1, ceili(float(maxi(packed_count, 1)) / float(maxi(rows, 1))))
	return float(c - 1) * 0.5 * spacing

func has_player_order() -> bool:
	return order_type != OrderType.NONE

func clear_order() -> void:
	order_type = OrderType.NONE
	order_target_army = -1
	order_target_unit = -1
	moving = false
	path = PackedVector2Array()
	path_i = 0

func set_stance(s: int) -> void:
	stance = s
	if s == Stance.HOLD:
		hold_position = anchor

## MOVE: one path from the current anchor to dest. `facing` < -100 keeps travel direction.
func issue_move(p_dest: Vector2, facing: float = -999.0, attack_move: bool = false) -> void:
	order_type = OrderType.ATTACK_MOVE if attack_move else OrderType.MOVE
	order_target_army = -1
	order_target_unit = -1
	order_dest = p_dest
	_start_path_to(p_dest, facing)

func issue_attack_army(target_idx: int) -> void:
	order_type = OrderType.ATTACK
	order_target_army = target_idx
	order_target_unit = -1
	hold_position = anchor
	_target_eval_t = TARGET_REEVAL_SEC

func issue_attack_unit(target_id: int) -> void:
	order_type = OrderType.ATTACK
	order_target_army = -1
	order_target_unit = target_id
	hold_position = anchor
	_target_eval_t = TARGET_REEVAL_SEC

func rotate(delta_angle: float) -> void:
	direction += delta_angle
	slots_dirty = true

## Called by UnitSim with a path finder; sets dest/path and faces travel direction.
var _pathfinder: Callable = Callable()

func _start_path_to(p_dest: Vector2, facing: float) -> void:
	dest = p_dest
	path = PackedVector2Array()
	if _pathfinder.is_valid():
		path = _pathfinder.call(anchor, p_dest)
	if path.is_empty():
		path = PackedVector2Array([p_dest])
	path_i = 0
	moving = true
	paused_for_contact = false
	if facing > -100.0:
		direction = facing
	else:
		var to := p_dest - anchor
		if to.length() > 1.0:
			direction = line_direction_for_front(to.angle())
	slots_dirty = true

## `direction` is the angle of the line's +x axis; the front of the formation is at
## `direction - PI/2` (local -y). Converts a desired front angle into a line direction.
static func line_direction_for_front(front_angle: float) -> float:
	return front_angle + PI * 0.5

func front_angle() -> float:
	return direction - PI * 0.5

## Choose the number of rows so the line is at most `width` wide.
func fit_rows_to_width(count: int, width: float) -> void:
	var cols: int = maxi(1, int(floor(width / maxf(spacing, 0.01))) + 1)
	set_rows(clampi(ceili(float(maxi(count, 1)) / float(cols)), 1, 12))

## Advance the anchor one tick along the path. Returns true if the anchor moved.
func advance_anchor(dt: float, contact_fraction: float) -> bool:
	if not moving:
		return false
	var budget := anchor_speed * dt
	if paused_for_contact:
		if contact_fraction < CONTACT_RESUME_FRACTION:
			paused_for_contact = false
		elif order_type == OrderType.ATTACK:
			budget *= CONTACT_PRESS_SPEED
		else:
			return false
	elif contact_fraction >= CONTACT_PAUSE_FRACTION and order_type != OrderType.MOVE:
		paused_for_contact = true
		if order_type == OrderType.ATTACK:
			budget *= CONTACT_PRESS_SPEED
		else:
			return false
	var moved := false
	while budget > 0.0 and path_i < path.size():
		var wp: Vector2 = path[path_i]
		var to := wp - anchor
		var d := to.length()
		var is_last := path_i == path.size() - 1
		var reach := 0.25 if is_last else WAYPOINT_REACH
		if d <= reach:
			if is_last:
				anchor = wp
				moved = true
			path_i += 1
			continue
		var step := minf(d, budget)
		anchor += to / d * step
		budget -= step
		moved = true
		if step >= d:
			path_i += 1
	if path_i >= path.size():
		moving = false
		if order_type == OrderType.MOVE:
			# Arrived: keep formation, order complete.
			order_type = OrderType.NONE
	return moved

## ATTACK pursuit: re-path toward `target_xz` at most every TARGET_REEVAL_SEC and only if the
## target moved. Non-aggressive stances are leashed to hold_position by `pursuit`.
func update_attack_destination(dt: float, target_xz: Vector2, pursuit: float, contact_fraction: float = 0.0) -> void:
	_target_eval_t += dt
	if _target_eval_t < TARGET_REEVAL_SEC:
		return
	_target_eval_t = 0.0
	var wanted := target_xz
	if stance != Stance.AGGRESSIVE:
		var leash := pursuit * (0.5 if stance == Stance.HOLD else 1.0)
		var from_hold := wanted - hold_position
		if from_hold.length() > leash:
			wanted = hold_position + from_hold.normalized() * leash
	if moving and wanted.distance_to(dest) < DEST_CHANGE_MIN:
		return
	if not moving:
		# Standing still with nobody fighting: close the remaining gap instead of waiting for the
		# target to drift DEST_CHANGE_MIN away (that wait was a stalemate with small armies).
		var min_change := DEST_CHANGE_MIN if contact_fraction > 0.0 else IDLE_CLOSE_MIN
		if wanted.distance_to(anchor) < min_change:
			return
	_start_path_to(wanted, -999.0)
