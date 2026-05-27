extends Control

@onready var back_button: Button = $UnitNamebgChara/UnitMinibutton1

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	UIManager.pop()
	var new_top: Node = UIManager.get_current_scene()
	if new_top and new_top.has_method("_on_awaken_units"):
		new_top.call_deferred("_on_awaken_units")
