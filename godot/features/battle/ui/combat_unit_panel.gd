extends PanelContainer

@onready var name_label: Label = %NameLabel
@onready var hp_label: Label = %HPLabel
@onready var mp_label: Label = %MPLabel
@onready var hp_bar: ProgressBar = %HPBar
@onready var mp_bar: ProgressBar = %MPBar
@onready var limit_bar: ProgressBar = %LimitBar
@onready var info_button: Button = %InfoButton

signal open_skill_menu(unit_index: int)
signal open_item_menu(unit_index: int)
signal panel_tapped(unit_index: int)
signal info_tapped(unit_index: int)

var _my_index: int = -1
var _is_dragging: bool = false
var _drag_start_position: Vector2 = Vector2.ZERO
var _current_queued_action: int = 0 # 0 is ATTACK
var _battle_manager: Node = null
var _has_acted: bool = false
var is_ally_targeting_mode: bool = false

func _ready() -> void:
	_battle_manager = get_tree().root.find_child("BattleManager", true, false)
	if _battle_manager:
		if not _battle_manager.unit_stats_updated.is_connected(_on_unit_stats_updated):
			_battle_manager.unit_stats_updated.connect(_on_unit_stats_updated)
		if not _battle_manager.unit_acted.is_connected(_on_unit_acted):
			_battle_manager.unit_acted.connect(_on_unit_acted)
		if not _battle_manager.turn_changed.is_connected(_on_turn_changed):
			_battle_manager.turn_changed.connect(_on_turn_changed)

	if info_button:
		info_button.pressed.connect(_on_info_button_pressed)

func _on_info_button_pressed() -> void:
	info_tapped.emit(_my_index)

func _gui_input(event: InputEvent) -> void:
	if not _battle_manager:
		return

	var has_acted = _my_index in _battle_manager.player_units_acted_this_turn

	if has_acted and not is_ally_targeting_mode:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = false
			_drag_start_position = event.position
		else:
			if not _is_dragging:
				panel_tapped.emit(_my_index)
			_is_dragging = false

	elif event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging = false
			_drag_start_position = event.position
		else:
			if not _is_dragging:
				panel_tapped.emit(_my_index)
			_is_dragging = false

	elif (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) or event is InputEventScreenDrag:
		if has_acted:
			return

		var diff = event.position - _drag_start_position
		if not _is_dragging:
			if abs(diff.y) > 20 and abs(diff.y) > abs(diff.x):
				_is_dragging = true
				if diff.y > 20: # Swipe down
					if _current_queued_action != _battle_manager.CombatAction.DEFEND:
						_current_queued_action = _battle_manager.CombatAction.DEFEND
						_battle_manager.set_queued_action(_my_index, _battle_manager.CombatAction.DEFEND)
						_update_visual_state()
				elif diff.y < -20: # Swipe up
					if _current_queued_action != _battle_manager.CombatAction.ATTACK:
						_current_queued_action = _battle_manager.CombatAction.ATTACK
						_battle_manager.set_queued_action(_my_index, _battle_manager.CombatAction.ATTACK)
						_update_visual_state()
			elif abs(diff.x) > 20 and abs(diff.x) > abs(diff.y):
				_is_dragging = true
				if diff.x > 20: # Swipe right
					open_skill_menu.emit(_my_index)
				elif diff.x < -20: # Swipe left
					open_item_menu.emit(_my_index)

func setup(unit_index: int) -> void:
	_my_index = unit_index
	_update_visual_state()
	if _battle_manager:
		_battle_manager.request_unit_stats(_my_index)

func _on_unit_acted(index: int) -> void:
	if index == _my_index:
		_has_acted = true
		modulate = Color(0.5, 0.5, 0.5, 1.0)
		name_label.text = name_label.text.split(" - ")[0] # Clean up action text

func _on_turn_changed(_new_turn: int) -> void:
	_has_acted = false
	_current_queued_action = 0 # ATTACK is 0, handled safely via variable initialization
	if _battle_manager:
		_battle_manager.set_queued_action(_my_index, _battle_manager.CombatAction.ATTACK)
	_update_visual_state()

func _on_unit_stats_updated(index: int, unit_name: String, cur_hp: int, max_hp: int, cur_mp: int, max_mp: int, cur_limit: int, max_limit: int) -> void:
	if index != _my_index:
		return

	# We want to preserve any existing action text, so we only update the base name.
	var current_text = name_label.text
	var action_text = ""
	if " - " in current_text:
		action_text = " - " + current_text.split(" - ")[1]

	name_label.text = unit_name + action_text

	hp_label.text = "%d / %d" % [cur_hp, max_hp]
	hp_bar.max_value = max_hp
	hp_bar.value = cur_hp

	mp_label.text = "%d / %d" % [cur_mp, max_mp]
	mp_bar.max_value = max_mp
	mp_bar.value = cur_mp

	limit_bar.max_value = max_limit
	limit_bar.value = cur_limit

func update_action_visuals() -> void:
	if not _battle_manager:
		return
	if _my_index < 0 or _my_index >= _battle_manager.party_data.size():
		return
	var unit_data: Dictionary = _battle_manager.party_data[_my_index]
	_current_queued_action = unit_data.get("queued_action", _battle_manager.CombatAction.ATTACK)
	_update_visual_state()

func _update_visual_state() -> void:
	if not _battle_manager:
		return

	if _has_acted:
		modulate = Color(0.5, 0.5, 0.5, 1.0)
		return

	var base_name = name_label.text.split(" - ")[0]
	var unit_data: Dictionary = _battle_manager.party_data[_my_index] if _my_index >= 0 and _my_index < _battle_manager.party_data.size() else {}
	var action_name = unit_data.get("queued_action_name", "")

	if _current_queued_action == _battle_manager.CombatAction.ATTACK:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		name_label.text = base_name
	elif _current_queued_action == _battle_manager.CombatAction.DEFEND:
		modulate = Color(0.5, 0.8, 1.0, 1.0) # Blue tint for GUARD
		name_label.text = base_name + " - GUARD"
	elif _current_queued_action == _battle_manager.CombatAction.SKILL:
		modulate = Color(1.0, 0.6, 0.6, 1.0) # Red tint for SKILL
		name_label.text = base_name + " - " + action_name
	elif _current_queued_action == _battle_manager.CombatAction.ITEM:
		modulate = Color(0.6, 1.0, 0.6, 1.0) # Green tint for ITEM
		name_label.text = base_name + " - " + action_name
