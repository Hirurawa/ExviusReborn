extends SceneTree


func _initialize() -> void:
	await process_frame
	var switches: Node = root.get_node("SwitchService")
	var quests: Node = root.get_node("QuestService")
	var old_switches: Array = switches.opened_switches
	switches.opened_switches = []
	var dialogue_loader: Script = load("res://core/dialogue_loader.gd")
	var speaker_id: int = dialogue_loader.get_speaker_id("111020100", 110170)
	assert(not dialogue_loader.get_dialogue("111020100", 110170)[0].body.contains("\n"))
	assert(quests.find_current_quest_for_npc("1101", [speaker_id]).get("id") == "1001002")
	assert(quests.get_quests_for_town("1101").is_empty())
	switches.opened_switches = ["20004011"]
	assert(quests.get_quests_for_town("1101").size() == 1)
	var npc: Node = load("res://features/town/npc_interactable.gd").new()
	npc.town_id = "111020100"
	npc.shop_id = 110103
	assert(npc.get_pages()[0].body == "Welcome!")
	var feather_quest: Dictionary = quests.find_current_quest_for_npc("1101", [1101060])
	assert(npc.get_quest_pages(feather_quest)[0].body.begins_with("You have been tasked"))
	npc.free()
	var popup: Control = load("res://features/outgame/town_store/town_stores_popup.tscn").instantiate()
	root.add_child(popup)
	await process_frame
	popup.open_store("1101", 110103)
	assert(popup.title_label.text == "Armorer")
	assert(popup.list_container.get_child_count() > 0)
	assert(root.get_node("InventoryService").get_item_cost("310000100", 21) == 140)
	assert(root.get_node("InventoryService").get_item_cost("310000100", 20) == 0)
	popup.free()
	switches.opened_switches = old_switches
	print("QUEST_SYSTEM_OK")
	quit()
