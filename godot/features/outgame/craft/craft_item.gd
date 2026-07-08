extends Control

enum Tab { RECOVERY, STRECOVERY, SUPPORT, ATTACK, OTHER }

@onready var back_button: TextureButton = $CrePrepareTitle/BackButton
@onready var recovery_tab_button: TextureButton = $TabBar/craft_recipe_type_recovery
@onready var strecovery_tab_button: TextureButton = $TabBar/craft_recipe_type_strecovery
@onready var support_tab_button: TextureButton = $TabBar/craft_recipe_type_support
@onready var attack_tab_button: TextureButton = $TabBar/craft_recipe_type_attack
@onready var other_tab_button: TextureButton = $TabBar/craft_recipe_type_other
@onready var list_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/ListContainer

var _current_tab: int = Tab.RECOVERY

const TAB_TEXTURE_INACTIVE: Texture2D = preload("res://assets/ui/create/cre_btn5_1.tres")
const TAB_TEXTURE_ACTIVE: Texture2D = preload("res://assets/ui/create/cre_btn5_2.tres")

@onready var craft_row_template: PackedScene = preload("res://features/outgame/craft/CraftRow.tscn")

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	recovery_tab_button.pressed.connect(_select_tab.bind(Tab.RECOVERY))
	strecovery_tab_button.pressed.connect(_select_tab.bind(Tab.STRECOVERY))
	support_tab_button.pressed.connect(_select_tab.bind(Tab.SUPPORT))
	attack_tab_button.pressed.connect(_select_tab.bind(Tab.ATTACK))
	other_tab_button.pressed.connect(_select_tab.bind(Tab.OTHER))
	_select_tab(Tab.RECOVERY)

func _select_tab(tab: int) -> void:
	_current_tab = tab
	_refresh_tab_button_textures()
	_populate_for_current_tab()

func _refresh_tab_button_textures() -> void:
	var active: TextureButton = _active_tab_button()
	for button in [recovery_tab_button, strecovery_tab_button, support_tab_button, attack_tab_button, other_tab_button]:
		var is_active: bool = button == active
		button.texture_normal = TAB_TEXTURE_ACTIVE if is_active else TAB_TEXTURE_INACTIVE
		button.texture_focused = button.texture_normal
		button.texture_hover = button.texture_normal
		button.texture_pressed = button.texture_normal

func _active_tab_button() -> TextureButton:
	match _current_tab:
		Tab.RECOVERY:
			return recovery_tab_button
		Tab.STRECOVERY:
			return strecovery_tab_button
		Tab.SUPPORT:
			return support_tab_button
		Tab.ATTACK:
			return attack_tab_button
		Tab.OTHER:
			return other_tab_button
		_:
			return recovery_tab_button

func _populate_for_current_tab() -> void:
	match _current_tab:
		Tab.RECOVERY:
			_populate_shop(GameDatabase.get_item_recipes(1))
		Tab.STRECOVERY:
			_populate_shop(GameDatabase.get_item_recipes(2))
		Tab.SUPPORT:
			_populate_shop(GameDatabase.get_item_recipes(3))
		Tab.ATTACK:
			_populate_shop(GameDatabase.get_item_recipes(4))
		Tab.OTHER:
			_populate_shop(GameDatabase.get_item_recipes(5))

func _populate_shop(data: Array) -> void:
	for child in list_container.get_children():
		child.queue_free()

	var matched_count: int = 0
	for item in data:
		var row = craft_row_template.instantiate()
		list_container.add_child(row)
		row.setup(item)
		row.craft_requested.connect(_on_craft_requested)
		matched_count += 1
		
	if matched_count == 0 :
		var empty_label := Label.new()
		empty_label.text = "No recipes."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list_container.add_child(empty_label)

func _on_craft_requested(id: String, quantity: int) -> void:
	InventoryService.request_craft_item(id, quantity)

func _on_back_button_pressed() -> void:
	UIManager.pop()
