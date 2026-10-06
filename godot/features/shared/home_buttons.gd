extends ScrollContainer

@onready var world_map_button: TextureButton = $ButtonRow/WorldMap
@onready var espers_button: TextureButton = $ButtonRow/Espers
@onready var craft_button: TextureButton = $ButtonRow/Craft
@onready var colosseum_button: TextureButton = $ButtonRow/Colosseum

func _ready() -> void:
	world_map_button.pressed.connect(_on_world_map_pressed)
	espers_button.pressed.connect(_on_espers_pressed)
	craft_button.pressed.connect(_on_craft_pressed)
	colosseum_button.pressed.connect(_on_colosseum_pressed)

func _on_world_map_pressed() -> void:
	UIManager.push("map_ui")

func _on_espers_pressed() -> void:
	UIManager.push("espers_ui")

func _on_craft_pressed() -> void:
	UIManager.push("craft_ui")

func _on_colosseum_pressed() -> void:
	UIManager.push("colosseum_ui")
