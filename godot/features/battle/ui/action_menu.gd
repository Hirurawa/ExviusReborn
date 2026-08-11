extends PanelContainer
class_name ActionMenu

## The in-combat skill / item selection panel. Slides in from the left for skills
## and from the right for items, and can be dismissed by swiping back the way it
## came. Builds its option list from the target unit's calculated profile
## (limit burst, esper rank skill, magic, abilities) or from the combat inventory.
##
## The menu only *selects*: it resolves the chosen action and emits it. The owning
## battle UI performs the actual queueing (it owns the inventory consumption and
## panel refresh) and calls close() once the action was accepted.
##
## Usage:
##   var menu := ActionMenu.new()
##   menu.setup(battle_manager, combat_inventory)
##   bottom_ui_wrapper.add_child(menu)
##   menu.action_chosen.connect(...)
##   menu.ally_selection_requested.connect(...)

const MagicScene: PackedScene = preload("res://features/shared/Skill.tscn")

const MENU_NONE: String = ""
const MENU_SKILL: String = "SKILL"
const MENU_ITEM: String = "ITEM"

const SLIDE_DURATION: float = 0.2
const SWIPE_THRESHOLD: float = 20.0

## The player picked a usable action. `consume_item` distinguishes item picks
## (which must decrement the combat inventory) from skill picks.
signal action_chosen(unit_index: int, action_type: int, action_name: String, resolution: Dictionary, consume_item: bool)
## The chosen action needs the player to pick an ally before it can be queued.
signal ally_selection_requested(unit_index: int, action_type: int, action_name: String, action_id: String, resolution: Dictionary)

var target_unit_index: int = -1
var current_menu: String = MENU_NONE

var _battle_manager: Node
var _combat_inventory: CombatInventory
var _vbox: VBoxContainer
var _tween: Tween
var _is_dragging: bool = false
var _drag_start_position: Vector2


func setup(battle_manager: Node, combat_inventory: CombatInventory) -> void:
	_battle_manager = battle_manager
	_combat_inventory = combat_inventory


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	hide()
	gui_input.connect(_on_gui_input)

	_vbox = VBoxContainer.new()
	add_child(_vbox)


func is_open() -> bool:
	return current_menu != MENU_NONE


func open_skill_menu(unit_index: int) -> void:
	target_unit_index = unit_index
	_populate(_build_skill_options(unit_index), _battle_manager.CombatAction.SKILL, true)
	current_menu = MENU_SKILL
	_slide_in_from(-_parent_width())


func open_item_menu(unit_index: int) -> void:
	target_unit_index = unit_index
	_populate(_build_item_options(), _battle_manager.CombatAction.ITEM, false)
	current_menu = MENU_ITEM
	_slide_in_from(_parent_width())


func close() -> void:
	if current_menu == MENU_NONE:
		return

	var target_x: float = -_parent_width() if current_menu == MENU_SKILL else _parent_width()
	_restart_tween()
	_tween.tween_property(self, "position:x", target_x, SLIDE_DURATION)
	_tween.finished.connect(func():
		hide()
		current_menu = MENU_NONE
	)


func _parent_width() -> float:
	var parent := get_parent() as Control
	return parent.size.x if parent != null else size.x


func _restart_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _slide_in_from(offscreen_x: float) -> void:
	position.x = offscreen_x
	show()
	_restart_tween()
	_tween.tween_property(self, "position:x", 0.0, SLIDE_DURATION)


## Swipe the menu back the way it came in to dismiss it.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if not _is_dragging and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or event is InputEventScreenDrag):
			_is_dragging = true
			_drag_start_position = event.position
		elif _is_dragging:
			var delta: Vector2 = event.position - _drag_start_position
			if abs(delta.x) > abs(delta.y) and abs(delta.x) > SWIPE_THRESHOLD:
				if current_menu == MENU_SKILL and delta.x < -SWIPE_THRESHOLD:
					close()
					_is_dragging = false
				elif current_menu == MENU_ITEM and delta.x > SWIPE_THRESHOLD:
					close()
					_is_dragging = false

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_is_dragging = false
	elif event is InputEventScreenTouch and not event.pressed:
		_is_dragging = false


## Limit burst + esper rank skill + the unit's calculated magic/ability lists.
## Reads from final_stats so equipment- and esper-granted skills (in addition to
## innate trait skills) appear; StatCalculator already filters by rarity/level.
func _build_skill_options(unit_index: int) -> Array:
	var options: Array = []
	if unit_index < 0 or unit_index >= _battle_manager.party_data.size():
		return options
	var unit_inst: Dictionary = _battle_manager.party_data[unit_index]
	if unit_inst.is_empty():
		return options

	var rarity: int = int(unit_inst.get("current_rarity", 1))
	var limitburst_id: String = str(unit_inst.get("limitBurstId", ""))

	var limitburst_data: Dictionary = GameDatabase.get_limitburst(limitburst_id) if limitburst_id != "" else {}
	if not limitburst_data.is_empty():
		options.append({
			"id": limitburst_id,
			"name": limitburst_data.get("name", "Unknown Limit Burst"),
			"skill_data": limitburst_data,
			"level": -1,
			"source_type": SkillUsage.SKILL_ROLE_LIMITBURST,
			"source": ""
		})

	var esper_rank_skill: Dictionary = StatCalculator.get_active_party_esper_rank_skill(unit_inst)
	if not esper_rank_skill.is_empty():
		options.append({
			"id": str(esper_rank_skill.get("skill_id", "")),
			"name": esper_rank_skill.get("name", "Unknown Esper Skill"),
			"skill_data": esper_rank_skill.get("skill_data", {}),
			"level": -1,
			"source_type": SkillUsage.SKILL_ROLE_ESPER,
			"source": "Esper"
		})

	var profile_skills: Dictionary = unit_inst.get("final_stats", {}).get("skills", {})

	for sk in profile_skills.get("magic", []):
		var magic_id: String = str(int(sk.get("id", 0)))
		var magic_data: Dictionary = GameDatabase.get_magic(magic_id)
		if not magic_data.is_empty():
			options.append({
				"id": magic_id,
				"name": magic_data.get("name", "Unknown Magic"),
				"skill_data": magic_data,
				"level": rarity,
				"source_type": SkillUsage.SKILL_ROLE_MAGIC,
				"source": str(sk.get("source", ""))
			})

	for sk in profile_skills.get("ability", []):
		var ability_id: String = str(int(sk.get("id", 0)))
		var ability_data: Dictionary = GameDatabase.get_ability(ability_id)
		if not ability_data.is_empty():
			options.append({
				"id": ability_id,
				"name": ability_data.get("name", "Unknown Ability"),
				"skill_data": ability_data,
				"level": rarity,
				"source_type": SkillUsage.SKILL_ROLE_ABILITY,
				"source": str(sk.get("source", ""))
			})

	return options


func _build_item_options() -> Array:
	var options: Array = []
	for item_id in _combat_inventory.entries().keys():
		var quantity: int = _combat_inventory.quantity(item_id)
		if quantity <= 0:
			continue
		var item_data: Dictionary = GameDatabase.get_item(int(item_id))
		if item_data.is_empty():
			continue
		options.append({
			"id": item_id,
			"name": "%s (x%d)" % [item_data.get("name", "Unknown Item"), quantity],
			"item_data": item_data
		})
	return options


func _populate(options: Array, action_type: int, is_skill: bool) -> void:
	for child in _vbox.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	for opt in options:
		grid.add_child(_build_skill_entry(opt, action_type) if is_skill else _build_item_entry(opt, action_type))

	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_END
	_vbox.add_child(bottom_hbox)

	var cancel_btn := Button.new()
	cancel_btn.text = "Back"
	cancel_btn.pressed.connect(close)
	bottom_hbox.add_child(cancel_btn)


func _build_skill_entry(opt: Dictionary, action_type: int) -> Control:
	var action_id: String = opt.get("id", "")
	var action_name: String = opt.get("name", "")
	var skill_data: Dictionary = opt.get("skill_data", {})
	var source_type: String = str(opt.get("source_type"))

	var role_style: String = SkillUsage.SKILL_ROLE_STANDARD
	if source_type == SkillUsage.SKILL_ROLE_LIMITBURST:
		role_style = SkillUsage.SKILL_ROLE_LIMITBURST
	elif source_type == SkillUsage.SKILL_ROLE_ESPER:
		role_style = SkillUsage.SKILL_ROLE_ESPER

	var source_unit: Dictionary = {}
	if target_unit_index >= 0 and target_unit_index < _battle_manager.party_data.size():
		source_unit = _battle_manager.party_data[target_unit_index]

	var disabled_reason: String = SkillUsage.skill_disabled_reason(source_unit, source_type, skill_data)
	var can_use_action: bool = disabled_reason == SkillUsage.SKILL_DISABLE_REASON_NONE

	var btn: Control = MagicScene.instantiate()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.setup_from_skill_data(skill_data, str(opt.get("source", "")), true)
	btn.set_skill_role_style(role_style)
	btn.set_action_availability(can_use_action, disabled_reason)

	btn.pressed.connect(func():
		if not can_use_action:
			return
		_emit_selection(action_type, action_name, action_id, SkillUsage.resolve_action(source_type, action_id, skill_data), false)
	)
	return btn


func _build_item_entry(opt: Dictionary, action_type: int) -> Control:
	var action_id: String = opt.get("id", "")
	var action_name: String = opt.get("name", "")

	# Split the trailing " (xCount)" off the label so the count renders as subtext.
	var sub_text: String = "MP: --"
	var paren_idx: int = action_name.find(" (x")
	if paren_idx != -1:
		sub_text = action_name.substr(paren_idx + 2, action_name.length() - paren_idx - 3)
		action_name = action_name.left(paren_idx)

	var btn := _create_action_button(action_name, sub_text)
	btn.pressed.connect(func():
		if action_type == _battle_manager.CombatAction.ITEM:
			var resolution: Dictionary = SkillUsage.resolve_action(SkillUsage.SOURCE_TYPE_ITEM, action_id)
			_emit_selection(action_type, opt.get("name", ""), str(resolution.get("resolved_action_id", "")), resolution, true)
		else:
			_emit_selection(action_type, opt.get("name", ""), action_id, SkillUsage.resolve_action("skill", action_id), false)
	)
	return btn


## Routes a resolved pick either into ally-target selection or straight to the
## owner for queueing. No-op when the action could not be resolved.
func _emit_selection(action_type: int, action_name: String, action_id: String, resolution: Dictionary, consume_item: bool) -> void:
	if resolution.is_empty():
		return
	if resolution.get("targeting", {}).get("needs_ally_selection", false):
		ally_selection_requested.emit(target_unit_index, action_type, action_name, action_id, resolution)
	else:
		action_chosen.emit(target_unit_index, action_type, action_name, resolution, consume_item)


func _create_action_button(action_name: String, sub_text: String) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 50)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(40, 40)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_rect)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	var name_label := Label.new()
	name_label.text = action_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var sub_label := Label.new()
	sub_label.text = sub_text
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(sub_label)

	return btn
