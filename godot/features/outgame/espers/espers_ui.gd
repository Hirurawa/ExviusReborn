extends Control

@onready var espers_list_container: VBoxContainer = $VBoxContainer/ScrollContainer/EspersListContainer

func _ready() -> void:
	_populate_espers_list()

func _populate_espers_list() -> void:
	for child in espers_list_container.get_children():
		child.queue_free()

	var summons: Dictionary = DataManager.game_data_summons
	if summons.is_empty():
		_add_empty_state_label("No espers available.")
		return

	var sorted_entries: Array[Dictionary] = []
	for summon_key in summons.keys():
		var summon_id: String = str(summon_key)
		var summon_data: Variant = summons.get(summon_key, {})
		if not (summon_data is Dictionary):
			continue

		sorted_entries.append({
			"id": summon_id,
			"sort_id": int(summon_id) if summon_id.is_valid_int() else 2147483647,
			"data": summon_data
		})

	if sorted_entries.is_empty():
		_add_empty_state_label("No espers available.")
		return

	sorted_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["sort_id"] == b["sort_id"]:
			return String(a["id"]) < String(b["id"])
		return int(a["sort_id"]) < int(b["sort_id"])
	)

	for entry in sorted_entries:
		var summon_id: String = str(entry["id"])
		var summon_name: String = _get_summon_display_name(summon_id, entry["data"])

		var row_button := Button.new()
		row_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row_button.text = "#%s  %s" % [summon_id, summon_name]
		row_button.pressed.connect(_on_esper_pressed.bind(summon_id, summon_name))
		espers_list_container.add_child(row_button)

		var separator := HSeparator.new()
		espers_list_container.add_child(separator)

func _get_summon_display_name(summon_id: String, summon_data: Dictionary) -> String:
	var names_value: Variant = summon_data.get("names", [])
	if names_value is Array:
		var names_array: Array = names_value
		if names_array.size() > 0:
			var primary_name: String = str(names_array[0]).strip_edges()
			if primary_name != "":
				return primary_name
		for name_variant in names_array:
			var fallback_name: String = str(name_variant).strip_edges()
			if fallback_name != "":
				return fallback_name

	return "Summon %s" % summon_id

func _on_esper_pressed(summon_id: String, summon_name: String) -> void:
	UIManager.push("summon_board_ui", {
		"summon_id": summon_id,
		"summon_name": summon_name
	})

func _add_empty_state_label(message: String) -> void:
	var empty_label := Label.new()
	empty_label.text = message
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	espers_list_container.add_child(empty_label)
