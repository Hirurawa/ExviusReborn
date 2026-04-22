extends Control


@onready var earth_shrine_button: Button = $EarthShrineButton
@onready var default_background: ColorRect = $DefaultBackground
@onready var background: TextureRect = $Background
@onready var player_sprites_grid: GridContainer = %PlayerSpritesGrid

func _ready() -> void:
	if earth_shrine_button:
		earth_shrine_button.pressed.connect(_on_earth_shrine_pressed)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()

func _on_visibility_changed() -> void:
	if visible:
		_setup_party_sprites()
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

func _setup_party_sprites() -> void:
	for child in player_sprites_grid.get_children():
		child.queue_free()

	var active_party = DataManager.player_stats.get("active_party", [])

	# Grid to party mapping as used in combat
	var grid_to_party_map: Array[int] = [0, 3, 1, 4, 2, -1]

	for grid_idx in range(6):
		var party_idx = grid_to_party_map[grid_idx]
		var template_id = ""

		if party_idx >= 0 and party_idx < active_party.size():
			var owned_unit_id = active_party[party_idx]
			if owned_unit_id and DataManager.owned_units.has(owned_unit_id):
				template_id = str(DataManager.owned_units[owned_unit_id].get("unit_id", ""))

		if template_id != "":
			var combat_sprite = load("res://features/battle/ui/combat_sprite.gd").new()
			combat_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			combat_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			combat_sprite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			combat_sprite.size_flags_vertical = Control.SIZE_EXPAND_FILL
			combat_sprite.setup(party_idx, template_id)
			player_sprites_grid.add_child(combat_sprite)
		else:
			var empty_sprite = Control.new()
			empty_sprite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			empty_sprite.size_flags_vertical = Control.SIZE_EXPAND_FILL
			player_sprites_grid.add_child(empty_sprite)

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
