extends Control

signal close_requested

@onready var title_label: Label = $Panel/VBoxContainer/Header/TitleLabel
@onready var back_button: Button = $Panel/VBoxContainer/Header/BackButton
@onready var close_button: Button = $Panel/VBoxContainer/Header/CloseButton
@onready var list_container: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/ListContainer

var _current_town_id: String = ""
var _stores: Array = []
var _viewing_items: bool = false

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	close_button.pressed.connect(_on_close_pressed)
	back_button.hide()

func populate(town_id: String) -> void:
	_current_town_id = town_id
	_viewing_items = false
	back_button.hide()
	title_label.text = "Town Stores"

	_stores = GameDatabase.get_town_stores(town_id)
	_show_stores_list()

func _show_stores_list() -> void:
	_viewing_items = false
	back_button.hide()
	title_label.text = "Town Stores"

	_clear_list()

	for store in _stores:
		var btn = Button.new()
		var store_name = str(store.get("name", "Unknown Store"))
		var owner_name = str(store.get("ownerName", ""))
		if owner_name != "":
			store_name += " (" + owner_name + ")"
		btn.text = store_name
		btn.custom_minimum_size = Vector2(0, 50)
		btn.pressed.connect(_on_store_clicked.bind(str(store.get("storeId"))))
		list_container.add_child(btn)

func _on_store_clicked(store_id: String) -> void:
	_viewing_items = true
	back_button.show()

	# Find store name for title
	for store in _stores:
		if str(store.get("storeId")) == store_id:
			title_label.text = str(store.get("name", "Store Items"))
			break

	_clear_list()

	var items = GameDatabase.get_store_items(store_id)

	for store_item in items:
		var target_type = int(store_item.get("targetType", 0))
		var target_id = str(store_item.get("targetId", ""))

		var item_container = HBoxContainer.new()
		item_container.custom_minimum_size = Vector2(0, 40)

		var icon_rect = TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(40, 40)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var name_label = Label.new()
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL

		if target_type == 20: # Item
			var item_data = GameDatabase.get_item(target_id)
			if typeof(item_data) == TYPE_DICTIONARY and not item_data.is_empty():
				name_label.text = item_data.get("name", "Unknown Item (" + target_id + ")")
				var icon_id = item_data.get("icon", "")
				if icon_id != "":
					var icon_path = "res://assets/items/%s.png" % icon_id
					if ResourceLoader.exists(icon_path):
						icon_rect.texture = load(icon_path)
			else:
				name_label.text = "Unknown Item (" + target_id + ")"
		elif target_type == 21: # Equipment
			var eq_data = GameDatabase.get_equipment(target_id)
			if typeof(eq_data) == TYPE_DICTIONARY and not eq_data.is_empty():
				name_label.text = eq_data.get("name", "Unknown Equipment (" + target_id + ")")
				var icon_id = eq_data.get("icon", "")
				if icon_id != "":
					var icon_path = "res://assets/items/%s.png" % icon_id
					if ResourceLoader.exists(icon_path):
						icon_rect.texture = load(icon_path)
			else:
				name_label.text = "Unknown Equipment (" + target_id + ")"
		elif target_type == 60: # Recipe
			name_label.text = "Recipe (" + target_id + ")"
		elif target_type == 22: # Materia
			name_label.text = "Materia (" + target_id + ")"
		else:
			name_label.text = "Unknown Type %d (%s)" % [target_type, target_id]

		item_container.add_child(icon_rect)
		item_container.add_child(name_label)

		list_container.add_child(item_container)

func _clear_list() -> void:
	for child in list_container.get_children():
		child.queue_free()

func _on_back_pressed() -> void:
	if _viewing_items:
		_show_stores_list()

func _on_close_pressed() -> void:
	close_requested.emit()
	queue_free()
