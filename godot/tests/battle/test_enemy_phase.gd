extends "res://tests/test_case.gd"

## The enemy phase: one action at a time, each decided when it starts, spacing,
## defend, the scripted AI through MonsterAIRuntime, fallbacks and defeat.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")


## Attacks once per turn and records the HP of party slot 1 each time it decides.
class RecordingBrain:
	extends EnemyBrain
	var seen_hp: Array[int] = []

	func next_action(ctx: Dictionary) -> Dictionary:
		if _attacks_left > 0:
			seen_hp.append(int(ctx["party"][0]["current_hp"]))
		return super.next_action(ctx)


## Returns the same decision once per turn.
class FixedBrain:
	extends EnemyBrain
	var decision: Dictionary = {}

	func next_action(_ctx: Dictionary) -> Dictionary:
		if _attacks_left <= 0:
			return turn_over("done")
		_attacks_left -= 1
		return decision


func _enemy_actions(battle: BattleEngine) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in Fixtures.actions_by(battle):
		if battle.combatant(int(event["actor"])).is_enemy():
			out.append(event)
	return out


func test_enemies_act_one_at_a_time_after_the_party() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	var e1: Combatant = Fixtures.monster("E1", {"attack_frames": "42:100"})
	var e2: Combatant = Fixtures.monster("E2", {"attack_frames": "42:100"})
	var battle: BattleEngine = Fixtures.engine([hero], [e1, e2])
	battle.start()
	battle.execute(hero.id)
	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.turn == 2))

	var enemy_phase: Dictionary = {}
	for event in battle.events.of_type(BattleEventLog.PHASE_CHANGED):
		if event["phase"] == &"enemy":
			enemy_phase = event
	assert_eq(int(enemy_phase.get("frame", -1)), 4, "the enemy phase starts when the party's last hit lands")

	var actions: Array[Dictionary] = _enemy_actions(battle)
	assert_eq(actions.size(), 2)
	assert_eq(int(actions[0]["actor"]), e1.id)
	assert_eq(int(actions[0]["frame"]), 4)
	# The next action waits max(42 + 20, 90) frames.
	assert_eq(int(actions[1]["actor"]), e2.id)
	assert_eq(int(actions[1]["frame"]), 94)

	var landed: Array[Dictionary] = Fixtures.hits(battle, hero.id)
	assert_eq([int(landed[0]["frame"]), int(landed[1]["frame"])], [46, 136])
	assert_eq(Fixtures.amounts(landed), [100, 100])
	assert_eq(int(landed[1]["chain"]), 0, "90 frames apart, so no chain")
	assert_eq(hero.hp, hero.max_hp - 200)

	var turn_two: Dictionary = battle.events.last_of_type(BattleEventLog.TURN_STARTED)
	assert_eq(int(turn_two["frame"]), 136, "the turn ends once the last enemy hit lands")
	assert_eq(battle.phase, BattleEngine.Phase.PLAYER)


func test_each_enemy_decision_sees_the_battle_as_it_is() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	var recorder := RecordingBrain.new()
	var e1: Combatant = Fixtures.monster("E1")
	var e2: Combatant = Fixtures.monster("E2", {"brain": recorder})
	var battle: BattleEngine = Fixtures.engine([hero], [e1, e2])
	battle.start()
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	# E2 decides on frame 94, after E1's hit on frame 46. The old engine decided the
	# whole enemy turn up front and would have seen 1000.
	assert_eq(recorder.seen_hp, [900])


func test_defend_halves_damage_until_the_next_turn() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 3)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, hero.id)), [50, 100])


func test_a_defending_enemy_takes_half_until_its_own_turn() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	var guard := FixedBrain.new()
	guard.decision = EnemyBrain.action(EnemyBrain.KIND_GUARD)
	var foe: Combatant = Fixtures.monster("Foe", {"brain": guard})
	var battle: BattleEngine = Fixtures.engine([hero], [foe])
	battle.start()
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_true(foe.defending, "guard holds through the next player phase")
	battle.execute(hero.id)
	battle.advance(4)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [100, 50])


func test_scripted_enemy_follows_its_ai_rules() -> void:
	var catalog: SkillCatalog = Fixtures.catalog()
	catalog.add_record(BattleSkill.KIND_MONSTER, "800001",
		Fixtures.skill_record("Big Breath", 15, Fixtures.magic_params(300), "20:100", SkillEffect.AREA_ALL))

	# Below half HP: skill slot 1; otherwise attack. One action per turn (no turn_end).
	var rules: Array[Dictionary] = [
		_rule(1, [{"type": "hp_pr_under", "params": PackedStringArray(["50"])}], MonsterAIScript.VERB_SKILL, 1),
		_rule(2, [], MonsterAIScript.VERB_ATTACK, MonsterAIScript.SKILL_INDEX_NONE),
	]
	var compiled := MonsterAIScript.new()
	compiled.monster_id = "900000001"
	compiled.skill_slots = PackedStringArray(["800001"])
	compiled.rules = rules
	var boss: Combatant = Fixtures.monster("Boss", {
		"hp": 1000,
		"brain": ScriptedEnemyBrain.new(compiled, MonsterAIState.new("900000001")),
	})
	var hero: Combatant = Fixtures.unit("Hero", {"atk": 250, "hp": 5000, "attack_frames": "4:100"})
	var battle: BattleEngine = Fixtures.engine([hero], [boss], null, catalog)
	battle.start()

	battle.execute(hero.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	battle.execute(hero.id)  # 250^2 / 100 = 625: the boss drops to 37.5%
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 3)

	var actions: Array[Dictionary] = _enemy_actions(battle)
	assert_eq(actions.size(), 2)
	assert_eq(actions[0]["skill_kind"], BattleSkill.KIND_ATTACK, "turn 1: full HP")
	assert_eq(actions[1]["skill_kind"], BattleSkill.KIND_MONSTER, "turn 2: below half")
	assert_eq(actions[1]["skill_id"], "800001")
	assert_eq(int(actions[1]["payload"]["rule_order"]), 1)
	var breath: Array[Dictionary] = []
	for event in Fixtures.hits(battle, hero.id):
		if int(event["action"]) == int(actions[1]["action"]):
			breath.append(event)
	assert_eq(Fixtures.amounts(breath), [300], "100^2 / 100 x 3.0")


func test_a_skill_the_engine_cannot_resolve_becomes_an_attack() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	var confused := FixedBrain.new()
	confused.decision = EnemyBrain.action(EnemyBrain.KIND_SKILL, "no_such_skill")
	var foe: Combatant = Fixtures.monster("Foe", {"brain": confused})
	var battle: BattleEngine = Fixtures.engine([hero], [foe])
	battle.start()
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	var actions: Array[Dictionary] = _enemy_actions(battle)
	assert_eq(actions.size(), 1)
	assert_eq(actions[0]["skill_kind"], BattleSkill.KIND_ATTACK)
	assert_eq(Fixtures.hits(battle, hero.id).size(), 1)


func test_waiting_takes_no_time() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:100"})
	var idle := FixedBrain.new()
	idle.decision = EnemyBrain.action(EnemyBrain.KIND_WAIT)
	var foe: Combatant = Fixtures.monster("Idle", {"brain": idle})
	var battle: BattleEngine = Fixtures.engine([hero], [foe])
	battle.start()
	battle.execute(hero.id)
	battle.advance(4)
	assert_eq(battle.turn, 2, "a monster that only waits hands the turn straight back")


func test_ai_target_modes_pick_from_the_living_party() -> void:
	var sturdy: Combatant = Fixtures.unit("Sturdy", {"hp": 3000, "attack_frames": "4:100"})
	var frail: Combatant = Fixtures.unit("Frail", {"hp": 500, "attack_frames": "4:100"})
	var picky := FixedBrain.new()
	picky.decision = EnemyBrain.action(EnemyBrain.KIND_ATTACK, "", "hp_min")
	var foe: Combatant = Fixtures.monster("Foe", {"brain": picky})
	var battle: BattleEngine = Fixtures.engine([sturdy, frail], [foe])
	battle.start()
	battle.execute_many([sturdy.id, frail.id])
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(Fixtures.hits(battle, frail.id).size(), 1, "hp_min aims at the lowest HP")
	assert_eq(Fixtures.hits(battle, sturdy.id).size(), 0)


func test_a_party_wipe_is_a_defeat() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"hp": 100, "attack_frames": "4:100"})
	var e1: Combatant = Fixtures.monster("E1", {"atk": 1000})
	var e2: Combatant = Fixtures.monster("E2", {"atk": 1000})
	var battle: BattleEngine = Fixtures.engine([hero], [e1, e2])
	battle.start()
	battle.execute(hero.id)
	assert_true(Fixtures.run_until_ended(battle))
	assert_eq(battle.outcome, BattleEngine.OUTCOME_DEFEAT)
	assert_eq(_enemy_actions(battle).size(), 1, "nobody is left for the second enemy to hit")
	var ended: Dictionary = battle.events.last_of_type(BattleEventLog.BATTLE_ENDED)
	assert_eq(int(ended["frame"]), 46)


func _rule(order: int, conditions: Array, verb: String, skill_index: int) -> Dictionary:
	return {
		"order": order,
		"triggers": [],
		"conditions": conditions,
		"verb": verb,
		"skill_index": skill_index,
		"flg_writes": [],
		"flg2_writes": [],
		"target_mode": "random",
		"target_param": 0,
		"probability": 100.0,
		"raw": "",
	}
