extends "res://tests/test_case.gd"

## Weapon inflicts (WeaponInflict): the ailments a party member's weapons put on the
## targets of its physical and hybrid damage, rolled once per target per action after
## its last hit there. Enemy recovery rolls are off, so results do not depend on the seed.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var catalog: SkillCatalog


func before_each() -> void:
	catalog = Fixtures.catalog()
	catalog.add_record(BattleSkill.KIND_ABILITY, "10", Fixtures.record("Slash", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", {"attack_type": BattleSkill.ATTACK_PHYSICAL}))
	catalog.add_record(BattleSkill.KIND_ABILITY, "11", Fixtures.record("Sweep", [[2, 1, 1, Fixtures.physical_params(100)]], "10:50-20:50", {"attack_type": BattleSkill.ATTACK_PHYSICAL}))
	catalog.add_record(BattleSkill.KIND_ABILITY, "12", Fixtures.record("Hybrid Slash", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", {"attack_type": BattleSkill.ATTACK_HYBRID}))
	catalog.add_record(BattleSkill.KIND_MAGIC, "15", Fixtures.skill_record("Blast", 15, Fixtures.magic_params(100), "10:100"))


func _engine(party: Array, foes: Array) -> BattleEngine:
	var rules: BattleRules = Fixtures.rules()
	rules.enemy_ailment_recovery_pct = 0
	return Fixtures.engine(party, foes, rules, catalog)


## An enemy that passes its turns.
func _idle(monster_name: String, spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"brain": IdleEnemyBrain.new()}
	full.merge(spec, true)
	return Fixtures.monster(monster_name, full)


## Runs until `actions` actions have ended (each ends after its last hit).
func _settle(battle: BattleEngine, actions: int = 1) -> void:
	assert_true(Fixtures.run_until(battle, func() -> bool:
		return battle.events.of_type(BattleEventLog.ACTION_ENDED).size() >= actions), "the actions finish")


## The ailment keys rolled on `target_id` (landed or resisted), sorted.
func _rolled(battle: BattleEngine, target_id: int) -> Array:
	var keys: Array = []
	for type in [BattleEventLog.STATUS_ADDED, BattleEventLog.STATUS_RESISTED]:
		for event in Fixtures.events_on(battle, type, target_id):
			if event["kind"] == BattleStatus.AILMENT:
				keys.append(str(event["key"]))
	keys.sort()
	return keys


func _has(fighter: Combatant, key: String) -> bool:
	return fighter.find_status(BattleStatus.AILMENT, key) != null


func test_a_basic_attack_inflicts_after_its_last_hit() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:50-12:50", "weapon_inflicts": {"SLEEP": 100}})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(hits.size(), 2)
	var added: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.STATUS_ADDED, foe.id)
	assert_eq(added.size(), 1)
	if added.size() == 1 and hits.size() == 2:
		assert_eq(added[0]["key"], "SLEEP")
		assert_eq(int(added[0]["frame"]), int(hits[1]["frame"]), "on the second hit")
		assert_eq(int(added[0]["action"]), int(hits[1]["action"]))
	assert_true(_has(foe, "SLEEP"), "its own second hit does not wake the foe")
	assert_eq(Fixtures.events_on(battle, BattleEventLog.STATUS_REMOVED, foe.id), [])


func test_each_ailment_rolls_once_per_target_per_action() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "4:30-8:30-12:40", "weapon_inflicts": {"POISON": 50, "BLIND": 50}})
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	assert_eq(Fixtures.hits(battle, foe.id).size(), 3)
	assert_eq(_rolled(battle, foe.id), ["BLIND", "POISON"], "one roll each for three hits")


func test_resistance_counts_against_the_chance() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"weapon_inflicts": {"SLEEP": 100, "POISON": 100}})
	var foe: Combatant = _idle("Foe", {"ailment_resist": {"SLEEP": 100}})
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	var resisted: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.STATUS_RESISTED, foe.id)
	assert_eq(resisted.size(), 1)
	if resisted.size() == 1:
		assert_eq([resisted[0]["key"], resisted[0]["reason"]], ["SLEEP", &"resisted"])
	assert_false(_has(foe, "SLEEP"))
	assert_true(_has(foe, "POISON"))


func test_physical_and_hybrid_skills_carry_them_and_magic_does_not() -> void:
	var inflicts: Dictionary = {"weapon_inflicts": {"POISON": 100}}
	var knight: Combatant = Fixtures.unit("Knight", inflicts)
	var lancer: Combatant = Fixtures.unit("Lancer", inflicts)
	var mage: Combatant = Fixtures.unit("Mage", inflicts)
	var slashed: Combatant = _idle("Slashed")
	var hybrid: Combatant = _idle("Hybrid")
	var blasted: Combatant = _idle("Blasted")
	var battle: BattleEngine = _engine([knight, lancer, mage], [slashed, hybrid, blasted])
	battle.start()
	battle.execute(knight.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "10", slashed.id))
	battle.execute(lancer.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "12", hybrid.id))
	battle.execute(mage.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "15", blasted.id))
	_settle(battle, 3)
	assert_true(_has(slashed, "POISON"), "a physical ability")
	assert_true(_has(hybrid, "POISON"), "a hybrid ability")
	assert_eq(Fixtures.hits(battle, blasted.id).size(), 1, "the magic landed")
	assert_eq(_rolled(battle, blasted.id), [], "magic carries no weapon inflict")


func test_an_aoe_attack_rolls_once_on_every_target() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"weapon_inflicts": {"POISON": 100}})
	var foes: Array = [_idle("Foe 1"), _idle("Foe 2")]
	var battle: BattleEngine = _engine([hero], foes)
	battle.start()
	battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "11", (foes[0] as Combatant).id))
	_settle(battle)
	for foe: Combatant in foes:
		assert_eq(Fixtures.hits(battle, foe.id).size(), 2, foe.name)
		assert_eq(_rolled(battle, foe.id), ["POISON"], foe.name)


func test_an_evaded_attack_inflicts_nothing() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"weapon_inflicts": {"POISON": 100}})
	var foe: Combatant = _idle("Foe", {"passives": {"evade_physical_pct": 100}})
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	assert_eq(Fixtures.hits(battle, foe.id), [], "evaded")
	assert_eq(_rolled(battle, foe.id), [])


func test_a_killing_hit_inflicts_nothing() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"weapon_inflicts": {"POISON": 100}})
	var foe: Combatant = _idle("Foe", {"hp": 1})
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	assert_false(foe.is_alive())
	assert_eq(_rolled(battle, foe.id), [])


func test_a_combatant_without_inflicting_weapons_inflicts_nothing() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = _idle("Foe")
	var battle: BattleEngine = _engine([hero], [foe])
	battle.start()
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	_settle(battle)
	assert_eq(Fixtures.hits(battle, foe.id).size(), 1)
	assert_eq(_rolled(battle, foe.id), [])
