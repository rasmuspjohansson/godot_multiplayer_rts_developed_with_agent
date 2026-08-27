extends RefCounted
## Data-driven combat/movement behaviour per unit type (RTS_Unit_Behaviour_Spec §5, §11).

const MELEE_PURSUIT := 80.0
const RANGED_PURSUIT := 40.0
const CAVALRY_PURSUIT := 100.0

static func profile_for_unit_type(unit_type: String) -> Dictionary:
	match unit_type:
		"bowman", "bauer_horse_archer":
			return {
				"attack_while_moving": true,
				"pursuit_distance": RANGED_PURSUIT,
			}
		"knight":
			return {
				"attack_while_moving": false,
				"pursuit_distance": CAVALRY_PURSUIT,
			}
		_:
			return {
				"attack_while_moving": false,
				"pursuit_distance": MELEE_PURSUIT,
			}

static func profile_for_unit(unit) -> Dictionary:
	if unit == null:
		return profile_for_unit_type("")
	var ut := ""
	if unit.has_method("get_unit_type"):
		ut = str(unit.get_unit_type())
	elif unit.get("unit_type") != null:
		ut = str(unit.get("unit_type"))
	return profile_for_unit_type(ut)

static func stance_allows_auto_engage(stance: int) -> bool:
	# Army3D.Stance: AGGRESSIVE=0, DEFENSIVE=1, HOLD=2, PASSIVE=3
	return stance == 0 or stance == 1

static func stance_allows_pursuit(stance: int) -> bool:
	return stance == 0
