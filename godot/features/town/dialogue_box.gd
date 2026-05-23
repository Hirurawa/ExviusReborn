class_name DialogueBox
extends CanvasLayer

# Bottom-of-screen modal dialog box. Built entirely in code so we don't
# need a .tscn file. Show with `show_pages(pages)` where pages is the
# Array returned by DialogueLoader.get_dialogue(); each entry is
# { "speaker": String, "body": String }. Click anywhere on the box (or
# press ui_accept) to advance; the box queue_free's itself after the
# last page.

signal closed

const PANEL_HEIGHT_RATIO: float = 0.32   # fraction of viewport height
const HORIZ_MARGIN: int = 24
const BOTTOM_MARGIN: int = 24

var _pages: Array = []
var _index: int = 0

var _panel: PanelContainer
var _speaker_label: Label
var _body_label: RichTextLabel
var _hint_label: Label


func _ready() -> void:
	layer = 100  # render above town-scene content
	_build_ui()
	# Block input from falling through to the town while open.
	process_mode = Node.PROCESS_MODE_ALWAYS


func show_pages(pages: Array) -> void:
	_pages = pages
	_index = 0
	if _pages.is_empty():
		_close()
		return
	_render_current()


func _build_ui() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_height: float = viewport_size.y * PANEL_HEIGHT_RATIO

	# Root MarginContainer anchored to bottom of the screen.
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = HORIZ_MARGIN
	_panel.offset_right = -HORIZ_MARGIN
	_panel.offset_top = -panel_height
	_panel.offset_bottom = -BOTTOM_MARGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_gui_input)
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 20)
	_speaker_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_speaker_label.text = ""
	vbox.add_child(_speaker_label)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = false
	_body_label.fit_content = false
	_body_label.scroll_active = true
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("normal_font_size", 18)
	vbox.add_child(_body_label)

	_hint_label = Label.new()
	_hint_label.text = "▼ Click or press Enter to continue"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_hint_label)


func _render_current() -> void:
	var page: Dictionary = _pages[_index]
	var speaker := String(page.get("speaker", ""))
	var body := String(page.get("body", ""))
	if speaker.is_empty():
		_speaker_label.hide()
	else:
		_speaker_label.show()
		_speaker_label.text = speaker
	_body_label.text = body
	# Update hint on the last page.
	if _index == _pages.size() - 1:
		_hint_label.text = "▼ Click or press Enter to close"
	else:
		_hint_label.text = "▼ Click or press Enter to continue"


func _advance() -> void:
	_index += 1
	if _index >= _pages.size():
		_close()
		return
	_render_current()


func _close() -> void:
	emit_signal("closed")
	queue_free()


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_advance()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_advance()
		get_viewport().set_input_as_handled()
