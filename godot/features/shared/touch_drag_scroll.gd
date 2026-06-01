class_name TouchDragScroll
extends Node

# Attach as a child of a ScrollContainer to enable touch-drag scrolling on
# mobile / touch builds.
#
# Why this exists (Android specifics):
#   Setting descendant Controls to MOUSE_FILTER_PASS is the textbook fix,
#   but on Android BaseButton captures the press internally, so the
#   follow-up InputEventScreenDrag events do not always reach the
#   ScrollContainer's _gui_input. The engine's built-in scroll then never
#   engages, which is why scrolling fails on a real device even though it
#   works on desktop (mouse-emulated touch).
#
# What this script does:
#   1. Coerces descendant Controls' mouse_filter from STOP to PASS so the
#      visual press/click behavior is preserved and code relying on
#      gui_input on those Controls still gets the events.
#   2. Listens at the Node-level _input, which receives every event in the
#      viewport regardless of focus/capture. When a touch begins inside
#      the ScrollContainer's global rect, we track subsequent drags and
#      scroll manually. Past a small threshold we mark the gesture as a
#      drag, force the focused Button to un-press, and mark the release as
#      handled so no pressed signal fires.
#   3. Applies a brief exponential momentum after release for natural feel.
#
# Cross-axis swipes (e.g. left/right swipe inside a vertical-only list to
# trigger a swipe-close handler on a parent) are not consumed: we ignore
# the gesture as soon as we see its dominant axis is not a scrollable one.
#
# Per-Control opt-out: set_meta("touch_drag_keep_stop", true) on a
# descendant Control to leave its mouse_filter unchanged.

@export var drag_threshold: float = 8.0
@export var friction: float = 8.0
@export var min_momentum_velocity: float = 20.0
@export var velocity_smoothing: float = 0.35

var _target: ScrollContainer
var _tracking: bool = false
var _dragging: bool = false
var _ignored_gesture: bool = false
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
	_coerce_subtree(_target)
	set_process(false)


func _on_descendant_added(node: Node) -> void:
	_coerce_subtree(node)


func _coerce_subtree(root: Node) -> void:
	if root is Control and root != _target:
		var c: Control = root
		if c.mouse_filter == Control.MOUSE_FILTER_STOP and not c.has_meta("touch_drag_keep_stop"):
			c.mouse_filter = Control.MOUSE_FILTER_PASS
	if not root.child_entered_tree.is_connected(_on_descendant_added):
		root.child_entered_tree.connect(_on_descendant_added)
	for child in root.get_children():
		_coerce_subtree(child)


func _refresh_scroll_axes() -> void:
	_can_scroll_h = _target.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	_can_scroll_v = _target.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_target) or not _target.is_visible_in_tree():
		return

	if event is InputEventScreenTouch:
		_handle_press(event.pressed, event.position)
	elif event is InputEventScreenDrag:
		_handle_motion(event.position)


func _handle_press(pressed: bool, position: Vector2) -> void:
	if pressed:
		var rect: Rect2 = _target.get_global_rect()
		if not rect.has_point(position):
			_tracking = false
			return
		_refresh_scroll_axes()
		if not _can_scroll_h and not _can_scroll_v:
			_tracking = false
			return
		_tracking = true
		_dragging = false
		_ignored_gesture = false
		_press_position = position
		_last_position = position
		_velocity = Vector2.ZERO
		set_process(false)
	else:
		if not _tracking:
			return
		var was_dragging := _dragging
		_tracking = false
		_dragging = false
		_ignored_gesture = false
		if was_dragging:
			get_viewport().set_input_as_handled()
			if _velocity.length() > min_momentum_velocity:
				set_process(true)


func _handle_motion(position: Vector2) -> void:
	if not _tracking or _ignored_gesture:
		return
	var delta: Vector2 = position - _last_position
	_last_position = position

	if not _dragging:
		var total: Vector2 = position - _press_position
		if total.length() < drag_threshold:
			return
		var wants_horizontal: bool = absf(total.x) > absf(total.y)
		if wants_horizontal and not _can_scroll_h:
			_ignored_gesture = true
			return
		if not wants_horizontal and not _can_scroll_v:
			_ignored_gesture = true
			return
		_dragging = true
		_release_pressed_focus()

	_apply_scroll_delta(delta)
	var frame_dt: float = get_process_delta_time()
	if frame_dt > 0.0:
		var instant: Vector2 = delta / frame_dt
		_velocity = _velocity.lerp(instant, velocity_smoothing)
	get_viewport().set_input_as_handled()


func _apply_scroll_delta(delta: Vector2) -> void:
	if _can_scroll_h and delta.x != 0.0:
		_target.scroll_horizontal -= int(round(delta.x))
	if _can_scroll_v and delta.y != 0.0:
		_target.scroll_vertical -= int(round(delta.y))


func _release_pressed_focus() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var focused: Control = vp.gui_get_focus_owner()
	if focused is BaseButton:
		(focused as BaseButton).button_pressed = false
		focused.release_focus()


func _process(delta: float) -> void:
	if _tracking:
		set_process(false)
		return
	_apply_scroll_delta(_velocity * delta)
	var decay: float = exp(-friction * delta)
	_velocity *= decay
	if _velocity.length() < min_momentum_velocity:
		_velocity = Vector2.ZERO
		set_process(false)
