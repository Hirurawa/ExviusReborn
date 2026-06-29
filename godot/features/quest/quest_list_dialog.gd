extends AcceptDialog
class_name QuestListDialog

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

		var name_label = Label.new()
		name_label.text = "• " + str(quest.get("name", "Unknown Quest"))
		name_label.add_theme_font_size_override("font_size", 16)
		# Optional: add bold theme or color
		name_label.modulate = Color(1.0, 0.9, 0.5) # A golden color for quests
		quest_vbox.add_child(name_label)

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
				task_label.text = "    - " + str(task)
				task_label.add_theme_font_size_override("font_size", 14)
				task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				quest_vbox.add_child(task_label)

		var separator = HSeparator.new()
		container.add_child(separator)
