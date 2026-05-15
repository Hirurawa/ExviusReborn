extends Control

@onready var back_button: TextureButton = $CrePrepareTitle/BackButton

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)

func _on_back_button_pressed() -> void:
	UIManager.pop()