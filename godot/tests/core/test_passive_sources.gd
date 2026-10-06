extends "res://tests/test_case.gd"

## PassiveSources: passive equip conditions (decoding and checking) and the loadout,
## built from real equipment and materia records. Reads GameDatabase; writes nothing.

const BROADSWORD: int = 302000100  # one-handed sword, ATK 15
const MYTHRIL_SWORD: int = 302000700  # one-handed sword, ATK 26
const KATAR: int = 301008300  # two-handed dagger
const SLEEP_DAGGER: int = 301000600  # 30% sleep (ailmentInflict 0,0,30,0,0,0,0,0)
const LEATHER_SHIELD: int = 401001000
const ESCUTCHEON: int = 401002200  # shield
const BRAVE_SUIT: int = 405001700  # clothes, DEF 51
const HP_MATERIA: int = 504100010  # "HP +10%"
## "Rallied Courage": +15% HP, MP, DEF and SPR with Brave Suit or Escutcheon (FFT).
const RALLIED_COURAGE: String = "226690"


static func _equipment(slot: String, template_id: int) -> Dictionary:
	return {
		"slot": slot, "kind": PassiveSources.KIND_EQUIPMENT, "id": template_id,
		"data": GameDatabase.get_equipment(template_id),
	}


static func _materia(slot: String, template_id: int) -> Dictionary:
	return {
		"slot": slot, "kind": PassiveSources.KIND_MATERIA, "id": template_id,
		"data": GameDatabase.get_materia(template_id),
	}


func test_decodes_each_kind_of_alternative() -> void:
	var condition: Array[Dictionary] = PassiveSources.decode_equip_condition(
		"6@21:405001700@1,6@22:1500000149@1,6@27:401001201@1")
	assert_eq(condition.size(), 3)
	assert_eq(condition[0], {"kind": PassiveSources.KIND_EQUIPMENT, "type": 21, "id": 405001700})
	assert_eq(condition[1], {"kind": PassiveSources.KIND_MATERIA, "type": 22, "id": 1500000149})
	assert_eq(condition[2], {"kind": PassiveSources.KIND_UNKNOWN, "type": 27, "id": 401001201})
	assert_eq(PassiveSources.decode_equip_condition(""), [])


func test_passive_records_carry_their_condition() -> void:
	var rallied: Dictionary = GameDatabase.get_passive(RALLIED_COURAGE)
	assert_eq(rallied["equip_condition"], [
		{"kind": PassiveSources.KIND_EQUIPMENT, "type": 21, "id": BRAVE_SUIT},
		{"kind": PassiveSources.KIND_EQUIPMENT, "type": 21, "id": ESCUTCHEON},
	])
	assert_eq(GameDatabase.get_passive("100010")["equip_condition"], [], "HP +10% has no condition")


func test_any_one_alternative_satisfies_a_condition() -> void:
	var condition: Array = GameDatabase.get_passive(RALLIED_COURAGE)["equip_condition"]
	var suit: Dictionary = PassiveSources.build_loadout([_equipment("body", BRAVE_SUIT)])
	var shield: Dictionary = PassiveSources.build_loadout([_equipment("l_hand", ESCUTCHEON)])
	var neither: Dictionary = PassiveSources.build_loadout([_equipment("r_hand", BROADSWORD)])
	assert_true(PassiveSources.condition_holds(condition, suit), "Brave Suit")
	assert_true(PassiveSources.condition_holds(condition, shield), "Escutcheon (FFT)")
	assert_false(PassiveSources.condition_holds(condition, neither), "a broadsword")
	assert_true(PassiveSources.condition_holds([], neither), "no condition always holds")


func test_materia_and_unknown_alternatives() -> void:
	var loadout: Dictionary = PassiveSources.build_loadout([_materia("ability_1", HP_MATERIA)])
	var on_materia: Array = [{"kind": PassiveSources.KIND_MATERIA, "type": 22, "id": HP_MATERIA}]
	assert_true(PassiveSources.condition_holds(on_materia, loadout))
	var on_equipment_id: Array = [{"kind": PassiveSources.KIND_EQUIPMENT, "type": 21, "id": HP_MATERIA}]
	assert_false(PassiveSources.condition_holds(on_equipment_id, loadout), "a materia id is not an equipment id")
	var unknown: Array = [{"kind": PassiveSources.KIND_UNKNOWN, "type": 27, "id": HP_MATERIA}]
	assert_false(PassiveSources.condition_holds(unknown, loadout), "type 27 never holds")


func test_one_handed_weapon_with_the_other_hand_empty() -> void:
	var loadout: Dictionary = PassiveSources.build_loadout([
		_equipment("r_hand", BROADSWORD), _equipment("body", BRAVE_SUIT), _materia("ability_1", HP_MATERIA),
	])
	assert_eq(loadout["weapon_count"], 1)
	assert_true(loadout["single_weapon"], "true doublehand holds")
	assert_true(loadout["single_one_handed"], "doublehand holds")
	assert_false(loadout["two_handed"])
	assert_false(loadout["dual_wielding"])
	assert_false(loadout["unarmed"])
	assert_eq(loadout["item_ids"], [BROADSWORD, BRAVE_SUIT])
	assert_eq(loadout["materia_ids"], [HP_MATERIA])
	assert_eq(loadout["categories"], [2, 50], "sword, clothes")
	assert_eq(loadout["stats"]["ATK"], 15)
	assert_eq(loadout["stats"]["DEF"], 51)
	var hands: Array = loadout["hands"]
	assert_eq(hands.size(), 1)
	assert_eq(hands[0]["slot"], "r_hand")
	assert_eq(hands[0]["kind"], PassiveSources.HAND_WEAPON)
	assert_eq(hands[0]["category"], 2)
	assert_eq(hands[0]["stats"]["ATK"], 15)


func test_a_shield_in_the_other_hand_is_not_empty() -> void:
	var loadout: Dictionary = PassiveSources.build_loadout([
		_equipment("r_hand", BROADSWORD), _equipment("l_hand", LEATHER_SHIELD),
	])
	assert_eq(loadout["weapon_count"], 1)
	assert_false(loadout["single_weapon"], "no true doublehand with a shield")
	assert_false(loadout["single_one_handed"], "no doublehand with a shield")
	assert_false(loadout["dual_wielding"])
	assert_false(loadout["unarmed"])
	assert_eq(loadout["hands"][1]["kind"], PassiveSources.HAND_SHIELD)


func test_a_two_handed_weapon_counts_as_a_single_weapon() -> void:
	var loadout: Dictionary = PassiveSources.build_loadout([_equipment("r_hand", KATAR)])
	assert_true(loadout["single_weapon"], "true doublehand works with two-handed weapons")
	assert_true(loadout["two_handed"])
	assert_false(loadout["single_one_handed"], "doublehand needs a one-handed weapon")


func test_the_right_hand_comes_first() -> void:
	# A dual wielder swings with the right hand first, whatever order the save keeps.
	var loadout: Dictionary = PassiveSources.build_loadout([
		_equipment("l_hand", MYTHRIL_SWORD), _equipment("body", BRAVE_SUIT), _equipment("r_hand", BROADSWORD),
	])
	var slots: Array = []
	for hand in loadout["hands"]:
		slots.append(hand["slot"])
	assert_eq(slots, ["r_hand", "l_hand"])


func test_two_weapons_are_dual_wielding() -> void:
	var loadout: Dictionary = PassiveSources.build_loadout([
		_equipment("r_hand", BROADSWORD), _equipment("l_hand", MYTHRIL_SWORD),
	])
	assert_eq(loadout["weapon_count"], 2)
	assert_true(loadout["dual_wielding"])
	assert_false(loadout["single_weapon"])
	assert_eq(loadout["stats"]["ATK"], 41)


func test_hands_carry_their_ailment_inflicts() -> void:
	var loadout: Dictionary = PassiveSources.build_loadout([
		_equipment("r_hand", SLEEP_DAGGER), _equipment("l_hand", LEATHER_SHIELD),
	])
	assert_eq(loadout["hands"][0]["inflicts"], [0, 0, 30, 0, 0, 0, 0, 0], "sleep is the third slot")
	assert_eq(loadout["hands"][1]["inflicts"], [0, 0, 0, 0, 0, 0, 0, 0], "a shield inflicts nothing")


func test_no_weapon_is_unarmed() -> void:
	var empty: Dictionary = PassiveSources.build_loadout([])
	assert_true(empty["unarmed"])
	assert_false(empty["single_weapon"])
	assert_false(empty["single_one_handed"])
	assert_eq(empty["hands"], [])
	var shield_only: Dictionary = PassiveSources.build_loadout([_equipment("l_hand", LEATHER_SHIELD)])
	assert_true(shield_only["unarmed"], "a shield is not a weapon")
	assert_false(shield_only["single_weapon"])


## Every conditioned passive in the data decodes, names items that exist, and can be met
## with something this game has (types 21 and 22).
func test_every_passive_equip_condition_resolves() -> void:
	var rows: Array = GameDatabase.query(
		"SELECT abilityId, equipCondition FROM ability"
		+ " WHERE abilityType = 1 AND equipCondition IS NOT NULL AND equipCondition != ''")
	assert_eq(rows.size(), 1044)
	var problems: PackedStringArray = []
	var unknown_types: Dictionary = {}
	for row in rows:
		var skill_id: String = str(row["abilityId"])
		var can_be_met: bool = false
		for alternative in PassiveSources.decode_equip_condition(str(row["equipCondition"])):
			var item_id: int = int(alternative["id"])
			match str(alternative["kind"]):
				PassiveSources.KIND_EQUIPMENT:
					if GameDatabase.get_equipment(item_id).is_empty():
						problems.append("%s: equipment %d does not exist" % [skill_id, item_id])
					can_be_met = true
				PassiveSources.KIND_MATERIA:
					if GameDatabase.get_materia(item_id).is_empty():
						problems.append("%s: materia %d does not exist" % [skill_id, item_id])
					can_be_met = true
				_:
					unknown_types[int(alternative["type"])] = true
		if not can_be_met:
			problems.append("%s: no alternative can be equipped" % skill_id)
	assert_eq(Array(problems), [])
	assert_eq(unknown_types.keys(), [27], "the only unknown type")
