class_name CombatSprite
extends TextureRect

## A unit's or monster's animated sprite: a state machine over its spritesheets (idle,
## attacks, standby poses, victory, and the dying and dead resting poses that HP picks).
## It knows nothing about battles: the battle screen pushes poses and HP in
## (play_action, play_queued, set_hp); the hub and the colosseum only call setup().

## What the sprite is playing right now. Exactly one state is active at a time,
## and only _enter() may assign it.
enum AnimState { IDLE, STANDBY, MAGIC_STANDBY, ATK, MAGIC_ATK, LIMIT_ATK, WIN_BEFORE, WIN }

## Which resting pose IDLE resolves to. Orthogonal to AnimState: it is derived
## from HP and outlives any single action.
enum HpState { HEALTHY, DYING, DEAD }

## Below this fraction of max HP the unit rests in its "dying" pose instead of idle.
const DYING_HP_RATIO: float = 0.1

## Where a state goes once it has played its loops out. States missing from the
## table (IDLE and the two standby poses) hold until something else transitions them.
const STATE_NEXT: Dictionary = {
	AnimState.ATK: AnimState.IDLE,
	AnimState.MAGIC_ATK: AnimState.IDLE,
	AnimState.LIMIT_ATK: AnimState.IDLE,
	AnimState.WIN_BEFORE: AnimState.WIN,
	AnimState.WIN: AnimState.IDLE
}

## Where a state goes when the unit has no spritesheet for it. _enter() walks
## this until it finds a state with real frames, so a unit missing magic_atk
## still swings instead of freezing.
const STATE_FALLBACK: Dictionary = {
	AnimState.STANDBY: AnimState.IDLE,
	AnimState.MAGIC_STANDBY: AnimState.IDLE,
	AnimState.MAGIC_ATK: AnimState.ATK,
	AnimState.LIMIT_ATK: AnimState.ATK,
	AnimState.ATK: AnimState.IDLE,
	AnimState.WIN_BEFORE: AnimState.WIN,
	AnimState.WIN: AnimState.IDLE
}

## How many times a state repeats before handing over to STATE_NEXT. Anything
## unlisted plays through once.
const STATE_LOOPS: Dictionary = {
	AnimState.MAGIC_ATK: 3,
	AnimState.WIN: 2
}

## Enemies swing twice per attack where units swing once.
const ENEMY_ATK_LOOPS: int = 2

## Frame delays are authored in 60ths of a second.
const FRAME_DELAY_UNIT: float = 1.0 / 60.0
const DEFAULT_FRAME_DELAY: int = 3

const LONG_PRESS_THRESHOLD: float = 0.5

# Spritesheets, loaded once in setup().
var idle_anim: Dictionary = {}
var atk_anim: Dictionary = {}
var standby_anim: Dictionary = {}
var magic_standby_anim: Dictionary = {}
var magic_atk_anim: Dictionary = {}
var limit_atk_anim: Dictionary = {}
var win_before_anim: Dictionary = {}
var win_anim: Dictionary = {}
var dying_anim: Dictionary = {}
var dead_anim: Dictionary = {}

var anim_state: AnimState = AnimState.IDLE
var hp_state: HpState = HpState.HEALTHY
var loop_count: int = 0
var current_frame_idx: int = 0
var current_frame_timer: float = 0.0

var is_enemy: bool = false
var current_hp: int = 1
var max_hp: int = 1

## What setup() was given to name this sprite in its signals: a party slot, or in
## battle the combatant id. Taps are ignored while it is negative.
var index: int = -1

signal short_tapped(index: int)
signal long_pressed(index: int)
## Emitted once the whole victory pose (win_before + STATE_LOOPS win loops) has
## played out, so the caller knows it can move on to the result screen.
signal win_finished(index: int)

var _is_pressed: bool = false
var _press_elapsed: float = 0.0
var _long_press_emitted: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if index < 0:
		return

	var press_started: bool = false
	var press_ended: bool = false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_started = true
		else:
			press_ended = true
	elif event is InputEventScreenTouch:
		if event.pressed:
			press_started = true
		else:
			press_ended = true

	if press_started:
		_is_pressed = true
		_press_elapsed = 0.0
		_long_press_emitted = false
	elif press_ended and _is_pressed:
		_is_pressed = false
		if not _long_press_emitted:
			short_tapped.emit(index)

## Loads `template_id`'s spritesheets (a unit id, or with `p_is_enemy` a monster id) and
## starts the idle pose. `p_index` names the sprite in its signals.
func setup(p_index: int, template_id: String, p_is_enemy: bool = false) -> void:
	index = p_index
	is_enemy = p_is_enemy

	# Load animation data using TextureBuilder
	if is_enemy:
		idle_anim = TextureBuilder.load_monster_animation_data(template_id, "idle")
		atk_anim = TextureBuilder.load_monster_animation_data(template_id, "atk")
	else:
		idle_anim = TextureBuilder.load_unit_animation_data(template_id, "idle")
		atk_anim = TextureBuilder.load_unit_animation_data(template_id, "atk")
		standby_anim = TextureBuilder.load_unit_animation_data(template_id, "standby")
		magic_standby_anim = TextureBuilder.load_unit_animation_data(template_id, "magic_standby")
		magic_atk_anim = TextureBuilder.load_unit_animation_data(template_id, "magic_atk")
		# The limit_atk sheets are the biggest on disk and are a likely candidate for
		# being dropped from an export; STATE_FALLBACK sends this back to a plain
		# attack when the folder isn't shipped.
		limit_atk_anim = TextureBuilder.load_unit_animation_data(template_id, "limit_atk")
		var win_anims: Dictionary = TextureBuilder.load_unit_win_animations(template_id)
		win_before_anim = win_anims[TextureBuilder.WIN_BEFORE_ANIM]
		win_anim = win_anims[TextureBuilder.WIN_ANIM]
		var hp_state_anims: Dictionary = TextureBuilder.load_unit_hp_state_animations(template_id)
		dying_anim = hp_state_anims[TextureBuilder.DYING_ANIM]
		dead_anim = hp_state_anims[TextureBuilder.DEAD_ANIM]

	# Visual fail-fast: If idle animation is missing, fallback to icon and turn neon pink
	if idle_anim.is_empty():
		if is_enemy:
			var icon_path = "res://assets/monster_icon/monster_icon_" + template_id + ".png"
			if ResourceLoader.exists(icon_path):
				texture = ResourceLoader.load(icon_path) as Texture2D
			else:
				texture = ResourceLoader.load("res://icon.svg") as Texture2D
		else:
			texture = ResourceLoader.load("res://icon.svg") as Texture2D
			modulate = Color(1, 0, 1, 1) # Neon pink
	else:
		_enter(AnimState.IDLE)

# === State machine ===

## The single entry point for every animation change. Resolves missing
## spritesheets through STATE_FALLBACK, then restarts playback from frame 0.
func _enter(state: AnimState) -> void:
	hp_state = _resolve_hp_state()

	var resolved: AnimState = state
	while not _has_frames(_anim_for_state(resolved)) and STATE_FALLBACK.has(resolved):
		resolved = STATE_FALLBACK[resolved]

	anim_state = resolved
	loop_count = 0
	current_frame_idx = 0
	current_frame_timer = 0.0

	var anim: Dictionary = _anim_for_state(anim_state)
	if _has_frames(anim):
		texture = anim["frames"][0]

## Called when the current animation runs past its last frame.
func _on_anim_completed() -> void:
	loop_count += 1
	if loop_count < _loops_for_state(anim_state) or not STATE_NEXT.has(anim_state):
		# More loops to go, or a state that holds forever: restart the frames.
		var anim: Dictionary = _anim_for_state(anim_state)
		current_frame_idx = 0
		if _has_frames(anim):
			texture = anim["frames"][0]
		return

	var next_state: AnimState = STATE_NEXT[anim_state]
	var was_win: bool = anim_state == AnimState.WIN_BEFORE or anim_state == AnimState.WIN
	_enter(next_state)

	# Report the victory pose as done once we leave it for good -- including the
	# case where the "win" sheet is missing and _enter() fell through to idle.
	if was_win and anim_state != AnimState.WIN:
		win_finished.emit(index)

func _anim_for_state(state: AnimState) -> Dictionary:
	match state:
		AnimState.STANDBY:
			return standby_anim
		AnimState.MAGIC_STANDBY:
			return magic_standby_anim
		AnimState.ATK:
			return atk_anim
		AnimState.MAGIC_ATK:
			return magic_atk_anim
		AnimState.LIMIT_ATK:
			return limit_atk_anim
		AnimState.WIN_BEFORE:
			return win_before_anim
		AnimState.WIN:
			return win_anim
	return _resting_anim()

func _loops_for_state(state: AnimState) -> int:
	if state == AnimState.ATK and is_enemy:
		return ENEMY_ATK_LOOPS
	return int(STATE_LOOPS.get(state, 1))

# === HP-driven resting pose ===

func _resolve_hp_state() -> HpState:
	if current_hp <= 0:
		return HpState.DEAD
	if float(current_hp) / float(maxi(1, max_hp)) < DYING_HP_RATIO:
		return HpState.DYING
	return HpState.HEALTHY

## Falls back down the chain (dead -> dying -> idle) so a unit missing the newer
## spritesheets still rests on something rather than going blank.
func _resting_anim() -> Dictionary:
	match hp_state:
		HpState.DEAD:
			if _has_frames(dead_anim):
				return dead_anim
			if _has_frames(dying_anim):
				return dying_anim
		HpState.DYING:
			if _has_frames(dying_anim):
				return dying_anim
	return idle_anim

# === Public playback ===

## Plays an action pose (ATK, MAGIC_ATK, LIMIT_ATK); the sprite returns to its resting
## pose once the pose has played out.
func play_action(state: AnimState) -> void:
	_enter(state)

## The pose a unit holds while a command is queued: STANDBY, MAGIC_STANDBY, or IDLE
## for none.
func play_queued(state: AnimState) -> void:
	_enter(state)

## Takes the combatant's HP, which picks the resting pose (idle, dying, dead). An
## action in flight is left alone, since every action state routes back through IDLE
## and lands on the new pose when it ends, unless the unit just died, which cuts it
## short. Call it before the first frames show, so a sprite built mid-battle opens on
## the right pose.
func set_hp(cur_hp: int, p_max_hp: int) -> void:
	current_hp = cur_hp
	max_hp = maxi(1, p_max_hp)

	var next_state: HpState = _resolve_hp_state()
	if next_state == hp_state:
		return

	if anim_state == AnimState.IDLE or next_state == HpState.DEAD:
		_enter(AnimState.IDLE)

## Victory pose: "win_before" plays through once as a lead-in, then "win" loops
## STATE_LOOPS times, after which `win_finished` fires and the sprite returns to
## its resting pose.
func play_win() -> void:
	_enter(AnimState.WIN_BEFORE)

	# No win frames at all -- report back immediately so the caller isn't left
	# waiting on an animation that will never play.
	if anim_state != AnimState.WIN_BEFORE and anim_state != AnimState.WIN:
		win_finished.emit(index)

# === Frame playback ===

func _process(delta: float) -> void:
	_update_long_press(delta)

	var anim: Dictionary = _anim_for_state(anim_state)
	if not _has_frames(anim):
		return

	var frames: Array = anim["frames"]
	if current_frame_idx >= frames.size():
		# The sheet changed underneath us (HP crossed a threshold mid-pose).
		current_frame_idx = 0
		texture = frames[0]
		return

	var delays: Array = anim.get("delays", [])
	var delay_seconds: float = float(_delay_at(delays, current_frame_idx)) * FRAME_DELAY_UNIT

	current_frame_timer += delta
	if current_frame_timer < delay_seconds:
		return

	current_frame_timer -= delay_seconds
	current_frame_idx += 1

	if current_frame_idx < frames.size():
		texture = frames[current_frame_idx]
		return

	_on_anim_completed()

func _update_long_press(delta: float) -> void:
	if not _is_pressed or _long_press_emitted:
		return

	_press_elapsed += delta
	if _press_elapsed >= LONG_PRESS_THRESHOLD:
		_long_press_emitted = true
		long_pressed.emit(index)

static func _has_frames(anim: Dictionary) -> bool:
	return not anim.is_empty() and anim.get("frames", []).size() > 0

static func _delay_at(delays: Array, idx: int) -> int:
	if idx < delays.size():
		return int(delays[idx])
	return DEFAULT_FRAME_DELAY
