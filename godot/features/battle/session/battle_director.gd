class_name BattleDirector
extends Node

## The mission around the fight, next to the BattleSession in the battle scene: the
## intro, the wave transitions with their dialogue and cutscenes, the rewards, the
## challenges, BattleEvents, and the mission end. Ported from the old BattleManager's
## flow (initialize_battle's intro, _trigger_wave_clear, _spawn_next_wave,
## _trigger_mission_complete, _trigger_defeat), keeping its 1.0 s and 2.0 s waits.
##
## It asks the battle screen for dialogue and the wave transition through signals and
## waits for the answer (dialogue_finished(), transition_finished()), as the old
## play_dialogue awaited dialogue_completed. An answer may come at once, from inside the
## signal. The session is paused while dialogue shows.
##
##   start(params)   builds the battle (BattleBuilder), pauses and starts the session,
##                   plays the slot 0 cutscenes and wave 1's opening dialogue, unpauses
##   WAVE_CLEARED    1.0 s, the wave's victory dialogue, the cutscenes after it, the
##                   transition (2.0 s and the screen's answer), begin_next_wave(), the
##                   new wave's opening dialogue
##   victory         1.0 s, the last wave's victory dialogue and the outro cutscenes,
##                   BattleEvents.mission_completed, the challenge results, finisher(true, ...)
##   defeat          the challenges disconnected, finisher(false, ...)
##
## The flows run one at a time, in the order their events came, each once the
## director has taken the whole event batch. With the real waits they resume on a later
## frame; with instant ones (tests) they run inside the session's call, and a flow an
## inner batch asks for (an empty wave cleared at once) waits for the current one.
##
## Every service call that writes a save goes through a Callable a test replaces:
## `finisher` (MissionService.request_finish_mission) and `kill_recorder`
## (PlayerProfile.record_monster_kill). `wait` makes the timed pauses.

## Show these [{ speaker, text }] lines; answer with dialogue_finished().
signal dialogue_requested(lines: Array)
## Play the wave counter roll from `wave` to `next_wave` of `waves`; answer with
## transition_finished().
signal wave_transition_requested(wave: int, next_wave: int, waves: int)
## A defeated enemy dropped `item_id`.
signal item_dropped(enemy_id: int, item_id: String)

signal _dialogue_answered
signal _transition_answered

## The old engine's wait for the death tweens before a cleared wave moves on.
const DEATH_TWEEN_SECONDS: float = 1.0
## The old engine's wait for the wave counter roll before the next wave spawns.
const WAVE_TRANSITION_SECONDS: float = 2.0

@export var session: BattleSession = null

## Callable(win: bool, mission_id: String, used_items: Dictionary, challenge_results:
## Array, drops: Array, unit_exp: int, gil: int), MissionService.request_finish_mission's
## signature. The real one writes a save.
var finisher: Callable
## Callable(template_id: String). The real one writes a save.
var kill_recorder: Callable
## Callable(seconds: float) -> a Signal to await, or null to go on at once.
var wait: Callable

## Prints each wave's monster AI (MonsterAIResolver: skills and rules) to the console
## when the wave starts, as the old engine did. On in debug builds; tests turn it off.
var print_monster_ai: bool = OS.is_debug_build()

## Set before start() to replace what start() would build from its params (tests): the
## engine factory (Callable(seed) -> BattleEngine), the story and the challenges.
var factory: Callable = Callable()
var story: BattleStory = null
var challenges: ChallengeSet = null

## "" for a battle group or the test battle (the old engine finished those with "" too).
var mission_id: String = ""
var ledger: RewardLedger = null
var bridge: BattleEventsBridge = null

## Set once the battle's end is decided (BATTLE_ENDED seen, or debug_finish()).
var _finished: bool = false
## WAVE_CLEARED and BATTLE_ENDED events whose flows have not run yet.
var _flows: Array[Dictionary] = []
## The intro or a flow is running; a new flow waits in _flows.
var _flow_running: bool = false
var _holds: int = 0
var _dialogue_pending: bool = false
var _transition_pending: bool = false


func _init() -> void:
	finisher = MissionService.request_finish_mission
	kill_recorder = PlayerProfile.record_monster_kill
	wait = _timer


func _exit_tree() -> void:
	if challenges != null:
		challenges.cleanup()


## Builds and starts the battle for `params` ({ mission_id }, { battle_group } or {}, as
## UIManager hands them to the battle scene) and plays its intro. A negative seed picks
## a random one. The session must be set.
func start(params: Dictionary, seed_value: int = -1) -> void:
	if session == null:
		push_error("BattleDirector.start: no session")
		return
	mission_id = str(params.get("mission_id", ""))
	if story == null:
		story = BattleStory.for_params(params)
	if challenges == null:
		challenges = ChallengeSet.for_params(params)
	var battle_seed: int = seed_value if seed_value >= 0 else randi()
	ledger = RewardLedger.new(battle_seed)
	ledger.item_dropped.connect(func(enemy_id: int, item_id: String) -> void: item_dropped.emit(enemy_id, item_id))
	ledger.monster_killed.connect(func(template_id: String) -> void: kill_recorder.call(template_id))
	bridge = BattleEventsBridge.new()
	if not session.events_emitted.is_connected(_on_events):
		session.events_emitted.connect(_on_events)
	session.auto_advance_waves = false

	_hold()
	_flow_running = true
	session.start(factory if factory.is_valid() else _builder_factory(params), battle_seed)
	if session.engine == null:
		_flow_running = false
		_release()
		return
	await _play_cutscenes(0)
	# A battle with no enemies (an exploration mission) is won before it starts: no
	# wave 1 to open.
	if not _finished:
		await _play_dialogue(story.wave_dialogue_lines(1, BattleStory.COND_START))
	_release()
	_flow_running = false
	await _run_flows()


## The battle screen has shown the requested dialogue.
func dialogue_finished() -> void:
	if not _dialogue_pending:
		return
	_dialogue_pending = false
	_dialogue_answered.emit()


## The battle screen has played the requested wave transition.
func transition_finished() -> void:
	if not _transition_pending:
		return
	_transition_pending = false
	_transition_answered.emit()


## The debug Finish button: the victory path at once, without the fight, as the old
## _trigger_mission_complete did. Does nothing once the battle is over.
func debug_finish() -> void:
	if _finished or session == null or session.engine == null:
		return
	_finished = true
	_hold()
	_complete_mission()


## Whether the mission has been reported (or is being wrapped up).
func is_finished() -> bool:
	return _finished


# === Events ===

func _on_events(events: Array[Dictionary]) -> void:
	if _finished or session.engine == null:
		return
	var engine: BattleEngine = session.engine
	ledger.record(engine, events)
	bridge.relay(engine, events)
	var queued: bool = false
	for event in events:
		if print_monster_ai and (event["type"] == BattleEventLog.BATTLE_STARTED or event["type"] == BattleEventLog.WAVE_STARTED):
			_print_wave_ai(engine)
		if event["type"] == BattleEventLog.WAVE_CLEARED or event["type"] == BattleEventLog.BATTLE_ENDED:
			_flows.append(event)
			queued = true
			if event["type"] == BattleEventLog.BATTLE_ENDED:
				_finished = true
	if queued and not _flow_running:
		_run_flows()


func _run_flows() -> void:
	_flow_running = true
	while not _flows.is_empty():
		var event: Dictionary = _flows.pop_front()
		if event["type"] == BattleEventLog.BATTLE_ENDED:
			await _end_battle(event)
		elif not _finished:
			await _next_wave(event)
	_flow_running = false


func _next_wave(cleared: Dictionary) -> void:
	var wave: int = int(cleared.get("wave", 1))
	var waves: int = int(cleared.get("waves", wave + 1))
	_hold()
	await _wait(DEATH_TWEEN_SECONDS)
	await _play_dialogue(story.wave_dialogue_lines(wave, BattleStory.COND_VICTORY))
	await _play_cutscenes(wave)
	if not _finished:
		await _play_transition(wave, wave + 1, waves)
	if not _finished:
		session.begin_next_wave()
		await _play_dialogue(story.wave_dialogue_lines(wave + 1, BattleStory.COND_START))
	_release()


func _end_battle(ended: Dictionary) -> void:
	if StringName(ended.get("outcome", &"")) != BattleEngine.OUTCOME_VICTORY:
		challenges.cleanup()
		finisher.call(false, mission_id, ledger.used_items.duplicate(), [], [], 0, 0)
		return
	var wave: int = int(ended.get("wave", 1))
	await _wait(DEATH_TWEEN_SECONDS)
	await _play_dialogue(story.wave_dialogue_lines(wave, BattleStory.COND_VICTORY))
	await _play_cutscenes(wave)
	_complete_mission()


func _complete_mission() -> void:
	bridge.mission_completed(session.engine)
	var results: Array[bool] = challenges.evaluate()
	finisher.call(true, mission_id, ledger.used_items.duplicate(), results, ledger.drops.duplicate(), ledger.unit_exp, ledger.gil)


func _print_wave_ai(engine: BattleEngine) -> void:
	if engine.enemies.is_empty():
		return
	print("
########## Wave %d monster AI (mission %s) ##########" % [engine.wave, mission_id])
	for foe in engine.enemies:
		MonsterAIResolver.print_behaviour(foe.source_id)


# === Requests to the screen ===

## Shows `lines` and waits until the screen answers, with the battle paused. Nothing to
## wait for when the lines are empty or nobody listens.
func _play_dialogue(lines: Array) -> void:
	if lines.is_empty() or dialogue_requested.get_connections().is_empty():
		return
	_hold()
	_dialogue_pending = true
	dialogue_requested.emit(lines)
	if _dialogue_pending:
		await _dialogue_answered
	_release()


## Each cutscene slotted at `slot` as its own dialogue, as the old engine showed them.
func _play_cutscenes(slot: int) -> void:
	for card in story.cutscene_cards(slot):
		await _play_dialogue([card])


## The old 2.0 s wait for the wave counter roll, then the screen's answer if it has not
## come yet.
func _play_transition(wave: int, next_wave: int, waves: int) -> void:
	_transition_pending = not wave_transition_requested.get_connections().is_empty()
	wave_transition_requested.emit(wave, next_wave, waves)
	await _wait(WAVE_TRANSITION_SECONDS)
	if _transition_pending:
		await _transition_answered


func _wait(seconds: float) -> void:
	var waiting: Variant = wait.call(seconds)
	if waiting is Signal:
		await waiting


func _timer(seconds: float) -> Signal:
	return get_tree().create_timer(seconds).timeout


# === Internals ===

## The director's own pauses nest (a dialogue inside a wave transition): the session
## runs again once the last one ends.
func _hold() -> void:
	_holds += 1
	session.paused = true


func _release() -> void:
	_holds = maxi(0, _holds - 1)
	if _holds == 0:
		session.paused = false


static func _builder_factory(params: Dictionary) -> Callable:
	return func(seed_value: int) -> BattleEngine: return BattleBuilder.new(null, null, seed_value).build(params)
