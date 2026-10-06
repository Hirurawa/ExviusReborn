class_name BattleMenus
extends Control

## The battle screen's bottom area, on %BottomUIWrapper: one UnitPanel per party member
## (a slot frame where the party has none), the skill menu sliding in from the left and
## the item menu from the right (each closed by a swipe back the way it came, or Back),
## and picking an ally for a skill or item, with its Cancel button. It draws what the
## battle screen gives it (BattleCommandMenu's options) and reports what the player
## chose. While the screen builds a multicast it redraws the open menu with each pick.

## Swipe up or down on a panel: UnitPanel.ATTACK or UnitPanel.DEFEND.
signal command_chosen(unit_id: int, command: StringName)
## A tap on a panel while no ally is being picked: act.
signal unit_tapped(unit_id: int)
signal skill_menu_requested(unit_id: int)
signal item_menu_requested(unit_id: int)
## An enabled option of the open menu was pressed.
signal option_picked(unit_id: int, option: Dictionary)
signal ally_picked(target_id: int)
signal ally_pick_cancelled
## The player closed the open menu (Back, or the swipe), not the screen.
signal menu_dismissed

const UnitPanelScene: PackedScene = preload("res://features/battle/ui/UnitPanel.tscn")
const SkillButtonScene: PackedScene = preload("res://features/shared/Skill.tscn")
const UnitSlotTexture: Texture2D = preload("res://assets/ui/battle/battle_unit_wait.tres")

const MENU_SKILL: StringName = &"skill"
const MENU_ITEM: StringName = &"item"
const SWIPE_THRESHOLD: float = 20.0
const SLIDE_SECONDS: float = 0.2
const SLOT_SIZE: Vector2 = Vector2(320, 116)
const PANEL_COUNT: int = 6

## MENU_SKILL, MENU_ITEM, or &"" when no menu is open, and whose menu it is.
var open_menu: StringName = &""
var menu_unit_id: int = -1

@onready var _section: GridContainer = $BottomSection

## Unit id -> UnitPanel.
var _panels: Dictionary = {}
var _picking: bool = false
var _menu_panel: PanelContainer
var _menu_box: VBoxContainer
var _menu_tween: Tween
var _dragging_menu: bool = false
var _menu_drag_start: Vector2 = Vector2.ZERO
var _cancel_button: Button


func _ready() -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_panel.hide()
	_menu_panel.gui_input.connect(_on_menu_gui_input)
	_menu_box = VBoxContainer.new()
	_menu_panel.add_child(_menu_box)
	add_child(_menu_panel)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel Target"
	_cancel_button.custom_minimum_size = Vector2(200, 60)
	_cancel_button.hide()
	_cancel_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_cancel_button.position.y = -80  # above the panels
	_cancel_button.pressed.connect(cancel_ally_pick)
	add_child(_cancel_button)


## One panel per member, { id, slot, template_id }, in the dots' slot order
## (PartyField.GRID_TO_PARTY_MAP); a slot frame for each slot without one.
func build(members: Array) -> void:
	for child in _section.get_children():
		_section.remove_child(child)
		child.queue_free()
	_panels.clear()
	var by_slot: Dictionary = {}
	for member in members:
		by_slot[int(member["slot"])] = member
	for grid_index in range(PANEL_COUNT):
		var member: Dictionary = by_slot.get(PartyField.GRID_TO_PARTY_MAP[grid_index], {})
		if member.is_empty():
			_section.add_child(_slot_placeholder())
			continue
		var unit_id: int = int(member["id"])
		var unit_panel: UnitPanel = UnitPanelScene.instantiate()
		_section.add_child(unit_panel)
		unit_panel.setup(int(member["slot"]), str(member.get("template_id", "")))
		unit_panel.command_chosen.connect(func(_slot: int, command: StringName) -> void: command_chosen.emit(unit_id, command))
		unit_panel.open_skill_menu.connect(func(_slot: int) -> void: skill_menu_requested.emit(unit_id))
		unit_panel.open_item_menu.connect(func(_slot: int) -> void: item_menu_requested.emit(unit_id))
		unit_panel.panel_tapped.connect(func(_slot: int) -> void: _on_panel_tapped(unit_id))
		_panels[unit_id] = unit_panel


## The panel of `unit_id`, or null.
func panel(unit_id: int) -> UnitPanel:
	return _panels.get(unit_id, null)


# === Menus ===

## Each option is BattleCommandMenu.options(): a Skill button per option, greyed with
## its overlay when disabled. Slides in from the left.
func show_skill_menu(unit_id: int, options: Array[Dictionary]) -> void:
	menu_unit_id = unit_id
	_fill_menu(options, true)
	_slide_in(MENU_SKILL)


## Each option is BattleCommandMenu.item_options(): a button with the item's name and
## how many the unit can pick. Slides in from the right.
func show_item_menu(unit_id: int, options: Array[Dictionary]) -> void:
	menu_unit_id = unit_id
	_fill_menu(options, false)
	_slide_in(MENU_ITEM)


## Redraws the open menu with fresh options (counts and greyed buttons change as the
## battle goes on).
func refresh_menu(options: Array[Dictionary]) -> void:
	if open_menu != &"":
		_fill_menu(options, open_menu == MENU_SKILL)


func close_menu() -> void:
	if open_menu == &"":
		return
	var target_x: float = -size.x if open_menu == MENU_SKILL else size.x
	_restart_menu_tween()
	_menu_tween.tween_property(_menu_panel, "position:x", target_x, SLIDE_SECONDS)
	_menu_tween.finished.connect(func() -> void:
		_menu_panel.hide()
		open_menu = &""
		menu_unit_id = -1)


func _slide_in(kind: StringName) -> void:
	open_menu = kind
	_menu_panel.position.x = -size.x if kind == MENU_SKILL else size.x
	_menu_panel.show()
	_restart_menu_tween()
	_menu_tween.tween_property(_menu_panel, "position:x", 0.0, SLIDE_SECONDS)


func _restart_menu_tween() -> void:
	if _menu_tween and _menu_tween.is_valid():
		_menu_tween.kill()
	_menu_tween = create_tween()
	_menu_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _fill_menu(options: Array[Dictionary], skills: bool) -> void:
	for child in _menu_box.get_children():
		_menu_box.remove_child(child)
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_box.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	for option in options:
		var enabled: bool = str(option.get("disabled_reason", "")) == ""
		if skills:
			var skill_button: Control = SkillButtonScene.instantiate()
			skill_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(skill_button)
			var skill: BattleSkill = option["skill"]
			skill_button.setup_from_skill_data(skill.record, str(option.get("source", "")), int(option.get("awaken_level", 0)), true)
			if str(option.get("role_style", "")) != BattleCommandMenu.ROLE_STANDARD:
				skill_button.set_skill_role_style(str(option["role_style"]))
			skill_button.set_action_availability(enabled, str(option.get("disabled_reason", "")))
			skill_button.pressed.connect(_on_option_pressed.bind(option, enabled))
		else:
			var item_button: Button = _item_button(str(option.get("name", "")), "x%d" % int(option.get("count", 0)))
			item_button.disabled = not enabled
			item_button.pressed.connect(_on_option_pressed.bind(option, enabled))
			grid.add_child(item_button)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	_menu_box.add_child(bottom)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_dismiss_menu)
	bottom.add_child(back)


func _on_option_pressed(option: Dictionary, enabled: bool) -> void:
	if enabled and open_menu != &"":
		option_picked.emit(menu_unit_id, option)


## A swipe back the way the menu came closes it: left for skills, right for items.
func _on_menu_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if not _dragging_menu and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or event is InputEventScreenDrag):
			_dragging_menu = true
			_menu_drag_start = event.position
		elif _dragging_menu:
			var delta: Vector2 = event.position - _menu_drag_start
			if abs(delta.x) > abs(delta.y) and abs(delta.x) > SWIPE_THRESHOLD:
				if (open_menu == MENU_SKILL and delta.x < 0.0) or (open_menu == MENU_ITEM and delta.x > 0.0):
					_dismiss_menu()
					_dragging_menu = false
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_menu = false
	elif event is InputEventScreenTouch and not event.pressed:
		_dragging_menu = false


func _dismiss_menu() -> void:
	if open_menu == &"":
		return
	close_menu()
	menu_dismissed.emit()


static func _item_button(item_name: String, sub_text: String) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 50)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)

	var name_label := Label.new()
	name_label.text = item_name
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_child(name_label)

	var sub_label := Label.new()
	sub_label.text = sub_text
	sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	text.add_child(sub_label)
	return button


static func _slot_placeholder() -> TextureRect:
	var placeholder := TextureRect.new()
	placeholder.texture = UnitSlotTexture
	placeholder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	placeholder.stretch_mode = TextureRect.STRETCH_SCALE
	placeholder.custom_minimum_size = SLOT_SIZE
	placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return placeholder


# === Picking an ally ===

## Highlights the panels of `valid_ids` for an ally pick and shows Cancel. A tap on a
## highlighted panel emits ally_picked; Cancel, or cancel_ally_pick(), ends it.
func begin_ally_pick(valid_ids: Array) -> void:
	_picking = true
	_cancel_button.show()
	for unit_id in _panels:
		(_panels[unit_id] as UnitPanel).set_ally_targeting_mode(true, valid_ids.has(unit_id))


func is_picking_ally() -> bool:
	return _picking


func cancel_ally_pick() -> void:
	if not _picking:
		return
	_end_ally_pick()
	ally_pick_cancelled.emit()


func _end_ally_pick() -> void:
	_picking = false
	_cancel_button.hide()
	for unit_id in _panels:
		(_panels[unit_id] as UnitPanel).set_ally_targeting_mode(false)


func _on_panel_tapped(unit_id: int) -> void:
	if not _picking:
		unit_tapped.emit(unit_id)
		return
	if not (_panels[unit_id] as UnitPanel).is_valid_target:
		return
	_end_ally_pick()
	ally_picked.emit(unit_id)
