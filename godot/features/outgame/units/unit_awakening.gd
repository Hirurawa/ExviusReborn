extends Control

@onready var back_button: Button = $UnitNamebgChara/UnitMinibutton1

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	UIManager.pop()
