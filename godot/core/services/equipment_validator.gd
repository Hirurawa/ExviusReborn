extends Node
## EquipmentValidator — central rules for equipping items to a unit.
## Pure helpers; no state, no persistence. Read template data from StaticData /
## InventoryService and answer "can this equip happen?" questions used by both
## the equip UI (filtering, slot-lock display) and UnitService (authoritative
## server-side rejection).

const HAND_SLOTS: Array[String] = ["r_hand", "l_hand"]

const ERR_OK: String = ""
const ERR_TWO_HANDED_LOCKED: String = "ERR_TWO_HANDED_LOCKED"
const ERR_DUAL_WIELD_REQUIRED: String = "ERR_DUAL_WIELD_REQUIRED"
const ERR_EQUIPMENT_ALREADY_EQUIPPED: String = "ERR_EQUIPMENT_ALREADY_EQUIPPED"


func can_equip(unit_inst: Dictionary, slot_id: String, item_template: Dictionary, owned_units: Array, requesting_item_instance_id: String = "") -> Dictionary:
	## Returns {ok: bool, reason: String, conflicting_unit_id: String}.
	## `owned_units` is the full list (UnitService.owned_units_ids) so we can detect
	## the "already equipped to another unit" conflict.
	var result: Dictionary = {"ok": true, "reason": ERR_OK, "conflicting_unit_id": ""}
	if item_template.is_empty():
		return result

	# 1) Sharing conflict — same item already equipped on a different unit.
	var instance_id: String = str(unit_inst.get("instance_id", ""))
	if requesting_item_instance_id != "":
		var conflicting_unit_id: String = _find_conflicting_unit(owned_units, instance_id, slot_id, requesting_item_instance_id)
		if conflicting_unit_id != "":
			result["ok"] = false
			result["reason"] = ERR_EQUIPMENT_ALREADY_EQUIPPED
			result["conflicting_unit_id"] = conflicting_unit_id
			return result

	# 2) Two-handed lock on the *other* hand (cannot equip into a slot the other
	#    hand's two-handed weapon has reserved). Two-handed equips into r_hand or
	#    l_hand themselves are handled by the auto-unequip logic in UnitService.
	if slot_id in HAND_SLOTS and is_slot_locked_by_two_handed(unit_inst, slot_id):
		var incoming_is_twohanded: bool = bool(item_template.get("is_twohanded", false))
		if not incoming_is_twohanded:
			result["ok"] = false
			result["reason"] = ERR_TWO_HANDED_LOCKED
			return result

	# 3) Dual-wield rule — only one weapon at a time unless the unit has opcode 14
	#    permitting both weapons' type_ids.
	if slot_id in HAND_SLOTS and _is_one_handed_weapon(item_template):
		var other_hand: String = _other_hand(slot_id)
		var other_weapon: Dictionary = _get_one_handed_weapon_in_slot(unit_inst, other_hand)
		if not other_weapon.is_empty():
			var allow: Dictionary = get_dual_wield_allowed_type_ids(unit_inst)
			var incoming_type: int = int(item_template.get("type_id", -1))
			var other_type: int = int(other_weapon.get("type_id", -1))
			if not _dual_wield_permits(allow, incoming_type) or not _dual_wield_permits(allow, other_type):
				result["ok"] = false
				result["reason"] = ERR_DUAL_WIELD_REQUIRED
				return result

	return result


func is_slot_locked_by_two_handed(unit_inst: Dictionary, slot_id: String) -> bool:
	## True when the *other* hand holds a two-handed weapon (so this hand is reserved).
	if not (slot_id in HAND_SLOTS):
		return false
	var equipment: Dictionary = unit_inst.get("equipment", {})
	var other_item_id: String = str(equipment.get(_other_hand(slot_id), ""))
	if other_item_id == "":
		return false
	var other_template_id: String = InventoryService.get_equipment_template_id(other_item_id)
	var other_template: Dictionary = GameDatabase.get_equipment(other_template_id)
	return bool(other_template.get("is_twohanded", false))


func get_dual_wield_allowed_type_ids(unit_inst: Dictionary) -> Dictionary:
	## Scans the unit's accessible passive `effects_raw` for opcode 14.
	## Returns {has: bool, allows_any: bool, type_ids: Array[int]}.
	## - `has`  = unit has any DUAL_WIELD passive
	## - `allows_any` = at least one opcode-14 entry carried `['none']` (broad permit)
	## - `type_ids` = union of restricted type_ids from non-broad entries
	var result: Dictionary = {"has": false, "allows_any": false, "type_ids": []}
	var seen_types: Dictionary = {}

	for effects_raw in _gather_passive_effects_raw(unit_inst):
		for entry in effects_raw:
			if not (entry is Array) or entry.size() < 4:
				continue
			if int(entry[2]) != 14:
				continue
			result["has"] = true
			var payload: Variant = entry[3]
			if not (payload is Array) or (payload as Array).is_empty():
				result["allows_any"] = true
				continue
			var first: Variant = (payload as Array)[0]
			if first is String and String(first) == "none":
				result["allows_any"] = true
				continue
			for type_id in payload:
				if type_id is int or type_id is float:
					seen_types[int(type_id)] = true

	result["type_ids"] = seen_types.keys()
	return result


# === Internal helpers ===

func _other_hand(slot_id: String) -> String:
	return "l_hand" if slot_id == "r_hand" else "r_hand"


func _is_one_handed_weapon(item_template: Dictionary) -> bool:
	return str(item_template.get("slot", "")) == "Weapon" and not bool(item_template.get("is_twohanded", false))


func _get_one_handed_weapon_in_slot(unit_inst: Dictionary, slot_id: String) -> Dictionary:
	var equipment: Dictionary = unit_inst.get("equipment", {})
	var item_id: String = str(equipment.get(slot_id, ""))
	if item_id == "":
		return {}
	var template_id: String = InventoryService.get_equipment_template_id(item_id)
	var template: Dictionary = GameDatabase.get_equipment(template_id)
	if template.is_empty():
		return {}
	if not _is_one_handed_weapon(template):
		return {}
	return template


func _dual_wield_permits(allow: Dictionary, weapon_type_id: int) -> bool:
	if not bool(allow.get("has", false)):
		return false
	if bool(allow.get("allows_any", false)):
		return true
	return weapon_type_id in (allow.get("type_ids", []) as Array)


func _find_conflicting_unit(owned_units: Array, this_unit_instance_id: String, slot_id: String, item_instance_id: String) -> String:
	for existing in owned_units:
		if not (existing is Dictionary):
			continue
		var other_unit_id: String = str(existing.get("instance_id", ""))
		var other_equipment: Dictionary = existing.get("equipment", {})
		if not (other_equipment is Dictionary):
			continue
		for existing_slot_id in other_equipment.keys():
			if str(other_equipment.get(existing_slot_id, "")) != item_instance_id:
				continue
			# Same slot on same unit = re-equip-no-op, not a conflict.
			if other_unit_id == this_unit_instance_id and str(existing_slot_id) == slot_id:
				continue
			return other_unit_id
	return ""


func _gather_passive_effects_raw(unit_inst: Dictionary) -> Array:
	## Collects `effects_raw` arrays from all passive sources currently active on
	## the unit: filtered innate traits, equipment items' direct effects_raw,
	## and passive skills granted by equipment.
	var collected: Array = []
	var rarity: int = int(unit_inst.get("current_rarity", 1))
	var level: int = int(unit_inst.get("level", 1))

	# Innate traits — same gating as StatCalculator.
	var innate_skills: Variant = unit_inst.get("skills", [])
	if innate_skills is Array:
		for skill in innate_skills:
			if not (skill is Dictionary):
				continue
			var req_rarity_var: Variant = skill.get("rarity", 999)
			if typeof(req_rarity_var) == TYPE_STRING:
				continue
			var req_rarity: int = int(req_rarity_var)
			var req_level: int = int(skill.get("level", 999))
			if rarity > req_rarity or (rarity == req_rarity and level >= req_level):
				_collect_passive_skill_effects(str(skill.get("id", "")), collected)

	# Equipment.
	var equipment: Dictionary = unit_inst.get("equipment", {})
	for slot_id in equipment.keys():
		var item_id: String = str(equipment.get(slot_id, ""))
		if item_id == "":
			continue
		var template_id: String = InventoryService.get_equipment_template_id(item_id)
		var item_data: Dictionary = GameDatabase.get_equipment(template_id)
		if item_data.is_empty():
			item_data = StaticData.game_data_materia.get(template_id, {})
		if item_data.is_empty():
			continue
		var raw: Variant = item_data.get("effects_raw", [])
		if raw is Array:
			collected.append(raw)
		var item_skills: Variant = item_data.get("skills", [])
		if item_skills is Array:
			for skill_id in item_skills:
				_collect_passive_skill_effects(str(skill_id), collected)

	return collected


func _collect_passive_skill_effects(skill_id: String, collected: Array) -> void:
	if skill_id == "":
		return
	var skill_data: Dictionary = GameDatabase.get_passive(skill_id)
	if skill_data.is_empty():
		return
	var raw: Variant = skill_data.get("effects_raw", [])
	if raw is Array:
		collected.append(raw)
