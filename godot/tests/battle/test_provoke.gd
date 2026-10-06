extends "res://tests/test_case.gd"

## Provoke (active opcode 61): a status that makes an enemy's random single-target pick
## go to its bearer. The user's rules (2026-10-06): the chance is the provoke plus the
## bearer's passive aggro, capped at 100; provokers roll highest chance first, the most
## recent provoke first on a tie; when no roll lands, the aggro-weighted pick runs.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var catalog: SkillCatalog


## Returns the same decision once per turn.
class FixedBrain:
	extends EnemyBrain
	var decision: Dictionary = {}

	func next_action(_ctx: Dictionary) -> Dictionary:
		if _attacks_left <= 0:
			return turn_over("done")
		_attacks_left -= 1
		return decision


func before_each() -> void:
	catalog = Fixtures.catalog()
	# Provoke on the caster, as most rows have it (area 0, target 3), and on one ally.
	catalog.add_record(BattleSkill.KIND_ABILITY, "61", Fixtures.record("Provoke", [[0, 3, 61, [100, 3]]], "4:100"))
	catalog.add_record(BattleSkill.KIND_ABILITY, "62", Fixtures.record("Mist Decoy", [[1, 2, 61, [50, 2]]], "4:100"))


func _provoke(fighter: Combatant, pct: int) -> void:
	fighter.add_status(BattleStatus.make(BattleStatus.PROVOKE, "", pct, 3))


func _cast(battle: BattleEngine, actor: Combatant, skill_id: String, target: Combatant = null) -> StringName:
	return battle.execute(actor.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, skill_id, target.id if target != null else -1))


## How often each pool member is picked in `rolls` random picks, by name.
func _picks(battle: BattleEngine, pool: Array[Combatant], rolls: int) -> Dictionary:
	var counts: Dictionary = {}
	for member in pool:
		counts[member.name] = 0
	for _i in range(rolls):
		counts[battle.random_target(pool).name] += 1
	return counts


func test_provoke_puts_a_buff_on_its_target() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var friend: Combatant = Fixtures.unit("Friend")
	var bait: Combatant = Fixtures.unit("Bait")
	var battle: BattleEngine = Fixtures.engine([tank, friend, bait], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	assert_eq(_cast(battle, tank, "61"), BattleEngine.OK)
	assert_eq(_cast(battle, friend, "62", bait), BattleEngine.OK)
	battle.advance(10)
	var own: BattleStatus = tank.find_status(BattleStatus.PROVOKE)
	assert_not_null(own, "the caster provokes")
	if own != null:
		assert_eq(own.value, 100)
		assert_eq(own.turns_left, 3)
		assert_false(own.is_debuff(), "a buff, so dispel removes it")
	assert_eq(bait.status_value(BattleStatus.PROVOKE), 50, "the picked ally provokes")
	assert_null(friend.find_status(BattleStatus.PROVOKE), "not the caster of an ally provoke")


func test_the_chance_adds_passive_aggro_and_stays_within_0_and_100() -> void:
	var plain: Combatant = Fixtures.unit("Plain")
	_provoke(plain, 50)
	assert_eq(plain.provoke_chance(), 50)
	var drawn: Combatant = Fixtures.unit("Drawn", {"passives": {"aggro_pct": 30}})
	_provoke(drawn, 50)
	assert_eq(drawn.provoke_chance(), 80, "50 + 30 passive")
	var capped: Combatant = Fixtures.unit("Capped", {"passives": {"aggro_pct": 50}})
	_provoke(capped, 80)
	assert_eq(capped.provoke_chance(), 100, "80 + 50 capped at 100")
	var hiding: Combatant = Fixtures.unit("Hiding", {"passives": {"aggro_pct": -50}})
	_provoke(hiding, 20)
	assert_eq(hiding.provoke_chance(), 0, "20 - 50 floors at 0")
	var passive_only: Combatant = Fixtures.unit("Passive", {"passives": {"aggro_pct": 100}})
	assert_eq(passive_only.provoke_chance(), 0, "passive aggro alone only weighs the roll")


func test_full_provoke_draws_every_random_pick() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var a: Combatant = Fixtures.unit("A", {"passives": {"aggro_pct": 100}})
	var b: Combatant = Fixtures.unit("B")
	var battle: BattleEngine = Fixtures.engine([a, tank, b], [Fixtures.monster("Foe")])
	_provoke(tank, 100)
	var counts: Dictionary = _picks(battle, [a, tank, b], 500)
	assert_eq(counts["Tank"], 500, "100% always lands")


func test_a_partial_provoke_falls_back_to_the_weighted_pick() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var other: Combatant = Fixtures.unit("Other")
	var battle: BattleEngine = Fixtures.engine([tank, other], [Fixtures.monster("Foe")])
	_provoke(tank, 50)
	var counts: Dictionary = _picks(battle, [tank, other], 4000)
	# 50% from the provoke roll, then half of the other 50% from the even pick: 75%.
	assert_true(counts["Tank"] > 2850 and counts["Tank"] < 3150, "about 75%%: %d of 4000" % counts["Tank"])


func test_the_highest_chance_rolls_first() -> void:
	var strong: Combatant = Fixtures.unit("Strong")
	var weak: Combatant = Fixtures.unit("Weak")
	var battle: BattleEngine = Fixtures.engine([weak, strong], [Fixtures.monster("Foe")])
	_provoke(weak, 80)
	_provoke(strong, 100)
	strong.find_status(BattleStatus.PROVOKE).added_order = 1
	weak.find_status(BattleStatus.PROVOKE).added_order = 2
	var counts: Dictionary = _picks(battle, [weak, strong], 300)
	assert_eq(counts["Strong"], 300, "100 rolls before 80, even though 80 is more recent")


func test_the_most_recent_provoke_wins_a_tie() -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, "63", Fixtures.record("Provoke", [[0, 3, 61, [100, 3]]], "8:100"))
	var first: Combatant = Fixtures.unit("First")
	var second: Combatant = Fixtures.unit("Second")
	var battle: BattleEngine = Fixtures.engine([first, second], [Fixtures.monster("Foe")], null, catalog)
	battle.start()
	# The first one to cast lands later (frame 8 against 4), so its provoke is the newer.
	_cast(battle, first, "63")
	_cast(battle, second, "61")
	battle.advance(10)
	assert_true(first.find_status(BattleStatus.PROVOKE).added_order > second.find_status(BattleStatus.PROVOKE).added_order)
	var counts: Dictionary = _picks(battle, [second, first], 300)
	assert_eq(counts["First"], 300, "the newer provoke rolls first")


func test_enemies_attack_the_provoker() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var a: Combatant = Fixtures.unit("A")
	var b: Combatant = Fixtures.unit("B")
	var brain := EnemyBrain.new()
	brain.attacks_per_turn = 5
	var foe: Combatant = Fixtures.monster("Foe", {"brain": brain})
	var battle: BattleEngine = Fixtures.engine([a, tank, b], [foe], null, catalog)
	battle.start()
	_cast(battle, tank, "61")
	battle.execute(a.id, BattleCommand.defend())
	battle.execute(b.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(Fixtures.hits(battle, tank.id).size(), 5, "every basic attack went to the provoker")
	assert_eq(Fixtures.hits(battle, a.id).size() + Fixtures.hits(battle, b.id).size(), 0)


func test_a_monster_can_make_a_party_member_the_target() -> void:
	# "The enemy gazes at you...": 200% provoke on one party member.
	catalog.add_record(BattleSkill.KIND_MONSTER, "900523", Fixtures.record("Gaze", [[1, 1, 61, [200, 3]]], "4:100"))
	var hero: Combatant = Fixtures.unit("Hero")
	var brain := FixedBrain.new()
	brain.decision = EnemyBrain.action(EnemyBrain.KIND_SKILL, "900523")
	var battle: BattleEngine = Fixtures.engine([hero], [Fixtures.monster("Watcher", {"brain": brain})], null, catalog)
	battle.start()
	battle.execute(hero.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(hero.status_value(BattleStatus.PROVOKE), 200)
	assert_eq(hero.provoke_chance(), 100, "200 counts as 100")
