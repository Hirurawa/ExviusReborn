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
@onready var bottom_ui_wrapper: Control = %BottomUIWrapper
@onready var bottom_section: GridContainer = %BottomSection

var _texture_cache: Dictionary = {}
var _hit_flash: ColorRect

var _action_menu_panel: PanelContainer
var _action_menu_vbox: VBoxContainer
var _menu_target_unit_index: int = -1
var _active_panels: Array = []

var _current_open_menu: String = ""
var _menu_tween: Tween
var _is_dragging_menu: bool = false
var _menu_drag_start_position: Vector2

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
	_action_menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_action_menu_panel.hide()
	_action_menu_panel.gui_input.connect(_on_action_menu_gui_input)

	_action_menu_vbox = VBoxContainer.new()
	_action_menu_panel.add_child(_action_menu_vbox)

	bottom_ui_wrapper.add_child(_action_menu_panel)

func _on_action_menu_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if not _is_dragging_menu and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or event is InputEventScreenDrag):
			_is_dragging_menu = true
			_menu_drag_start_position = event.position
		elif _is_dragging_menu:
			var delta = event.position - _menu_drag_start_position
			if abs(delta.x) > abs(delta.y) and abs(delta.x) > 20:
				if _current_open_menu == "SKILL" and delta.x < -20:
					_close_action_menu()
					_is_dragging_menu = false
				elif _current_open_menu == "ITEM" and delta.x > 20:
					_close_action_menu()
					_is_dragging_menu = false

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_is_dragging_menu = false
	elif event is InputEventScreenTouch and not event.pressed:
		_is_dragging_menu = false

func _open_skill_menu(unit_index: int) -> void:
	_menu_target_unit_index = unit_index

	var options: Array = []
	if unit_index >= 0 and unit_index < battle_manager.party_data.size():
		var unit_inst: Dictionary = battle_manager.party_data[unit_index]
		if not unit_inst.is_empty():
			var unit_id = str(unit_inst.get("unit_id", ""))
			var rarity = int(unit_inst.get("current_rarity", 1))
			var level = int(unit_inst.get("level", 1))

			var unit_data: Dictionary = DataManager.game_data_units.get(unit_id, {})
			var skills: Array = unit_data.get("skills", [])

			for sk in skills:
				var req_rarity = int(sk.get("rarity", 99))
				var req_level = int(sk.get("level", 99))

				if rarity > req_rarity or (rarity == req_rarity and level >= req_level):
					var sk_id = str(int(sk.get("id", "")))
					var sk_type = sk.get("type", "")

					if sk_type == "MAGIC":
						if DataManager.game_data_skills_magic.has(sk_id):
							options.append({
								"id": sk_id,
								"name": DataManager.game_data_skills_magic[sk_id].get("name", "Unknown Magic")
							})
					elif sk_type == "ABILITY":
						if DataManager.game_data_skills_ability.has(sk_id):
							options.append({
								"id": sk_id,
								"name": DataManager.game_data_skills_ability[sk_id].get("name", "Unknown Ability")
							})

	_populate_action_menu("Skill", options, battle_manager.CombatAction.SKILL, true)

	_current_open_menu = "SKILL"
	var target_center_x = 0.0
	var offscreen_left_x = -bottom_ui_wrapper.size.x

	_action_menu_panel.position.x = offscreen_left_x
	_action_menu_panel.show()

	if _menu_tween and _menu_tween.is_valid():
		_menu_tween.kill()
	_menu_tween = create_tween()
	_menu_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_menu_tween.tween_property(_action_menu_panel, "position:x", target_center_x, 0.2)

func _open_item_menu(unit_index: int) -> void:
	_menu_target_unit_index = unit_index

	var options: Array = []
	var stackables: Dictionary = DataManager.owned_items.get("stackables", {})

	for item_id in stackables.keys():
		var quantity: int = stackables[item_id]
		if quantity > 0 and DataManager.game_data_items.has(item_id):
			var item_data: Dictionary = DataManager.game_data_items[item_id]
			var item_name: String = item_data.get("name", "Unknown Item")
			options.append({
				"id": item_id,
				"name": item_name + " (x" + str(quantity) + ")"
			})

	_populate_action_menu("Item", options, battle_manager.CombatAction.ITEM, false)

	_current_open_menu = "ITEM"
	var target_center_x = 0.0
	var offscreen_right_x = bottom_ui_wrapper.size.x

	_action_menu_panel.position.x = offscreen_right_x
	_action_menu_panel.show()

	if _menu_tween and _menu_tween.is_valid():
		_menu_tween.kill()
	_menu_tween = create_tween()
	_menu_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_menu_tween.tween_property(_action_menu_panel, "position:x", target_center_x, 0.2)

func _close_action_menu() -> void:
	if _current_open_menu == "":
		return

	var target_x: float
	if _current_open_menu == "SKILL":
		target_x = -bottom_ui_wrapper.size.x
	else:
		target_x = bottom_ui_wrapper.size.x

	if _menu_tween and _menu_tween.is_valid():
		_menu_tween.kill()
	_menu_tween = create_tween()
	_menu_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_menu_tween.tween_property(_action_menu_panel, "position:x", target_x, 0.2)
	_menu_tween.finished.connect(func():
		_action_menu_panel.hide()
		_current_open_menu = ""
	)

func _create_action_button(action_name: String, sub_text: String) -> Button:
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 50)

	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	var icon_rect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(40, 40)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_rect)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	var name_label = Label.new()
	name_label.text = action_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var sub_label = Label.new()
	sub_label.text = sub_text
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(sub_label)

	return btn

func _populate_action_menu(menu_title: String, options: Array, action_type: int, is_skill: bool) -> void:
	for child in _action_menu_vbox.get_children():
		child.queue_free()

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_action_menu_vbox.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for opt in options:
		var action_id: String = opt.get("id", "")
		var action_name: String = opt.get("name", "")
		var sub_text: String = "MP: --"

		if not is_skill:
			# For items, extract the " (xCount)" part to be the subtext
			var paren_idx = action_name.find(" (x")
			if paren_idx != -1:
				sub_text = action_name.substr(paren_idx + 2, action_name.length() - paren_idx - 3) # Extracts 'xCount'
				action_name = action_name.left(paren_idx)

		var btn = _create_action_button(action_name, sub_text)
		btn.pressed.connect(func():
			battle_manager.set_queued_action(_menu_target_unit_index, action_type, opt.get("name", ""), action_id)
			for p in _active_panels:
				if p._my_index == _menu_target_unit_index:
					p.update_action_visuals()
			_close_action_menu()
		)
		grid.add_child(btn)

	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_END
	_action_menu_vbox.add_child(bottom_hbox)

	var cancel_btn = Button.new()
	cancel_btn.text = "Back"
	cancel_btn.pressed.connect(func():
		_close_action_menu()
	)
	bottom_hbox.add_child(cancel_btn)

func init_scene(params: Dictionary) -> void:
	current_mission_id = params.get("mission_id", "")
	var dungeon_id: String = params.get("dungeon_id", "")

	battle_manager.initialize_battle(dungeon_id)

func _on_battle_state_ready() -> void:
	# Populate enemy details
	enemy_name_label.text = battle_manager.enemy_data.get("name", "Unknown Monster")

	var monster_id: String = str(battle_manager.enemy_data.get("id", "5010010"))
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
