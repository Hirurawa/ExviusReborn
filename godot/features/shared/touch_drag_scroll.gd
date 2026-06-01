class_name TouchDragScroll
extends Node

## Attach as a child of a ScrollContainer to enable drag-anywhere touch
## scrolling with inertial momentum. Designed for Android/touch builds where
## interactive child Controls (Buttons, etc.) would otherwise eat the touch
## event before the ScrollContainer can interpret it as a drag.
##
## Behavior:
##   - Coerces descendant Controls from MOUSE_FILTER_STOP to MOUSE_FILTER_PASS
##     so the parent ScrollContainer receives touch events as well. PASS
##     preserves click handling on Buttons, unlike IGNORE.
##   - Tracks touch position; once movement exceeds `drag_threshold`, treats
##     subsequent motion as a drag and calls accept_event() so child Buttons
##     do not fire `pressed` on release.
##   - On release after a drag, applies an exponentially decaying velocity
##     for a native-feeling flick.

@export var drag_threshold: float = 8.0
@export var friction: float = 8.0
@export var min_momentum_velocity: float = 20.0
@export var velocity_smoothing: float = 0.35

var _target: ScrollContainer
var _pressed: bool = false
var _dragging: bool = false
var _gesture_ignored: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _last_position: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _can_scroll_h: bool = false
var _can_scroll_v: bool = false


func _ready() -> void:
	var parent := get_parent()
	if not (parent is ScrollContainer):
		push_warning("TouchDragScroll: parent is not a ScrollContainer (%s)" % parent)
		queue_free()
		return
	_target = parent
	_refresh_scroll_axes()
	_target.gui_input.connect(_on_target_gui_input)
	# Coerce existing descendants now; further coercion happens on each press
	# to cover Controls added dynamically at any depth.
	_coerce_subtree(_target)
	set_process(false)


func _refresh_scroll_axes() -> void:
	_can_scroll_h = _target.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	_can_scroll_v = _target.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED


func _on_descendant_added(node: Node) -> void:
	_coerce_subtree(node)


func _coerce_subtree(root: Node) -> void:
	if root is Control and root != _target:
		var c: Control = root
		if c.mouse_filter == Control.MOUSE_FILTER_STOP and not c.has_meta("touch_drag_keep_stop"):
			c.mouse_filter = Control.MOUSE_FILTER_PASS
	# Hook descendants added later at this depth so the coercion propagates
	# into dynamically built lists/grids no matter when they appear.
	if not root.child_entered_tree.is_connected(_on_descendant_added):
		root.child_entered_tree.connect(_on_descendant_added)
	for child in root.get_children():
		_coerce_subtree(child)


func _on_target_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_press(event.pressed, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_press(event.pressed, event.position)
	elif event is InputEventScreenDrag:
		_handle_motion(event.position)
	elif event is InputEventMouseMotion and _pressed:
		_handle_motion(event.position)


func _handle_press(pressed: bool, position: Vector2) -> void:
	if pressed:
		_pressed = true
		_dragging = false
		_gesture_ignored = false
		_press_position = position
		_last_position = position
		_velocity = Vector2.ZERO
		set_process(false)
		_refresh_scroll_axes()
	else:
		var was_dragging := _dragging
		_pressed = false
		_dragging = false
		_gesture_ignored = false
		if was_dragging:
			# Swallow the release so the underlying Button does not fire `pressed`.
			_target.accept_event()
			if _velocity.length() > min_momentum_velocity:
				set_process(true)


func _handle_motion(position: Vector2) -> void:
	if not _pressed or _gesture_ignored:
		return
	var delta: Vector2 = position - _last_position
	_last_position = position
	if not _dragging:
		var total: Vector2 = position - _press_position
		if total.length() < drag_threshold:
			return
		# Only engage if the dominant axis of the gesture matches an enabled
		# scroll axis. Otherwise let the event propagate to ancestors
		# (e.g. a swipe-to-close handler on a parent panel).
		var wants_horizontal: bool = absf(total.x) > absf(total.y)
		if wants_horizontal and not _can_scroll_h:
			_gesture_ignored = true
			return
		if not wants_horizontal and not _can_scroll_v:
			_gesture_ignored = true
			return
		_dragging = true
	_apply_scroll_delta(delta)
	var frame_dt: float = get_process_delta_time()
	if frame_dt > 0.0:
		var instant_velocity: Vector2 = delta / frame_dt
		_velocity = _velocity.lerp(instant_velocity, velocity_smoothing)
	_target.accept_event()


func _apply_scroll_delta(delta: Vector2) -> void:
	if _can_scroll_h and delta.x != 0.0:
		_target.scroll_horizontal -= int(round(delta.x))
	if _can_scroll_v and delta.y != 0.0:
		_target.scroll_vertical -= int(round(delta.y))


func _process(delta: float) -> void:
	if _pressed:
		set_process(false)
		return
	_apply_scroll_delta(_velocity * delta)
	var decay: float = exp(-friction * delta)
	_velocity *= decay
	if _velocity.length() < min_momentum_velocity:
		_velocity = Vector2.ZERO
		set_process(false)
