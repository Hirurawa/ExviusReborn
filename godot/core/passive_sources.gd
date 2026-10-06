class_name PassiveSources
extends RefCounted

## Pure helpers that decide which of a unit's passives are in effect: the loadout (what
## the unit has equipped, per hand and in total) and passive equip conditions.
## StatCalculator gathers the inputs from the services and GameDatabase; nothing here
## reads an autoload, so tests can build loadouts from plain records.

## Item kinds in StatCalculator.resolve_equipped_items and in decoded equip conditions.
const KIND_EQUIPMENT: String = "equipment"
const KIND_MATERIA: String = "materia"
## A condition alternative this game has no data for (type 27, probably vision cards).
const KIND_UNKNOWN: String = "unknown"

## What a hand holds, from the equip_item record's slot (equipType 1 and 2).
const HAND_WEAPON: String = "weapon"
const HAND_SHIELD: String = "shield"

const CORE_STATS: PackedStringArray = ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]
## Slots of equip_item.ailmentInflict: poison, blind, sleep, silence, paralysis,
## confusion, disease, petrify (StatCalculator.STATUSES order).
const AILMENT_SLOTS: int = 8

## ability.equipCondition type ids.
const _CONDITION_TYPE_EQUIPMENT: int = 21
const _CONDITION_TYPE_MATERIA: int = 22


## A passive's equipCondition as a list of alternatives, { kind, type, id }; empty when
## the passive has none. The grammar is comma-separated `6@<type>:<id>@1`: type 21 is an
## equip_item id, 22 a materia id, 27 an id in no table of the DB (KIND_UNKNOWN). The
## leading 6 and trailing 1 are the same in all 1044 conditioned passives.
static func decode_equip_condition(raw: String) -> Array[Dictionary]:
	var alternatives: Array[Dictionary] = []
	for token in raw.split(",", false):
		var parts: PackedStringArray = token.strip_edges().split("@")
		var target: PackedStringArray = parts[1].split(":") if parts.size() >= 2 else PackedStringArray()
		var type_id: int = int(target[0]) if target.size() == 2 and target[0].is_valid_int() else 0
		var item_id: int = int(target[1]) if target.size() == 2 and target[1].is_valid_int() else 0
		var kind: String = KIND_UNKNOWN
		if type_id == _CONDITION_TYPE_EQUIPMENT:
			kind = KIND_EQUIPMENT
		elif type_id == _CONDITION_TYPE_MATERIA:
			kind = KIND_MATERIA
		alternatives.append({"kind": kind, "type": type_id, "id": item_id})
	return alternatives


## True when an equip condition holds for the loadout: it has no alternatives, or any one
## of them is equipped. An unknown alternative never holds. Alternatives are "any of"
## because they pair items with their own upgrades (Obscura Blade, Obscura Blade+).
static func condition_holds(condition: Array, loadout: Dictionary) -> bool:
	if condition.is_empty():
		return true
	var item_ids: Array = loadout.get("item_ids", [])
	var materia_ids: Array = loadout.get("materia_ids", [])
	for alternative in condition:
		var item_id: int = int(alternative.get("id", 0))
		match str(alternative.get("kind", "")):
			KIND_EQUIPMENT:
				if item_ids.has(item_id):
					return true
			KIND_MATERIA:
				if materia_ids.has(item_id):
					return true
	return false


## What the unit has equipped. `items` holds one entry per filled slot, as
## StatCalculator.resolve_equipped_items returns them: { slot, kind (KIND_EQUIPMENT or
## KIND_MATERIA), id (template id), data (the GameDatabase record) }. Returns:
##   hands              [{ slot, item_id, kind (HAND_WEAPON or HAND_SHIELD), category,
##                        two_handed, stats, elements, variance, inflicts }], the right
##                        hand first; inflicts holds AILMENT_SLOTS chances in percent
##                        (ailmentInflict: Sleep Dagger is [0, 0, 30, 0, 0, 0, 0, 0]).
##                        StatCalculator adds `equipment_bonus`, the hand's share of
##                        the equipment-stat boosts, once the passives are known
##   categories         equipCategory of every equipped item: weapon types 1-16,
##                      shields 30-31, hats 40-41, body armor 50-53, accessories 60
##   item_ids           template ids of the equipment
##   materia_ids        template ids of the materia
##   stats              the six stats summed over the equipment (materia has none)
##   weapon_count
##   dual_wielding      two weapons
##   single_weapon      one weapon and nothing in the other hand: true doublehand's
##                      condition, for a one- or two-handed weapon
##   single_one_handed  single_weapon with a one-handed weapon: doublehand's condition
##   two_handed         single_weapon with a two-handed weapon
##   unarmed            no weapon in either hand
## A shield in the other hand is not "empty" (the user's rule, 2026-09-30).
static func build_loadout(items: Array) -> Dictionary:
	var hands: Array[Dictionary] = []
	var categories: Array[int] = []
	var item_ids: Array[int] = []
	var materia_ids: Array[int] = []
	var stats: Dictionary = {}
	for stat_name in CORE_STATS:
		stats[stat_name] = 0

	for item in items:
		var data: Dictionary = item.get("data", {})
		if str(item.get("kind", "")) == KIND_MATERIA:
			materia_ids.append(int(item.get("id", 0)))
			continue
		item_ids.append(int(item.get("id", 0)))
		var category: int = int(data.get("type_id", 0))
		categories.append(category)
		var item_stats: Dictionary = data.get("stats", {})
		for stat_name in CORE_STATS:
			stats[stat_name] += int(item_stats.get(stat_name, 0))

		var hand_kind: String = _hand_kind(str(data.get("slot", "")))
		if hand_kind == "":
			continue
		var hand_stats: Dictionary = {}
		for stat_name in CORE_STATS:
			hand_stats[stat_name] = int(item_stats.get(stat_name, 0))
		var elements: Variant = item_stats.get("element_inflict")
		var variance: Variant = data.get("dmgVariance")
		hands.append({
			"slot": str(item.get("slot", "")),
			"item_id": int(item.get("id", 0)),
			"kind": hand_kind,
			"category": category,
			"two_handed": bool(data.get("is_twohanded", false)),
			"stats": hand_stats,
			"elements": elements if elements is Array else [],
			"variance": "" if variance == null else str(variance),
			"inflicts": _inflict_chances(item_stats.get("status_inflict")),
		})
	# The equipment dict's order is whatever the save had; a dual wielder swings with the
	# right hand first.
	hands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _hand_order(str(a["slot"])) < _hand_order(str(b["slot"])))

	var weapons: Array[Dictionary] = []
	for hand in hands:
		if hand["kind"] == HAND_WEAPON:
			weapons.append(hand)
	var single_weapon: bool = weapons.size() == 1 and hands.size() == 1
	return {
		"hands": hands,
		"categories": categories,
		"item_ids": item_ids,
		"materia_ids": materia_ids,
		"stats": stats,
		"weapon_count": weapons.size(),
		"dual_wielding": weapons.size() >= 2,
		"single_weapon": single_weapon,
		"single_one_handed": single_weapon and not bool(weapons[0]["two_handed"]),
		"two_handed": single_weapon and bool(weapons[0]["two_handed"]),
		"unarmed": weapons.is_empty(),
	}


## An equipment record's status_inflict (GameDatabase keeps the non-zero slots as
## { 1-based slot: "30" }; null when the column is empty) as AILMENT_SLOTS ints.
static func _inflict_chances(raw: Variant) -> Array[int]:
	var chances: Array[int] = []
	chances.resize(AILMENT_SLOTS)
	chances.fill(0)
	if raw is Dictionary:
		for slot in raw:
			var index: int = int(str(slot)) - 1
			if index >= 0 and index < AILMENT_SLOTS:
				chances[index] = int(str(raw[slot]))
	return chances


## Sort key of a hand slot: the right hand (r_hand) before the left (l_hand).
static func _hand_order(slot: String) -> int:
	match slot:
		"r_hand":
			return 0
		"l_hand":
			return 1
	return 2


## HAND_WEAPON, HAND_SHIELD, or "" for an item worn elsewhere, from the record's slot name
## (GameDatabase._EQUIP_SLOT_NAMES).
static func _hand_kind(slot_name: String) -> String:
	match slot_name:
		"Weapon":
			return HAND_WEAPON
		"Shield":
			return HAND_SHIELD
	return ""
