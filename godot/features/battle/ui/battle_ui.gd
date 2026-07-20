extends Control

const UnitSlotTexture: Texture2D = preload("res://assets/ui/battle/battle_unit_wait.tres")
const TargetArrowTexture: Texture2D = preload("res://assets/ui/common/mini_arrow_b.tres")
const MagicScene = preload("res://features/shared/Skill.tscn")
const LIMIT_CRYSTAL_TEXTURE: Texture2D = preload("res://assets/ui/battle/battle_limit_crystal.png")
const LIMIT_CRYSTAL_ANIM_DURATION: float = 0.7
const GRID_TO_PARTY_MAP: Array[int] = [0, 3, 1, 4, 2, -1]
const SKILL_DISABLE_REASON_NONE: String = ""
const SKILL_DISABLE_REASON_LACK_MP: String = "lack_mp"
const SKILL_DISABLE_REASON_LACK_LIMIT: String = "lack_limit"
const SKILL_ROLE_STANDARD: String = "standard"
const SKILL_ROLE_LIMITBURST: String = "limitburst"
const SKILL_ROLE_ESPER: String = "esper_skill"
const SKILL_ROLE_MAGIC: String = "magic"
const SKILL_ROLE_ABILITY: String = "ability"

var current_mission_id: String = ""
var UnitPanelScene: PackedScene = preload("res://features/battle/ui/UnitPanel.tscn")

@onready var battle_manager: Node = %BattleManager
@onready var finish_button: Button = %FinishButton
@onready var rewards_popup: AcceptDialog = %RewardsPopup

@onready var enemy_region: Control = %EnemyRegion
@onready var enemies_container: Control = %EnemiesContainer
@onready var turn_label: Label = %TurnLabel
@onready var player_sprites_container: Control = %PlayerSpritesContainer
@onready var chain_count_label: Label = %ChainCountLabel
@onready var enemy_name_label: Label = %EnemyNameLabel
@onready var enemy_hp_bar: ProgressBar = %EnemyHPBar
@onready var enemy_hp_pct_label: Label = %EnemyHPPctLabel
@onready var bottom_ui_wrapper: Control = %BottomUIWrapper
var _original_unit_dot_positions: Dictionary = {}
var _unit_dot_covering_state: Dictionary = {}
const COVER_TARGET_POSITION: Vector2 = Vector2(260, 240)
@onready var bottom_section: GridContainer = %BottomSection
@onready var unit_info_popup: Control = %UnitInfoPopup
@onready var background: TextureRect = $Background
@onready var monster_hp_bar: Sprite2D = $BattleEnemyHpBar1
@onready var action_feedback_label: Label = %ActionFeedbackLabel
@onready var reload_button: TextureButton = %ReloadButtonDecor

const ACTION_FEEDBACK_DURATION: float = 1.5

## Enemy layout tuning. `dispPos` values from BATTLE_GROUP are authored in an
## abstract field space (observed roughly x:110-260, y:206-426); they are mapped
## proportionally into the EnemyRegion using DISP_REFERENCE as the assumed field
## size. Tweak DISP_REFERENCE to shift/scale the whole enemy arrangement.
const DISP_REFERENCE: Vector2 = Vector2(320, 480)
const ENEMY_WRAPPER_SIZE: Vector2 = Vector2(140, 140)
const ENEMY_REGION_FALLBACK_SIZE: Vector2 = Vector2(360, 400)
var _action_feedback_token: int = 0

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

var combat_inventory: CombatInventory = CombatInventory.new()
var _damage_numbers: DamageNumberSpawner

var _is_ally_targeting_mode: bool = false
var _pending_skill_action_id: String = ""
var _pending_skill_action_name: String = ""
var _pending_skill_action_type: int = 0
var _pending_action_payload: Dictionary = {}
var _cancel_target_button: Button

func _get_dynamic_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = tex
	return tex

func _exit_tree() -> void:
	# Prevent unbounded memory growth across repeated battle entries.
	_texture_cache.clear()
	if _damage_numbers:
		_damage_numbers.clear_pool()

func _ready() -> void:
	for i in range(player_sprites_container.get_child_count()):
		var dot = player_sprites_container.get_child(i)
		_original_unit_dot_positions[i] = dot.position
		_unit_dot_covering_state[i] = false
	# Block the Android hardware back button / Escape key during combat — the
	# scene has its own retreat/menu flow and accidental backing out would
	# desync battle state.
	set_meta("block_back_request", true)

	finish_button.pressed.connect(_on_finish_pressed)
	rewards_popup.confirmed.connect(_on_rewards_confirmed)

	battle_manager.battle_state_ready.connect(_on_battle_state_ready)
	battle_manager.enemy_hp_changed.connect(_on_enemy_hp_changed)
	battle_manager.turn_changed.connect(_on_turn_changed)
	battle_manager.wave_changed.connect(_on_wave_changed)
	battle_manager.attack_landed.connect(_on_attack_landed)
	battle_manager.wave_transition_started.connect(_on_wave_transition_started)
	battle_manager.item_dropped.connect(_on_item_dropped)
	battle_manager.limit_crystal_dropped.connect(_on_limit_crystal_dropped)
	battle_manager.item_refunded.connect(_on_item_refunded)
	battle_manager.unit_action_started.connect(_on_unit_action_started_feedback)
	battle_manager.enemy_action_started.connect(_on_enemy_action_started_feedback)

	reload_button.pressed.connect(_on_reload_pressed)

	MissionService.mission_completed.connect(_on_mission_completed)
	battle_manager.mission_failed.connect(_on_mission_failed)
	MissionService.mission_failed.connect(_on_mission_failed)

	
	_hit_flash = ColorRect.new()
	_hit_flash.color = Color(1.0, 0.0, 0.0, 0.0)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	enemy_region.add_child(_hit_flash)

	_setup_action_menu()
	_setup_cancel_target_button()
	_damage_numbers = DamageNumberSpawner.new(self)
	_init_combat_inventory()

func _enter_ally_selection_state(action_type: int, action_name: String, action_id: String, action_payload: Dictionary = {}) -> void:
	_is_ally_targeting_mode = true
	_pending_skill_action_type = action_type
	_pending_skill_action_name = action_name
	_pending_skill_action_id = action_id
	_pending_action_payload = action_payload.duplicate(true)

	if _cancel_target_button:
		_cancel_target_button.show()

	var resolution: Dictionary = action_payload.get("resolution", {})
	var targeting_meta: Dictionary = resolution.get("targeting", {})
	var targets_dead: bool = targeting_meta.get("targets_dead", false)
	var targets_living: bool = targeting_meta.get("targets_living", true)

	for p in _active_panels:
		var is_valid: bool = false
		var unit_idx: int = p._my_index
		if unit_idx >= 0 and unit_idx < battle_manager.party_data.size():
			var unit_data: Dictionary = battle_manager.party_data[unit_idx]
			if not unit_data.is_empty():
				var is_dead: bool = unit_data.get("current_hp", 0) <= 0
				if is_dead and targets_dead:
					is_valid = true
				elif not is_dead and targets_living:
					is_valid = true

		p.set_ally_targeting_mode(true, is_valid)

func _init_combat_inventory() -> void:
	combat_inventory.reload_from_services()

func _exit_ally_selection_state() -> void:
	_is_ally_targeting_mode = false
	_pending_skill_action_type = 0
	_pending_skill_action_name = ""
	_pending_skill_action_id = ""
	_pending_action_payload = {}

	if _cancel_target_button:
		_cancel_target_button.hide()

	# Reset panels visually
	for p in _active_panels:
		p.set_ally_targeting_mode(false)
		p.update_action_visuals()

func _queue_resolved_action(unit_index: int, action_type: int, action_name: String, resolution: Dictionary, should_consume_item: bool = true) -> bool:
	if resolution.is_empty():
		return false

	var action_payload: Dictionary = {
		"source_type": resolution.get("source_type", "skill"),
		"resolved_action_id": resolution.get("resolved_action_id", ""),
		"resolved_action_data": resolution.get("resolved_action_data", {}),
		"parsed_data": resolution.get("parsed_data", {})
	}

	if resolution.get("source_type", "") == "item":
		var original_item_id: String = str(resolution.get("original_item_id", ""))
		if should_consume_item:
			if not combat_inventory.consume(original_item_id):
				return false

		action_payload["is_item"] = true
		action_payload["original_item_id"] = original_item_id

	battle_manager.set_queued_action(
		unit_index,
		action_type,
		action_name,
		str(resolution.get("resolved_action_id", "")),
		action_payload
	)

	for p in _active_panels:
		if p._my_index == unit_index:
			p.update_action_visuals()

	return true

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
			var rarity = int(unit_inst.get("current_rarity", 1))
			var limitburst_id: String = str(unit_inst.get("limitBurstId", ""))

			var limitburst_data: Dictionary = GameDatabase.get_limitburst(limitburst_id) if limitburst_id != "" else {}
			if not limitburst_data.is_empty():
				options.append({
					"id": limitburst_id,
					"name": limitburst_data.get("name", "Unknown Limit Burst"),
					"skill_data": limitburst_data,
					"level": -1,
					"source_type": SKILL_ROLE_LIMITBURST,
					"source": ""
				})

			var esper_rank_skill: Dictionary = StatCalculator.get_active_party_esper_rank_skill(unit_inst)
			if not esper_rank_skill.is_empty():
				var esper_skill_data: Dictionary = esper_rank_skill.get("skill_data", {})
				options.append({
					"id": str(esper_rank_skill.get("skill_id", "")),
					"name": esper_rank_skill.get("name", "Unknown Esper Skill"),
					"skill_data": esper_skill_data,
					"level": -1,
					"source_type": SKILL_ROLE_ESPER,
					"source": "Esper"
				})

			# Read from the calculated profile so equipment- and esper-granted
			# skills (in addition to innate trait skills) appear in the menu.
			# StatCalculator already filters innate skills by rarity/level.
			var profile: Dictionary = unit_inst.get("final_stats", {})
			var profile_skills: Dictionary = profile.get("skills", {})
			var magic_entries: Array = profile_skills.get("magic", [])
			var ability_entries: Array = profile_skills.get("ability", [])

			for sk in magic_entries:
				var sk_id: String = str(int(sk.get("id", 0)))
				var magic_data = GameDatabase.get_magic(sk_id)
				if not magic_data.is_empty():
					options.append({
						"id": sk_id,
						"name": magic_data.get("name", "Unknown Magic"),
						"skill_data": magic_data,
						"level": rarity,
						"source_type": SKILL_ROLE_MAGIC,
						"source": str(sk.get("source", ""))
					})

			for sk in ability_entries:
				var sk_id: String = str(int(sk.get("id", 0)))
				var ability_data = GameDatabase.get_ability(sk_id)
				if not ability_data.is_empty():
					options.append({
						"id": sk_id,
						"name": ability_data.get("name", "Unknown Ability"),
						"skill_data": ability_data,
						"level": rarity,
						"source_type": SKILL_ROLE_ABILITY,
						"source": str(sk.get("source", ""))
					})

	_populate_action_menu(options, battle_manager.CombatAction.SKILL, true)

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

	for item_id in combat_inventory.entries().keys():
		var quantity: int = combat_inventory.quantity(item_id)
		if quantity > 0:
			var item_data: Dictionary = GameDatabase.get_item(int(item_id))
			if not item_data.is_empty():
				var item_name: String = item_data.get("name", "Unknown Item")
				options.append({
					"id": item_id,
					"name": item_name + " (x" + str(quantity) + ")",
					"item_data": item_data
				})

	_populate_action_menu(options, battle_manager.CombatAction.ITEM, false)

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

func _populate_action_menu(options: Array, action_type: int, is_skill: bool) -> void:
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
			var skill_data: Dictionary = opt.get("skill_data", {})
			var source_type: String = str(opt.get("source_type"))
			var source_name: String = str(opt.get("source", ""))
			var role_style: String = SKILL_ROLE_STANDARD
			var can_use_limitburst: bool = true
			var can_use_mp: bool = true
			var can_use_action: bool = true
			var disabled_reason: String = SKILL_DISABLE_REASON_NONE
			var source_unit: Dictionary = {}

			if _menu_target_unit_index >= 0 and _menu_target_unit_index < battle_manager.party_data.size():
				source_unit = battle_manager.party_data[_menu_target_unit_index]

			if source_type == SKILL_ROLE_LIMITBURST:
				role_style = SKILL_ROLE_LIMITBURST
				can_use_limitburst = false
				if not source_unit.is_empty():
					var current_limit: int = int(source_unit.get("limit_gauge", 0))
					var max_limit: int = int(source_unit.get("max_limit", 0))
					can_use_limitburst = max_limit > 0 and current_limit >= max_limit
				can_use_action = can_use_limitburst
				if not can_use_action:
					disabled_reason = SKILL_DISABLE_REASON_LACK_LIMIT
			elif source_type == SKILL_ROLE_ESPER:
				role_style = SKILL_ROLE_ESPER
				can_use_mp = _can_unit_pay_skill_mp(source_unit, skill_data)
				can_use_action = can_use_mp
				if not can_use_action:
					disabled_reason = SKILL_DISABLE_REASON_LACK_MP
			else:
				can_use_mp = _can_unit_pay_skill_mp(source_unit, skill_data)
				can_use_action = can_use_mp
				if not can_use_action:
					disabled_reason = SKILL_DISABLE_REASON_LACK_MP
			
			var btn = MagicScene.instantiate() #if skill_data.get("magic_type", "") != "" else SkillEntryButtonScene.instantiate()
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(btn)
			
			btn.setup_from_skill_data(skill_data, source_name, true)
			btn.set_skill_role_style(role_style)
			btn.set_action_availability(can_use_action, disabled_reason)

			btn.pressed.connect(func():
				if not can_use_action:
					return

				var resolution: Dictionary = {}
				if source_type == SKILL_ROLE_LIMITBURST:
					resolution = SkillResolver.resolve_combat_limitburst(action_id)
				elif source_type == SKILL_ROLE_ESPER:
					resolution = SkillResolver.resolve_esper_skill(skill_data)
				elif source_type == SKILL_ROLE_MAGIC:
					resolution = SkillResolver.resolve_combat_magic(action_id)
				elif source_type == SKILL_ROLE_ABILITY:
					resolution = SkillResolver.resolve_combat_ability(action_id)
				if resolution.is_empty():
					return

				if resolution.get("targeting", {}).get("needs_ally_selection", false):
					_enter_ally_selection_state(action_type, opt.get("name", ""), action_id, {
						"resolution": resolution
					})
					_close_action_menu()
				else:
					if _queue_resolved_action(_menu_target_unit_index, action_type, opt.get("name", ""), resolution, false):
						_close_action_menu()
			)
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
					var resolution: Dictionary = SkillResolver.resolve_combat_item(action_id)
					if resolution.is_empty():
						return

					if resolution.get("targeting", {}).get("needs_ally_selection", false):
						_enter_ally_selection_state(action_type, opt.get("name", ""), str(resolution.get("resolved_action_id", "")), {
							"resolution": resolution
						})
						_close_action_menu()
					else:
						if _queue_resolved_action(_menu_target_unit_index, action_type, opt.get("name", ""), resolution):
							_close_action_menu()
				else:
					var skill_resolution: Dictionary = SkillResolver.resolve_combat_skill(action_id)
					if _queue_resolved_action(_menu_target_unit_index, action_type, opt.get("name", ""), skill_resolution, false):
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

func _can_unit_pay_skill_mp(unit_data: Dictionary, skill_data: Dictionary) -> bool:
	if unit_data.is_empty():
		return false

	var current_mp: int = int(unit_data.get("current_mp", 0))
	var cost_value: Variant = skill_data.get("cost", {})
	var mp_cost: int = int(cost_value.get("MP", 0)) if cost_value is Dictionary else int(cost_value) if typeof(cost_value) in [TYPE_INT, TYPE_FLOAT] else 0
	return current_mp >= mp_cost


func _apply_battle_background_from_formatted_dungeon_name(formatted_name: String) -> void:
	if formatted_name == "":
		return

	var bg_path = "res://assets/battle_bg/%s.jpg" % formatted_name
	if ResourceLoader.exists(bg_path):
		background.texture = load(bg_path)
	else:
		push_warning("CombatUI: Background not found at %s" % bg_path)

func init_scene(params: Dictionary) -> void:
	# Yield one frame so any caller-side loading overlay can render before we
	# start synchronous data work (dataset eviction, mission lookup, sprite
	# allocation). This keeps the UI responsive on battle entry.
	await get_tree().process_frame
	# Free outgame-only static data (worlds, towns, summon boards, equip icons,
	# pattern tables) before combat allocates its own atlases/animations. Datasets
	# transparently re-load lazily if they're touched again later. Safe to call
	# every combat entry.
	StaticData.evict_outgame_only_datasets()
	current_mission_id = params.get("mission_id", "")
	var dungeon_id: String = params.get("dungeon_id", "")
	var formatted_name: String = ""

	if dungeon_id != "":
		var dungeon_name: String = GameDatabase.get_dungeon_name(dungeon_id)
		if dungeon_name != "":
			formatted_name = dungeon_name.replace(" ", "_")

	if formatted_name == "" and current_mission_id != "":
		var mission_data: Dictionary = MissionService.get_mission_data(str(current_mission_id))
		var mission_dungeon_id: String = str(int(mission_data.get("dungeon_id", "")))
		if mission_dungeon_id != "":
			var mission_dungeon_name: String = GameDatabase.get_dungeon_name(mission_dungeon_id)
			if mission_dungeon_name != "":
				formatted_name = mission_dungeon_name.replace(" ", "_")

	if formatted_name == "":
		formatted_name = MissionService.last_played_dungeon_name

	_apply_battle_background_from_formatted_dungeon_name(formatted_name)

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
		wrapper.custom_minimum_size = ENEMY_WRAPPER_SIZE
		wrapper.size = ENEMY_WRAPPER_SIZE
		wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
		# Position the wrapper from the monster's authored dispPos (BATTLE_GROUP),
		# falling back to an even vertical stagger when no position is available.
		wrapper.position = _compute_enemy_wrapper_position(
			i, battle_manager.enemy_units.size(), enemy_data.get("disp_pos", Vector2.ZERO))
		enemies_container.add_child(wrapper)

		var enemy_sprite = load("res://features/battle/ui/combat_sprite.gd").new()
		enemy_sprite.name = "EnemyCombatSprite_" + str(i)
		enemy_sprite.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		enemy_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		enemy_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)

		wrapper.add_child(enemy_sprite)
		enemy_sprite.setup(i, monster_id, true, battle_manager)

		var damage_container = Control.new()
		damage_container.name = "DamageContainer"
		damage_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		damage_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(damage_container)

		var target_arrow := TextureRect.new()
		target_arrow.name = "TargetArrow"
		target_arrow.texture = TargetArrowTexture
		target_arrow.custom_minimum_size = Vector2(48, 28)
		target_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target_arrow.anchor_left = 0.5
		target_arrow.anchor_right = 0.5
		target_arrow.anchor_top = 0.0
		target_arrow.anchor_bottom = 0.0
		target_arrow.offset_left = -24
		target_arrow.offset_right = 24
		target_arrow.offset_top = -32
		target_arrow.offset_bottom = -4
		target_arrow.visible = (i == 0)
		wrapper.add_child(target_arrow)

		# Connect click input for targeting (short tap) and info popup (long press)
		enemy_sprite.short_tapped.connect(_on_enemy_short_tapped)
		enemy_sprite.long_pressed.connect(_on_enemy_long_pressed)

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
	for dot in player_sprites_container.get_children():
		for child in dot.get_children():
			child.queue_free()

	_active_panels.clear()

	# Map the 6 UnitDot slots to the correct party indices:
	# UnitDot0 (Top Left)     -> Party index 0
	# UnitDot1 (Top Right)    -> Party index 3
	# UnitDot2 (Mid Left)     -> Party index 1
	# UnitDot3 (Mid Right)    -> Party index 4
	# UnitDot4 (Bot Left)     -> Party index 2
	# UnitDot5 (Bot Right)    -> Empty / -1

	for grid_idx in range(6):
		var party_idx = GRID_TO_PARTY_MAP[grid_idx]
		var has_unit = false

		var unit_data = {}
		if party_idx >= 0 and party_idx < battle_manager.party_data.size():
			unit_data = battle_manager.party_data[party_idx]
			if not unit_data.is_empty():
				has_unit = true

		# Create a visual placeholder in every slot first.
		var slot_node: Control = _create_slot_placeholder()
		bottom_section.add_child(slot_node)

		if has_unit:
			# Replace placeholder with functional panel when a unit exists.
			var panel: Node = UnitPanelScene.instantiate()
			bottom_section.remove_child(slot_node)
			slot_node.queue_free()
			bottom_section.add_child(panel)
			panel.setup(party_idx)
			panel.open_skill_menu.connect(_open_skill_menu)
			panel.open_item_menu.connect(_open_item_menu)
			panel.panel_tapped.connect(_on_panel_tapped)
			_active_panels.append(panel)

			# Add Combat Sprite to the corresponding UnitDot
			var template_id: String = str(unit_data.get("unitId"))
			var combat_sprite = load("res://features/battle/ui/combat_sprite.gd").new()
			combat_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			combat_sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			combat_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
			combat_sprite.setup(party_idx, template_id, false, battle_manager)
			combat_sprite.long_pressed.connect(_on_unit_info_tapped)

			player_sprites_container.get_child(grid_idx).add_child(combat_sprite)

			var damage_container := Control.new()
			damage_container.name = "DamageContainer"
			damage_container.set_anchors_preset(Control.PRESET_FULL_RECT)
			damage_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
			player_sprites_container.get_child(grid_idx).add_child(damage_container)

## Computes an enemy wrapper's top-left position inside `enemies_container`.
## When `disp_pos` is set (data-driven spawn), it is mapped proportionally from
## DISP_REFERENCE space into the region and centered on the wrapper. Otherwise an
## even vertical distribution with a horizontal stagger reproduces the legacy look.
func _compute_enemy_wrapper_position(i: int, count: int, disp_pos: Vector2) -> Vector2:
	var region_size: Vector2 = enemies_container.size
	if region_size.x <= 1.0 or region_size.y <= 1.0:
		region_size = enemy_region.size
	if region_size.x <= 1.0 or region_size.y <= 1.0:
		region_size = ENEMY_REGION_FALLBACK_SIZE

	var half: Vector2 = ENEMY_WRAPPER_SIZE * 0.5

	if disp_pos != Vector2.ZERO:
		var nx: float = clampf(disp_pos.x / DISP_REFERENCE.x, 0.0, 1.0)
		var ny: float = clampf(disp_pos.y / DISP_REFERENCE.y, 0.0, 1.0)
		return Vector2(nx * region_size.x, ny * region_size.y) - half

	# Legacy fallback: even vertical slots, centered, odd indices nudged right.
	var slot_h: float = region_size.y / float(max(count, 1))
	var pos: Vector2 = Vector2(region_size.x * 0.5, slot_h * (float(i) + 0.5)) - half
	if i % 2 != 0:
		pos.x += 30.0
	return pos

func _create_slot_placeholder() -> TextureRect:
	var placeholder := TextureRect.new()
	placeholder.texture = UnitSlotTexture
	placeholder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	placeholder.stretch_mode = TextureRect.STRETCH_SCALE
	placeholder.custom_minimum_size = Vector2(320, 116)
	placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return placeholder

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
		var fill_ratio: float = clampf(float(new_hp) / float(max_hp), 0.0, 1.0)
		monster_hp_bar.scale.x = fill_ratio
		
		enemy_hp_bar.max_value = max_hp
		enemy_hp_bar.value = new_hp
		enemy_hp_pct_label.text = "%d%%" % hp_percent

	if new_hp <= 0:
		if enemy_index >= 0 and enemy_index < enemies_container.get_child_count():
			var wrapper = enemies_container.get_child(enemy_index)
			if wrapper.get_child_count() > 0:
				var enemy_sprite = wrapper.get_child(0)
				_play_enemy_death(enemy_sprite)
			var arrow := wrapper.get_node_or_null("TargetArrow")
			if arrow:
				arrow.visible = false

		# If the dead enemy was the current target, advance the UI to the next
		# living enemy so the HP gauge and target arrow match what attacks will
		# actually hit (battle_manager._resolve_targets falls back to the first
		# living enemy when the queued target is dead).
		if enemy_index == _current_target_enemy_index:
			var next_index: int = _find_first_living_enemy_index()
			if next_index >= 0:
				_set_current_target_enemy(next_index)

func _find_first_living_enemy_index() -> int:
	for i in range(battle_manager.enemy_units.size()):
		var enemy_data: Dictionary = battle_manager.enemy_units[i]
		if enemy_data.get("current_hp", 0) > 0:
			return i
	return -1

func _set_current_target_enemy(enemy_index: int) -> void:
	if enemy_index < 0 or enemy_index >= battle_manager.enemy_units.size():
		return

	_current_target_enemy_index = enemy_index

	# Apply this target to all player units (mirrors _on_enemy_clicked).
	for i in range(battle_manager.party_data.size()):
		var unit_data = battle_manager.party_data[i]
		if not unit_data.is_empty():
			unit_data["queued_target_team"] = "enemy"
			unit_data["queued_target_index"] = enemy_index

	# Refresh info bar (name + HP gauge) for the new target.
	var enemy_data: Dictionary = battle_manager.enemy_units[enemy_index]
	enemy_name_label.text = enemy_data.get("name", "Unknown Monster")
	battle_manager.set_enemy_hp(enemy_index, enemy_data.get("current_hp", 0))

	_refresh_target_arrow()

func _on_unit_info_tapped(unit_index: int) -> void:
	if unit_index >= 0 and unit_index < battle_manager.party_data.size():
		var unit_data = battle_manager.party_data[unit_index]
		unit_info_popup.setup(unit_data)
		unit_info_popup.move_to_front()
		unit_info_popup.show()

func _on_panel_tapped(unit_index: int) -> void:
	if _is_ally_targeting_mode:
		# Validate both source and target indices before touching party_data
		if _menu_target_unit_index < 0 or _menu_target_unit_index >= battle_manager.party_data.size():
			_exit_ally_selection_state()
			return
		if unit_index < 0 or unit_index >= battle_manager.party_data.size():
			_exit_ally_selection_state()
			return

		# Check if the tapped panel is marked as a valid target
		for p in _active_panels:
			if p._my_index == unit_index:
				if not p.is_valid_target:
					return
				break

		var unit_data: Dictionary = battle_manager.party_data[_menu_target_unit_index]
		if not unit_data.is_empty():
			unit_data["queued_target_team"] = "player"
			unit_data["queued_target_index"] = unit_index

			var resolution: Dictionary = _pending_action_payload.get("resolution", {})
			_queue_resolved_action(_menu_target_unit_index, _pending_skill_action_type, _pending_skill_action_name, resolution)

		_exit_ally_selection_state()
	else:
		if unit_index in battle_manager.player_units_acted_this_turn:
			return
		# Normal execution
		battle_manager.execute_queued_action(unit_index)

func _on_enemy_short_tapped(enemy_index: int) -> void:
	if _is_ally_targeting_mode:
		_exit_ally_selection_state()
		return

	if OS.is_debug_build():
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

	_refresh_target_arrow()

func _on_enemy_long_pressed(enemy_index: int) -> void:
	if enemy_index >= 0 and enemy_index < battle_manager.enemy_units.size():
		var enemy_data = battle_manager.enemy_units[enemy_index]
		unit_info_popup.setup(enemy_data)
		unit_info_popup.move_to_front()
		unit_info_popup.show()

func _on_enemy_clicked(event: InputEvent, enemy_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_enemy_short_tapped(enemy_index)

func _refresh_target_arrow() -> void:
	for i in range(enemies_container.get_child_count()):
		var wrapper := enemies_container.get_child(i)
		var arrow := wrapper.get_node_or_null("TargetArrow")
		if arrow:
			arrow.visible = (i == _current_target_enemy_index)

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

func _on_attack_landed(target_team: String, target_index: int, damage: int, chain_count: int, receipt_type: String) -> void:
	chain_count_label.text = "Chain: %d" % chain_count
	if target_team == "enemy":
		if target_index >= 0 and target_index < enemies_container.get_child_count():
			var wrapper = enemies_container.get_child(target_index)
			if wrapper.get_child_count() > 0:
				var enemy_sprite = wrapper.get_child(0)
				_shake_enemy(enemy_sprite)
		_spawn_damage_number(damage, target_index)
	elif target_team == "player":
		var player_sprite: Control = _find_player_combat_sprite(target_index)
		if receipt_type == "DAMAGE":
			if player_sprite != null:
				_shake_enemy(player_sprite)
			_spawn_player_damage_number(damage, target_index)

func _spawn_damage_number(damage: int, target_index: int) -> void:
	if target_index < 0 or target_index >= enemies_container.get_child_count():
		return

	var wrapper = enemies_container.get_child(target_index)
	var damage_container = wrapper.get_node_or_null("DamageContainer")
	if not damage_container:
		return
	_damage_numbers.spawn(damage, damage_container)

func _spawn_player_damage_number(damage: int, party_index: int) -> void:
	if party_index < 0:
		return

	var damage_container: Control = _find_player_damage_container(party_index)
	if damage_container == null:
		return

	_damage_numbers.spawn(damage, damage_container)

func _find_player_damage_container(party_index: int) -> Control:
	for grid_idx in range(min(player_sprites_container.get_child_count(), GRID_TO_PARTY_MAP.size())):
		if GRID_TO_PARTY_MAP[grid_idx] != party_index:
			continue
		var slot: Node = player_sprites_container.get_child(grid_idx)
		var damage_container: Control = slot.get_node_or_null("DamageContainer") as Control
		if damage_container == null:
			damage_container = Control.new()
			damage_container.name = "DamageContainer"
			damage_container.set_anchors_preset(Control.PRESET_FULL_RECT)
			damage_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(damage_container)
		return damage_container
	return null

func _on_turn_changed(new_turn: int) -> void:
	turn_label.text = "Turn %d" % new_turn
	chain_count_label.text = "Chain: 0"
	# Reset panels visually
	for p in _active_panels:
		p.is_ally_targeting_mode = false
		p.modulate = Color(1.0, 1.0, 1.0, 1.0)
		p.update_action_visuals()

func _on_wave_changed() -> void:
	chain_count_label.text = "Chain: 0"
	# Reset panels visually
	for p in _active_panels:
		p.is_ally_targeting_mode = false
		p.modulate = Color(1.0, 1.0, 1.0, 1.0)
		p.update_action_visuals()

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
	combat_inventory.refund(item_id)

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
	var item_data = GameDatabase.get_item(int(item_id))
	if not item_data.is_empty():
		if item_data.has("iconFile"):
			tex_path = "res://assets/items/" + str(item_data["iconFile"])

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

func _find_player_combat_sprite(party_index: int) -> Control:
	for slot in player_sprites_container.get_children():
		for child in slot.get_children():
			if child.get("party_index") == party_index:
				return child as Control
	return null

func _on_limit_crystal_dropped(enemy_index: int, target_unit_index: int) -> void:
	if enemy_index < 0 or enemy_index >= enemies_container.get_child_count():
		return

	var enemy_wrapper: Node = enemies_container.get_child(enemy_index)
	if enemy_wrapper.get_child_count() <= 0:
		return

	var enemy_sprite: Control = enemy_wrapper.get_child(0) as Control
	if enemy_sprite == null:
		return

	var target_sprite: Control = _find_player_combat_sprite(target_unit_index)
	if target_sprite == null:
		return

	var crystal_sprite := TextureRect.new()
	crystal_sprite.texture = LIMIT_CRYSTAL_TEXTURE
	crystal_sprite.custom_minimum_size = Vector2(28, 28)
	crystal_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crystal_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crystal_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(crystal_sprite)

	var start_pos: Vector2 = enemy_sprite.global_position + Vector2(36, -14)
	var end_pos: Vector2 = target_sprite.global_position + Vector2(22, 14)
	crystal_sprite.global_position = start_pos

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(crystal_sprite, "global_position", end_pos, LIMIT_CRYSTAL_ANIM_DURATION)
	tween.parallel().tween_property(crystal_sprite, "scale", Vector2(0.85, 0.85), LIMIT_CRYSTAL_ANIM_DURATION)
	tween.tween_property(crystal_sprite, "modulate:a", 0.0, 0.15)
	tween.tween_callback(crystal_sprite.queue_free)

func _on_wave_transition_started(curr_wave: int, next_wave: int, total_waves: int) -> void:
	# Defensive: if the player was mid-skill-targeting when the wave cleared,
	# drop pending targeting state so it can't leak into the next wave.
	if _is_ally_targeting_mode:
		_exit_ally_selection_state()

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
	tween.parallel().tween_property(current_num, "position:y", -60, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
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

func _on_mission_completed(result: Dictionary) -> void:
	AudioService.play_music("res://assets/audio/bgm/la009_battleend.wav", false)
	var sequence = preload("res://features/battle/ui/MissionResultSequence.tscn").instantiate()
	add_child(sequence)
	sequence.start(result, battle_manager.party_data)
	sequence.finished.connect(_on_result_sequence_finished)

func _on_mission_failed(error_msg: String = "") -> void:
	push_error("Failed to complete mission: %s" % error_msg)
	AudioService.play_music("res://assets/audio/bgm/la009_battleend.wav", false)
	rewards_popup.dialog_text = "Mission Failed!"
	rewards_popup.popup_centered()

func _on_rewards_confirmed() -> void:
	UIManager.pop()

func _on_result_sequence_finished() -> void:
	UIManager.pop()

func _on_unit_action_started_feedback(unit_index: int, action: int) -> void:
	var text: String = ""
	match action:
		battle_manager.CombatAction.ATTACK:
			text = "Attack"
		battle_manager.CombatAction.DEFEND:
			text = "Defend"
		battle_manager.CombatAction.SKILL, battle_manager.CombatAction.ITEM:
			if unit_index >= 0 and unit_index < battle_manager.party_data.size():
				var unit: Dictionary = battle_manager.party_data[unit_index]
				text = str(unit.get("queued_action_name", ""))
			if text == "":
				text = "Skill" if action == battle_manager.CombatAction.SKILL else "Item"
	if text != "":
		var unit_name: String = ""
		if unit_index >= 0 and unit_index < battle_manager.party_data.size():
			unit_name = str(battle_manager.party_data[unit_index].get("name", ""))
		if unit_name != "":
			text = "%s - %s" % [unit_name, text]
		_show_action_feedback(text)

func _on_enemy_action_started_feedback(enemy_index: int, _action: int) -> void:
	var text: String = "Enemy attacks"
	if enemy_index >= 0 and enemy_index < battle_manager.enemy_units.size():
		var enemy: Dictionary = battle_manager.enemy_units[enemy_index]
		var enemy_name: String = str(enemy.get("enemy_name", ""))
		if enemy_name != "":
			text = "%s attacks" % enemy_name
	_show_action_feedback(text)

func _show_action_feedback(text: String) -> void:
	if action_feedback_label == null:
		return
	action_feedback_label.text = text
	action_feedback_label.visible = true
	action_feedback_label.modulate.a = 1.0
	_action_feedback_token += 1
	var token: int = _action_feedback_token
	await get_tree().create_timer(ACTION_FEEDBACK_DURATION).timeout
	if token == _action_feedback_token and action_feedback_label != null:
		action_feedback_label.visible = false

func _on_reload_pressed() -> void:
	if _is_ally_targeting_mode:
		return
	if battle_manager.current_state != battle_manager.BattleState.PLAYER_TURN:
		return

	var acted: Array = battle_manager.player_units_acted_this_turn
	var requeued_any: bool = false

	for unit_index in range(battle_manager.party_data.size()):
		if unit_index in acted:
			continue
		var unit_data: Dictionary = battle_manager.party_data[unit_index]
		if unit_data.is_empty():
			continue
		if int(unit_data.get("current_hp", 0)) <= 0:
			continue
		if not unit_data.has("last_action"):
			continue

		var last_action: int = int(unit_data.get("last_action", battle_manager.CombatAction.ATTACK))
		var last_name: String = str(unit_data.get("last_action_name", ""))
		var last_id: String = str(unit_data.get("last_action_id", ""))
		var last_payload_src: Dictionary = unit_data.get("last_payload", {})
		var last_payload: Dictionary = last_payload_src.duplicate(true)
		var last_target_team: String = str(unit_data.get("last_target_team", "enemy"))
		var last_target_index: int = int(unit_data.get("last_target_index", 0))

		# Items: only repeat if we still have at least one in the combat inventory; consume one now.
		if last_action == battle_manager.CombatAction.ITEM:
			var item_id: String = str(last_payload.get("original_item_id", ""))
			if item_id == "":
				continue
			if not combat_inventory.consume(item_id):
				continue

		battle_manager.set_queued_action(unit_index, last_action, last_name, last_id, last_payload)
		unit_data["queued_target_team"] = last_target_team
		unit_data["queued_target_index"] = last_target_index
		requeued_any = true

	if requeued_any:
		for p in _active_panels:
			p.update_action_visuals()
		_show_action_feedback("Reload last actions")


func _process(_delta: float) -> void:
	if not battle_manager or battle_manager.party_data.is_empty():
		return

	for grid_idx in range(min(player_sprites_container.get_child_count(), GRID_TO_PARTY_MAP.size())):
		var party_idx = GRID_TO_PARTY_MAP[grid_idx]
		if party_idx < 0 or party_idx >= battle_manager.party_data.size():
			continue

		var unit_data: Dictionary = battle_manager.party_data[party_idx]
		if unit_data.is_empty():
			continue

		var transient: Dictionary = unit_data.get("transient_turn_state", {})
		var is_aoe_covering: bool = bool(transient.get(CoverSystem.STATE_AOE, false))

		var currently_covering: bool = _unit_dot_covering_state.get(grid_idx, false)

		if is_aoe_covering != currently_covering:
			_unit_dot_covering_state[grid_idx] = is_aoe_covering
			var dot = player_sprites_container.get_child(grid_idx)
			var target_pos: Vector2 = _original_unit_dot_positions[grid_idx]
			if is_aoe_covering:
				target_pos = COVER_TARGET_POSITION

			var tween = create_tween().bind_node(dot)
			tween.tween_property(dot, "position", target_pos, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
