import re

with open('godot/demo.gd', 'r') as f:
    content = f.read()

# We can see the unit ID matches the illustration filename `unit_ills_{unit_id}.png`.
# Some units might end in 2 but the illustration might end differently if it has multiple rarities?
# Actually, the unit ID itself is the key, e.g. "100000102". Let's check if `unit_ills_100000102.png` exists.
# We will just try `res://assets/unit_illustrations/unit_ills_%s.png` % unit_id.
# If it fails to load, maybe just use a placeholder or something.

new_refresh_units = '''func _refresh_units_list() -> void:
	for child in units_list_container.get_children():
		units_list_container.remove_child(child)
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
		var unit_data: Dictionary = game_data_units.get(unit_id, {})

		var container = VBoxContainer.new()
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.alignment = BoxContainer.ALIGNMENT_CENTER

		var tex_btn = TextureButton.new()
		var img_path = "res://assets/unit_illustrations/unit_ills_%s.png" % unit_id
		var tex = load(img_path)
		if tex:
			tex_btn.texture_normal = tex

		# Set size properties
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

		units_list_container.add_child(container)'''

content = re.sub(
    r'func _refresh_units_list\(\) -> void:.*?units_list_container\.add_child\(grid_item\)',
    new_refresh_units,
    content,
    flags=re.DOTALL
)

with open('godot/demo.gd', 'w') as f:
    f.write(content)
