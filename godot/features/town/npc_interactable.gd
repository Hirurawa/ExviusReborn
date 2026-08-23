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
const TownStoreScene := preload("res://features/outgame/town_store/town_stores_popup.tscn")

var dialogue_line_id: int = -1
var town_id: String = ""
var quest_town_id: String = ""
var npc_ids: Array = []
var shop_id: int = 0

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
	if town_id == "":
		push_warning("NpcInteractable: missing town_id")
		return

	var speaker_id := DialogueLoader.get_speaker_id(town_id, dialogue_line_id) if dialogue_line_id >= 0 else -1
	if speaker_id >= 0 and not npc_ids.has(speaker_id):
		npc_ids.append(speaker_id)
	var quest: Dictionary = QuestService.find_current_quest_for_npc(quest_town_id, npc_ids) if quest_town_id != "" else {}
	var pages := get_quest_pages(quest) if not quest.is_empty() else get_pages()
	if pages.is_empty():
		push_warning("NpcInteractable: no dialogue or shop greeting")
		return
	if not quest.is_empty():
		var accepted := QuestService.accept_quest_from_npc(quest_town_id, npc_ids)
		if not accepted.is_empty():
			pages.append({"speaker": "Quest", "body": "Quest accepted: %s" % accepted.get("name", "")})

	var box := DialogueBoxScript.new()
	var ui_root := _find_ui_root()
	ui_root.add_child(box)
	box.show_pages(pages)
	_popup_open = true
	box.closed.connect(_on_dialogue_closed)
	get_viewport().set_input_as_handled()


func get_quest_pages(quest: Dictionary) -> Array:
	var tasks: Array = quest.get("tasks", [])
	var task: Dictionary = tasks[0] if not tasks.is_empty() else {}
	var body := str(task.get("detail", task.get("text", "")))
	return [{"speaker": str(quest.get("name", "Quest")), "body": body}]


func _on_dialogue_closed() -> void:
	_popup_open = false
	if shop_id <= 0 or quest_town_id == "":
		return
	var popup: Control = TownStoreScene.instantiate()
	_find_ui_root().add_child(popup)
	popup.open_store(quest_town_id, shop_id)


func get_pages() -> Array:
	if dialogue_line_id >= 0:
		var dialogue := DialogueLoader.get_dialogue(town_id, dialogue_line_id)
		if not dialogue.is_empty():
			return dialogue
	if shop_id > 0:
		var store := GameDatabase.get_town_store_greeting(shop_id)
		if not store.is_empty():
			return [{
				"speaker": str(store.get("ownerName", store.get("name", "Shopkeeper"))),
				"body": str(store.get("comment", "Welcome to the %s." % store.get("name", "shop"))),
			}]
	return []


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
