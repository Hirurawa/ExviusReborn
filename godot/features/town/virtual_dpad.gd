extends Control

# Maps child node names to the corresponding InputMap actions
const BUTTON_MAPPING = {
	"left": ["ui_left"],
	"right": ["ui_right"],
	"up": ["ui_up"],
	"down": ["ui_down"],
	"up_left": ["ui_up", "ui_left"],
	"up_right": ["ui_up", "ui_right"],
	"down_left": ["ui_down", "ui_left"],
	"down_right": ["ui_down", "ui_right"]
}

var _buttons: Dictionary = {}
var _current_active_button: String = ""
var _touch_index: int = -1

func _ready() -> void:
	for btn_name in BUTTON_MAPPING.keys():
		var btn: TextureButton = get_node_or_null(btn_name)
		if btn:
			# Ignore mouse so the Control (this node) can handle _gui_input / _input globally for dragging
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_buttons[btn_name] = btn

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	# Only care about touch or mouse events
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventMouseMotion):
		return

	var is_pressed = false
	var pos = Vector2.ZERO
	var touch_idx = -1

	if event is InputEventScreenTouch:
		is_pressed = event.pressed
		pos = event.position
		touch_idx = event.index
	elif event is InputEventScreenDrag:
		is_pressed = true
		pos = event.position
		touch_idx = event.index
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		is_pressed = event.pressed
		pos = event.position
		touch_idx = 0 # Mouse is index 0
	elif event is InputEventMouseMotion:
		is_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		pos = event.position
		touch_idx = 0

	# If we have an active touch that was released
	if not is_pressed:
		if touch_idx == _touch_index or _touch_index == -1:
			_release_current()
			_touch_index = -1
		return

	# If a touch is active but it's a different finger, ignore it
	if _touch_index != -1 and touch_idx != _touch_index:
		return

	# Check which button contains the point
	var found_btn_name = ""
	for btn_name in _buttons.keys():
		var btn: TextureButton = _buttons[btn_name]
		var rect = btn.get_global_rect()
		if rect.has_point(pos):
			found_btn_name = btn_name
			break

	# Update state
	if found_btn_name != "":
		_touch_index = touch_idx
		if found_btn_name != _current_active_button:
			_release_current()
			_press_button(found_btn_name)
	elif _touch_index == touch_idx:
		# Finger dragged off the D-pad
		_release_current()
		_touch_index = -1

func _press_button(btn_name: String) -> void:
	_current_active_button = btn_name

	# Update visuals (simulate pressed state)
	var btn: TextureButton = _buttons[btn_name]
	btn.button_pressed = true

	# Trigger actions
	for action in BUTTON_MAPPING[btn_name]:
		Input.action_press(action)

func _release_current() -> void:
	if _current_active_button == "":
		return

	var btn_name = _current_active_button
	_current_active_button = ""

	if _buttons.has(btn_name):
		var btn: TextureButton = _buttons[btn_name]
		btn.button_pressed = false

	for action in BUTTON_MAPPING[btn_name]:
		Input.action_release(action)
