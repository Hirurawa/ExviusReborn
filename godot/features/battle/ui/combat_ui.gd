extends Control

var current_mission_id: String = ""
var UnitPanelScene: PackedScene = preload("res://features/battle/ui/CombatUnitPanel.tscn")

@onready var battle_manager: Node = %BattleManager
@onready var finish_button: Button = %FinishButton
@onready var rewards_popup: AcceptDialog = %RewardsPopup

@onready var enemy_texture: TextureRect = %EnemyTexture
@onready var turn_label: Label = %TurnLabel
@onready var player_sprites_grid: GridContainer = %PlayerSpritesGrid
@onready var enemy_name_label: Label = %EnemyNameLabel
@onready var enemy_hp_bar: ProgressBar = %EnemyHPBar
@onready var enemy_hp_pct_label: Label = %EnemyHPPctLabel
@onready var bottom_section: GridContainer = %BottomSection

var _texture_cache: Dictionary = {}

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _ready() -> void:
	finish_button.pressed.connect(_on_finish_pressed)
	rewards_popup.confirmed.connect(_on_rewards_confirmed)

	battle_manager.battle_state_ready.connect(_on_battle_state_ready)
	battle_manager.enemy_hp_changed.connect(_on_enemy_hp_changed)
	battle_manager.turn_changed.connect(_on_turn_changed)

	DataManager.mission_completed.connect(_on_mission_completed)
	DataManager.mission_failed.connect(_on_mission_failed)

	enemy_texture.gui_input.connect(_on_enemy_texture_gui_input)

func init_scene(params: Dictionary) -> void:
	current_mission_id = params.get("mission_id", "")
	var dungeon_id: String = params.get("dungeon_id", "")

	battle_manager.initialize_battle(dungeon_id)

func _on_battle_state_ready() -> void:
	# Populate enemy details
	enemy_name_label.text = battle_manager.enemy_data.get("name", "Unknown Monster")

	var monster_id: String = str(battle_manager.enemy_data.get("monster_id", "5010010"))
	var tex_path: String = "res://assets/monster_icon/monster_icon_" + monster_id + ".png"
	if ResourceLoader.exists(tex_path):
		enemy_texture.texture = _get_dynamic_texture(tex_path)
	else:
		# Fallback placeholder
		enemy_texture.texture = _get_dynamic_texture("res://icon.svg")

	# Populate enemy HP
	battle_manager.set_enemy_hp(battle_manager.enemy_current_hp)
	_on_turn_changed(battle_manager.turn_count)

	# Clear previous panels and sprites
	for child in bottom_section.get_children():
		child.queue_free()
	for child in player_sprites_grid.get_children():
		child.queue_free()

	# Map the 6 grid cells to the correct party indices
	# GridContainer places items left-to-right, top-to-bottom:
	# Grid 0 (Top Left)     -> Party index 0
	# Grid 1 (Top Right)    -> Party index 3
	# Grid 2 (Mid Left)     -> Party index 1
	# Grid 3 (Mid Right)    -> Party index 4
	# Grid 4 (Bot Left)     -> Party index 2
	# Grid 5 (Bot Right)    -> Empty / -1
	var grid_to_party_map: Array[int] = [0, 3, 1, 4, 2, -1]

	for grid_idx in range(6):
		var party_idx = grid_to_party_map[grid_idx]
		var has_unit = false

		if party_idx >= 0 and party_idx < battle_manager.party_data.size():
			var unit_data = battle_manager.party_data[party_idx]
			if not unit_data.is_empty():
				has_unit = true

		if has_unit:
			# Add panel
			var panel: Node = UnitPanelScene.instantiate()
			bottom_section.add_child(panel)
			panel.setup(party_idx)

			# Add sprite placeholder
			var anim_sprite: AnimatedSprite2D = AnimatedSprite2D.new()
			var frames: SpriteFrames = SpriteFrames.new()
			frames.add_frame("default", _get_dynamic_texture("res://icon.svg"))
			anim_sprite.sprite_frames = frames

			# Put AnimatedSprite2D in a Control wrapper to work with GridContainer
			var sprite_wrapper: Control = Control.new()
			sprite_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sprite_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL

			# Position sprite at center of wrapper
			anim_sprite.position = Vector2(40, 40) # Approximate center for default icon
			sprite_wrapper.add_child(anim_sprite)
			player_sprites_grid.add_child(sprite_wrapper)
		else:
			# Empty slot for both UI elements
			var empty_panel: Control = Control.new()
			empty_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bottom_section.add_child(empty_panel)

			var empty_sprite: Control = Control.new()
			empty_sprite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			player_sprites_grid.add_child(empty_sprite)

func _on_enemy_hp_changed(new_hp: int, max_hp: int, hp_percent: int) -> void:
	enemy_hp_bar.max_value = max_hp
	enemy_hp_bar.value = new_hp
	enemy_hp_pct_label.text = "%d%%" % hp_percent

func _on_enemy_texture_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Enemy tapped! Target set.")

func _on_turn_changed(new_turn: int) -> void:
	turn_label.text = "Turn %d" % new_turn

func _on_finish_pressed() -> void:
	if current_mission_id == "":
		return

	finish_button.disabled = true
	DataManager.request_perform_mission(current_mission_id)

func _on_mission_completed(rewards_text: String) -> void:
	rewards_popup.dialog_text = "Mission completed successfully!\n" + rewards_text
	rewards_popup.popup_centered()

func _on_mission_failed(error_msg: String) -> void:
	print("Failed to complete mission: ", error_msg)
	finish_button.disabled = false

func _on_rewards_confirmed() -> void:
	UIManager.pop()
