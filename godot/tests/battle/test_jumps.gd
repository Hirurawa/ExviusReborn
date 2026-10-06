extends "res://tests/test_case.gd"

## Jumps (ops 52 and 134; JumpHandler, BattleStatus.AWAY). The wiki's jump rules (pasted
## by the user, 2026-10-06) and the user's answers: a jumping unit cannot be targeted or
## attacked and misses party buffs cast after the jump; a 52 jump lands at the beginning
## of the player's turn and the unit cannot act that turn; the player lands a 134 jump; a
## dual wielder strikes with each hand on landing; damage uses the buffs at landing; jump
## damage% stacks additively, capped at 800%, as its own multiplier; a two-handed jumper
## rolls at least 2.50 to 2.80; a dead target is replaced, or nothing is hit; a won round
## brings the unit back down. Enemies land on their own turn.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

## Jump: 52, lands next turn at 180%, 10 MP, one hit on frame 0.
const JUMP: String = "30"
## Hyper Dive: 52, lands three turns later at 450%.
const HIGH_JUMP: String = "31"
## Dragoon Dive: 134, ready next turn, 470%, one hit on frame 8.
const DIVE: String = "32"
## Death Crimson: op 13 at 450% and a 52 jump at 300%, both next turn.
const CRIMSON: String = "33"
## A drop-time chain (Spineshatter Dive 2 212210): op 99 runs DIVE_FAST (delay 1) when
## DIVE_ONE was used last turn, DIVE_SLOW (delay 2) otherwise.
const DIVE_ONE: String = "37"
const DIVE_TWO: String = "38"
const DIVE_FAST: String = "39"
const DIVE_SLOW: String = "42"
## High Dragoon Dive: 134, ready in two turns.
const DIVE_IN_TWO: String = "34"
## A plain 100% physical ability, and a multicast command that picks JUMP or STRIKE twice.
const STRIKE: String = "35"
const DOUBLE_ACT: String = "36"
## ATK +50% for all allies (3 turns), and a heal for all allies.
const RALLY: String = "40"
const HEAL_ALL: String = "41"
## Monster skills: a single-target slam, an AoE quake, a jump.
const SLAM: String = "1"
const QUAKE: String = "2"
const LEAP: String = "3"

var catalog: SkillCatalog


## Acts `decisions` in order each turn and counts how often it is asked.
class ScriptBrain:
	extends EnemyBrain
	var decisions: Array = []
	var asked: int = 0
	var _next: int = 0

	func begin_turn(_ctx: Dictionary) -> void:
		_next = 0

	func next_action(_ctx: Dictionary) -> Dictionary:
		asked += 1
		if _next >= decisions.size():
			return turn_over("done")
		_next += 1
		return decisions[_next - 1]

	func is_turn_over() -> bool:
		return _next >= decisions.size()


func before_each() -> void:
	catalog = Fixtures.catalog()
	var physical: Dictionary = {"attack_type": BattleSkill.ATTACK_PHYSICAL}
	_ability(JUMP, Fixtures.record("Jump", [[1, 1, 52, [0, 0, 1, 1, 180]]], "0:100", {"attack_type": 1, "cost": {"MP": 10}}))
	_ability(HIGH_JUMP, Fixtures.record("Hyper Dive", [[1, 1, 52, [0, 0, 3, 3, 450]]], "0:100", physical))
	_ability(DIVE, Fixtures.record("Dragoon Dive", [[1, 1, 134, [0, 0, 1, 1, 470]]], "8:100", physical))
	_ability(CRIMSON, Fixtures.record("Death Crimson", [[1, 1, 13, [1, 0, 0, 1, 0, 450]], [1, 1, 52, [0, 0, 1, 1, 300]]],
		"5:100@0:100", physical))
	_ability(DIVE_IN_TWO, Fixtures.record("High Dragoon Dive", [[1, 1, 134, [0, 0, 2, 2, 750]]], "0:100", physical))
	_ability(STRIKE, Fixtures.record("Strike", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	_ability(DOUBLE_ACT, Fixtures.record("Double Act", [[0, 3, 53, [2, 199, -1, [int(JUMP), int(STRIKE)], 1, 0]]], ""))
	_ability(RALLY, Fixtures.record("Rally", [[2, 2, 3, [50, 0, 0, 0, 3]]], ""))
	_ability(DIVE_ONE, Fixtures.record("Dive 1", [[1, 1, 52, [0, 0, 1, 1, 200]]], "0:100", physical))
	_ability(DIVE_TWO, Fixtures.record("Dive 2", [[1, 1, 99, [2, int(DIVE_ONE), 2, int(DIVE_FAST), 2, int(DIVE_SLOW)]]], ""))
	_ability(DIVE_FAST, Fixtures.record("Dive 2", [[1, 1, 52, [0, 0, 1, 1, 300]]], "0:100", physical))
	_ability(DIVE_SLOW, Fixtures.record("Dive 2", [[1, 1, 52, [0, 0, 2, 2, 300]]], "0:100", physical))
	_ability(HEAL_ALL, Fixtures.record("Heal All", [[2, 2, 2, [0, 0, 500, 0]]], "10:100"))
	catalog.add_record(BattleSkill.KIND_MONSTER, SLAM, Fixtures.record("Slam", [[1, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	catalog.add_record(BattleSkill.KIND_MONSTER, QUAKE, Fixtures.record("Quake", [[2, 1, 1, Fixtures.physical_params(100)]], "10:100", physical))
	catalog.add_record(BattleSkill.KIND_MONSTER, LEAP, Fixtures.record("Leap", [[1, 1, 52, [0, 0, 1, 1, 200]]], "0:100", physical))


func _ability(id: String, data: Dictionary) -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, id, data)


static func _skill(id: String, target: int = -1) -> BattleCommand:
	return BattleCommand.skill(BattleSkill.KIND_ABILITY, id, target)


static func _idle(foe_name: String = "Foe", spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"brain": IdleEnemyBrain.new()}
	full.merge(spec, true)
	return Fixtures.monster(foe_name, full)


## A monster acting `decisions` each turn: [monster skill id or "" for the attack, party
## slot it aims at or -1 for a random member].
static func _scripted(foe_name: String, decisions: Array) -> Combatant:
	var brain := ScriptBrain.new()
	for decision in decisions:
		var skill_id: String = str(decision[0])
		var slot: int = int(decision[1])
		brain.decisions.append(EnemyBrain.action(EnemyBrain.KIND_SKILL if skill_id != "" else EnemyBrain.KIND_ATTACK, skill_id,
			"disp_order" if slot >= 0 else "random", slot))
	return Fixtures.monster(foe_name, {"brain": brain})


## Every unit that can still act defends (a ready 134 jumper cannot: the caller lands it
## first), then the battle runs to the next turn's player phase.
static func _next_turn(battle: BattleEngine) -> void:
	var turn: int = battle.total_turns
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	for member in battle.units_to_act():
		battle.execute(member.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.total_turns > turn and battle.phase == BattleEngine.Phase.PLAYER, 5000)


## ACTION_STARTED events whose command is LAND.
static func _landings(battle: BattleEngine) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in battle.events.of_type(BattleEventLog.ACTION_STARTED):
		if int(event["kind"]) == BattleCommand.Kind.LAND:
			out.append(event)
	return out


## HIT_LANDED events of `actor_id` on `target_id`.
static func _hits_by(battle: BattleEngine, actor_id: int, target_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in Fixtures.hits(battle, target_id):
		if int(event["actor"]) == actor_id:
			out.append(event)
	return out


func test_a_jump_leaves_the_field_and_lands_at_the_next_turns_start() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	assert_eq(battle.execute(hero.id, _skill(JUMP, foe.id)), BattleEngine.OK)
	battle.tick()
	assert_true(hero.is_away(), "in the air from the action's first frame")
	assert_false(hero.is_targetable())
	assert_eq(hero.mp, 90, "the jump pays its MP")
	assert_eq(battle.jump_of(hero.id), {"skill_kind": BattleSkill.KIND_ABILITY, "skill_id": JUMP, "ready_turn": 2, "manual": false, "ready": false})
	assert_eq(BattleEngine.ai_view(hero)["is_off_field"], true, "the AI's outside_field sees it")
	assert_eq(_hits_by(battle, hero.id, foe.id).size(), 0, "no damage yet")
	_next_turn(battle)
	var landings: Array[Dictionary] = _landings(battle)
	assert_eq(landings.size(), 1, "lands in turn 2's opening phase")
	if landings.size() == 1:
		assert_eq([int(landings[0]["origin"]), landings[0]["reaction"], landings[0]["skill_id"], landings[0]["skill_name"]],
			[BattleAction.Origin.REACTION, Reaction.LANDING, JUMP, "Jump"])
	assert_eq(Fixtures.amounts(_hits_by(battle, hero.id, foe.id)), [180])
	assert_false(hero.is_away())
	assert_true(hero.acted, "the wiki: unavailable for further actions on that turn")
	assert_eq(battle.can_execute(hero.id), BattleEngine.REJECT_ALREADY_ACTED)
	assert_false(battle.units_to_act().has(hero))
	assert_eq(hero.mp, 90, "the landing costs nothing")
	assert_eq(hero.history.previous_declared, "ability:%s" % JUMP)
	assert_true(hero.history.used_on("ability:%s" % JUMP, 2), "the landing counts as the jump used on turn 2")
	var removed: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.STATUS_REMOVED, hero.id)
	assert_eq(removed.map(func(event: Dictionary) -> StringName: return event["reason"]), [&"landed"])


func test_a_landing_feeds_a_drop_time_chain() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(DIVE_ONE, foe.id))
	_next_turn(battle)
	assert_eq(_landings(battle).size(), 1, "Dive 1 lands on turn 2")
	_next_turn(battle)
	assert_eq(battle.executed_skill(hero.id, _skill(DIVE_TWO)).id, DIVE_FAST, "Dive 1 counts as used on turn 2")
	battle.execute(hero.id, _skill(DIVE_TWO, foe.id))
	battle.tick()
	assert_eq(int(battle.jump_of(hero.id)["ready_turn"]), 4, "the shorter drop time")


func test_a_unit_in_the_air_is_out_of_reach() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _scripted("Foe", [[SLAM, 0], [QUAKE, -1], ["", 0]])
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(JUMP, foe.id))
	battle.advance(5)
	battle.execute(buddy.id, _skill(RALLY))
	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.total_turns == 2, 5000))
	assert_eq(hero.status_value(BattleStatus.STAT, "ATK"), 0, "the wiki: party buffs cast after the jump miss it")
	assert_eq(buddy.status_value(BattleStatus.STAT, "ATK"), 50)
	assert_eq(Fixtures.hits(battle, hero.id).size(), 0, "aimed at it, area-wide or plain attacks: none reach it")
	assert_eq(Fixtures.hits(battle, buddy.id).size(), 3)
	assert_eq(hero.hp, hero.max_hp)


func test_a_jump_three_turns_long_keeps_the_unit_away_in_between() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(HIGH_JUMP, foe.id))
	for turn in [2, 3]:
		_next_turn(battle)
		assert_true(hero.is_away(), "still away on turn %d" % turn)
		assert_false(battle.units_to_act().has(hero))
		assert_eq(battle.can_execute(hero.id, BattleCommand.attack()), BattleEngine.REJECT_AWAY)
		assert_eq(battle.can_execute(hero.id, BattleCommand.land()), BattleEngine.REJECT_AWAY, "a 52 jump lands on its own")
	_next_turn(battle)
	assert_eq(_landings(battle).size(), 1, "lands on turn 4")
	assert_eq(Fixtures.amounts(_hits_by(battle, hero.id, foe.id)), [450])


func test_the_landing_takes_a_new_target_when_its_own_is_gone() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var first: Combatant = _idle("First")
	var second: Combatant = _idle("Second")
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [first, second], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(JUMP, second.id))
	battle.tick()
	battle.debug_edit(second.id, &"hp", 0)
	_next_turn(battle)
	assert_eq(Fixtures.amounts(_hits_by(battle, hero.id, first.id)), [180], "the wiki: a new target is chosen")


func test_a_won_wave_brings_the_jumper_back_without_landing() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [_idle("First", {"hp": 1})], null, catalog)
	battle.queue_wave(func() -> Array[Combatant]: return [_idle("Second")])
	battle.start()
	battle.execute(hero.id, _skill(JUMP))
	battle.tick()
	battle.execute(buddy.id)
	assert_true(Fixtures.run_until_phase(battle, BattleEngine.Phase.WAVE_CLEARED))
	assert_false(hero.is_away(), "the wiki: back on the ground for the next round")
	var removed: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.STATUS_REMOVED, hero.id)
	assert_eq(removed.map(func(event: Dictionary) -> StringName: return event["reason"]), [&"battle_end"])
	battle.begin_next_wave()
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	assert_eq(_landings(battle).size(), 0, "the jump is canceled")
	assert_true(battle.units_to_act().has(hero))


func test_landing_damage_uses_the_stats_at_landing() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(JUMP, foe.id))
	battle.tick()
	battle.debug_edit(hero.id, &"stat", 200, "ATK")
	_next_turn(battle)
	assert_eq(Fixtures.amounts(_hits_by(battle, hero.id, foe.id)), [720], "200 ATK: 400 x 1.8")


func test_poison_can_ko_a_unit_in_the_air() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.debug_edit(hero.id, &"ailment", 1, "POISON")
	battle.debug_edit(hero.id, &"hp", 50)
	battle.execute(hero.id, _skill(JUMP, foe.id))
	_next_turn(battle)
	assert_false(hero.is_alive(), "poison ticks in the air (the user's rule)")
	assert_eq(_landings(battle).size(), 0, "a KO ends the jump")


func test_an_activated_jump_waits_for_the_player() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(DIVE, foe.id))
	_next_turn(battle)
	assert_true(hero.is_away())
	assert_eq(_landings(battle).size(), 0, "a 134 jump does not land on its own")
	assert_eq(battle.jump_of(hero.id)["ready"], true)
	assert_true(battle.units_to_act().has(hero), "the turn waits for it")
	assert_eq(battle.can_execute(hero.id), BattleEngine.OK, "its default command is LAND")
	assert_eq(battle.can_execute(hero.id, BattleCommand.attack()), BattleEngine.REJECT_AWAY)
	battle.execute(buddy.id, BattleCommand.defend())
	battle.advance(200)
	assert_eq(battle.phase, BattleEngine.Phase.PLAYER, "still waiting")
	var execute_frame: int = battle.frame
	assert_eq(battle.execute(hero.id), BattleEngine.OK)
	var landings: Array[Dictionary] = _landings(battle)
	assert_eq(landings.size(), 1)
	if landings.size() == 1:
		assert_eq([int(landings[0]["origin"]), landings[0]["skill_id"], landings[0]["reaction"]], [BattleAction.Origin.COMMAND, DIVE, &""])
	assert_false(hero.is_away())
	Fixtures.run_until(battle, func() -> bool: return _hits_by(battle, hero.id, foe.id).size() > 0, 100)
	var hits: Array[Dictionary] = _hits_by(battle, hero.id, foe.id)
	assert_eq(Fixtures.amounts(hits), [470])
	if hits.size() == 1:
		assert_eq(int(hits[0]["frame"]) - execute_frame, 8, "on the frame the player chose, plus its attack frame")
		assert_eq(int(hits[0]["opcode"]), 134)
	assert_eq(hero.last_command.skill_id, DIVE, "Repeat jumps again")


func test_an_activated_jump_is_not_ready_before_its_turn() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(DIVE_IN_TWO, foe.id))
	_next_turn(battle)
	assert_false(battle.units_to_act().has(hero), "in two turns")
	assert_eq(battle.can_execute(hero.id, BattleCommand.land()), BattleEngine.REJECT_AWAY)
	_next_turn(battle)
	assert_true(battle.units_to_act().has(hero))
	assert_eq(battle.can_execute(buddy.id, BattleCommand.land()), BattleEngine.REJECT_NOTHING_TO_LAND)


func test_a_landing_on_a_chosen_frame_chains_with_an_ally() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(DIVE, foe.id))
	_next_turn(battle)
	battle.execute(buddy.id, BattleCommand.attack(foe.id))
	battle.advance(3)
	battle.execute(hero.id)
	Fixtures.run_until(battle, func() -> bool: return _hits_by(battle, hero.id, foe.id).size() > 0, 100)
	var buddy_hits: Array[Dictionary] = _hits_by(battle, buddy.id, foe.id)
	var hero_hits: Array[Dictionary] = _hits_by(battle, hero.id, foe.id)
	assert_eq([buddy_hits.size(), hero_hits.size()], [1, 1])
	if buddy_hits.size() == 1 and hero_hits.size() == 1:
		assert_eq(int(hero_hits[0]["frame"]) - int(buddy_hits[0]["frame"]), 1)
		assert_true(int(hero_hits[0]["chain"]) > int(buddy_hits[0]["chain"]), "the landing continues the chain")


func test_auto_battle_lands_a_ready_jumper() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(DIVE, foe.id))
	_next_turn(battle)
	var ids: Array = battle.units_to_act().map(func(member: Combatant) -> int: return member.id)
	var results: Dictionary = battle.execute_many(ids)
	assert_eq(results, {hero.id: BattleEngine.OK, buddy.id: BattleEngine.OK})
	assert_eq(_landings(battle).size(), 1)


func test_an_enemy_jump_lands_on_its_own_turn() -> void:
	var counter: Dictionary = {
		"trigger": "physical", "chance": 100, "modifier": 0, "max": 0, "skill_kind": BattleSkill.KIND_ATTACK, "skill_id": "",
		"source_skill_id": "900",
	}
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {"counters": [counter]}})
	var foe: Combatant = _scripted("Dragoon", [[LEAP, 0]])
	var brain := foe.brain as ScriptBrain
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, BattleCommand.defend())
	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.total_turns == 2 and battle.phase == BattleEngine.Phase.PLAYER, 5000))
	assert_true(foe.is_away(), "it jumped in the enemy phase")
	assert_eq(brain.asked, 1)
	assert_eq(battle.events.of_type(BattleEventLog.COUNTER_QUEUED).size(), 0, "a jump without damage is no attack")
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.phase == BattleEngine.Phase.ENEMY, 500))
	assert_eq(Fixtures.hits(battle, foe.id).size(), 0, "nothing reaches it")
	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.total_turns == 3, 5000))
	var landings: Array[Dictionary] = _landings(battle)
	assert_eq(landings.size(), 1, "it lands in turn 2's enemy phase")
	if landings.size() == 1:
		assert_eq(landings[0]["reaction"], Reaction.LANDING)
	assert_eq(brain.asked, 1, "the landing is its whole turn: the AI is not asked")
	assert_eq(Fixtures.amounts(_hits_by(battle, foe.id, hero.id)), [200])
	assert_eq(battle.events.of_type(BattleEventLog.COUNTER_QUEUED).size(), 1, "a landing is an attack")


func test_a_dual_wielder_lands_with_both_hands() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"hand_atk": [50, 50]})
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(JUMP, foe.id))
	battle.advance(60)
	var leaps: Array[Dictionary] = Fixtures.events_on(battle, BattleEventLog.STATUS_ADDED, hero.id)
	assert_eq(leaps.size(), 1, "the left swing does not jump again")
	_next_turn(battle)
	var landings: Array[Dictionary] = _landings(battle)
	if landings.size() == 1:
		assert_true(bool(landings[0]["dual_wield"]), "the wiki: damage on each hand when they land")
	var hits: Array[Dictionary] = _hits_by(battle, hero.id, foe.id)
	assert_eq(hits.map(func(event: Dictionary) -> int: return int(event["swing"])), [DualWield.RIGHT, DualWield.LEFT])
	assert_eq(Fixtures.amounts(hits), [45, 45], "each hand's ATK: 50 x 50 / 100 x 1.8")


func test_death_crimson_lands_both_parts_on_the_same_turn() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(CRIMSON, foe.id))
	_next_turn(battle)
	var reactions: Array = Fixtures.actions_by(battle, hero.id).filter(func(event: Dictionary) -> bool: return int(event["origin"]) == BattleAction.Origin.REACTION)
	assert_eq(reactions.map(func(event: Dictionary) -> StringName: return event["reaction"]), [Reaction.DELAYED, Reaction.LANDING],
		"op 13 first, as in the data")
	assert_eq(Fixtures.amounts(_hits_by(battle, hero.id, foe.id)), [450, 300])


func test_jump_damage_is_its_own_multiplier_capped_at_800() -> void:
	var opcode_boost: Dictionary = {"skill_ids": [], "opcodes": [52, 134], "damage_type": 0, "pct": 3000}
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {"jump_damage_pct": 900, "skill_boosts": [opcode_boost]}})
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(CRIMSON, foe.id))
	_next_turn(battle)
	assert_eq(Fixtures.amounts(_hits_by(battle, hero.id, foe.id)), [450, 300 * 9 * 31],
		"op 13 is no jump; the landing: x9 (900 capped at 800) and x31 (the 52&134 ability boost)")
	battle.execute(buddy.id, BattleCommand.defend())
	_next_turn(battle)
	battle.execute(hero.id, BattleCommand.attack(foe.id))
	Fixtures.run_until(battle, func() -> bool: return _hits_by(battle, hero.id, foe.id).size() == 3, 200)
	assert_eq(Fixtures.amounts(_hits_by(battle, hero.id, foe.id))[2], 100, "a plain attack is not boosted")


func test_a_two_handed_jumper_rolls_at_least_the_flat_variance() -> void:
	var rules: BattleRules = Fixtures.rules()
	rules.weapon_variance = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var great_sword: Combatant = Fixtures.unit("Great Sword", {"two_handed": true, "weapon_variance": [125, 175]})
	var dagger: Combatant = Fixtures.unit("Dagger", {"weapon_variance": [110, 120]})
	var dice: Combatant = Fixtures.unit("Dice", {"two_handed": true, "weapon_variance": [120, 560]})
	var ranges: Dictionary = {"jump": [9.0, 0.0], "swing": [9.0, 0.0], "dagger": [9.0, 0.0], "dice": [9.0, 0.0]}
	for _i in range(300):
		_widen(ranges["jump"], DamageFormula.weapon_variance(great_sword, rules, rng, 52))
		_widen(ranges["swing"], DamageFormula.weapon_variance(great_sword, rules, rng, 1))
		_widen(ranges["dagger"], DamageFormula.weapon_variance(dagger, rules, rng, 134))
		_widen(ranges["dice"], DamageFormula.weapon_variance(dice, rules, rng, 134))
	assert_true(ranges["jump"][0] >= 2.5 and ranges["jump"][1] <= 2.8, "the wiki's flat 2.50 to 2.80: %s" % [ranges["jump"]])
	assert_true(ranges["swing"][0] >= 1.25 and ranges["swing"][1] <= 1.75, "not a jump: the weapon's own: %s" % [ranges["swing"]])
	assert_true(ranges["dagger"][0] >= 1.1 and ranges["dagger"][1] <= 1.2, "one-handed: the weapon's own: %s" % [ranges["dagger"]])
	assert_true(ranges["dice"][0] >= 2.5 and ranges["dice"][1] > 2.8, "whichever is higher: %s" % [ranges["dice"]])
	rules.weapon_variance = false
	assert_eq(DamageFormula.weapon_variance(great_sword, rules, rng, 52), 1.0)


static func _widen(bounds: Array, value: float) -> void:
	bounds[0] = minf(float(bounds[0]), value)
	bounds[1] = maxf(float(bounds[1]), value)


func test_a_multicast_pick_after_a_jump_is_dropped() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [foe], null, catalog)
	battle.start()
	var picks: Array[BattleCommand] = [_skill(JUMP, foe.id), _skill(STRIKE, foe.id)]
	assert_eq(battle.execute(hero.id, BattleCommand.multicast(DOUBLE_ACT, picks, foe.id)), BattleEngine.OK)
	battle.advance(60)
	var dropped: Array[Dictionary] = battle.events.of_type(BattleEventLog.MULTICAST_CAST_DROPPED)
	assert_eq(dropped.map(func(event: Dictionary) -> StringName: return event["reason"]), [&"caster_away"])
	assert_true(hero.is_away())
