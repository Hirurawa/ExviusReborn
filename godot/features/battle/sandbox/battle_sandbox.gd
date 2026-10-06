extends Control

## The battle sandbox, a debug scene for trying the new engine: pick units and
## monsters, start a battle, give commands and watch hits, chains and statuses land.
## Run it directly (F6, or godot --path <abs>/godot res://features/battle/sandbox/BattleSandbox.tscn).
## No save is needed; units come straight from the unit table.
##
## Layout: controls bar on top; setup and inspector tabs on the left; party and enemy
## cards with the frame ruler in the middle; the event log on the right. The window is
## resized to a landscape size while the scene runs.
##
## The scene only renders engine state and sends commands through its BattleSession.
## Its logic lives in SandboxBattleFactory and FrameRulerModel, which tests cover.
## Keys: P pauses or resumes, "." steps one frame.

const UnitCard = preload("res://features/battle/sandbox/sandbox_unit_card.gd")
const SetupPanel = preload("res://features/battle/sandbox/sandbox_setup_panel.gd")
const Inspector = preload("res://features/battle/sandbox/sandbox_inspector.gd")
const EventLog = preload("res://features/battle/sandbox/sandbox_event_log.gd")
const FrameRuler = preload("res://features/battle/sandbox/frame_ruler.gd")

## The last setup started, restored on the next run.
const SAVE_PATH: String = "user://battle_sandbox.json"
const WINDOW_SIZE := Vector2i(1600, 900)
const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]
const DEFAULT_SPEED_INDEX: int = 2
const TAB_SETUP: int = 0
const TAB_INSPECT: int = 1

@onready var session: BattleSession = $BattleSession

## Load the last setup on start and save each one started. Tests turn it off.
var remember_setup: bool = true

var _factory := SandboxBattleFactory.new()
var _rules := BattleRules.new()
## Enemy behaviour picked per formation slot; kept across restarts of one setup.
var _behaviours: Dictionary = {}
## Combatant id -> card.
var _cards: Dictionary = {}
var _selected_id: int = -1
## HIT_LANDED and HIT_MISSED events recent enough for the frame ruler.
var _recent_hits: Array[Dictionary] = []
var _dirty: bool = true
var _previous_window: Dictionary = {}

var _setup: SetupPanel = null
var _inspector: Inspector = null
var _log: EventLog = null
var _ruler: FrameRuler = null
var _tabs := TabContainer.new()
var _party_box := VBoxContainer.new()
var _enemy_box := VBoxContainer.new()
var _execute_all := Button.new()
var _play := Button.new()
var _speed := OptionButton.new()
var _status := Label.new()


func _ready() -> void:
	_resize_window()
	_build_layout()
	session.process_priority = -1
	session.battle_started.connect(_on_battle_started)
	session.events_emitted.connect(_on_events_emitted)
	session.frames_advanced.connect(func(_frame: int) -> void: _dirty = true)
	var saved: Dictionary = _load_setup() if remember_setup else {}
	_setup.set_setup(saved if not saved.is_empty() else SandboxBattleFactory.test_setup())
	_start(_setup.get_setup())


func _exit_tree() -> void:
	if _previous_window.is_empty():
		return
	var window: Window = get_window()
	window.content_scale_mode = _previous_window["mode"]
	window.size = _previous_window["size"]


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_P:
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_PERIOD:
		session.step(1)
		get_viewport().set_input_as_handled()


# === Battle ===

func _start(setup: Dictionary) -> void:
	if remember_setup:
		_save_setup(setup)
	_behaviours.clear()
	var frozen: Dictionary = setup.duplicate(true)
	var factory: Callable = func(seed_value: int) -> BattleEngine:
		return _build(frozen, seed_value)
	session.start(factory, int(setup.get("seed", 0)))


func _build(setup: Dictionary, seed_value: int) -> BattleEngine:
	var engine: BattleEngine = _factory.build(setup, seed_value, _rules)
	_apply_behaviours(engine)
	_setup.show_message("\n".join(PackedStringArray(_factory.problems)))
	return engine


## The behaviours picked per formation slot, on the current formation (each wave's too).
func _apply_behaviours(engine: BattleEngine) -> void:
	for foe in engine.enemies:
		if _behaviours.has(foe.slot):
			SandboxBattleFactory.set_behaviour(foe, _behaviours[foe.slot])


func _restart(new_seed: bool) -> void:
	if new_seed:
		var seed_value: int = randi() % SetupPanel.MAX_SEED
		_setup.set_seed(seed_value)
		session.restart(seed_value)
	else:
		session.restart()


func _on_battle_started(engine: BattleEngine) -> void:
	for card in _cards.values():
		(card as Node).get_parent().remove_child(card)
		(card as Node).queue_free()
	_cards.clear()
	_recent_hits.clear()
	for member in engine.party_members():
		_add_card(engine, member, _party_box)
	for foe in engine.enemies:
		_add_card(engine, foe, _enemy_box)
	if engine.combatant(_selected_id) == null:
		_selected_id = -1
	_select(_selected_id)
	_log.reset(engine)
	_dirty = true


func _on_events_emitted(events: Array[Dictionary]) -> void:
	_log.append(events)
	var new_wave: bool = false
	for event in events:
		var type: StringName = event.get("type", &"")
		if type == BattleEventLog.HIT_LANDED or type == BattleEventLog.HIT_MISSED:
			_recent_hits.append(event)
		elif type == BattleEventLog.WAVE_STARTED:
			new_wave = true
	if new_wave:
		_show_new_formation(session.engine)
	_dirty = true


## A wave began: the enemy cards now show its formation.
func _show_new_formation(engine: BattleEngine) -> void:
	for id in _cards.keys():
		var card: UnitCard = _cards[id]
		if card.get_parent() == _enemy_box:
			_enemy_box.remove_child(card)
			card.queue_free()
			_cards.erase(id)
	_apply_behaviours(engine)
	for foe in engine.enemies:
		_add_card(engine, foe, _enemy_box)
	_select(_selected_id)


func _add_card(engine: BattleEngine, fighter: Combatant, box: VBoxContainer) -> void:
	var card: UnitCard = UnitCard.new()
	box.add_child(card)
	card.setup(engine, fighter)
	card.inspected.connect(_on_card_inspected)
	card.command_chosen.connect(func(unit_id: int, command: BattleCommand) -> void: session.queue_command(unit_id, command))
	card.target_chosen.connect(_on_target_chosen)
	card.execute_pressed.connect(func(unit_id: int) -> void: session.execute(unit_id))
	card.behaviour_chosen.connect(_on_behaviour_chosen)
	_cards[fighter.id] = card


func _on_target_chosen(unit_id: int, target_id: int) -> void:
	if target_id >= 0:
		session.set_target(unit_id, target_id)
		return
	# "auto" re-queues the command without a target; with nothing queued it already is.
	var unit: Combatant = session.engine.combatant(unit_id)
	if unit != null and unit.queued_command != null:
		var command: BattleCommand = unit.queued_command.duplicate_command()
		command.target_id = -1
		session.queue_command(unit_id, command)


func _on_behaviour_chosen(foe_id: int, behaviour: StringName) -> void:
	var foe: Combatant = session.engine.combatant(foe_id)
	if foe == null:
		return
	SandboxBattleFactory.set_behaviour(foe, behaviour)
	_behaviours[foe.slot] = behaviour
	_dirty = true


func _on_card_inspected(combatant_id: int) -> void:
	_select(combatant_id)
	_tabs.current_tab = TAB_INSPECT


func _select(combatant_id: int) -> void:
	_selected_id = combatant_id
	for id in _cards:
		(_cards[id] as UnitCard).set_selected(id == combatant_id)
	_inspector.show_combatant(session.engine, combatant_id)


func _on_edit_requested(target_id: int, field: StringName, value: int, key: String) -> void:
	if session.engine == null:
		return
	session.engine.debug_edit(target_id, field, value, key)
	session.flush_events()
	_dirty = true


func _execute_all_units() -> void:
	var ids: Array = []
	for unit in session.engine.units_to_act():
		ids.append(unit.id)
	session.execute_many(ids)


func _toggle_pause() -> void:
	session.paused = not session.paused
	_dirty = true


# === Rendering ===

func _refresh() -> void:
	var engine: BattleEngine = session.engine
	_play.text = "Play" if session.paused else "Pause"
	if engine == null:
		_status.text = "No battle"
		return
	var phase: String = "%s phase" % BattleEngine.PHASE_NAMES.get(engine.phase, "?")
	if engine.phase == BattleEngine.Phase.ENDED:
		phase = "ended: %s" % str(engine.outcome).to_upper()
	_status.text = "Wave %d/%d   Turn %d   %s   frame %d   seed %d   to act %d   esper orbs %d/%d" % [
		engine.wave, engine.wave_count(), engine.turn, phase, engine.frame, session.battle_seed,
		engine.units_to_act().size(), engine.esper_orbs, engine.rules.esper_gauge_max,
	]
	for card in _cards.values():
		(card as UnitCard).refresh(engine)
	_execute_all.disabled = engine.phase != BattleEngine.Phase.PLAYER or engine.units_to_act().is_empty()

	var oldest: int = engine.frame - FrameRulerModel.PAST_FRAMES
	while not _recent_hits.is_empty() and int(_recent_hits[0].get("frame", 0)) < oldest:
		_recent_hits.pop_front()
	_ruler.show_model(FrameRulerModel.build(engine, _recent_hits), engine)
	if _tabs.current_tab == TAB_INSPECT:
		_inspector.refresh()


# === Layout ===

func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = Color(0.1, 0.1, 0.12)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 6)
	add_child(margin)
	var main := VBoxContainer.new()
	margin.add_child(main)
	main.add_child(_build_controls())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(split)

	_tabs.custom_minimum_size.x = 430
	split.add_child(_tabs)
	_setup = SetupPanel.new()
	_setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setup.start_requested.connect(_start)
	var setup_scroll: ScrollContainer = _scroll(_setup)
	setup_scroll.name = "Setup"
	_tabs.add_child(setup_scroll)
	_inspector = Inspector.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.edit_requested.connect(_on_edit_requested)
	var inspect_scroll: ScrollContainer = _scroll(_inspector)
	inspect_scroll.name = "Inspect"
	_tabs.add_child(inspect_scroll)
	_tabs.tab_changed.connect(func(_tab: int) -> void: _dirty = true)

	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right_split)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size.x = 620
	right_split.add_child(center)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(columns)

	var party_column := VBoxContainer.new()
	party_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(party_column)
	var party_head := HBoxContainer.new()
	party_column.add_child(party_head)
	var party_label := _heading("Party")
	party_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_head.add_child(party_label)
	_execute_all.text = "Execute all"
	_execute_all.tooltip_text = "Every unit that has not acted, on this frame, in slot order"
	_execute_all.pressed.connect(_execute_all_units)
	party_head.add_child(_execute_all)
	var party_scroll: ScrollContainer = _scroll(_party_box)
	party_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_column.add_child(party_scroll)

	var enemy_column := VBoxContainer.new()
	enemy_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(enemy_column)
	enemy_column.add_child(_heading("Enemies"))
	var enemy_scroll: ScrollContainer = _scroll(_enemy_box)
	enemy_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_column.add_child(enemy_scroll)

	var ruler_head := _heading("Frame ruler")
	ruler_head.tooltip_text = "Filled: landed. Hollow: pending. Cross: miss. Dot: heal or status. The bar after a damage hit is the chain window; hover a mark for details."
	ruler_head.mouse_filter = Control.MOUSE_FILTER_PASS
	center.add_child(ruler_head)
	_ruler = FrameRuler.new()
	_ruler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ruler_scroll: ScrollContainer = _scroll(_ruler)
	ruler_scroll.custom_minimum_size.y = 200
	center.add_child(ruler_scroll)

	_log = EventLog.new()
	_log.custom_minimum_size.x = 400
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(_log)


func _build_controls() -> HBoxContainer:
	var bar := HBoxContainer.new()
	_play.custom_minimum_size.x = 70
	_play.tooltip_text = "Pause or resume the clock (P)"
	_play.pressed.connect(_toggle_pause)
	bar.add_child(_play)
	for frames in [1, 10, 60]:
		var step := Button.new()
		step.text = "+%d f" % frames
		step.tooltip_text = "Run %d frame(s) now, paused or not%s" % [frames, " (.)" if frames == 1 else ""]
		step.pressed.connect(func() -> void: session.step(frames))
		bar.add_child(step)
	var speed_label := Label.new()
	speed_label.text = "  Speed"
	bar.add_child(speed_label)
	for speed in SPEEDS:
		_speed.add_item(("%dx" % int(speed)) if is_equal_approx(speed, roundf(speed)) else ("%sx" % String.num(speed)))
	_speed.select(DEFAULT_SPEED_INDEX)
	_speed.item_selected.connect(func(index: int) -> void: session.speed = SPEEDS[index])
	bar.add_child(_speed)
	var restart := Button.new()
	restart.text = "Restart"
	restart.tooltip_text = "The same setup and seed"
	restart.pressed.connect(func() -> void: _restart(false))
	bar.add_child(restart)
	var reseed := Button.new()
	reseed.text = "Restart, new seed"
	reseed.pressed.connect(func() -> void: _restart(true))
	bar.add_child(reseed)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status)
	return bar


## `content` in a vertical ScrollContainer that keeps plain mouse scrolling (the
## project's touch-drag scrolling would turn clicks on cards into drags).
static func _scroll(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.set_meta("skip_touch_drag", true)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


static func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	return label


func _resize_window() -> void:
	var window: Window = get_window()
	_previous_window = {"mode": window.content_scale_mode, "size": window.size}
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	if DisplayServer.get_name() == "headless" or window.mode != Window.MODE_WINDOWED:
		return
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	var target := Vector2i(mini(WINDOW_SIZE.x, usable.size.x - 40), mini(WINDOW_SIZE.y, usable.size.y - 60))
	window.size = target
	window.position = usable.position + (usable.size - target) / 2


# === Saved setup ===

func _save_setup(setup: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(setup, "\t"))


static func _load_setup() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return parsed if parsed is Dictionary else {}
