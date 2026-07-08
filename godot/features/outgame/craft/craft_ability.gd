extends Control

enum Tab { BLACK, WHITE, GREEN, SPECIAL }

@onready var back_button: TextureButton = $CreAbilityTitle/BackButton
@onready var black_tab_button: TextureButton = $TabBar/craft_recipe_type_black_magic
@onready var white_tab_button: TextureButton = $TabBar/craft_recipe_type_white_magic
@onready var green_tab_button: TextureButton = $TabBar/craft_recipe_type_green_magic
@onready var special_tab_button: TextureButton = $TabBar/craft_recipe_type_spcial
@onready var list_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/ListContainer

var _current_tab: int = Tab.BLACK

const TAB_TEXTURE_INACTIVE: Texture2D = preload("res://assets/ui/create/cre_btn4_1.tres")
const TAB_TEXTURE_ACTIVE: Texture2D = preload("res://assets/ui/create/cre_btn4_2.tres")

@onready var craft_row_template: PackedScene = preload("res://features/outgame/craft/CraftRow.tscn")

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	black_tab_button.pressed.connect(_select_tab.bind(Tab.BLACK))
	white_tab_button.pressed.connect(_select_tab.bind(Tab.WHITE))
	green_tab_button.pressed.connect(_select_tab.bind(Tab.GREEN))
	special_tab_button.pressed.connect(_select_tab.bind(Tab.SPECIAL))
	_select_tab(Tab.BLACK)

func _select_tab(tab: int) -> void:
	_current_tab = tab
	_refresh_tab_button_textures()
	_populate_for_current_tab()

func _refresh_tab_button_textures() -> void:
	var active: TextureButton = _active_tab_button()
	for button in [black_tab_button, white_tab_button, green_tab_button, special_tab_button]:
		var is_active: bool = button == active
		button.texture_normal = TAB_TEXTURE_ACTIVE if is_active else TAB_TEXTURE_INACTIVE
		button.texture_focused = button.texture_normal
		button.texture_hover = button.texture_normal
		button.texture_pressed = button.texture_normal

func _active_tab_button() -> TextureButton:
	match _current_tab:
		Tab.BLACK:
			return black_tab_button
		Tab.WHITE:
			return white_tab_button
		Tab.GREEN:
			return green_tab_button
		Tab.SPECIAL:
			return special_tab_button
		_:
			return black_tab_button

func _populate_for_current_tab() -> void:
	match _current_tab:
		Tab.BLACK:
			_populate_shop(GameDatabase.get_materia_recipes(1))
		Tab.WHITE:
			_populate_shop(GameDatabase.get_materia_recipes(2))
		Tab.GREEN:
			_populate_shop(GameDatabase.get_materia_recipes(3))
		Tab.SPECIAL:
			_populate_shop(GameDatabase.get_materia_recipes(4))

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
