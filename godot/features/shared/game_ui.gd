extends Control


@onready var earth_shrine_button: Button = $EarthShrineButton
@onready var default_background: ColorRect = $DefaultBackground
@onready var background: TextureRect = $Background

func _ready() -> void:
	if earth_shrine_button:
		earth_shrine_button.pressed.connect(_on_earth_shrine_pressed)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()

func _on_visibility_changed() -> void:
	if visible:
		if DataManager.last_played_dungeon_name != "":
			var bg_path = "res://assets/battle_bg/%s.jpg" % DataManager.last_played_dungeon_name
			if ResourceLoader.exists(bg_path):
				background.texture = load(bg_path)
				background.show()
				default_background.hide()
			else:
				background.hide()
				default_background.show()
		else:
			background.hide()
			default_background.show()

func _on_earth_shrine_pressed() -> void:
	DataManager.request_dungeon_missions(["1110101"])
	UIManager.push("combat_ui", {"mission_id": "1110101", "dungeon_id": "11101"})

func _on_world_map_pressed() -> void:
	UIManager.push("map_ui")

func _on_user_menu_pressed(id: int) -> void:
	if id == 0:
		UIManager.push("edit_profile_ui")
	elif id == 1:
		DataManager.logout()
		UIManager.set_root("login_ui")
