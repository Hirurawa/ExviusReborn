extends Control

@onready var items_list_container = $VBoxContainer/ScrollContainer/VBoxContainer/ItemsListContainer
@onready var equipment_list_container = $VBoxContainer/ScrollContainer/VBoxContainer/EquipmentListContainer

func _ready():
	DataManager.items_updated.connect(_on_items_updated)
	_refresh_items_list(DataManager.owned_items)

func _on_items_updated(items: Array):
	_refresh_items_list(items)

func _refresh_items_list(owned_items: Array) -> void:
	for child in items_list_container.get_children():
		child.queue_free()
	for child in equipment_list_container.get_children():
		child.queue_free()

	if owned_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items owned."
		items_list_container.add_child(empty_label)
		
		var empty_equip := Label.new()
		empty_equip.text = "No equipment owned."
		equipment_list_container.add_child(empty_equip)
		return

	var has_items = false
	var has_equipment = false

	for item in owned_items:
		if not item is Dictionary:
			continue

		var item_id = item.get("item_id", "")
		var quantity = item.get("quantity", 0)
		
		# Determine if it's an item, equipment, or weapon
		var is_item = DataManager.game_data_items.has(item_id)
		var is_equipment = DataManager.game_data_equipment.has(item_id)
		
		var item_data: Dictionary = {}
		var container_to_use = null
		
		if is_item:
			item_data = DataManager.game_data_items.get(item_id, {})
			container_to_use = items_list_container
			has_items = true
		elif is_equipment:
			item_data = DataManager.game_data_equipment.get(item_id, {})
			container_to_use = equipment_list_container
			has_equipment = true

		if item_data.is_empty() or container_to_use == null:
			continue

		var hbox := HBoxContainer.new()
		container_to_use.add_child(hbox)

		var icon_name = item_data.get("icon", "")
		if icon_name != "":
			var tex_rect := TextureRect.new()
			var tex = null
			if is_item:
				tex = ResourceLoader.load("res://assets/items/" + icon_name) if ResourceLoader.exists("res://assets/items/" + icon_name) else null
			elif is_equipment:
				tex = ResourceLoader.load("res://assets/equip/" + icon_name) if ResourceLoader.exists("res://assets/equip/" + icon_name) else null
				
			if tex:
				tex_rect.texture = tex
				tex_rect.custom_minimum_size = Vector2(40, 40)
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			hbox.add_child(tex_rect)

		var label := Label.new()
		label.text = "%s x%d" % [item_data.get("name", "Unknown Item"), quantity]
		label.add_theme_font_size_override("font_size", 18)
		hbox.add_child(label)
		
	if not has_items:
		var empty_label := Label.new()
		empty_label.text = "No items owned."
		items_list_container.add_child(empty_label)

	if not has_equipment:
		var empty_label := Label.new()
		empty_label.text = "No equipment owned."
		equipment_list_container.add_child(empty_label)
