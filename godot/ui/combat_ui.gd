extends Control

var current_mission_id: String = ""
var UnitPanelScene = preload("res://ui/combat_unit_panel.tscn")

@onready var battle_manager = %BattleManager
@onready var finish_button = %FinishButton
@onready var rewards_popup = %RewardsPopup

@onready var enemy_texture = %EnemyTexture
@onready var turn_label = %TurnLabel
@onready var player_sprites_grid = %PlayerSpritesGrid
@onready var enemy_name_label = %EnemyNameLabel
@onready var enemy_hp_bar = %EnemyHPBar
@onready var enemy_hp_pct_label = %EnemyHPPctLabel
@onready var bottom_section = %BottomSection

func _ready() -> void:
	finish_button.pressed.connect(_on_finish_pressed)
	rewards_popup.confirmed.connect(_on_rewards_confirmed)

	battle_manager.battle_state_ready.connect(_on_battle_state_ready)
	battle_manager.enemy_hp_changed.connect(_on_enemy_hp_changed)
	battle_manager.turn_changed.connect(_on_turn_changed)

	enemy_texture.gui_input.connect(_on_enemy_texture_gui_input)

func init_scene(params: Dictionary) -> void:
	current_mission_id = params.get("mission_id", "")
	var dungeon_id = params.get("dungeon_id", "")

	battle_manager.initialize_battle(dungeon_id)

func _on_battle_state_ready() -> void:
	# Populate enemy details
	enemy_name_label.text = battle_manager.enemy_data.get("name", "Unknown Monster")

	var monster_id = str(battle_manager.enemy_data.get("monster_id", "5010010"))
	var tex_path = "res://assets/monster_icon/monster_icon_" + monster_id + ".png"
	if ResourceLoader.exists(tex_path):
		enemy_texture.texture = load(tex_path)
	else:
		# Fallback placeholder
		enemy_texture.texture = load("res://icon.svg")

	# Populate enemy HP
	_on_enemy_hp_changed(battle_manager.enemy_current_hp, battle_manager.enemy_max_hp)
	_on_turn_changed(battle_manager.turn_count)

	# Clear previous panels and sprites
	for child in bottom_section.get_children():
		child.queue_free()
	for child in player_sprites_grid.get_children():
		child.queue_free()

	# Populate player units
	# Order: Top Left, Bottom Left, Top Right, Middle Right.
	# We can just iterate the party data and place them.
	for unit in battle_manager.party_data:
		# Add panel
		var panel = UnitPanelScene.instantiate()
		bottom_section.add_child(panel)
		panel.setup(unit)

		# Add sprite placeholder
		var anim_sprite = AnimatedSprite2D.new()
		var frames = SpriteFrames.new()
		frames.add_frame("default", load("res://icon.svg"))
		anim_sprite.sprite_frames = frames

		# Put AnimatedSprite2D in a Control wrapper to work with GridContainer
		var sprite_wrapper = Control.new()
		sprite_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sprite_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL

		# Position sprite at center of wrapper
		anim_sprite.position = Vector2(40, 40) # Approximate center for default icon
		sprite_wrapper.add_child(anim_sprite)
		player_sprites_grid.add_child(sprite_wrapper)

	# Reorder panels to match "Top Left -> Bottom Left -> Top Right -> Middle Right"
	# GridContainer places items:
	# 0 (Row 1 Col 1) - Top Left
	# 1 (Row 1 Col 2) - Top Right
	# 2 (Row 2 Col 1) - Mid Left
	# 3 (Row 2 Col 2) - Mid Right
	# 4 (Row 3 Col 1) - Bot Left
	# 5 (Row 3 Col 2) - Bot Right
	#
	# User wants: Top Left (0), Bottom Left (4), Top Right (1), Middle Right (3)

	# Add empty slots to make exactly 6 items first
	while bottom_section.get_child_count() < 6:
		var empty_panel = Control.new()
		empty_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom_section.add_child(empty_panel)
	while player_sprites_grid.get_child_count() < 6:
		var empty_sprite = Control.new()
		empty_sprite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_sprites_grid.add_child(empty_sprite)

	var panels = bottom_section.get_children()
	var sprites = player_sprites_grid.get_children()

	# Mapping from logical Party index to Grid index
	# Index 0: Top Left -> Grid pos 0
	# Index 1: Bottom Left -> Grid pos 4
	# Index 2: Top Right -> Grid pos 1
	# Index 3: Middle Right -> Grid pos 3
	var expected_positions = [0, 4, 1, 3, 2, 5]

	for i in range(panels.size()):
		if i < expected_positions.size():
			bottom_section.move_child(panels[i], expected_positions[i])
			player_sprites_grid.move_child(sprites[i], expected_positions[i])

func _on_enemy_hp_changed(new_hp: int, max_hp: int) -> void:
	enemy_hp_bar.max_value = max_hp
	enemy_hp_bar.value = new_hp

	var pct = 0
	if max_hp > 0:
		pct = int((float(new_hp) / float(max_hp)) * 100.0)
	enemy_hp_pct_label.text = "%d%%" % pct

func _on_enemy_texture_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Enemy tapped! Target set.")

func _on_turn_changed(new_turn: int) -> void:
	turn_label.text = "Turn %d" % new_turn

func _on_finish_pressed() -> void:
	if current_mission_id == "":
		return

	finish_button.disabled = true
	var result = await DataManager.perform_mission(current_mission_id)

	if result.has("error"):
		print("Failed to complete mission: ", result.error)
		finish_button.disabled = false
	else:
		# Success! Show rewards popup
		rewards_popup.dialog_text = "Mission completed successfully!\n"

		var rewards_text = ""

		# Show Gil/Lapis rewards if any from wallet changes (simplified for placeholder)
		var mission_data = DataManager.game_data_missions.get(current_mission_id, {})
		if mission_data.has("gil"):
			rewards_text += "Gil +%s\n" % str(int(mission_data.get("gil", 0)))
		if mission_data.has("exp"):
			rewards_text += "Rank EXP +%s\n" % str(int(mission_data.get("exp", 0)))

		rewards_popup.dialog_text += rewards_text
		rewards_popup.popup_centered()

func _on_rewards_confirmed() -> void:
	UIManager.pop()
