extends Node
## Thin per-army handle around a FormationController living in UnitSim.
## Holds identity, ownership and selection so MockPlayer, ArmyCommandBar and the World UI
## keep a node to talk to; all movement/combat state lives in the sim (see sim/UnitSim.gd).

enum Stance { AGGRESSIVE, DEFENSIVE, HOLD, PASSIVE }

signal selection_changed(army, selected: bool)

var army_id: String = ""
var owner_id: int = 0
var owner_name: String = ""
var is_npc: bool = false
var is_selected: bool = false
var has_horse: bool = false
var has_spear: bool = false
var has_bow: bool = false
var sim_index: int = -1
## FormationController (RefCounted) owned by the sim.
var fc = null

var is_routed: bool:
	get:
		return fc != null and fc.is_routed

var stance: int:
	get:
		return fc.stance if fc != null else Stance.DEFENSIVE
	set(v):
		if fc != null:
			fc.set_stance(v)

var direction: float:
	get:
		return fc.front_angle() if fc != null else 0.0

func setup(p_army_id: String, p_owner_id: int, p_owner_name: String, p_fc) -> void:
	army_id = p_army_id
	owner_id = p_owner_id
	owner_name = p_owner_name
	fc = p_fc
	if fc != null:
		sim_index = fc.index
		has_horse = fc.has_horse
		has_spear = fc.has_spear
		has_bow = fc.has_bow
	name = "Army_" + army_id

func unit_ids() -> PackedInt32Array:
	return fc.members if fc != null else PackedInt32Array()

func select() -> void:
	if is_selected:
		return
	is_selected = true
	selection_changed.emit(self, true)

func deselect() -> void:
	if not is_selected:
		return
	is_selected = false
	selection_changed.emit(self, false)

func soldier_count() -> int:
	return fc.members.size() if fc != null else 0

func is_ranged() -> bool:
	return has_bow

func uses_mounted_spacing() -> bool:
	return has_horse

func anchor() -> Vector2:
	return fc.anchor if fc != null else Vector2.ZERO
