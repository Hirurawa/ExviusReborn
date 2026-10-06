extends "res://tests/test_case.gd"

## PassiveAggregator with hand-written effects and loadouts (no DB), plus one sweep over
## every passive in the DB to catch keys the handlers do not read. How the engine uses
## the battle modifiers is in tests/battle/test_damage_formula.gd.

const KATANA: int = 4
const SWORD: int = 2
const AXE: int = 8
const SHIELD: int = 30
const FIRE: int = 1
const LIGHTNING: int = 3
const STAFF: int = 5
## Handled-type keys nothing reads on purpose: crits and accuracy are not in the engine
## yet (the user, 2026-09-30).
const KNOWN_UNREAD: Array = ["STAT_BOOST_PCT.crit_rate", "EQUIPMENT_ATK.accuracy", "EQUIPMENT_MAG.accuracy"]


## A parsed passive as OpcodeParser.parse_passive gives it, from one source.
static func _source(effects: Array, skill_id: String = "900001", source: String = "Trait") -> Dictionary:
	return {"skill_id": skill_id, "source": source, "effects": effects}


static func _effect(effect_type: String, opcode: int, payload: Dictionary) -> Dictionary:
	return {"type": effect_type, "opcode": opcode, "effect": payload}


## An equipped item record shaped like GameDatabase.get_equipment's.
static func _item(slot: String, item_id: int, category: int, slot_name: String = "Weapon", elements: Array = [], two_handed: bool = false) -> Dictionary:
	return {
		"slot": slot, "kind": PassiveSources.KIND_EQUIPMENT, "id": item_id,
		"data": {"type_id": category, "slot": slot_name, "is_twohanded": two_handed, "stats": {"ATK": 10, "element_inflict": elements}},
	}


## The equipment-stat percent a list of effects gives with the loadout.
static func _equipment_pct(effects: Array, items: Array, stat_name: String) -> int:
	return int(PassiveAggregator.aggregate([_source(effects)], _loadout(items), {})["equipment_stat_pct"][stat_name])


static func _loadout(items: Array = []) -> Dictionary:
	return PassiveSources.build_loadout(items)


func test_stat_boosts_and_fixed_stats_sum_over_sources() -> void:
	var boost: Dictionary = _effect("STAT_BOOST_PCT", 1, {"ATK": 20, "HP": 10})
	var totals: Dictionary = PassiveAggregator.aggregate([
		_source([boost], "100070"),
		_source([boost], "100070", "Equip"),
		_source([_effect("FIX_STAT", 89, {"atk": 50})]),
	], _loadout(), {})
	assert_eq(totals["stat_pct"]["ATK"], 40, "the same passive twice counts twice")
	assert_eq(totals["stat_pct"]["HP"], 20)
	assert_eq(totals["stat_flat"]["ATK"], 50)
	assert_eq(totals["stat_pct"]["MAG"], 0)
	assert_eq(totals["unconsumed"], [])


func test_element_and_status_resistances() -> void:
	var totals: Dictionary = PassiveAggregator.aggregate([_source([
		_effect("ELEMENT_RESIST", 3, {"fire": 30, "dark": 10}),
		_effect("STATUS_RESIST", 2, {"paralysis": 100, "poison": 50}),
	])], _loadout(), {})
	assert_eq(totals["element_resist"]["FIRE"], 30)
	assert_eq(totals["element_resist"]["DARK"], 10)
	assert_eq(totals["status_resist"]["PARALYSIS"], 100)
	assert_eq(totals["status_resist"]["POISON"], 50)


func test_break_stop_and_charm_resistance() -> void:
	var totals: Dictionary = PassiveAggregator.aggregate([_source([
		_effect("SPECIAL_STATUS_RESIST", 55, {"atk_break": 50, "stop": 100, "charm": 30}),
	])], _loadout(), {})
	assert_eq(totals["debuff_resist"], {"ATK": 50, "DEF": 0, "MAG": 0, "SPR": 0, "STOP": 100, "CHARM": 30})


func test_a_category_boost_needs_that_category_equipped() -> void:
	var mastery: Array = [_source([_effect("EQUIP_CONDITIONAL_BOOST", 6, {"equip_id": KATANA, "ATK": 50, "DEF": 50})])]
	var with_katana: Dictionary = PassiveAggregator.aggregate(mastery, _loadout([_item("r_hand", 1, KATANA)]), {})
	var with_sword: Dictionary = PassiveAggregator.aggregate(mastery, _loadout([_item("r_hand", 2, SWORD)]), {})
	assert_eq(with_katana["stat_pct"]["ATK"], 50)
	assert_eq(with_katana["stat_pct"]["DEF"], 50)
	assert_eq(with_sword["stat_pct"]["ATK"], 0)
	assert_eq(with_sword["unconsumed"], [], "a failed condition is handled, not unconsumed")


func test_a_set_boost_needs_any_one_of_its_items() -> void:
	var set_boost: Array = [_source([_effect("EQUIP_SET_BOOST", 74, {"equip_ids": [111, 222], "SPR": 10})])]
	var single: Array = [_source([_effect("EQUIP_SET_BOOST", 74, {"equip_ids": 333, "ATK": 5})])]
	var loadout: Dictionary = _loadout([_item("head", 222, 40, "Headgear"), _item("body", 333, 50, "Chest")])
	assert_eq(PassiveAggregator.aggregate(set_boost, loadout, {})["stat_pct"]["SPR"], 10, "one listed item is enough")
	assert_eq(PassiveAggregator.aggregate(single, loadout, {})["stat_pct"]["ATK"], 5, "a single id")
	assert_eq(PassiveAggregator.aggregate(set_boost, _loadout([_item("head", 999, 40, "Headgear")]), {})["stat_pct"]["SPR"], 0)


func test_an_equipment_element_resist_needs_its_category() -> void:
	var axe_fire: Array = [_source([_effect("WEAPON_ELEMENT_RESIST", 76, {"equip_type": AXE, "fire": 50})])]
	assert_eq(PassiveAggregator.aggregate(axe_fire, _loadout([_item("r_hand", 1, AXE)]), {})["element_resist"]["FIRE"], 50)
	assert_eq(PassiveAggregator.aggregate(axe_fire, _loadout([_item("r_hand", 1, SWORD)]), {})["element_resist"]["FIRE"], 0)


func test_an_element_weapon_boost_needs_a_weapon_of_that_element() -> void:
	var lightning_might: Array = [_source([_effect("ELEMENT_WEAPON_STAT_BOOST", 10004, {"element": LIGHTNING, "ATK": 80})])]
	var lightning_sword: Dictionary = _loadout([_item("r_hand", 1, SWORD, "Weapon", [LIGHTNING])])
	var fire_sword: Dictionary = _loadout([_item("r_hand", 1, SWORD, "Weapon", [FIRE])])
	var lightning_shield: Dictionary = _loadout([_item("l_hand", 2, SHIELD, "Shield", [LIGHTNING])])
	assert_eq(PassiveAggregator.aggregate(lightning_might, lightning_sword, {})["stat_pct"]["ATK"], 80)
	assert_eq(PassiveAggregator.aggregate(lightning_might, fire_sword, {})["stat_pct"]["ATK"], 0)
	assert_eq(PassiveAggregator.aggregate(lightning_might, lightning_shield, {})["stat_pct"]["ATK"], 0, "a shield is not a weapon")
	assert_eq(PassiveAggregator.aggregate(lightning_might, _loadout(), {})["stat_pct"]["ATK"], 0)


func test_an_esper_boost_needs_an_esper_and_the_named_one() -> void:
	var any_esper: Array = [_source([_effect("ESPER_STAT", 63, {"atk": 50, "hp": 50})])]
	var alexander_only: Array = [_source([_effect("ESPER_STAT", 63, {"atk": 50, "esper_id": 13})])]
	var golem: Dictionary = {"summon_id": "6"}
	var alexander: Dictionary = {"summon_id": "13"}
	assert_eq(PassiveAggregator.aggregate(any_esper, _loadout(), golem)["esper_stat_pct"]["ATK"], 50)
	assert_eq(PassiveAggregator.aggregate(any_esper, _loadout(), golem)["esper_stat_pct"]["HP"], 50)
	assert_eq(PassiveAggregator.aggregate(any_esper, _loadout(), {})["esper_stat_pct"]["ATK"], 0, "no esper")
	assert_eq(PassiveAggregator.aggregate(alexander_only, _loadout(), alexander)["esper_stat_pct"]["ATK"], 50)
	assert_eq(PassiveAggregator.aggregate(alexander_only, _loadout(), golem)["esper_stat_pct"]["ATK"], 0, "another esper")


func test_unhandled_effects_are_kept_with_their_source() -> void:
	var guts: Dictionary = _effect("FATAL_PREVENT", 51, {"hp_threshold": 30, "pct": 100, "times": 1})
	var totals: Dictionary = PassiveAggregator.aggregate([_source([guts], "200010", "Esper")], _loadout(), {})
	assert_eq(totals["unconsumed"], [{
		"type": "FATAL_PREVENT", "opcode": 51, "effect": {"hp_threshold": 30, "pct": 100, "times": 1},
		"skill_id": "200010", "source": "Esper",
	}])


func test_killers_sum_per_race_over_sources() -> void:
	var dragon: Dictionary = _effect("KILLER", 11, {"race_id": 7, "phys_pct": 50, "mag_pct": 25})
	var totals: Dictionary = PassiveAggregator.aggregate([_source([dragon]), _source([dragon], "900002", "Equip")], _loadout(), {})
	assert_eq(totals["killers"], {"physical:7": 100, "magic:7": 50}, "uncapped sums")
	assert_eq(totals["unconsumed"], [])


func test_killer_lists_run_in_parallel_and_a_single_percent_covers_every_race() -> void:
	var pair: Dictionary = _effect("KILLER", 11, {"race_id": [4, 10], "phys_pct": [75, 50]})
	var shared: Dictionary = _effect("KILLER", 11, {"race_id": [5, 8], "phys_pct": 25, "mag_pct": [10, 20]})
	var totals: Dictionary = PassiveAggregator.aggregate([_source([pair, shared])], _loadout(), {})
	assert_eq(totals["killers"], {
		"physical:4": 75, "physical:10": 50, "physical:5": 25, "physical:8": 25, "magic:5": 10, "magic:8": 20,
	})


func test_an_equipment_killer_needs_its_category() -> void:
	var collector: Array = [_source([_effect("EQUIP_CONDITIONAL_KILLER", 75, {"equip_type": [3, 4], "race_id": 1, "phys_pct": 100, "mag_pct": 100})])]
	var with_katana: Dictionary = PassiveAggregator.aggregate(collector, _loadout([_item("r_hand", 1, KATANA)]), {})
	var with_sword: Dictionary = PassiveAggregator.aggregate(collector, _loadout([_item("r_hand", 1, SWORD)]), {})
	assert_eq(with_katana["killers"], {"physical:1": 100, "magic:1": 100}, "a katana is one of the listed categories")
	assert_eq(with_sword["killers"], {})


func test_a_killer_limit_boost_raises_the_cap_and_the_killers() -> void:
	var avian: Dictionary = _effect("KILLER_LIMIT_BOOST", 105, {"race_id": 2, "pct": 10})
	var totals: Dictionary = PassiveAggregator.aggregate([_source([avian])], _loadout(), {})
	assert_eq(totals["killer_cap_bonus"], {"2": 10})
	assert_eq(totals["killers"], {"physical:2": 10, "magic:2": 10})


func test_lb_damage_sums() -> void:
	var lb: Dictionary = _effect("LB_DAMAGE", 68, {"pct": 50})
	assert_eq(PassiveAggregator.aggregate([_source([lb, lb])], _loadout(), {})["lb_damage_pct"], 100)


func test_evo_mag_and_the_evoke_boost_naming_no_esper_sum() -> void:
	var evo: Dictionary = _effect("ESPER_DAMAGE", 21, {"pct": 50})
	var boost: Dictionary = _effect("EVOKE_DAMAGE_BOOST", 64, {"pct": 100, "esper_id": 0})
	var bare: Dictionary = _effect("EVOKE_DAMAGE_BOOST", 64, {"pct": 25})
	var for_bahamut: Dictionary = _effect("EVOKE_DAMAGE_BOOST", 64, {"pct": 75, "esper_id": 15})
	var totals: Dictionary = PassiveAggregator.aggregate([_source([evo, evo, boost, bare, for_bahamut])], _loadout(), {})
	assert_eq(totals["evo_mag_pct"], 100)
	assert_eq(totals["evoke_damage_pct"], 125, "the wiki: a boost that names an esper is not this multiplier")
	assert_eq(totals["unconsumed"], [])


func test_jump_damage_sums_without_a_cap() -> void:
	var high_jump: Dictionary = _effect("JUMP", 17, {"pct": 100})
	var high_jump_iii: Dictionary = _effect("JUMP", 17, {"pct": 400})
	var totals: Dictionary = PassiveAggregator.aggregate([_source([high_jump]), _source([high_jump_iii, high_jump_iii])], _loadout(), {})
	assert_eq(totals["jump_damage_pct"], 900, "the wiki: additive; DamageFormula caps it at 800")
	assert_eq(totals["unconsumed"], [])


func test_skill_boosts_keep_their_ids_filters_and_damage_type() -> void:
	var listed: Dictionary = _effect("SKILL_DAMAGE_BOOST", 73, {"skill_ids": [202120, 700070], "pct": 300})
	var single: Dictionary = _effect("SKILL_DAMAGE_BOOST", 73, {"skill_ids": 205530, "opcode_filter": [52, 134], "pct": 100})
	var physical: Dictionary = _effect("SKILL_DAMAGE_BOOST", 73, {"damage_type": 1, "pct": 500})
	var nothing: Dictionary = _effect("SKILL_DAMAGE_BOOST", 73, {"skill_ids": 1})
	var totals: Dictionary = PassiveAggregator.aggregate([_source([listed, single, physical, nothing])], _loadout(), {})
	assert_eq(totals["skill_boosts"], [
		{"skill_ids": ["202120", "700070"], "opcodes": [], "damage_type": 0, "pct": 300},
		{"skill_ids": ["205530"], "opcodes": [52, 134], "damage_type": 0, "pct": 100},
		{"skill_ids": [], "opcodes": [], "damage_type": 1, "pct": 500},
	], "a boost without a percent is dropped")


func test_keys_no_pool_reads_are_ignored_and_reported() -> void:
	var crit: Dictionary = _effect("STAT_BOOST_PCT", 1, {"ATK": 20, "crit_rate": 40})
	var totals: Dictionary = PassiveAggregator.aggregate([_source([crit])], _loadout(), {})
	assert_eq(totals["stat_pct"]["ATK"], 20)
	assert_eq(Array(PassiveAggregator.ignored_keys("STAT_BOOST_PCT", crit["effect"])), ["crit_rate"])
	assert_eq(Array(PassiveAggregator.ignored_keys("EQUIP_CONDITIONAL_BOOST", {"equip_id": 4, "ATK": 50})), [],
		"the condition's param is read")
	assert_eq(Array(PassiveAggregator.ignored_keys("KILLER", {"race_id": 7, "phys_pct": 50, "slot_9": 1})), ["slot_9"],
		"a handler reads only its listed params")
	assert_eq(Array(PassiveAggregator.ignored_keys("FATAL_PREVENT", {"pct": 100})), [], "unhandled types report nothing")


func test_values_that_are_not_numbers_add_nothing() -> void:
	var odd: Dictionary = _effect("STAT_BOOST_PCT", 1, {"ATK": [10, 20], "DEF": "none", "MAG": 15})
	var totals: Dictionary = PassiveAggregator.aggregate([_source([odd])], _loadout(), {})
	assert_eq(totals["stat_pct"]["ATK"], 0)
	assert_eq(totals["stat_pct"]["DEF"], 0)
	assert_eq(totals["stat_pct"]["MAG"], 15)


func test_doublehand_needs_one_one_handed_weapon_and_an_empty_hand() -> void:
	var doublehand: Array = [_effect("EQUIPMENT_ATK", 13, {"pct": 50, "accuracy": 25})]  # wield_mode 0, dropped
	assert_eq(_equipment_pct(doublehand, [_item("r_hand", 1, SWORD)], "ATK"), 50)
	assert_eq(_equipment_pct(doublehand, [_item("r_hand", 1, SWORD, "Weapon", [], true)], "ATK"), 0, "not a two-handed weapon")
	assert_eq(_equipment_pct(doublehand, [_item("r_hand", 1, SWORD), _item("l_hand", 2, SHIELD, "Shield")], "ATK"), 0, "a shield")
	assert_eq(_equipment_pct(doublehand, [_item("r_hand", 1, SWORD), _item("l_hand", 2, KATANA)], "ATK"), 0, "two weapons")
	assert_eq(_equipment_pct(doublehand, [], "ATK"), 0, "unarmed")


func test_true_doublehand_takes_either_kind_of_weapon() -> void:
	var true_doublehand: Array = [_effect("EQUIPMENT_MAG", 70, {"pct": 100, "wield_mode": 2})]
	assert_eq(_equipment_pct(true_doublehand, [_item("r_hand", 1, STAFF)], "MAG"), 100)
	assert_eq(_equipment_pct(true_doublehand, [_item("r_hand", 1, STAFF, "Weapon", [], true)], "MAG"), 100, "two-handed")
	assert_eq(_equipment_pct(true_doublehand, [_item("r_hand", 1, STAFF), _item("l_hand", 2, SHIELD, "Shield")], "MAG"), 0, "a shield")
	assert_eq(_equipment_pct(true_doublehand, [_item("r_hand", 1, STAFF)], "ATK"), 0, "70 boosts MAG only")


func test_the_six_stat_single_wield_boost_reads_its_mode() -> void:
	var both_hands: Array = [_effect("EQUIP_STATS_SINGLE_WEAPON", 10003, {"MAG": 50, "SPR": 25, "wield_mode": 1})]
	var one_handed: Array = [_effect("EQUIP_STATS_SINGLE_WEAPON", 10003, {"MAG": 100})]
	var great_staff: Array = [_item("r_hand", 1, STAFF, "Weapon", [], true)]
	assert_eq(_equipment_pct(both_hands, great_staff, "MAG"), 50)
	assert_eq(_equipment_pct(both_hands, great_staff, "SPR"), 25)
	assert_eq(_equipment_pct(one_handed, great_staff, "MAG"), 0, "six params: one-handed only")
	assert_eq(_equipment_pct(one_handed, [_item("r_hand", 1, STAFF)], "MAG"), 100)


func test_true_dual_wield_needs_two_weapons() -> void:
	var dual: Array = [_effect("DUAL_WIELD_EQUIPMENT_STAT", 69, {"stat_id": 3, "pct": 50})]
	var two: Array = [_item("r_hand", 1, SWORD), _item("l_hand", 2, SWORD)]
	assert_eq(_equipment_pct(dual, two, "MAG"), 50, "stat id 3 is MAG")
	assert_eq(_equipment_pct(dual, [_item("r_hand", 1, SWORD)], "MAG"), 0)


func test_a_single_weapon_boost_needs_one_weapon_of_its_types() -> void:
	var staff_only: Array = [_effect("EQUIP_STAT_SINGLE_WEAPON", 99, {"stat_id": 4, "pct": 50, "weapon_types": STAFF})]
	var any_weapon: Array = [_effect("EQUIP_STAT_SINGLE_WEAPON", 99, {"stat_id": 1, "pct": 100, "weapon_types": [1, 2, 3, 4, 5]})]
	var no_list: Array = [_effect("EQUIP_STAT_SINGLE_WEAPON", 99, {"stat_id": 2, "pct": 100})]
	assert_eq(_equipment_pct(staff_only, [_item("r_hand", 1, STAFF)], "SPR"), 50, "stat id 4 is SPR")
	assert_eq(_equipment_pct(staff_only, [_item("r_hand", 1, STAFF, "Weapon", [], true)], "SPR"), 50, "two-handed too")
	assert_eq(_equipment_pct(staff_only, [_item("r_hand", 1, SWORD)], "SPR"), 0, "another type")
	assert_eq(_equipment_pct(staff_only, [_item("r_hand", 1, STAFF), _item("l_hand", 2, SHIELD, "Shield")], "SPR"), 0, "a shield")
	assert_eq(_equipment_pct(staff_only, [_item("r_hand", 1, STAFF), _item("l_hand", 2, STAFF)], "SPR"), 0, "two weapons")
	assert_eq(_equipment_pct(any_weapon, [_item("r_hand", 1, SWORD)], "ATK"), 100)
	assert_eq(_equipment_pct(no_list, [_item("r_hand", 1, SWORD)], "DEF"), 100, "no list means any weapon")


func test_the_unarmed_boost_needs_empty_hands() -> void:
	var brawl: Array = [_effect("UNARMED_ATK", 19, {"pct": 200})]
	assert_eq(_equipment_pct(brawl, [], "ATK"), 200)
	assert_eq(_equipment_pct(brawl, [_item("body", 5, 50, "Chest")], "ATK"), 200, "armor does not count")
	assert_eq(_equipment_pct(brawl, [_item("r_hand", 1, SWORD)], "ATK"), 0)


func test_equipment_stat_boosts_share_one_pool() -> void:
	var boosts: Array = [
		_effect("EQUIPMENT_ATK", 13, {"pct": 150}),
		_effect("EQUIPMENT_ATK", 13, {"pct": 150, "wield_mode": 2}),
		_effect("EQUIP_STAT_SINGLE_WEAPON", 99, {"stat_id": 1, "pct": 200}),
	]
	assert_eq(_equipment_pct(boosts, [_item("r_hand", 1, SWORD)], "ATK"), 500, "summed; StatCalculator caps it")
	assert_eq(Array(PassiveAggregator.ignored_keys("EQUIPMENT_ATK", {"pct": 50, "accuracy": 25, "wield_mode": 2})), ["accuracy"])


func test_chain_cap_passives_sum_and_the_dual_wield_ones_need_two_weapons() -> void:
	var limits: Array = [
		_effect("CHAIN_DAMAGE_LIMIT_BOOST", 98, {"pct": 100}),
		_effect("CHAIN_DAMAGE_LIMIT_BOOST", 98, {"pct": 50}),
	]
	var dual: Array = [_effect("DUAL_WIELD_CHAIN_LIMIT", 81, {}), _effect("DUAL_WIELD_CHAIN_LIMIT_FIXED", 106, {})]
	var two_swords: Dictionary = _loadout([_item("r_hand", 1, SWORD), _item("l_hand", 2, SWORD)])
	var one_sword: Dictionary = _loadout([_item("r_hand", 1, SWORD)])
	assert_eq(PassiveAggregator.aggregate([_source(limits)], one_sword, {})["chain_cap_raise"], 150, "98's percent is the raise")
	assert_eq(PassiveAggregator.aggregate([_source(dual)], two_swords, {})["chain_cap_raise"], 400,
		"200 each; ChainTracker stops the cap at the ceiling")
	assert_eq(PassiveAggregator.aggregate([_source(dual)], one_sword, {})["chain_cap_raise"], 0, "not dual wielding")


func test_a_chain_boost_counts_once_per_skill() -> void:
	var master: Array = [_effect("CHAIN_DAMAGE_BOOST", 84, {"pct": 100}), _effect("CHAIN_DAMAGE_BOOST_2", 85, {"pct": 100})]
	var only_85: Array = [_effect("CHAIN_DAMAGE_BOOST_2", 85, {"pct": 150})]
	assert_eq(PassiveAggregator.aggregate([_source(master)], _loadout(), {})["chain_boost_pct"], 100, "84 and 85 are one boost")
	assert_eq(PassiveAggregator.aggregate([_source(master), _source(only_85, "900002")], _loadout(), {})["chain_boost_pct"], 250,
		"two skills add up")


func test_gauge_evasion_aggro_and_cost_passives_sum() -> void:
	var effects: Array = [
		_effect("LB_FILLRATE", 31, {"pct": 100}),
		_effect("MP_PER_TURN", 32, {"pct": 5}),
		_effect("MP_PER_TURN", 32, {"pct": 3}),
		_effect("LB_GAUGE_INCREASE", 33, {"amount": 200}),
		_effect("EVASION", 22, {"pct": 30}),
		_effect("EVASION", 22, {"pct": 20}),
		_effect("MAGIC_EVASION", 54, {"pct": 25}),
		_effect("AGGRO_INCREASE", 24, {"pct": 50}),
		_effect("AGGRO_DECREASE", 25, {"pct": 70}),
		_effect("MP_REDUCTION", 77, {"pct": 30}),
	]
	var totals: Dictionary = PassiveAggregator.aggregate([_source(effects)], _loadout(), {})
	assert_eq(totals["lb_fill_rate_pct"], 100)
	assert_eq(totals["mp_regen_pct"], 8)
	assert_eq(totals["lb_per_turn"], 200)
	assert_eq(totals["evade_physical_pct"], 50, "evasion adds up")
	assert_eq(totals["evade_magic_pct"], 25)
	assert_eq(totals["aggro_pct"], -20, "50 up, 70 down")
	assert_eq(totals["ability_mp_cut_pct"], 30)
	assert_eq(totals["unconsumed"], [])


func test_an_lb_change_keeps_the_last_limit_burst() -> void:
	var first: Dictionary = _effect("LB_CHANGE", 72, {"lb_id": 900000498})
	var second: Dictionary = _effect("LB_CHANGE", 72, {"lb_id": 900000499})
	assert_eq(PassiveAggregator.aggregate([_source([first])], _loadout(), {})["lb_change_id"], "900000498")
	assert_eq(PassiveAggregator.aggregate([_source([first]), _source([second])], _loadout(), {})["lb_change_id"], "900000499")
	assert_eq(PassiveAggregator.aggregate([], _loadout(), {})["lb_change_id"], "")


func test_a_normal_attack_replacement_and_its_equipment_condition() -> void:
	var plain: Array = [_source([_effect("NORMAL_ATTACK_REPLACE", 100, {"skill_id": 514832})])]
	var clothes_only: Array = [_source([_effect("NORMAL_ATTACK_REPLACE", 100, {"skill_id": 514068, "equip_type": 50})])]
	assert_eq(PassiveAggregator.aggregate(plain, _loadout(), {})["attack_replace_id"], "514832", "no restriction")
	assert_eq(PassiveAggregator.aggregate(clothes_only, _loadout([_item("body", 5, 50, "Chest")]), {})["attack_replace_id"], "514068",
		"with clothes")
	assert_eq(PassiveAggregator.aggregate(clothes_only, _loadout([_item("body", 5, 52, "Chest")]), {})["attack_replace_id"], "",
		"heavy armor is not clothes")


func test_multicast_passives_give_their_commands_once_each() -> void:
	var steal_chance: Dictionary = _effect("MULTICAST_SKILLS", 53, {"cast_count": 2, "skill_id": 503330, "skill_ids": [200010, 200020]})
	var dual_white: Dictionary = _effect("MULTICAST", 52, {"magic_type": 2, "cast_amount": 2, "ability_id": 502090})
	var totals: Dictionary = PassiveAggregator.aggregate([_source([steal_chance]), _source([dual_white]), _source([steal_chance])], _loadout(), {})
	assert_eq(totals["multicast_commands"], ["503330", "502090"])
	assert_eq(totals["multicast_picks"], {
		"503330": {"count": 2, "skill_ids": ["200010", "200020"]},
		"502090": {"count": 2, "skill_ids": []},
	})
	assert_eq(totals["unconsumed"], [])
	assert_eq(PassiveAggregator.ignored_keys("MULTICAST_SKILLS", steal_chance["effect"]), PackedStringArray())
	var passives: CombatantPassives = CombatantPassives.from_profile(totals)
	assert_eq(passives.multicast_commands, PackedStringArray(["503330", "502090"]))
	assert_eq(passives.multicast_picks["503330"], {"count": 2, "skill_ids": PackedStringArray(["200010", "200020"])})
	assert_false(passives.is_empty())


func test_two_passives_naming_one_command_keep_the_larger_count_and_both_lists() -> void:
	var first: Dictionary = _effect("MULTICAST_SKILLS", 53, {"cast_count": 2, "skill_id": 600, "skill_ids": [1, 2]})
	var second: Dictionary = _effect("MULTICAST_SKILLS", 53, {"cast_count": 3, "skill_id": 600, "skill_ids": 3})
	var totals: Dictionary = PassiveAggregator.aggregate([_source([first]), _source([second])], _loadout(), {})
	assert_eq(totals["multicast_commands"], ["600"])
	assert_eq(totals["multicast_picks"], {"600": {"count": 3, "skill_ids": ["1", "2", "3"]}})


## The real Steal Chance passive (217440) gives the Steal Chance command (503330).
func test_the_database_passive_53_names_its_command() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	var effects: Array = SkillResolver.parse_passive_effects(GameDatabase.get_passive(217440)).get("effects", [])
	var totals: Dictionary = PassiveAggregator.aggregate([{"skill_id": "217440", "source": "Trait", "effects": effects}], _loadout(), {})
	assert_eq(totals["multicast_commands"], ["503330"])


## Where a passive and the active it names disagree, the passive decides: Triple
## Strongest Attack's active (509704) says 2 casts, its passive (230784) 3; Dual Martial
## Arts' active (506090) does not list All-out Scuffle +1 (707576), its passive (223580)
## does.
func test_the_database_passive_decides_what_its_command_picks() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	var catalog: SkillCatalog = DatabaseSkillCatalog.new()
	for case in [["230784", "509704"], ["223580", "506090"]]:
		var effects: Array = SkillResolver.parse_passive_effects(GameDatabase.get_passive(int(case[0]))).get("effects", [])
		var totals: Dictionary = PassiveAggregator.aggregate([{"skill_id": case[0], "source": "Trait", "effects": effects}], _loadout(), {})
		assert_eq(totals["multicast_commands"], [case[1]])
	var strongest: BattleSkill = catalog.get_skill(BattleSkill.KIND_ABILITY, "509704")
	assert_eq(Multicast.rule_for(strongest).count, 2, "the active's own record")
	var strongest_picks: Dictionary = _picks_of("230784", "509704")
	assert_eq(Multicast.rule_for(strongest, strongest_picks).count, 3, "the passive's count")
	var martial: BattleSkill = catalog.get_skill(BattleSkill.KIND_ABILITY, "506090")
	var scuffle_plus: BattleSkill = catalog.get_skill(BattleSkill.KIND_ABILITY, "707576")
	assert_false(Multicast.allows(Multicast.rule_for(martial), scuffle_plus), "missing from the active's list")
	assert_true(Multicast.allows(Multicast.rule_for(martial, _picks_of("223580", "506090")), scuffle_plus), "in the passive's")


## multicast_picks of the database passive `passive_id` for `command_id`.
func _picks_of(passive_id: String, command_id: String) -> Dictionary:
	var effects: Array = SkillResolver.parse_passive_effects(GameDatabase.get_passive(int(passive_id))).get("effects", [])
	var totals: Dictionary = PassiveAggregator.aggregate([{"skill_id": passive_id, "source": "Trait", "effects": effects}], _loadout(), {})
	return CombatantPassives.from_profile(totals).multicast_picks.get(command_id, {})


func test_counter_passives_keep_their_trigger_answer_and_cap() -> void:
	var effects: Array = [
		_effect("COUNTER", 12, {"chance_pct": 30, "max": 5}),
		_effect("COUNTER_MAGIC_ATTACK", 41, {"chance_pct": 20, "modifier": 120, "max": 2}),
		_effect("PHYS_COUNTER_ABILITY", 49, {"chance_pct": 20, "cast_type": 1}),
		_effect("PHYS_COUNTER_ABILITY", 49, {"chance_pct": 45, "cast_type": 2, "skill_id": 91003}),
		_effect("MAG_COUNTER_ABILITY", 50, {"chance_pct": 30, "cast_type": 3, "skill_id": 500350, "max": 1}),
		_effect("MAG_COUNTER_ABILITY", 50, {"chance_pct": 30, "cast_type": 3}),
		_effect("COUNTER_CHANCE", 20, {"pct": 100}),
		_effect("COUNTER_CHANCE", 20, {"pct": 50}),
	]
	var totals: Dictionary = PassiveAggregator.aggregate([_source(effects, "910496")], _loadout(), {})
	var counters: Array = totals["counters"]
	assert_eq(counters.size(), 5, "an ability counter naming no ability is dropped")
	if counters.size() != 5:
		return
	assert_eq(counters[0], {
		"trigger": "physical", "chance": 30, "modifier": 0, "max": 5, "skill_kind": "attack", "skill_id": "", "source_skill_id": "910496",
	})
	assert_eq([counters[1]["trigger"], counters[1]["modifier"], counters[1]["max"], counters[1]["skill_kind"]], ["magic", 120, 2, "attack"])
	assert_eq([counters[2]["skill_kind"], counters[2]["skill_id"]], ["attack", ""], "cast type 1 is the normal attack")
	assert_eq([counters[3]["skill_kind"], counters[3]["skill_id"]], ["magic", "91003"], "cast type 2 is magic")
	assert_eq([counters[4]["trigger"], counters[4]["skill_kind"], counters[4]["skill_id"], counters[4]["max"]], ["magic", "ability", "500350", 1])
	assert_eq(totals["counter_chance_pct"], 150)
	assert_eq(totals["unconsumed"], [])
	var passives: CombatantPassives = CombatantPassives.from_profile(totals)
	assert_eq(passives.counters.size(), 5)
	assert_eq(passives.counters[3]["skill_kind"], BattleSkill.KIND_MAGIC)
	assert_eq(passives.counter_chance_pct, 150)
	assert_false(passives.is_empty())
	assert_has(passives.describe(), "Counter physical attacks 30%: attack, 5 per turn")


func test_auto_cast_passives_say_when_they_cast() -> void:
	var effects: Array = [
		_effect("BATTLE_START_CAST", 103, {"skill_id": 514923}),
		_effect("START_OF_BATTLE_OR_REVIVE", 35, {"ability_id": 10121}),
		_effect("REVIVE_AUTO_ABILITY", 56, {"ability_id": 508110}),
		_effect("TURN_START_CAST", 66, {"skill_id": 509443, "pct": 70}),
	]
	var casts: Array = PassiveAggregator.aggregate([_source(effects)], _loadout(), {})["auto_casts"]
	assert_eq(casts.map(func(cast: Dictionary) -> Array: return [cast["skill_kind"], cast["skill_id"], cast["battle_start"], cast["revive"], cast["turn_start"], cast["chance"]]), [
		["ability", "514923", true, false, false, 100],
		["magic", "10121", true, true, false, 100],
		["ability", "508110", true, true, false, 100],
		["ability", "509443", false, false, true, 70],
	])
	var passives: CombatantPassives = CombatantPassives.from_profile({"auto_casts": casts})
	assert_has(passives.describe(), "Casts ability:509443 at turn start 70%")
	assert_has(passives.describe(), "Casts magic:10121 at battle start and revive")


func test_passive_covers_keep_their_type_condition_and_hp_gate() -> void:
	var sentinel: Dictionary = _effect("INTERCEPT", 8, {"hp_below_pct": 100, "dmg_reduce_min": 50, "dmg_reduce_max": 70, "chance_pct": 30})
	var chivalry: Dictionary = _effect("INTERCEPT", 8, {"condition": 1, "hp_below_pct": 100, "chance_pct": 5})
	var scapegoat: Dictionary = _effect("INTERCEPT", 8, {"hp_below_pct": 30, "dmg_reduce_min": 70, "dmg_reduce_max": 70, "chance_pct": 30})
	var barrier: Dictionary = _effect("ST_MAGIC_COVER", 59, {"hp_below_pct": 100, "dmg_reduce_min": 50, "dmg_reduce_max": 50, "chance_pct": 40})
	var covers: Array = PassiveAggregator.aggregate([_source([sentinel, chivalry]), _source([scapegoat, barrier])], _loadout(), {})["covers"]
	assert_eq(covers.size(), 4)
	if covers.size() != 4:
		return
	assert_eq(covers[0], {"physical": true, "magic": false, "chance": 30, "mit_min": 50, "mit_max": 70, "condition": 0, "hp_below_pct": 100})
	assert_eq([covers[1]["condition"], covers[1]["mit_min"], covers[1]["chance"]], [1, 0, 5])
	assert_eq(covers[2]["hp_below_pct"], 30)
	assert_eq([covers[3]["physical"], covers[3]["magic"], covers[3]["chance"]], [false, true, 40])
	var gateless: Dictionary = _effect("INTERCEPT", 8, {"chance_pct": 50})
	assert_eq(PassiveAggregator.aggregate([_source([gateless])], _loadout(), {})["covers"][0]["hp_below_pct"], 100, "no gate")


## Every passive in the DB parses and aggregates without an error, and each effect of a
## handled type feeds its pool or handler with all its keys but KNOWN_UNREAD. A schema
## key that nothing reads (a rename, a typo) fails here.
func test_every_passive_in_the_data_aggregates() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	var rows: Array = GameDatabase.query("SELECT abilityId FROM ability WHERE abilityType = 1")
	assert_true(rows.size() > 15000)
	var unexpected: Dictionary = {}
	var handled_effects: int = 0
	for row in rows:
		var skill_id: String = str(row["abilityId"])
		var effects: Array = SkillResolver.parse_passive_effects(GameDatabase.get_passive(skill_id)).get("effects", [])
		for effect in effects:
			var effect_type: String = str(effect["type"])
			if not PassiveAggregator.handles(effect_type):
				continue
			handled_effects += 1
			for key in PassiveAggregator.ignored_keys(effect_type, effect["effect"]):
				var name: String = "%s.%s" % [effect_type, key]
				if not KNOWN_UNREAD.has(name):
					unexpected[name] = skill_id
		PassiveAggregator.aggregate([_source(effects, skill_id)], _loadout(), {})
	assert_true(handled_effects > 10000, "handled effects: %d" % handled_effects)
	assert_eq(unexpected, {}, "keys no pool reads, with an example skill")
