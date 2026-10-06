extends "res://tests/test_case.gd"

## BattleSession: the fixed 60 Hz step at any render rate and speed, pause and single
## stepping, commands passing through with their events, and restarts with the same or a
## new seed. _process is called directly, so no real frames are needed.

const Fixtures = preload("res://tests/battle/battle_fixtures.gd")

var _session: BattleSession = null
var _emitted: Array[Dictionary] = []
var _started: int = 0


func before_each() -> void:
	_session = BattleSession.new()
	_session.battle_started.connect(func(_engine: BattleEngine) -> void: _started += 1)
	_session.events_emitted.connect(func(events: Array[Dictionary]) -> void: _emitted.append_array(events))


func after_each() -> void:
	_session.free()


## A hero against a sturdy dummy that never acts, with random damage on so seeds matter.
func _factory(seed_value: int) -> BattleEngine:
	var rules: BattleRules = Fixtures.rules()
	rules.damage_variance_min = 0.5
	rules.damage_variance_max = 1.5
	var hero: Combatant = Fixtures.unit("Hero", {"attack_frames": "10:50-20:50"})
	var dummy: Combatant = Fixtures.monster("Dummy", {"brain": IdleEnemyBrain.new()})
	return Fixtures.engine([hero], [dummy], rules, null, seed_value)


func _start(seed_value: int = 7) -> void:
	_session.start(_factory, seed_value)


func _amounts() -> Array[int]:
	var out: Array[int] = []
	for event in _emitted:
		if event["type"] == BattleEventLog.HIT_LANDED:
			out.append(int(event["amount"]))
	return out


func test_start_emits_the_opening_events() -> void:
	_start()
	assert_eq(_started, 1)
	assert_not_null(_session.engine)
	assert_eq(_session.engine.phase, BattleEngine.Phase.PLAYER)
	assert_eq(_emitted[0]["type"], BattleEventLog.BATTLE_STARTED)
	assert_true(_session.engine.events.keep_history, "the sandbox keeps the whole log")


func test_one_tick_per_sixtieth_of_a_second_at_any_frame_rate() -> void:
	_start()
	_session._process(1.0 / 60.0)
	assert_eq(_session.engine.frame, 1, "60 fps: one tick per frame")
	_session._process(1.0 / 30.0)
	assert_eq(_session.engine.frame, 3, "30 fps: two ticks per frame")
	for _i in range(8):
		_session._process(1.0 / 240.0)
	assert_eq(_session.engine.frame, 5, "240 fps: one tick every four frames")


func test_speed_scales_time_and_is_clamped() -> void:
	_start()
	_session.speed = 2.0
	_session._process(1.0 / 60.0)
	assert_eq(_session.engine.frame, 2)
	_session.speed = 0.25
	for _i in range(4):
		_session._process(1.0 / 60.0)
	assert_eq(_session.engine.frame, 3)
	_session.speed = 100.0
	assert_eq(_session.speed, BattleSession.MAX_SPEED)
	_session.speed = 0.0
	assert_eq(_session.speed, BattleSession.MIN_SPEED)


func test_a_long_frame_runs_at_most_the_tick_cap() -> void:
	_start()
	_session._process(1.0)
	assert_eq(_session.engine.frame, BattleSession.MAX_TICKS_PER_FRAME)
	_session._process(1.0 / 60.0)
	assert_true(_session.engine.frame <= BattleSession.MAX_TICKS_PER_FRAME + 2, "the backlog is dropped, not replayed")


func test_paused_holds_the_clock_and_step_still_runs() -> void:
	_start()
	_session.paused = true
	_session._process(0.5)
	assert_eq(_session.engine.frame, 0)
	_session.step(5)
	assert_eq(_session.engine.frame, 5)


func test_commands_pass_through_and_emit_at_once() -> void:
	_start()
	_emitted.clear()
	var hero: Combatant = _session.engine.party_members()[0]
	assert_eq(_session.execute(hero.id), BattleEngine.OK)
	assert_eq(_emitted.size() > 0 and _emitted[0]["type"] == BattleEventLog.ACTION_STARTED, true, "emitted before any tick")
	assert_eq(_session.execute(hero.id), BattleEngine.REJECT_ALREADY_ACTED)
	assert_eq(_emitted[-1]["type"], BattleEventLog.COMMAND_REJECTED)
	_session.step(20)
	assert_eq(_amounts().size(), 2, "both hits landed and were emitted")


func test_restart_replays_the_same_seed_and_can_take_a_new_one() -> void:
	_start(11)
	var hero_id: int = _session.engine.party_members()[0].id
	_session.execute(hero_id)
	_session.step(30)
	var first: Array[int] = _amounts()
	assert_eq(first.size(), 2)

	_emitted.clear()
	_session.restart()
	assert_eq(_started, 2)
	assert_eq(_session.battle_seed, 11)
	assert_eq(_session.engine.frame, 0, "a fresh engine")
	_session.execute(_session.engine.party_members()[0].id)
	_session.step(30)
	assert_eq(_amounts(), first, "same seed, same rolls")

	_emitted.clear()
	_session.restart(12345)
	assert_eq(_session.battle_seed, 12345)
	_session.execute(_session.engine.party_members()[0].id)
	_session.step(30)
	assert_ne(_amounts(), first, "another seed rolls other damage")


func test_nothing_happens_before_start() -> void:
	_session.step(3)
	_session.restart()
	_session._process(1.0)
	assert_null(_session.engine)
	assert_eq(_session.execute(1), BattleEngine.REJECT_BATTLE_NOT_RUNNING)
