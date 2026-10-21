class_name EventDialogue
extends Control

## The cinema window: the panel across the bottom of the screen that cutscene dialogue
## plays in (CUTSCENE-PLAN.md section 8.4). EventStage calls tick() once per frame.
##
## A line reveals a few characters a frame, pausing on the <wait> tokens inside it. A
## <wait> at the end of a page is where it waits for the keypress (the user): the ▼
## shows, blinking, and a tap turns the page or ends the line; a tap while the page is
## still appearing completes it. A line marked <invalid_touchwait> has nobody to wait
## for, so its last wait runs as a pause and the line ends by itself. The panel stays
## up, empty, between lines.
##
## Layout, from the two recordings (CUTSCENE-PLAN.md section 8.7): the window's top edge
## sits at 64.5% of the screen height (64.2% and 64.8%) and the window runs to the
## bottom; what is inside scales with the screen height (the second recording, 917 px
## tall, shows the text at 0.83 of the first's size, 917 / 1107). Positions are in
## pixels at the first recording's height, a 640 x 1107 screen.
const REFERENCE_HEIGHT: float = 1107.0
const TOP_FRACTION: float = 0.645
const NAME_POSITION: Vector2 = Vector2(28, 14)
const TEXT_POSITION: Vector2 = Vector2(45, 66)
## The ▼ sits 34 px from the window's right edge and 30 px from its bottom.
const CURSOR_MARGIN: Vector2 = Vector2(34, 30)
const CURSOR_SIZE: Vector2 = Vector2(24, 16)
const FONT_SIZE: int = 24
## Lines sit 44 px apart at the reference height.
const LINE_SPACING: int = 14
## The window's corner ornaments keep their size when it stretches.
const PATCH_MARGIN: int = 16
## <speed=N> shows a character every N / 2 frames. The default is a reading of the
## recording, about a character every 1.5 frames (❓).
const DEFAULT_SPEED: int = 3
## The ▼ first shows about 0.5 s after the page is out, then blinks about 0.67 s on and
## 0.83 s off (first recording).
const CURSOR_DELAY_FRAMES: int = 30
const CURSOR_ON_FRAMES: int = 40
const CURSOR_OFF_FRAMES: int = 50

enum State { IDLE, REVEAL, CURSOR, DONE }

## (speaker_id: int, speaker_kind: String) -> String. Set by EventStage.
var name_resolver: Callable

var state: int = State.IDLE
var line: EventText = null
var text_id: int = -1

## Screen height / REFERENCE_HEIGHT.
var ui_scale: float = 1.0

var _window: NinePatchRect
var _name: Label
var _text: Label
var _cursor: TextureRect
var _page: int = 0
var _token: int = 0
var _char: int = 0
var _pause: int = 0
var _speed: int = DEFAULT_SPEED
var _progress: float = 0.0
var _shown: String = ""
var _cursor_age: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_scale = get_viewport().get_visible_rect().size.y / REFERENCE_HEIGHT
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor_top = TOP_FRACTION
	offset_top = 0
	_window = NinePatchRect.new()
	_window.texture = preload("res://assets/ui/event/cinema_window.tres")
	_window.patch_margin_left = PATCH_MARGIN
	_window.patch_margin_right = PATCH_MARGIN
	_window.patch_margin_top = PATCH_MARGIN
	_window.patch_margin_bottom = PATCH_MARGIN
	_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_window)
	_name = _label(NAME_POSITION * ui_scale)
	_text = _label(TEXT_POSITION * ui_scale)
	_text.add_theme_constant_override("line_spacing", roundi(LINE_SPACING * ui_scale))
	_cursor = TextureRect.new()
	_cursor.texture = preload("res://assets/ui/event/talk_cursor.tres")
	_cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_cursor.offset_right = -CURSOR_MARGIN.x * ui_scale
	_cursor.offset_bottom = -CURSOR_MARGIN.y * ui_scale
	_cursor.offset_left = _cursor.offset_right - CURSOR_SIZE.x * ui_scale
	_cursor.offset_top = _cursor.offset_bottom - CURSOR_SIZE.y * ui_scale
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.visible = false
	add_child(_cursor)


## Starts line `text_id`, whose raw markup is `raw`.
func show_line(id: int, raw: String) -> void:
	text_id = id
	line = EventText.parse(raw)
	var speaker: String = ""
	if line.speaker_id >= 0 and name_resolver.is_valid():
		speaker = str(name_resolver.call(line.speaker_id, line.speaker_kind))
	_name.text = speaker
	_page = 0
	_speed = DEFAULT_SPEED
	_start_page()


## A tap: completes the page while it appears, turns the page or ends the line at the
## cursor. Returns true when the tap was used.
func tap() -> bool:
	match state:
		State.REVEAL:
			_shown = EventText.page_text(line.pages[_page])
			_text.text = _shown
			_token = line.pages[_page].size()
			_pause = 0
			_end_page()
			return true
		State.CURSOR:
			if _page + 1 < line.pages.size():
				_page += 1
				_start_page()
			else:
				_close()
			return true
	return false


## One frame of the reveal, or of the cursor's blink.
func tick() -> void:
	if state == State.CURSOR:
		_cursor_age += 1
		_cursor.visible = _cursor_age >= 0 and _cursor_age % (CURSOR_ON_FRAMES + CURSOR_OFF_FRAMES) < CURSOR_ON_FRAMES
		return
	if state != State.REVEAL:
		return
	if _pause > 0:
		_pause -= 1
		if _pause > 0:
			return
	_progress += 2.0 / float(maxi(_speed, 1))
	var tokens: Array = line.pages[_page]
	var holds_tap: bool = not (line.auto_close and _page + 1 >= line.pages.size())
	while _token < tokens.size():
		var token: Dictionary = tokens[_token]
		if token.has("wait") and holds_tap and EventDialogue._only_waits_from(tokens, _token):
			break  # the page is out: the keypress takes over
		if token.has("wait"):
			_token += 1
			_pause = int(token["wait"])
			if _pause > 0:
				return
			continue
		if token.has("speed"):
			_speed = int(token["speed"])
			_token += 1
			continue
		var text: String = token["text"]
		while _char < text.length():
			if text[_char] == "\n":
				_shown += "\n"
				_char += 1
				continue
			if _progress < 1.0:
				_text.text = _shown
				return
			_shown += text[_char]
			_char += 1
			_progress -= 1.0
		_token += 1
		_char = 0
	_text.text = _shown
	_end_page()


## A line is on screen and not yet finished: what `advance` waits for.
func is_busy() -> bool:
	return state == State.REVEAL or state == State.CURSOR


## The text currently on the panel.
func shown_text() -> String:
	return _shown


func shown_name() -> String:
	return _name.text


func cursor_visible() -> bool:
	return _cursor.visible


func _start_page() -> void:
	_token = 0
	_char = 0
	_pause = 0
	_progress = 0.0
	_shown = ""
	_text.text = ""
	_cursor.visible = false
	state = State.REVEAL


func _end_page() -> void:
	if line.auto_close and _page + 1 >= line.pages.size():
		_close()
		return
	state = State.CURSOR
	_cursor_age = -CURSOR_DELAY_FRAMES
	_cursor.visible = false


func _close() -> void:
	state = State.DONE
	_shown = ""
	_text.text = ""
	_name.text = ""
	_cursor.visible = false


static func _only_waits_from(tokens: Array, from: int) -> bool:
	for i in range(from, tokens.size()):
		if not tokens[i].has("wait"):
			return false
	return true


func _label(at: Vector2) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", roundi(FONT_SIZE * ui_scale))
	label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
