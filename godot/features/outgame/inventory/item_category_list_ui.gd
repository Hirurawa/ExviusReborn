extends Control

const ItemScene: PackedScene = preload("res://features/shared/Item.tscn")
const ITEMS_ICON_BASE_PATH: String = "res://assets/items/"
const MATERIA_ICON_BASE_PATH: String = "res://assets/abilities/"

@onready var item_grid: GridContainer = $ItemsScroll/ItemGrid
@onready var items_scroll: ScrollContainer = $ItemsScroll
@onready var back_button: TextureButton = $UnitNamebgChara2/BackButton
@onready var title_label: Label = $UnitNamebgChara2/Title

var current_category_key: String = "items"
var _is_combat_selection_mode: bool = false
var _combat_slot_index: int = -1

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	if not InventoryService.items_updated.is_connected(_on_items_updated):
		InventoryService.items_updated.connect(_on_items_updated)
	_sync_grid_width()
	_refresh_items_grid(InventoryService.owned_items)

func _exit_tree() -> void:
	if InventoryService.items_updated.is_connected(_on_items_updated):
		InventoryService.items_updated.disconnect(_on_items_updated)

func init_scene(params: Dictionary) -> void:
	current_category_key = str(params.get("category", "items"))
	var mode_key: String = str(params.get("mode", ""))
	_is_combat_selection_mode = mode_key == "select_combat"
	_combat_slot_index = int(params.get("slot_index", -1))
	if _is_combat_selection_mode:
		current_category_key = "items"
	if is_node_ready():
		_apply_category_title()
		_refresh_items_grid(InventoryService.owned_items)

func _on_back_pressed() -> void:
	UIManager.pop()

func _on_items_updated(items: Dictionary) -> void:
	_refresh_items_grid(items)

func _refresh_items_grid(owned_items: Dictionary) -> void:
	if not is_node_ready():
		await ready

	_apply_category_title()
	_sync_grid_width()

	for child in item_grid.get_children():
		child.queue_free()

	var entries: Array[Dictionary] = _build_entries_for_category(owned_items, current_category_key)
	if entries.is_empty():
		_add_empty_category_cell(current_category_key)
		return

	for entry in entries:
		_add_entry_cell(entry)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_sync_grid_width()

func _sync_grid_width() -> void:
	var viewport_width: float = max(items_scroll.size.x, 1.0)
	item_grid.custom_minimum_size = Vector2(viewport_width, item_grid.custom_minimum_size.y)

func _build_entries_for_category(owned_items: Dictionary, category_key: String) -> Array[Dictionary]:
	if owned_items.is_empty():
		return []

	var entries: Array[Dictionary] = []

	if category_key == "equipment":
		var equipment_arr: Array = owned_items.get("equipment", [])
		for equipment_entry in equipment_arr:
			if not (equipment_entry is Dictionary):
				continue

			var equipment_dict: Dictionary = equipment_entry as Dictionary
			var template_id: String = str(equipment_dict.get("template_id", ""))
			if template_id == "" or not StaticData.game_data_equipment.has(template_id):
				continue

			var equipment_data: Dictionary = StaticData.game_data_equipment.get(template_id, {})
			entries.append({
				"kind": "equipment",
				"data": equipment_data,
				"quantity": 1,
				"sort_name": str(equipment_data.get("name", "Unknown Equipment")),
				"sort_id": str(equipment_dict.get("instance_id", template_id))
			})
	else:
		var stackables: Dictionary = owned_items.get("stackables", {})
		for item_id_variant in stackables.keys():
			var item_id: String = str(item_id_variant)
			var quantity: int = int(stackables[item_id_variant])
			if quantity <= 0:
				continue
			if not StaticData.game_data_items.has(item_id):
				continue

			var item_data: Dictionary = StaticData.game_data_items.get(item_id, {})
			var item_type: String = str(item_data.get("type", ""))
			var is_consumable: bool = item_type == "Consumable"
			if _is_combat_selection_mode and (item_data.get("usable_in_combat", false) != true or not item_data.has("effects_raw")):
				continue
			if _is_combat_selection_mode and _is_item_already_selected_in_combat(item_id):
				continue
			if category_key == "items" and not is_consumable:
				continue
			if category_key == "materials" and is_consumable:
				continue
			if category_key != "items" and category_key != "materials":
				continue

			entries.append({
				"kind": "stackable",
				"item_id": item_id,
				"data": item_data,
				"quantity": quantity,
				"sort_name": str(item_data.get("name", "Unknown Item")),
				"sort_id": item_id
			})

		if category_key == "abilities":
			var equipment_arr: Array = owned_items.get("equipment", [])
			for eq_entry: Variant in equipment_arr:
				if not (eq_entry is Dictionary):
					continue
				var eq_dict: Dictionary = eq_entry as Dictionary
				if str(eq_dict.get("item_type", "")) != "MATERIA":
					continue
				var template_id: String = str(eq_dict.get("template_id", ""))
				if template_id == "" or not StaticData.game_data_materia.has(template_id):
					continue
				var materia_data: Dictionary = StaticData.game_data_materia.get(template_id, {})
				entries.append({
					"kind": "materia",
					"data": materia_data,
					"quantity": 1,
					"sort_name": str(materia_data.get("name", "Unknown Materia")),
					"sort_id": str(eq_dict.get("instance_id", template_id))
				})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_name: String = str(a.get("sort_name", "")).to_lower()
		var b_name: String = str(b.get("sort_name", "")).to_lower()
		if a_name == b_name:
			return str(a.get("sort_id", "")) < str(b.get("sort_id", ""))
		return a_name < b_name
	)

	return entries

func _add_entry_cell(entry: Dictionary) -> void:
	var item_cell: Control = ItemScene.instantiate()
	item_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_grid.add_child(item_cell)

	var kind: String = str(entry.get("kind", ""))
	var item_data: Dictionary = entry.get("data", {})
	if kind == "equipment":
		item_cell.setup_from_item_data(item_data, {"show_quantity": false, "show_slot_badge": false})
	elif kind == "materia":
		var icon_name: String = str(item_data.get("icon", ""))
		var icon_path: String = ""
		if icon_name != "":
			icon_path = MATERIA_ICON_BASE_PATH + icon_name
		if not ResourceLoader.exists(icon_path):
			icon_path = ""
		var detail_text: String = ""
		var effects: Array = item_data.get("effects", [])
		if not effects.is_empty():
			detail_text = str(effects[0])
		else:
			detail_text = _resolve_item_detail_text(item_data)
		item_cell.setup_placeholder(
			str(item_data.get("name", "Unknown Materia")),
			detail_text,
			{"icon_path": icon_path, "quantity": 1}
		)
	else:
		var icon_name: String = str(item_data.get("icon", ""))
		var icon_path: String = ""
		if icon_name != "":
			icon_path = ITEMS_ICON_BASE_PATH + icon_name
		if not ResourceLoader.exists(icon_path):
			icon_path = ""

		item_cell.setup_placeholder(
			str(item_data.get("name", "Unknown Item")),
			_resolve_item_detail_text(item_data),
			{
				"icon_path": icon_path,
				"quantity": int(entry.get("quantity", 0))
			}
		)

	if _is_combat_selection_mode and kind == "stackable":
		item_cell.set_clickable(true)
		var selected_item_id: String = str(entry.get("item_id", ""))
		item_cell.pressed.connect(_on_combat_item_selected.bind(selected_item_id))
	else:
		item_cell.set_clickable(false)

func _add_empty_category_cell(category_key: String) -> void:
	var item_cell: Control = ItemScene.instantiate()
	item_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_grid.add_child(item_cell)
	item_cell.setup_placeholder(_get_category_title(category_key), _get_empty_message(category_key))
	item_cell.set_clickable(false)

func _resolve_item_detail_text(item_data: Dictionary) -> String:
	var strings_value: Variant = item_data.get("strings", {})
	if strings_value is Dictionary:
		var strings: Dictionary = strings_value as Dictionary
		var short_desc_value: Variant = strings.get("desc_short", [])
		if short_desc_value is Array:
			var short_desc: Array = short_desc_value as Array
			if not short_desc.is_empty():
				return str(short_desc[0])

	var type_text: String = str(item_data.get("type", ""))
	if type_text != "":
		return type_text

	return "No description."

func _apply_category_title() -> void:
	if _is_combat_selection_mode:
		title_label.text = "Select Combat Item"
		return
	title_label.text = _get_category_title(current_category_key)

func _on_combat_item_selected(item_id: String) -> void:
	if not _is_combat_selection_mode:
		return
	if _combat_slot_index < 0:
		return
	CombatItemsService.set_combat_item(_combat_slot_index, item_id)
	UIManager.pop()

func _is_item_already_selected_in_combat(item_id: String) -> bool:
	var selected_slots: Array = CombatItemsService.combat_items
	for slot_value in selected_slots:
		if str(slot_value) == item_id:
			return true
	return false

func _get_category_title(category_key: String) -> String:
	match category_key:
		"items":
			return "Items"
		"materials":
			return "Materials"
		"equipment":
			return "Equipment"
		"abilities":
			return "Abilities"
		"vision_card":
			return "Vision Card"
		"craft":
			return "Craft"
		_:
			return "Inventory"

func _get_empty_message(category_key: String) -> String:
	match category_key:
		"items":
			return "No consumable items owned."
		"materials":
			return "No materials owned."
		"equipment":
			return "No equipment owned."
		"abilities":
			return "No materia owned."
		"vision_card":
			return "Vision card inventory is not wired yet."
		"craft":
			return "Craft inventory is not wired yet."
		_:
			return "No entries available."
