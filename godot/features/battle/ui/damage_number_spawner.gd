extends RefCounted
class_name DamageNumberSpawner

## Spawns floating damage-number labels inside a target Control and animates them.
## Holds a tiny pool of recycled Labels so multi-hit bursts don't churn allocations.
##
## Usage:
##   var spawner := DamageNumberSpawner.new(host_node)
##   spawner.spawn(damage_value, target_damage_container)
##   # On scene exit:
##   spawner.clear_pool()

const PUSH_AMOUNT: float = 40.0
const PUSH_DURATION: float = 0.15
const FADE_DURATION: float = 1.0
const DAMAGE_FONT_SIZE: int = 32
const POOL_CAP: int = 16

const DAMAGE_COLOR := Color(1, 0.2, 0.2)
const OUTLINE_COLOR := Color(0, 0, 0)
const OUTLINE_SIZE: int = 4

var _host: Node
var _pool: Array[Label] = []


## `host` is the Node used to create_tween() against (needs a scene tree).
func _init(host: Node) -> void:
	_host = host


## Spawn a damage number inside `container`. Existing labels in the container
## get pushed up to make room.
func spawn(damage: int, container: Control) -> void:
	if container == null or _host == null or not is_instance_valid(_host):
		return

	# Push existing labels up.
	for child in container.get_children():
		if child is Label:
			var move_tween: Tween = _host.create_tween()
			move_tween.tween_property(child, "position:y", child.position.y - PUSH_AMOUNT, PUSH_DURATION) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var label: Label = _acquire_label()
	label.text = str(damage)
	container.add_child(label)
	# Re-apply the full-rect preset *after* reparenting. add_child() on an
	# already-anchored Control mutates its offsets to preserve the previous
	# on-screen rect, so a pooled label dragged from a different container
	# (or from a different container size) carries stale offsets that bloat
	# the label's rect and visually push centered text down-right. This
	# zeroes both anchors and offsets so the label exactly fills `container`.
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.position = Vector2.ZERO
	label.modulate = Color(1, 1, 1, 1)

	var fade_tween: Tween = _host.create_tween()
	fade_tween.tween_property(label, "modulate:a", 0.0, FADE_DURATION) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	fade_tween.finished.connect(func(): _release_label(label))


## Drop pooled labels (call on scene exit to avoid hanging references).
func clear_pool() -> void:
	for label in _pool:
		if is_instance_valid(label):
			label.queue_free()
	_pool.clear()


# --- internals --------------------------------------------------------------

func _acquire_label() -> Label:
	while not _pool.is_empty():
		var candidate: Label = _pool.pop_back()
		if is_instance_valid(candidate):
			return candidate
	return _make_label()


func _release_label(label: Label) -> void:
	if not is_instance_valid(label):
		return
	if label.get_parent() != null:
		label.get_parent().remove_child(label)
	if _pool.size() < POOL_CAP:
		_pool.append(label)
	else:
		label.queue_free()


func _make_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", DAMAGE_FONT_SIZE)
	label.add_theme_color_override("font_color", DAMAGE_COLOR)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
