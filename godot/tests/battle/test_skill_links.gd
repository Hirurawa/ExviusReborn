extends "res://tests/test_case.gd"

## Skills that lead to other skills: cooldown and use-limited wrappers (130, 157), uses
## per battle (1014) and random casts (29).

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var catalog: SkillCatalog


func before_each() -> void:
	catalog = Fixtures.catalog()
	catalog.add_record(BattleSkill.KIND_ABILITY, "500", Fixtures.skill_record("Inner Strike", 1, Fixtures.physical_params(200), "10:100"))
	catalog.add_record(BattleSkill.KIND_ABILITY, "501", Fixtures.skill_record("Inner Heal", 16, [150], "10:100", 1, 3))


func _skill(skill_id: String, target: Combatant = null) -> BattleCommand:
	return BattleCommand.skill(BattleSkill.KIND_ABILITY, skill_id, target.id if target != null else -1)


## Plays out the rest of the turn with basic attacks for whoever has not acted.
func _finish_turn(battle: BattleEngine) -> void:
	var next_turn: int = battle.turn + 1
	var ids: Array = []
	for unit in battle.units_to_act():
		ids.append(unit.id)
	battle.execute_many(ids)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == next_turn)


func test_a_cooldown_wrapper_runs_its_ability_every_n_turns() -> void:
	# "One use every 3 turns" is stored as turns 2; initial 2 means ready at once.
	catalog.add_record(BattleSkill.KIND_ABILITY, "130", Fixtures.record("Strike (CD)", [[1, 1, 130, [500, 1, [2, 2], 0]]], "", {"cost": {"MP": 20}}))
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()

	assert_eq(battle.execute(hero.id, _skill("130", foe)), BattleEngine.OK)
	var started: Dictionary = Fixtures.actions_by(battle, hero.id)[0]
	assert_eq(started["skill_name"], "Strike (CD)", "the event names the wrapper")
	assert_eq(started["executed_skill_id"], "500")
	assert_eq(hero.mp, 80, "the wrapper's cost is paid")
	battle.advance(10)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [200], "the wrapped ability runs")
	assert_eq(battle.skill_limits(hero.id, _skill("130")), {"uses_left": -1, "ready_turn": 4})
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)

	assert_eq(battle.can_execute(hero.id, _skill("130")), BattleEngine.REJECT_SKILL_NOT_READY, "turn 2")
	_finish_turn(battle)
	assert_eq(battle.can_execute(hero.id, _skill("130")), BattleEngine.REJECT_SKILL_NOT_READY, "turn 3")
	_finish_turn(battle)
	assert_eq(battle.can_execute(hero.id, _skill("130")), BattleEngine.OK, "turn 4")


func test_a_cooldown_that_starts_empty_waits_first() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "131", Fixtures.record("Strike (charging)", [[1, 1, 130, [500, 1, [2, 0], 0]]], ""))
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = Fixtures.engine([hero], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	assert_eq(battle.can_execute(hero.id, _skill("131")), BattleEngine.REJECT_SKILL_NOT_READY)
	_finish_turn(battle)
	_finish_turn(battle)
	assert_eq(battle.turn, 3)
	assert_eq(battle.can_execute(hero.id, _skill("131")), BattleEngine.OK)


func test_uses_per_battle_run_out() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "600", Fixtures.record("Once (CD)", [
		[1, 1, 130, [500, 0, [0, 0], 0]],
		[0, 3, 1014, [600, 2, 1, 1, 1, 0]],
	], ""))
	catalog.add_record(BattleSkill.KIND_ABILITY, "157", Fixtures.record("Twice", [[0, 3, 157, [501, 0, 2, 2, 1, 1, 0, 0, 0]]], ""))
	var hero: Combatant = Fixtures.unit("Hero")
	hero.hp = 100
	var battle: BattleEngine = Fixtures.engine([hero], [Fixtures.monster("Foe", {"atk": 0})], null, catalog)
	battle.start()
	assert_eq(battle.execute(hero.id, _skill("600")), BattleEngine.OK)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(battle.can_execute(hero.id, _skill("600")), BattleEngine.REJECT_NO_USES_LEFT)

	assert_eq(battle.execute(hero.id, _skill("157")), BattleEngine.OK)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 3)
	assert_eq(battle.execute(hero.id, _skill("157")), BattleEngine.OK)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 4)
	assert_eq(battle.can_execute(hero.id, _skill("157")), BattleEngine.REJECT_NO_USES_LEFT)
	assert_eq(hero.hp, 400, "the limited skill healed 150 twice")


func test_a_random_cast_runs_its_pick_as_a_linked_action() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "29", Fixtures.record("Gamble", [[1, 1, 29, [[500, 100], [501, 0], 0, 0, 0]]], ""))
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	assert_eq(battle.execute(hero.id, _skill("29", foe)), BattleEngine.OK)
	var actions: Array[Dictionary] = Fixtures.actions_by(battle, hero.id)
	assert_eq(actions.size(), 2)
	assert_eq(actions[0]["skill_id"], "29")
	assert_eq(actions[1]["skill_id"], "500", "the only choice with weight")
	assert_eq(actions[1]["origin"], BattleAction.Origin.CAST)
	battle.advance(10)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [200])
