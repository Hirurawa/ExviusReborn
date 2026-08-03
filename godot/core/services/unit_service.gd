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
	var unit_data: Dictionary = GameDatabase.get_unit(int(unit_id))
	if unit_data.is_empty():
		return {}

	var initial_rarity: int = unit_data.get("rare", 2)

	return {
		"instance_id": instance_id,
		"unit_id": unit_id,
		"level": 1,
		"xp": 0,
		"current_rarity": initial_rarity,
		"equipment": {
			"body": instance_id + "_LeatherPlate",
			"r_hand": instance_id + "_Broadsword"
		},
		"trust_value": 0,
		"limitburst_level": 1,
		"limitburst_xp": 0,
		"is_locked": false,
		"trust_reward_claimed": false
	}

func summon_units(amount: int, is_nv: bool = false) -> Dictionary:
	var summoned_units: Array = []
	var summonable_units: Array = GameDatabase.get_summonable_units(is_nv)

	if summonable_units.is_empty():
		return {"error": "ERR_NO_UNITS_AVAILABLE"}

	for _i in range(amount):
		var random_unit: Dictionary = summonable_units[randi() % summonable_units.size()]
		var new_instance: Dictionary = {
			"unit_id": random_unit.get("unitId"),
			"instance_id": InventoryService.generate_instance_id(),
			"xp": 0,
			"level": 1,
			"equipment": {},
			"is_locked": false,
			"trust_value": 0,
			"trust_reward_claimed": false,
			"limitburst_xp": 0,
			"limitburst_level": 1,
			"current_rarity": random_unit.get("minRare")
		}
		summoned_units.append(new_instance)

	summoned_units = _hydrate_owned_units(summoned_units)
	owned_units_ids.append_array(summoned_units)
	emit_updated()
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "summon_units")
	return {"summoned": summoned_units}

func summon_exp_boost_units(amount: int = 3) -> Dictionary:
	return _summon_fixed_units("900020401", amount, "summon_exp_boost_units")

func summon_trust_units(amount: int = 3) -> Dictionary:
	return _summon_fixed_units("904000105", amount, "summon_trust_units")

func calculate_next_xp_for_unit(unit_inst: Dictionary) -> int:
	if unit_inst.is_empty():
		return 0

	var unit_data: Dictionary = GameDatabase.get_unit(_unit_template_id(unit_inst))
	var runtime_unit: Dictionary = unit_inst.duplicate(true)
	_update_unit_next_xp(runtime_unit, unit_data)
	return int(runtime_unit.get("next_xp", 0))

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
	var current_rarity: int = int(unit.get("current_rarity", 1))
	if current_rarity >= 7:
		result["reason"] = "Unit is at maximum rarity"
		return result

	var awakening_var: Variant = GameDatabase.get_unit_class_up_info(_unit_template_id(unit))
	if awakening_var.is_empty():
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

	var materials: Dictionary = {}
	for item in str(awakening.get("materialInfo", "")).split(',', false):
		var parts := item.split(":")
		if parts.size() >= 3:
			materials[parts[1]] = parts[2].to_int()
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
	
	var awakening_data: Dictionary = GameDatabase.get_unit_class_up_info(_unit_template_id(unit))
	var new_unit_id = awakening_data.get("classUpUnitID")
	unit["unit_id"] = new_unit_id
	
	var unit_data: Dictionary = GameDatabase.get_unit(_unit_template_id(unit))
	var exp_pattern: int = unit_data.get("expPatternId")
	unit.merge(unit_data, true)
	if new_rarity == 7:
		unit["xp"] = _calculate_total_xp_for_level(101, exp_pattern)
		unit["level"] = 101
	else:
		unit["xp"] = 0
		unit["level"] = 1
	
	owned_units_ids[unit_index] = unit

	# Persist + signal
	owned_units_ids = _hydrate_owned_units(owned_units_ids)
	
	emit_updated()
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "awaken_unit")

	InventoryService.emit_updated()

	return {"success": true}

func _unit_template_id(unit: Dictionary) -> int:
	return int(unit.get("unit_id", unit.get("unitId", 0)))

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

	var base_unit_data = GameDatabase.get_unit(int(base_unit.get("unit_id")))
	if base_unit_data.is_empty():
		return {"success": false, "error": "Base unit data not found"}

	var base_max_level: int = _get_unit_max_level(base_unit)
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

		var material_unit_data = GameDatabase.get_unit(int(material_unit.get("unit_id")))
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
			var gains: Dictionary = _calculate_material_enhance_gains(material_unit_value)
			total_exp_to_add += int(gains.get("xp_gain", 0))

		var max_accumulated_exp: int = _get_max_accumulated_exp(base_unit_data)
		base_unit["current_accumulated_exp"] = mini(max_accumulated_exp, int(base_unit.get("current_accumulated_exp", 0)) + total_exp_to_add)
	elif base_unit_type == UNIT_TYPE_TRUST_MATERIAL:
		var total_trust_to_add: float = 0.0
		for material_unit_value in material_units:
			var gains: Dictionary = _calculate_material_enhance_gains(material_unit_value)
			total_trust_to_add += float(gains.get("trust_gain", 0.0))

		base_unit["trust_value"] = min(ENHANCE_MAX_TRUST_VALUE, float(base_unit.get("trust_value", 0.0)) + total_trust_to_add)
	else:
		var total_xp_gain: int = 0
		var total_trust_gain: float = 0.0
		var previous_trust_value: float = float(base_unit.get("trust_value", 0.0))

		for material_unit_value in material_units:
			var gains: Dictionary = _calculate_material_enhance_gains(material_unit_value)
			total_xp_gain += int(gains.get("xp_gain", 0))
			total_trust_gain += float(gains.get("trust_gain", 0.0))

			if _get_unit_type(material_unit_value) == UNIT_TYPE_PLAYABLE and _is_duplicate_unit(base_unit, material_unit_value):
				total_trust_gain += PLAYABLE_DUPLICATE_TRUST_BONUS + _get_material_accumulated_trust(material_unit_value)

		base_unit["xp"] = int(base_unit.get("xp", 0)) + total_xp_gain
		var exp_pattern: int = base_unit_data.get("expPatternId")
		if exp_pattern <= 0:
			exp_pattern = 5
		base_unit["level"] = _calculate_level_from_xp(int(base_unit.get("xp", 0)), exp_pattern, base_max_level)
		_update_unit_next_xp(base_unit, base_unit_data)

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
	
	# 1. Store targets as keys in a dictionary for rapid lookup
	var targets_dict : Dictionary = {}
	for id in material_unit_instance_ids:
		targets_dict[id] = true
		
	var filtered_units: Array = []
	# 2. Filter using dictionary key check (much faster for large datasets)
	filtered_units = owned_units_ids.filter(func(unit): return not targets_dict.has(unit["instance_id"]))

	owned_units_ids = _hydrate_owned_units(filtered_units)
	emit_updated()
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), "enhance_unit")

	if granted_trust_reward != null:
		InventoryService.emit_updated()

	var response: Dictionary = {
		"success": true,
		"updated_base_unit": {
			"instance_id": str(base_unit.get("instance_id", base_unit_instance_id)),
			"level": int(base_unit.get("level", 1)),
			"xp": int(base_unit.get("xp", 0)),
			"trust_value": float(base_unit.get("trust_value", 0.0)),
			"limitburst_level": int(base_unit.get("limitburst_level", 1)),
			"limitburst_xp": int(base_unit.get("limitburst_xp", 0)),
			"current_accumulated_exp": int(base_unit.get("current_accumulated_exp", 0))
		},
		"consumed_material_ids": material_unit_instance_ids.duplicate(),
		"updated_currency": {
			"gil": PlayerProfile.gil
		},
		"granted_trust_reward": granted_trust_reward,
		"trust_reward_warning": trust_reward_warning,
		# Backward-compatible field consumed by current enhance_ui.gd
		"enhanced_unit": base_unit
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
			item_template = GameDatabase.get_materia(int(template_id))

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

func is_material_unit(unit_inst: Dictionary) -> bool:
	"""Check if a unit is a material unit (non-playable) based on job_id."""
	if unit_inst.is_empty():
		return false
		
	var unit_data: Dictionary = GameDatabase.get_unit(_unit_template_id(unit_inst))
	if unit_data.is_empty():
		return false
	
	var job_id: int = int(unit_data.get("job_id", 0))
	return job_id in MATERIAL_UNIT_JOB_IDS

# === Internal helpers ===

func _summon_fixed_units(unit_id: String, amount: int, source_event: String) -> Dictionary:
	var unit_data: Dictionary = GameDatabase.get_unit(int(unit_id))
	if unit_data.is_empty():
		return {"error": "Unit data not found for unit_id %s" % unit_id}

	var summon_amount: int = maxi(1, amount)
	var summoned_units: Array = []
	var initial_rarity: int = unit_data.get("rare")

	for _i in range(summon_amount):
		var new_instance: Dictionary = {
			"unit_id": unit_id,
			"instance_id": InventoryService.generate_instance_id(),
			"xp": 0,
			"level": 1,
			"equipment": {},
			"is_locked": false,
			"trust_value": 0,
			"trust_reward_claimed": false,
			"limitburst_xp": 0,
			"limitburst_level": 1,
			"current_rarity": initial_rarity,
		}
		summoned_units.append(new_instance)

	summoned_units = _hydrate_owned_units(summoned_units)
	owned_units_ids.append_array(summoned_units)
	emit_updated()
	Persistence.save_snapshot(SNAPSHOT_FILE, snapshot_payload(), source_event)
	return {"summoned": summoned_units}

func _name_is_latin(unit_name: String) -> bool:
	if unit_name == "":
		return false
	for i in unit_name.length():
		var cp: int = unit_name.unicode_at(i)
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

func _load_units_from_local() -> Array:
	var envelope: Dictionary = Persistence.load_snapshot(SNAPSHOT_FILE)
	if envelope.is_empty():
		return []

	var data: Variant = envelope.get("data", {})
	if not (data is Dictionary):
		return []

	var payload: Array = data.get("owned_units", [])
	
	return _hydrate_owned_units(payload)

func _get_unit_type(unit_data: Dictionary) -> String:
	if unit_data.is_empty():
		return UNIT_TYPE_PLAYABLE
	if int(unit_data.get("jobId", 0)) == EXP_UNIT_JOB_ID:
		return UNIT_TYPE_EXP_MATERIAL
	if int(unit_data.get("jobId", 0)) == TRUST_MATERIAL_JOB_ID:
		return UNIT_TYPE_TRUST_MATERIAL
	return UNIT_TYPE_PLAYABLE

func _get_base_exp_yield(unit: Dictionary) -> int:
	if unit.has("base_exp_yield"):
		return int(unit.get("base_exp_yield", 0))

	var unit_type: String = _get_unit_type(unit)
	if unit_type == UNIT_TYPE_EXP_MATERIAL:
		if int(unit.get("jobId", 0)) != EXP_UNIT_JOB_ID:
			return 0
		var exp_pattern: int = int(unit.get("expPatternId"))
		return int(EXP_UNIT_YIELD_BY_PATTERN.get(exp_pattern, 0))

	if unit_type == UNIT_TYPE_PLAYABLE:
		var rarity: int = maxi(1, int(unit.get("current_rarity", int(unit.get("rarity_min", 1)))))
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

func _get_trust_yield(unit_data: Dictionary) -> float:
	if unit_data.has("trust_yield"):
		return max(0.0, float(unit_data.get("trust_yield", 0.0)))
	return float(TRUST_YIELD_BY_UNIT_ID.get(int(unit_data.get("unit_id")), 0.0))

func _is_duplicate_unit(base_unit: Dictionary, material_unit: Dictionary) -> bool:
	return str(base_unit.get("unitSeries")) == str(material_unit.get("unitSeries"))

func _get_max_accumulated_exp(unit_data: Dictionary) -> int:
	if unit_data.has("max_accumulated_exp"):
		return maxi(0, int(unit_data.get("max_accumulated_exp", DEFAULT_MAX_ACCUMULATED_EXP)))
	return DEFAULT_MAX_ACCUMULATED_EXP

func _resolve_trust_reward(unit_data: Dictionary) -> Dictionary:
	if unit_data.is_empty():
		return {"error": "Missing unit static data for trust reward"}

	var tmr_value: Variant = unit_data.get("trustMasterReward", null)
	tmr_value = tmr_value.split(":")
	if tmr_value.size() >= 2 and tmr_value[1] != null:
		var reward_type: String = str(tmr_value[0])
		var reward_id: String = str(tmr_value[1])
		if reward_type == "21":
			if GameDatabase.get_equipment(reward_id).is_empty():
				return {"error": "Trust reward equipment template not found"}
			return {"reward_type": "EQUIP", "template_id": reward_id}
		elif reward_type == "22":
			if GameDatabase.get_materia(int(reward_id)).is_empty():
				return {"error": "Trust reward materia template not found"}
			return {"reward_type": "MATERIA", "template_id": reward_id}
		else:
			return {"error": "Unsupported trust reward type: %s" % reward_type}

	var trust_mastery_id: String = str(unit_data.get("trust_mastery_id", ""))
	if trust_mastery_id != "":
		if not GameDatabase.get_equipment(trust_mastery_id).is_empty():
			return {"reward_type": "EQUIP", "template_id": trust_mastery_id}
		if not GameDatabase.get_materia(int(trust_mastery_id)).is_empty():
			return {"reward_type": "MATERIA", "template_id": trust_mastery_id}

	return {"error": "No supported trust reward configured"}

func _calculate_material_enhance_gains(material_unit: Dictionary) -> Dictionary:
	var material_type: String = _get_unit_type(material_unit)

	if material_type == UNIT_TYPE_EXP_MATERIAL:
		var exp_total: int = _get_base_exp_yield(material_unit) + _get_material_accumulated_exp(material_unit)
		return {"xp_gain": exp_total, "trust_gain": 0.0, "limitburst_gain": 0}

	if material_type == UNIT_TYPE_TRUST_MATERIAL:
		var trust_total: float = _get_trust_yield(material_unit) + _get_material_accumulated_trust(material_unit)
		return {"xp_gain": 0, "trust_gain": trust_total, "limitburst_gain": 0}

	var base_exp: int = _get_base_exp_yield(material_unit)
	var stored_exp: int = _get_material_accumulated_exp(material_unit)
	var xp_gain: int = base_exp + int(floor(float(stored_exp) * PLAYABLE_ACCUMULATED_EXP_TRANSFER_RATE))
	return {"xp_gain": xp_gain, "trust_gain": 0.0, "limitburst_gain": 0}

func _get_unit_max_level(unit: Dictionary) -> int:
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

func _calculate_total_xp_for_level(level: int, exp_pattern: int) -> int:
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

func _calculate_level_from_xp(total_xp: int, exp_pattern: int, max_level: int) -> int:
	_ensure_exp_patterns_loaded()
	var arr: PackedInt32Array = _unit_exp_patterns_cache.get(exp_pattern, PackedInt32Array())
	if arr.is_empty():
		return 1

	var calculated_level: int = arr.bsearch(total_xp, false) - 1
	return clampi(calculated_level, 1, max_level)

func _update_unit_next_xp(unit: Dictionary, unit_data: Dictionary) -> void:
	var exp_pattern: int = unit_data.get("expPatternId")
	if exp_pattern <= 0:
		exp_pattern = 5

	var max_level: int = _get_unit_max_level(unit)
	var level: int = int(unit.get("level", 1))
	if level < max_level:
		var next_level_xp: int = _calculate_total_xp_for_level(level + 1, exp_pattern)
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
	var game_data_units: Array = GameDatabase.get_all_units()
	for unit_instance in units:
		if typeof(unit_instance) != TYPE_DICTIONARY:
			hydrated_units.append(unit_instance)
			continue
		
		var hydrated_unit: Dictionary = {}

		# Base Template Data
		var unit_id = str(unit_instance.get("unit_id", unit_instance.get("unitId", "")))
		var template_data = game_data_units.filter(func(x): return x.unitId == int(unit_id))
		template_data = template_data[0] if not template_data.is_empty() else null

		hydrated_unit.merge(template_data)

		# Instance Data
		hydrated_unit.merge(unit_instance, true)
		hydrated_unit["equipment"] = _normalize_unit_equipment(unit_instance.get("equipment", {}))

		# Recalculate level and next_xp from current xp
		var xp_val: int = int(hydrated_unit.get("xp", 0))
		var exp_pattern: int = template_data.get("expPatternId")

		var max_level: int = template_data.get("maxLv")
		var calc_level: int = _calculate_level_from_xp(xp_val, exp_pattern, max_level)
		hydrated_unit["level"] = calc_level

		if calc_level < max_level:
			var next_level_xp: int = _calculate_total_xp_for_level(calc_level + 1, exp_pattern)
			hydrated_unit["next_xp"] = maxi(0, next_level_xp - xp_val)
		else:
			hydrated_unit["next_xp"] = 0

		# 4. Calculate Final Stats
		hydrated_unit["final_stats"] = StatCalculator.calculate_final_stats(hydrated_unit)

		hydrated_units.append(hydrated_unit)

	return hydrated_units
