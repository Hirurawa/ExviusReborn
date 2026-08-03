class_name BattleDialogue
extends CanvasLayer

## Minimal in-battle dialogue overlay: a text panel pinned to the top of the
## screen plus a full-screen click-catcher. Because the catcher sits on a high
## CanvasLayer and consumes clicks, it also blocks the battle UI beneath while a
## line is showing (BattleManager pauses the turn engine in parallel).
##
## Wiring (done in battle_ui.gd):
##   battle_manager.dialogue_requested.connect(overlay.play)
##   overlay.finished.connect(battle_manager.close_dialogue)

signal finished

var _lines: Array = []
var _idx: int = 0
var _click: Button
var _speaker: Label
var _text: Label


func _ready() -> void:
	layer = 128          # above the battle UI
	visible = false
	_build()


func _build() -> void:
	# Full-screen transparent click-catcher. Button defaults to MOUSE_FILTER_STOP,
	# so on its high layer it consumes the click before the battle UI sees it.
	_click = Button.new()
	_click.flat = true
	_click.focus_mode = Control.FOCUS_NONE
	_click.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_click.pressed.connect(_advance)
	add_child(_click)

	# Text panel across the top. IGNORE mouse so taps fall through to _click.
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 12
	panel.offset_right = -12
	panel.offset_top = 20
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	_speaker = Label.new()
	_speaker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_speaker.add_theme_font_size_override("font_size", 16)
	_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_speaker)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 18)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_text)

	var hint := Label.new()
	hint.text = "▼ tap to continue"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hint.add_theme_font_size_override("font_size", 12)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint)


## Play an ordered list of {speaker, text} lines. Emits `finished` when the last
## line is dismissed (or immediately if the list is empty).
func play(lines: Array) -> void:
	_lines = lines
	_idx = 0
	if _lines.is_empty():
		finished.emit()
		return
	visible = true
	_show(0)


func _advance() -> void:
	_idx += 1
	if _idx >= _lines.size():
		visible = false
		finished.emit()
	else:
		_show(_idx)


func _show(i: int) -> void:
	var ln: Dictionary = _lines[i]
	var spk: String = str(ln.get("speaker", ""))
	_speaker.text = spk
	_speaker.visible = spk != "" and spk != "(system)"
	_text.text = str(ln.get("text", ""))
