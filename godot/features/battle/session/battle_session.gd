class_name BattleSession
extends Node

## Runs one BattleEngine in real time. Each frame adds delta x speed to an accumulator
## and ticks the engine once per 1/60 s of it, so hits land on the same frames at any
## render rate (the old engine ticked once per rendered frame, which with
## run/max_fps=240 landed hits early on fast screens). After every batch of ticks and
## every command it drains the engine's events and emits them.
##
## The session builds its engine through a factory, Callable(seed: int) -> BattleEngine
## returning an engine not yet started, so restart() can rebuild the same battle with
## the same seed or a new one. It knows nothing about the UI that drives it: the
## sandbox uses it now, BattleUI later.
##
## Read state through `engine`; send commands through the session so their events go
## out at once. When a wave is cleared the session starts the next one at once, unless
## auto_advance_waves is off; then the host calls begin_next_wave() when it is ready.

## A new engine is built and about to start; its combatants exist. Listeners reset
## their views here, then receive the start events through events_emitted.
signal battle_started(engine: BattleEngine)
## Events appended since the previous emit, in order.
signal events_emitted(events: Array[Dictionary])
## The engine ran one or more ticks; `frame` is the engine's frame now.
signal frames_advanced(frame: int)

const MIN_SPEED: float = 0.25
const MAX_SPEED: float = 4.0
## Most ticks one rendered frame may run. A slower frame drops the rest of its backlog
## instead of trying to catch up.
const MAX_TICKS_PER_FRAME: int = 16
const TICK_SECONDS: float = 1.0 / BattleRules.TICKS_PER_SECOND
## Absorbs float error so an exact 1/60 s delta always counts as one tick.
const _EPSILON: float = 1e-6

## The running battle, or null before start(). Read-only for listeners.
var engine: BattleEngine = null
var battle_seed: int = 0
var paused: bool = false
var speed: float = 1.0:
	set(value):
		speed = clampf(value, MIN_SPEED, MAX_SPEED)
## Passed to each engine's event log. The sandbox keeps the whole log; a long real
## battle can turn it off.
var keep_history: bool = true
## Whether the next wave starts as soon as one is cleared. BattleUI will turn it off to
## play its wave transition and dialogue first.
var auto_advance_waves: bool = true

var _factory: Callable = Callable()
var _accumulator: float = 0.0


## Builds the battle with `factory` for `seed_value`, starts it and emits its first
## events. The session keeps the factory for restart().
func start(factory: Callable, seed_value: int) -> void:
	_factory = factory
	_begin(seed_value)


## Rebuilds the battle from the same factory: the same seed, or `seed_value` when it
## is not negative. Does nothing before start().
func restart(seed_value: int = -1) -> void:
	if not _factory.is_valid():
		return
	_begin(seed_value if seed_value >= 0 else battle_seed)


## Runs `frames` ticks now, paused or not (single-frame stepping).
func step(frames: int = 1) -> void:
	if engine == null or frames <= 0:
		return
	for _i in range(frames):
		engine.tick()
	_after_ticks()


func is_running() -> bool:
	return engine != null and engine.is_running()


# === Commands (forwarded to the engine) ===

func queue_command(unit_id: int, command: BattleCommand) -> StringName:
	if engine == null:
		return BattleEngine.REJECT_BATTLE_NOT_RUNNING
	var result: StringName = engine.queue_command(unit_id, command)
	flush_events()
	return result


func set_target(unit_id: int, target_id: int) -> StringName:
	if engine == null:
		return BattleEngine.REJECT_BATTLE_NOT_RUNNING
	var result: StringName = engine.set_target(unit_id, target_id)
	flush_events()
	return result


func execute(unit_id: int, command: BattleCommand = null) -> StringName:
	if engine == null:
		return BattleEngine.REJECT_BATTLE_NOT_RUNNING
	var result: StringName = engine.execute(unit_id, command)
	flush_events()
	return result


## Unit id -> result, as BattleEngine.execute_many.
func execute_many(unit_ids: Array) -> Dictionary:
	if engine == null:
		return {}
	var results: Dictionary = engine.execute_many(unit_ids)
	flush_events()
	return results


## After a WAVE_CLEARED event: starts the next wave (see auto_advance_waves).
func begin_next_wave() -> StringName:
	if engine == null:
		return BattleEngine.REJECT_BATTLE_NOT_RUNNING
	var result: StringName = engine.begin_next_wave()
	flush_events()
	return result


## Emits the events appended since the last emit (after a call made on the engine
## directly, such as a debug edit) and returns them. Starts the next wave first when
## one was cleared and auto_advance_waves is on.
func flush_events() -> Array[Dictionary]:
	if engine == null:
		return []
	var fresh: Array[Dictionary] = engine.events.drain()
	while auto_advance_waves and engine.phase == BattleEngine.Phase.WAVE_CLEARED:
		engine.begin_next_wave()
		fresh.append_array(engine.events.drain())
	if not fresh.is_empty():
		events_emitted.emit(fresh)
	return fresh


# === Internals ===

func _process(delta: float) -> void:
	if not is_running() or paused:
		_accumulator = 0.0
		return
	_accumulator += delta * speed
	var ticks: int = 0
	while _accumulator + _EPSILON >= TICK_SECONDS and ticks < MAX_TICKS_PER_FRAME:
		_accumulator -= TICK_SECONDS
		engine.tick()
		ticks += 1
	if ticks >= MAX_TICKS_PER_FRAME:
		_accumulator = minf(_accumulator, TICK_SECONDS)
	if ticks > 0:
		_after_ticks()


func _begin(seed_value: int) -> void:
	battle_seed = seed_value
	_accumulator = 0.0
	var built: Variant = _factory.call(seed_value)
	if not built is BattleEngine:
		push_error("BattleSession: the factory returned no BattleEngine")
		engine = null
		return
	engine = built
	engine.events.keep_history = keep_history
	battle_started.emit(engine)
	engine.start()
	flush_events()
	frames_advanced.emit(engine.frame)


func _after_ticks() -> void:
	flush_events()
	frames_advanced.emit(engine.frame)
