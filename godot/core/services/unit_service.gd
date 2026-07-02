extends Node

## UnitService
##
## Owns the player's unit roster (owned_units_ids), summon/enhance/awaken/xp
## flows, equipment requests, hydration, and unit XP-pattern tables.
## Persists via the Persistence autoload using `units.json`.

signal units_updated(units: Array)
signal equip_successful()
signal equip_failed(error_message: String)
signal equip_conflict(target_unit_id: String, slot_id: String, item_id: String, conflicting_unit_id: String)

const SNAPSHOT_FILE: String = "units.json"

const STARTER_RAIN_UNIT_ID: String = "100000102"
const STARTER_LASSWELL_UNIT_ID: String = "100000202"
const STARTER_RAIN_INSTANCE_ID: String = "starter_100000102"
const STARTER_LASSWELL_INSTANCE_ID: String = "starter_100000202"

const ENHANCE_MAX_TRUST_VALUE: float = 100.0
const ENHANCE_GIL_COST_PER_MATERIAL: int = 1000
const SELL_GIL_PER_UNIT: int = 1000
const ENHANCE_BASE_XP_GAIN: int = 100
const ENHANCE_XP_PER_RARITY: int = 100
const ENHANCE_XP_PER_LEVEL: int = 20
const ENHANCE_BASE_TRUST_GAIN: float = 0.2
const ENHANCE_TRUST_PER_RARITY: float = 0.15
const ENHANCE_TRUST_PER_LEVEL: float = 0.01
const UNIT_TYPE_PLAYABLE: String = "playable"
const UNIT_TYPE_EXP_MATERIAL: String = "exp_material"
const UNIT_TYPE_TRUST_MATERIAL: String = "trust_material"
const PLAYABLE_ACCUMULATED_EXP_TRANSFER_RATE: float = 0.5
const PLAYABLE_DUPLICATE_TRUST_BONUS: float = 5.0
const DEFAULT_MAX_ACCUMULATED_EXP: int = 2000000000
const EXP_UNIT_JOB_ID: int = 901
const TRUST_MATERIAL_JOB_ID: int = 903
const MATERIAL_UNIT_JOB_IDS: Array[int] = [900, 901, 902, 903]
const EXP_UNIT_YIELD_BY_PATTERN: Dictionary = {
	201: 5000,
	202: 10000,
	203: 30000, # MIN_EXP: 30000, MAX_EXP: 1290000
	204: 1000000, # MIN_EXP: 100000, MAX_EXP: 4500000
}
const TRUST_YIELD_BY_UNIT_ID: Dictionary = {
	904000101: 1.0,
	904000104: 5.0,
	904000105: 50.0,
}

var owned_units_ids: Array = []
var _unit_exp_patterns_cache: Dictionary = {}

# === Public API ===

func emit_updated() -> void:
	units_updated.emit(owned_units_ids)

func snapshot_payload() -> Dictionary:
	var lean_units: Array = []
	for unit in owned_units_ids:
		if unit is Dictionary:
			lean_units.append(_extract_unit_lean_record(unit))
		else:
			lean_units.append(unit)
	return {"owned_units": lean_units}

func load_from_local() -> void:
	owned_units_ids = _load_units_from_local()

func reset_to_starter() -> bool:
	var rain_unit: Dictionary = build_starter_unit(STARTER_RAIN_UNIT_ID, STARTER_RAIN_INSTANCE_ID)
	var lasswell_unit: Dictionary = build_starter_unit(STARTER_LASSWELL_UNIT_ID, STARTER_LASSWELL_INSTANCE_ID)
	if rain_unit.is_empty() or lasswell_unit.is_empty():
		return false
	owned_units_ids = _hydrate_owned_units([rain_unit, lasswell_unit])
	return true

func build_starter_unit(unit_id: String, instance_id: String) -> Dictionary:
	var unit_data: Dictionary = GameDatabase.get_unit(unit_id)
	if unit_data.is_empty():
		return {}

	var initial_rarity: int = _get_unit_initial_rarity(unit_id)
	var exp_pattern: int = _get_raw_unit_exp_pattern(unit_id, unit_data, initial_rarity)
	if exp_pattern <= 0:
		exp_pattern = 5
	var next_xp_required: int = _calculate_total_xp_for_level_local(2, exp_pattern)
	if next_xp_required <= 0:
		next_xp_required = 1000

	return {
		"instance_id": instance_id,
		"unit_id": unit_id,
		"level": 1,
		"xp": 0,
		"current_rarity": initial_rarity,
		"next_xp": next_xp_required,
		"equipment": {},
		"trust_value": 0,
		"limitburst_level": 1,
		"limitburst_xp": 0,
		"is_locked": false,
		"trust_reward_claimed": false,
		"current_accumulated_exp": 0
	}

func summon_units(amount: int) -> Dictionary:
	var summoned_units: Array = []
	var unit_ids: Array = []

	var all_units = GameDatabase.query("SELECT u.unitId, u.isSummonable, u.rare, u.unitSeries FROM unit u INNER JOIN (SELECT unitSeries, MIN(rare) AS min_rarity FROM unit GROUP BY unitSeries) min_r ON u.unitSeries = min_r.unitSeries AND u.rare = min_r.min_rarity")
	for row in all_units:
		if int(row.get("isSummonable", 0)) == 1:
			unit_ids.append(str(row.get("unitId")))

	if unit_ids.is_empty():
		return {"error": "ERR_NO_UNITS_AVAILABLE"}

	for _i in range(amount):
		var random_unit_id: String = unit_ids[randi() % unit_ids.size()]
		var initial_rarity: int = _get_unit_initial_rarity(random_unit_id)
		var new_instance: Dictionary = {
			"unit_id": random_unit_id,
			"instance_id": InventoryService.generate_instance_id(),
			"xp": 0,
			"level": 1,
			"next_xp": 1000,
			"equipment": {},
			"is_locked": false,
			"trust_value": 0,
			"trust_reward_claimed": false,
			"limitburst_xp": 0,
			"limitburst_level": 1,
			"current_rarity": initial_rarity,
			"current_accumulated_exp": 0
		}
		summoned_units.append(new_instance)

	summoned_units = _hydrate_owned_units(summoned_units)
	owned_units_ids.append_array(summoned_units)
	emit_updated()
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "summon_units")
	return {"summoned": summoned_units}

func summon_exp_boost_units(amount: int = 3) -> Dictionary:
	return _summon_fixed_units_local("900020401", amount, "summon_exp_boost_units")

func summon_trust_units(amount: int = 3) -> Dictionary:
	return _summon_fixed_units_local("904000105", amount, "summon_trust_units")

## CAN BE REMOVED ???
func add_unit_xp(instance_id: String, xp_amount: int) -> Dictionary:
	var unit_found: bool = false
	for unit in owned_units_ids:
		if unit is Dictionary and unit.get("instance_id", "") == instance_id:
			unit["xp"] = int(unit.get("xp", 0)) + xp_amount
			unit_found = true
			break

	if unit_found:
		owned_units_ids = _hydrate_owned_units(owned_units_ids)
		emit_updated()
		Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "add_unit_xp")
		return {"success": true}
	else:
		return {"error": "ERR_UNIT_NOT_FOUND"}

func calculate_next_xp_for_unit(unit_inst: Dictionary) -> int:
	if unit_inst.is_empty():
		return 0

	var unit_data: Dictionary = GameDatabase.get_unit(str(unit_inst.get("unit_id", "")))
	var runtime_unit: Dictionary = unit_inst.duplicate(true)
	_update_unit_next_xp_local(runtime_unit, unit_data)
	return int(runtime_unit.get("next_xp", 0))

func _find_awakening_entry(unit: Dictionary) -> Dictionary:
	var unit_id: String = str(unit.get("unit_id", ""))
	if unit_id == "":
		return {}
	var class_up = GameDatabase.get_unit_class_up(unit_id)
	if class_up.is_empty():
		return {}

	var mat_info = str(class_up.get("materialInfo", ""))
	var materials = {}
	if mat_info != "":
		for part in mat_info.split(",", false):
			var comps = part.split(":")
			if comps.size() >= 3:
				var mat_id = str(comps[1])
				var amount = int(comps[2])
				materials[mat_id] = amount

	class_up["materials"] = materials
	class_up["gil_cost"] = int(class_up.get("gil", 0))
	return class_up

func _evaluate_awakening_requirements(instance_id: String) -> Dictionary:
	# Shared validation used by both can_awaken_unit() and awaken_unit().
	# Returns: { ok: bool, reason: String, unit_index: int, gil_cost: int, materials: Dictionary }
	var result: Dictionary = {
		"ok": false,
		"reason": "",
		"unit_index": -1,
		"gil_cost": 0,
		"materials": {},
	}

	var unit_index: int = -1
	for i in range(owned_units_ids.size()):
		var candidate: Variant = owned_units_ids[i]
		if candidate is Dictionary and str(candidate.get("instance_id", "")) == instance_id:
			unit_index = i
			break
	if unit_index < 0:
		result["reason"] = "Unit not found"
		return result
	result["unit_index"] = unit_index

	var unit: Dictionary = owned_units_ids[unit_index]
	var current_rarity: int = int(unit.get("current_rarity", unit.get("rarity", 1)))
	if current_rarity >= 7:
		result["reason"] = "Unit is at maximum rarity"
		return result

	var entry: Dictionary = _find_awakening_entry(unit)
	var awakening_var: Variant = entry.get("awakening", null) if not entry.is_empty() else null
	if not (awakening_var is Dictionary):
		result["reason"] = "Unit is at maximum rarity"
		return result
	var awakening: Dictionary = awakening_var as Dictionary

	var max_level: int = int(StatCalculator.RARITY_MAX_LEVELS.get(current_rarity, 15))
	if int(unit.get("level", 1)) < max_level:
		result["reason"] = "Unit must be at max level"
		return result

	var gil_cost: int = int(awakening.get("gil", 0))
	result["gil_cost"] = gil_cost
	if PlayerProfile.gil < gil_cost:
		result["reason"] = "Insufficient gil"
		return result

	var materials_var: Variant = awakening.get("materials", {})
	var materials: Dictionary = materials_var as Dictionary if materials_var is Dictionary else {}
	result["materials"] = materials

	var stackables_var: Variant = InventoryService.owned_items.get("stackables", {})
	var stackables: Dictionary = stackables_var as Dictionary if stackables_var is Dictionary else {}
	for item_key in materials.keys():
		var item_id: String = str(item_key)
		var required: int = int(materials[item_key])
		var owned: int = int(stackables.get(item_id, 0))
		if owned < required:
			result["reason"] = "Insufficient materials"
			return result

	result["ok"] = true
	return result

func can_awaken_unit(instance_id: String) -> Dictionary:
	var eval: Dictionary = _evaluate_awakening_requirements(instance_id)
	return {
		"can_awaken": bool(eval.get("ok", false)),
		"reason": str(eval.get("reason", "")),
	}

func awaken_unit(instance_id: String) -> Dictionary:
	var eval: Dictionary = _evaluate_awakening_requirements(instance_id)
	if not bool(eval.get("ok", false)):
		return {"success": false, "error": str(eval.get("reason", "Unit cannot be awakened"))}

	var unit_index: int = int(eval.get("unit_index", -1))
	var gil_cost: int = int(eval.get("gil_cost", 0))
	var materials_var: Variant = eval.get("materials", {})
	var materials: Dictionary = materials_var as Dictionary if materials_var is Dictionary else {}

	# Consume gil.
	PlayerProfile.deduct_gil(gil_cost)

	# Consume materials.
	var items_to_consume = []
	for item_key in materials.keys():
		items_to_consume.append({
			"id": str(item_key),
			"amount": int(materials[item_key])
		})
	InventoryService.consume_stackables_and_save(items_to_consume)

	# Bump rarity.
	var unit: Dictionary = owned_units_ids[unit_index]
	var new_rarity: int = int(unit.get("current_rarity", 1)) + 1
	unit["current_rarity"] = new_rarity

	var class_up_data = GameDatabase.get_unit_class_up(str(unit.get("unit_id", "")))
	var next_unit_id = str(class_up_data.get("classUpUnitID", ""))
	if next_unit_id != "":
		unit["unit_id"] = next_unit_id

	var unit_data: Dictionary = GameDatabase.get_unit(str(unit.get("unit_id", "")))
	var exp_pattern: int = _get_raw_unit_exp_pattern(str(unit.get("unit_id", "")), unit_data, new_rarity)
	if exp_pattern <= 0:
		exp_pattern = 5

	if new_rarity == 7:
		unit["xp"] = _calculate_total_xp_for_level_local(101, exp_pattern)
		unit["level"] = 101
	else:
		unit["xp"] = 0
		unit["level"] = 1

	_update_unit_next_xp_local(unit, unit_data)
	owned_units_ids[unit_index] = unit

	# Persist + signal (mirrors enhance_unit flow).
	owned_units_ids = _hydrate_owned_units(owned_units_ids)
	emit_updated()
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "awaken_unit")

	InventoryService.emit_updated()

	return {"success": true}

func enhance_unit(base_unit_instance_id: String, material_unit_instance_ids: Array) -> Dictionary:
	if base_unit_instance_id == "":
		return {"success": false, "error": "Invalid base_unit_instance_id"}
	if material_unit_instance_ids.is_empty():
		return {"success": false, "error": "material_unit_instance_ids must be a non-empty array"}

	var seen_materials: Dictionary = {}
	for material_id_value in material_unit_instance_ids:
		var material_id: String = str(material_id_value)
		if material_id == "":
			return {"success": false, "error": "All material ids must be non-empty strings"}
		if seen_materials.has(material_id):
			return {"success": false, "error": "Duplicate material ids are not allowed"}
		seen_materials[material_id] = true
		if material_id == base_unit_instance_id:
			return {"success": false, "error": "Base unit cannot be used as enhancement material"}



	var base_unit: Dictionary = {}
	var base_index: int = -1
	for i in range(owned_units_ids.size()):
		var candidate: Variant = owned_units_ids[i]
		if candidate is Dictionary and str(candidate.get("instance_id", "")) == base_unit_instance_id:
			base_unit = candidate
			base_index = i
			break
	if base_index < 0:
		return {"success": false, "error": "Ownership check failed for base unit"}

	var base_unit_data: Dictionary = GameDatabase.get_unit(str(base_unit.get("unit_id", "")))
	if base_unit_data.is_empty():
		return {"success": false, "error": "Base unit data not found"}

	var base_max_level: int = _get_unit_max_level_local(base_unit)
	var base_unit_type: String = _get_unit_type(base_unit_data)
	if base_unit_type == UNIT_TYPE_PLAYABLE:
		if int(base_unit.get("level", 1)) >= base_max_level and float(base_unit.get("trust_value", 0.0)) >= ENHANCE_MAX_TRUST_VALUE:
			return {"success": false, "error": "Base unit is already at maximum level and trust"}

	var material_units: Array = []
	for material_id_value in material_unit_instance_ids:
		var material_id: String = str(material_id_value)
		var material_unit: Dictionary = {}
		var found_material: bool = false
		for unit_value in owned_units_ids:
			if unit_value is Dictionary and str(unit_value.get("instance_id", "")) == material_id:
				material_unit = unit_value
				found_material = true
				break
		if not found_material:
			return {"success": false, "error": "Ownership check failed for one or more material units"}

		if bool(material_unit.get("is_locked", false)):
			return {"success": false, "error": "One or more material units are locked"}

		if PartyService.is_unit_assigned_to_any_party(material_id):
			return {"success": false, "error": "One or more material units are assigned to a party"}

		var material_unit_data: Dictionary = GameDatabase.get_unit(str(material_unit.get("unit_id", "")))
		if material_unit_data.is_empty():
			return {"success": false, "error": "Material unit data not found"}

		var material_type: String = _get_unit_type(material_unit_data)
		if material_type == UNIT_TYPE_PLAYABLE and float(material_unit.get("trust_value", 0.0)) >= ENHANCE_MAX_TRUST_VALUE:
			return {"success": false, "error": "One or more material units are already at 100% trust"}

		if base_unit_type == UNIT_TYPE_EXP_MATERIAL and material_type != UNIT_TYPE_EXP_MATERIAL:
			return {"success": false, "error": "Cannot use non-EXP materials to enhance an EXP unit"}

		if base_unit_type == UNIT_TYPE_TRUST_MATERIAL and material_type != UNIT_TYPE_TRUST_MATERIAL:
			return {"success": false, "error": "Cannot use non-trust materials to enhance a trust material unit"}

		material_units.append(material_unit)

	var total_cost: int = material_unit_instance_ids.size() * ENHANCE_GIL_COST_PER_MATERIAL
	if PlayerProfile.gil < total_cost:
		return {"success": false, "error": "Insufficient gil"}
	PlayerProfile.deduct_gil(total_cost)

	var granted_trust_reward: Variant = {}
	var trust_reward_warning: String = ""

	if base_unit_type == UNIT_TYPE_EXP_MATERIAL:
		var total_exp_to_add: int = 0
		for material_unit_value in material_units:
			var material_unit: Dictionary = material_unit_value
			var material_unit_data: Dictionary = GameDatabase.get_unit(str(material_unit.get("unit_id", "")))
			var gains: Dictionary = _calculate_material_enhance_gains(material_unit, material_unit_data)
			total_exp_to_add += int(gains.get("xp_gain", 0))

		var max_accumulated_exp: int = _get_max_accumulated_exp(base_unit_data)
		base_unit["current_accumulated_exp"] = mini(max_accumulated_exp, int(base_unit.get("current_accumulated_exp", 0)) + total_exp_to_add)
	elif base_unit_type == UNIT_TYPE_TRUST_MATERIAL:
		var total_trust_to_add: float = 0.0
		for material_unit_value in material_units:
			var material_unit: Dictionary = material_unit_value
			var material_unit_data: Dictionary = GameDatabase.get_unit(str(material_unit.get("unit_id", "")))
			var gains: Dictionary = _calculate_material_enhance_gains(material_unit, material_unit_data)
			total_trust_to_add += float(gains.get("trust_gain", 0.0))

		base_unit["trust_value"] = min(ENHANCE_MAX_TRUST_VALUE, float(base_unit.get("trust_value", 0.0)) + total_trust_to_add)
	else:
		var total_xp_gain: int = 0
		var total_trust_gain: float = 0.0
		var previous_trust_value: float = float(base_unit.get("trust_value", 0.0))

		for material_unit_value in material_units:
			var material_unit: Dictionary = material_unit_value
			var material_unit_data: Dictionary = GameDatabase.get_unit(str(material_unit.get("unit_id", "")))
			var gains: Dictionary = _calculate_material_enhance_gains(material_unit, material_unit_data)
			total_xp_gain += int(gains.get("xp_gain", 0))
			total_trust_gain += float(gains.get("trust_gain", 0.0))

			if _get_unit_type(material_unit_data) == UNIT_TYPE_PLAYABLE and _is_duplicate_unit(base_unit, base_unit_data, material_unit, material_unit_data):
				total_trust_gain += PLAYABLE_DUPLICATE_TRUST_BONUS + _get_material_accumulated_trust(material_unit)

		base_unit["xp"] = int(base_unit.get("xp", 0)) + total_xp_gain
		var exp_pattern: int = _get_raw_unit_exp_pattern(str(base_unit.get("unit_id", "")), base_unit_data, int(base_unit.get("current_rarity", 1)))
		if exp_pattern <= 0:
			exp_pattern = 5
		base_unit["level"] = _calculate_level_from_xp_local(int(base_unit.get("xp", 0)), exp_pattern, base_max_level)
		_update_unit_next_xp_local(base_unit, base_unit_data)

		base_unit["trust_value"] = min(ENHANCE_MAX_TRUST_VALUE, float(base_unit.get("trust_value", 0.0)) + total_trust_gain)

		if previous_trust_value < ENHANCE_MAX_TRUST_VALUE and float(base_unit.get("trust_value", 0.0)) >= ENHANCE_MAX_TRUST_VALUE and not bool(base_unit.get("trust_reward_claimed", false)):
			var reward_info: Dictionary = _resolve_trust_reward(base_unit_data)
			if reward_info.has("template_id"):
				var reward_type: String = str(reward_info.get("reward_type", ""))
				var reward_template_id: String = str(reward_info.get("template_id", ""))
				var grant_result: Dictionary = InventoryService.grant_instanced_items(reward_type, reward_template_id, 1)
				if bool(grant_result.get("success", false)):
					var granted_items: Array = grant_result.get("granted_items", [])
					granted_trust_reward = {
						"reward_type": reward_type,
						"template_id": reward_template_id,
						"quantity": 1,
						"granted_equipment": granted_items
					}
					base_unit["trust_reward_claimed"] = true
				else:
					trust_reward_warning = "Failed to grant trust reward"
			else:
				trust_reward_warning = str(reward_info.get("error", "No supported trust reward configured"))

	owned_units_ids[base_index] = base_unit
	var material_id_set: Dictionary = {}
	for material_id_value in material_unit_instance_ids:
		material_id_set[str(material_id_value)] = true

	var filtered_units: Array = []
	for unit_value in owned_units_ids:
		if unit_value is Dictionary:
			var instance_id: String = str(unit_value.get("instance_id", ""))
			if material_id_set.has(instance_id):
				continue
		filtered_units.append(unit_value)

	owned_units_ids = _hydrate_owned_units(filtered_units)
	emit_updated()
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "enhance_unit")

	if granted_trust_reward != null:
		InventoryService.emit_updated()

	var updated_base_unit: Dictionary = {}
	for unit_value in owned_units_ids:
		if unit_value is Dictionary and str(unit_value.get("instance_id", "")) == base_unit_instance_id:
			updated_base_unit = unit_value
			break

	var response: Dictionary = {
		"success": true,
		"updated_base_unit": {
			"instance_id": str(updated_base_unit.get("instance_id", base_unit_instance_id)),
			"level": int(updated_base_unit.get("level", base_unit.get("level", 1))),
			"xp": int(updated_base_unit.get("xp", base_unit.get("xp", 0))),
			"trust_value": float(updated_base_unit.get("trust_value", base_unit.get("trust_value", 0.0))),
			"limitburst_level": int(updated_base_unit.get("limitburst_level", base_unit.get("limitburst_level", 1))),
			"limitburst_xp": int(updated_base_unit.get("limitburst_xp", base_unit.get("limitburst_xp", 0))),
			"current_accumulated_exp": int(updated_base_unit.get("current_accumulated_exp", base_unit.get("current_accumulated_exp", 0)))
		},
		"consumed_material_ids": material_unit_instance_ids.duplicate(),
		"updated_currency": {
			"gil": PlayerProfile.gil
		},
		"granted_trust_reward": granted_trust_reward,
		"trust_reward_warning": trust_reward_warning,
		# Backward-compatible field consumed by current enhance_ui.gd
		"enhanced_unit": updated_base_unit
	}
	return response

func sell_units(instance_ids: Array) -> Dictionary:
	if instance_ids == null or instance_ids.is_empty():
		return {"success": false, "error": "No units selected to sell"}

	var sell_id_set: Dictionary = {}
	for id_value in instance_ids:
		var instance_id: String = str(id_value)
		if instance_id == "":
			return {"success": false, "error": "All unit ids must be non-empty strings"}
		if sell_id_set.has(instance_id):
			return {"success": false, "error": "Duplicate unit ids are not allowed"}
		sell_id_set[instance_id] = true

	for instance_id in sell_id_set.keys():
		var sell_unit: Dictionary = {}
		var found_unit: bool = false
		for unit_value in owned_units_ids:
			if unit_value is Dictionary and str(unit_value.get("instance_id", "")) == instance_id:
				sell_unit = unit_value
				found_unit = true
				break
		if not found_unit:
			return {"success": false, "error": "Ownership check failed for one or more units"}
		if bool(sell_unit.get("is_locked", false)):
			return {"success": false, "error": "One or more units are locked"}
		if PartyService.is_unit_assigned_to_any_party(instance_id):
			return {"success": false, "error": "One or more units are assigned to a party"}

	var filtered_units: Array = []
	for unit_value in owned_units_ids:
		if unit_value is Dictionary:
			var instance_id: String = str(unit_value.get("instance_id", ""))
			if sell_id_set.has(instance_id):
				continue
		filtered_units.append(unit_value)

	var sold_count: int = sell_id_set.size()
	var gil_gained: int = sold_count * SELL_GIL_PER_UNIT

	owned_units_ids = _hydrate_owned_units(filtered_units)
	PlayerProfile.add_gil(gil_gained)

	emit_updated()
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "sell_units")

	return {
		"success": true,
		"sold_count": sold_count,
		"gil_gained": gil_gained,
		"sold_instance_ids": sell_id_set.keys()
	}

func request_equip_item(instance_id: String, slot_id: String, item_id: String, allow_transfer: bool = false) -> void:
	if item_id != "" and not InventoryService.equipment_instance_exists(item_id):
		equip_failed.emit("ERR_EQUIPMENT_NOT_FOUND")
		return

	var target_unit_inst: Dictionary = {}
	for unit in owned_units_ids:
		if unit is Dictionary and str(unit.get("instance_id", "")) == instance_id:
			target_unit_inst = unit
			break
	if target_unit_inst.is_empty():
		equip_failed.emit("ERR_UNIT_NOT_FOUND")
		return

	var item_template: Dictionary = {}
	if item_id != "":
		var requested_item: Dictionary = InventoryService.get_equipment_instance(item_id)
		var template_id: String = str(requested_item.get("template_id", ""))
		item_template = GameDatabase.get_equipment(template_id)
		if item_template.is_empty():
			# Materia instances live in the same equipment collection but resolve
			# their template via game_data_materia. The validator only needs the
			# template for weapon-shape checks (slot/is_twohanded/type_id), which
			# materia simply won't satisfy — so the dual-wield branch falls through
			# while the sharing-conflict branch still runs.
			item_template = StaticData.game_data_materia.get(template_id, {})

		var validation: Dictionary = EquipmentValidator.can_equip(target_unit_inst, slot_id, item_template, owned_units_ids, item_id)
		if not bool(validation.get("ok", false)):
			var reason: String = str(validation.get("reason", ""))
			if reason == EquipmentValidator.ERR_EQUIPMENT_ALREADY_EQUIPPED:
				if not allow_transfer:
					equip_conflict.emit(instance_id, slot_id, item_id, str(validation.get("conflicting_unit_id", "")))
					return
				# Caller approved transfer: clear the conflicting unit's slot here so
				# the equip below succeeds. Inventory `equipped_to` is rewritten by
				# the shared cleanup loop further down.
				_clear_item_from_unit(str(validation.get("conflicting_unit_id", "")), item_id)
			else:
				equip_failed.emit(reason)
				return

	var owned_items: Dictionary = InventoryService.owned_items
	var removed_item_ids: Array[String] = []

	if item_id != "" and bool(item_template.get("is_twohanded", false)):
		var other_hand: String = "l_hand" if slot_id == "r_hand" else "r_hand"
		var current_equipment_th: Dictionary = _normalize_unit_equipment(target_unit_inst.get("equipment", {}))
		var removed_other_hand_item_id: String = str(current_equipment_th.get(other_hand, ""))
		current_equipment_th.erase(other_hand)
		if removed_other_hand_item_id != "":
			removed_item_ids.append(removed_other_hand_item_id)
		target_unit_inst["equipment"] = current_equipment_th

	var current_equipment: Dictionary = _normalize_unit_equipment(target_unit_inst.get("equipment", {}))
	if item_id != "":
		for equipped_slot_id in current_equipment.keys():
			if str(current_equipment.get(equipped_slot_id, "")) == item_id and str(equipped_slot_id) != slot_id:
				equip_failed.emit("ERR_EQUIPMENT_ALREADY_IN_USE")
				return

	var previously_equipped_item_id: String = str(current_equipment.get(slot_id, ""))
	if item_id == "":
		current_equipment.erase(slot_id)
	else:
		current_equipment[slot_id] = item_id
	if previously_equipped_item_id != "" and previously_equipped_item_id != item_id:
		removed_item_ids.append(previously_equipped_item_id)
	target_unit_inst["equipment"] = current_equipment

	if owned_items.has("equipment"):
		for raw_item in owned_items["equipment"]:
			if not (raw_item is Dictionary):
				continue
			var inv_item: Dictionary = raw_item
			var inv_item_instance_id: String = str(inv_item.get("instance_id", ""))
			if inv_item_instance_id == item_id:
				inv_item["equipped_to"] = instance_id
			elif inv_item_instance_id in removed_item_ids:
				inv_item["equipped_to"] = ""

	owned_units_ids = _hydrate_owned_units(owned_units_ids)
	emit_updated()
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "equip_item")

	# Important: Because equipment assignment changes 'equipped_to' inside InventoryService's dictionary,
	# we must also trigger an explicit save for the inventory service since we bypassed its methods.
	Persistence.save_snapshot(InventoryService.SNAPSHOT_FILE, InventoryService.snapshot_payload(), "equip_item")
	InventoryService.emit_updated()
	equip_successful.emit()


func _clear_item_from_unit(unit_instance_id: String, item_id: String) -> void:
	if unit_instance_id == "" or item_id == "":
		return
	for unit in owned_units_ids:
		if not (unit is Dictionary) or str(unit.get("instance_id", "")) != unit_instance_id:
			continue
		var equipment: Dictionary = _normalize_unit_equipment(unit.get("equipment", {}))
		var changed: bool = false
		for existing_slot_id in equipment.keys():
			if str(equipment.get(existing_slot_id, "")) == item_id:
				equipment.erase(existing_slot_id)
				changed = true
		if changed:
			unit["equipment"] = equipment
		return
	
func get_entry_id(unit_inst: Dictionary) -> String:
	if unit_inst.is_empty():
		return ""
	var entry_id: String = str(unit_inst.get("entry_id", ""))
	if entry_id != "":
		return entry_id
	var unit_id: String = str(unit_inst.get("unit_id", ""))
	return unit_id

func is_material_unit(unit_inst: Dictionary) -> bool:
	if unit_inst.is_empty():
		return false
	
	var unit_id: String = str(unit_inst.get("unit_id", ""))
	if unit_id == "":
		return false
	
	var unit_data: Dictionary = GameDatabase.get_unit(unit_id)
	if unit_data.is_empty():
		return false
	
	var job_id: int = int(unit_data.get("jobId", 0))
	return job_id in MATERIAL_UNIT_JOB_IDS

# === Internal helpers ===

func _summon_fixed_units_local(unit_id: String, amount: int, source_event: String) -> Dictionary:
	var unit_data: Dictionary = GameDatabase.get_unit(unit_id)
	if unit_data.is_empty():
		return {"error": "Unit data not found for unit_id %s" % unit_id}

	var summon_amount: int = maxi(1, amount)
	var summoned_units: Array = []
	var initial_rarity: int = _get_unit_initial_rarity(unit_id)

	for _i in range(summon_amount):
		var new_instance: Dictionary = {
			"unit_id": unit_id,
			"instance_id": InventoryService.generate_instance_id(),
			"xp": 0,
			"level": 1,
			"next_xp": 1000,
			"equipment": {},
			"is_locked": false,
			"trust_value": 0,
			"trust_reward_claimed": false,
			"limitburst_xp": 0,
			"limitburst_level": 1,
			"current_rarity": initial_rarity,
			"current_accumulated_exp": 0
		}
		summoned_units.append(new_instance)

	summoned_units = _hydrate_owned_units(summoned_units)
	owned_units_ids.append_array(summoned_units)
	emit_updated()
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), source_event)
	return {"summoned": summoned_units}


func _name_is_latin(name: String) -> bool:
	if name == "":
		return false
	for i in name.length():
		var cp: int = name.unicode_at(i)
		# Basic Latin, Latin-1 Supplement, Latin Extended-A/B (0x0000..0x024F)
		if cp > 0x024F:
			return false
	return true

func _extract_unit_lean_record(hydrated_unit: Dictionary) -> Dictionary:
	return {
		"xp": int(hydrated_unit.get("xp", 0)),
		"unit_id": str(hydrated_unit.get("unit_id", "")),
		"instance_id": str(hydrated_unit.get("instance_id", "")),
		"equipment": _normalize_unit_equipment(hydrated_unit.get("equipment", {})),
		"is_locked": bool(hydrated_unit.get("is_locked", false)),
		"trust_value": int(hydrated_unit.get("trust_value", 0)),
		"trust_reward_claimed": bool(hydrated_unit.get("trust_reward_claimed", false)),
		"limitburst_xp": int(hydrated_unit.get("limitburst_xp", 0)),
		"limitburst_level": int(hydrated_unit.get("limitburst_level", 1)),
		"current_rarity": int(hydrated_unit.get("current_rarity", 1)),
		"current_accumulated_exp": int(hydrated_unit.get("current_accumulated_exp", 0))
	}

func _normalize_units_payload(raw_payload: Variant) -> Array:
	if not (raw_payload is Dictionary):
		return []

	var payload: Dictionary = raw_payload
	var units_list: Variant = payload.get("owned_units", [])
	if not (units_list is Array):
		return []

	var lean_units: Array = []
	for unit in units_list:
		if unit is Dictionary:
			lean_units.append(unit.duplicate(true))
		else:
			lean_units.append(unit)

	return lean_units

func _load_units_from_local() -> Array:
	var envelope: Dictionary = Persistence.load_snapshot(SNAPSHOT_FILE)
	if envelope.is_empty():
		return []

	var data: Variant = envelope.get("data", {})
	if not (data is Dictionary):
		return []

	var lean_units: Array = _normalize_units_payload(data)
	if lean_units.is_empty():
		return []

	return _hydrate_owned_units(lean_units)

func _get_unit_initial_rarity(unit_id: String) -> int:
	var unit_data: Dictionary = GameDatabase.get_unit(unit_id)
	if unit_data.is_empty():
		return 1
	var limits: Dictionary = GameDatabase.get_unit_series_limits(int(unit_data.get("unitSeries", 0)))
	return int(limits.get("min_rarity", 1))

func _get_unit_type(unit_data: Dictionary) -> String:
	if unit_data.is_empty():
		return UNIT_TYPE_PLAYABLE
	if int(unit_data.get("job_id", 0)) == EXP_UNIT_JOB_ID:
		return UNIT_TYPE_EXP_MATERIAL
	if int(unit_data.get("job_id", 0)) == TRUST_MATERIAL_JOB_ID:
		return UNIT_TYPE_TRUST_MATERIAL
	return UNIT_TYPE_PLAYABLE

func _get_raw_unit_exp_pattern(unit_id: String, unit_data: Dictionary, rarity: int = -1) -> int:
	var entries: Variant = unit_data.get("entries", {})
	if entries is Dictionary:
		if rarity >= 0:
			for entry_key in entries.keys():
				var entry: Variant = entries[entry_key]
				if entry is Dictionary and int(entry.get("rarity", -1)) == rarity:
					if entry.has("exp_pattern"):
						return int(entry.get("exp_pattern", 0))

		if entries.has(unit_id):
			var keyed_entry: Variant = entries[unit_id]
			if keyed_entry is Dictionary and keyed_entry.has("exp_pattern"):
				return int(keyed_entry.get("exp_pattern", 0))

		for entry_key in entries.keys():
			var fallback_entry: Variant = entries[entry_key]
			if fallback_entry is Dictionary and fallback_entry.has("exp_pattern"):
				return int(fallback_entry.get("exp_pattern", 0))

	return 0

func _get_exp_unit_yield(unit_id: String, unit_data: Dictionary) -> int:
	if int(unit_data.get("job_id", 0)) != EXP_UNIT_JOB_ID:
		return 0
	var exp_pattern: int = _get_raw_unit_exp_pattern(unit_id, unit_data, int(unit_data.get("rarity_min", 1)))
	return int(EXP_UNIT_YIELD_BY_PATTERN.get(exp_pattern, 0))

func _get_base_exp_yield(unit: Dictionary, unit_data: Dictionary) -> int:
	if unit_data.has("base_exp_yield"):
		return int(unit_data.get("base_exp_yield", 0))

	var unit_type: String = _get_unit_type(unit_data)
	if unit_type == UNIT_TYPE_EXP_MATERIAL:
		return _get_exp_unit_yield(str(unit.get("unit_id", "")), unit_data)

	if unit_type == UNIT_TYPE_PLAYABLE:
		var rarity: int = maxi(1, int(unit.get("current_rarity", int(unit_data.get("rarity_min", 1)))))
		return ENHANCE_BASE_XP_GAIN + (rarity * ENHANCE_XP_PER_RARITY) + ENHANCE_XP_PER_LEVEL

	return 0

func _get_material_accumulated_exp(material_unit: Dictionary) -> int:
	if material_unit.has("current_accumulated_exp"):
		return maxi(0, int(material_unit.get("current_accumulated_exp", 0)))
	if material_unit.has("bonus_exp"):
		return maxi(0, int(material_unit.get("bonus_exp", 0)))
	return maxi(0, int(material_unit.get("xp", 0)))

func _get_material_accumulated_trust(material_unit: Dictionary) -> float:
	return max(0.0, float(material_unit.get("trust_value", 0.0)))

func _get_trust_yield(unit_id: String, unit_data: Dictionary) -> float:
	if unit_data.has("trust_yield"):
		return max(0.0, float(unit_data.get("trust_yield", 0.0)))
	return float(TRUST_YIELD_BY_UNIT_ID.get(int(unit_id), 0.0))

func _get_trust_mastery_id(unit_data: Dictionary) -> String:
	if unit_data.has("trust_mastery_id") and str(unit_data.get("trust_mastery_id", "")) != "":
		return str(unit_data.get("trust_mastery_id", ""))
	var tmr_value: Variant = unit_data.get("TMR", null)
	if tmr_value is Array and tmr_value.size() >= 2 and tmr_value[1] != null:
		return str(tmr_value[1])
	return ""

func _is_duplicate_unit(base_unit: Dictionary, base_unit_data: Dictionary, material_unit: Dictionary, material_unit_data: Dictionary) -> bool:
	var base_series = str(base_unit_data.get("unitSeries", ""))
	var material_series = str(material_unit_data.get("unitSeries", ""))

	if base_series != "" and material_series != "" and base_series == material_series:
		return true

	var base_tmr = str(base_unit_data.get("trustMasterReward", ""))
	var material_tmr = str(material_unit_data.get("trustMasterReward", ""))

	if base_tmr != "" and material_tmr != "" and base_tmr == material_tmr:
		return true

	return false

func _get_max_accumulated_exp(unit_data: Dictionary) -> int:
	return int(unit_data.get("adjustParamMax", DEFAULT_MAX_ACCUMULATED_EXP))

func _resolve_trust_reward(unit_data: Dictionary) -> Dictionary:
	if unit_data.is_empty():
		return {"error": "Missing unit static data for trust reward"}

	var game_data_materia: Dictionary = StaticData.game_data_materia

	var tmr_value: Variant = unit_data.get("TMR", null)
	if tmr_value is Array and tmr_value.size() >= 2 and tmr_value[1] != null:
		var reward_type: String = str(tmr_value[0])
		var reward_id: String = str(tmr_value[1])
		if reward_type == "EQUIP":
			if GameDatabase.get_equipment(reward_id).is_empty():
				return {"error": "Trust reward equipment template not found"}
			return {"reward_type": "EQUIP", "template_id": reward_id}
		elif reward_type == "MATERIA":
			if not game_data_materia.has(reward_id):
				return {"error": "Trust reward materia template not found"}
			return {"reward_type": "MATERIA", "template_id": reward_id}
		else:
			return {"error": "Unsupported trust reward type: %s" % reward_type}

	var trust_mastery_id: String = str(unit_data.get("trust_mastery_id", ""))
	if trust_mastery_id != "":
		if not GameDatabase.get_equipment(trust_mastery_id).is_empty():
			return {"reward_type": "EQUIP", "template_id": trust_mastery_id}
		if game_data_materia.has(trust_mastery_id):
			return {"reward_type": "MATERIA", "template_id": trust_mastery_id}

	return {"error": "No supported trust reward configured"}

func _calculate_material_enhance_gains(material_unit: Dictionary, material_unit_data: Dictionary) -> Dictionary:
	var material_type: String = _get_unit_type(material_unit_data)

	if material_type == UNIT_TYPE_EXP_MATERIAL:
		var exp_total: int = _get_base_exp_yield(material_unit, material_unit_data) + _get_material_accumulated_exp(material_unit)
		return {"xp_gain": exp_total, "trust_gain": 0.0, "limitburst_gain": 0}

	if material_type == UNIT_TYPE_TRUST_MATERIAL:
		var trust_total: float = _get_trust_yield(str(material_unit.get("unit_id", "")), material_unit_data) + _get_material_accumulated_trust(material_unit)
		return {"xp_gain": 0, "trust_gain": trust_total, "limitburst_gain": 0}

	var base_exp: int = _get_base_exp_yield(material_unit, material_unit_data)
	var stored_exp: int = _get_material_accumulated_exp(material_unit)
	var xp_gain: int = base_exp + int(floor(float(stored_exp) * PLAYABLE_ACCUMULATED_EXP_TRANSFER_RATE))
	return {"xp_gain": xp_gain, "trust_gain": 0.0, "limitburst_gain": 0}

func _get_unit_max_level_local(unit: Dictionary) -> int:
	var rarity: int = int(unit.get("current_rarity", 1))
	return int(StatCalculator.RARITY_MAX_LEVELS.get(rarity, 15))

# Total-XP table for all exp patterns, lazily fetched from the DB
# (unit_exp_pattern table) and cached. The DB stores needExp[L] as
# the cumulative XP required to REACH level L (with an L=1=0 row).
# The cache stores them in a PackedInt32Array where index == level.
var _exp_patterns_loaded: bool = false

func _ensure_exp_patterns_loaded() -> void:
	if _exp_patterns_loaded:
		return

	if not GameDatabase:
		push_error("Unit exp patterns unavailable: GameDatabase autoload is missing")
		return

	_exp_patterns_loaded = true
	var temp_dict: Dictionary = {}
	for row in GameDatabase.get_all_unit_exp_patterns():
		var pattern_id: int = int(row.get("expPatternId", 0))
		var level: int = int(row.get("level", 0))
		var need_exp: int = int(row.get("needExp", 0))

		if not temp_dict.has(pattern_id):
			temp_dict[pattern_id] = {}
		temp_dict[pattern_id][level] = need_exp

	for pattern_id in temp_dict.keys():
		var max_lvl: int = 0
		for l in temp_dict[pattern_id].keys():
			max_lvl = maxi(max_lvl, l)

		var arr: PackedInt32Array = PackedInt32Array()
		arr.resize(max_lvl + 1)
		arr.fill(-1) # Default to -1 so bsearch isn't confused by trailing zeroes
		for l in temp_dict[pattern_id].keys():
			arr[l] = temp_dict[pattern_id][l]

		_unit_exp_patterns_cache[pattern_id] = arr

func _calculate_total_xp_for_level_local(level: int, exp_pattern: int) -> int:
	_ensure_exp_patterns_loaded()
	var arr: PackedInt32Array = _unit_exp_patterns_cache.get(exp_pattern, PackedInt32Array())
	if arr.is_empty():
		return 0

	if level < 1:
		return 0
	elif level < arr.size():
		return arr[level]
	else:
		return arr[arr.size() - 1]

func _calculate_level_from_xp_local(total_xp: int, exp_pattern: int, max_level: int) -> int:
	_ensure_exp_patterns_loaded()
	var arr: PackedInt32Array = _unit_exp_patterns_cache.get(exp_pattern, PackedInt32Array())
	if arr.is_empty():
		return 1

	var calculated_level: int = arr.bsearch(total_xp, false) - 1
	return clampi(calculated_level, 1, max_level)

func _update_unit_next_xp_local(unit: Dictionary, unit_data: Dictionary) -> void:
	var exp_pattern: int = _get_raw_unit_exp_pattern(str(unit.get("unit_id", "")), unit_data, int(unit.get("current_rarity", 1)))
	if exp_pattern <= 0:
		exp_pattern = 5

	var max_level: int = _get_unit_max_level_local(unit)
	var level: int = int(unit.get("level", 1))
	if level < max_level:
		var next_level_xp: int = _calculate_total_xp_for_level_local(level + 1, exp_pattern)
		unit["next_xp"] = maxi(0, next_level_xp - int(unit.get("xp", 0)))
	else:
		unit["next_xp"] = 0

func _normalize_unit_equipment(raw_equipment: Variant) -> Dictionary:
	if raw_equipment is Dictionary:
		return raw_equipment.duplicate(true)

	if raw_equipment is Array:
		var arr: Array = raw_equipment
		var normalized: Dictionary = {}
		if arr.size() > 0 and arr[0] != null and str(arr[0]) != "":
			normalized["r_hand"] = str(arr[0])
		if arr.size() > 1 and arr[1] != null and str(arr[1]) != "":
			normalized["l_hand"] = str(arr[1])
		return normalized

	return {}

func _hydrate_owned_units(units: Array) -> Array:
	var hydrated_units: Array = []
	for unit_instance in units:
		if typeof(unit_instance) != TYPE_DICTIONARY:
			hydrated_units.append(unit_instance)
			continue

		var hydrated_unit: Dictionary = {}

		# 1. Base Template Data
		var unit_id = str(unit_instance.get("unit_id", ""))
		var template_data = GameDatabase.get_unit(unit_id)
		hydrated_unit.merge(template_data)

		# 2. Extract specific stats from DB format
		var hp_str = str(template_data.get("hp", ""))
		var mp_str = str(template_data.get("mp", ""))
		var atk_str = str(template_data.get("atk", ""))
		var def_str = str(template_data.get("def", ""))
		var mag_str = str(template_data.get("mag", ""))
		var spr_str = str(template_data.get("spr", ""))

		var parse_stat = func(stat_str: String) -> Array:
			var parts = stat_str.split(",")
			var result = []
			for p in parts:
				if p.strip_edges() != "":
					result.append(int(p))
			return result

		hydrated_unit["stats"] = {
			"HP": parse_stat.call(hp_str),
			"MP": parse_stat.call(mp_str),
			"ATK": parse_stat.call(atk_str),
			"DEF": parse_stat.call(def_str),
			"MAG": parse_stat.call(mag_str),
			"SPR": parse_stat.call(spr_str)
		}

		# Element / Status resists
		var elem_resist_str = str(template_data.get("elemResistValue", ""))
		var status_resist_str = str(template_data.get("ailmentResistValue", ""))
		hydrated_unit["element_resist"] = parse_stat.call(elem_resist_str)
		hydrated_unit["status_resist"] = parse_stat.call(status_resist_str)

		# Trust Master Reward parsing
		var tmr_str = str(template_data.get("trustMasterReward", ""))
		if tmr_str != "":
			var tmr_parts = tmr_str.split(":")
			if tmr_parts.size() >= 2:
				hydrated_unit["TMR"] = tmr_parts[1]
				hydrated_unit["trust_mastery_id"] = tmr_parts[1]

		# 3. Dynamic XP / Level
		var xp = int(unit_instance.get("xp", 0))
		var current_rarity = int(unit_instance.get("current_rarity", 1))
		var exp_pattern: int = _get_raw_unit_exp_pattern(unit_id, template_data, current_rarity)
		if exp_pattern <= 0:
			exp_pattern = 5

		var limits = GameDatabase.get_unit_series_limits(int(template_data.get("unitSeries", 0)))
		var max_rarity = int(limits.get("max_rarity", 1))
		var current_max_level = StatCalculator.RARITY_MAX_LEVELS.get(current_rarity, 15)

		hydrated_unit["level"] = _calculate_level_from_xp_local(xp, exp_pattern, current_max_level)
		hydrated_unit["xp"] = xp
		hydrated_unit["current_rarity"] = current_rarity
		hydrated_unit["rarity_max"] = max_rarity

		# Copy other dynamic state
		for key in ["instance_id", "equipment", "trust_value", "current_accumulated_exp", "is_locked"]:
			if unit_instance.has(key):
				hydrated_unit[key] = unit_instance[key]

		_update_unit_next_xp_local(hydrated_unit, template_data)
		hydrated_unit["final_stats"] = StatCalculator.calculate_final_stats(hydrated_unit)
		hydrated_units.append(hydrated_unit)

	return hydrated_units
