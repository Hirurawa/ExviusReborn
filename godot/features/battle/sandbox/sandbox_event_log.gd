extends VBoxContainer

## The battle's event log, one BattleEngine.format_event line per event, coloured by
## type. Filter by event type (the Types menu) and by text (matches the line); Copy
## puts the lines currently shown on the clipboard.

## Most lines drawn at once; older events stay in memory and come back through Copy.
const MAX_LINES: int = 4000
const TYPES: Array[StringName] = [
	BattleEventLog.BATTLE_STARTED, BattleEventLog.TURN_STARTED, BattleEventLog.TURN_ENDED,
	BattleEventLog.PHASE_CHANGED, BattleEventLog.COMMAND_QUEUED, BattleEventLog.COMMAND_REJECTED,
	BattleEventLog.ACTION_STARTED, BattleEventLog.COST_PAID, BattleEventLog.HIT_LANDED,
	BattleEventLog.HIT_MISSED, BattleEventLog.COMBATANT_DEFEATED, BattleEventLog.RESTORED,
	BattleEventLog.REVIVED, BattleEventLog.LB_CHANGED, BattleEventLog.LB_CRYSTAL_DROPPED,
	BattleEventLog.STATUS_ADDED, BattleEventLog.STATUS_RESISTED, BattleEventLog.STATUS_REMOVED,
	BattleEventLog.COVER_ACTIVATED, BattleEventLog.COVERED, BattleEventLog.COVER_ENDED,
	BattleEventLog.EFFECT_UNSUPPORTED, BattleEventLog.ACTION_ENDED, BattleEventLog.MULTICAST_CAST_DROPPED,
	BattleEventLog.COUNTER_QUEUED, BattleEventLog.REACTION_DROPPED, BattleEventLog.DELAY_QUEUED,
	BattleEventLog.DELAY_DROPPED, BattleEventLog.DEBUG_EDITED, BattleEventLog.BATTLE_ENDED,
]
const HIDDEN_BY_DEFAULT: Array[StringName] = [BattleEventLog.ACTION_ENDED]
const TYPE_COLORS: Dictionary = {
	BattleEventLog.BATTLE_STARTED: Color(0.45, 0.85, 0.95),
	BattleEventLog.TURN_STARTED: Color(0.45, 0.85, 0.95),
	BattleEventLog.TURN_ENDED: Color(0.45, 0.85, 0.95),
	BattleEventLog.PHASE_CHANGED: Color(0.45, 0.85, 0.95),
	BattleEventLog.BATTLE_ENDED: Color(0.45, 0.85, 0.95),
	BattleEventLog.ACTION_STARTED: Color(0.65, 0.75, 1.0),
	BattleEventLog.HIT_MISSED: Color(0.6, 0.6, 0.65),
	BattleEventLog.COMMAND_QUEUED: Color(0.6, 0.6, 0.65),
	BattleEventLog.ACTION_ENDED: Color(0.5, 0.5, 0.55),
	BattleEventLog.STATUS_ADDED: Color(0.95, 0.85, 0.5),
	BattleEventLog.STATUS_RESISTED: Color(0.95, 0.85, 0.5),
	BattleEventLog.STATUS_REMOVED: Color(0.8, 0.7, 0.45),
	BattleEventLog.COVER_ACTIVATED: Color(0.5, 0.85, 0.85),
	BattleEventLog.COVERED: Color(0.5, 0.85, 0.85),
	BattleEventLog.COVER_ENDED: Color(0.45, 0.7, 0.7),
	BattleEventLog.RESTORED: Color(0.55, 0.9, 0.55),
	BattleEventLog.REVIVED: Color(0.55, 0.9, 0.55),
	BattleEventLog.EFFECT_UNSUPPORTED: Color(1.0, 0.45, 0.4),
	BattleEventLog.COMMAND_REJECTED: Color(1.0, 0.6, 0.35),
	BattleEventLog.COMBATANT_DEFEATED: Color(1.0, 0.45, 0.4),
	BattleEventLog.DEBUG_EDITED: Color(0.9, 0.55, 0.95),
	BattleEventLog.COUNTER_QUEUED: Color(1.0, 0.7, 0.85),
	BattleEventLog.REACTION_DROPPED: Color(1.0, 0.6, 0.35),
	BattleEventLog.DELAY_QUEUED: Color(1.0, 0.7, 0.85),
	BattleEventLog.DELAY_DROPPED: Color(1.0, 0.6, 0.35),
}
const DEFAULT_COLOR := Color(0.88, 0.88, 0.9)

var _engine: BattleEngine = null
var _events: Array[Dictionary] = []
var _hidden: Dictionary = {}
var _types := MenuButton.new()
var _filter := LineEdit.new()
var _follow := CheckBox.new()
var _text := RichTextLabel.new()


func _ready() -> void:
	for type in HIDDEN_BY_DEFAULT:
		_hidden[type] = true
	var bar := HBoxContainer.new()
	add_child(bar)
	var title := Label.new()
	title.text = "Event log"
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	bar.add_child(title)
	_types.text = "Types"
	_types.flat = false
	var popup: PopupMenu = _types.get_popup()
	popup.hide_on_checkable_item_selection = false
	for i in range(TYPES.size()):
		popup.add_check_item(str(TYPES[i]), i)
		popup.set_item_checked(i, not _hidden.has(TYPES[i]))
	popup.id_pressed.connect(_on_type_toggled)
	bar.add_child(_types)
	_filter.placeholder_text = "filter text"
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_text_now: String) -> void: _rebuild())
	bar.add_child(_filter)
	_follow.text = "Follow"
	_follow.button_pressed = true
	_follow.toggled.connect(func(on: bool) -> void: _text.scroll_following = on)
	bar.add_child(_follow)
	var copy := Button.new()
	copy.text = "Copy"
	copy.tooltip_text = "Copy the lines shown (all of them, not only the last %d)" % MAX_LINES
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set("\n".join(_shown_lines())))
	bar.add_child(copy)

	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.scroll_following = true
	_text.selection_enabled = true
	_text.bbcode_enabled = false
	_text.add_theme_font_size_override("normal_font_size", 12)
	add_child(_text)


## Starts a new log for `engine`.
func reset(engine: BattleEngine) -> void:
	_engine = engine
	_events.clear()
	_text.clear()


func append(events: Array[Dictionary]) -> void:
	for event in events:
		_events.append(event)
		var line: String = _line(event)
		if _shows(event, line):
			_write(event, line)


func _rebuild() -> void:
	_text.clear()
	var shown: Array = []
	for event in _events:
		var line: String = _line(event)
		if _shows(event, line):
			shown.append([event, line])
	for entry in shown.slice(maxi(0, shown.size() - MAX_LINES)):
		_write(entry[0], entry[1])


func _shown_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for event in _events:
		var line: String = _line(event)
		if _shows(event, line):
			lines.append(line)
	return lines


func _line(event: Dictionary) -> String:
	return _engine.format_event(event) if _engine != null else str(event)


func _shows(event: Dictionary, line: String) -> bool:
	if _hidden.has(event.get("type", &"")):
		return false
	var needle: String = _filter.text.strip_edges()
	return needle == "" or line.containsn(needle)


func _write(event: Dictionary, line: String) -> void:
	_text.push_color(TYPE_COLORS.get(event.get("type", &""), DEFAULT_COLOR))
	_text.add_text(line)
	_text.pop()
	_text.newline()


func _on_type_toggled(id: int) -> void:
	var type: StringName = TYPES[id]
	if _hidden.has(type):
		_hidden.erase(type)
	else:
		_hidden[type] = true
	_types.get_popup().set_item_checked(id, not _hidden.has(type))
	_rebuild()
