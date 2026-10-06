extends "res://tests/test_case.gd"

## Waves: one engine runs every wave of a battle. What happens when a formation is down
## with more to come, what the party keeps into the next wave, and the session starting
## the next wave on its own.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")


## A foe that dies to one basic attack from a 1000 ATK hero and never acts.
static func _weak(monster_name: String) -> Combatant:
	return Fixtures.monster(monster_name, {"hp": 100, "brain": IdleEnemyBrain.new()})


## A hero that kills a weak foe with one basic attack.
static func _hero() -> Combatant:
	return Fixtures.unit("Hero", {"atk": 1000, "attack_frames": "4:100"})


## Queues a wave holding `foes`.
static func _queue(battle: BattleEngine, foes: Array) -> void:
	var formation: Array[Combatant] = []
	formation.assign(foes)
	battle.queue_wave(func() -> Array[Combatant]: return formation)


func _clear_first_wave(battle: BattleEngine, hero: Combatant) -> void:
	battle.execute(hero.id)
	assert_true(Fixtures.run_until_phase(battle, BattleEngine.Phase.WAVE_CLEARED), "wave 1 cleared")


func test_a_cleared_wave_waits_for_the_next_one() -> void:
	var hero: Combatant = _hero()
	var second: Combatant = _weak("Second")
	var battle: BattleEngine = Fixtures.engine([hero], [_weak("First")])
	_queue(battle, [second])
	assert_eq(battle.wave_count(), 2)
	battle.start()
	_clear_first_wave(battle, hero)
	var cleared: Dictionary = battle.events.last_of_type(BattleEventLog.WAVE_CLEARED)
	assert_eq([int(cleared["wave"]), int(cleared["waves"])], [1, 2])
	assert_eq(battle.events.count_of_type(BattleEventLog.BATTLE_ENDED), 0)
	var frame_then: int = battle.frame
	battle.tick()
	assert_eq(battle.frame, frame_then, "the clock waits")
	assert_eq(battle.execute(hero.id), BattleEngine.REJECT_BATTLE_NOT_RUNNING)

	assert_eq(battle.begin_next_wave(), BattleEngine.OK)
	assert_eq([battle.wave, battle.turn, battle.total_turns], [2, 1, 2])
	assert_eq(battle.enemies, [second])
	assert_eq(second.slot, 0)
	assert_eq(battle.events.last_of_type(BattleEventLog.WAVE_STARTED)["enemies"], [second.id])
	assert_eq(battle.begin_next_wave(), BattleEngine.REJECT_NO_WAVE_WAITING)
	assert_eq(battle.execute(hero.id), BattleEngine.OK, "a fresh turn")
	assert_true(Fixtures.run_until_ended(battle))
	assert_eq(battle.outcome, BattleEngine.OUTCOME_VICTORY)
	assert_eq(int(battle.events.last_of_type(BattleEventLog.BATTLE_ENDED)["wave"]), 2)


func test_the_party_keeps_what_persists_into_the_next_wave() -> void:
	var hero: Combatant = Fixtures.unit("Hero", {"atk": 1000, "attack_frames": "4:100", "max_lb": 1000, "lb": 300})
	var afflicted: Combatant = Fixtures.unit("Afflicted")
	var fallen: Combatant = Fixtures.unit("Fallen")
	var battle: BattleEngine = Fixtures.engine([hero, afflicted, fallen], [_weak("First")])
	_queue(battle, [_weak("Second")])
	for key in ["POISON", "BLIND", "SILENCE", "DISEASE", "PETRIFY", "STOP", "SLEEP", "PARALYSIS", "CONFUSION", "ZOMBIE"]:
		battle.debug_edit(afflicted.id, &"ailment", 3, key)
	hero.add_status(BattleStatus.make(BattleStatus.STAT, "ATK", 50, 3))
	hero.hp = 600
	battle.start()
	battle.debug_edit(fallen.id, &"hp", 0)
	hero.skill_state["130"] = {"uses_left": 0, "ready_turn": 9}
	afflicted.chain_count = 3
	_clear_first_wave(battle, hero)

	var kept: Array = []
	for status in afflicted.statuses_of(BattleStatus.AILMENT):
		kept.append(status.key)
	kept.sort()
	assert_eq(kept, ["BLIND", "DISEASE", "PETRIFY", "POISON", "SILENCE", "STOP"])
	var dropped: Array = []
	for event in Fixtures.events_on(battle, BattleEventLog.STATUS_REMOVED, afflicted.id):
		if event["reason"] == &"battle_end":
			dropped.append(event["key"])
	dropped.sort()
	assert_eq(dropped, ["CONFUSION", "PARALYSIS", "SLEEP", "ZOMBIE"])
	assert_eq(hero.find_status(BattleStatus.STAT, "ATK").turns_left, 3, "buffs keep their turns")
	assert_eq([hero.hp, hero.lb], [600, 300])
	assert_true(hero.skill_state.is_empty(), "cooldowns and uses reset")
	assert_eq(afflicted.chain_count, 0)
	battle.begin_next_wave()
	assert_false(fallen.is_alive(), "KO'd units stay down")
	assert_eq(battle.units_to_act(), [hero])


func test_poison_can_clear_a_wave_at_the_end_of_a_turn() -> void:
	var rules: BattleRules = Fixtures.rules()
	rules.enemy_ailment_recovery_pct = 0
	var hero: Combatant = Fixtures.unit("Hero")
	var first: Combatant = Fixtures.monster("First", {"brain": IdleEnemyBrain.new()})
	first.hp = 500
	var battle: BattleEngine = Fixtures.engine([hero], [first], rules)
	_queue(battle, [_weak("Second")])
	battle.debug_edit(first.id, &"ailment", 1, "POISON")
	battle.start()
	battle.execute(hero.id, BattleCommand.defend())
	assert_true(Fixtures.run_until_phase(battle, BattleEngine.Phase.WAVE_CLEARED))
	assert_eq(battle.events.count_of_type(BattleEventLog.TURN_ENDED), 0, "the turn does not end")
	battle.begin_next_wave()
	assert_eq([battle.wave, battle.turn], [2, 1])


func test_the_session_starts_the_next_wave_itself_and_skips_empty_ones() -> void:
	var session := BattleSession.new()
	var factory: Callable = func(seed_value: int) -> BattleEngine:
		var battle: BattleEngine = Fixtures.engine([_hero()], [_weak("First")], null, null, seed_value)
		_queue(battle, [])
		_queue(battle, [_weak("Third")])
		return battle
	session.start(factory, 7)
	session.execute(session.engine.party_members()[0].id)
	session.step(10)
	assert_eq([session.engine.wave, session.engine.phase], [3, BattleEngine.Phase.PLAYER])
	assert_eq(session.engine.enemies[0].name, "Third")

	session.auto_advance_waves = false
	session.restart()
	session.execute(session.engine.party_members()[0].id)
	session.step(10)
	assert_eq(session.engine.phase, BattleEngine.Phase.WAVE_CLEARED, "held until the host says so")
	assert_eq(session.begin_next_wave(), BattleEngine.OK)
	assert_eq([session.engine.wave, session.engine.phase], [2, BattleEngine.Phase.WAVE_CLEARED], "the empty wave clears at once")
	session.free()
