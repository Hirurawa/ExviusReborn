extends Control

enum ItemCategory {
	ITEMS,
	MATERIALS,
	EQUIPMENT,
	ABILITIES,
	VISION_CARD,
	CRAFT
}

const ITEMS_ICON_BASE_PATH: String = "res://assets/items/"
const COMBAT_SLOT_COUNT: int = 10

@onready var items_button: TextureButton = $Items
@onready var materials_button: TextureButton = $Materials
@onready var equipment_button: TextureButton = $Equipment
@onready var abilities_button: TextureButton = $Abilities
@onready var vision_card_button: TextureButton = $VisionCard
@onready var craft_button: TextureButton = $Craft
@onready var reset_button: TextureButton = $btn_reset

@onready var _frame_buttons: Array[TextureButton] = [
	$item_bg/item_frame1,
	$item_bg/item_frame2,
	$item_bg/item_frame3,
	$item_bg/item_frame4,
	$item_bg/item_frame5,
	$item_bg/item_frame6,
	$item_bg/item_frame7,
	$item_bg/item_frame8,
	$item_bg/item_frame9,
	$item_bg/item_frame10
]

@onready var _frame_icons: Array[TextureRect] = [
	$item_bg/item_frame1/ItemIcon,
	$item_bg/item_frame2/ItemIcon,
	$item_bg/item_frame3/ItemIcon,
	$item_bg/item_frame4/ItemIcon,
	$item_bg/item_frame5/ItemIcon,
	$item_bg/item_frame6/ItemIcon,
	$item_bg/item_frame7/ItemIcon,
	$item_bg/item_frame8/ItemIcon,
	$item_bg/item_frame9/ItemIcon,
	$item_bg/item_frame10/ItemIcon
]

func _ready() -> void:
	items_button.pressed.connect(_on_category_button_pressed.bind(ItemCategory.ITEMS))
	materials_button.pressed.connect(_on_category_button_pressed.bind(ItemCategory.MATERIALS))
	equipment_button.pressed.connect(_on_category_button_pressed.bind(ItemCategory.EQUIPMENT))
	abilities_button.pressed.connect(_on_category_button_pressed.bind(ItemCategory.ABILITIES))
	vision_card_button.pressed.connect(_on_category_button_pressed.bind(ItemCategory.VISION_CARD))
	craft_button.pressed.connect(_on_category_button_pressed.bind(ItemCategory.CRAFT))
	reset_button.pressed.connect(_on_reset_pressed)

	for i in range(min(COMBAT_SLOT_COUNT, _frame_buttons.size())):
		_frame_buttons[i].pressed.connect(_on_item_frame_pressed.bind(i))

	if not DataManager.combat_items_updated.is_connected(_on_combat_items_updated):
		DataManager.combat_items_updated.connect(_on_combat_items_updated)
	if not DataManager.items_updated.is_connected(_on_items_updated):
		DataManager.items_updated.connect(_on_items_updated)

	_refresh_slot_icons()

func _exit_tree() -> void:
	if DataManager.combat_items_updated.is_connected(_on_combat_items_updated):
		DataManager.combat_items_updated.disconnect(_on_combat_items_updated)
	if DataManager.items_updated.is_connected(_on_items_updated):
		DataManager.items_updated.disconnect(_on_items_updated)

func _on_category_button_pressed(category: ItemCategory) -> void:
	UIManager.push("item_category_list_ui", {"category": _get_category_key(category)})

func _on_item_frame_pressed(slot_index: int) -> void:
	UIManager.push("item_category_list_ui", {
		"category": "items",
		"mode": "select_combat",
		"slot_index": slot_index
	})

func _on_reset_pressed() -> void:
	DataManager.clear_all_combat_items()

func _on_combat_items_updated(slots: Array) -> void:
	_refresh_slot_icons(slots)

func _on_items_updated(_items: Dictionary) -> void:
	_refresh_slot_icons()

func _refresh_slot_icons(slots: Array = []) -> void:
	var selected_slots: Array = slots if not slots.is_empty() else DataManager.combat_items
	var stackables: Dictionary = DataManager.owned_items.get("stackables", {})

	for i in range(min(COMBAT_SLOT_COUNT, _frame_icons.size())):
		var icon_rect: TextureRect = _frame_icons[i]
		icon_rect.texture = null
		icon_rect.hide()

		if i >= selected_slots.size():
			continue

		var item_id: String = str(selected_slots[i])
		if item_id == "":
			continue
		if int(stackables.get(item_id, 0)) <= 0:
			continue
		if not DataManager.game_data_items.has(item_id):
			continue

		var item_data: Dictionary = DataManager.game_data_items.get(item_id, {})
		var icon_name: String = str(item_data.get("icon", ""))
		if icon_name == "":
			continue

		var icon_path: String = ITEMS_ICON_BASE_PATH + icon_name
		if not ResourceLoader.exists(icon_path):
			continue

		var icon_texture: Texture2D = ResourceLoader.load(icon_path) as Texture2D
		if icon_texture == null:
			continue

		icon_rect.texture = icon_texture
		icon_rect.show()

func _get_category_key(category: ItemCategory) -> String:
	match category:
		ItemCategory.ITEMS:
			return "items"
		ItemCategory.MATERIALS:
			return "materials"
		ItemCategory.EQUIPMENT:
			return "equipment"
		ItemCategory.ABILITIES:
			return "abilities"
		ItemCategory.VISION_CARD:
			return "vision_card"
		ItemCategory.CRAFT:
			return "craft"
		_:
			return "items"
