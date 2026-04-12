extends PanelContainer

@onready var name_label: Label = %NameLabel
@onready var hp_label: Label = %HPLabel
@onready var mp_label: Label = %MPLabel
@onready var hp_bar: ProgressBar = %HPBar
@onready var mp_bar: ProgressBar = %MPBar
@onready var limit_bar: ProgressBar = %LimitBar

var _my_index: int = -1
var _is_dragging: bool = false
var _drag_start_position: Vector2 = Vector2.ZERO
var _current_queued_action: int = 0 # 0 is ATTACK
var _battle_manager: Node = null

func _ready() -> void:
	_battle_manager = get_tree().root.find_child("BattleManager", true, false)
	if _battle_manager:
		if not _battle_manager.unit_stats_updated.is_connected(_on_unit_stats_updated):
			_battle_manager.unit_stats_updated.connect(_on_unit_stats_updated)
		if not _battle_manager.unit_acted.is_connected(_on_unit_acted):
			_battle_manager.unit_acted.connect(_on_unit_acted)
		if not _battle_manager.turn_changed.is_connected(_on_turn_changed):
			_battle_manager.turn_changed.connect(_on_turn_changed)

func _gui_input(event: InputEvent) -> void:
	if not _battle_manager:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = false
			_drag_start_position = event.position
		else:
			if not _is_dragging:
				_battle_manager.execute_queued_action(_my_index)
			_is_dragging = false

	elif event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging = false
			_drag_start_position = event.position
		else:
			if not _is_dragging:
				_battle_manager.execute_queued_action(_my_index)
			_is_dragging = false

	elif (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) or event is InputEventScreenDrag:
		var diff = event.position - _drag_start_position
		if abs(diff.y) > 20 and abs(diff.y) > abs(diff.x):
			_is_dragging = true
			if diff.y > 20: # Swipe down
				if _current_queued_action != _battle_manager.CombatAction.DEFEND:
					_current_queued_action = _battle_manager.CombatAction.DEFEND
					_battle_manager.set_queued_action(_my_index, _battle_manager.CombatAction.DEFEND)
					modulate = Color(0.5, 0.8, 1.0, 1.0) # Blue tint for GUARD
			elif diff.y < -20: # Swipe up
				if _current_queued_action != _battle_manager.CombatAction.ATTACK:
					_current_queued_action = _battle_manager.CombatAction.ATTACK
					_battle_manager.set_queued_action(_my_index, _battle_manager.CombatAction.ATTACK)
					modulate = Color(1.0, 1.0, 1.0, 1.0) # Normal tint for ATTACK

func setup(unit_index: int) -> void:
	_my_index = unit_index
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	if _battle_manager:
		_battle_manager.request_unit_stats(_my_index)

func _on_unit_acted(index: int) -> void:
	if index == _my_index:
		modulate = Color(0.5, 0.5, 0.5, 1.0)

func _on_turn_changed(_new_turn: int) -> void:
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	_current_queued_action = 0 # ATTACK is 0, handled safely via variable initialization
	if _battle_manager:
		_battle_manager.set_queued_action(_my_index, _battle_manager.CombatAction.ATTACK)

func _on_unit_stats_updated(index: int, unit_name: String, cur_hp: int, max_hp: int, cur_mp: int, max_mp: int, cur_limit: int, max_limit: int) -> void:
	if index != _my_index:
		return

	name_label.text = unit_name

	hp_label.text = "%d / %d" % [cur_hp, max_hp]
	hp_bar.max_value = max_hp
	hp_bar.value = cur_hp

	mp_label.text = "%d / %d" % [cur_mp, max_mp]
	mp_bar.max_value = max_mp
	mp_bar.value = cur_mp

	limit_bar.max_value = max_limit
	limit_bar.value = cur_limit
