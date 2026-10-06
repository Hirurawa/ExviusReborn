extends Node
## EquipmentValidator — central rules for equipping items to a unit.
## Pure helpers; no state, no persistence. Read template data from GameDatabase /
## InventoryService and answer "can this equip happen?" questions used by both
## the equip UI (filtering, slot-lock display) and UnitService (authoritative
## server-side rejection).
##
## The hands (wiki, dual wield; the user's rules, 2026-10-02):
##   - A two-handed weapon takes both hands: equipping one takes the other hand's item
##     off, and nothing else goes into the hand it holds.
##   - Two shields never go together, dual wield or not.
##   - Two one-handed weapons need a dual-wield permit (passive opcode 14) covering both
##     weapon types, among the passives in effect once the change is made: a weapon can
##     grant its own (Bowie Knife; Aqua Blade for swords only), and a permit can hang on
##     an equip condition (Twin Saber Style). Without one, a second weapon cannot go in.
##   - A change that takes the permit away goes through and takes a weapon off: the other
##     hand's when one weapon is swapped for another, the left hand's otherwise (taking
##     off Genji Glove or a dual-wield materia).

const HAND_SLOTS: Array[String] = ["r_hand", "l_hand"]

const ERR_OK: String = ""
const ERR_TWO_HANDED_LOCKED: String = "ERR_TWO_HANDED_LOCKED"
const ERR_DUAL_WIELD_REQUIRED: String = "ERR_DUAL_WIELD_REQUIRED"
const ERR_TWO_SHIELDS: String = "ERR_TWO_SHIELDS"
const ERR_EQUIPMENT_ALREADY_EQUIPPED: String = "ERR_EQUIPMENT_ALREADY_EQUIPPED"

## Passive opcode 14: enable dual wielding (of the listed weapon types, or any).
const _OP_DUAL_WIELD: int = 14

func can_equip(unit_inst: Dictionary, slot_id: String, item_template: Dictionary, owned_units: Array, requesting_item_instance_id: String = "") -> Dictionary:
	## Returns {ok: bool, reason: String, conflicting_unit_id: String, unequip: Array}.
	## An empty `item_template` asks about taking the slot's item off. `unequip` holds the
	## slots whose items come off with the change (the hand rules above); it is set with
	## ERR_EQUIPMENT_ALREADY_EQUIPPED too, for a transfer the caller approves.
	## `owned_units` is the full list (UnitService.owned_units_ids) so we can detect
	## the "already equipped to another unit" conflict.
	var result: Dictionary = {"ok": true, "reason": ERR_OK, "conflicting_unit_id": "", "unequip": []}

	# 1) The hands, with the change made.
	var incoming: Dictionary = {}
	if not item_template.is_empty():
		var template_id: String = InventoryService.get_equipment_template_id(requesting_item_instance_id) if requesting_item_instance_id != "" else ""
		incoming = StatCalculator.resolve_item(slot_id, template_id)
		if incoming.is_empty():
			# No inventory record to name it by: the template alone (no equip condition
			# can name it then).
			var kind: String = PassiveSources.KIND_MATERIA if slot_id.begins_with("ability_") else PassiveSources.KIND_EQUIPMENT
			incoming = {"slot": slot_id, "kind": kind, "id": 0, "data": item_template}
	var hands: Dictionary = check_hands(unit_inst, StatCalculator.resolve_equipped_items(unit_inst), slot_id, incoming)
	if str(hands["reason"]) != ERR_OK:
		result["ok"] = false
		result["reason"] = hands["reason"]
		return result
	result["unequip"] = hands["unequip"]

	# 2) Sharing conflict: the same item already equipped on a different unit.
	var instance_id: String = str(unit_inst.get("instance_id", ""))
	if requesting_item_instance_id != "":
		var conflicting_unit_id: String = _find_conflicting_unit(owned_units, instance_id, slot_id, requesting_item_instance_id)
		if conflicting_unit_id != "":
			result["ok"] = false
			result["reason"] = ERR_EQUIPMENT_ALREADY_EQUIPPED
			result["conflicting_unit_id"] = conflicting_unit_id
	return result

## The hand rules for putting `incoming` into `slot_id` of a unit wearing `items`. Both
## are entries as StatCalculator.resolve_equipped_items returns them ({ slot, kind, id,
## data }); an empty `incoming` takes the slot's item off. Reads GameDatabase but no
## account state, so tests can pass any items. Returns { reason (ERR_OK when the change
## may happen), unequip (hand slots whose items come off with it) }.
func check_hands(unit_inst: Dictionary, items: Array, slot_id: String, incoming: Dictionary) -> Dictionary:
	var result: Dictionary = {"reason": ERR_OK, "unequip": []}
	var data: Dictionary = incoming.get("data", {})
	var is_hand: bool = slot_id in HAND_SLOTS
	var other_hand: String = _other_hand(slot_id)
	if is_hand and not incoming.is_empty():
		var other: Dictionary = _data_in(items, other_hand)
		if bool(data.get("is_twohanded", false)):
			if not other.is_empty():
				result["unequip"] = [other_hand]
			return result
		if bool(other.get("is_twohanded", false)):
			result["reason"] = ERR_TWO_HANDED_LOCKED
			return result
		if _is_shield(data) and _is_shield(other):
			result["reason"] = ERR_TWO_SHIELDS
			return result

	var after: Array = []
	for item in items:
		if str(item.get("slot", "")) != slot_id:
			after.append(item)
	if not incoming.is_empty():
		after.append(incoming)
	var weapon_types: Array[int] = []
	for item in after:
		var item_data: Dictionary = item.get("data", {})
		if str(item.get("slot", "")) in HAND_SLOTS and _is_weapon(item_data):
			weapon_types.append(int(item_data.get("type_id", -1)))
	if weapon_types.size() < 2:
		return result
	var allow: Dictionary = dual_wield_permits(unit_inst, after)
	if _dual_wield_permits(allow, weapon_types[0]) and _dual_wield_permits(allow, weapon_types[1]):
		return result

	if is_hand and _is_weapon(data):
		if _is_weapon(_data_in(items, slot_id)):
			# One weapon swapped for another the unit cannot dual wield with the first:
			# the other hand's weapon comes off.
			result["unequip"] = [other_hand]
		else:
			result["reason"] = ERR_DUAL_WIELD_REQUIRED
	else:
		# The change took the permit away (Genji Glove, a dual-wield materia, the item an
		# equip condition needs): the left hand's weapon comes off.
		result["unequip"] = ["l_hand"]
	return result

## The hand rule putting the item with `template_id` into `slot_id` breaks (ERR_OK when
## none), for the equip list. `items` is the unit's gear as
## StatCalculator.resolve_equipped_items returns it, resolved once per list.
func hand_problem(unit_inst: Dictionary, items: Array, slot_id: String, template_id: String) -> String:
	var incoming: Dictionary = StatCalculator.resolve_item(slot_id, template_id)
	if incoming.is_empty():
		return ERR_OK
	return str(check_hands(unit_inst, items, slot_id, incoming)["reason"])

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
	## dual_wield_permits for the gear the unit wears.
	return dual_wield_permits(unit_inst, StatCalculator.resolve_equipped_items(unit_inst))

func dual_wield_permits(unit_inst: Dictionary, items: Array) -> Dictionary:
	## Scans the `effects_raw` of the passives in effect with `items` equipped for opcode 14.
	## Returns {has: bool, allows_any: bool, type_ids: Array[int]}.
	## - `has`  = unit has any DUAL_WIELD passive
	## - `allows_any` = at least one opcode-14 entry carried `['none']` (broad permit)
	## - `type_ids` = union of restricted type_ids from non-broad entries
	var result: Dictionary = {"has": false, "allows_any": false, "type_ids": []}
	var seen_types: Dictionary = {}

	for effects_raw in _gather_passive_effects_raw(unit_inst, items):
		for entry in effects_raw:
			if not (entry is Array) or entry.size() < 4:
				continue
			if int(entry[2]) != _OP_DUAL_WIELD:
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

func _is_weapon(item_template: Dictionary) -> bool:
	return str(item_template.get("slot", "")) == "Weapon"

func _is_shield(item_template: Dictionary) -> bool:
	return str(item_template.get("slot", "")) == "Shield"

## The record of the item in `slot_id` among `items`; {} when the slot is empty.
func _data_in(items: Array, slot_id: String) -> Dictionary:
	for item in items:
		if str(item.get("slot", "")) == slot_id:
			return item.get("data", {})
	return {}

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

func _gather_passive_effects_raw(unit_inst: Dictionary, items: Array) -> Array:
	## The `effects_raw` of every passive in effect on the unit with `items` equipped
	## (traits and awakenings, equipment, materia, the party esper's board), from the same
	## collection StatCalculator uses. Passives whose equip condition fails are left out.
	var collected: Array = []
	for source in StatCalculator.passive_sources_for(unit_inst, items):
		if not bool(source["active"]):
			continue
		var raw: Variant = (source["record"] as Dictionary).get("effects_raw", [])
		if raw is Array:
			collected.append(raw)
	return collected
