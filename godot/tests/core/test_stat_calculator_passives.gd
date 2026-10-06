extends "res://tests/test_case.gd"

## Which passives StatCalculator counts: equip conditions, esper board passives, and the
## shared collection EquipmentValidator reads. Uses real units and items through
## calculate_unit_profile, which takes resolved equipment and esper, so no account state
## is needed. Reads GameDatabase; writes nothing.

## Ramza 7*: at level 101 he has "Rallied Courage", +15% HP, MP, DEF and SPR with
## Brave Suit or Escutcheon (FFT).
const RAMZA: String = "253000107"
const RALLIED_COURAGE: String = "226690"
const BRAVE_SUIT: int = 405001700  # its own passives are ATK +15% and MAG +15%
const ESCUTCHEON: int = 401002200  # its own passive is HP +15%
## Golem's rank 3 board node 60060 unlocks "DEF +10%".
const GOLEM: String = "6"
const GOLEM_DEF_NODE_SKILL: String = "100130"
## Rena 6* learns "Martial Arts Knowledge"; its second awakening (recipes 225590001 and
## 225590002) adds dual wield.
const RENA: String = "317000106"
const RENA_AWAKENINGS: Array = [225590001, 225590002]
## Supreme Deva Akstar 5* has "Katana Mastery", +50% ATK, DEF, MAG and SPR with a katana.
const AKSTAR: String = "100027405"
const KOTETSU: int = 304000100  # katana, ATK 25, no passives
const BROADSWORD: int = 302000100  # sword, ATK 15, no passives
## Selphie 5* has "GF", +50% to the stats any esper gives; Edea 6* has "GF -Alexander-",
## +50% with Alexander (13) only.
const SELPHIE: String = "208000505"
const EDEA: String = "208001306"
const ALEXANDER: String = "13"
## Dark Knight Luneth 5* has "True Doublehand" (50%, either kind of weapon); Tessen 5*
## at level 24 has "Doublehand" (50%, a one-handed weapon only).
const LUNETH: String = "203001405"
const TESSEN: String = "100023505"
const MYTHRIL_SWORD: int = 302000700  # one-handed, ATK 26
const RAS_ALGETHI: int = 313001600  # two-handed gun, ATK 52, no passives
const LEATHER_SHIELD: int = 401001000


## The login screen loads the opcode schemas in the game; without them no passive parses.
func before_each() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()


static func _unit(unit_id: String, level: int, awakened: Array = []) -> Dictionary:
	var unit: Dictionary = GameDatabase.get_unit(int(unit_id)).duplicate()
	unit.merge({
		"instance_id": "passive_test_%s" % unit_id,
		"unit_id": unit_id,
		"level": level,
		"current_rarity": int(unit.get("rare", 1)),
		"equipment": {},
		"awakened_abilities": awakened,
	}, true)
	return unit


static func _equipment(slot: String, template_id: int) -> Dictionary:
	return {
		"slot": slot, "kind": PassiveSources.KIND_EQUIPMENT, "id": template_id,
		"data": GameDatabase.get_equipment(template_id),
	}


static func _passive_entry(profile: Dictionary, skill_id: String) -> Dictionary:
	for entry in profile["skills"]["passive"]:
		if str(entry.get("id")) == skill_id:
			return entry
	return {}


func test_a_conditional_passive_needs_its_item() -> void:
	var ramza: Dictionary = _unit(RAMZA, 101)
	var bare: Dictionary = StatCalculator.calculate_unit_profile(ramza, [], {})
	var suited: Dictionary = StatCalculator.calculate_unit_profile(ramza, [_equipment("body", BRAVE_SUIT)], {})
	var base_hp: float = float(bare["base_stats"]["HP"])

	assert_false(bool(_passive_entry(bare, RALLIED_COURAGE).get("active", true)), "listed but inactive without the item")
	assert_true(bool(_passive_entry(suited, RALLIED_COURAGE).get("active", false)), "active with Brave Suit")
	# Brave Suit has no HP of its own, so the whole difference is Rallied Courage's 15%.
	assert_almost_eq(float(suited["stats"]["HP"] - bare["stats"]["HP"]), base_hp * 0.15, 1.0, "HP +15%")


func test_either_item_of_a_condition_switches_it_on() -> void:
	var ramza: Dictionary = _unit(RAMZA, 101)
	var bare: Dictionary = StatCalculator.calculate_unit_profile(ramza, [], {})
	var shielded: Dictionary = StatCalculator.calculate_unit_profile(ramza, [_equipment("l_hand", ESCUTCHEON)], {})
	assert_true(bool(_passive_entry(shielded, RALLIED_COURAGE).get("active", false)), "active with Escutcheon (FFT)")
	# The shield's own HP +15% and Rallied Courage's 15% add up.
	assert_almost_eq(float(shielded["stats"]["HP"] - bare["stats"]["HP"]), float(bare["base_stats"]["HP"]) * 0.30, 1.0)


func test_inactive_passives_leave_passive_effects_out() -> void:
	var ramza: Dictionary = _unit(RAMZA, 101)
	var bare: Dictionary = StatCalculator.calculate_unit_profile(ramza, [], {})
	var suited: Dictionary = StatCalculator.calculate_unit_profile(ramza, [_equipment("body", BRAVE_SUIT)], {})
	# Rallied Courage adds one effect, and Brave Suit's two passives one each.
	assert_eq(suited["passive_effects"].size() - bare["passive_effects"].size(), 3)


func test_the_profile_carries_the_loadout() -> void:
	var profile: Dictionary = StatCalculator.calculate_unit_profile(
		_unit(RAMZA, 101), [_equipment("body", BRAVE_SUIT)], {})
	assert_eq(profile["loadout"]["item_ids"], [BRAVE_SUIT])
	assert_true(profile["loadout"]["unarmed"])


func test_esper_board_passives_reach_the_profile() -> void:
	var ramza: Dictionary = _unit(RAMZA, 101)
	var golem: Dictionary = {"summon_id": GOLEM, "rank": 3, "level": 1, "unlocked_skills": [], "board_bonus": {}}
	var golem_def_node: Dictionary = golem.duplicate(true)
	golem_def_node["unlocked_skills"] = [GOLEM_DEF_NODE_SKILL]

	var without_node: Dictionary = StatCalculator.calculate_unit_profile(ramza, [], golem)
	var with_node: Dictionary = StatCalculator.calculate_unit_profile(ramza, [], golem_def_node)
	var entry: Dictionary = _passive_entry(with_node, GOLEM_DEF_NODE_SKILL)
	assert_eq(str(entry.get("source", "")), "Esper")
	assert_true(bool(entry.get("active", false)))
	assert_true(_passive_entry(without_node, GOLEM_DEF_NODE_SKILL).is_empty())
	assert_almost_eq(float(with_node["stats"]["DEF"] - without_node["stats"]["DEF"]),
		float(with_node["base_stats"]["DEF"]) * 0.10, 1.0, "DEF +10%")


func test_final_stats_without_equipment_or_party_match_the_unit_profile() -> void:
	var ramza: Dictionary = _unit(RAMZA, 101)
	var direct: Dictionary = StatCalculator.calculate_unit_profile(ramza, [], {})
	var through_services: Dictionary = StatCalculator.calculate_final_stats(ramza)
	assert_eq(through_services["stats"], direct["stats"])
	assert_eq(through_services["skills"]["passive"].size(), direct["skills"]["passive"].size())


func test_a_category_boost_needs_that_category() -> void:
	var akstar: Dictionary = _unit(AKSTAR, 1)
	var bare: Dictionary = StatCalculator.calculate_unit_profile(akstar, [], {})
	var katana: Dictionary = StatCalculator.calculate_unit_profile(akstar, [_equipment("r_hand", KOTETSU)], {})
	var sword: Dictionary = StatCalculator.calculate_unit_profile(akstar, [_equipment("r_hand", BROADSWORD)], {})
	var base_atk: float = float(bare["base_stats"]["ATK"])
	assert_almost_eq(float(katana["stats"]["ATK"] - bare["stats"]["ATK"]), base_atk * 0.5 + 25.0, 1.0,
		"Katana Mastery's 50% plus the katana's 25")
	assert_almost_eq(float(sword["stats"]["ATK"] - bare["stats"]["ATK"]), 15.0, 1.0, "only the sword's 15")


func test_the_equipment_and_esper_columns_hold_only_their_own_stats() -> void:
	var golem: Dictionary = {"summon_id": GOLEM, "rank": 3, "level": 60, "unlocked_skills": [], "board_bonus": {}}
	var profile: Dictionary = StatCalculator.calculate_unit_profile(_unit(RAMZA, 101), [_equipment("body", BRAVE_SUIT)], golem)
	assert_eq(profile["equipment_stats"], profile["loadout"]["stats"])
	assert_eq(profile["equipment_stats"]["DEF"], 51, "Brave Suit's DEF")
	assert_eq(profile["equipment_stats"]["HP"], 0, "no esper HP in the equipment column")
	assert_true(int(profile["esper_stats"]["HP"]) > 0, "Golem gives HP")


func test_an_esper_boost_scales_the_esper_share() -> void:
	var golem: Dictionary = {"summon_id": GOLEM, "rank": 3, "level": 60, "unlocked_skills": [], "board_bonus": {}}
	var share: Dictionary = StatCalculator._compute_esper_flat_bonus(golem)
	var selphie: Dictionary = StatCalculator.calculate_unit_profile(_unit(SELPHIE, 1), [], golem)
	for stat_name in ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]:
		assert_eq(selphie["esper_stats"][stat_name], floori(float(share[stat_name]) * 1.5), stat_name)


func test_an_esper_boost_that_names_an_esper_needs_that_esper() -> void:
	var golem: Dictionary = {"summon_id": GOLEM, "rank": 1, "level": 1, "unlocked_skills": [], "board_bonus": {}}
	var alexander: Dictionary = {"summon_id": ALEXANDER, "rank": 1, "level": 1, "unlocked_skills": [], "board_bonus": {}}
	var edea: Dictionary = _unit(EDEA, 1)
	var with_golem: Dictionary = StatCalculator.calculate_unit_profile(edea, [], golem)
	var with_alexander: Dictionary = StatCalculator.calculate_unit_profile(edea, [], alexander)
	assert_eq(with_golem["esper_stats"], StatCalculator._compute_esper_flat_bonus(golem), "no boost with Golem")
	var alexander_share: Dictionary = StatCalculator._compute_esper_flat_bonus(alexander)
	assert_eq(with_alexander["esper_stats"]["HP"], floori(float(alexander_share["HP"]) * 1.5), "boosted with Alexander")


func test_unhandled_passive_effects_are_kept_in_the_profile() -> void:
	var profile: Dictionary = StatCalculator.calculate_unit_profile(_unit(RAMZA, 101), [], {})
	var unconsumed: Array = profile["passives"]["unconsumed"]
	assert_true(unconsumed.size() > 0, "Ramza's kit has effects no handler reads yet")
	for entry in unconsumed:
		assert_false(PassiveAggregator.handles(str(entry["type"])), str(entry["type"]))
		assert_ne(str(entry["skill_id"]), "")


func test_battle_modifiers_go_to_the_profile() -> void:
	# Firion 3* has "Plant Killer": +50% physical damage against plants (race 11).
	var profile: Dictionary = StatCalculator.calculate_unit_profile(_unit("202000103", 1), [], {})
	assert_eq(profile["passives"]["killers"], {"physical:11": 50})
	assert_eq(profile["passives"]["killer_cap_bonus"], {})
	assert_eq(profile["passives"]["lb_damage_pct"], 0)


func test_equipment_stat_boosts_cap_at_400() -> void:
	var stats: Dictionary = {"HP": 0, "MP": 0, "ATK": 100, "DEF": 15, "MAG": 0, "SPR": 0}
	var bonus: Dictionary = StatCalculator.equipment_stat_bonus(stats, {"ATK": 500, "DEF": 50})
	assert_eq(bonus["ATK"], 400, "500% counts as 400%")
	assert_eq(bonus["DEF"], 8, "15 x 50% rounds to 8")
	assert_eq(bonus["MAG"], 0)


func test_true_doublehand_boosts_the_equipment_with_either_weapon() -> void:
	var luneth: Dictionary = _unit(LUNETH, 1)
	var sword: Dictionary = StatCalculator.calculate_unit_profile(luneth, [_equipment("r_hand", MYTHRIL_SWORD)], {})
	var great: Dictionary = StatCalculator.calculate_unit_profile(luneth, [_equipment("r_hand", RAS_ALGETHI)], {})
	var shielded: Dictionary = StatCalculator.calculate_unit_profile(luneth,
		[_equipment("r_hand", MYTHRIL_SWORD), _equipment("l_hand", LEATHER_SHIELD)], {})
	var bare: Dictionary = StatCalculator.calculate_unit_profile(luneth, [], {})
	assert_eq(sword["equipment_bonus"]["ATK"], 13, "26 x 50%")
	assert_eq(great["equipment_bonus"]["ATK"], 26, "52 x 50%, two-handed")
	assert_eq(shielded["equipment_bonus"]["ATK"], 0, "a shield in the other hand")
	assert_eq(great["stats"]["ATK"] - bare["stats"]["ATK"], 78, "the gun's 52 and the 26 bonus")
	assert_eq(great["equipment_stats"]["ATK"], 52, "the equipment column keeps the item's own stat")


func test_doublehand_needs_a_one_handed_weapon() -> void:
	var tessen: Dictionary = _unit(TESSEN, 24)
	var sword: Dictionary = StatCalculator.calculate_unit_profile(tessen, [_equipment("r_hand", MYTHRIL_SWORD)], {})
	var great: Dictionary = StatCalculator.calculate_unit_profile(tessen, [_equipment("r_hand", RAS_ALGETHI)], {})
	assert_eq(sword["equipment_bonus"]["ATK"], 13)
	assert_eq(great["equipment_bonus"]["ATK"], 0, "not with a two-handed weapon")


func test_a_clothes_only_attack_replacement_needs_clothes() -> void:
	# Vermilion Blade Ardyn 7*: "Burning Passion for Vengeance" changes the normal attack
	# to ability 514068 when equipped with clothes (Brave Suit is clothes, 50).
	var ardyn: Dictionary = _unit("215003007", 1)
	var dressed: Dictionary = StatCalculator.calculate_unit_profile(ardyn, [_equipment("body", BRAVE_SUIT)], {})
	var bare: Dictionary = StatCalculator.calculate_unit_profile(ardyn, [], {})
	assert_eq(dressed["passives"]["attack_replace_id"], "514068")
	assert_eq(bare["passives"]["attack_replace_id"], "")


func test_dual_wield_from_an_awakened_trait_is_seen_by_the_validator() -> void:
	var before: Dictionary = EquipmentValidator.get_dual_wield_allowed_type_ids(_unit(RENA, 1))
	assert_false(bool(before["has"]), "no dual wield before the awakening")
	var after: Dictionary = EquipmentValidator.get_dual_wield_allowed_type_ids(_unit(RENA, 1, RENA_AWAKENINGS))
	assert_true(bool(after["has"]), "the awakened trait grants dual wield")
	assert_true(bool(after["allows_any"]), "with any one-handed weapons")
