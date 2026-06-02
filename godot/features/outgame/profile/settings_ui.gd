extends Control
## SettingsUI — audio volume / mute controls bound to AudioService.
##
## Pushed via `UIManager.push("settings_ui")`. Changes apply immediately and
## are persisted by AudioService to `user://settings/audio.json`.

const BUSES: Array[String] = ["Master", "Music", "SFX", "UI"]

@onready var rows_container: VBoxContainer = %RowsContainer
@onready var close_button: Button = %CloseButton

var _sliders: Dictionary = {}
var _mute_buttons: Dictionary = {}
var _value_labels: Dictionary = {}
var _suppress_signals: bool = false


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	_build_rows()
	_refresh_from_service()


func _build_rows() -> void:
	for bus in BUSES:
		var row: HBoxContainer = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 36)
		row.add_theme_constant_override("separation", 12)
		rows_container.add_child(row)

		var name_label: Label = Label.new()
		name_label.text = bus
		name_label.custom_minimum_size = Vector2(72, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)

		var slider: HSlider = HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_slider_changed.bind(bus))
		row.add_child(slider)
		_sliders[bus] = slider

		var value_label: Label = Label.new()
		value_label.custom_minimum_size = Vector2(44, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value_label)
		_value_labels[bus] = value_label

		var mute_button: CheckButton = CheckButton.new()
		mute_button.text = "Mute"
		mute_button.toggled.connect(_on_mute_toggled.bind(bus))
		row.add_child(mute_button)
		_mute_buttons[bus] = mute_button


func _refresh_from_service() -> void:
	_suppress_signals = true
	for bus in BUSES:
		var linear: float = AudioService.get_bus_volume_linear(bus)
		var muted: bool = AudioService.is_bus_muted(bus)
		(_sliders[bus] as HSlider).value = linear
		(_mute_buttons[bus] as CheckButton).button_pressed = muted
		_update_value_label(bus, linear)
	_suppress_signals = false


func _update_value_label(bus: String, linear: float) -> void:
	(_value_labels[bus] as Label).text = "%d%%" % int(round(linear * 100.0))


func _on_slider_changed(value: float, bus: String) -> void:
	if _suppress_signals:
		return
	AudioService.set_bus_volume_linear(bus, value)
	_update_value_label(bus, value)


func _on_mute_toggled(pressed: bool, bus: String) -> void:
	if _suppress_signals:
		return
	AudioService.set_bus_mute(bus, pressed)


func _on_close_pressed() -> void:
	UIManager.pop()
