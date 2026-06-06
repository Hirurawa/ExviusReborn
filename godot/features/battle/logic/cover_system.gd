extends RefCounted
class_name CoverSystem

## Encapsulates cover interception and the per-turn transient cover state stored
## on unit dicts. Owned by BattleManager; pure logic over unit-dict arrays so the
## class is easy to unit-test in isolation.

const STATE_AOE: String = "is_aoe_covering"
const STATE_ST: String = "is_st_covering"
const STATE_MITIGATION: String = "active_cover_mitigation"

const _INTERCEPTABLE_EFFECT_TYPES := ["physical_damage", "magic_damage"]


## True if the incoming effect type is one that cover effects can intercept.
static func is_interceptable_effect(effect: Dictionary) -> bool:
	return str(effect.get("type", "")).to_lower() in _INTERCEPTABLE_EFFECT_TYPES


## Returns the active AOE coverer in the defending pool (the unit that has
## already proc'd AOE cover this turn), or an empty dict if none.
static func find_active_aoe_coverer(defending_pool: Array) -> Dictionary:
	for unit_data in defending_pool:
		var unit: Dictionary = unit_data
		if unit.is_empty() or int(unit.get("current_hp", 0)) <= 0:
			continue
		var transient: Dictionary = unit.get("transient_turn_state", {})
		if bool(transient.get(STATE_AOE, false)):
			return unit
	return {}


## True if some other living unit in the pool is currently single-target covering
## the given unit (so the given unit can't take incoming hits).
static func is_unit_currently_st_covered(unit: Dictionary, defending_pool: Array) -> bool:
	var unit_identity: String = str(unit.get("identity", ""))
	if unit_identity == "":
		return false

	for other_data in defending_pool:
		var other: Dictionary = other_data
		if other == unit:
			continue
		if other.is_empty() or int(other.get("current_hp", 0)) <= 0:
			continue
		var transient: Dictionary = other.get("transient_turn_state", {})
		if str(transient.get(STATE_ST, "")) == unit_identity:
			return true

	return false


## Of all AOE cover effects on the defender that match the incoming damage type,
## returns the one with the highest proc chance. Empty dict if none qualify.
static func get_best_aoe_cover_effect(defender: Dictionary, incoming_effect_type: String) -> Dictionary:
	var best_effect: Dictionary = {}
	var best_chance: float = -1.0

	for active_effect_data in defender.get("active_effects", []):
		var active_effect: Dictionary = active_effect_data
		if str(active_effect.get("type", "")).to_lower() != "aoe_cover":
			continue
		if not _cover_supports_effect_type(active_effect, incoming_effect_type):
			continue

		var chance: float = clampf(float(active_effect.get("params", {}).get("pct_chance", 0.0)), 0.0, 100.0)
		if chance > best_chance:
			best_chance = chance
			best_effect = active_effect

	return best_effect


## Apply cover interception to the intended targets of an incoming effect.
## Returns the (possibly re-routed) target list. Mutates defender transient state
## when a cover effect procs.
static func evaluate_interception(intended_targets: Array[Dictionary], effect: Dictionary, defending_pool: Array) -> Array[Dictionary]:
	if _should_skip_interception(intended_targets, effect):
		return intended_targets

	# Someone already procced AOE cover this turn — redirect everything to them.
	var active_aoe_coverer: Dictionary = find_active_aoe_coverer(defending_pool)
	if not active_aoe_coverer.is_empty():
		return _redirect_all_to(intended_targets, active_aoe_coverer)

	var incoming_effect_type: String = str(effect.get("type", "")).to_lower()

	for defender_data in defending_pool:
		var defender: Dictionary = defender_data
		if not _is_defender_eligible_for_cover(defender, defending_pool):
			continue

		var cover_effect: Dictionary = get_best_aoe_cover_effect(defender, incoming_effect_type)
		if cover_effect.is_empty():
			continue

		var allies_in_danger: int = _count_other_targets(intended_targets, defender)
		if allies_in_danger <= 0:
			continue

		if not _roll_cover_proc(cover_effect, allies_in_danger):
			continue

		_apply_cover_state(defender, cover_effect)
		return _redirect_all_to(intended_targets, defender)

	return intended_targets


## Reduces incoming damage by any active cover mitigation flagged on the target.
static func apply_active_cover_mitigation(target: Dictionary, incoming_damage: int) -> int:
	if incoming_damage <= 0:
		return incoming_damage

	var transient: Dictionary = target.get("transient_turn_state", {})
	if transient.is_empty() or not transient.has(STATE_MITIGATION):
		return incoming_damage

	var mitigation_pct: int = clampi(int(transient.get(STATE_MITIGATION, 0)), 0, 100)
	var mitigated_damage: int = int(round(float(incoming_damage) * (100.0 - float(mitigation_pct)) / 100.0))
	return maxi(0, mitigated_damage)


## Wipes per-turn cover state (AOE/ST/mitigation) from every unit in the pool.
## Called at the end of each team's turn.
static func clear_transient_state(defending_pool: Array) -> void:
	for unit_data in defending_pool:
		var unit: Dictionary = unit_data
		if unit.is_empty():
			continue
		var transient: Dictionary = unit.get("transient_turn_state", {})
		if transient.is_empty():
			continue

		transient.erase(STATE_AOE)
		transient.erase(STATE_ST)
		transient.erase(STATE_MITIGATION)

		if transient.is_empty():
			unit.erase("transient_turn_state")
		else:
			unit["transient_turn_state"] = transient


# --- private helpers --------------------------------------------------------

static func _should_skip_interception(intended_targets: Array[Dictionary], effect: Dictionary) -> bool:
	return intended_targets.is_empty() or not is_interceptable_effect(effect)


static func _is_defender_eligible_for_cover(defender: Dictionary, defending_pool: Array) -> bool:
	if defender.is_empty() or int(defender.get("current_hp", 0)) <= 0:
		return false
	# Can't cover if someone else is already covering this defender.
	return not is_unit_currently_st_covered(defender, defending_pool)


static func _count_other_targets(intended_targets: Array, defender: Dictionary) -> int:
	var count: int = 0
	for target in intended_targets:
		if target != defender:
			count += 1
	return count


static func _roll_cover_proc(cover_effect: Dictionary, allies_in_danger: int) -> bool:
	var chance: float = clampf(float(cover_effect.get("params", {}).get("pct_chance", 0.0)), 0.0, 100.0)
	if chance <= 0.0:
		return false
	for i in range(allies_in_danger):
		if randf() * 100.0 < chance:
			return true
	return false


static func _redirect_all_to(intended_targets: Array[Dictionary], new_target: Dictionary) -> Array[Dictionary]:
	var redirected: Array[Dictionary] = []
	for i in range(intended_targets.size()):
		redirected.append(new_target)
	return redirected


static func _apply_cover_state(defender: Dictionary, cover_effect: Dictionary) -> void:
	var transient: Dictionary = _ensure_transient_state(defender)
	transient[STATE_AOE] = true
	defender["transient_turn_state"] = transient
	_flag_mitigation(defender, cover_effect)


static func _ensure_transient_state(unit: Dictionary) -> Dictionary:
	var transient: Dictionary = unit.get("transient_turn_state", {})
	if transient.is_empty():
		transient = {}
		unit["transient_turn_state"] = transient
	return transient


static func _flag_mitigation(defender: Dictionary, cover_effect: Dictionary) -> void:
	var transient: Dictionary = _ensure_transient_state(defender)
	var params: Dictionary = cover_effect.get("params", {})

	var mitigation_min: int = int(params.get("dmg_reduce_min", 0))
	var mitigation_max: int = int(params.get("dmg_reduce_max", mitigation_min))

	if mitigation_max < mitigation_min:
		var swap_value: int = mitigation_min
		mitigation_min = mitigation_max
		mitigation_max = swap_value

	mitigation_min = clampi(mitigation_min, 0, 100)
	mitigation_max = clampi(mitigation_max, 0, 100)

	var rolled_mitigation: int = mitigation_min
	if mitigation_max > mitigation_min:
		rolled_mitigation = (randi() % ((mitigation_max - mitigation_min) + 1)) + mitigation_min

	transient[STATE_MITIGATION] = rolled_mitigation
	defender["transient_turn_state"] = transient


static func _cover_supports_effect_type(cover_effect: Dictionary, incoming_effect_type: String) -> bool:
	var effect_type: String = incoming_effect_type.to_lower()
	if effect_type not in _INTERCEPTABLE_EFFECT_TYPES:
		return false

	var params: Dictionary = cover_effect.get("params", {})
	var phys_mag_mode = params.get("phys_mag", "both")

	if typeof(phys_mag_mode) == TYPE_STRING:
		var mode_text: String = str(phys_mag_mode).to_lower()
		if mode_text in ["physical", "phys"]:
			return effect_type == "physical_damage"
		if mode_text in ["magic", "mag"]:
			return effect_type == "magic_damage"
		return true

	if typeof(phys_mag_mode) in [TYPE_INT, TYPE_FLOAT]:
		var mode_id: int = int(phys_mag_mode)
		if mode_id == 1:
			return effect_type == "physical_damage"
		if mode_id == 2:
			return effect_type == "magic_damage"

	return true
