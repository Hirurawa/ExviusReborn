extends "res://tests/test_case.gd"

## DamageFormula terms, one at a time.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var rules: BattleRules
var rng: RandomNumberGenerator


func before_each() -> void:
	rules = Fixtures.rules()
	rng = RandomNumberGenerator.new()
	rng.seed = 1


func _compute(attacker: Combatant, target: Combatant, kind: int, modifier: float, elements: Array = [], magic_modifier: float = 1.0) -> DamageFormula.Roll:
	var req: DamageFormula.Request = DamageFormula.request(attacker, target, kind, modifier, PackedInt32Array(elements))
	req.magic_modifier = magic_modifier
	return DamageFormula.compute(req, rules, rng)


func test_physical_is_atk_squared_over_def_times_modifier() -> void:
	var attacker: Combatant = Fixtures.unit("A", {"atk": 300})
	var target: Combatant = Fixtures.monster("T", {"def": 150})
	var roll: DamageFormula.Roll = _compute(attacker, target, DamageFormula.Kind.PHYSICAL, 2.5)
	assert_almost_eq(roll.stat_term, 600.0, 0.0001)
	assert_almost_eq(roll.amount, 1500.0, 0.0001)


func test_magic_is_mag_squared_over_spr_times_modifier() -> void:
	var attacker: Combatant = Fixtures.unit("A", {"mag": 200})
	var target: Combatant = Fixtures.monster("T", {"spr": 80})
	assert_almost_eq(_compute(attacker, target, DamageFormula.Kind.MAGIC, 1.5).amount, 750.0, 0.0001)


func test_hybrid_averages_both_parts_with_their_own_modifiers() -> void:
	var attacker: Combatant = Fixtures.unit("A", {"atk": 300, "mag": 200})
	var target: Combatant = Fixtures.monster("T", {"def": 150, "spr": 100})
	# (600 x 1.0 + 400 x 2.0) / 2
	assert_almost_eq(_compute(attacker, target, DamageFormula.Kind.HYBRID, 1.0, [], 2.0).amount, 700.0, 0.0001)


func test_zero_defense_counts_as_one() -> void:
	var attacker: Combatant = Fixtures.unit("A", {"atk": 10})
	var target: Combatant = Fixtures.monster("T", {"def": 0})
	assert_almost_eq(_compute(attacker, target, DamageFormula.Kind.PHYSICAL, 1.0).amount, 100.0, 0.0001)


func test_element_multiplier_uses_the_mean_resistance() -> void:
	var target: Combatant = Fixtures.monster("T", {"element_resist": {"FIRE": -50, "ICE": 50, "DARK": 150}})
	assert_almost_eq(DamageFormula.element_multiplier(target, PackedInt32Array()), 1.0, 0.0001, "non-elemental")
	assert_almost_eq(DamageFormula.element_multiplier(target, PackedInt32Array([1])), 1.5, 0.0001, "fire weakness")
	assert_almost_eq(DamageFormula.element_multiplier(target, PackedInt32Array([2])), 0.5, 0.0001, "ice resistance")
	assert_almost_eq(DamageFormula.element_multiplier(target, PackedInt32Array([1, 2])), 1.0, 0.0001, "mean of -50 and 50")


func test_resistance_above_100_counts_as_100() -> void:
	# Above 100 is headroom against imperils (120 imperiled by 70 is 50), not absorption.
	var target: Combatant = Fixtures.monster("T", {"element_resist": {"FIRE": -50, "DARK": 150}})
	assert_almost_eq(DamageFormula.element_multiplier(target, PackedInt32Array([8])), 0.0, 0.0001, "no damage, no healing")
	assert_almost_eq(DamageFormula.element_multiplier(target, PackedInt32Array([1, 8])), 0.75, 0.0001,
		"capped per element before the mean: (-50 + 100) / 2")


func test_element_ids_map_to_the_datamine_order() -> void:
	assert_eq(DamageFormula.element_name(3), "LIGHTNING")
	assert_eq(DamageFormula.element_name(4), "WATER")
	assert_eq(DamageFormula.element_name(8), "DARK")
	assert_eq(DamageFormula.element_name(9), "")


func test_elements_apply_to_the_amount() -> void:
	var attacker: Combatant = Fixtures.unit("A", {"mag": 100})
	var target: Combatant = Fixtures.monster("T", {"spr": 100, "element_resist": {"FIRE": -50}})
	assert_almost_eq(_compute(attacker, target, DamageFormula.Kind.MAGIC, 1.5, [1]).amount, 225.0, 0.0001)


func test_default_rules_follow_the_wiki() -> void:
	var defaults := BattleRules.new()
	assert_almost_eq(defaults.damage_variance_min, 0.85, 0.0)
	assert_almost_eq(defaults.damage_variance_max, 1.0, 0.0)
	assert_true(defaults.level_correction)
	assert_true(defaults.weapon_variance)


func test_variance_rolls_whole_hundredths_and_is_seeded() -> void:
	var attacker: Combatant = Fixtures.unit("A")
	var target: Combatant = Fixtures.monster("T")
	assert_almost_eq(_compute(attacker, target, DamageFormula.Kind.PHYSICAL, 1.0).variance, 1.0, 0.0, "off in the fixture rules")

	rules.damage_variance_min = 0.85
	rules.damage_variance_max = 1.0
	var seen: Dictionary = {}
	var off_step: int = 0
	var off_amount: int = 0
	for _i in range(400):
		var roll: DamageFormula.Roll = _compute(attacker, target, DamageFormula.Kind.PHYSICAL, 1.0)
		var hundredths: int = roundi(roll.variance * 100.0)
		if absf(roll.variance * 100.0 - float(hundredths)) > 0.0001:
			off_step += 1
		if absf(roll.amount - 100.0 * roll.variance) > 0.0001:
			off_amount += 1
		seen[hundredths] = true
	assert_eq(off_step, 0, "every roll is a whole hundredth")
	assert_eq(off_amount, 0, "the amount is the stat term times the roll")
	var values: Array = seen.keys()
	values.sort()
	assert_eq(values, range(85, 101), "the 16 values from 0.85 to 1.00 all come up")

	var first := RandomNumberGenerator.new()
	first.seed = 99
	var second := RandomNumberGenerator.new()
	second.seed = 99
	var req: DamageFormula.Request = DamageFormula.request(attacker, target, DamageFormula.Kind.PHYSICAL, 1.0)
	var roll_a: DamageFormula.Roll = DamageFormula.compute(req, rules, first)
	var roll_b: DamageFormula.Roll = DamageFormula.compute(req, rules, second)
	assert_true(roll_a.variance >= 0.85 and roll_a.variance <= 1.0, "variance in range")
	assert_almost_eq(roll_a.amount, roll_b.amount, 0.0, "same seed, same roll")


func test_weapon_variance_rolls_whole_percents_in_the_weapons_range() -> void:
	var attacker: Combatant = Fixtures.unit("A", {"weapon_variance": [110, 120]})
	var target: Combatant = Fixtures.monster("T")
	assert_almost_eq(_compute(attacker, target, DamageFormula.Kind.PHYSICAL, 1.0).weapon_variance, 1.0, 0.0, "off in the fixture rules")

	rules.weapon_variance = true
	var seen: Dictionary = {}
	var off_step: int = 0
	var off_amount: int = 0
	for _i in range(300):
		var roll: DamageFormula.Roll = _compute(attacker, target, DamageFormula.Kind.PHYSICAL, 1.0)
		var percent: int = roundi(roll.weapon_variance * 100.0)
		if absf(roll.weapon_variance * 100.0 - float(percent)) > 0.0001:
			off_step += 1
		if absf(roll.amount - 100.0 * roll.weapon_variance) > 0.0001:
			off_amount += 1
		seen[percent] = true
	assert_eq(off_step, 0, "every roll is a whole percent")
	assert_eq(off_amount, 0, "the amount is the stat term times the roll")
	var values: Array = seen.keys()
	values.sort()
	assert_eq(values, range(110, 121), "the 11 values from 110% to 120% all come up")


func test_weapon_variance_stacks_with_the_final_variance() -> void:
	rules.weapon_variance = true
	rules.damage_variance_min = 0.85
	rules.damage_variance_max = 1.0
	var attacker: Combatant = Fixtures.unit("A", {"weapon_variance": [125, 175]})
	var target: Combatant = Fixtures.monster("T")
	for _i in range(50):
		var roll: DamageFormula.Roll = _compute(attacker, target, DamageFormula.Kind.PHYSICAL, 1.0)
		assert_true(roll.weapon_variance >= 1.25 and roll.weapon_variance <= 1.75, "weapon variance in range")
		assert_almost_eq(roll.amount, 100.0 * roll.weapon_variance * roll.variance, 0.0001, "both multiply")


func test_equal_weapon_variance_bounds_skip_the_roll() -> void:
	# Fists (claws) are 115,115 in the data.
	rules.weapon_variance = true
	var attacker: Combatant = Fixtures.unit("A", {"weapon_variance": [115, 115]})
	var target: Combatant = Fixtures.monster("T")
	var state_before: int = rng.state
	var roll: DamageFormula.Roll = _compute(attacker, target, DamageFormula.Kind.PHYSICAL, 1.0)
	assert_almost_eq(roll.weapon_variance, 1.15, 0.0)
	assert_almost_eq(roll.amount, 115.0, 0.0001)
	assert_eq(rng.state, state_before, "no random number used")


func test_no_weapon_means_no_weapon_variance() -> void:
	rules.weapon_variance = true
	var unarmed: Combatant = Fixtures.unit("A")
	var foe: Combatant = Fixtures.monster("T")
	assert_almost_eq(_compute(unarmed, foe, DamageFormula.Kind.PHYSICAL, 1.0).weapon_variance, 1.0, 0.0, "unarmed")
	assert_almost_eq(_compute(foe, unarmed, DamageFormula.Kind.PHYSICAL, 1.0).weapon_variance, 1.0, 0.0, "enemies have no weapons")


func test_weapon_variance_applies_to_every_formula_kind() -> void:
	# The user's rule (2026-10-02): every stat-based hit, magic and evoke damage included.
	rules.weapon_variance = true
	var attacker: Combatant = Fixtures.unit("A", {"weapon_variance": [150, 150]})
	var target: Combatant = Fixtures.monster("T")
	for kind in [DamageFormula.Kind.PHYSICAL, DamageFormula.Kind.MAGIC, DamageFormula.Kind.HYBRID,
			DamageFormula.Kind.DEF_BASED, DamageFormula.Kind.SPR_BASED, DamageFormula.Kind.EVOKE]:
		assert_almost_eq(_compute(attacker, target, kind, 1.0).amount, 150.0, 0.0001, "kind %d" % kind)


func test_level_correction_adds_one_percent_per_level_on_both_sides() -> void:
	rules.level_correction = true
	var hero: Combatant = Fixtures.unit("Hero", {"level": 99})
	var foe: Combatant = Fixtures.monster("Foe", {"level": 50})
	var roll: DamageFormula.Roll = _compute(hero, foe, DamageFormula.Kind.PHYSICAL, 1.0)
	assert_almost_eq(roll.level_correction, 1.99, 0.0001)
	assert_almost_eq(roll.amount, 199.0, 0.0001, "100 x 1.99")
	assert_almost_eq(_compute(foe, hero, DamageFormula.Kind.MAGIC, 1.0).amount, 150.0, 0.0001, "an enemy's level counts too")
	assert_almost_eq(_compute(hero, foe, DamageFormula.Kind.HYBRID, 1.0).amount, 199.0, 0.0001, "hybrid")

	rules.level_correction = false
	assert_almost_eq(_compute(hero, foe, DamageFormula.Kind.PHYSICAL, 1.0).amount, 100.0, 0.0001, "rule off")


# --- Passive battle modifiers (PASSIVES-HANDOVER.md phase 3) ---

## A roll's amount with the boost-relevant request fields set.
func _boosted(attacker: Combatant, target: Combatant, kind: int, skill_ids: Array = [], opcode: int = 0, limit_burst: bool = false) -> float:
	var req: DamageFormula.Request = DamageFormula.request(attacker, target, kind, 1.0)
	req.skill_ids = PackedStringArray(skill_ids)
	req.opcode = opcode
	req.is_limit_burst = limit_burst
	req.magic_modifier = 1.0
	return DamageFormula.compute(req, rules, rng).amount


func test_passive_killers_count_against_their_race() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {"killers": {"physical:7": 50}}})
	var dragon: Combatant = Fixtures.monster("Dragon", {"races": [7]})
	var human: Combatant = Fixtures.monster("Human", {"races": [5]})
	assert_almost_eq(_compute(hero, dragon, DamageFormula.Kind.PHYSICAL, 1.0).amount, 150.0, 0.0001)
	assert_almost_eq(_compute(hero, human, DamageFormula.Kind.PHYSICAL, 1.0).amount, 100.0, 0.0001)
	assert_almost_eq(_compute(hero, dragon, DamageFormula.Kind.MAGIC, 1.0).amount, 100.0, 0.0001, "physical killers only")


func test_passive_killers_cap_at_300_per_race_before_the_average() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {"killers": {"physical:7": 400, "physical:4": 100}}})
	var dragon: Combatant = Fixtures.monster("Dragon", {"races": [7]})
	var dragon_demon: Combatant = Fixtures.monster("Dragon demon", {"races": [7, 4]})
	assert_almost_eq(_compute(hero, dragon, DamageFormula.Kind.PHYSICAL, 1.0).killer_multiplier, 4.0, 0.0001, "400% counts as 300%")
	assert_almost_eq(_compute(hero, dragon_demon, DamageFormula.Kind.PHYSICAL, 1.0).killer_multiplier, 3.0, 0.0001,
		"(300 + 100) / 2, not (400 + 100) / 2")
	rules.passive_killer_cap_pct = 500
	assert_almost_eq(_compute(hero, dragon, DamageFormula.Kind.PHYSICAL, 1.0).killer_multiplier, 5.0, 0.0001, "the cap is a rule")


func test_a_killer_limit_raise_lifts_the_cap_for_its_race() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {
		"killers": {"physical:7": 400, "physical:2": 400}, "killer_cap_bonus": {"7": 20},
	}})
	var dragon: Combatant = Fixtures.monster("Dragon", {"races": [7]})
	var avian: Combatant = Fixtures.monster("Avian", {"races": [2]})
	assert_almost_eq(_compute(hero, dragon, DamageFormula.Kind.PHYSICAL, 1.0).killer_multiplier, 4.2, 0.0001, "cap 320")
	assert_almost_eq(_compute(hero, avian, DamageFormula.Kind.PHYSICAL, 1.0).killer_multiplier, 4.0, 0.0001, "other races keep 300")


func test_active_killers_go_on_top_of_the_capped_passive() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {"killers": {"physical:7": 400}}})
	hero.add_status(BattleStatus.make(BattleStatus.KILLER, "physical:7", 100, 3))
	var dragon: Combatant = Fixtures.monster("Dragon", {"races": [7]})
	assert_almost_eq(_compute(hero, dragon, DamageFormula.Kind.PHYSICAL, 1.0).killer_multiplier, 5.0, 0.0001, "300 + 100")


func test_hybrid_halves_take_their_own_passive_killers() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {"killers": {"physical:7": 100}}})
	var dragon: Combatant = Fixtures.monster("Dragon", {"races": [7]})
	# (100 x 2.0 + 100 x 1.0) / 2
	assert_almost_eq(_compute(hero, dragon, DamageFormula.Kind.HYBRID, 1.0).amount, 150.0, 0.0001)


func test_passive_lb_damage_adds_to_lb_buffs() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {"lb_damage_pct": 50}})
	hero.add_status(BattleStatus.make(BattleStatus.LB_BOOST, "", 20, 3))
	var foe: Combatant = Fixtures.monster("Foe")
	assert_almost_eq(_boosted(hero, foe, DamageFormula.Kind.PHYSICAL, [], 0, true), 170.0, 0.0001, "50% + 20% = 70%")
	assert_almost_eq(_boosted(hero, foe, DamageFormula.Kind.PHYSICAL), 100.0, 0.0001, "not a limit burst")


func test_passive_skill_boosts_add_to_skill_buffs() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {"skill_boosts": [
		{"skill_ids": ["777"], "opcodes": [], "damage_type": 0, "pct": 100},
		{"skill_ids": ["888"], "opcodes": [52], "damage_type": 0, "pct": 200},
	]}})
	hero.add_status(BattleStatus.make(BattleStatus.SKILL_BOOST, "7", 100, 3, {
		"skill_ids": PackedStringArray(["777"]), "opcodes": [],
	}))
	var foe: Combatant = Fixtures.monster("Foe")
	assert_almost_eq(_boosted(hero, foe, DamageFormula.Kind.PHYSICAL, ["777"]), 300.0, 0.0001, "100% passive + 100% buff")
	assert_almost_eq(_boosted(hero, foe, DamageFormula.Kind.PHYSICAL, ["778"]), 100.0, 0.0001, "another skill")
	assert_almost_eq(_boosted(hero, foe, DamageFormula.Kind.PHYSICAL, ["888"], 52), 300.0, 0.0001, "opcode filter holds")
	assert_almost_eq(_boosted(hero, foe, DamageFormula.Kind.PHYSICAL, ["888"], 1), 100.0, 0.0001, "opcode filter fails")


func test_a_damage_type_boost_covers_every_attack_of_that_type() -> void:
	var brawler: Combatant = Fixtures.unit("Brawler", {"passives": {"skill_boosts": [
		{"skill_ids": [], "opcodes": [], "damage_type": 1, "pct": 100},
	]}})
	var mage: Combatant = Fixtures.unit("Mage", {"passives": {"skill_boosts": [
		{"skill_ids": [], "opcodes": [], "damage_type": 2, "pct": 100},
	]}})
	var foe: Combatant = Fixtures.monster("Foe")
	assert_almost_eq(_boosted(brawler, foe, DamageFormula.Kind.PHYSICAL), 200.0, 0.0001, "any physical attack")
	assert_almost_eq(_boosted(brawler, foe, DamageFormula.Kind.DEF_BASED), 200.0, 0.0001, "DEF-based is physical")
	assert_almost_eq(_boosted(brawler, foe, DamageFormula.Kind.MAGIC), 100.0, 0.0001, "not magic")
	assert_almost_eq(_boosted(mage, foe, DamageFormula.Kind.MAGIC), 200.0, 0.0001, "any magic attack")
	assert_almost_eq(_boosted(mage, foe, DamageFormula.Kind.PHYSICAL), 100.0, 0.0001, "not physical")
	assert_almost_eq(_boosted(brawler, foe, DamageFormula.Kind.HYBRID), 200.0, 0.0001, "hybrid counts as both")


func test_a_damage_type_limits_listed_skills() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {"skill_boosts": [
		{"skill_ids": ["777"], "opcodes": [], "damage_type": 2, "pct": 100},
	]}})
	var foe: Combatant = Fixtures.monster("Foe")
	assert_almost_eq(_boosted(hero, foe, DamageFormula.Kind.MAGIC, ["777"]), 200.0, 0.0001)
	assert_almost_eq(_boosted(hero, foe, DamageFormula.Kind.PHYSICAL, ["777"]), 100.0, 0.0001, "the listed skill, but physical")
	assert_almost_eq(_boosted(hero, foe, DamageFormula.Kind.MAGIC, ["778"]), 100.0, 0.0001, "magic, but not listed")


func test_enemies_and_bare_units_have_no_passive_modifiers() -> void:
	var foe: Combatant = Fixtures.monster("Foe", {"races": [5]})
	var hero: Combatant = Fixtures.unit("Hero", {"races": [5]})
	assert_true(foe.passives.is_empty())
	assert_true(hero.passives.is_empty())
	assert_almost_eq(_compute(foe, hero, DamageFormula.Kind.PHYSICAL, 1.0).amount, 100.0, 0.0001)
