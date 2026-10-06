extends "res://tests/test_case.gd"

## BattleBuilder against the real database: the test battle, StatCalculator profiles,
## monster parts and AI, a mission formation, and a full battle on real data. Reads
## GameDatabase; writes no save.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

const ZU_ID: String = "302001000"
const GREAT_WHIRLWIND_ID: String = "150350"
const SLEEP_DAGGER: int = 301000600  # 30% sleep
const LOCKES_DAGGER: int = 301004600  # 50% sleep
const MECH_DAGGER: int = 301002800  # 30% poison, 30% paralysis; fire; ATK 85
const LIGHTNING_DAGGER: int = 301003400  # lightning; ATK 20
const LEATHER_SHIELD: int = 401001000
const BROADSWORD: int = 302000100  # one-handed sword, variance 105,125
const KATAR: int = 301008300  # two-handed dagger, variance 145,165
const DUAL_FORM: int = 504230370  # materia: equipment ATK +100% while dual wielding


func _builder() -> BattleBuilder:
	return BattleBuilder.new(Fixtures.rules(), null, 42)


func test_test_battle_matches_the_old_setup() -> void:
	var battle: BattleEngine = _builder().build({})
	var party: Array[Combatant] = battle.party_members()
	assert_eq(party.size(), 2)
	assert_eq(party[0].name, "Lasswell")
	assert_eq(party[1].name, "Rain")
	assert_eq(party[0].max_hp, 100000, "the old test battle's stat override")
	assert_eq(party[0].stat("ATK"), 1000)
	assert_eq(Array(party[0].attack_skill.effects[0].hit_frames), [4])
	assert_eq(Array(party[1].attack_skill.effects[0].hit_frames), [15, 36])
	assert_eq(Array(party[1].attack_skill.effects[0].hit_damage), [60, 40])
	assert_eq(party[0].max_lb, 800, "Blade Flash costs 8 crystals at level 1")

	assert_eq(battle.enemies.size(), 1)
	var zu: Combatant = battle.enemies[0]
	assert_eq(zu.source_id, ZU_ID)
	assert_eq(zu.max_hp, 3000)
	assert_eq(zu.stat("ATK"), 65)
	assert_eq(zu.stat("DEF"), 23)
	assert_eq(Array(zu.races), [2])
	assert_eq(Array(zu.attack_skill.effects[0].hit_frames), [42], "monster_parts.attackFrames")
	assert_eq(int(zu.meta["exp"]), 400)
	assert_true(zu.brain is ScriptedEnemyBrain, "Zu has an AI script")


func test_party_members_take_their_stats_from_stat_calculator() -> void:
	var builder: BattleBuilder = _builder()
	var unit: Dictionary = builder.unit_from_database("100000202")
	var expected: Dictionary = StatCalculator.calculate_final_stats(unit.duplicate())
	var member: Combatant = builder.party_member(unit)
	for stat_name in ["HP", "MP", "ATK", "DEF", "MAG", "SPR"]:
		assert_eq(member.base_stats[stat_name], int(expected["stats"][stat_name]), stat_name)
	assert_eq(member.max_hp, int(expected["stats"]["HP"]))
	assert_eq(member.limit_burst_id, "100000202")
	assert_eq(member.source_id, "battle_100000202")


func test_debuff_resistance_from_passives_reaches_the_combatant() -> void:
	# Ayaka 6* has "Wind the Clock" (opcode 55): nullify stop.
	var builder: BattleBuilder = _builder()
	var ayaka: Combatant = builder.party_member(builder.unit_from_database("100008606"))
	assert_eq(ayaka.debuff_resistance("STOP"), 100)
	assert_eq(ayaka.debuff_resistance("CHARM"), 0)
	var plain: Combatant = builder.party_member(builder.unit_from_database("100000202"))
	assert_eq(plain.debuff_resistance("STOP"), 0)


func test_a_killer_trait_reaches_the_combatant_and_its_damage() -> void:
	# Firion 3* has "Plant Killer" (opcode 11): +50% physical damage against plants (11).
	var builder: BattleBuilder = _builder()
	var firion: Combatant = builder.party_member(builder.unit_from_database("202000103"))
	assert_eq(firion.passives.killer_pct("physical", 11), 50)
	assert_eq(firion.passives.killer_pct("magic", 11), 0)
	var plant: Combatant = CombatantFactory.from_spec({"name": "Plant", "party": false, "races": [11]})
	var beast: Combatant = CombatantFactory.from_spec({"name": "Beast", "party": false, "races": [1]})
	var rules: BattleRules = Fixtures.rules()
	assert_almost_eq(DamageFormula.killer_multiplier(firion, plant, "physical", rules), 1.5, 0.0001)
	assert_almost_eq(DamageFormula.killer_multiplier(firion, beast, "physical", rules), 1.0, 0.0001)


func test_a_chain_master_trait_counts_once() -> void:
	# Melo 7* has "Chain Master": opcodes 84 and 85, both 200 ("boost damage for various
	# chains by 200%").
	var builder: BattleBuilder = _builder()
	var melo: Combatant = builder.party_member(builder.unit_from_database("100033407"))
	assert_eq(melo.passives.chain_boost_pct, 200)


func test_an_awakened_lb_change_replaces_the_limit_burst() -> void:
	# Rydia & Mist Dragon 7*: "The Feymarch Guardian" awakened once (recipe 223440001)
	# changes her LB to 900000498, twice (223440002) to 900000499.
	var builder: BattleBuilder = _builder()
	var unit: Dictionary = builder.unit_from_database("204003017")
	assert_eq(builder.party_member(unit).limit_burst_id, "204003017", "her own LB")
	unit["awakened_abilities"] = [223440001]
	var once: Combatant = builder.party_member(unit)
	assert_eq(once.limit_burst_id, "900000498")
	assert_true(once.max_lb > 0, "the gauge follows the new LB's cost")
	unit["awakened_abilities"] = [223440001, 223440002]
	assert_eq(builder.party_member(unit).limit_burst_id, "900000499")


func test_a_normal_attack_replacement_runs_on_the_attack_command() -> void:
	# Rain -Neo Vision- 7*: "Inherited Bloodline" changes the normal attack to ability
	# 514832, physical damage plus FILL_LB 500, which has no attack frames of its own.
	var builder: BattleBuilder = _builder()
	var unit: Dictionary = builder.unit_from_database("100031007")
	var rain: Combatant = builder.party_member(unit)
	var swing: BattleSkill = BattleSkill.basic_attack(str(unit.get("attackFrames", "")))
	assert_eq(rain.attack_skill.id, "514832")
	assert_eq(rain.attack_skill.kind, BattleSkill.KIND_ABILITY)
	assert_eq(Array(rain.attack_skill.effects[0].hit_frames), Array(swing.effects[0].hit_frames), "her own swing's frames")

	var battle: BattleEngine = builder.assemble([rain], [builder.enemy_by_id(ZU_ID)])
	battle.start()
	assert_eq(battle.execute(rain.id), BattleEngine.OK)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2 or battle.phase == BattleEngine.Phase.ENDED)
	var acted: Array[Dictionary] = Fixtures.actions_by(battle, rain.id)
	assert_true(not acted.is_empty() and str(acted[0]["skill_id"]) == "514832", "the action is the replacement")
	assert_true(rain.lb >= mini(500, rain.max_lb), "FILL_LB 500 ran: lb %d" % rain.lb)
	assert_true(not Fixtures.hits(battle).is_empty(), "the damage landed")


func test_a_units_passive_covers_and_sex_reach_its_combatant() -> void:
	# Cecil 6* at level 100: Cover (8: 5%, no mitigation), Sentinel (30%, 50%) and Saintly
	# Wall (75%, 50%).
	var builder: BattleBuilder = _builder()
	var cecil: Combatant = builder.party_member(builder.unit_from_database("204000106", 100))
	assert_eq(cecil.sex, Combatant.SEX_MALE)
	var chances: Array = []
	for cover in cecil.passives.covers:
		assert_true(bool(cover["physical"]) and not bool(cover["magic"]))
		chances.append(int(cover["chance"]))
	chances.sort()
	assert_eq(chances, [5, 30, 75])
	var ally: Combatant = Fixtures.unit("Ally")
	var best: Dictionary = CoverTracker.best_st_cover(cecil, ally, BattleSkill.ATTACK_PHYSICAL)
	assert_eq([int(best.get("chance", 0)), int(best.get("mit_min", 0)), int(best.get("mit_max", 0))], [75, 50, 50])


func test_weapon_inflicts_reach_the_combatant() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	var unit: Dictionary = _builder().unit_from_database("100000202")
	var inflicts: Callable = func(items: Array) -> Dictionary:
		var hands: Array = []
		for item in items:
			hands.append({"slot": item[0], "kind": PassiveSources.KIND_EQUIPMENT, "id": item[1], "data": GameDatabase.get_equipment(item[1])})
		return CombatantFactory.party_member(unit, StatCalculator.calculate_unit_profile(unit, hands, {})).weapon_inflicts
	assert_eq(inflicts.call([["r_hand", SLEEP_DAGGER], ["l_hand", LEATHER_SHIELD]]), {"SLEEP": 30})
	assert_eq(inflicts.call([["r_hand", SLEEP_DAGGER], ["l_hand", LOCKES_DAGGER]]), {"SLEEP": 50}, "the higher chance")
	assert_eq(inflicts.call([["r_hand", SLEEP_DAGGER], ["l_hand", MECH_DAGGER]]), {"POISON": 30, "SLEEP": 30, "PARALYSIS": 30})
	assert_eq(inflicts.call([]), {}, "unarmed")
	assert_eq(_builder().enemy_by_id(ZU_ID).weapon_inflicts, {}, "monsters have no weapons")


func test_a_dual_wielders_hands_reach_the_combatant() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	var unit: Dictionary = _builder().unit_from_database("100000202")
	var member: Callable = func(items: Array) -> Combatant:
		var resolved: Array = []
		for item in items:
			resolved.append(StatCalculator.resolve_item(item[0], str(item[1])))
		return CombatantFactory.party_member(unit, StatCalculator.calculate_unit_profile(unit, resolved, {}))
	# The left hand listed first, as a save may keep it.
	var dual: Combatant = member.call([["l_hand", LIGHTNING_DAGGER], ["r_hand", MECH_DAGGER], ["ability_1", DUAL_FORM]])
	assert_true(dual.is_dual_wielding())
	assert_eq(Array(dual.hand_atk), [170, 40], "85 and 20, each doubled by Dual Form")
	assert_eq(Array(dual.weapon_elements), [1, 3], "fire, then lightning")
	var single: Combatant = member.call([["r_hand", MECH_DAGGER], ["l_hand", LEATHER_SHIELD], ["ability_1", DUAL_FORM]])
	assert_false(single.is_dual_wielding())
	assert_eq(Array(single.hand_atk), [85], "no Dual Form bonus with one weapon")
	assert_eq(dual.stat("ATK") - single.stat("ATK"), 125, "the dagger's 20 plus Dual Form's 105")

	var foe: Combatant = Fixtures.monster("Foe", {"brain": IdleEnemyBrain.new()})
	var battle: BattleEngine = Fixtures.engine([dual], [foe])
	battle.start()
	battle.execute(dual.id, BattleCommand.attack(foe.id))
	Fixtures.run_until(battle, func() -> bool: return battle.events.count_of_type(BattleEventLog.ACTION_ENDED) >= 1)
	var atk: int = dual.stat("ATK")
	var expected: Array[int] = []
	for left_out in [40, 170]:
		expected.append(floori(float((atk - left_out) * (atk - left_out)) / 100.0))
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), expected, "each hand leaves the other weapon out")


func test_the_right_hand_weapons_variance_reaches_the_combatant() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	var unit: Dictionary = _builder().unit_from_database("100000202")
	var variance: Callable = func(items: Array) -> Array:
		var hands: Array = []
		for item in items:
			hands.append({"slot": item[0], "kind": PassiveSources.KIND_EQUIPMENT, "id": item[1], "data": GameDatabase.get_equipment(item[1])})
		var member: Combatant = CombatantFactory.party_member(unit, StatCalculator.calculate_unit_profile(unit, hands, {}))
		return [member.weapon_variance_min, member.weapon_variance_max]
	assert_eq(variance.call([["r_hand", SLEEP_DAGGER], ["l_hand", LEATHER_SHIELD]]), [110, 120], "a dagger")
	assert_eq(variance.call([["r_hand", KATAR]]), [145, 165], "a two-handed dagger")
	assert_eq(variance.call([["l_hand", BROADSWORD], ["r_hand", SLEEP_DAGGER]]), [110, 120],
		"dual wield: the right hand's for both (wiki), whatever order the save keeps")
	assert_eq(variance.call([["r_hand", LEATHER_SHIELD], ["l_hand", BROADSWORD]]), [105, 125], "the only weapon, in the left hand")
	assert_eq(variance.call([["l_hand", LEATHER_SHIELD]]), [100, 100], "a shield is not a weapon")
	assert_eq(variance.call([]), [100, 100], "unarmed")
	var zu: Combatant = _builder().enemy_by_id(ZU_ID)
	assert_eq([zu.weapon_variance_min, zu.weapon_variance_max], [100, 100], "monsters have no weapons")


func test_unreadable_weapon_variance_counts_as_none() -> void:
	var weapon: Callable = func(variance: Variant) -> Vector2i:
		return CombatantFactory.weapon_variance_from({"hands": [{"kind": PassiveSources.HAND_WEAPON, "variance": variance}]})
	assert_eq(weapon.call("120,560"), Vector2i(120, 560), "odd ranges stay as the data has them")
	assert_eq(weapon.call(" 130, 170 "), Vector2i(130, 170))
	assert_eq(weapon.call("170,130"), Vector2i(130, 170), "the lower value first")
	assert_eq(weapon.call(""), Vector2i(100, 100))
	assert_eq(weapon.call("0"), Vector2i(100, 100), "armor and accessories carry 0")
	assert_eq(weapon.call("a,b"), Vector2i(100, 100))
	assert_eq(CombatantFactory.weapon_variance_from({}), Vector2i(100, 100))
	assert_eq(CombatantFactory.weapon_variance_from(null), Vector2i(100, 100))


func test_a_two_handed_weapon_marks_the_combatant() -> void:
	var great_sword: Dictionary = {"kind": PassiveSources.HAND_WEAPON, "two_handed": true, "variance": "125,175"}
	var dagger: Dictionary = {"kind": PassiveSources.HAND_WEAPON, "two_handed": false, "variance": "110,120"}
	var shield: Dictionary = {"kind": PassiveSources.HAND_SHIELD, "two_handed": true}
	assert_true(CombatantFactory.two_handed_from({"hands": [great_sword]}), "its jumps roll the flat 2.50 to 2.80")
	assert_false(CombatantFactory.two_handed_from({"hands": [dagger]}))
	assert_false(CombatantFactory.two_handed_from({"hands": [shield]}), "weapons only")
	assert_false(CombatantFactory.two_handed_from({}))


func test_monster_profile_comes_from_monster_stat_calculator() -> void:
	var parts: Dictionary = GameDatabase.get_monster_parts(ZU_ID)
	var stat_input: Dictionary = CombatantFactory.monster_stat_input(parts)
	assert_true(bool(stat_input["is_monster"]))
	var profile: Dictionary = StatCalculator.calculate_final_stats(stat_input)
	assert_eq(int(profile["stats"]["SPR"]), 23)
	assert_eq(int(profile["element_resist"]["WIND"]), 0)


func test_tribes_with_several_races_keep_them_all() -> void:
	assert_eq(Array(CombatantFactory.races_from("4,8")), [4, 8])
	assert_eq(Array(CombatantFactory.races_from(5)), [5])
	assert_eq(Array(CombatantFactory.races_from(null)), [])
	assert_eq(Array(CombatantFactory.races_from("")), [])
	# monster_parts.tribe "3,4": aquatic and demon.
	assert_eq(Array(_builder().enemy_by_id("103039000").races), [3, 4])


func test_monster_damage_cuts_come_from_the_parts_row() -> void:
	var builder: BattleBuilder = _builder()
	var physical_proof: Combatant = builder.enemy_by_id("104023013")
	assert_eq(physical_proof.physical_resist, 100)
	assert_eq(physical_proof.magic_resist, 0)
	var magic_proof: Combatant = builder.enemy_by_id("104023014")
	assert_eq(magic_proof.physical_resist, 0)
	assert_eq(magic_proof.magic_resist, 100)
	assert_eq(builder.enemy_by_id(ZU_ID).physical_resist, 0)


func test_mission_wave_formation_resolves() -> void:
	var plan: Array = EncounterResolver.build_wave_plan("1110100")
	assert_true(plan.size() >= 2, "mission 1110100 has a wave plan")
	var formation: Array[Combatant] = _builder().formation_for("1110100", str(plan[0]["target_id"]))
	assert_true(formation.size() > 0, "wave 1 has enemies")
	for foe in formation:
		assert_true(foe.max_hp > 0 and foe.stat("ATK") > 0, foe.name)
		assert_not_null(foe.brain)


func test_mission_waves_cover_the_whole_plan() -> void:
	var plan: Array = EncounterResolver.build_wave_plan("1110100")
	var waves: Array[Callable] = _builder().mission_waves("1110100")
	assert_eq(waves.size(), plan.size())
	var second: Array[Combatant] = []
	second.assign(waves[1].call())
	assert_true(second.size() > 0, "wave 2 resolves when called")


func test_database_catalog_resolves_real_skills() -> void:
	var catalog := DatabaseSkillCatalog.new()
	var whirlwind: BattleSkill = catalog.get_skill(BattleSkill.KIND_MONSTER, GREAT_WHIRLWIND_ID)
	assert_not_null(whirlwind)
	assert_eq(whirlwind.name, "Great Whirlwind")
	assert_eq(whirlwind.effects[0].type, "PHYSICAL_DAMAGE")
	assert_eq(whirlwind.effects[0].param_float("modifier"), 200.0)
	assert_eq(whirlwind.effects[0].target_area, SkillEffect.AREA_ALL)
	assert_eq(Array(whirlwind.elements), [5], "wind")
	var blade_flash: BattleSkill = catalog.get_limit_burst("100000202", 1)
	assert_eq(blade_flash.lb_cost, 800)
	assert_eq(blade_flash.effects[0].param_float("modifier"), 180.0)
	assert_null(catalog.get_skill(BattleSkill.KIND_ABILITY, "0"))


func test_real_cover_abilities_put_their_statuses_where_the_data_says() -> void:
	# Light is with us! (96 on self, physical), Illusion - Redirect (96 on one ally),
	# Royal Guard (118 on a chosen ally, with a DEF and SPR buff on the caster).
	var builder: BattleBuilder = _builder()
	var knight: Combatant = Fixtures.unit("Knight", {"attack_frames": "4:100"})
	var dancer: Combatant = Fixtures.unit("Dancer", {"attack_frames": "4:100"})
	var guard: Combatant = Fixtures.unit("Guard", {"attack_frames": "4:100"})
	var battle: BattleEngine = builder.assemble([knight, dancer, guard], [builder.enemy_by_id(ZU_ID)])
	for skill_id in ["206480", "910536", "216100"]:
		var skill: BattleSkill = battle.catalog.get_skill(BattleSkill.KIND_ABILITY, skill_id)
		assert_true(skill != null and battle.unsupported_effects(skill).is_empty(), "%s runs in full" % skill_id)
	battle.start()
	battle.execute(knight.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "206480", knight.id))
	battle.execute(dancer.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "910536", guard.id))
	battle.advance(1)
	var light: BattleStatus = knight.find_status(BattleStatus.COVER, CoverTracker.KEY_AOE)
	assert_true(light != null and light.value == 50 and bool(light.params["physical"]) and not bool(light.params["magic"]),
		"Light is with us!: 50% physical AoE cover")
	var redirect: BattleStatus = guard.find_status(BattleStatus.COVER, CoverTracker.KEY_AOE)
	assert_true(redirect != null and redirect.value == 100 and int(redirect.params["mit_min"]) == 30, "Redirect: on the ally")
	assert_null(dancer.find_status(BattleStatus.COVER, CoverTracker.KEY_AOE), "not on the dancer")
	battle.execute(guard.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "216100", knight.id))
	# Its cover effect lands on frame 120.
	Fixtures.run_until(battle, func() -> bool: return guard.find_status(BattleStatus.COVER, CoverTracker.KEY_ST) != null, 200)
	var royal: BattleStatus = guard.find_status(BattleStatus.COVER, CoverTracker.KEY_ST)
	assert_true(royal != null and int(royal.params["protects"]) == knight.id and bool(royal.params["magic"]),
		"Royal Guard: the caster covers the knight, physical and magic")


func test_real_provoke_abilities_put_their_statuses_where_the_data_says() -> void:
	# Provoke (61 on self: 100%, 3 turns), Mist Decoy (61 and 101 on one ally).
	var builder: BattleBuilder = _builder()
	var tank: Combatant = Fixtures.unit("Tank", {"attack_frames": "4:100"})
	var mage: Combatant = Fixtures.unit("Mage", {"attack_frames": "4:100"})
	var decoy: Combatant = Fixtures.unit("Decoy", {"attack_frames": "4:100"})
	var battle: BattleEngine = builder.assemble([tank, mage, decoy], [builder.enemy_by_id(ZU_ID)])
	for skill_id in ["200480", "235615"]:
		var skill: BattleSkill = battle.catalog.get_skill(BattleSkill.KIND_ABILITY, skill_id)
		assert_true(skill != null and battle.unsupported_effects(skill).is_empty(), "%s runs in full" % skill_id)
	battle.start()
	battle.execute(tank.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "200480", tank.id))
	battle.execute(mage.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "235615", decoy.id))
	# Provoke lands on frame 130 (its attackFrames), Mist Decoy at once.
	Fixtures.run_until(battle, func() -> bool: return tank.find_status(BattleStatus.PROVOKE) != null, 200)
	var own: BattleStatus = tank.find_status(BattleStatus.PROVOKE)
	assert_true(own != null and own.value == 100 and own.turns_left == 3, "Provoke: 100% on the caster for 3 turns")
	assert_eq(decoy.status_value(BattleStatus.PROVOKE), 100, "Mist Decoy: on the picked ally")
	assert_eq(decoy.status_value(BattleStatus.MITIGATION, "all"), 30, "with its damage reduction")
	assert_null(mage.find_status(BattleStatus.PROVOKE), "not on the caster")


func test_a_real_battle_runs_to_the_end() -> void:
	var builder: BattleBuilder = _builder()
	# Tough but weak-hitting starters, so Zu lives long enough to use its AI.
	var party: Array[Combatant] = builder.party_from_units(builder.test_party_units(), {
		"HP": 100000, "ATK": 60, "DEF": 1000, "SPR": 1000,
	})
	var battle: BattleEngine = builder.assemble(party, builder.formation_for("", BattleBuilder.TEST_BATTLE_GROUP))
	var zu: Combatant = battle.enemies[0]
	battle.start()
	for _turn in range(40):
		if battle.phase == BattleEngine.Phase.ENDED:
			break
		battle.execute_many(battle.units_to_act().map(func(unit: Combatant) -> int: return unit.id))
		Fixtures.run_until(battle, func() -> bool:
			return battle.phase == BattleEngine.Phase.ENDED or not battle.units_to_act().is_empty(), 5000)

	assert_eq(battle.outcome, BattleEngine.OUTCOME_VICTORY)
	var zu_actions: Array[Dictionary] = Fixtures.actions_by(battle, zu.id)
	assert_true(zu_actions.size() >= 3, "Zu acted on each of its turns")

	# Rule 1 (below 30% HP, once per battle) is Great Whirlwind: AoE physical, 200%.
	var whirlwinds: Array[Dictionary] = []
	for event in zu_actions:
		if event["skill_id"] == GREAT_WHIRLWIND_ID:
			whirlwinds.append(event)
	assert_eq(whirlwinds.size(), 1, "limited_act:1")
	if whirlwinds.size() == 1:
		for hit in Fixtures.hits(battle):
			if int(hit["action"]) != int(whirlwinds[0]["action"]):
				continue
			var target: Combatant = battle.combatant(int(hit["target"]))
			var expected: int = floori(65.0 * 65.0 / float(target.stat("DEF")) * 2.0 * DamageFormula.element_multiplier(target, PackedInt32Array([5])))
			assert_eq(int(hit["amount"]), expected, "Great Whirlwind on %s" % target.name)
