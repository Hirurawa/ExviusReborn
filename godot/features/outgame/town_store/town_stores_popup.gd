extends Control

signal close_requested
signal farewell_requested(pages: Array)

const ItemDisplayScript := preload("res://features/shared/item.gd")

@onready var title_label: Label = $Panel/VBoxContainer/Header/TitleLabel
@onready var back_button: Button = $Panel/VBoxContainer/Header/BackButton
@onready var close_button: Button = $Panel/VBoxContainer/Header/CloseButton
@onready var list_container: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/ListContainer
@onready var feedback_label: Label = $Panel/VBoxContainer/FeedbackLabel

var _current_town_id: String = ""
var _stores: Array = []
var _view: String = "stores"
var _selected_store_id: String = ""
var _selected_store_name: String = "Store"
var _opened_directly: bool = false
var _minimap: CanvasLayer = null
var _minimap_was_visible: bool = false
var _held_labels: Dictionary = {}

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	close_button.pressed.connect(_on_close_pressed)
	back_button.hide()
	feedback_label.text = ""
	InventoryService.purchase_successful.connect(_on_purchase_successful)
	InventoryService.purchase_failed.connect(_on_purchase_failed)
	InventoryService.sale_successful.connect(_on_sale_successful)
	InventoryService.sale_failed.connect(_on_sale_failed)
	_apply_panel_style()
	_hide_minimap()

func populate(town_id: String) -> void:
	_opened_directly = false
	_current_town_id = town_id
	_selected_store_id = ""
	back_button.hide()
	title_label.text = "Town Stores"

	_stores = GameDatabase.get_town_stores(town_id)
	_show_stores_list()

func open_store(town_id: String, store_id: int) -> void:
	populate(town_id)
	_opened_directly = true
	_show_store_actions(str(store_id))

func _show_stores_list() -> void:
	_view = "stores"
	back_button.hide()
	close_button.show()
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
		btn.pressed.connect(_show_store_actions.bind(str(store.get("storeId"))))
		list_container.add_child(btn)

func _show_store_actions(store_id: String) -> void:
	_view = "actions"
	_selected_store_id = store_id
	_selected_store_name = "Store"
	back_button.show()
	close_button.hide()
	var selected_store: Dictionary = {}
	for store in _stores:
		if str(store.get("storeId")) == store_id:
			selected_store = store
			_selected_store_name = str(store.get("name", "Store"))
			break
	title_label.text = _selected_store_name
	feedback_label.text = ""
	_clear_list()
	var greeting := GameDatabase.get_town_store_greeting(int(store_id))
	var dialogue_panel := PanelContainer.new()
	dialogue_panel.custom_minimum_size = Vector2(0, 200)
	dialogue_panel.add_theme_stylebox_override("panel", _texture_style("res://assets/ui/event/talk_window.tres", 18))
	var dialogue := VBoxContainer.new()
	dialogue.add_theme_constant_override("separation", 18)
	var owner := Label.new()
	owner.text = str(greeting.get("ownerName", selected_store.get("ownerName", "Shop Manager")))
	owner.add_theme_font_size_override("font_size", 22)
	var prompt := Label.new()
	var greeting_comment: Variant = greeting.get("comment")
	var greeting_text := str(greeting_comment) if greeting_comment != null else ""
	prompt.text = greeting_text if greeting_text != "" else "What can I do for you?"
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.add_theme_font_size_override("font_size", 26)
	dialogue.add_child(owner)
	dialogue.add_child(prompt)
	dialogue_panel.add_child(dialogue)
	list_container.add_child(dialogue_panel)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 160)
	list_container.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	for label in ["Buy Items", "Sell Items"]:
		var button := Button.new()
		button.tooltip_text = label
		button.icon = load("res://assets/ui/town/%s" % ("largebutton_label_buy_item.tres" if label == "Buy Items" else "largebutton_label_sell_item.tres"))
		button.custom_minimum_size = Vector2(0, 104)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		_style_primary_button(button)
		if label == "Buy Items":
			button.pressed.connect(_show_buy_items)
		else:
			button.pressed.connect(_show_sell_items)
		actions.add_child(button)
	list_container.add_child(actions)

func _show_buy_items() -> void:
	_view = "buy"
	back_button.show()
	title_label.text = "%s - Buy" % _selected_store_name
	feedback_label.text = ""
	_held_labels.clear()

	_clear_list()

	var items = GameDatabase.get_store_items(_selected_store_id)

	for store_item in items:
		var target_type = int(store_item.get("targetType", 0))
		var target_id = str(store_item.get("targetId", ""))

		var item_container = HBoxContainer.new()
		item_container.custom_minimum_size = Vector2(0, 124)

		var icon_rect = TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(96, 96)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_frame := PanelContainer.new()
		icon_frame.custom_minimum_size = Vector2(112, 112)
		icon_frame.add_theme_stylebox_override("panel", _texture_style(_item_frame_path(target_type), 12))
		icon_frame.add_child(icon_rect)

		var name_label = Label.new()
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		var category_icon := TextureRect.new()
		category_icon.custom_minimum_size = Vector2(30, 30)
		category_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		category_icon.hide()

		var info_box := VBoxContainer.new()
		info_box.custom_minimum_size = Vector2(105, 0)
		var held_label := Label.new()
		held_label.text = "Held 0"
		held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var price_line := HBoxContainer.new()
		price_line.alignment = BoxContainer.ALIGNMENT_END
		var coin_icon := TextureRect.new()
		coin_icon.custom_minimum_size = Vector2(26, 26)
		coin_icon.texture = load("res://assets/ui/common/icon_coin.tres")
		coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var price_label = Label.new()
		price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_line.add_child(coin_icon)
		price_line.add_child(price_label)
		info_box.add_child(held_label)
		info_box.add_child(price_line)

		var buy_button = Button.new()
		buy_button.tooltip_text = "Buy"
		buy_button.icon = load("res://assets/ui/town/middlebutton_label_buy_town.tres")
		buy_button.custom_minimum_size = Vector2(112, 80)
		buy_button.disabled = true
		_style_item_button(buy_button)

		if target_type == 20: # Item
			var item_data = GameDatabase.get_item(int(target_id))
			if typeof(item_data) == TYPE_DICTIONARY and not item_data.is_empty():
				name_label.text = item_data.get("name", "Unknown Item (" + target_id + ")")
				var price = int(item_data.get("priceBuy", 0))
				price_label.text = str(price)
				buy_button.disabled = false
				buy_button.pressed.connect(_request_buy.bind(target_id, 1, target_type))
				var icon_id = item_data.get("iconFile", "")
				if icon_id != "":
					var icon_path = "res://assets/items/%s" % icon_id
					if ResourceLoader.exists(icon_path):
						icon_rect.texture = load(icon_path)
			else:
				name_label.text = "Unknown Item (" + target_id + ")"
				price_label.text = ""
		elif target_type == 21: # Equipment
			var eq_data = GameDatabase.get_equipment(target_id)
			if typeof(eq_data) == TYPE_DICTIONARY and not eq_data.is_empty():
				name_label.text = eq_data.get("name", "Unknown Equipment (" + target_id + ")")
				var stat_summary := _equipment_stats(eq_data)
				if stat_summary != "":
					name_label.text += "\n" + stat_summary
				var badge_key := str(ItemDisplayScript.TYPE_BADGE_BY_ICON_NAME.get(str(eq_data.get("type_icon", "")), ""))
				var badge_path := "res://assets/ui/unit/equip_category_%s.tres" % badge_key
				if badge_key != "" and ResourceLoader.exists(badge_path):
					category_icon.texture = load(badge_path)
					category_icon.show()
				var price = int(eq_data.get("priceBuy", 0))
				price_label.text = str(price)
				buy_button.disabled = false
				buy_button.pressed.connect(_request_buy.bind(target_id, 1, target_type))
				var icon_id = eq_data.get("iconFile", "")
				if icon_id != "":
					var icon_path = "res://assets/equip/%s" % icon_id
					if ResourceLoader.exists(icon_path):
						icon_rect.texture = load(icon_path)
			else:
				name_label.text = "Unknown Equipment (" + target_id + ")"
				price_label.text = ""
		elif target_type == 22: # Materia
			var materia_data = GameDatabase.get_materia(int(target_id))
			if not materia_data.is_empty():
				name_label.text = str(materia_data.get("name", "Unknown Materia"))
				price_label.text = str(int(materia_data.get("priceBuy", 0)))
				buy_button.disabled = false
				buy_button.pressed.connect(_request_buy.bind(target_id, 1, target_type))
				var icon_file := str(materia_data.get("iconFile", ""))
				var icon_path := "res://assets/materia/%s" % icon_file
				if icon_file != "" and ResourceLoader.exists(icon_path):
					icon_rect.texture = load(icon_path)
			else:
				name_label.text = "Unknown Materia (" + target_id + ")"
		elif target_type == 40: # Star quartz - medal exchange
			name_label.text = "Star Quartz (" + target_id + ")"
			price_label.text = ""
		elif target_type == 41: # Vault item - store box
			name_label.text = "Vault Item (" + target_id + ")"
			price_label.text = ""
		elif target_type == 60: # Recipe
			name_label.text = "Recipe (" + target_id + ")"
			price_label.text = ""

		else:
			name_label.text = "Unknown Type %d (%s)" % [target_type, target_id]
			price_label.text = ""

		item_container.add_child(icon_frame)
		item_container.add_child(name_label)
		item_container.add_child(category_icon)
		item_container.add_child(info_box)
		item_container.add_child(buy_button)
		if target_type >= 20 and target_type <= 22:
			var held_key := "%d:%s" % [target_type, target_id]
			_held_labels[held_key] = held_label
			held_label.text = "Held %d" % _held_count(target_id, target_type)
		else:
			held_label.hide()
		if price_label.text == "":
			coin_icon.hide()
		var row_panel := PanelContainer.new()
		row_panel.add_theme_stylebox_override("panel", _texture_style("res://assets/ui/common/list_frame1.tres", 14))
		row_panel.add_child(item_container)
		list_container.add_child(row_panel)

func _show_sell_items() -> void:
	_view = "sell"
	back_button.show()
	title_label.text = "%s - Sell" % _selected_store_name
	feedback_label.text = ""
	_clear_list()
	var row_count: int = 0

	var stackables: Dictionary = InventoryService.owned_items.get("stackables", {})
	var item_ids: Array = stackables.keys()
	item_ids.sort()
	for item_id_value in item_ids:
		var item_id: String = str(item_id_value)
		var quantity: int = int(stackables.get(item_id_value, 0))
		var stack_data: Dictionary = GameDatabase.get_item(int(item_id))
		var stack_price: int = int(stack_data.get("priceSell", 0))
		if quantity <= 0 or stack_price <= 0:
			continue
		_add_sell_row(
			"%s x%d" % [str(stack_data.get("name", item_id)), quantity],
			stack_price,
			"res://assets/items/%s" % str(stack_data.get("iconFile", "")),
			item_id,
			20,
			""
		)
		row_count += 1

	for entry_value in InventoryService.owned_items.get("equipment", []):
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		if entry.get("equipped_to") != null and str(entry.get("equipped_to", "")) != "":
			continue
		var template_id: String = str(entry.get("template_id", ""))
		var item_type: int = 22 if str(entry.get("item_type", "")) == "MATERIA" else 21
		var equip_data: Dictionary = GameDatabase.get_materia(int(template_id)) if item_type == 22 else GameDatabase.get_equipment(template_id)
		if equip_data.is_empty() and item_type == 21:
			equip_data = GameDatabase.get_materia(int(template_id))
			item_type = 22 if not equip_data.is_empty() else 21
		var equip_price: int = int(equip_data.get("priceSell", equip_data.get("price_sell", 0)))
		if equip_data.is_empty() or equip_price <= 0:
			continue
		var icon_dir: String = "materia" if item_type == 22 else "equip"
		_add_sell_row(
			str(equip_data.get("name", template_id)),
			equip_price,
			"res://assets/%s/%s" % [icon_dir, str(equip_data.get("iconFile", ""))],
			template_id,
			item_type,
			str(entry.get("instance_id", ""))
		)
		row_count += 1

	if row_count == 0:
		var empty_label := Label.new()
		empty_label.text = "No sellable items."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_container.add_child(empty_label)

func _add_sell_row(name: String, price: int, icon_path: String, item_id: String, item_type: int, instance_id: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 40)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	var name_label := Label.new()
	name_label.text = name
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	var price_label := Label.new()
	price_label.text = "%d Gil" % price
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.custom_minimum_size = Vector2(80, 0)
	var sell_button := Button.new()
	sell_button.tooltip_text = "Sell"
	sell_button.icon = load("res://assets/ui/common/middlebutton_label_sell.tres")
	sell_button.custom_minimum_size = Vector2(112, 80)
	_style_item_button(sell_button)
	sell_button.pressed.connect(_request_sell.bind(item_id, item_type, instance_id))
	for child in [icon, name_label, price_label, sell_button]:
		row.add_child(child)
	list_container.add_child(row)

func _clear_list() -> void:
	for child in list_container.get_children():
		child.queue_free()

func _on_back_pressed() -> void:
	if _view == "buy" or _view == "sell":
		_show_store_actions(_selected_store_id)
	elif _view == "actions":
		if _opened_directly:
			var farewell := GameDatabase.get_town_store_greeting(int(_selected_store_id), 3)
			var farewell_comment: Variant = farewell.get("comment")
			var farewell_text := str(farewell_comment) if farewell_comment != null else ""
			farewell_requested.emit([{
				"speaker": str(farewell.get("ownerName", _selected_store_name)),
				"body": farewell_text if farewell_text != "" else "Come back anytime!",
			}])
			_on_close_pressed()
		else:
			_show_stores_list()

func _on_close_pressed() -> void:
	_restore_minimap()
	close_requested.emit()
	queue_free()


func _request_buy(item_id: String, quantity: int, item_type: int) -> void:
	feedback_label.text = ""
	InventoryService.request_buy_item(item_id, quantity, item_type)

func _request_sell(item_id: String, item_type: int, instance_id: String) -> void:
	feedback_label.text = ""
	InventoryService.request_sell_item(item_id, item_type, instance_id)

func _on_purchase_successful() -> void:
	_refresh_held_counts()
	feedback_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
	feedback_label.text = "Item purchased successfully!"

func _on_purchase_failed(error_message: String) -> void:
	feedback_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
	if error_message == "ERR_INSUFFICIENT_RESOURCES":
		feedback_label.text = "Not enough gil to purchase this item."
	else:
		feedback_label.text = "Purchase failed: " + error_message

func _on_sale_successful() -> void:
	_show_sell_items()
	feedback_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
	feedback_label.text = "Item sold successfully!"

func _on_sale_failed(error_message: String) -> void:
	feedback_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
	feedback_label.text = "Sale failed: " + error_message


func _apply_panel_style() -> void:
	$Panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_stylebox_override("normal", _texture_style("res://assets/ui/common/pagetitlebg.tres", 12))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for button in [back_button, close_button]:
		_style_header_button(button)


func _style_primary_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_stylebox_override("normal", _texture_style("res://assets/ui/common/button_large1.tres", 24))
	button.add_theme_stylebox_override("hover", _texture_style("res://assets/ui/common/button_large2.tres", 24))
	button.add_theme_stylebox_override("pressed", _texture_style("res://assets/ui/common/button_large2.tres", 24))


func _style_header_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_stylebox_override("normal", _texture_style("res://assets/ui/common/commonR_btnM_bg-blue-off.tres", 20))
	button.add_theme_stylebox_override("hover", _texture_style("res://assets/ui/common/commonR_btnM_bg-blue-on.tres", 20))
	button.add_theme_stylebox_override("pressed", _texture_style("res://assets/ui/common/commonR_btnM_bg-blue-on.tres", 20))


func _style_item_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", _texture_style("res://assets/ui/common/button_middle1.tres", 18))
	button.add_theme_stylebox_override("hover", _texture_style("res://assets/ui/common/button_middle2.tres", 18))
	button.add_theme_stylebox_override("pressed", _texture_style("res://assets/ui/common/button_middle2.tres", 18))


func _texture_style(path: String, margin: float) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(path)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, margin)
		style.set_content_margin(side, 10)
	return style


func _hide_minimap() -> void:
	_minimap = get_tree().get_first_node_in_group("minimap") as CanvasLayer
	if _minimap != null:
		_minimap_was_visible = _minimap.visible
		_minimap.hide()


func _restore_minimap() -> void:
	if _minimap != null and is_instance_valid(_minimap):
		_minimap.visible = _minimap_was_visible
	_minimap = null


func _exit_tree() -> void:
	_restore_minimap()


func _held_count(item_id: String, item_type: int) -> int:
	if item_type == 20:
		return int(InventoryService.owned_items.get("stackables", {}).get(item_id, 0))
	var count := 0
	for entry in InventoryService.owned_items.get("equipment", []):
		if entry is Dictionary and str(entry.get("template_id", "")) == item_id:
			count += 1
	return count


func _refresh_held_counts() -> void:
	for key_value in _held_labels:
		var key := str(key_value)
		var parts := key.split(":", true, 1)
		var label := _held_labels[key] as Label
		if parts.size() == 2 and is_instance_valid(label):
			label.text = "Held %d" % _held_count(parts[1], int(parts[0]))


func _item_frame_path(item_type: int) -> String:
	match item_type:
		20:
			return "res://assets/ui/item/item_frame_1.tres"
		21:
			return "res://assets/ui/item/item_frame_3.tres"
		22:
			return "res://assets/ui/item/item_frame_4.tres"
		_:
			return "res://assets/ui/item/item_frame_0.tres"


func _equipment_stats(data: Dictionary) -> String:
	var parts: Array[String] = []
	var stats: Dictionary = data.get("stats", data)
	for stat in ["atk", "def", "mag", "spr", "hp", "mp"]:
		var value := int(stats.get(stat, stats.get(stat.to_upper(), 0)))
		if value != 0:
			parts.append("%s %+d" % [stat.to_upper(), value])
	return "  ".join(parts)
