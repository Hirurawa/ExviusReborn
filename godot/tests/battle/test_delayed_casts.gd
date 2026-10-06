extends "res://tests/test_case.gd"

## Delayed casts (op 132) and delayed damage (op 13): DelayHandler queues them
## (DelayedCast) and the opening phase of the turn they are due runs them as reactions,
## after the turn-start casts. They cost nothing, leave `acted` and the history alone,
## and compute their damage when they land. A KO drops the caster's pending ones, a
## new cast with a pending one's key replaces it, a cleared wave drops them all.
## DELAYED-SKILLS-PLAN.md has the plan and the user's rules.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

## Op 132 casting POWER_UP next turn, key 5.
const POWER_LATER: String = "10"
## ATK +50% on the caster for 3 turns.
const POWER_UP: String = "11"
## Op 132 casting POWER_UP in two turns.
const POWER_IN_TWO: String = "12"
## Op 132 casting LINK next turn; LINK casts POWER_UP the turn after (a chain).
const CHAIN: String = "13"
const LINK: String = "14"
## Op 132 starting LOOP under key 16; LOOP buffs ATK +10% for a turn and recasts itself
## every turn under the same key (Chronic Flow and Chronic Energy).
const LOOP_START: String = "15"
const LOOP: String = "16"
## Air Anchor: damage one enemy, and break its ATK next turn (op 132 on one enemy, key 0).
const AIR_ANCHOR: String = "17"
const ANCHOR_BREAK: String = "18"
## Op 13: 200% physical damage on one enemy next turn, in two hits at frames 5 and 15.
const DELAYED_HIT: String = "20"
## Op 13: 150% on all enemies next turn.
const DELAYED_AOE: String = "21"
## Dynamite Arrow: op 13 at 12000 (120x, the wiki) with attack type 4.
const DYNAMITE: String = "22"
## Op 132 casting POWER_UP three turns later, cast at the battle start.
const POWER_IN_THREE: String = "23"

var catalog: SkillCatalog


func before_each() -> void:
	catalog = Fixtures.catalog()
	var physical: Dictionary = {"attack_type": BattleSkill.ATTACK_PHYSICAL}
	_ability(POWER_LATER, Fixtures.record("Power Later", [[0, 3, 132, [int(POWER_UP), 1, 1, 100, 0, 5]]], ""))
	_ability(POWER_UP, Fixtures.record("Power Up", [[0, 3, 3, [50, 0, 0, 0, 3]]], ""))
	_ability(POWER_IN_TWO, Fixtures.record("Power In Two", [[0, 3, 132, [int(POWER_UP), 1, 2, 100, 0, 6]]], ""))
	_ability(CHAIN, Fixtures.record("Chain", [[0, 3, 132, [int(LINK), 1, 1, 100, 0, 7]]], ""))
	_ability(LINK, Fixtures.record("Link", [[0, 3, 132, [int(POWER_UP), 1, 1, 100, 0, 8]]], ""))
	_ability(LOOP_START, Fixtures.record("Loop Start", [[0, 3, 132, [int(LOOP), 1, 1, 100, 0, 16]]], ""))
	_ability(LOOP, Fixtures.record("Loop", [[0, 3, 3, [10, 0, 0, 0, 1]], [0, 3, 132, [int(LOOP), 1, 1, 100, 0, 16]]], ""))
	_ability(AIR_ANCHOR, Fixtures.record("Air Anchor", [[1, 1, 1, Fixtures.physical_params(100)],
		[1, 1, 132, [int(ANCHOR_BREAK), 0, 1, 100, 0, 0]]], "10:100", physical))
	_ability(ANCHOR_BREAK, Fixtures.record("Anchor Break", [[1, 1, 24, [-50, 0, 0, 0, 3]]], ""))
	_ability(DELAYED_HIT, Fixtures.record("Delayed Hit", [[1, 1, 13, [1, 0, 0, 1, 0, 200]]], "5:50-15:50", physical))
	_ability(DELAYED_AOE, Fixtures.record("Delayed AoE", [[2, 1, 13, [1, 0, 0, 2, 0, 150]]], "5:100", physical))
	_ability(DYNAMITE, Fixtures.record("Dynamite Arrow", [[2, 1, 13, [1, 0, 0, 2, 5000210, 12000]]], "5:100",
		{"attack_type": BattleSkill.ATTACK_NONE}))
	_ability(POWER_IN_THREE, Fixtures.record("Power In Three", [[0, 3, 132, [int(POWER_UP), 0, 3, 100, 0, 23]]], ""))


func _ability(id: String, data: Dictionary) -> void:
	catalog.add_record(BattleSkill.KIND_ABILITY, id, data)


static func _skill(id: String, target: int = -1) -> BattleCommand:
	return BattleCommand.skill(BattleSkill.KIND_ABILITY, id, target)


static func _idle(foe_name: String = "Foe", spec: Dictionary = {}) -> Combatant:
	var full: Dictionary = {"brain": IdleEnemyBrain.new()}
	full.merge(spec, true)
	return Fixtures.monster(foe_name, full)


## ACTION_STARTED events of delayed effects, optionally only those running `skill_id`.
static func _delayed_actions(battle: BattleEngine, skill_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event in battle.events.of_type(BattleEventLog.ACTION_STARTED):
		if StringName(event["reaction"]) == Reaction.DELAYED and (skill_id == "" or str(event["skill_id"]) == skill_id):
			out.append(event)
	return out


## Every unit that can still act defends, then the battle runs to the next turn's player
## phase.
static func _next_turn(battle: BattleEngine) -> void:
	var turn: int = battle.total_turns
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	for member in battle.units_to_act():
		battle.execute(member.id, BattleCommand.defend())
	Fixtures.run_until(battle, func() -> bool: return battle.total_turns > turn and battle.phase == BattleEngine.Phase.PLAYER, 5000)


static func _events_of(battle: BattleEngine, type: StringName) -> Array[Dictionary]:
	return battle.events.of_type(type)


func test_a_delayed_cast_runs_at_the_start_of_the_next_turn() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = Fixtures.engine([hero], [_idle()], null, catalog)
	battle.start()
	assert_eq(battle.execute(hero.id, _skill(POWER_LATER)), BattleEngine.OK)
	var queued: Array[Dictionary] = _events_of(battle, BattleEventLog.DELAY_QUEUED)
	assert_eq(queued.size(), 1, "queued as the action starts")
	if queued.size() == 1:
		assert_eq([queued[0]["kind"], queued[0]["skill_id"], queued[0]["source_skill_id"], queued[0]["due_turn"], queued[0]["key"]],
			[DelayedCast.CAST, POWER_UP, POWER_LATER, 2, "5"])
	assert_eq(battle.pending_delays().size(), 1)
	assert_eq(hero.status_value(BattleStatus.STAT, "ATK"), 0, "nothing happens this turn")
	_next_turn(battle)
	var ran: Array[Dictionary] = _delayed_actions(battle, POWER_UP)
	assert_eq(ran.size(), 1, "runs in turn 2's opening phase")
	if ran.size() == 1:
		assert_eq([int(ran[0]["origin"]), ran[0]["source_skill_id"]], [BattleAction.Origin.REACTION, POWER_LATER])
	assert_eq(hero.status_value(BattleStatus.STAT, "ATK"), 50)
	assert_false(hero.acted, "a delayed cast does not use up the turn")
	assert_eq(hero.history.previous_declared, "ability:%s" % POWER_LATER, "nor go into the history")
	assert_eq(battle.pending_delays().size(), 0)
	var phases: Array = battle.events.of_type(BattleEventLog.PHASE_CHANGED).map(func(event: Dictionary) -> StringName: return event["phase"])
	assert_has(phases, &"opening")


func test_the_delay_counts_turns_from_the_cast() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = Fixtures.engine([hero], [_idle()], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(POWER_IN_TWO))
	_next_turn(battle)
	assert_eq(_delayed_actions(battle).size(), 0, "not on turn 2")
	_next_turn(battle)
	assert_eq(_delayed_actions(battle, POWER_UP).size(), 1, "on turn 3")


func test_delays_add_up_along_a_chain() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = Fixtures.engine([hero], [_idle()], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(CHAIN))
	_next_turn(battle)
	assert_eq(_delayed_actions(battle, LINK).size(), 1, "the link on turn 2")
	assert_eq(_delayed_actions(battle, POWER_UP).size(), 0)
	_next_turn(battle)
	assert_eq(_delayed_actions(battle, POWER_UP).size(), 1, "what it casts on turn 3")


func test_a_new_cast_with_a_pending_key_replaces_it() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var battle: BattleEngine = Fixtures.engine([hero], [_idle()], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(LOOP_START))
	_next_turn(battle)
	assert_eq(_delayed_actions(battle, LOOP).size(), 1, "the loop runs on turn 2")
	assert_eq(battle.pending_delays().size(), 1, "and queues itself again")
	battle.execute(hero.id, _skill(LOOP_START))
	assert_eq(battle.pending_delays().size(), 1, "the restart replaces the pending one")
	var dropped: Array[Dictionary] = _events_of(battle, BattleEventLog.DELAY_DROPPED)
	assert_eq(dropped.map(func(event: Dictionary) -> StringName: return event["reason"]), [&"replaced"])
	_next_turn(battle)
	assert_eq(_delayed_actions(battle, LOOP).size(), 2, "once on turn 3, not twice")
	_next_turn(battle)
	assert_eq(_delayed_actions(battle, LOOP).size(), 3, "and every turn after")


func test_a_delayed_cast_follows_the_picked_enemy() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var first: Combatant = _idle("First")
	var second: Combatant = _idle("Second")
	var battle: BattleEngine = Fixtures.engine([hero], [first, second], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(AIR_ANCHOR, second.id))
	_next_turn(battle)
	assert_eq(second.status_value(BattleStatus.STAT, "ATK"), -50, "their ATK, next turn")
	assert_eq(first.status_value(BattleStatus.STAT, "ATK"), 0)


func test_a_delayed_cast_falls_back_when_its_target_is_gone() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var first: Combatant = _idle("First")
	var second: Combatant = _idle("Second")
	var battle: BattleEngine = Fixtures.engine([hero], [first, second], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(AIR_ANCHOR, second.id))
	# Gone before turn 2 (with a lone hero and an idle enemy, the rest of the turn passes
	# in one tick once the action ends).
	battle.debug_edit(second.id, &"hp", 0)
	_next_turn(battle)
	assert_eq(first.status_value(BattleStatus.STAT, "ATK"), -50, "the first enemy on the field")


func test_a_battle_start_cast_with_delay_three_runs_on_turn_four() -> void:
	var cast: Dictionary = {
		"skill_kind": BattleSkill.KIND_ABILITY, "skill_id": POWER_IN_THREE, "battle_start": true, "revive": false,
		"turn_start": false, "chance": 100, "source_skill_id": "900",
	}
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {"auto_casts": [cast]}})
	var battle: BattleEngine = Fixtures.engine([hero], [_idle()], null, catalog)
	battle.start()
	for _i in range(2):
		_next_turn(battle)
	assert_eq(_delayed_actions(battle).size(), 0, "nothing on turns 2 and 3")
	_next_turn(battle)
	var ran: Array[Dictionary] = _delayed_actions(battle, POWER_UP)
	assert_eq(ran.size(), 1, "three turns after the beginning of battle")
	assert_eq(battle.total_turns, 4)


func test_a_ko_drops_the_casters_pending_casts() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [_idle()], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(POWER_LATER))
	battle.debug_edit(hero.id, &"hp", 0)
	var dropped: Array[Dictionary] = _events_of(battle, BattleEventLog.DELAY_DROPPED)
	assert_eq(dropped.size(), 1)
	if dropped.size() == 1:
		assert_eq([dropped[0]["reason"], dropped[0]["skill_id"]], [&"caster_down", POWER_UP])
	battle.debug_edit(hero.id, &"hp", 500)
	_next_turn(battle)
	assert_eq(_delayed_actions(battle).size(), 0, "a revive does not bring it back")


func test_a_cleared_wave_drops_pending_casts() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var buddy: Combatant = Fixtures.unit("Buddy")
	var battle: BattleEngine = Fixtures.engine([hero, buddy], [_idle("First", {"hp": 1})], null, catalog)
	battle.queue_wave(func() -> Array[Combatant]: return [_idle("Second")])
	battle.start()
	battle.execute(hero.id, _skill(POWER_LATER))
	battle.execute(buddy.id)
	assert_true(Fixtures.run_until_phase(battle, BattleEngine.Phase.WAVE_CLEARED))
	var dropped: Array[Dictionary] = _events_of(battle, BattleEventLog.DELAY_DROPPED)
	assert_eq(dropped.map(func(event: Dictionary) -> StringName: return event["reason"]), [&"wave_cleared"])
	battle.begin_next_wave()
	Fixtures.run_until_phase(battle, BattleEngine.Phase.PLAYER)
	assert_eq(_delayed_actions(battle).size(), 0)


func test_delayed_damage_lands_next_turn_with_its_own_frames() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(DELAYED_HIT, foe.id))
	# Computed when it lands: an ATK change after the cast counts.
	battle.debug_edit(hero.id, &"stat", 200, "ATK")
	_next_turn(battle)
	var ran: Array[Dictionary] = _delayed_actions(battle, DELAYED_HIT)
	assert_eq(ran.size(), 1)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(Fixtures.amounts(hits), [400, 400], "200% at 200 ATK, split 50/50")
	if ran.size() == 1 and hits.size() == 2:
		var start: int = int(ran[0]["frame"])
		assert_eq([int(hits[0]["frame"]) - start, int(hits[1]["frame"]) - start], [5, 15], "the effect's own frames, on turn 2")
		assert_eq(int(hits[0]["opcode"]), 13)


func test_delayed_damage_on_all_enemies() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var first: Combatant = _idle("First")
	var second: Combatant = _idle("Second")
	var battle: BattleEngine = Fixtures.engine([hero], [first, second], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(DELAYED_AOE))
	_next_turn(battle)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, first.id)), [150])
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, second.id)), [150])


func test_dynamite_arrow_is_a_fixed_attack_at_120x() -> void:
	var hero: Combatant = Fixtures.unit("Hero")
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(DYNAMITE))
	_next_turn(battle)
	var hits: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(Fixtures.amounts(hits), [12000], "the wiki: physical damage (120x)")
	if hits.size() == 1:
		assert_eq(int(hits[0]["attack_type"]), BattleSkill.ATTACK_NONE, "the wiki's fixed attack")


func test_a_skill_boost_naming_the_skill_raises_delayed_damage() -> void:
	var boost: Dictionary = {"skill_ids": [DELAYED_HIT], "opcodes": [], "damage_type": 0, "pct": 100}
	var hero: Combatant = Fixtures.unit("Hero", {"passives": {"skill_boosts": [boost]}})
	var foe: Combatant = _idle()
	var battle: BattleEngine = Fixtures.engine([hero], [foe], null, catalog)
	battle.start()
	battle.execute(hero.id, _skill(DELAYED_HIT, foe.id))
	_next_turn(battle)
	assert_eq(Fixtures.amounts(Fixtures.hits(battle, foe.id)), [200, 200])
