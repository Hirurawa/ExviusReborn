extends Control

@onready var craft_top_btn1: TextureButton = $craft_top_btn1
@onready var craft_top_btn3: TextureButton = $craft_top_btn3
@onready var craft_top_btn4: TextureButton = $craft_top_btn4
@onready var back_button: TextureButton = $CreCraftTitle/BackButton

func _ready() -> void:
	craft_top_btn1.pressed.connect(_on_craft_top_btn1_pressed)
	craft_top_btn3.pressed.connect(_on_craft_top_btn3_pressed)
	craft_top_btn4.pressed.connect(_on_craft_top_btn4_pressed)
	back_button.pressed.connect(_on_back_button_pressed)

func _on_craft_top_btn1_pressed() -> void:
	UIManager.push("craft_equipment_ui")

func _on_craft_top_btn3_pressed() -> void:
	UIManager.push("craft_item_ui")

func _on_craft_top_btn4_pressed() -> void:
	UIManager.push("craft_ability_ui")

func _on_back_button_pressed() -> void:
	UIManager.pop()
