extends Area2D

# Click-to-talk wrapper around an NPC AnimatedSprite2D. Built by
# tile_map.gd._spawn_npcs(). When the user clicks the rectangular hit
# region, looks up the NPC's dialogue line via DialogueLoader and shows
# a DialogueBox overlay.
#
# `monitoring` and `monitorable` are left at their defaults; this Area2D
# is purely for picking input events, not for body/area overlap. It does
# NOT collide with the player's CharacterBody2D so NPC bumping behaviour
# (free walk-through) is preserved from before the wrapper existed.

const DialogueBoxScript := preload("res://features/town/dialogue_box.gd")

var dialogue_line_id: int = -1
var town_id: String = ""

# Set to true while a popup spawned by this NPC is open, so rapid clicks
# don't stack multiple dialog boxes.
var _popup_open: bool = false


func _ready() -> void:
	input_pickable = true
	monitoring = false
	monitorable = false
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _popup_open:
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	# Not every placed NPC talks: 18 of the 195 scripted entities in the
	# current corpus carry no dialogue line at all, and shop NPCs reference a
	# store (shop_id_raw -> town_store) instead of a line. Those are silent
	# scenery until their interaction is wired up.
	if dialogue_line_id < 0 or town_id == "":
		return

	var pages := DialogueLoader.get_dialogue(town_id, dialogue_line_id)
	if pages.is_empty():
		# Nothing to show -- DialogueLoader already logged the reason.
		return

	var box := DialogueBoxScript.new()
	var ui_root := _find_ui_root()
	ui_root.add_child(box)
	box.show_pages(pages)
	_popup_open = true
	box.closed.connect(func(): _popup_open = false)
	get_viewport().set_input_as_handled()


func _on_mouse_entered() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)


func _on_mouse_exited() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# Prefer attaching the popup high in the tree so it isn't yanked away by
# chunk redraws (which free the NpcSprites container). Fall back to the
# current scene root if no other host is available.
func _find_ui_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return self
	var root := tree.current_scene
	if root == null:
		return self
	return root
