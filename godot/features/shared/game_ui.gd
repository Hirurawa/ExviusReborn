extends Control

@onready var default_background: ColorRect = $DefaultBackground
@onready var background: TextureRect = $Background
@onready var user_menu_button: MenuButton = $UserMenuButton
@onready var player_sprites_container: Control = $PlayerSpritesContainer
@onready var debug_gil_amount: LineEdit = $DebugAddGil/GilAmount
@onready var debug_add_gil_button: Button = $DebugAddGil/AddGilButton
@onready var vortex_dungeon: TextureButton = $VortexDungeon

const GRID_TO_PARTY_MAP: Array[int] = [0, 3, 1, 4, 2, -1]
const COMBAT_SPRITE_SCRIPT: GDScript = preload("res://features/battle/ui/combat_sprite.gd")

var _spawned_party_sprites: Array[TextureRect] = []

func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	user_menu_button.get_popup().id_pressed.connect(_on_user_menu_pressed)
	debug_add_gil_button.pressed.connect(_on_debug_add_gil_pressed)
	vortex_dungeon.pressed.connect(_on_vortex_dungeon_pressed)
	if not PartyService.parties_updated.is_connected(_on_parties_updated):
		PartyService.parties_updated.connect(_on_parties_updated)
	if not PartyService.active_party_changed.is_connected(_on_active_party_changed):
		PartyService.active_party_changed.connect(_on_active_party_changed)
	if not UnitService.units_updated.is_connected(_on_units_updated):
		UnitService.units_updated.connect(_on_units_updated)
	_on_visibility_changed()
	_refresh_party_sprites()

func _exit_tree() -> void:
	if PartyService.parties_updated.is_connected(_on_parties_updated):
		PartyService.parties_updated.disconnect(_on_parties_updated)
	if PartyService.active_party_changed.is_connected(_on_active_party_changed):
		PartyService.active_party_changed.disconnect(_on_active_party_changed)
	if UnitService.units_updated.is_connected(_on_units_updated):
		UnitService.units_updated.disconnect(_on_units_updated)

func _on_parties_updated(_parties: Array) -> void:
	_refresh_party_sprites()

func _on_active_party_changed(_party_index: int) -> void:
	_refresh_party_sprites()

func _on_units_updated(_units: Array) -> void:
	_refresh_party_sprites()

func _clear_party_sprites() -> void:
	for dot in player_sprites_container.get_children():
		for child in dot.get_children():
			child.queue_free()
	_spawned_party_sprites.clear()

func _refresh_party_sprites() -> void:
	_clear_party_sprites()

	var active_party: Dictionary = PartyService.get_active_party()
	if active_party.is_empty():
		return

	var party_units: Array = active_party.get("units", [])

	for grid_idx in range(player_sprites_container.get_child_count()):
		if grid_idx >= GRID_TO_PARTY_MAP.size():
			continue

		var party_idx: int = GRID_TO_PARTY_MAP[grid_idx]
		if party_idx < 0 or party_idx >= party_units.size():
			continue

		var instance_id: String = str(party_units[party_idx])
		if instance_id == "":
			continue

		var unit_inst: Dictionary = _find_unit_inst(instance_id)
		if unit_inst.is_empty():
			continue

		var unit_id: String = str(unit_inst.get("unitId"))
		if unit_id == "":
			continue

		var combat_sprite: TextureRect = COMBAT_SPRITE_SCRIPT.new()
		combat_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		combat_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		combat_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
		combat_sprite.setup(party_idx, unit_id)

		player_sprites_container.get_child(grid_idx).add_child(combat_sprite)
		_spawned_party_sprites.append(combat_sprite)

func _find_unit_inst(instance_id: String) -> Dictionary:
	for unit_entry in UnitService.owned_units_ids:
		if unit_entry is Dictionary and str(unit_entry.get("instance_id", "")) == instance_id:
			return unit_entry
	return {}

func _on_visibility_changed() -> void:
	if visible:
		if MissionService.last_entered_mission_id != "":
			var bg_tex = GameDatabase.get_mission_bg(MissionService.last_entered_mission_id)
			var bg_path = "res://assets/battle_bg/%s" % bg_tex
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

func _on_world_map_pressed() -> void:
	UIManager.push("map_ui")

func _on_user_menu_pressed(id: int) -> void:
	if id == 0:
		UIManager.push("edit_profile_ui")
	elif id == 1:
		AccountService.logout()
		UIManager.set_root("login_ui")
	elif id == 2:
		UIManager.push("settings_ui")

func _on_debug_add_gil_pressed() -> void:
	var text: String = debug_gil_amount.text.strip_edges()
	if not text.is_valid_int():
		return
	var amount: int = int(text)
	if amount == 0:
		return
	PlayerProfile.add_gil(amount)
	debug_gil_amount.text = ""

func _on_vortex_dungeon_pressed() -> void:
	UIManager.push("vortex_dungeon_ui")
