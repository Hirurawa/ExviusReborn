extends "res://tests/test_case.gd"

## Skills from the catalog: splits across hits and targets, magic and elements, costs,
## limit bursts, effects the engine cannot run yet, opcode 99 and targeting.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var catalog: SkillCatalog


func before_each() -> void:
	catalog = Fixtures.catalog()


func test_multi_hit_aoe_ability_splits_damage_per_target() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "1001",
		Fixtures.skill_record("Cleave", 1, Fixtures.physical_params(200), "10:50-20:50", SkillEffect.AREA_ALL))
	var a: Combatant = Fixtures.unit("A")
	var e1: Combatant = Fixtures.monster("E1")
	var e2: Combatant = Fixtures.monster("E2")
	var battle: BattleEngine = Fixtures.engine([a], [e1, e2], null, catalog)
	battle.start()
	assert_eq(battle.execute(a.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "1001", e1.id)), BattleEngine.OK)
	battle.advance(20)
	for foe in [e1, e2]:
		var landed: Array[Dictionary] = Fixtures.hits(battle, foe.id)
		# 100 x 2.0 split 50/50; the second hit comes from the same unit, so no chain.
		assert_eq(Fixtures.amounts(landed), [100, 100], foe.name)
		assert_eq(int(landed[0]["hits"]), 2)


func test_magic_uses_mag_against_spr_with_elements_and_costs_mp() -> void:
	catalog.add_record(BattleSkill.KIND_MAGIC, "2001",
		Fixtures.skill_record("Fire", 15, Fixtures.magic_params(150), "30:100", 1, 1, 10, [1]))
	var mage: Combatant = Fixtures.unit("Mage", {"mp": 30, "mag": 100})
	var foe: Combatant = Fixtures.monster("Foe", {"spr": 100, "element_resist": {"FIRE": -50}})
	var battle: BattleEngine = Fixtures.engine([mage], [foe], null, catalog)
	battle.start()
	assert_eq(battle.execute(mage.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "2001", foe.id)), BattleEngine.OK)
	assert_eq(mage.mp, 20)
	var paid: Dictionary = battle.events.last_of_type(BattleEventLog.COST_PAID)
	assert_eq(int(paid.get("mp_cost", 0)), 10)
	battle.advance(30)
	# 100 x 1.5 x 1.5 (fire weakness)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [225])


func test_not_enough_mp_is_rejected_without_acting() -> void:
	catalog.add_record(BattleSkill.KIND_MAGIC, "2002",
		Fixtures.skill_record("Firaga", 15, Fixtures.magic_params(300), "30:100", 1, 1, 50))
	var mage: Combatant = Fixtures.unit("Mage", {"mp": 20})
	var battle: BattleEngine = Fixtures.engine([mage], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	assert_eq(battle.execute(mage.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "2002")), BattleEngine.REJECT_NOT_ENOUGH_MP)
	assert_false(mage.acted)
	assert_eq(mage.mp, 20)
	var rejected: Dictionary = battle.events.last_of_type(BattleEventLog.COMMAND_REJECTED)
	assert_eq(rejected.get("reason", &""), BattleEngine.REJECT_NOT_ENOUGH_MP)


## Rough Divide's shape: alternateCost "2:400" takes 4 crystals (400 hundredths) from the
## unit's own gauge, on top of any MP.
func test_an_ability_that_consumes_lb_gauge_needs_it_and_takes_it_when_cast() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "2003", Fixtures.record("Rough Divide",
		[[1, 1, 1, Fixtures.physical_params(100)]], "10:100", {"cost": {"MP": 5}, "alternate_cost": {"type": 2, "amount": 400}}))
	var squall: Combatant = Fixtures.unit("Squall", {"lb": 300, "max_lb": 2000})
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([squall], [foe], null, catalog)
	battle.start()
	var command: BattleCommand = BattleCommand.skill(BattleSkill.KIND_ABILITY, "2003", foe.id)
	assert_eq(catalog.get_skill(BattleSkill.KIND_ABILITY, "2003").lb_cost, 400)
	assert_eq(battle.can_execute(squall.id, command), BattleEngine.REJECT_LIMIT_NOT_FULL, "3 crystals are not enough")
	squall.lb = 500
	assert_eq(battle.execute(squall.id, command), BattleEngine.OK)
	assert_eq([squall.lb, squall.mp], [100, 95])
	var paid: Dictionary = battle.events.last_of_type(BattleEventLog.COST_PAID)
	assert_eq([int(paid["lb_cost"]), int(paid["mp_cost"]), int(paid["lb"])], [400, 5, 100])


func test_unknown_skill_is_rejected() -> void:
	var a: Combatant = Fixtures.unit("A")
	var battle: BattleEngine = Fixtures.engine([a], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	assert_eq(battle.execute(a.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "404")), BattleEngine.REJECT_UNKNOWN_SKILL)


func test_limit_burst_needs_a_full_gauge_and_uses_its_level() -> void:
	catalog.add_record(BattleSkill.KIND_LIMIT_BURST, "3001", {
		"name": "Blade Flash",
		"levels": [
			[8, [[1, 1, 1, Fixtures.physical_params(180)]]],
			[8, [[1, 1, 1, Fixtures.physical_params(185)]]],
		],
		"attack_frames": [[60]],
		"attack_damage": [[100]],
	})
	var hero: Combatant = Fixtures.unit("Hero", {"limit_burst_id": "3001", "max_lb": 800, "lb": 700})
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	assert_eq(battle.execute(hero.id, BattleCommand.limit_burst("3001", foe.id)), BattleEngine.REJECT_LIMIT_NOT_FULL)
	hero.lb = 800
	assert_eq(battle.execute(hero.id, BattleCommand.limit_burst("3001", foe.id)), BattleEngine.OK)
	assert_eq(hero.lb, 0, "the gauge is spent")
	battle.advance(60)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [180], "level 1 modifier")


func test_effects_the_engine_cannot_run_are_reported() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "5001", {
		"name": "Mixed Bag",
		"effects_raw": [
			[1, 1, 1, Fixtures.physical_params(100)],
			[1, 1, 35, [50]],
			[1, 1, 9999, [1]],
		],
		"attack_frames": [[10]],
		"attack_damage": [[100]],
	})
	var a: Combatant = Fixtures.unit("A")
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a], [foe], null, catalog)
	battle.start()
	battle.execute(a.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "5001", foe.id))
	var unsupported: Array[Dictionary] = battle.events.of_type(BattleEventLog.EFFECT_UNSUPPORTED)
	assert_eq(unsupported.size(), 2)
	assert_eq(int(unsupported[0]["opcode"]), 35)
	assert_eq(unsupported[0]["effect"], "KO")
	assert_eq(unsupported[0]["reason"], &"no_handler")
	assert_eq(int(unsupported[1]["opcode"]), 9999)
	assert_eq(unsupported[1]["reason"], &"opcode_not_in_schema")
	battle.advance(10)
	assert_eq(Fixtures.hits(battle, foe.id).size(), 1, "the damage effect still lands")


func test_replacement_runs_its_default_branch_for_now() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "4001", {
		"name": "Dance",
		"effects_raw": [[1, 1, 99, [2, 4000, 0, 4002, 0, 4003]]],
	})
	catalog.add_record(BattleSkill.KIND_ABILITY, "4003",
		Fixtures.skill_record("Default Dance", 1, Fixtures.physical_params(100), "5:100"))
	var a: Combatant = Fixtures.unit("A")
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a], [foe], null, catalog)
	battle.start()
	assert_eq(battle.execute(a.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "4001", foe.id)), BattleEngine.OK)
	var started: Dictionary = Fixtures.actions_by(battle, a.id)[0]
	assert_eq(started["skill_id"], "4001", "the event names the skill the player chose")
	assert_eq(started["executed_skill_id"], "4003", "and the branch that runs")
	battle.advance(5)
	assert_eq(Fixtures.hits(battle, foe.id).size(), 1)


func test_random_target_effect_spreads_hits_over_living_enemies() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "6001",
		Fixtures.skill_record("Scatter", 1, Fixtures.physical_params(100), "5:25-10:25-15:25-20:25", SkillEffect.AREA_RANDOM))
	var a: Combatant = Fixtures.unit("A")
	var e1: Combatant = Fixtures.monster("E1")
	var e2: Combatant = Fixtures.monster("E2")
	var gone: Combatant = Fixtures.monster("Gone")
	gone.hp = 0
	var battle: BattleEngine = Fixtures.engine([a], [e1, e2, gone], null, catalog)
	battle.start()
	battle.execute(a.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "6001"))
	battle.advance(20)
	var landed: Array[Dictionary] = Fixtures.hits(battle)
	assert_eq(landed.size(), 4)
	for event in landed:
		assert_true(int(event["target"]) in [e1.id, e2.id], "hits land on living enemies only")
		assert_eq(int(event["amount"]), 25)


func test_target_resolution_by_side_and_area() -> void:
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	var e1: Combatant = Fixtures.monster("E1")
	var e2: Combatant = Fixtures.monster("E2")
	var battle: BattleEngine = Fixtures.engine([a, b], [e1, e2], null, catalog)
	battle.start()

	var ally_single := SkillEffect.new()
	ally_single.target_type = SkillEffect.TARGET_ALLY
	ally_single.target_area = SkillEffect.AREA_SINGLE
	assert_eq(battle.resolve_targets(a, ally_single, null), [a], "no pick: the caster")
	assert_eq(battle.resolve_targets(a, ally_single, b), [b], "an ally pick")
	assert_eq(battle.resolve_targets(a, ally_single, e1), [a], "an enemy pick does not count for an ally effect")

	var others := SkillEffect.new()
	others.target_type = SkillEffect.TARGET_ALLY_EXCEPT_SELF
	others.target_area = SkillEffect.AREA_ALL
	assert_eq(battle.resolve_targets(a, others, null), [b])

	var self_only := SkillEffect.new()
	self_only.target_type = SkillEffect.TARGET_SELF
	self_only.target_area = SkillEffect.AREA_SELF
	assert_eq(battle.resolve_targets(a, self_only, e1), [a])

	var enemy_all := SkillEffect.new()
	enemy_all.target_type = SkillEffect.TARGET_OPPONENT
	enemy_all.target_area = SkillEffect.AREA_ALL
	assert_eq(battle.resolve_targets(a, enemy_all, null), [e1, e2])
	assert_eq(battle.resolve_targets(e1, enemy_all, null), [a, b], "sides are relative to the caster")

	var enemy_ally := battle.resolve_targets(e1, ally_single, null)
	assert_eq(enemy_ally.size(), 1)
	assert_true(enemy_ally[0].is_enemy(), "an enemy's ally effect picks one of its own side")
