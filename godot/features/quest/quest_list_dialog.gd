extends AcceptDialog
class_name QuestListDialog

signal quest_progress_updated

@onready var container: VBoxContainer = $ScrollContainer/VBoxContainer

func _ready() -> void:
	self.title = "Town Quests"
	self.ok_button_text = "Close"
	self.min_size = Vector2(400, 300)
	self.popup_window = true

func populate(quests: Array[Dictionary]) -> void:
	if not is_inside_tree():
		await ready

	# Clear previous entries
	for child in container.get_children():
		child.queue_free()

	if quests.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No quests available."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(empty_label)
		return

	for quest in quests:
		var quest_vbox = VBoxContainer.new()
		container.add_child(quest_vbox)

		var top_hbox = HBoxContainer.new()
		quest_vbox.add_child(top_hbox)

		var name_label = Label.new()
		name_label.text = "• " + str(quest.get("name", "Unknown Quest"))
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.modulate = Color(1.0, 0.9, 0.5) # A golden color for quests
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_hbox.add_child(name_label)

		var open_switch = quest.get("openSwitch", "")
		var is_new = false
		var is_done = false
		var start_switch = ""
		var end_switch = ""

		if open_switch != "":
			var parts = open_switch.split(",")
			if parts.size() >= 2:
				start_switch = parts[0].strip_edges()
				end_switch = parts[parts.size() - 1].strip_edges()
				if SwitchService.is_unlocked(end_switch):
					is_done = true
				elif not SwitchService.is_unlocked(start_switch):
					is_new = true

		var status_label = Label.new()
		if is_done:
			status_label.text = "[Done]"
			status_label.modulate = Color(0.5, 0.5, 0.5)
		elif is_new:
			status_label.text = "[New]"
			status_label.modulate = Color(0.5, 1.0, 0.5)
		else:
			status_label.text = "[In Progress]"
			status_label.modulate = Color(0.5, 0.8, 1.0)
		top_hbox.add_child(status_label)

		var action_button = Button.new()
		if is_done:
			action_button.text = "Done"
			action_button.disabled = true
		elif is_new:
			action_button.text = "Start"
			action_button.pressed.connect(func(): _start_quest(start_switch))
		else:
			action_button.text = "Finish"
			var can_finish = _check_requirements(quest)
			action_button.disabled = not can_finish
			action_button.pressed.connect(func(): _finish_quest(end_switch, quest))
		top_hbox.add_child(action_button)

		var tasks = quest.get("tasks", [])
		if tasks.is_empty():
			var no_task_label = Label.new()
			no_task_label.text = "    No active tasks."
			no_task_label.add_theme_font_size_override("font_size", 12)
			no_task_label.modulate = Color(0.7, 0.7, 0.7)
			quest_vbox.add_child(no_task_label)
		else:
			for task in tasks:
				var task_label = Label.new()
				task_label.text = "    - " + str(task.get("text", task)) if typeof(task) == TYPE_DICTIONARY else "    - " + str(task)
				task_label.add_theme_font_size_override("font_size", 14)
				task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				quest_vbox.add_child(task_label)

				if typeof(task) == TYPE_DICTIONARY and task.has("requirements") and not task["requirements"].is_empty():
					for req in task["requirements"]:
						var req_label = Label.new()
						req_label.text = "        * " + str(req)
						req_label.add_theme_font_size_override("font_size", 12)
						req_label.modulate = Color(0.8, 1.0, 0.8) # Light green color for requirements
						req_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
						quest_vbox.add_child(req_label)

		var rewards = quest.get("rewards", [])
		if not rewards.is_empty():
			var reward_title_label = Label.new()
			reward_title_label.text = "    Rewards:"
			reward_title_label.add_theme_font_size_override("font_size", 12)
			reward_title_label.modulate = Color(0.8, 0.8, 1.0)
			quest_vbox.add_child(reward_title_label)

			for reward in rewards:
				var reward_label = Label.new()
				reward_label.text = "      + " + str(reward)
				reward_label.add_theme_font_size_override("font_size", 12)
				reward_label.modulate = Color(0.8, 0.8, 1.0)
				reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				quest_vbox.add_child(reward_label)

		var separator = HSeparator.new()
		container.add_child(separator)

func _start_quest(start_switch: String) -> void:
	if start_switch != "":
		SwitchService.unlock_switches(start_switch)
		Persistence.save_snapshot(SwitchService.SNAPSHOT_FILE, SwitchService.snapshot_payload(), "start_quest")
		quest_progress_updated.emit()

func _check_requirements(quest: Dictionary) -> bool:
	for task in quest.get("tasks", []):
		if typeof(task) == TYPE_DICTIONARY and task.get("target_type", "") == "1":
			for req in task.get("raw_requirements", []):
				var type = req.get("type")
				var id = req.get("id")
				var amount = req.get("amount", 0)
				if InventoryService.get_item_count(type, id) < amount:
					return false
	return true

func _finish_quest(end_switch: String, quest: Dictionary) -> void:
	for task in quest.get("tasks", []):
		if typeof(task) == TYPE_DICTIONARY and task.get("target_type", "") == "1":
			var items_to_consume = []
			for req in task.get("raw_requirements", []):
				items_to_consume.append({"id": req.get("id"), "amount": req.get("amount")})
			if not items_to_consume.is_empty():
				InventoryService.consume_stackables_and_save(items_to_consume)

	var items_granted: bool = false
	for reward in quest.get("raw_rewards", []):
		var type = reward.get("type")
		var id = reward.get("id")
		var amount = reward.get("amount", 0)

		if type == "20":
			InventoryService.add_stackable(id, amount)
			items_granted = true
		elif type == "21":
			InventoryService.add_equipment_instances(id, amount)
			items_granted = true

	if items_granted:
		InventoryService.emit_updated()
		Persistence.save_snapshot(InventoryService.SNAPSHOT_FILE, InventoryService.snapshot_payload(), "quest_reward")

	if end_switch != "":
		SwitchService.unlock_switches(end_switch)
		Persistence.save_snapshot(SwitchService.SNAPSHOT_FILE, SwitchService.snapshot_payload(), "finish_quest")

	quest_progress_updated.emit()
