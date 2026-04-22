extends Control

const SkillEntryButtonScene = preload("res://shared/ui/skill_entry/SkillEntryButton.tscn")

var current_mission_id: String = ""
var UnitPanelScene: PackedScene = preload("res://features/battle/ui/CombatUnitPanel.tscn")

@onready var battle_manager: Node = %BattleManager
@onready var finish_button: Button = %FinishButton
@onready var rewards_popup: AcceptDialog = %RewardsPopup

@onready var enemy_region: Control = %EnemyRegion
@onready var enemies_container: VBoxContainer = %EnemiesContainer
@onready var turn_label: Label = %TurnLabel
@onready var player_sprites_grid: GridContainer = %PlayerSpritesGrid
@onready var chain_count_label: Label = %ChainCountLabel
@onready var enemy_name_label: Label = %EnemyNameLabel
@onready var enemy_hp_bar: ProgressBar = %EnemyHPBar
@onready var enemy_hp_pct_label: Label = %EnemyHPPctLabel
@onready var bottom_ui_wrapper: Control = %BottomUIWrapper
@onready var bottom_section: GridContainer = %BottomSection
@onready var unit_info_popup: Control = %UnitInfoPopup
@onready var background: TextureRect = $Background

var _texture_cache: Dictionary = {}
var _hit_flash: ColorRect

var _action_menu_panel: PanelContainer
var _action_menu_vbox: VBoxContainer
var _menu_target_unit_index: int = -1
var _current_target_enemy_index: int = 0
var _active_panels: Array = []

var _current_open_menu: String = ""
var _menu_tween: Tween
var _is_dragging_menu: bool = false
var _menu_drag_start_position: Vector2

var combat_inventory: Dictionary = {}

var _is_ally_targeting_mode: bool = false
var _pending_skill_action_id: String = ""
var _pending_skill_action_name: String = ""
var _pending_skill_action_type: int = 0
var _cancel_target_button: Button

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
	battle_manager.wave_changed.connect(_on_wave_changed)
	battle_manager.attack_landed.connect(_on_attack_landed)
	battle_manager.wave_transition_started.connect(_on_wave_transition_started)
	battle_manager.item_dropped.connect(_on_item_dropped)
	battle_manager.item_refunded.connect(_on_item_refunded)

	DataManager.mission_completed.connect(_on_mission_completed)
	battle_manager.mission_failed.connect(_on_mission_failed)
	DataManager.mission_failed.connect(_on_mission_failed)

	
	_hit_flash = ColorRect.new()
	_hit_flash.color = Color(1.0, 0.0, 0.0, 0.0)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	enemy_region.add_child(_hit_flash)

	_setup_action_menu()
	_setup_cancel_target_button()
	_init_combat_inventory()

func _enter_ally_selection_state(action_type: int, action_name: String, action_id: String) -> void:
	_is_ally_targeting_mode = true
	_pending_skill_action_type = action_type
	_pending_skill_action_name = action_name
	_pending_skill_action_id = action_id

	if _cancel_target_button:
		_cancel_target_button.show()

	for p in _active_panels:
		p.is_ally_targeting_mode = true
		p.modulate = Color(0.5, 1.0, 0.5, 1.0) # Green highlight

func _init_combat_inventory() -> void:
	combat_inventory.clear()
	var stackables: Dictionary = DataManager.owned_items.get("stackables", {})

	for item_id in stackables.keys():
		var quantity: int = stackables[item_id]
		if quantity > 0 and DataManager.game_data_items.has(item_id):
			var item_data: Dictionary = DataManager.game_data_items[item_id]
			if item_data.get("usable_in_combat", false) == true and item_data.has("effects_raw"):
				combat_inventory[item_id] = quantity

func _unwrap_item_ability_id(effects_raw: Array) -> String:
	for effect in effects_raw:
		if effect.size() >= 4 and effect[2] == 71:
			var payload = effect[3]
			if typeof(payload) == TYPE_ARRAY and payload.size() > 0:
				return str(payload[0])
	return ""

func _exit_ally_selection_state() -> void:
	_is_ally_targeting_mode = false
	_pending_skill_action_type = 0
	_pending_skill_action_name = ""
	_pending_skill_action_id = ""

	if _cancel_target_button:
		_cancel_target_button.hide()

	# Reset panels visually
	for p in _active_panels:
		p.is_ally_targeting_mode = false
		p.modulate = Color(1.0, 1.0, 1.0, 1.0)
		p.update_action_visuals()

func _setup_cancel_target_button() -> void:
	_cancel_target_button = Button.new()
	_cancel_target_button.text = "Cancel Target"
	_cancel_target_button.custom_minimum_size = Vector2(200, 60)
	_cancel_target_button.hide()

	# Center it near the top of the bottom section
	_cancel_target_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_cancel_target_button.position.y = -80 # Move it up above the panels

	_cancel_target_button.pressed.connect(_exit_ally_selection_state)

	bottom_ui_wrapper.add_child(_cancel_target_button)

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
							var magic_data = DataManager.game_data_skills_magic[sk_id]
							options.append({
								"id": sk_id,
								"name": magic_data.get("name", "Unknown Magic"),
								"skill_data": magic_data,
								"level": req_rarity
							})
					elif sk_type == "ABILITY":
						if DataManager.game_data_skills_ability.has(sk_id):
							var ability_data = DataManager.game_data_skills_ability[sk_id]
							options.append({
								"id": sk_id,
								"name": ability_data.get("name", "Unknown Ability"),
								"skill_data": ability_data,
								"level": req_rarity
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

	for item_id in combat_inventory.keys():
		var quantity: int = combat_inventory[item_id]
		if quantity > 0 and DataManager.game_data_items.has(item_id):
			var item_data: Dictionary = DataManager.game_data_items[item_id]
			var item_name: String = item_data.get("name", "Unknown Item")
			options.append({
				"id": item_id,
				"name": item_name + " (x" + str(quantity) + ")",
				"item_data": item_data
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
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_action_menu_vbox.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	for opt in options:
		var action_id: String = opt.get("id", "")
		var action_name: String = opt.get("name", "")

		if is_skill:
			var btn = SkillEntryButtonScene.instantiate()
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var skill_data = opt.get("skill_data", {})
			var skill_level = opt.get("level", -1)
			btn.setup_from_skill_data(skill_data, "", true, skill_level)

			btn.pressed.connect(func():
				var parsed_data: Dictionary = OpcodeParser.parse_skill_improved(skill_data)
				var needs_ally_target = false

				for effect in parsed_data.get("effects", []):
					if effect.get("target_area", 1) == 1 and effect.get("target_type", 1) in [2, 6]:
						needs_ally_target = true
						break

				if needs_ally_target:
					_enter_ally_selection_state(action_type, opt.get("name", ""), action_id)
					_close_action_menu()
				else:
					battle_manager.set_queued_action(_menu_target_unit_index, action_type, opt.get("name", ""), action_id)
					for p in _active_panels:
						if p._my_index == _menu_target_unit_index:
							p.update_action_visuals()
					_close_action_menu()
			)
			grid.add_child(btn)
		else:
			var sub_text: String = "MP: --"
			# For items, extract the " (xCount)" part to be the subtext
			var paren_idx = action_name.find(" (x")
			if paren_idx != -1:
				sub_text = action_name.substr(paren_idx + 2, action_name.length() - paren_idx - 3) # Extracts 'xCount'
				action_name = action_name.left(paren_idx)

			var btn = _create_action_button(action_name, sub_text)
			btn.pressed.connect(func():
				if action_type == battle_manager.CombatAction.ITEM:
					if combat_inventory.has(action_id) and combat_inventory[action_id] > 0:
						combat_inventory[action_id] -= 1
						var item_data = opt.get("item_data", {})
						var effects_raw = item_data.get("effects_raw", [])
						var unwrapped_ability_id = _unwrap_item_ability_id(effects_raw)

						var action_payload: Dictionary = {
							"is_item": true,
							"original_item_id": action_id
						}
						
						battle_manager.set_queued_action(_menu_target_unit_index, action_type, opt.get("name", ""), unwrapped_ability_id, action_payload)
						for p in _active_panels:
							if p._my_index == _menu_target_unit_index:
								p.update_action_visuals()

						# We should just close the menu. If we wanted to refresh it while open, we wouldn't call _close_action_menu.
						_close_action_menu()
				else:
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

	if dungeon_id != "":
		var dungeon_data = DataManager.game_data_dungeons.get(dungeon_id, {})
		if dungeon_data.has("names"):
			var dungeon_name = str(dungeon_data["names"][0])
			var formatted_name = dungeon_name.replace(" ", "_")
			DataManager.last_played_dungeon_name = formatted_name

			var bg_path = "res://assets/battle_bg/%s.jpg" % formatted_name
			if ResourceLoader.exists(bg_path):
				background.texture = load(bg_path)
			else:
				print("CombatUI: Background not found at ", bg_path)

	battle_manager.initialize_battle(current_mission_id)

func _on_battle_state_ready() -> void:
	if battle_manager.current_wave == 1:
		_play_wave_one_intro(battle_manager.total_waves)

	# Clear previous children in enemies_container (to remove old CombatSprites)
	for child in enemies_container.get_children():
		enemies_container.remove_child(child)
		child.queue_free()

	# Instantiate a new CombatSprite for each enemy
	for i in range(battle_manager.enemy_units.size()):
		var enemy_data = battle_manager.enemy_units[i]
		var monster_id: String = str(enemy_data.get("id", "5010010"))

		var wrapper = Control.new()
		wrapper.name = "EnemyWrapper_" + str(i)
		wrapper.custom_minimum_size = Vector2(100, 100)
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
		enemies_container.add_child(wrapper)

		var enemy_sprite = load("res://features/battle/ui/combat_sprite.gd").new()
		enemy_sprite.name = "EnemyCombatSprite_" + str(i)
		enemy_sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		enemy_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		enemy_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)

		wrapper.add_child(enemy_sprite)
		enemy_sprite.setup(i, monster_id, true)

		var damage_container = Control.new()
		damage_container.name = "DamageContainer"
		damage_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		damage_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(damage_container)

		var is_staggered = (i % 2 != 0)
		if is_staggered:
			enemy_sprite.position.x += 30
			damage_container.position.x += 30

		# Connect click input for targeting
		enemy_sprite.gui_input.connect(Callable(self, "_on_enemy_clicked").bind(i))

	# Initialize top bar to target the first enemy (index 0) if it exists
	if battle_manager.enemy_units.size() > 0:
		_current_target_enemy_index = 0
		var first_enemy = battle_manager.enemy_units[0]
		enemy_name_label.text = first_enemy.get("name", "Unknown Monster")
		battle_manager.set_enemy_hp(0, first_enemy.get("current_hp", 0))
	else:
		enemy_name_label.text = "Cleared"
		battle_manager.set_enemy_hp(0, 0)
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
			panel.panel_tapped.connect(_on_panel_tapped)
			panel.info_tapped.connect(_on_unit_info_tapped)
			_active_panels.append(panel)

			# Add Combat Sprite
			var template_id: String = str(unit_data.get("unit_id", ""))
			var combat_sprite = load("res://features/battle/ui/combat_sprite.gd").new()
			combat_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			combat_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			combat_sprite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			combat_sprite.size_flags_vertical = Control.SIZE_EXPAND_FILL
			combat_sprite.setup(party_idx, template_id)

			player_sprites_grid.add_child(combat_sprite)
		else:
			# Empty slot for both UI elements
			var empty_panel: Control = Control.new()
			empty_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bottom_section.add_child(empty_panel)

			var empty_sprite: Control = Control.new()
			empty_sprite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			empty_sprite.size_flags_vertical = Control.SIZE_EXPAND_FILL
			player_sprites_grid.add_child(empty_sprite)

func _play_enemy_death(inner_sprite: Node) -> void:
	# 1. Kill any damage shake that is currently happening
	if inner_sprite.has_meta("shake_tween"):
		var old_shake = inner_sprite.get_meta("shake_tween")
		if old_shake and old_shake.is_valid():
			old_shake.kill()
			
	# 2. Kill any existing fade (just in case)
	if inner_sprite.has_meta("fade_tween"):
		var old_fade = inner_sprite.get_meta("fade_tween")
		if old_fade and old_fade.is_valid():
			old_fade.kill()

	# 3. Establish base position
	var orig_x = inner_sprite.position.x
	if inner_sprite.has_meta("orig_x"):
		orig_x = inner_sprite.get_meta("orig_x")
	else:
		inner_sprite.set_meta("orig_x", orig_x)

	# 4. The Fade Tween
	var fade_tween = create_tween()
	inner_sprite.set_meta("fade_tween", fade_tween)
	
	var fade_time = 0.4
	fade_tween.tween_property(inner_sprite, "modulate:a", 0.0, fade_time)
	fade_tween.tween_callback(inner_sprite.hide)
	
	# 5. The Shake Tween
	var shake_tween = create_tween()
	inner_sprite.set_meta("shake_tween", shake_tween)
	
	shake_tween.set_loops(4)
	shake_tween.tween_property(inner_sprite, "position:x", orig_x - 15, 0.05)
	shake_tween.tween_property(inner_sprite, "position:x", orig_x + 15, 0.05)
	
	# Optional: Snap it back exactly to center when the loops finish
	shake_tween.finished.connect(func(): inner_sprite.position.x = orig_x)
	
func _on_enemy_hp_changed(enemy_index: int, new_hp: int, max_hp: int, hp_percent: int) -> void:
	if enemy_index == _current_target_enemy_index:
		enemy_hp_bar.max_value = max_hp
		enemy_hp_bar.value = new_hp
		enemy_hp_pct_label.text = "%d%%" % hp_percent

	if new_hp <= 0:
		if enemy_index >= 0 and enemy_index < enemies_container.get_child_count():
			var wrapper = enemies_container.get_child(enemy_index)
			if wrapper.get_child_count() > 0:
				var enemy_sprite = wrapper.get_child(0)
				_play_enemy_death(enemy_sprite)

func _on_unit_info_tapped(unit_index: int) -> void:
	if unit_index >= 0 and unit_index < battle_manager.party_data.size():
		var unit_data = battle_manager.party_data[unit_index]
		unit_info_popup.setup(unit_data)
		unit_info_popup.show()

func _on_panel_tapped(unit_index: int) -> void:
	if _is_ally_targeting_mode:
		# Finalize targeting
		if unit_index >= 0 and unit_index < battle_manager.party_data.size():
			var unit_data = battle_manager.party_data[_menu_target_unit_index]
			if not unit_data.is_empty():
				unit_data["queued_target_team"] = "player"
				unit_data["queued_target_index"] = unit_index

				# Now queue the skill
				battle_manager.set_queued_action(_menu_target_unit_index, _pending_skill_action_type, _pending_skill_action_name, _pending_skill_action_id)
				for p in _active_panels:
					if p._my_index == _menu_target_unit_index:
						p.update_action_visuals()

		_exit_ally_selection_state()
	else:
		if unit_index in battle_manager.player_units_acted_this_turn:
			return
		# Normal execution
		battle_manager.execute_queued_action(unit_index)

func _on_enemy_clicked(event: InputEvent, enemy_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_ally_targeting_mode:
			_exit_ally_selection_state()
			return

		print("Enemy tapped! Global target set to index: ", enemy_index)

		_current_target_enemy_index = enemy_index

		# Apply this target to all player units
		for i in range(battle_manager.party_data.size()):
			var unit_data = battle_manager.party_data[i]
			if not unit_data.is_empty():
				unit_data["queued_target_team"] = "enemy"
				unit_data["queued_target_index"] = enemy_index

		# Update info bar with newly targeted enemy
		if enemy_index >= 0 and enemy_index < battle_manager.enemy_units.size():
			var enemy_data = battle_manager.enemy_units[enemy_index]
			enemy_name_label.text = enemy_data.get("name", "Unknown Monster")
			battle_manager.set_enemy_hp(enemy_index, enemy_data.get("current_hp", 0))

func _shake_enemy(enemy_node: Node) -> void:
	# Ensure we don't overlap tweens if hit rapidly
	if enemy_node.has_meta("shake_tween"):
		var old_tween = enemy_node.get_meta("shake_tween")
		if old_tween and old_tween.is_valid():
			old_tween.kill()

	var tween = create_tween()
	enemy_node.set_meta("shake_tween", tween)

	var orig_x = 0.0
	if enemy_node.has_meta("orig_x"):
		orig_x = enemy_node.get_meta("orig_x")
	else:
		orig_x = enemy_node.position.x
		enemy_node.set_meta("orig_x", orig_x)

	var offset = 10.0

	# Quick back and forth
	tween.tween_property(enemy_node, "position:x", orig_x - offset, 0.05)
	tween.tween_property(enemy_node, "position:x", orig_x + offset, 0.05)
	tween.tween_property(enemy_node, "position:x", orig_x, 0.05)

func _on_attack_landed(attacker_team: String, attacker_index: int, target_team: String, target_index: int, damage: int, chain_count: int) -> void:
	chain_count_label.text = "Chain: %d" % chain_count
	if target_team == "enemy":
		if target_index >= 0 and target_index < enemies_container.get_child_count():
			var wrapper = enemies_container.get_child(target_index)
			if wrapper.get_child_count() > 0:
				var enemy_sprite = wrapper.get_child(0)
				_shake_enemy(enemy_sprite)
		_spawn_damage_number(damage, target_index)

func _spawn_damage_number(damage: int, target_index: int) -> void:
	if target_index < 0 or target_index >= enemies_container.get_child_count():
		return

	var wrapper = enemies_container.get_child(target_index)
	var damage_container = wrapper.get_node_or_null("DamageContainer")
	if not damage_container:
		return

	var label = Label.new()
	label.text = str(damage)
	# Set appearance
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(1, 0.2, 0.2)) # Red damage color
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)

	# To ensure we push up by a known amount, we'll estimate or read the label size
	# But Label size isn't immediately known before drawing, so we use a fixed offset.
	var push_amount = 40.0

	# Move existing labels up
	for child in damage_container.get_children():
		if child is Label:
			var move_tween = create_tween()
			move_tween.tween_property(child, "position:y", child.position.y - push_amount, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Add new label at bottom
	damage_container.add_child(label)
	label.position = Vector2.ZERO

	# Animate the new label
	# We want it to fade out over 1 second and then delete itself.
	# We'll use a Tween that runs for 1 second, fading the alpha to 0.
	var fade_tween = create_tween()
	fade_tween.tween_property(label, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	fade_tween.finished.connect(func():
		label.queue_free()
	)

func _on_turn_changed(new_turn: int) -> void:
	turn_label.text = "Turn %d" % new_turn
	chain_count_label.text = "Chain: 0"

func _on_wave_changed(current_wave: int, total_waves: int) -> void:
	chain_count_label.text = "Chain: 0"

func _play_wave_one_intro(total_waves: int) -> void:
	# Setup the labels
	var transition_ui = %TransitionUI
	var current_num = transition_ui.get_node("HBox/NumberMask/CurrentNum")
	var next_num = transition_ui.get_node("HBox/NumberMask/NextNum")
	var total_waves_label = transition_ui.get_node("HBox/TotalWavesLabel")

	current_num.text = "1"
	next_num.text = "" # Keep it empty/hidden
	total_waves_label.text = " / " + str(total_waves)

	# Ensure positions are reset
	current_num.position.y = 0
	next_num.position.y = 50

	transition_ui.show()
	transition_ui.modulate.a = 0.0

	var tween = create_tween()
	# Fade in the UI
	tween.tween_property(transition_ui, "modulate:a", 1.0, 0.3)
	tween.tween_interval(1.0) # Hold so the player reads it

	# Fade out
	tween.tween_property(transition_ui, "modulate:a", 0.0, 0.3)
	tween.tween_callback(transition_ui.hide)

func _on_item_refunded(item_id: String) -> void:
	if combat_inventory.has(item_id):
		combat_inventory[item_id] += 1
	else:
		combat_inventory[item_id] = 1

	if _current_open_menu == "ITEM":
		_open_item_menu(_menu_target_unit_index)

func _on_item_dropped(enemy_index: int, item_id: String) -> void:
	var enemy_node: Node = null
	if enemy_index >= 0 and enemy_index < enemies_container.get_child_count():
		var wrapper = enemies_container.get_child(enemy_index)
		if wrapper.get_child_count() > 0:
			enemy_node = wrapper.get_child(0)

	if not enemy_node:
		return

	var drop_icon = TextureRect.new()
	var tex_path = "res://icon.svg"
	if DataManager.game_data_items.has(item_id):
		var item_data = DataManager.game_data_items[item_id]
		if item_data.has("icon"):
			tex_path = "res://assets/items/" + str(item_data["icon"])

	if ResourceLoader.exists(tex_path):
		drop_icon.texture = _get_dynamic_texture(tex_path)
	else:
		drop_icon.texture = _get_dynamic_texture("res://icon.svg")

	drop_icon.custom_minimum_size = Vector2(40, 40)
	drop_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drop_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drop_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(drop_icon)
	drop_icon.global_position = enemy_node.global_position

	var tween = create_tween()
	var drop_distance_x = 60.0
	var drop_distance_y = 40.0

	tween.parallel().tween_property(drop_icon, "global_position:x", drop_icon.global_position.x + drop_distance_x, 0.6)
	tween.parallel().tween_property(drop_icon, "global_position:y", drop_icon.global_position.y + drop_distance_y, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	tween.tween_interval(0.5)
	tween.tween_property(drop_icon, "modulate:a", 0.0, 0.3)
	tween.tween_callback(drop_icon.queue_free)

func _on_wave_transition_started(curr_wave: int, next_wave: int, total_waves: int) -> void:
	# Setup the labels
	var transition_ui = %TransitionUI
	var current_num = transition_ui.get_node("HBox/NumberMask/CurrentNum")
	var next_num = transition_ui.get_node("HBox/NumberMask/NextNum")
	var total_waves_label = transition_ui.get_node("HBox/TotalWavesLabel")

	current_num.text = str(curr_wave)
	next_num.text = str(next_wave)
	total_waves_label.text = " / " + str(total_waves)

	# Ensure positions are reset
	current_num.position.y = 0
	next_num.position.y = 50

	transition_ui.show()
	transition_ui.modulate.a = 0.0

	var tween = create_tween()
	# Fade in the UI
	tween.tween_property(transition_ui, "modulate:a", 1.0, 0.3)
	tween.tween_interval(0.5) # Hold so the player reads it

	# The Odometer "Push" Effect!
	tween.parallel().tween_property(current_num, "position:y", -50, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(next_num, "position:y", 0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)

	tween.tween_interval(0.5) # Hold again

	# Fade out
	tween.tween_property(transition_ui, "modulate:a", 0.0, 0.3)
	tween.tween_callback(transition_ui.hide)

func _on_finish_pressed() -> void:
	if current_mission_id == "":
		return

	finish_button.disabled = true
	battle_manager._trigger_mission_complete()

func _on_mission_completed(rewards_text: String = "") -> void:
	rewards_popup.dialog_text = "Mission completed successfully!" + rewards_text
	rewards_popup.popup_centered()

func _on_mission_failed(error_msg: String = "") -> void:
	print("Failed to complete mission: ", error_msg)
	rewards_popup.dialog_text = "Mission Failed!"
	rewards_popup.popup_centered()

func _on_rewards_confirmed() -> void:
	UIManager.pop()
