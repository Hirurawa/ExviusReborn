extends "res://tests/test_case.gd"

## Counters (Counters): passives 12, 41 (the normal attack), 49, 50 (a skill), 20 (chance
## boost) and the COUNTER statuses of actives 119 and 123. The wiki's rules (2026-10-06):
## sustaining physical or magic damage triggers them, evading still counts, chances from
## different sources add up but give one counter per attack. Counters roll when the
## attack ends and run in the next turn's opening phase (REACTIONS-PLAN.md, Q1).

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

## Monster skills.
const SLAM: String = "1"
const FIRA: String = "2"
const HYBRID: String = "3"
const TRIPLE: String = "4"
const QUAKE: String = "5"
const BREAK: String = "6"
const SLEEPGA: String = "7"
## Party abilities.
const HEAL_ALL: String = "10"
const ANTAGONIZE: String = "11"
const AVOID: String = "12"
const POWER_UP: String = "13"

var catalog: SkillCatalog


## Attacks with `decisions` in order, one per action, every turn.
class ScriptBrain:
	extends EnemyBrain
	var decisions: Array = []
	var _next: int = 0

	func begin_turn(_ctx: Dictionary) -> void:
		_next = 0

	func next_action(_ctx: Dictionary) -> Dictionary:
		if _next >= decisions.size():
			return turn_over("done")
		_next += 1
		return decisions[_next - 1]

	func is_turn_over() -> bool:
		return _next >= decisions.size()


func before_each() -> void:
	catalog = Fixtures.catalog()
	var physical: Dictionary = {"attack_type": BattleSkill.ATTACK_PHYSICAL}
	var magic: Dictionary = {"attack_type": BattleSkill.ATTACK_MAGIC}
	_monster(SLAM, Fixtures.record("Slam", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	_monster(FIRA, Fixtures.record("Fira", [[1, 1, 15, Fixtures.magic_params(100)]], "10:100", magic))
	_monster(HYBRID, Fixtures.record("Hybrid", [[1, 1, 40, [0, 0, 0, 0, 0, 0, 0, 0, 100, 100]]], "10:100", {"attack_type": BattleSkill.ATTACK_HYBRID}))
	_monster(TRIPLE, Fixtures.record("Triple", [[1, 1, 1, Fixtures.physical_params(100)]], "10:33-20:33-30:34", physical))
	_monster(QUAKE, Fixtures.record("Quake", [[2, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	_monster(BREAK, Fixtures.record("Break", [[1, 1, 24, [-50, 0, 0, 0, 3]]], "10:100", physical))
	_monster(SLEEPGA, Fixtures.record("Sleep", [[1, 1, 6, [0, 0, 100, 0, 0, 0, 0, 0, 1]]], "10:100", magic))
	_ability(HEAL_ALL, Fixtures.record("Heal All", [[2, 2, 2, [0, 0, 500, 0]]], "10:100"))
	_ability(ANTAGONIZE, Fixtures.record("Antagonize", [[0, 3, 123, [50, 1, 150, 5, 1]]], ""))
	_ability(AVOID, Fixtures.record("Avoid", [[0, 3, 119, [50, 1, 1000, 2, 1, 0]]], ""))
	_ability(POWER_UP, Fixtures.record("Power Up", [[0, 3, 3, [100, 0, 0, 0, 1]]], ""))


func _monster(id: String, data: Dictionary) -> void:
	catalog.add_record(BattleSkill.KIND_MONSTER, id, data)


func _ability(id: String, data: Dictionary) -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, id, data)


## One CombatantPassives.counters entry.
static func _counter(trigger: String, chance: int, cap: int = 0, modifier: int = 0, skill_kind: StringName = BattleSkill.KIND_ATTACK, skill_id: String = "") -> Dictionary:
	return {
		"trigger": trigger, "chance": chance, "modifier": modifier, "max": cap, "skill_kind": skill_kind, "skill_id": skill_id,
		"source_skill_id": "900",
	}


## A unit with `counters`; `passives` adds other passive totals, `spec` the rest.
static func _counterer(unit_name: String, counters: Array, spec: Dictionary = {}, passives: Dictionary = {}) -> Combatant:
	var totals: Dictionary = {"counters": counters}
	totals.merge(passives, true)
	var full: Dictionary = {"passives": totals}
	full.merge(spec, true)
	return Fixtures.unit(unit_name, full)


## A monster acting `decisions` each turn; each is [skill id or "" for the basic attack,
## the party slot it aims at or -1 for a random member].
static func _attacker(foe_name: String, decisions: Array, spec: Dictionary = {}) -> Combatant:
	var brain := ScriptBrain.new()
	for decision in decisions:
		var skill_id: String = str(decision[0])
		var kind: String = EnemyBrain.KIND_SKILL if skill_id != "" else EnemyBrain.KIND_ATTACK
		var slot: int = int(decision[1])
		brain.decisions.append(EnemyBrain.action(kind, skill_id, "disp_order" if slot >= 0 else "random", slot))
	var full: Dictionary = {"brain": brain}
	full.merge(spec, true)
	return Fixtures.monster(foe_name, full)


static func _counters_queued(battle: BattleEngine, actor_id: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in battle.events.of_type(BattleEventLog.COUNTER_QUEUED):
		if actor_id < 0 or int(event["actor"]) == actor_id:
			out.append(event)
	return out


static func _counter_actions(battle: BattleEngine, actor_id: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in Fixtures.actions_by(battle, actor_id):
		if StringName(event.get("reaction", &"")) == Reaction.COUNTER:
			out.append(event)
	return out


## Every living member defends, then the battle runs to the next turn's player phase.
static func _next_turn(battle: BattleEngine) -> void:
	var turn: int = battle.turn
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	for member in battle.units_to_act():
		battle.execute(member.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.phase == BattleEngine.Phase.ENDED \
		or (battle.turn > turn and battle.phase == BattleEngine.Phase.PLAYER), 5000)


## An attack by `foe` that `sustained` took ({ id: Counters bits }), for rolling directly.
static func _attack_on(foe: Combatant, sustained: Dictionary) -> BattleAction:
	var action := BattleAction.new()
	action.id = 999
	action.actor_id = foe.id
	action.origin = BattleAction.Origin.AI
	action.sustained = sustained
	return action


func test_a_physical_attack_is_countered_in_the_next_turns_opening() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 100)])
	var foe: Combatant = _attacker("Foe", [["", -1]])
	var battle: BattleEngine = Fixtures.engine([guard], [foe], null, catalog)
	battle.start()
	battle.execute(guard.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.turn == 2)
	assert_eq(battle.phase, BattleEngine.Phase.OPENING)
	var attack: Dictionary = Fixtures.actions_by(battle, foe.id)[0]
	var queued: Array[Dictionary] = _counters_queued(battle)
	var turn_ended: Dictionary = battle.events.last_of_type(BattleEventLog.TURN_ENDED)
	assert_eq(queued.size(), 1)
	if queued.size() == 1:
		assert_eq([int(queued[0]["attacker"]), int(queued[0]["action"]), int(queued[0]["chance"])], [foe.id, int(attack["action"]), 100])
		assert_eq(int(queued[0]["frame"]), int(battle.events.of_type(BattleEventLog.ACTION_ENDED).filter(
			func(event: Dictionary) -> bool: return int(event["action"]) == int(attack["action"]))[0]["frame"]), "rolled when the attack ends")
		assert_true(int(queued[0]["seq"]) < int(turn_ended["seq"]), "in the enemy phase")
	var counters: Array[Dictionary] = _counter_actions(battle, guard.id)
	assert_eq(counters.size(), 1, "runs as the next turn opens")
	if counters.size() == 1:
		assert_eq([int(counters[0]["origin"]), int(counters[0]["kind"]), int(counters[0]["trigger_action"])],
			[BattleAction.Origin.REACTION, BattleCommand.Kind.ATTACK, int(attack["action"])])
		assert_true(int(counters[0]["seq"]) > int(battle.events.last_of_type(BattleEventLog.TURN_STARTED)["seq"]),
			"after the turn's countdown and the new turn's start")
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	assert_eq(Fixtures.hits(battle, foe.id).size(), 1, "the counter hit the attacker")
	assert_false(guard.acted)


func test_evaded_and_dodged_attacks_still_count() -> void:
	var evader: Combatant = _counterer("Evader", [_counter("physical", 100)], {}, {"evade_physical_pct": 100})
	var dodger: Combatant = _counterer("Dodger", [_counter("physical", 100)])
	dodger.add_status(BattleStatus.make(BattleStatus.DODGE, "", 1, 3))
	var foe: Combatant = _attacker("Foe", [["", 0], ["", 1]])
	var battle: BattleEngine = Fixtures.engine([evader, dodger], [foe], null, catalog)
	battle.start()
	_next_turn(battle)
	assert_eq(Fixtures.hits(battle, evader.id).size() + Fixtures.hits(battle, dodger.id).size(), 0, "both missed")
	assert_eq(_counters_queued(battle, evader.id).size(), 1, "evaded")
	assert_eq(_counters_queued(battle, dodger.id).size(), 1, "dodged")


func test_a_multi_hit_attack_gives_one_roll_and_an_aoe_one_per_unit() -> void:
	var a: Combatant = _counterer("A", [_counter("physical", 100)])
	var b: Combatant = _counterer("B", [_counter("physical", 100)])
	var foe: Combatant = _attacker("Foe", [[TRIPLE, 0], [QUAKE, -1]], {"atk": 1})
	var battle: BattleEngine = Fixtures.engine([a, b], [foe], null, catalog)
	battle.start()
	_next_turn(battle)
	assert_eq(Fixtures.hits(battle, a.id).size(), 4, "three hits, then the AoE")
	assert_eq(_counters_queued(battle, a.id).size(), 2, "one per attack, not per hit")
	assert_eq(_counters_queued(battle, b.id).size(), 1, "its own roll for the AoE")


func test_chances_add_up_and_the_roll_picks_the_source() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 30), _counter("physical", 20, 0, 0, BattleSkill.KIND_ABILITY, HEAL_ALL)])
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([guard], [foe], null, catalog)
	var by_source: Dictionary = {BattleSkill.KIND_ATTACK: 0, BattleSkill.KIND_ABILITY: 0}
	for _i in range(2000):
		Counters.on_attack_ended(battle, _attack_on(foe, {guard.id: Counters.PHYSICAL}))
	for event in _counters_queued(battle):
		by_source[StringName(event["skill_kind"])] += 1
		assert_eq(int(event["chance"]), 50)
	var total: int = by_source[BattleSkill.KIND_ATTACK] + by_source[BattleSkill.KIND_ABILITY]
	assert_true(total > 900 and total < 1100, "about 50%%: %d of 2000" % total)
	assert_true(by_source[BattleSkill.KIND_ATTACK] > by_source[BattleSkill.KIND_ABILITY] * 1.2, "30 against 20: %s" % by_source)
	assert_eq(battle.queued_reactions().size(), total, "one counter per success")


func test_chances_over_100_always_counter_and_share_the_roll() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 80), _counter("physical", 80, 0, 0, BattleSkill.KIND_ABILITY, HEAL_ALL)])
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([guard], [foe], null, catalog)
	for _i in range(400):
		Counters.on_attack_ended(battle, _attack_on(foe, {guard.id: Counters.PHYSICAL}))
	var queued: Array[Dictionary] = _counters_queued(battle)
	assert_eq(queued.size(), 400)
	var attacks: int = queued.filter(func(event: Dictionary) -> bool: return StringName(event["skill_kind"]) == BattleSkill.KIND_ATTACK).size()
	assert_true(attacks > 150 and attacks < 250, "an even split: %d of 400" % attacks)


func test_op_20_multiplies_every_chance() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 30), _counter("magic", 25)], {}, {"counter_chance_pct": 100})
	guard.add_status(BattleStatus.make(BattleStatus.COUNTER, Counters.KEY_SELF, 20, 3, {"modifier": 0, "max": 0}))
	var chances: Array = Counters.sources(guard, Counters.PHYSICAL, false).map(func(source: Dictionary) -> int: return int(source["chance"]))
	assert_eq(chances, [60, 40], "the physical passive doubled, then the status doubled")


func test_physical_magic_and_hybrid_attacks_reach_their_sources() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 10), _counter("magic", 20)])
	guard.add_status(BattleStatus.make(BattleStatus.COUNTER, Counters.KEY_SELF, 30, 3, {"modifier": 0, "max": 0}))
	guard.add_status(BattleStatus.make(BattleStatus.COUNTER, Counters.KEY_ALLY, 40, 3, {"modifier": 0, "max": 0}))
	var chances: Callable = func(own: int, ally: bool) -> Array:
		return Counters.sources(guard, own, ally).map(func(source: Dictionary) -> int: return int(source["chance"]))
	assert_eq(chances.call(Counters.PHYSICAL, false), [10, 30])
	assert_eq(chances.call(Counters.MAGIC, false), [20], "119 answers physical attacks only")
	assert_eq(chances.call(Counters.PHYSICAL | Counters.MAGIC, false), [10, 20, 30], "hybrid reaches both")
	assert_eq(chances.call(0, true), [40], "123 answers attacks on another ally")
	assert_eq(chances.call(Counters.PHYSICAL, true), [10, 30, 40], "own and ally triggers share the one roll")


func test_magic_and_hybrid_attacks_in_battle() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("magic", 100, 0, 0, BattleSkill.KIND_ABILITY, HEAL_ALL)])
	var foe: Combatant = _attacker("Foe", [[SLAM, 0], [FIRA, 0], [HYBRID, 0]], {"atk": 1, "mag": 1})
	var battle: BattleEngine = Fixtures.engine([guard], [foe], null, catalog)
	battle.start()
	_next_turn(battle)
	var answered: Array = _counters_queued(battle).map(func(event: Dictionary) -> int: return int(event["action"]))
	var attacks: Array = Fixtures.actions_by(battle, foe.id).map(func(event: Dictionary) -> int: return int(event["action"]))
	assert_eq(answered, attacks.slice(1), "the magic and the hybrid attack, not the physical one")
	assert_eq(_counter_actions(battle, guard.id).size(), 2)
	assert_false(Fixtures.events_on(battle, BattleEventLog.RESTORED, guard.id).is_empty(), "a counter can heal the party")


func test_a_skill_without_damage_triggers_nothing() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 100)])
	var battle: BattleEngine = Fixtures.engine([guard], [_attacker("Foe", [[BREAK, 0]])], null, catalog)
	battle.start()
	_next_turn(battle)
	assert_true(guard.status_value(BattleStatus.STAT, "ATK") < 0, "the break landed")
	assert_eq(_counters_queued(battle).size(), 0)


func test_the_cap_stops_a_source_for_the_turn() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 100, 2)])
	var foe: Combatant = _attacker("Foe", [["", 0], ["", 0], ["", 0]], {"atk": 1})
	var battle: BattleEngine = Fixtures.engine([guard], [foe], null, catalog)
	battle.start()
	_next_turn(battle)
	assert_eq(_counters_queued(battle).size(), 2, "the third attack finds the cap reached")
	_next_turn(battle)
	assert_eq(_counters_queued(battle).size(), 4, "two more the next turn")
	assert_eq(_counter_actions(battle, guard.id).size(), 4)


func test_the_coverer_counters_and_the_covered_ally_does_not() -> void:
	var tank: Combatant = _counterer("Tank", [_counter("physical", 100)])
	var ward: Combatant = _counterer("Ward", [_counter("physical", 100)])
	tank.add_status(BattleStatus.make(BattleStatus.COVER, CoverTracker.KEY_AOE, 100, 3, {
		"mit_min": 0, "mit_max": 0, "physical": true, "magic": false, "protects": -1, "condition": CoverTracker.CONDITION_ANY,
	}))
	var battle: BattleEngine = Fixtures.engine([tank, ward], [_attacker("Foe", [["", 1]], {"atk": 1})], null, catalog)
	battle.start()
	_next_turn(battle)
	assert_eq(Fixtures.hits(battle, tank.id).size(), 1, "covered")
	assert_eq(_counters_queued(battle, tank.id).size(), 1)
	assert_eq(_counters_queued(battle, ward.id).size(), 0)


func test_a_unit_ko_d_by_the_attack_or_later_does_not_counter() -> void:
	var frail: Combatant = _counterer("Frail", [_counter("physical", 100)], {"hp": 1})
	var later: Combatant = _counterer("Later", [_counter("physical", 100)], {"hp": 1})
	later.add_status(BattleStatus.make(BattleStatus.DODGE, "", 1, 3))
	later.add_status(BattleStatus.make(BattleStatus.AUTO_REVIVE, "", 100, 3))
	var other: Combatant = Fixtures.unit("Other", {"hp": 99999})
	# Frail dies to the first attack; Later dodges the second (a counter is queued) and
	# dies to the third, then gets back up through its reraise.
	var foe: Combatant = _attacker("Foe", [["", 0], ["", 1], ["", 1]], {"atk": 500})
	var battle: BattleEngine = Fixtures.engine([frail, later, other], [foe], null, catalog)
	battle.start()
	_next_turn(battle)
	assert_false(frail.is_alive())
	assert_true(later.is_alive(), "reraised")
	assert_eq(_counters_queued(battle, frail.id).size(), 0, "KO'd by the attack")
	assert_eq(_counters_queued(battle, later.id).size(), 1, "the dodged attack")
	var dropped: Array[Dictionary] = battle.events.of_type(BattleEventLog.REACTION_DROPPED)
	assert_eq(dropped.map(func(event: Dictionary) -> Array: return [int(event["actor"]), event["reason"]]), [[later.id, &"caster_down"]],
		"its counter died with it, reraise or not")
	assert_eq(_counter_actions(battle).size(), 0)


func test_a_unit_that_cannot_act_loses_its_counter() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 100)])
	var hitter: Combatant = _attacker("Hitter", [["", 0]], {"atk": 1})
	var sleeper: Combatant = _attacker("Sleeper", [[SLEEPGA, 0]])
	var battle: BattleEngine = Fixtures.engine([guard, Fixtures.unit("Other")], [hitter, sleeper], null, catalog)
	battle.start()
	_next_turn(battle)
	assert_true(guard.has_ailment("SLEEP"), "asleep since the enemy phase")
	assert_eq(_counters_queued(battle, guard.id).size(), 1)
	var dropped: Dictionary = battle.events.last_of_type(BattleEventLog.REACTION_DROPPED)
	assert_eq([int(dropped.get("actor", -1)), dropped.get("reason")], [guard.id, &"cannot_act"])
	assert_eq(_counter_actions(battle).size(), 0)


func test_a_counter_whose_attacker_fell_takes_another_opponent() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 100)])
	var first: Combatant = _attacker("First", [["", 0]], {"atk": 1})
	var second: Combatant = Fixtures.monster("Second", {"brain": IdleEnemyBrain.new()})
	var battle: BattleEngine = Fixtures.engine([guard], [first, second], null, catalog)
	battle.start()
	battle.execute(guard.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return not _counters_queued(battle).is_empty())
	battle.debug_edit(first.id, &"hp", 0)
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER, 3000)
	assert_eq(Fixtures.hits(battle, second.id).size(), 1)


func test_a_counter_that_ends_the_battle_drops_the_rest() -> void:
	var a: Combatant = _counterer("A", [_counter("physical", 100)], {"atk": 5000})
	var b: Combatant = _counterer("B", [_counter("physical", 100)], {"atk": 5000})
	var foe: Combatant = _attacker("Foe", [[QUAKE, -1]], {"atk": 1, "hp": 10})
	var battle: BattleEngine = Fixtures.engine([a, b], [foe], null, catalog)
	battle.start()
	_next_turn(battle)
	assert_eq(battle.outcome, BattleEngine.OUTCOME_VICTORY)
	assert_eq(_counter_actions(battle).size(), 1)
	var dropped: Dictionary = battle.events.last_of_type(BattleEventLog.REACTION_DROPPED)
	assert_eq([int(dropped.get("actor", -1)), dropped.get("reason")], [b.id, &"battle_over"])


func test_counters_and_other_reactions_are_not_countered() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 100)])
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([guard], [foe], null, catalog)
	var reaction := BattleAction.new()
	reaction.actor_id = foe.id
	reaction.origin = BattleAction.Origin.REACTION
	var hit := ScheduledHit.new()
	hit.action = reaction
	hit.actor_id = foe.id
	hit.target_id = guard.id
	hit.attack_type = BattleSkill.ATTACK_PHYSICAL
	Counters.note_sustained(battle, hit)
	assert_true(reaction.sustained.is_empty())
	reaction.origin = BattleAction.Origin.AI
	Counters.note_sustained(battle, hit)
	assert_eq(reaction.sustained, {guard.id: Counters.PHYSICAL})


func test_the_modifier_scales_the_counters_attack() -> void:
	var plain: Combatant = _counterer("Plain", [_counter("physical", 100)])
	var strong: Combatant = _counterer("Strong", [_counter("physical", 100, 0, 200)])
	var foe: Combatant = _attacker("Foe", [[QUAKE, -1]], {"atk": 1})
	var battle: BattleEngine = Fixtures.engine([plain, strong], [foe], null, catalog)
	battle.start()
	_next_turn(battle)
	var plain_hits: Array[int] = Fixtures.amounts(Fixtures.hits(battle, foe.id).filter(func(hit: Dictionary) -> bool: return int(hit["actor"]) == plain.id))
	var strong_hits: Array[int] = Fixtures.amounts(Fixtures.hits(battle, foe.id).filter(func(hit: Dictionary) -> bool: return int(hit["actor"]) == strong.id))
	assert_eq(plain_hits.size(), 1)
	assert_eq(strong_hits.size(), 1)
	if plain_hits.size() == 1 and strong_hits.size() == 1:
		assert_true(plain_hits[0] > 0)
		assert_eq(strong_hits[0], plain_hits[0] * 2, "200% of the plain attack")


func test_a_dual_wielders_counter_swings_twice() -> void:
	var dual: Combatant = _counterer("Dual", [_counter("physical", 100)], {"atk": 350, "hand_atk": [100, 50]})
	var foe: Combatant = _attacker("Foe", [["", 0]], {"atk": 1})
	var battle: BattleEngine = Fixtures.engine([dual], [foe], null, catalog)
	battle.start()
	_next_turn(battle)
	var counters: Array[Dictionary] = _counter_actions(battle, dual.id)
	assert_eq(counters.size(), 1)
	if counters.size() == 1:
		assert_true(bool(counters[0]["dual_wield"]))
	assert_eq(Fixtures.hits(battle, foe.id).size(), 2)


func test_ally_counters_answer_attacks_on_other_allies() -> void:
	var bait: Combatant = Fixtures.unit("Bait")
	var keeper: Combatant = Fixtures.unit("Keeper")
	keeper.add_status(BattleStatus.make(BattleStatus.COUNTER, Counters.KEY_ALLY, 100, 3, {"modifier": 150, "max": 1}))
	var foe: Combatant = _attacker("Foe", [["", 0], ["", 1], ["", 0]], {"atk": 1})
	var battle: BattleEngine = Fixtures.engine([bait, keeper], [foe], null, catalog)
	battle.start()
	_next_turn(battle)
	var queued: Array[Dictionary] = _counters_queued(battle)
	assert_eq(queued.size(), 1, "the attack on the bait; not the one on itself; then the cap of 1")
	if queued.size() == 1:
		assert_eq([int(queued[0]["actor"]), int(queued[0]["modifier"])], [keeper.id, 150])


func test_a_one_turn_buff_from_a_counter_lasts_through_the_player_phase() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 100, 0, 0, BattleSkill.KIND_ABILITY, POWER_UP)])
	var battle: BattleEngine = Fixtures.engine([guard], [_attacker("Foe", [["", 0]], {"atk": 1})], null, catalog)
	battle.start()
	_next_turn(battle)
	assert_eq(battle.turn, 2)
	assert_eq(guard.status_value(BattleStatus.STAT, "ATK"), 100, "Ziedrich-like: ATK +100% for 1 turn, usable now")


func test_119_and_123_put_counter_statuses() -> void:
	var tank: Combatant = Fixtures.unit("Tank")
	var other: Combatant = Fixtures.unit("Other")
	var battle: BattleEngine = Fixtures.engine([tank, other], [Fixtures.monster("Foe", {"brain": IdleEnemyBrain.new()})], null, catalog)
	battle.start()
	battle.execute(tank.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, AVOID, -1))
	battle.advance(2)
	var own: BattleStatus = tank.find_status(BattleStatus.COUNTER, Counters.KEY_SELF)
	assert_not_null(own)
	if own != null:
		assert_eq([own.value, own.turns_left, own.params], [50, 2, {"modifier": 1000, "max": 0}])
		assert_false(own.is_debuff(), "a buff")
	_next_turn(battle)
	battle.execute(tank.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, ANTAGONIZE, -1))
	battle.advance(2)
	var ally: BattleStatus = tank.find_status(BattleStatus.COUNTER, Counters.KEY_ALLY)
	assert_not_null(ally)
	if ally != null:
		assert_eq([ally.value, ally.turns_left, ally.params], [50, 5, {"modifier": 150, "max": 0}])
	assert_eq(tank.status_value(BattleStatus.COUNTER, Counters.KEY_SELF), 50, "one of each key")


func test_the_log_names_the_counter() -> void:
	var guard: Combatant = _counterer("Guard", [_counter("physical", 100, 0, 200)])
	var foe: Combatant = _attacker("Foe", [["", 0]], {"atk": 1})
	var battle: BattleEngine = Fixtures.engine([guard], [foe], null, catalog)
	battle.start()
	_next_turn(battle)
	var queued: String = battle.format_event(_counters_queued(battle)[0])
	assert_true(queued.contains("will counter") and queued.contains("attack x2.00"), queued)
	var started: String = battle.format_event(_counter_actions(battle)[0])
	assert_true(started.contains("(counter to #"), started)


## Real data: Counter (101200) answers physical attacks with the attack, 5 a turn; Face
## Me! (910443) answers physical attacks with Firaga (91003) and magic ones with Blizzaga
## (91004); Ziedrich (216170) boosts ATK for the next player phase; Avoid (914053) and
## Antagonize (216120) put counter statuses.
func test_database_counters() -> void:
	if not SkillResolver.opcode_schemas_ready:
		SkillResolver.load_schemas()
	var counter: CombatantPassives = CombatantPassives.from_profile(_passives_of(["101200"]))
	assert_eq(counter.counters, [{
		"trigger": "physical", "chance": 30, "modifier": 0, "max": 5, "skill_kind": BattleSkill.KIND_ATTACK, "skill_id": "",
		"source_skill_id": "101200",
	}])
	var face_me: CombatantPassives = CombatantPassives.from_profile(_passives_of(["910443"]))
	assert_eq(face_me.counters.map(func(entry: Dictionary) -> Array: return [entry["trigger"], entry["chance"], entry["skill_kind"], entry["skill_id"]]),
		[["physical", 45, BattleSkill.KIND_MAGIC, "91003"], ["magic", 45, BattleSkill.KIND_MAGIC, "91004"]])

	var data := DatabaseSkillCatalog.new()
	var zied: Combatant = Fixtures.unit("Zied", {"passives": _passives_of(["216170"])})
	zied.passives.counters[0]["chance"] = 100
	var mage: Combatant = Fixtures.unit("Mage", {"passives": _passives_of(["910443"])})
	mage.passives.counters[0]["chance"] = 100
	var foe: Combatant = _attacker("Foe", [["", 0], ["", 1]], {"atk": 1})
	var battle: BattleEngine = Fixtures.engine([zied, mage], [foe], null, data)
	battle.start()
	_next_turn(battle)
	assert_eq(zied.status_value(BattleStatus.STAT, "ATK"), 100, "Ziedrich's 1-turn ATK +100%")
	assert_eq(_counter_actions(battle, mage.id).map(func(event: Dictionary) -> String: return str(event["skill_id"])), ["91003"], "Firaga")

	var tank: Combatant = Fixtures.unit("Tank")
	var other: BattleEngine = Fixtures.engine([tank, Fixtures.unit("Waiting")], [Fixtures.monster("Idle", {"brain": IdleEnemyBrain.new()})], null, data)
	other.start()
	other.execute(tank.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "914053", -1))
	other.advance(60)
	var avoid: BattleStatus = tank.find_status(BattleStatus.COUNTER, Counters.KEY_SELF)
	assert_eq([avoid.value, avoid.params["modifier"]] if avoid != null else [], [50, 1000])
	_next_turn(other)
	other.execute(tank.id, BattleCommand.skill(BattleSkill.KIND_ABILITY, "216120", -1))
	other.advance(60)
	var antagonize: BattleStatus = tank.find_status(BattleStatus.COUNTER, Counters.KEY_ALLY)
	assert_eq([antagonize.value, antagonize.params["modifier"], antagonize.turns_left] if antagonize != null else [], [50, 150, 5])


static func _passives_of(passive_ids: Array) -> Dictionary:
	var sources: Array = []
	for passive_id in passive_ids:
		var effects: Array = SkillResolver.parse_passive_effects(GameDatabase.get_passive(int(passive_id))).get("effects", [])
		sources.append({"skill_id": str(passive_id), "source": "Trait", "effects": effects})
	return PassiveAggregator.aggregate(sources, PassiveSources.build_loadout([]), {})
