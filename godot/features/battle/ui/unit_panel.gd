extends TextureRect

class_name UnitPanel

signal open_skill_menu(unit_index: int)
signal open_item_menu(unit_index: int)
signal panel_tapped(unit_index: int)
signal info_tapped(unit_index: int)

@onready var unit_thum: TextureRect = $UnitThum
@onready var unit_name: Label = $UnitName
@onready var hp_gage: TextureRect = $HPGage
@onready var hp_now: Label = $HPNow
@onready var hp_slash: TextureRect = $HPSlash
@onready var hp_max: Label = $HPMax
@onready var mp_gage: TextureRect = $MPGage
@onready var mp_now: Label = $MPNow
@onready var limit_gage: TextureRect = $LimitGage
@onready var barrier_gage: TextureRect = $BarrierGage
@onready var cmd_baloon: TextureRect = $CmdBaloon
@onready var hp_bar: Sprite2D = $BattleUnitHpBar1
@onready var mp_bar: Sprite2D = $BattleUnitMpBar
@onready var limit_bar: Sprite2D = $BattleUnitLimitBar
@onready var barrier_bar: Sprite2D = $BattleUnitBarrierBar

var _my_index: int = -1
var _is_dragging: bool = false
var _drag_start_position: Vector2 = Vector2.ZERO
var _current_queued_action: int = 0
var _current_queued_action_id: String = ""
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

	cmd_baloon.mouse_filter = Control.MOUSE_FILTER_STOP
	cmd_baloon.gui_input.connect(_on_cmd_baloon_input)

func _on_cmd_baloon_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		info_tapped.emit(_my_index)
	elif event is InputEventScreenTouch and not event.pressed:
		info_tapped.emit(_my_index)

func _gui_input(event: InputEvent) -> void:
	if not _battle_manager:
		return

	var has_acted: bool = _my_index in _battle_manager.player_units_acted_this_turn

	if has_acted and not is_ally_targeting_mode:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = false
			_drag_start_position = event.position
		else:
			if not _is_dragging and _is_within_tap_distance(event.position):
				panel_tapped.emit(_my_index)
			_is_dragging = false

	elif event is InputEventScreenTouch:
		if event.pressed:
			_is_dragging = false
			_drag_start_position = event.position
		else:
			if not _is_dragging and _is_within_tap_distance(event.position):
				panel_tapped.emit(_my_index)
			_is_dragging = false

	elif (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) or event is InputEventScreenDrag:
		if has_acted:
			return

		var diff: Vector2 = event.position - _drag_start_position
		if not _is_dragging:
			if abs(diff.y) > 20 and abs(diff.y) > abs(diff.x):
				_is_dragging = true
				if diff.y > 20:
					if _current_queued_action != _battle_manager.CombatAction.DEFEND:
						_current_queued_action = _battle_manager.CombatAction.DEFEND
						_battle_manager.set_queued_action(_my_index, _battle_manager.CombatAction.DEFEND)
						_update_command_icon("defense")
						_update_visual_state()
				elif diff.y < -20:
					if _current_queued_action != _battle_manager.CombatAction.ATTACK:
						_current_queued_action = _battle_manager.CombatAction.ATTACK
						_battle_manager.set_queued_action(_my_index, _battle_manager.CombatAction.ATTACK)
						_update_command_icon("attack")
						_update_visual_state()
			elif abs(diff.x) > 20 and abs(diff.x) > abs(diff.y):
				_is_dragging = true
				if diff.x > 20:
					open_skill_menu.emit(_my_index)
				elif diff.x < -20:
					open_item_menu.emit(_my_index)

func setup(unit_index: int) -> void:
	_my_index = unit_index
	_update_visual_state()
	if _battle_manager:
		_battle_manager.request_unit_stats(_my_index)

const _TAP_MAX_DISTANCE: float = 8.0

func _is_within_tap_distance(release_position: Vector2) -> bool:
	return (release_position - _drag_start_position).length() <= _TAP_MAX_DISTANCE

func _on_unit_acted(index: int) -> void:
	if index == _my_index:
		_has_acted = true
		modulate = Color(0.5, 0.5, 0.5, 1.0)

func _on_turn_changed(_new_turn: int) -> void:
	_has_acted = false
	_current_queued_action = 0
	_current_queued_action_id = ""
	if _battle_manager:
		_battle_manager.set_queued_action(_my_index, _battle_manager.CombatAction.ATTACK)
	_update_command_icon("attack")
	_update_visual_state()

func _on_unit_stats_updated(index: int, _unit_name: String, cur_hp: int, max_hp: int, cur_mp: int, max_mp: int, cur_limit: int, max_limit: int) -> void:
	if index != _my_index:
		return
	_update_stats_display(_unit_name, cur_hp, max_hp, cur_mp)
	set_hp_display(cur_hp, max_hp)
	set_mp_display(cur_mp, max_mp)
	set_limit_gauge(cur_limit, max_limit)

func update_action_visuals() -> void:
	if not _battle_manager:
		return
	if _my_index < 0 or _my_index >= _battle_manager.party_data.size():
		return
	var unit_data: Dictionary = _battle_manager.party_data[_my_index]
	_current_queued_action = unit_data.get("queued_action", _battle_manager.CombatAction.ATTACK)
	_current_queued_action_id = str(unit_data.get("queued_action_id", ""))
	_update_visual_state()

func _update_visual_state() -> void:
	if not _battle_manager:
		return

	if _has_acted:
		modulate = Color(0.5, 0.5, 0.5, 1.0)
		return
	modulate = Color(1.0, 1.0, 1.0, 1.0)

	if _current_queued_action == _battle_manager.CombatAction.ATTACK:
		#modulate = Color(1.0, 1.0, 1.0, 1.0)
		_update_command_icon("attack")
	elif _current_queued_action == _battle_manager.CombatAction.DEFEND:
		#modulate = Color(0.5, 0.8, 1.0, 1.0)
		_update_command_icon("defense")
	elif _current_queued_action == _battle_manager.CombatAction.SKILL:
		#modulate = Color(1.0, 0.6, 0.6, 1.0)
		_update_command_icon(_resolve_skill_command_icon())
	elif _current_queued_action == _battle_manager.CombatAction.ITEM:
		#modulate = Color(0.6, 1.0, 0.6, 1.0)
		_update_command_icon("item")

func _resolve_skill_command_icon() -> String:
	if _current_queued_action_id == "":
		return "magic"
	if StaticData.game_data_skills_magic.has(_current_queued_action_id):
		return "magic"
	if StaticData.game_data_skills_ability.has(_current_queued_action_id):
		return "special"
	return "magic"

func set_hp_display(current_hp: int, max_hp: int) -> void:
	if max_hp <= 0:
		return
	var fill_ratio: float = clampf(float(current_hp) / float(max_hp), 0.0, 1.0)
	#hp_gage.scale.x = fill_ratio
	hp_bar.scale.x = fill_ratio

func set_mp_display(current_mp: int, max_mp: int) -> void:
	if max_mp <= 0:
		return
	var fill_ratio: float = clampf(float(current_mp) / float(max_mp), 0.0, 1.0)
	#mp_gage.scale.x = fill_ratio
	mp_bar.scale.x = fill_ratio

func set_limit_gauge(current_limit: int, max_limit: int) -> void:
	if max_limit <= 0:
		return
	var fill_ratio: float = clampf(float(current_limit) / float(max_limit), 0.0, 1.0)
	limit_bar.scale.x = fill_ratio

func _update_command_icon(command: String) -> void:
	var icon_path: String = "res://assets/ui/battle/battle_com_icon_%s.tres" % command
	if ResourceLoader.exists(icon_path):
		cmd_baloon.texture = ResourceLoader.load(icon_path)

func _update_stats_display(unit_name_str: String, cur_hp: int, max_hp: int, cur_mp: int) -> void:
	unit_name.text = unit_name_str
	hp_now.text = str(cur_hp)
	hp_max.text = str(max_hp)
	mp_now.text = str(cur_mp)
	
	# Load and display unit thumbnail
	if _battle_manager and _my_index >= 0 and _my_index < _battle_manager.party_data.size():
		var unit_data: Dictionary = _battle_manager.party_data[_my_index]
		var unit_static_id: String = UnitService.get_entry_id(unit_data)
		if unit_static_id != "":
			var texture_path: String = "res://assets/unit_icons/unit_icon_%s.png" % unit_static_id
			if ResourceLoader.exists(texture_path):
				unit_thum.texture = ResourceLoader.load(texture_path)

func set_barrier_gauge(current_barrier: float) -> void:
	var is_active: bool = current_barrier > 0.0
	barrier_gage.visible = is_active
	barrier_bar.visible = is_active
	if is_active:
		barrier_gage.modulate.a = clampf(current_barrier, 0.0, 1.0)
		barrier_bar.scale.x = clampf(current_barrier, 0.0, 1.0)
