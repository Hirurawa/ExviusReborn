extends PanelContainer

## One combatant in the sandbox's battle view: name, bars, stats, statuses and chain. A
## party member's card carries its command controls (action, target, execute; a
## multicast command adds a row per pick, its skill and target, each skill greyed when
## the command cannot cast it after the rows above); an enemy's card its behaviour
## switch. Clicking the card asks to inspect the combatant. The card only renders
## engine state and emits what the user picked.

signal inspected(combatant_id: int)
signal command_chosen(unit_id: int, command: BattleCommand)
signal target_chosen(unit_id: int, target_id: int)
signal execute_pressed(unit_id: int)
signal behaviour_chosen(foe_id: int, behaviour: StringName)

const BEHAVIOURS: Array[StringName] = [
	SandboxBattleFactory.BEHAVIOUR_SCRIPTED, SandboxBattleFactory.BEHAVIOUR_ATTACK, SandboxBattleFactory.BEHAVIOUR_PASS,
]
const HP_COLOR := Color(0.3, 0.75, 0.35)
const MP_COLOR := Color(0.3, 0.5, 0.95)
const LB_COLOR := Color(0.95, 0.75, 0.2)
const WARN_COLOR := Color(1.0, 0.6, 0.35)
const MUTED_COLOR := Color(0.6, 0.6, 0.65)

var fighter_id: int = -1

var _style := StyleBoxFlat.new()
var _title := Label.new()
var _flags := Label.new()
var _hp: Array = []
var _mp: Array = []
var _lb: Array = []
var _stats := Label.new()
var _chain := Label.new()
var _statuses := Label.new()
var _actions: OptionButton = null
var _target: OptionButton = null
var _execute: Button = null
var _note: Label = null
var _behaviour: OptionButton = null

var _options: Array[Dictionary] = []
## command_key -> item index of _actions.
var _option_index: Dictionary = {}
## Item index of _target -> combatant id (-1: let the engine pick).
var _target_ids: Array[int] = []
## The multicast pick rows under the action: [skill OptionButton, target OptionButton]
## each. A skill list's item 0 is "(pick)"; item i is option _pick_options[i].
var _picks_box: VBoxContainer = null
var _pick_rows: Array = []
var _pick_options: Array[int] = []
## The command the rows were built for (its skill id; "" when there are none).
var _rows_for: String = ""


func setup(engine: BattleEngine, fighter: Combatant) -> void:
	fighter_id = fighter.id
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style.bg_color = Color(0.14, 0.14, 0.17)
	_style.set_border_width_all(1)
	_style.border_color = Color(0.25, 0.25, 0.3)
	_style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", _style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	_flags.add_theme_color_override("font_color", WARN_COLOR)
	head.add_child(_flags)

	_hp = _add_bar(box, "HP", HP_COLOR)
	_mp = _add_bar(box, "MP", MP_COLOR)
	if fighter.is_party():
		_lb = _add_bar(box, "LB", LB_COLOR)
	for label in [_stats, _chain, _statuses]:
		label.add_theme_font_size_override("font_size", 12)
		box.add_child(label)
	_chain.add_theme_color_override("font_color", LB_COLOR)
	_statuses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_statuses.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))

	if fighter.is_party():
		_build_commands(box, engine, fighter)
	else:
		_build_behaviour(box, fighter)
	refresh(engine)


func set_selected(selected: bool) -> void:
	_style.border_color = Color(1.0, 0.85, 0.3) if selected else Color(0.25, 0.25, 0.3)
	_style.set_border_width_all(2 if selected else 1)


func refresh(engine: BattleEngine) -> void:
	var fighter: Combatant = engine.combatant(fighter_id)
	if fighter == null:
		return
	var rarity: String = ""
	if fighter.is_party():
		rarity = " R%d" % int(fighter.source.get("rare", 0))
	_title.text = "%s#%d  Lv %d%s%s" % [fighter.name, fighter.id, fighter.level, rarity, "  BOSS" if fighter.is_boss else ""]
	_flags.text = _flags_text(fighter)
	_set_bar(_hp, fighter.hp, fighter.max_hp, "%d / %d" % [fighter.hp, fighter.max_hp])
	_set_bar(_mp, fighter.mp, fighter.max_mp, "%d / %d" % [fighter.mp, fighter.max_mp])
	if not _lb.is_empty():
		_set_bar(_lb, fighter.lb, fighter.max_lb, "%.1f / %.1f" % [fighter.lb / 100.0, fighter.max_lb / 100.0])
	_stats.text = _stats_text(fighter)
	_chain.text = _chain_text(engine, fighter)
	_chain.visible = _chain.text != ""
	_statuses.text = _statuses_text(fighter)
	_statuses.visible = _statuses.text != ""
	if _actions != null:
		_refresh_commands(engine, fighter)
	if _behaviour != null:
		var index: int = BEHAVIOURS.find(SandboxBattleFactory.behaviour_of(fighter))
		if index >= 0 and _behaviour.selected != index:
			_behaviour.select(index)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		inspected.emit(fighter_id)
		accept_event()


# === Party commands ===

func _build_commands(box: VBoxContainer, engine: BattleEngine, fighter: Combatant) -> void:
	_actions = OptionButton.new()
	_actions.fit_to_longest_item = false
	_actions.clip_text = true
	_fill_actions(SandboxBattleFactory.command_options(engine, fighter))
	_actions.item_selected.connect(_on_action_selected)
	box.add_child(_actions)
	_picks_box = VBoxContainer.new()
	_picks_box.add_theme_constant_override("separation", 1)
	box.add_child(_picks_box)

	var row := HBoxContainer.new()
	box.add_child(row)
	_target = OptionButton.new()
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.fit_to_longest_item = false
	_target.clip_text = true
	_target.add_item("Target: auto")
	_target_ids.append(-1)
	var everyone: Array[Combatant] = engine.enemies.duplicate()
	everyone.append_array(engine.party_members())
	for other in everyone:
		_target.add_item("%s %s#%d" % ["E" if other.is_enemy() else "P", other.name, other.id])
		_target_ids.append(other.id)
	_target.item_selected.connect(_on_target_selected)
	row.add_child(_target)
	_execute = Button.new()
	_execute.text = "Execute"
	_execute.pressed.connect(func() -> void: execute_pressed.emit(fighter_id))
	row.add_child(_execute)

	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 11)
	_note.add_theme_color_override("font_color", MUTED_COLOR)
	box.add_child(_note)


## Puts `options` in the action list, and the skills among them in the pick lists.
func _fill_actions(options: Array[Dictionary]) -> void:
	_options = options
	_actions.clear()
	_option_index.clear()
	_pick_options = [-1]
	for i in range(_options.size()):
		_actions.add_item(str(_options[i]["label"]), i)
		_actions.set_item_tooltip(i, str(_options[i]["tooltip"]))
		_option_index[SandboxBattleFactory.command_key(_options[i]["command"])] = i
		if (_options[i]["command"] as BattleCommand).kind == BattleCommand.Kind.SKILL:
			_pick_options.append(i)


## Whether `options` differ from the listed ones (a grant came or went, or its turns or
## uses changed).
func _options_changed(options: Array[Dictionary]) -> bool:
	if options.size() != _options.size():
		return true
	for i in range(options.size()):
		if options[i]["label"] != _options[i]["label"]:
			return true
	return false


func _refresh_commands(engine: BattleEngine, fighter: Combatant) -> void:
	var current: Array[Dictionary] = SandboxBattleFactory.command_options(engine, fighter)
	if _options_changed(current):
		_fill_actions(current)
		_rows_for = "-"
	var queued: BattleCommand = fighter.queued_command
	var index: int = int(_option_index.get(SandboxBattleFactory.command_key(queued), 0))
	if _actions.selected != index:
		_actions.select(index)
	var target_index: int = maxi(0, _target_ids.find(queued.target_id if queued != null else -1))
	if _target.selected != target_index:
		_target.select(target_index)
	for i in range(1, _target_ids.size()):
		var other: Combatant = engine.combatant(_target_ids[i])
		var text: String = "%s %s#%d%s" % ["E" if other.is_enemy() else "P", other.name, other.id, "" if other.is_alive() else " (KO)"]
		if _target.get_item_text(i) != text:
			_target.set_item_text(i, text)

	_refresh_pick_rows(engine, fighter, queued)

	var reason: StringName = engine.can_execute(fighter.id)
	_execute.disabled = reason != BattleEngine.OK
	var notes: PackedStringArray = []
	if reason != BattleEngine.OK:
		notes.append(str(reason))
	var limits: Dictionary = engine.skill_limits(fighter.id, queued)
	if int(limits.get("uses_left", -1)) >= 0:
		notes.append("uses left %d" % int(limits["uses_left"]))
	if limits.has("ready_turn"):
		notes.append("ready on turn %d" % int(limits["ready_turn"]))
	if limits.has("grant_turns_left"):
		var turns: int = int(limits["grant_turns_left"])
		var uses: int = int(limits["grant_uses_left"])
		notes.append("granted: %s, %s" % [
			"no time limit" if turns < 0 else "%d turn(s) left" % turns, "unlimited uses" if uses < 0 else "%d use(s) left" % uses,
		])
	_note.text = ", ".join(notes)
	_note.add_theme_color_override("font_color", WARN_COLOR if reason != BattleEngine.OK and reason != BattleEngine.REJECT_ALREADY_ACTED else MUTED_COLOR)


func _on_action_selected(index: int) -> void:
	var command: BattleCommand = (_options[index]["command"] as BattleCommand).duplicate_command()
	if command.kind != BattleCommand.Kind.DEFEND:
		command.target_id = _target_ids[maxi(0, _target.selected)]
	command_chosen.emit(fighter_id, command)


func _on_target_selected(index: int) -> void:
	target_chosen.emit(fighter_id, _target_ids[index])


# === Multicast picks ===

## Builds a row per pick when the queued command is a multicast command (none otherwise),
## then shows its picks and greys each row's skills the command cannot cast after the
## picks above it (BattleEngine.multicast_pick_problem; the reason is the tooltip).
func _refresh_pick_rows(engine: BattleEngine, fighter: Combatant, queued: BattleCommand) -> void:
	var rule: Multicast.Rule = engine.multicast_rule(fighter.id, queued) if queued != null else null
	var rows_for: String = queued.skill_id if rule != null else ""
	if rows_for != _rows_for:
		_build_pick_rows(engine, rule.count if rule != null else 0)
		_rows_for = rows_for
	if rule == null:
		return
	var picks_before: Array[BattleCommand] = []
	for row in range(_pick_rows.size()):
		var skill_button: OptionButton = _pick_rows[row][0]
		var target_button: OptionButton = _pick_rows[row][1]
		for item in range(1, skill_button.item_count):
			var candidate: BattleCommand = _options[_pick_options[item]]["command"]
			var reason: StringName = engine.multicast_pick_problem(fighter.id, queued, picks_before, candidate)
			skill_button.set_item_disabled(item, reason != BattleEngine.OK)
			skill_button.set_item_tooltip(item, "" if reason == BattleEngine.OK else str(reason))
		var pick: BattleCommand = queued.picks[row] if row < queued.picks.size() else null
		var item_index: int = _pick_item(pick)
		if skill_button.selected != item_index:
			skill_button.select(item_index)
		var target_index: int = maxi(0, _target_ids.find(pick.target_id)) if pick != null else 0
		if target_button.selected != target_index:
			target_button.select(target_index)
		if pick != null:
			picks_before.append(pick)


func _build_pick_rows(engine: BattleEngine, count: int) -> void:
	for child in _picks_box.get_children():
		_picks_box.remove_child(child)
		child.queue_free()
	_pick_rows.clear()
	for row in range(count):
		var line := HBoxContainer.new()
		_picks_box.add_child(line)
		var skill_button := OptionButton.new()
		skill_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill_button.fit_to_longest_item = false
		skill_button.clip_text = true
		skill_button.add_item("Pick %d: (pick)" % (row + 1))
		for item in range(1, _pick_options.size()):
			skill_button.add_item("Pick %d: %s" % [row + 1, _options[_pick_options[item]]["label"]])
		skill_button.item_selected.connect(func(_index: int) -> void: _emit_multicast())
		line.add_child(skill_button)
		var target_button := OptionButton.new()
		target_button.fit_to_longest_item = false
		target_button.clip_text = true
		target_button.custom_minimum_size.x = 90
		for i in range(_target_ids.size()):
			target_button.add_item("auto" if i == 0 else _target.get_item_text(i))
		target_button.item_selected.connect(func(_index: int) -> void: _emit_multicast())
		line.add_child(target_button)
		_pick_rows.append([skill_button, target_button])


## The skill list item showing `pick` (0, "(pick)", when there is none).
func _pick_item(pick: BattleCommand) -> int:
	if pick == null:
		return 0
	for item in range(1, _pick_options.size()):
		var candidate: BattleCommand = _options[_pick_options[item]]["command"]
		if candidate.skill_kind == pick.skill_kind and candidate.skill_id == pick.skill_id:
			return item
	return 0


## Queues the multicast command with the picks the rows hold, up to the first empty row.
## An incomplete one is queued too; Execute stays off until every row has a pick.
func _emit_multicast() -> void:
	var command: BattleCommand = (_options[maxi(0, _actions.selected)]["command"] as BattleCommand).duplicate_command()
	command.target_id = _target_ids[maxi(0, _target.selected)]
	for row in _pick_rows:
		var item: int = (row[0] as OptionButton).selected
		if item <= 0:
			break
		var pick: BattleCommand = (_options[_pick_options[item]]["command"] as BattleCommand).duplicate_command()
		pick.target_id = _target_ids[maxi(0, (row[1] as OptionButton).selected)]
		command.picks.append(pick)
	command_chosen.emit(fighter_id, command)


# === Enemy behaviour ===

func _build_behaviour(box: VBoxContainer, fighter: Combatant) -> void:
	_behaviour = OptionButton.new()
	var scripted: bool = SandboxBattleFactory.has_ai_script(fighter)
	_behaviour.add_item("Behaviour: AI script" if scripted else "Behaviour: default attack (no AI script)")
	_behaviour.add_item("Behaviour: basic attack")
	_behaviour.add_item("Behaviour: pass")
	_behaviour.item_selected.connect(func(index: int) -> void: behaviour_chosen.emit(fighter_id, BEHAVIOURS[index]))
	box.add_child(_behaviour)


# === Text ===

func _add_bar(box: VBoxContainer, caption: String, color: Color) -> Array:
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_label := Label.new()
	name_label.text = caption
	name_label.custom_minimum_size.x = 24
	name_label.add_theme_font_size_override("font_size", 12)
	row.add_child(name_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size.y = 10
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 110
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 12)
	row.add_child(value_label)
	return [bar, value_label]


static func _set_bar(bar: Array, value: int, maximum: int, text: String) -> void:
	var progress: ProgressBar = bar[0]
	progress.max_value = maxi(1, maximum)
	progress.value = value
	(bar[1] as Label).text = text


static func _flags_text(fighter: Combatant) -> String:
	if not fighter.is_alive():
		return "KO"
	var flags: PackedStringArray = []
	match fighter.control():
		StatusBehavior.CONTROL_DISABLED:
			flags.append("DISABLED")
		StatusBehavior.CONTROL_BERSERK:
			flags.append("BERSERK")
		StatusBehavior.CONTROL_CONFUSED:
			flags.append("CONFUSED")
	if not fighter.is_standing():
		flags.append("DOWN")
	if fighter.defending:
		flags.append("DEFENDING")
	if fighter.is_party() and fighter.acted:
		flags.append("ACTED")
	return " ".join(flags)


static func _stats_text(fighter: Combatant) -> String:
	var parts: PackedStringArray = []
	for stat_name in ["ATK", "DEF", "MAG", "SPR"]:
		var now: int = fighter.stat(stat_name)
		var base: int = int(fighter.base_stats.get(stat_name, 0))
		parts.append("%s %d%s" % [stat_name, now, "*" if now != base else ""])
	return "  ".join(parts)


static func _chain_text(engine: BattleEngine, fighter: Combatant) -> String:
	if fighter.chain_count <= 0:
		return ""
	var frames_left: int = fighter.chain_last_frame + engine.rules.chain_window_frames - engine.frame
	var state: String = "%df left" % frames_left if frames_left >= 0 else "ended"
	return "Chain %d  x%.2f  (%s)" % [fighter.chain_count, fighter.chain_percent / 100.0, state]


static func _statuses_text(fighter: Combatant) -> String:
	var parts: PackedStringArray = []
	for status in fighter.statuses:
		var label: String = status.key if status.kind == BattleStatus.STAT else ("%s %s" % [status.kind, status.key]).strip_edges()
		var turns: String = "perm" if status.is_permanent() else "%dt" % status.turns_left
		parts.append("%s %+d [%s]" % [label, status.value, turns])
	return ", ".join(parts)
