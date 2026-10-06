extends "res://tests/test_case.gd"

## EquipmentValidator's hand rules with real units and items, through check_hands, which
## takes resolved items so no account or inventory state is needed. Reads GameDatabase;
## writes nothing.

## Rena 6* has no dual wield until her second awakening (recipes 225590001, 225590002),
## which grants it for any one-handed weapons.
const RENA: String = "317000106"
const RENA_AWAKENINGS: Array = [225590001, 225590002]

const MECH_DAGGER: int = 301002800  # dagger, fire
const LIGHTNING_DAGGER: int = 301003400  # dagger, lightning
const BOWIE_KNIFE: int = 301001700  # dagger that grants dual wield (any weapons)
const AQUA_BLADE: int = 302002800  # sword that grants dual wield of swords
const BROADSWORD: int = 302000100  # sword
const RAS_ALGETHI: int = 313001600  # two-handed gun
const LEATHER_SHIELD: int = 401001000
const ESCUTCHEON: int = 401002200  # shield
const GENJI_GLOVE: int = 409008100  # accessory: dual wield (any)
const MOBIUS_RING: int = 409031400  # accessory: dual wield (any)
const CLAN_MASTERS_HEADBAND: int = 409015000  # accessory: dual wield of katanas
const DUAL_WIELD_MATERIA: int = 504101370
const TWIN_SWORD_USER: int = 504237887  # materia: dual wield of swords and katanas


## The login screen loads the opcode schemas in the game; without them no passive parses.
func before_each() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()


static func _unit(awakened: Array = []) -> Dictionary:
	var unit: Dictionary = GameDatabase.get_unit(int(RENA)).duplicate()
	unit.merge({
		"instance_id": "validator_test_%s" % RENA,
		"unit_id": RENA,
		"level": 1,
		"current_rarity": int(unit.get("rare", 1)),
		"equipment": {},
		"awakened_abilities": awakened,
	}, true)
	return unit


static func _item(slot: String, template_id: int) -> Dictionary:
	return StatCalculator.resolve_item(slot, str(template_id))


## check_hands for putting `template_id` (0 to take the slot's item off) into `slot` of
## the unit wearing `worn` ([[slot, template id], ...]): [reason, unequip].
static func _hands(unit: Dictionary, worn: Array, slot: String, template_id: int) -> Array:
	var items: Array = []
	for pair in worn:
		items.append(_item(pair[0], pair[1]))
	var incoming: Dictionary = _item(slot, template_id) if template_id != 0 else {}
	var result: Dictionary = EquipmentValidator.check_hands(unit, items, slot, incoming)
	return [result["reason"], Array(result["unequip"])]


## _hands's result for a change that goes through and takes nothing else off.
const OK: Array = ["", []]


func test_a_second_weapon_needs_a_dual_wield_permit() -> void:
	var worn: Array = [["r_hand", MECH_DAGGER]]
	assert_eq(_hands(_unit(), worn, "l_hand", LIGHTNING_DAGGER), [EquipmentValidator.ERR_DUAL_WIELD_REQUIRED, []])
	assert_eq(_hands(_unit(RENA_AWAKENINGS), worn, "l_hand", LIGHTNING_DAGGER), OK, "the awakened trait permits it")


func test_a_weapon_and_a_shield_need_no_permit() -> void:
	assert_eq(_hands(_unit(), [["r_hand", MECH_DAGGER]], "l_hand", LEATHER_SHIELD), OK)
	assert_eq(_hands(_unit(), [["l_hand", LEATHER_SHIELD]], "r_hand", MECH_DAGGER), OK)


func test_a_weapon_can_grant_its_own_permit() -> void:
	assert_eq(_hands(_unit(), [["r_hand", MECH_DAGGER]], "l_hand", BOWIE_KNIFE), OK, "Bowie Knife comes in")
	assert_eq(_hands(_unit(), [["r_hand", BOWIE_KNIFE]], "l_hand", MECH_DAGGER), OK, "Bowie Knife already in")


func test_accessories_and_materia_permit_dual_wield() -> void:
	assert_eq(_hands(_unit(), [["acc_1", GENJI_GLOVE], ["r_hand", MECH_DAGGER]], "l_hand", LIGHTNING_DAGGER), OK)
	assert_eq(_hands(_unit(), [["ability_1", DUAL_WIELD_MATERIA], ["r_hand", MECH_DAGGER]], "l_hand", LIGHTNING_DAGGER), OK)


func test_a_permit_for_some_weapon_types_needs_both_weapons_of_them() -> void:
	assert_eq(_hands(_unit(), [["r_hand", BROADSWORD]], "l_hand", AQUA_BLADE), OK, "two swords with Aqua Blade")
	assert_eq(_hands(_unit(), [["r_hand", MECH_DAGGER]], "l_hand", AQUA_BLADE), [EquipmentValidator.ERR_DUAL_WIELD_REQUIRED, []],
		"Aqua Blade does not permit a dagger")
	assert_eq(_hands(_unit(), [["ability_1", TWIN_SWORD_USER], ["r_hand", BROADSWORD]], "l_hand", AQUA_BLADE), OK)
	assert_eq(_hands(_unit(), [["acc_1", CLAN_MASTERS_HEADBAND], ["r_hand", MECH_DAGGER]], "l_hand", LIGHTNING_DAGGER),
		[EquipmentValidator.ERR_DUAL_WIELD_REQUIRED, []], "katanas only")


func test_two_shields_never_go_together() -> void:
	var dual: Dictionary = _unit(RENA_AWAKENINGS)
	assert_eq(_hands(dual, [["r_hand", LEATHER_SHIELD]], "l_hand", ESCUTCHEON), [EquipmentValidator.ERR_TWO_SHIELDS, []])
	assert_eq(_hands(dual, [["l_hand", ESCUTCHEON]], "r_hand", LEATHER_SHIELD), [EquipmentValidator.ERR_TWO_SHIELDS, []])
	assert_eq(_hands(dual, [["r_hand", LEATHER_SHIELD]], "r_hand", ESCUTCHEON), OK, "a shield replacing a shield")


func test_a_two_handed_weapon_takes_both_hands() -> void:
	var dual: Dictionary = _unit(RENA_AWAKENINGS)
	assert_eq(_hands(dual, [["r_hand", MECH_DAGGER]], "l_hand", RAS_ALGETHI), [EquipmentValidator.ERR_OK, ["r_hand"]],
		"the other hand's weapon comes off")
	assert_eq(_hands(dual, [["l_hand", LEATHER_SHIELD]], "r_hand", RAS_ALGETHI), [EquipmentValidator.ERR_OK, ["l_hand"]])
	assert_eq(_hands(dual, [["r_hand", RAS_ALGETHI]], "l_hand", MECH_DAGGER), [EquipmentValidator.ERR_TWO_HANDED_LOCKED, []],
		"dual wield does not reach two-handed weapons")
	assert_eq(_hands(dual, [["r_hand", RAS_ALGETHI]], "l_hand", LEATHER_SHIELD), [EquipmentValidator.ERR_TWO_HANDED_LOCKED, []])


func test_swapping_out_the_weapon_that_permits_dual_wield_takes_the_other_weapon_off() -> void:
	var worn: Array = [["r_hand", BOWIE_KNIFE], ["l_hand", MECH_DAGGER]]
	assert_eq(_hands(_unit(), worn, "r_hand", LIGHTNING_DAGGER), [EquipmentValidator.ERR_OK, ["l_hand"]])
	assert_eq(_hands(_unit(), [["r_hand", MECH_DAGGER], ["l_hand", BOWIE_KNIFE]], "l_hand", LIGHTNING_DAGGER),
		[EquipmentValidator.ERR_OK, ["r_hand"]], "the other hand, whichever it is")
	assert_eq(_hands(_unit(), worn, "r_hand", BOWIE_KNIFE), OK, "the same weapon again")


func test_taking_off_the_weapon_that_permits_dual_wield_leaves_one_weapon() -> void:
	assert_eq(_hands(_unit(), [["r_hand", BOWIE_KNIFE], ["l_hand", MECH_DAGGER]], "r_hand", 0), OK)


func test_swapping_a_weapon_the_permit_does_not_cover_takes_the_other_weapon_off() -> void:
	var worn: Array = [["ability_1", TWIN_SWORD_USER], ["r_hand", BROADSWORD], ["l_hand", AQUA_BLADE]]
	assert_eq(_hands(_unit(), worn, "r_hand", MECH_DAGGER), [EquipmentValidator.ERR_OK, ["l_hand"]],
		"swords and katanas only")


func test_taking_off_the_permit_takes_the_left_weapon_off() -> void:
	var gloved: Array = [["acc_1", GENJI_GLOVE], ["r_hand", MECH_DAGGER], ["l_hand", LIGHTNING_DAGGER]]
	assert_eq(_hands(_unit(), gloved, "acc_1", 0), [EquipmentValidator.ERR_OK, ["l_hand"]], "Genji Glove taken off")
	assert_eq(_hands(_unit(), gloved, "acc_1", CLAN_MASTERS_HEADBAND), [EquipmentValidator.ERR_OK, ["l_hand"]],
		"replaced by a katana-only permit")
	assert_eq(_hands(_unit(), gloved, "acc_1", MOBIUS_RING), OK, "replaced by another permit")
	var materia: Array = [["ability_1", DUAL_WIELD_MATERIA], ["r_hand", MECH_DAGGER], ["l_hand", LIGHTNING_DAGGER]]
	assert_eq(_hands(_unit(), materia, "ability_1", 0), [EquipmentValidator.ERR_OK, ["l_hand"]], "the materia taken off")


func test_a_change_that_keeps_a_permit_takes_nothing_off() -> void:
	var gloved: Array = [["acc_1", GENJI_GLOVE], ["r_hand", MECH_DAGGER], ["l_hand", LIGHTNING_DAGGER]]
	assert_eq(_hands(_unit(RENA_AWAKENINGS), gloved, "acc_1", 0), OK, "her trait still permits it")
	assert_eq(_hands(_unit(), gloved, "acc_2", MOBIUS_RING), OK, "an unrelated slot")
	assert_eq(_hands(_unit(), gloved, "l_hand", 0), OK, "a weapon taken off")


func test_the_permits_are_read_with_the_change_made() -> void:
	var items: Array = [_item("r_hand", MECH_DAGGER), _item("l_hand", BOWIE_KNIFE)]
	var with_bowie: Dictionary = EquipmentValidator.dual_wield_permits(_unit(), items)
	assert_true(bool(with_bowie["has"]) and bool(with_bowie["allows_any"]))
	var with_aqua: Dictionary = EquipmentValidator.dual_wield_permits(_unit(), [_item("l_hand", AQUA_BLADE)])
	assert_true(bool(with_aqua["has"]) and not bool(with_aqua["allows_any"]))
	assert_eq(with_aqua["type_ids"], [2], "swords")
	assert_false(bool(EquipmentValidator.dual_wield_permits(_unit(), [_item("r_hand", MECH_DAGGER)])["has"]))
