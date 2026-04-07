extends Control

@onready var items_list_container = $VBoxContainer/ScrollContainer/ItemsListContainer

func _ready():
	DataManager.items_updated.connect(_on_items_updated)
	_refresh_items_list(DataManager.owned_items)

func _on_items_updated(items: Array):
	_refresh_items_list(items)

func _refresh_items_list(owned_items: Array) -> void:
	for child in items_list_container.get_children():
		child.queue_free()

	if owned_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items owned."
		items_list_container.add_child(empty_label)
		return

	for item in owned_items:
		if not item is Dictionary:
			continue

		var item_id = item.get("item_id", "")
		var item_data: Dictionary = DataManager.game_data_items.get(item_id, {})

		var hbox := HBoxContainer.new()
		items_list_container.add_child(hbox)

		var icon_name = item_data.get("icon", "")
		if icon_name != "":
			var tex_rect := TextureRect.new()
			var tex = load("res://assets/items/" + icon_name)
			if tex:
				tex_rect.texture = tex
				tex_rect.custom_minimum_size = Vector2(40, 40)
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			hbox.add_child(tex_rect)

		var label := Label.new()
		label.text = "%s x%d" % [item_data.get("name", "Unknown Item"), item.get("quantity", 0)]
		label.add_theme_font_size_override("font_size", 18)
		hbox.add_child(label)
