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
var _hit_flash: ColorRect

var _action_menu_panel: PanelContainer
var _action_menu_vbox: VBoxContainer
var _menu_target_unit_index: int = -1
var _active_panels: Array = []

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
	battle_manager.attack_landed.connect(_on_attack_landed)

	DataManager.mission_completed.connect(_on_mission_completed)
	DataManager.mission_failed.connect(_on_mission_failed)

	enemy_texture.gui_input.connect(_on_enemy_texture_gui_input)
	
	_hit_flash = ColorRect.new()
	_hit_flash.color = Color(1.0, 0.0, 0.0, 0.0)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	enemy_texture.add_child(_hit_flash)

	_setup_action_menu()

func _setup_action_menu() -> void:
	_action_menu_panel = PanelContainer.new()
	_action_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	_action_menu_panel.hide()

	_action_menu_vbox = VBoxContainer.new()
	_action_menu_panel.add_child(_action_menu_vbox)

	add_child(_action_menu_panel)

func _open_skill_menu(unit_index: int) -> void:
	_menu_target_unit_index = unit_index
	_populate_action_menu("Skill", ["Fire", "Cure", "Slash"], battle_manager.CombatAction.SKILL)

func _open_item_menu(unit_index: int) -> void:
	_menu_target_unit_index = unit_index
	_populate_action_menu("Item", ["Potion", "Phoenix Down"], battle_manager.CombatAction.ITEM)

func _populate_action_menu(menu_title: String, options: Array, action_type: int) -> void:
	for child in _action_menu_vbox.get_children():
		child.queue_free()

	var title_label = Label.new()
	title_label.text = menu_title + " Menu"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_menu_vbox.add_child(title_label)

	for opt in options:
		var btn = Button.new()
		btn.text = opt
		btn.pressed.connect(func():
			battle_manager.set_queued_action(_menu_target_unit_index, action_type, opt)
			for p in _active_panels:
				if p._my_index == _menu_target_unit_index:
					p.update_action_visuals()
			_action_menu_panel.hide()
		)
		_action_menu_vbox.add_child(btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func():
		_action_menu_panel.hide()
	)
	_action_menu_vbox.add_child(cancel_btn)

	_action_menu_panel.show()

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

	_active_panels.clear()

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

		var unit_data = {}
		if party_idx >= 0 and party_idx < battle_manager.party_data.size():
			unit_data = battle_manager.party_data[party_idx]
			if not unit_data.is_empty():
				has_unit = true

		if has_unit:
			# Add panel
			var panel: Node = UnitPanelScene.instantiate()
			bottom_section.add_child(panel)
			panel.setup(party_idx)
			panel.open_skill_menu.connect(_open_skill_menu)
			panel.open_item_menu.connect(_open_item_menu)
			_active_panels.append(panel)

			# Add Combat Sprite
			var template_id: String = str(unit_data.get("unit_id", ""))
			var combat_sprite = load("res://features/battle/ui/combat_sprite.gd").new()
			combat_sprite.setup(party_idx, template_id)

			# Put CombatSprite in a Control wrapper to work with GridContainer
			var sprite_wrapper: Control = Control.new()
			sprite_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sprite_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL

			# Position sprite at center of wrapper
			combat_sprite.position = Vector2(40, 40) # Approximate center for default icon
			sprite_wrapper.add_child(combat_sprite)
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

func _on_attack_landed(attacker_index: int, target_index: int, damage: int) -> void:
	if target_index == -1:
		_hit_flash.color.a = 0.8
		var tween = create_tween()
		tween.tween_property(_hit_flash, "color:a", 0.0, 0.15)

func _on_turn_changed(new_turn: int) -> void:
	turn_label.text = "Turn %d" % new_turn

func _on_finish_pressed() -> void:
	if current_mission_id == "":
		return

	finish_button.disabled = true
	DataManager.request_perform_mission(current_mission_id)

func _on_mission_completed(rewards_text: String) -> void:
	rewards_popup.dialog_text = "Mission completed successfully!
" + rewards_text
	rewards_popup.popup_centered()

func _on_mission_failed(error_msg: String) -> void:
	print("Failed to complete mission: ", error_msg)
	finish_button.disabled = false

func _on_rewards_confirmed() -> void:
	UIManager.pop()
