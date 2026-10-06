extends "res://tests/test_case.gd"

## Passives the engine reads at turn end, cast time, targeting and cost time
## (PASSIVES-HANDOVER.md, batch 1): MP and LB per turn, LB fill rate, evasion, aggro and
## the ability MP cut. Combatants come from specs; nothing touches the database.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var catalog: SkillCatalog


func before_each() -> void:
	catalog = Fixtures.catalog()


## A party member whose passives are `passives` (a profile's `passives` dict).
static func _unit(unit_name: String, passives: Dictionary, spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"passives": passives}
	full.merge(spec, true)
	return Fixtures.unit(unit_name, full)


func _one_turn(battle: BattleEngine, actor: Combatant) -> void:
	battle.execute(actor.id)
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)


func test_mp_per_turn_restores_a_percent_of_max_mp() -> void:
	var mage: Combatant = _unit("Mage", {"mp_regen_pct": 10}, {"mp": 200})
	mage.mp = 0
	var battle: BattleEngine = Fixtures.engine([mage], [Fixtures.monster("Foe", {"atk": 0})])
	battle.start()
	_one_turn(battle, mage)
	assert_eq(mage.mp, 20, "10% of 200 at the end of turn 1")


func test_lb_per_turn_is_raised_by_the_fill_rate() -> void:
	var hero: Combatant = _unit("Hero", {"lb_per_turn": 200, "lb_fill_rate_pct": 50}, {"max_lb": 1000})
	var battle: BattleEngine = Fixtures.engine([hero], [Fixtures.monster("Foe", {"atk": 0})])
	battle.start()
	_one_turn(battle, hero)
	assert_eq(hero.lb, 300, "2 crystals x 1.5")
	var changed: Dictionary = battle.events.last_of_type(BattleEventLog.LB_CHANGED)
	assert_eq(str(changed.get("reason", "")), "lb_per_turn")


func test_the_passive_fill_rate_adds_to_fill_rate_statuses_for_crystals() -> void:
	var rules: BattleRules = Fixtures.rules()
	rules.lb_crystal_drop_chance = 1.0
	var hero: Combatant = _unit("Hero", {"lb_fill_rate_pct": 50}, {"max_lb": 10000, "attack_frames": "4:100"})
	hero.add_status(BattleStatus.make(BattleStatus.LB_FILL_RATE, "", 50, 3))
	assert_eq(hero.lb_fill_rate(), 100)
	var battle: BattleEngine = Fixtures.engine([hero], [Fixtures.monster("Foe")], rules)
	battle.start()
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return not battle.events.of_type(BattleEventLog.LB_CRYSTAL_DROPPED).is_empty())
	var dropped: Dictionary = battle.events.last_of_type(BattleEventLog.LB_CRYSTAL_DROPPED)
	assert_eq(int(dropped["amount"]), rules.lb_crystal_amount * 2)


func test_physical_evasion_dodges_enemy_attacks() -> void:
	var dodger: Combatant = _unit("Dodger", {"evade_physical_pct": 100})
	var foe: Combatant = Fixtures.monster("Foe", {"atk": 100})
	var battle: BattleEngine = Fixtures.engine([dodger], [foe])
	battle.start()
	_one_turn(battle, dodger)
	assert_eq(dodger.hp, dodger.max_hp, "no damage taken")
	var missed: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.HIT_MISSED, dodger.id)
	assert_true(missed.size() > 0)
	if not missed.is_empty():
		assert_eq(str(missed[0]["reason"]), "evaded")


func test_evasion_follows_the_attack_type() -> void:
	var battle: BattleEngine = Fixtures.engine([Fixtures.unit("Hero")], [Fixtures.monster("Foe")])
	var physical: Combatant = _unit("Physical", {"evade_physical_pct": 100})
	var magic: Combatant = _unit("Magic", {"evade_magic_pct": 100})
	assert_eq(battle.evasion_miss_reason(physical, BattleSkill.ATTACK_PHYSICAL), &"evaded")
	assert_eq(battle.evasion_miss_reason(physical, BattleSkill.ATTACK_MAGIC), &"")
	assert_eq(battle.evasion_miss_reason(magic, BattleSkill.ATTACK_MAGIC), &"evaded")
	assert_eq(battle.evasion_miss_reason(magic, BattleSkill.ATTACK_PHYSICAL), &"")
	assert_eq(battle.evasion_miss_reason(physical, BattleSkill.ATTACK_HYBRID), &"", "hybrid attacks are not evaded")


func test_evasion_chances_add_up_and_paralysis_stops_them() -> void:
	var battle: BattleEngine = Fixtures.engine([Fixtures.unit("Hero")], [Fixtures.monster("Foe")])
	var half: Combatant = _unit("Half", {"evade_physical_pct": 50})
	var evaded: int = 0
	for _i in range(2000):
		if battle.evasion_miss_reason(half, BattleSkill.ATTACK_PHYSICAL) == &"evaded":
			evaded += 1
	assert_true(evaded > 900 and evaded < 1100, "about half: %d of 2000" % evaded)
	var stuck: Combatant = _unit("Stuck", {"evade_physical_pct": 150})
	stuck.add_status(BattleStatus.make(BattleStatus.AILMENT, "PARALYSIS", 0, 2))
	assert_eq(battle.evasion_miss_reason(stuck, BattleSkill.ATTACK_PHYSICAL), &"", "paralysis stops evasion")


func test_aggro_weights_the_random_target() -> void:
	var battle: BattleEngine = Fixtures.engine([Fixtures.unit("Hero")], [Fixtures.monster("Foe")])
	var bait: Combatant = _unit("Bait", {"aggro_pct": 100})
	var plain: Combatant = _unit("Plain", {})
	var hidden: Combatant = _unit("Hidden", {"aggro_pct": -100})
	var pool: Array[Combatant] = [bait, plain, hidden]
	var picks: Dictionary = {"Bait": 0, "Plain": 0, "Hidden": 0}
	for _i in range(3000):
		picks[battle.weighted_target(pool).name] += 1
	assert_eq(picks["Hidden"], 0, "-100% is never picked")
	assert_true(picks["Bait"] > 1850 and picks["Bait"] < 2150, "weight 2 against 1: %d of 3000" % picks["Bait"])
	var everyone_hidden: Array[Combatant] = [hidden]
	assert_eq(battle.weighted_target(everyone_hidden), hidden, "the only one left is still picked")


func test_the_mp_cut_applies_to_abilities_only() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "910", Fixtures.skill_record("Strike", 1, Fixtures.physical_params(100), "10:100", 1, 1, 20))
	catalog.add_record(BattleSkill.KIND_MAGIC, "911", Fixtures.skill_record("Fire", 15, Fixtures.magic_params(100), "10:100", 1, 1, 20))
	var hero: Combatant = _unit("Hero", {"ability_mp_cut_pct": 50}, {"mp": 100})
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	assert_eq(battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "910", foe.id)), BattleEngine.OK)
	assert_eq(hero.mp, 90, "20 MP at 50% off")
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_MAGIC, "911", foe.id)), BattleEngine.OK)
	assert_eq(hero.mp, 70, "magic pays in full")


func test_a_cheaper_ability_can_be_afforded() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "910", Fixtures.skill_record("Strike", 1, Fixtures.physical_params(100), "10:100", 1, 1, 20))
	var hero: Combatant = _unit("Hero", {"ability_mp_cut_pct": 60}, {"mp": 100})
	hero.mp = 8
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	assert_eq(battle.execute(hero.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "910", foe.id)), BattleEngine.OK, "8 MP covers 20 at 60% off")
	assert_eq(hero.mp, 0)


func test_a_frameless_attack_replacement_keeps_the_units_swing() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "920", {
		"name": "Bloodline", "effects_raw": [[1, 1, 1, Fixtures.physical_params(300)]],
		"attack_frames": [[]], "attack_damage": [[]],
	})
	catalog.add_record(BattleSkill.KIND_ABILITY, "921", Fixtures.skill_record("Framed", 1, Fixtures.physical_params(200), "30:50-40:50"))
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "12:60-20:40"})
	var frameless: BattleSkill = catalog.get_attack_replacement("920", hero.attack_skill)
	assert_eq(Array(frameless.effects[0].hit_frames), [12, 20], "the unit's own swing")
	assert_eq(Array(frameless.effects[0].hit_damage), [60, 40])
	var framed: BattleSkill = catalog.get_attack_replacement("921", hero.attack_skill)
	assert_eq(Array(framed.effects[0].hit_frames), [30, 40], "its own frames")
	assert_null(catalog.get_attack_replacement("999", hero.attack_skill))


func test_the_attack_command_runs_the_replacement_for_free() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "921", Fixtures.skill_record("Framed", 1, Fixtures.physical_params(200), "10:100", 1, 1, 30))
	var hero: Combatant = Fixtures.unit("Hero", {"mp": 50})
	hero.attack_skill = catalog.get_attack_replacement("921", hero.attack_skill)
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	assert_eq(battle.execute(hero.id), BattleEngine.OK)
	Fixtures.run_until(battle, func() -> bool: return not Fixtures.hits(battle, foe.id).is_empty())
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [200], "the replacement's 200% modifier")
	assert_eq(hero.mp, 50, "an attack costs no MP, whatever the ability's cost")
