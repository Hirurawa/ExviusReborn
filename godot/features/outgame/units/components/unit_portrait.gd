extends Control

signal unit_selected(unit_data)

@onready var badge: TextureRect = $Button/Node2D/Badge
@onready var button: Button = $Button

var current_unit: Dictionary

func _ready() -> void:
	button.pressed.connect(_on_button_pressed)

func set_selected(is_selected: bool) -> void:
	badge.visible = is_selected

func setup(unit_data) -> void:
	current_unit = unit_data
	$Button/Node2D.setup(unit_data)

func _on_button_pressed() -> void:
	unit_selected.emit(current_unit)
