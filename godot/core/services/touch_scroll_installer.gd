extends Node

## Autoload that attaches a TouchDragScroll helper to every ScrollContainer
## in the scene tree, including ones added later. Provides Android-friendly
## drag-anywhere touch scrolling without per-scene edits.
##
## Opt-out: call `set_meta("skip_touch_drag", true)` on a ScrollContainer
## before it enters the tree to leave it untouched.

const _TouchDragScrollScript: Script = preload("res://features/shared/touch_drag_scroll.gd")
const _HELPER_NAME: String = "_TouchDragScroll"

var _attached_count: int = 0


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	# Attach to ScrollContainers already in the tree at startup.
	_scan(get_tree().root)


func _on_node_added(node: Node) -> void:
	if node is ScrollContainer:
		# Defer so the ScrollContainer finishes its own _ready first.
		_attach.call_deferred(node)


func _scan(root: Node) -> void:
	if root is ScrollContainer:
		_attach(root)
	for child in root.get_children():
		_scan(child)


func _attach(sc: ScrollContainer) -> void:
	if not is_instance_valid(sc) or not sc.is_inside_tree():
		return
	if sc.has_meta("skip_touch_drag") and sc.get_meta("skip_touch_drag"):
		return
	if sc.has_node(_HELPER_NAME):
		return
	var helper: Node = Node.new()
	helper.name = _HELPER_NAME
	helper.set_script(_TouchDragScrollScript)
	sc.add_child(helper)
	_attached_count += 1
