extends Control

@onready var items_list_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/ItemsListContainer
@onready var equipment_list_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/EquipmentListContainer

var _texture_cache: Dictionary = {}

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _ready() -> void:
	DataManager.items_updated.connect(_on_items_updated)
	_refresh_items_list(DataManager.owned_items)

func _on_items_updated(items: Dictionary) -> void:
	_refresh_items_list(items)

func _refresh_items_list(owned_items: Dictionary) -> void:
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

	var has_items: bool = false
	var has_equipment: bool = false

	# Format for owned_items is: {"stackables": {"item_id": count}, "equipment": [{"instance_id": x, "template_id": x}]}

	# Process stackables
	var stackables: Dictionary = owned_items.get("stackables", {})
	for item_id in stackables.keys():
		var quantity: int = stackables[item_id]

		# Determine if it's an item, equipment, or weapon
		var is_item: bool = DataManager.game_data_items.has(item_id)
		var is_equipment: bool = DataManager.game_data_equipment.has(item_id)

		var item_data: Dictionary = {}
		var container_to_use: VBoxContainer = null

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

		var icon_name: String = item_data.get("icon", "")
		if icon_name != "":
			var tex_rect := TextureRect.new()
			var tex: Texture2D = null
			if is_item:
				tex = _get_dynamic_texture("res://assets/items/" + icon_name) if ResourceLoader.exists("res://assets/items/" + icon_name) else null
			elif is_equipment:
				tex = _get_dynamic_texture("res://assets/equip/" + icon_name) if ResourceLoader.exists("res://assets/equip/" + icon_name) else null

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

	# Process equipment
	var equipment_arr: Array = owned_items.get("equipment", [])
	for equip in equipment_arr:
		if not equip is Dictionary:
			continue

		var item_id: String = equip.get("template_id", "")
		var quantity: int = 1 # Equipment is individual, count is 1
		
		# Determine if it's an item, equipment, or weapon
		var is_item: bool = DataManager.game_data_items.has(item_id)
		var is_equipment: bool = DataManager.game_data_equipment.has(item_id)
		
		var item_data: Dictionary = {}
		var container_to_use: VBoxContainer = null
		
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

		var icon_name: String = item_data.get("icon", "")
		if icon_name != "":
			var tex_rect := TextureRect.new()
			var tex: Texture2D = null
			if is_item:
				tex = _get_dynamic_texture("res://assets/items/" + icon_name) if ResourceLoader.exists("res://assets/items/" + icon_name) else null
			elif is_equipment:
				tex = _get_dynamic_texture("res://assets/equip/" + icon_name) if ResourceLoader.exists("res://assets/equip/" + icon_name) else null
				
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
