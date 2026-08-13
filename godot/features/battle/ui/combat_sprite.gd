extends TextureRect

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

var party_index: int = -1

signal short_tapped(unit_index: int)
signal long_pressed(unit_index: int)
## Emitted once the whole victory pose (win_before + STATE_LOOPS win loops) has
## played out, so the caller knows it can move on to the result screen.
signal win_finished(unit_index: int)

var _is_pressed: bool = false
var _press_elapsed: float = 0.0
var _long_press_emitted: bool = false

# BattleManager reference is injected via setup() so the sprite can be reused in
# non-combat contexts (e.g. unit gallery) without depending on scene paths.
var battle_manager: Node = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _exit_tree() -> void:
	# Disconnect from BattleManager so a re-entered battle scene doesn't end up with
	# stale listeners pointing at freed nodes.
	if not is_instance_valid(battle_manager):
		return
	if battle_manager.unit_action_started.is_connected(_on_unit_action_started):
		battle_manager.unit_action_started.disconnect(_on_unit_action_started)
	if battle_manager.enemy_action_started.is_connected(_on_enemy_action_started):
		battle_manager.enemy_action_started.disconnect(_on_enemy_action_started)
	if battle_manager.action_queued.is_connected(_on_action_queued):
		battle_manager.action_queued.disconnect(_on_action_queued)
	if battle_manager.unit_stats_updated.is_connected(_on_unit_stats_updated):
		battle_manager.unit_stats_updated.disconnect(_on_unit_stats_updated)

func _gui_input(event: InputEvent) -> void:
	if party_index < 0:
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
			short_tapped.emit(party_index)

func setup(p_index: int, template_id: String, p_is_enemy: bool = false, p_battle_manager: Node = null) -> void:
	party_index = p_index
	is_enemy = p_is_enemy

	# Wire up battle signals only when running inside a battle. In outgame
	# contexts (e.g. unit gallery) the sprite just plays its idle animation.
	battle_manager = p_battle_manager
	if battle_manager:
		if not battle_manager.unit_action_started.is_connected(_on_unit_action_started):
			battle_manager.unit_action_started.connect(_on_unit_action_started)
		if not battle_manager.enemy_action_started.is_connected(_on_enemy_action_started):
			battle_manager.enemy_action_started.connect(_on_enemy_action_started)
		if not battle_manager.action_queued.is_connected(_on_action_queued):
			battle_manager.action_queued.connect(_on_action_queued)
		if not battle_manager.unit_stats_updated.is_connected(_on_unit_stats_updated):
			battle_manager.unit_stats_updated.connect(_on_unit_stats_updated)

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

	_sync_hp_from_battle_state()

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
		win_finished.emit(party_index)

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

## Seeds HP from battle state so a sprite built mid-battle (wave respawn, scene
## reload) opens on the correct resting pose instead of always starting at idle.
func _sync_hp_from_battle_state() -> void:
	if is_enemy or not is_instance_valid(battle_manager):
		return
	if party_index < 0 or party_index >= battle_manager.party_data.size():
		return

	var unit_data: Dictionary = battle_manager.party_data[party_index]
	if unit_data.is_empty():
		return

	current_hp = int(unit_data.get("current_hp", 1))
	max_hp = maxi(1, int(unit_data.get("max_hp", 1)))

# === Public playback ===

## Victory pose: "win_before" plays through once as a lead-in, then "win" loops
## STATE_LOOPS times, after which `win_finished` fires and the sprite returns to
## its resting pose.
func play_win() -> void:
	_enter(AnimState.WIN_BEFORE)

	# No win frames at all -- report back immediately so the caller isn't left
	# waiting on an animation that will never play.
	if anim_state != AnimState.WIN_BEFORE and anim_state != AnimState.WIN:
		win_finished.emit(party_index)

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
		long_pressed.emit(party_index)

static func _has_frames(anim: Dictionary) -> bool:
	return not anim.is_empty() and anim.get("frames", []).size() > 0

static func _delay_at(delays: Array, idx: int) -> int:
	if idx < delays.size():
		return int(delays[idx])
	return DEFAULT_FRAME_DELAY

# === BattleManager signals ===

func _on_unit_action_started(unit_index: int, action: int) -> void:
	if is_enemy or unit_index != party_index:
		return

	# Check if action is ATTACK
	if action == battle_manager.CombatAction.ATTACK:
		_enter(AnimState.ATK)
	elif action == battle_manager.CombatAction.SKILL or action == battle_manager.CombatAction.ITEM:
		var queued_payload: Dictionary = battle_manager.party_data[party_index].get("queued_payload", {})
		var source_type: String = str(queued_payload.get("source_type", "skill"))
		if source_type == "limitburst":
			_enter(AnimState.LIMIT_ATK)
			return

		# Magic and abilities both cast through the magic_atk sheet; items keep the
		# plain swing.
		var action_id = battle_manager.party_data[party_index].get("queued_action_id", "")
		if GameDatabase.has_magic(action_id) or action == battle_manager.CombatAction.SKILL:
			_enter(AnimState.MAGIC_ATK)
		else:
			_enter(AnimState.ATK)

func _on_enemy_action_started(enemy_index: int, action: int) -> void:
	if not is_enemy or enemy_index != party_index:
		return

	if action == battle_manager.CombatAction.ATTACK:
		_enter(AnimState.ATK)

func _on_action_queued(unit_index: int, action: int, action_id: String) -> void:
	if is_enemy or unit_index != party_index:
		return

	# Queueing a spell or an ability puts the unit in its charge pose until the
	# action actually executes. Items don't get one.
	if action == battle_manager.CombatAction.SKILL or action == battle_manager.CombatAction.ITEM:
		if GameDatabase.has_magic(action_id):
			_enter(AnimState.MAGIC_STANDBY)
		elif action == battle_manager.CombatAction.SKILL:
			_enter(AnimState.STANDBY)
		else:
			_enter(AnimState.IDLE)
	else:
		_enter(AnimState.IDLE)

## The resting pose has to be re-picked whenever HP crosses the dying threshold
## or in/out of KO. An in-flight action is left alone -- it lands on the new pose
## when it ends, since every action state routes back through IDLE -- unless the
## unit just died, which cuts the action short.
func _on_unit_stats_updated(index: int, _unit_name: String, cur_hp: int, p_max_hp: int, _cur_mp: int, _max_mp: int, _cur_limit: int, _max_limit: int) -> void:
	if is_enemy or index != party_index:
		return

	current_hp = cur_hp
	max_hp = maxi(1, p_max_hp)

	var next_state: HpState = _resolve_hp_state()
	if next_state == hp_state:
		return

	if anim_state == AnimState.IDLE or next_state == HpState.DEAD:
		_enter(AnimState.IDLE)
