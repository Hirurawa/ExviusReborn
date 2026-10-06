extends "res://tests/test_case.gd"

## The player side of the engine: concurrent actions, chains across units, kills, the
## end of the battle, command checks and replay determinism. Every fixture unit has
## 100 in each stat, so a basic attack on a 100-DEF target deals 100 before chains.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")


func _frames(events: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	for event in events:
		out.append(int(event["frame"]))
	return out


func _chains(events: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	for event in events:
		out.append(int(event["chain"]))
	return out


func test_two_units_chain_on_one_target() -> void:
	var lasswell: Combatant = Fixtures.unit("Lasswell", {"attack_frames": "4:100"})
	var rain: Combatant = Fixtures.unit("Rain", {"attack_frames": "15:60-36:40"})
	var foe: Combatant = Fixtures.monster("Zu")
	var battle: BattleEngine = Fixtures.engine([lasswell, rain], [foe])
	battle.start()

	assert_eq(battle.execute(lasswell.id), BattleEngine.OK)
	assert_eq(battle.execute(rain.id), BattleEngine.OK)
	battle.advance(40)

	var landed: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(_frames(landed), [4, 15, 36])
	# Rain's first hit lands 11 frames after Lasswell's: chain 1, x1.1 on 60.
	# Her second lands 21 frames after that: the chain breaks.
	assert_eq(_chains(landed), [0, 1, 0])
	assert_eq(Fixtures.amounts(landed), [100, 66, 40])
	assert_eq(foe.hp, foe.max_hp - 206)


func test_hits_of_units_cast_together_land_in_party_order() -> void:
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "10:100"})
	var b: Combatant = Fixtures.unit("B", {"attack_frames": "10:100"})
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a, b], [foe])
	battle.start()
	battle.execute(b.id)
	battle.execute(a.id)
	battle.advance(10)
	var landed: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(int(landed[0]["actor"]), a.id, "A is in the first slot, so it counts first although B was executed first")
	assert_eq(Fixtures.amounts(landed), [100, 140], "B's hit on the same frame is a spark chain")
	assert_true(bool(landed[1]["spark"]))


func test_party_order_decides_whether_a_unit_hits_twice_in_a_row() -> void:
	# Both cast on frame 0. On frame 20, A (first slot) counts before B, so A's second
	# hit follows its first and ends the chain; B's hit then starts a new one with a spark.
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "10:50-20:50"})
	var b: Combatant = Fixtures.unit("B", {"attack_frames": "20:100"})
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a, b], [foe])
	battle.start()
	battle.execute(b.id)
	battle.execute(a.id)
	battle.advance(20)
	var landed: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(landed.map(func(event: Dictionary) -> int: return int(event["actor"])), [a.id, a.id, b.id])
	assert_eq(_chains(landed), [0, 0, 1])
	assert_eq(Fixtures.amounts(landed), [50, 50, 140])


func test_an_earlier_cast_lands_first_on_a_shared_frame() -> void:
	# B declares first; A declares 5 frames later with a hit 5 frames sooner, so both land
	# on frame 15. Party order only applies to units that cast at the same time.
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "10:100"})
	var b: Combatant = Fixtures.unit("B", {"attack_frames": "15:100"})
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a, b], [foe])
	battle.start()
	battle.execute(b.id)
	battle.advance(5)
	battle.execute(a.id)
	battle.advance(10)
	var landed: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(_frames(landed), [15, 15])
	assert_eq(int(landed[0]["actor"]), b.id)
	assert_eq(Fixtures.amounts(landed), [100, 140])


func test_units_act_while_earlier_actions_are_still_landing() -> void:
	var slow: Combatant = Fixtures.unit("Slow", {"attack_frames": "30:100"})
	var quick: Combatant = Fixtures.unit("Quick", {"attack_frames": "10:100"})
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([slow, quick], [foe])
	battle.start()

	battle.execute(slow.id)
	battle.advance(5)
	assert_eq(battle.execute(quick.id), BattleEngine.OK, "a second unit can act mid-action")
	battle.advance(10)
	assert_eq(battle.phase, BattleEngine.Phase.PLAYER, "Slow's hit is still in flight")
	battle.advance(15)

	var landed: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(_frames(landed), [15, 30])
	assert_eq(Fixtures.amounts(landed), [100, 110], "Slow's hit chains on Quick's")
	assert_eq(battle.phase, BattleEngine.Phase.ENEMY, "the phase ends once the last hit has landed")


func test_player_phase_waits_for_every_living_unit() -> void:
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "4:100"})
	var b: Combatant = Fixtures.unit("B")
	var fallen: Combatant = Fixtures.unit("Fallen")
	fallen.hp = 0
	var battle: BattleEngine = Fixtures.engine([a, b, fallen], [Fixtures.monster("Foe")])
	battle.start()
	battle.execute(a.id)
	battle.advance(30)
	assert_eq(battle.phase, BattleEngine.Phase.PLAYER, "B has not acted")
	assert_eq(battle.units_to_act(), [b], "a fallen unit is not waited for")
	battle.execute(b.id)
	battle.advance(30)
	assert_eq(battle.phase, BattleEngine.Phase.ENEMY)


func test_a_kill_ends_the_battle_once_the_last_hit_lands() -> void:
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "4:100"})
	var b: Combatant = Fixtures.unit("B", {"attack_frames": "6:100"})
	var c: Combatant = Fixtures.unit("C", {"attack_frames": "12:100"})
	var foe: Combatant = Fixtures.monster("Weakling", {"hp": 150})
	var battle: BattleEngine = Fixtures.engine([a, b, c], [foe])
	battle.start()
	battle.execute_many([a.id, b.id, c.id])
	battle.advance(30)

	var landed: Array[Dictionary] = Fixtures.hits(battle, foe.id)
	assert_eq(Fixtures.amounts(landed), [100, 110], "B's chained hit deals 110")
	assert_eq(int(landed[1]["hp_lost"]), 50, "only 50 HP were left")

	var defeated: Dictionary = battle.events.last_of_type(BattleEventLog.COMBATANT_DEFEATED)
	assert_eq(int(defeated.get("target", -1)), foe.id)
	assert_eq(int(defeated.get("by", -1)), b.id)
	assert_eq(int(defeated.get("frame", -1)), 6)

	var missed: Dictionary = battle.events.last_of_type(BattleEventLog.HIT_MISSED)
	assert_eq(int(missed.get("actor", -1)), c.id, "C's hit lands on a dead target")
	assert_eq(missed.get("reason", &""), &"target_down")

	var ended: Dictionary = battle.events.last_of_type(BattleEventLog.BATTLE_ENDED)
	assert_eq(ended.get("outcome", &""), BattleEngine.OUTCOME_VICTORY)
	assert_eq(int(ended.get("frame", -1)), 12, "the battle ends after the last scheduled hit")
	assert_eq(battle.phase, BattleEngine.Phase.ENDED)
	assert_eq(battle.frame, 12, "ticks after the end do nothing")
	assert_eq(battle.events.count_of_type(BattleEventLog.BATTLE_ENDED), 1)


func test_actions_start_and_end_around_their_hits() -> void:
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "4:50-9:50"})
	var battle: BattleEngine = Fixtures.engine([a], [Fixtures.monster("Foe")])
	battle.start()
	battle.execute(a.id)
	battle.advance(9)
	var started: Dictionary = Fixtures.actions_by(battle, a.id)[0]
	assert_eq(int(started["frame"]), 0)
	assert_eq(started["origin"], BattleAction.Origin.COMMAND)
	var ended: Array[Dictionary] = []
	for event in battle.events.of_type(BattleEventLog.ACTION_ENDED):
		if int(event["action"]) == int(started["action"]):
			ended.append(event)
	assert_eq(ended.size(), 1)
	assert_eq(int(ended[0]["frame"]), 9, "the action ends on its last hit")


func test_queued_command_and_target_are_used_by_execute() -> void:
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "4:100"})
	var first: Combatant = Fixtures.monster("First")
	var second: Combatant = Fixtures.monster("Second")
	var battle: BattleEngine = Fixtures.engine([a], [first, second])
	battle.start()
	assert_eq(battle.set_target(a.id, second.id), BattleEngine.OK)
	battle.execute(a.id)
	battle.advance(4)
	assert_eq(Fixtures.hits(battle, second.id).size(), 1)
	assert_eq(Fixtures.hits(battle, first.id).size(), 0)
	assert_eq(a.last_command.target_id, second.id, "the executed command is kept for repeat")


func test_a_dead_pick_falls_back_to_the_first_living_enemy() -> void:
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "4:100"})
	var first: Combatant = Fixtures.monster("First")
	var gone: Combatant = Fixtures.monster("Gone")
	gone.hp = 0
	var battle: BattleEngine = Fixtures.engine([a], [first, gone])
	battle.start()
	battle.execute(a.id, BattleCommand.attack(gone.id))
	battle.advance(4)
	assert_eq(Fixtures.hits(battle, first.id).size(), 1)


func test_commands_are_checked() -> void:
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "4:100"})
	var fallen: Combatant = Fixtures.unit("Fallen")
	fallen.hp = 0
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a, fallen], [foe])

	assert_eq(battle.execute(a.id), BattleEngine.REJECT_BATTLE_NOT_RUNNING, "before start")
	battle.start()
	assert_eq(battle.execute(999), BattleEngine.REJECT_UNKNOWN_UNIT)
	assert_eq(battle.execute(foe.id), BattleEngine.REJECT_NOT_PARTY_MEMBER)
	assert_eq(battle.execute(fallen.id), BattleEngine.REJECT_UNIT_DOWN)
	assert_eq(battle.set_target(a.id, 999), BattleEngine.REJECT_UNKNOWN_TARGET)
	assert_eq(battle.execute(a.id), BattleEngine.OK)
	assert_eq(battle.execute(a.id), BattleEngine.REJECT_ALREADY_ACTED)
	assert_eq(battle.events.count_of_type(BattleEventLog.COMMAND_REJECTED), 6)

	Fixtures.run_until_phase(battle, BattleEngine.Phase.ENEMY)
	assert_eq(battle.can_execute(a.id), BattleEngine.REJECT_NOT_PLAYER_PHASE)


func test_turns_reset_unit_state() -> void:
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "4:100"})
	var battle: BattleEngine = Fixtures.engine([a], [Fixtures.monster("Foe")])
	battle.start()
	battle.queue_command(a.id, BattleCommand.defend())
	battle.execute(a.id)
	assert_true(a.defending)
	assert_true(Fixtures.run_until(battle, func() -> bool: return battle.turn == 2))
	assert_false(a.acted)
	assert_false(a.defending)
	assert_null(a.queued_command)
	var turns: Array = []
	for event in battle.events.of_type(BattleEventLog.TURN_STARTED):
		turns.append(int(event["turn"]))
	assert_eq(turns, [1, 2])


func test_event_log_reads_as_text() -> void:
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "4:100"})
	var b: Combatant = Fixtures.unit("B", {"attack_frames": "6:100"})
	var foe: Combatant = Fixtures.monster("Foe")
	var battle: BattleEngine = Fixtures.engine([a, b], [foe])
	battle.start()
	battle.execute_many([a.id, b.id])
	battle.advance(6)
	var chained: Dictionary = Fixtures.hits(battle, foe.id)[1]
	assert_eq(battle.format_event(chained), "f6     hit_landed B#2 -> Foe#3 110 (chain 1 x1.10) hp 99790/100000")
	assert_true(battle.dump_events().contains("phase_changed player (turn 1)"))
	var drained: Array[Dictionary] = battle.events.drain()
	assert_eq(drained.size(), battle.events.size())
	assert_eq(battle.events.drain().size(), 0, "drain only returns new events")


func test_empty_formation_is_won_at_once() -> void:
	var battle: BattleEngine = Fixtures.engine([Fixtures.unit("A")], [])
	battle.start()
	assert_eq(battle.outcome, BattleEngine.OUTCOME_VICTORY)


func _scripted_battle(seed_value: int) -> String:
	var battle_rules: BattleRules = Fixtures.rules()
	battle_rules.damage_variance_min = 0.85
	battle_rules.lb_crystal_drop_chance = 0.5
	var a: Combatant = Fixtures.unit("A", {"attack_frames": "4:50-9:50", "max_lb": 1000})
	var b: Combatant = Fixtures.unit("B", {"attack_frames": "7:100", "max_lb": 1000})
	var foes: Array = [Fixtures.monster("E1", {"hp": 3000}), Fixtures.monster("E2", {"hp": 3000})]
	var battle: BattleEngine = Fixtures.engine([a, b], foes, battle_rules, null, seed_value)
	battle.start()
	for _turn in range(3):
		battle.execute_many([a.id, b.id])
		Fixtures.run_until(battle, func() -> bool:
			return battle.phase == BattleEngine.Phase.ENDED or battle.units_to_act().size() == 2)
	return battle.dump_events()


func test_same_seed_and_commands_replay_identically() -> void:
	var first: String = _scripted_battle(11)
	assert_true(first.contains("hit_landed"), "the scripted battle produced hits")
	assert_eq(_scripted_battle(11), first)
	assert_ne(_scripted_battle(12), first, "a different seed rolls differently")
