extends Control

@onready var units_list_container = $VBoxContainer/ScrollContainer/UnitsListContainer

func _ready():
	DataManager.units_updated.connect(_on_units_updated)
	_refresh_units_list(DataManager.owned_units_ids)

func _on_units_updated(units: Array):
	_refresh_units_list(units)

func _refresh_units_list(owned_units_ids: Array) -> void:
	for child in units_list_container.get_children():
		child.queue_free()

	if owned_units_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No units owned."
		units_list_container.add_child(empty_label)
		return

	for unit_inst in owned_units_ids:
		if not unit_inst is Dictionary:
			continue

		var unit_id = unit_inst.get("unit_id", "")
		var unit_data: Dictionary = DataManager.game_data_units.get(unit_id, {})

		var container = VBoxContainer.new()
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.alignment = BoxContainer.ALIGNMENT_CENTER

		var tex_btn = TextureButton.new()
		var img_path = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
		var tex = load(img_path)
		if tex:
			tex_btn.texture_normal = tex

		tex_btn.custom_minimum_size = Vector2(80, 80)
		tex_btn.ignore_texture_size = true
		tex_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tex_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		tex_btn.pressed.connect(_show_unit_detail.bind(unit_inst))
		container.add_child(tex_btn)

		var name_label = Label.new()
		name_label.text = unit_data.get("name", "Unknown")
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 12)
		container.add_child(name_label)

		units_list_container.add_child(container)

func _show_unit_detail(unit_inst: Dictionary) -> void:
	UIManager.push("unit_detail_ui", {"unit_inst": unit_inst})
